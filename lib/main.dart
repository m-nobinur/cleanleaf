import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'app.dart';
import 'core/licenses/third_party_licenses.dart';
import 'core/metrics/ab_session.dart';

void main() {
  registerThirdPartyLicenses();
  if (AbSession.enabled) {
    final name = '${DateTime.now().millisecondsSinceEpoch}';
    Future<Directory>? dir;
    AbSession.current = AbSession(
      () => dir ??= getExternalStorageDirectory().then(
        (root) => Directory(p.join(root!.path, 'ab', name)),
      ),
    );
    debugPrint('CLMETRIC ab_session $name');
    AbSession.current!.event('app_start', {});
  }
  runApp(const ProviderScope(child: CleanleafApp()));
}
