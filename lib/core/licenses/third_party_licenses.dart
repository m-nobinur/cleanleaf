import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// One bundled third-party component and the asset files that make up its notice.
class ThirdPartyNotice {
  const ThirdPartyNotice({required this.packages, required this.assets});

  final List<String> packages;
  final List<String> assets;
}

/// Add a notice here: drop its text in assets/licenses/ and list it (checklist in T-014).
/// OpenCV's SDK libraries are listed even where the linker may drop them, to keep the set complete.
const thirdPartyNotices = <ThirdPartyNotice>[
  ThirdPartyNotice(
    packages: ['OpenCV 4.13.0'],
    assets: ['assets/licenses/OpenCV-COPYRIGHT.txt', _apache],
  ),
  ThirdPartyNotice(
    packages: ['libjpeg-turbo'],
    assets: [
      'assets/licenses/libjpeg-turbo-LICENSE.md',
      'assets/licenses/libjpeg-turbo-README.ijg',
    ],
  ),
  ThirdPartyNotice(
    packages: ['libpng'],
    assets: ['assets/licenses/libpng-LICENSE'],
  ),
  ThirdPartyNotice(
    packages: ['libtiff'],
    assets: ['assets/licenses/libtiff-LICENSE.md'],
  ),
  ThirdPartyNotice(
    packages: ['libwebp'],
    assets: ['assets/licenses/libwebp-COPYING.txt'],
  ),
  ThirdPartyNotice(
    packages: ['OpenJPEG'],
    assets: ['assets/licenses/libopenjp2-LICENSE'],
  ),
  ThirdPartyNotice(
    packages: ['OpenEXR'],
    assets: ['assets/licenses/openexr-LICENSE'],
  ),
  ThirdPartyNotice(
    packages: ['oneTBB'],
    assets: ['assets/licenses/tbb-LICENSE.txt'],
  ),
  ThirdPartyNotice(
    packages: ['Intel ITT notify (BSD-3-Clause)'],
    assets: ['assets/licenses/ittnotify-BSD-3-Clause.txt'],
  ),
  ThirdPartyNotice(
    packages: ['cpufeatures (Android)'],
    assets: ['assets/licenses/cpufeatures-LICENSE', _apache],
  ),
  ThirdPartyNotice(
    packages: ['KleidiCV'],
    assets: ['assets/licenses/KleidiCV-NOTICE.txt', _apache],
  ),
  ThirdPartyNotice(
    packages: ['LiteRT 1.4.2'],
    assets: ['assets/licenses/LiteRT-NOTICE.txt', _apache],
  ),
  ThirdPartyNotice(
    packages: ['DocAligner model weights (modified)'],
    assets: ['assets/licenses/DocAligner-NOTICE.txt', _apache],
  ),
  ThirdPartyNotice(
    packages: ['AndroidX CameraX and Kotlin coroutines'],
    assets: ['assets/licenses/AndroidX-NOTICE.txt', _apache],
  ),
  ThirdPartyNotice(
    packages: ['JetBrains Mono'],
    assets: ['assets/licenses/JetBrainsMono-OFL.txt'],
  ),
];

const _apache = 'assets/licenses/Apache-2.0.txt';

void registerThirdPartyLicenses() => LicenseRegistry.addLicense(_notices);

Stream<LicenseEntry> _notices() async* {
  for (final notice in thirdPartyNotices) {
    final texts = await Future.wait(notice.assets.map(rootBundle.loadString));
    yield LicenseEntryWithLineBreaks(notice.packages, texts.join('\n\n'));
  }
}
