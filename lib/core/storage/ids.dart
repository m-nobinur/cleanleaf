import 'dart:math';

final _random = Random.secure();

/// 128-bit random hex id; ids are created before insert so files can be written first.
String newId() => List.generate(
  16,
  (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
).join();
