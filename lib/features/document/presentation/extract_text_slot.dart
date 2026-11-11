import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The document view's "Extract text" action; null hides it. T-031 overrides
/// this once the OCR engine reports it is available.
final extractTextActionProvider =
    Provider<Future<void> Function(BuildContext context, String documentId)?>(
      (ref) => null,
    );
