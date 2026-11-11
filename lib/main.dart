import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/licenses/third_party_licenses.dart';
import 'core/platform/clvision.dart';

void main() {
  registerThirdPartyLicenses();
  runApp(const ProviderScope(child: CleanleafApp()));
  // Live and still detection return no page until the model is in.
  unawaited(loadDocAligner());
}
