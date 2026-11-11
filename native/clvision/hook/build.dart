import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:logging/logging.dart';
import 'package:native_toolchain_cmake/native_toolchain_cmake.dart';

// Links a prebuilt static OpenCV per target OS, set in the app pubspec under
// hooks.user_defines.clvision.opencv_<os> (OpenCVConfig.cmake directory).
void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) return;
    final os = input.config.code.targetOS;
    final key = 'opencv_${os.name.toLowerCase()}';
    final raw = input.userDefines[key];
    if (raw is! String) {
      throw ArgumentError('hooks.user_defines.clvision.$key is not set');
    }
    final opencvDir = raw.replaceFirst('~', Platform.environment['HOME']!);
    if (!Directory(opencvDir).existsSync()) {
      throw ArgumentError('$key does not exist: $opencvDir');
    }
    final src = input.packageRoot.resolve('src/');
    final logger = Logger('clvision')
      ..onRecord.listen((r) => stderr.writeln(r.message));
    await CMakeBuilder.create(
      name: input.packageName,
      sourceDir: src,
      targets: ['install'],
      defines: {
        'OpenCV_DIR': opencvDir,
        'CMAKE_INSTALL_PREFIX': input.outputDirectory
            .resolve('install/')
            .toFilePath(),
      },
    ).run(input: input, output: output, logger: logger);
    await output.findAndAddCodeAssets(
      input,
      outDir: input.outputDirectory.resolve('install/'),
      names: {'clvision': 'clvision.dart'},
    );
    output.dependencies.addAll([
      for (final f in Directory.fromUri(src).listSync()) f.uri,
    ]);
  });
}
