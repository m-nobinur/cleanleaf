import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/licenses/third_party_licenses.dart';

void main() {
  registerThirdPartyLicenses();
  runApp(const ProviderScope(child: CleanleafApp()));
}
