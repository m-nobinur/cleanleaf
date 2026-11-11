import '../../enhance/domain/page_renderer.dart';
import '../../library/domain/document_page.dart';
import 'scan_mode.dart';

extension ScanModePresets on ScanMode {
  // Enhanced colour flattens a card's printed background, and B&W thresholding
  // can drop faint thermal print, so those modes start gentler.
  PageFilter get defaultFilter => switch (this) {
    ScanMode.idCard => PageFilter.original,
    ScanMode.receipt => PageFilter.grayscale,
    ScanMode.document || ScanMode.book => PageFilter.enhancedColor,
  };

  Map<String, double> get pageParams => switch (this) {
    ScanMode.idCard => {aspectRatioParam: PageAspect.id1.ratio},
    _ => const {},
  };
}
