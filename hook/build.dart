import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:crypto/crypto.dart';
import 'package:hooks/hooks.dart';
import 'package:logging/logging.dart';
import 'package:native_toolchain_cmake/native_toolchain_cmake.dart';

// Builds native/clvision into libclvision against static OpenCV 4.13.0
// (decisions.md D-10), the LiteRT C API (D-11) and zxing-cpp (D-47). Archives are SHA-256
// verified and cached per user in ~/.cache/cleanleaf so every checkout and
// worktree shares one copy.

const _openCvVersion = '4.13.0';

const _androidSdk = (
  url:
      'https://github.com/opencv/opencv/releases/download/$_openCvVersion/opencv-$_openCvVersion-android-sdk.zip',
  file: 'opencv-$_openCvVersion-android-sdk.zip',
  sha256: 'edfda20fdf65d0bd45391d168ec5261dd30b600b00279c4d910d7f1c3e020f0f',
);

const _sourceTarball = (
  url:
      'https://github.com/opencv/opencv/archive/refs/tags/$_openCvVersion.tar.gz',
  file: 'opencv-$_openCvVersion.tar.gz',
  sha256: '1d40ca017ea51c533cf9fd5cbde5b5fe7ae248291ddf2af99d4c17cf8e13017d',
);

// C API headers and the per-ABI libtensorflowlite_jni.so (which exports the C API).
const _litertAar = (
  url: 'https://dl.google.com/dl/android/maven2/com/google/ai/edge/litert/litert/1.4.2/litert-1.4.2.aar',
  file: 'litert-1.4.2.aar',
  sha256: '9b02cdf9db0a698b341b59e75c54ab8221d6304577cc43830d01024caf1fca74',
);

// Host-only LiteRT for `flutter test`: TensorFlow Lite's C library built once
// from this tarball; its C API matches the one the AAR's headers declare.
const _tensorFlowTarball = (
  url: 'https://github.com/tensorflow/tensorflow/archive/refs/tags/v2.21.0.tar.gz',
  file: 'tensorflow-2.21.0.tar.gz',
  sha256: 'ef3568bb4865d6c1b2564fb5689c19b6b9a5311572cd1f2ff9198636a8520921',
);

// QR and barcode readers (decisions.md D-47), compiled into clvision.
const _zxingVersion = '3.1.1';
const _zxingTarball = (
  url:
      'https://github.com/zxing-cpp/zxing-cpp/releases/download/v$_zxingVersion/zxing-cpp-$_zxingVersion.tar.gz',
  file: 'zxing-cpp-$_zxingVersion.tar.gz',
  sha256: 'c3c02c29c0b519de7bd4e25b376e606e87f0761befd1282815642a2246613d14',
);

// Host build for `flutter test`: only the modules and codecs clvision uses.
const _hostOpenCvDefines = {
  'CMAKE_POLICY_VERSION_MINIMUM': '3.5',
  'BUILD_SHARED_LIBS': 'OFF',
  'BUILD_LIST': 'core,imgproc,imgcodecs',
  'BUILD_ZLIB': 'ON',
  'BUILD_PNG': 'ON',
  'BUILD_JPEG': 'ON',
  'WITH_TIFF': 'OFF',
  'WITH_WEBP': 'OFF',
  'WITH_OPENJPEG': 'OFF',
  'WITH_JASPER': 'OFF',
  'WITH_OPENEXR': 'OFF',
  'WITH_AVIF': 'OFF',
  'WITH_IMGCODEC_HDR': 'OFF',
  'WITH_IMGCODEC_SUNRASTER': 'OFF',
  'WITH_IMGCODEC_PXM': 'OFF',
  'WITH_IMGCODEC_PFM': 'OFF',
  'WITH_OPENCL': 'OFF',
  'WITH_IPP': 'OFF',
  'WITH_ITT': 'OFF',
  'WITH_PROTOBUF': 'OFF',
  'WITH_ADE': 'OFF',
  'WITH_EIGEN': 'OFF',
  'WITH_LAPACK': 'OFF',
  'WITH_FFMPEG': 'OFF',
  'BUILD_opencv_apps': 'OFF',
  'BUILD_JAVA': 'OFF',
  'BUILD_opencv_python3': 'OFF',
  'BUILD_TESTS': 'OFF',
  'BUILD_PERF_TESTS': 'OFF',
  'BUILD_EXAMPLES': 'OFF',
  'BUILD_DOCS': 'OFF',
};

void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) return;
    final logger = _logger('clvision', Level.INFO);
    final cmakeLogger = _logger('cmake', Level.WARNING);
    final code = input.config.code;
    final cache = Directory('${Platform.environment['HOME']}/.cache/cleanleaf');
    final litert = await _litertAarDir(cache, logger);
    final zxing = await _zxingSource(cache, logger);
    final (:openCv, :litertLibrary) = switch (code.targetOS) {
      OS.android => (
        openCv: await _androidOpenCv(cache, logger),
        litertLibrary:
            '$litert/jni/${_androidAbi(code.targetArchitecture)}/libtensorflowlite_jni.so',
      ),
      OS.macOS => (
        openCv: await _hostOpenCv(cache, code, logger),
        litertLibrary: await _hostLitert(cache, code, logger),
      ),
      final os => throw UnsupportedError('clvision does not support $os'),
    };

    final root = input.packageRoot.resolve('native/clvision/');
    final install = input.outputDirectory.resolve('install/');
    await CMakeBuilder.create(
      name: 'clvision',
      sourceDir: root,
      targets: ['install'],
      defines: {
        'OpenCV_DIR': openCv,
        'LITERT_INCLUDE_DIR': '$litert/headers',
        'LITERT_LIBRARY': litertLibrary,
        'ZXING_SOURCE_DIR': zxing,
        'CMAKE_INSTALL_PREFIX': install.toFilePath(),
      },
    ).run(input: input, output: output, logger: cmakeLogger);
    await output.findAndAddCodeAssets(
      input,
      outDir: install,
      names: {'clvision': 'core/platform/clvision.dart'},
    );
    // Host tests resolve LiteRT through clvision's rpath; Android bundles it.
    // Bundle a copy: Flutter moves asset files, which would empty the cache.
    if (code.targetOS == OS.android) {
      final bundled = File.fromUri(
        input.outputDirectory.resolve('litert/libtensorflowlite_jni.so'),
      );
      bundled.parent.createSync(recursive: true);
      File(litertLibrary).copySync(bundled.path);
      output.assets.code.add(
        CodeAsset(
          package: input.packageName,
          name: 'core/platform/litert.dart',
          linkMode: DynamicLoadingBundled(),
          file: bundled.uri,
        ),
      );
    }
    // Directories catch added files, the files catch edits.
    for (final dir in [
      'src/',
      'include/',
      'third_party/litert/tflite/delegates/xnnpack/',
    ]) {
      final uri = root.resolve(dir);
      output.dependencies
        ..add(uri)
        ..addAll(Directory.fromUri(uri).listSync().map((f) => f.uri));
    }
    output.dependencies.add(root.resolve('CMakeLists.txt'));
  });
}

Future<String> _androidOpenCv(Directory cache, Logger logger) async {
  final dir = Directory('${cache.path}/opencv-$_openCvVersion-android');
  if (!dir.existsSync()) {
    final zip = await _download(cache, _androidSdk, logger);
    await _extractInto(dir, (tmp) async {
      await _run('unzip', [
        '-q',
        zip.path,
        'OpenCV-android-sdk/sdk/native/*',
        '-d',
        tmp.path,
      ]);
    });
  }
  return '${dir.path}/OpenCV-android-sdk/sdk/native/jni';
}

Future<String> _litertAarDir(Directory cache, Logger logger) async {
  final dir = Directory('${cache.path}/litert-1.4.2-android');
  if (!dir.existsSync()) {
    final aar = await _download(cache, _litertAar, logger);
    await _extractInto(dir, (tmp) async {
      await _run('unzip', [
        '-q',
        aar.path,
        'jni/*',
        'headers/*',
        '-d',
        tmp.path,
      ]);
    });
  }
  return dir.path;
}

Future<String> _zxingSource(Directory cache, Logger logger) async {
  final dir = Directory('${cache.path}/zxing-cpp-$_zxingVersion');
  if (!dir.existsSync()) {
    final tarball = await _download(cache, _zxingTarball, logger);
    await _extractInto(dir, (tmp) async {
      await _run('tar', ['xzf', tarball.path, '-C', tmp.path]);
    });
  }
  return '${dir.path}/zxing-cpp-$_zxingVersion';
}

String _androidAbi(Architecture arch) => switch (arch) {
  Architecture.arm64 => 'arm64-v8a',
  Architecture.arm => 'armeabi-v7a',
  Architecture.x64 => 'x86_64',
  Architecture.ia32 => 'x86',
  _ => throw UnsupportedError('No LiteRT library for Android $arch'),
};

Future<String> _hostOpenCv(
  Directory cache,
  CodeConfig code,
  Logger logger,
) async {
  final arch = code.targetArchitecture.name;
  final dir = Directory('${cache.path}/opencv-$_openCvVersion-macos-$arch');
  if (!dir.existsSync()) {
    final tarball = await _download(cache, _sourceTarball, logger);
    await _extractInto(dir, (tmp) async {
      final work = Directory('${tmp.path}.work')..createSync();
      try {
        await _run('tar', ['xzf', tarball.path, '-C', work.path]);
        logger.info('Building static OpenCV $_openCvVersion for macOS $arch');
        await CMakeBuilder.create(
          name: 'opencv',
          sourceDir: Uri.directory('${work.path}/opencv-$_openCvVersion'),
          outDir: Uri.directory('${work.path}/build'),
          generator: Generator.make,
          targets: ['install'],
          parallelUseAllProcessors: true,
          defines: {..._hostOpenCvDefines, 'CMAKE_INSTALL_PREFIX': tmp.path},
        ).runStandalone(
          outputDirectory: Uri.directory('${work.path}/build'),
          targetOS: OS.macOS,
          targetArchitecture: code.targetArchitecture,
          macOS: code.macOS,
          logger: _logger('cmake', Level.WARNING),
        );
      } finally {
        work.deleteSync(recursive: true);
      }
    });
  }
  return '${dir.path}/lib/cmake/opencv4';
}

Logger _logger(String name, Level level) => Logger.detached(name)
  ..level = level
  ..onRecord.listen((r) => stderr.writeln(r.message));

Future<String> _hostLitert(
  Directory cache,
  CodeConfig code,
  Logger logger,
) async {
  final arch = code.targetArchitecture.name;
  final dir = Directory('${cache.path}/litert-tf2.21.0-macos-$arch');
  if (!dir.existsSync()) {
    final tarball = await _download(cache, _tensorFlowTarball, logger);
    await _extractInto(dir, (tmp) async {
      final work = Directory('${tmp.path}.work')..createSync();
      try {
        await _run('tar', ['xzf', tarball.path, '-C', work.path]);
        logger.info('Building LiteRT C for macOS $arch (one-time, ~10 min)');
        final build = '${work.path}/build';
        final source = '${work.path}/tensorflow-2.21.0';
        // Plain CMake: native_toolchain_cmake's Apple toolchain file marks this
        // host build as cross-compiling, which makes TFLite demand a host flatc.
        // Without TENSORFLOW_SOURCE_DIR, TFLite fetches a mismatched TF checkout.
        await _run('cmake', [
          '-S',
          '$source/tensorflow/lite/c',
          '-B',
          build,
          '-G',
          'Unix Makefiles',
          '-DCMAKE_BUILD_TYPE=Release',
          '-DCMAKE_OSX_ARCHITECTURES=${arch == 'x64' ? 'x86_64' : arch}',
          '-DCMAKE_OSX_DEPLOYMENT_TARGET=${code.macOS.targetVersion}',
          '-DCMAKE_POLICY_VERSION_MINIMUM=3.5',
          '-DTFLITE_ENABLE_XNNPACK=ON',
          '-DTENSORFLOW_SOURCE_DIR=$source',
        ]);
        await _run('cmake', [
          '--build',
          build,
          '--target',
          'tensorflowlite_c',
          '-j',
          '${Platform.numberOfProcessors}',
        ]);
        Directory('${tmp.path}/lib').createSync();
        File('$build/libtensorflowlite_c.dylib')
            .copySync('${tmp.path}/lib/libtensorflowlite_c.dylib');
      } finally {
        work.deleteSync(recursive: true);
      }
    });
  }
  return '${dir.path}/lib/libtensorflowlite_c.dylib';
}

typedef _Archive = ({String url, String file, String sha256});

// Downloads to a temp name and renames only after the hash matches, so a
// concurrent or interrupted run never leaves an unverified archive in place.
Future<File> _download(Directory cache, _Archive archive, Logger logger) async {
  final file = File('${cache.path}/dl/${archive.file}');
  if (file.existsSync()) {
    await _verify(file, archive.sha256);
    return file;
  }
  logger.info('Downloading ${archive.url}');
  file.parent.createSync(recursive: true);
  final part = File('${file.path}.part-$pid');
  final client = HttpClient()..findProxy = HttpClient.findProxyFromEnvironment;
  try {
    final response = await (await client.getUrl(Uri.parse(archive.url)))
        .close();
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException(
        'HTTP ${response.statusCode}',
        uri: Uri.parse(archive.url),
      );
    }
    await response.pipe(part.openWrite());
    await _verify(part, archive.sha256);
    part.renameSync(file.path);
  } finally {
    client.close();
    if (part.existsSync()) part.deleteSync();
  }
  return file;
}

Future<void> _verify(File file, String expected) async {
  final actual = (await sha256.bind(file.openRead()).first).toString();
  if (actual != expected) {
    throw StateError(
      'SHA-256 mismatch for ${file.path}: expected $expected, got $actual',
    );
  }
}

// Fills a temp directory and renames it into place; a racing run that got
// there first wins and this run's copy is discarded.
Future<void> _extractInto(
  Directory target,
  Future<void> Function(Directory tmp) fill,
) async {
  final tmp = Directory('${target.path}.tmp-$pid');
  if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  tmp.createSync(recursive: true);
  try {
    await fill(tmp);
    try {
      tmp.renameSync(target.path);
    } on FileSystemException {
      if (!target.existsSync()) rethrow;
    }
  } finally {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  }
}

Future<void> _run(String executable, List<String> args) async {
  final result = await Process.run(executable, args);
  if (result.exitCode != 0) {
    throw ProcessException(
      executable,
      args,
      '${result.stdout}\n${result.stderr}',
      result.exitCode,
    );
  }
}
