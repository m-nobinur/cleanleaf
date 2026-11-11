import 'package:cleanleaf/core/platform/clvision.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('clvision links OpenCV 4.13.0 on the host', () {
    expect(openCvVersion(), '4.13.0');
  });
}
