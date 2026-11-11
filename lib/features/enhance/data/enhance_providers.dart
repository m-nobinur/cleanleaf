import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/page_renderer.dart';
import 'native_page_renderer.dart';

final pageRendererProvider = Provider<PageRenderer>(
  (ref) => const NativePageRenderer(),
);
