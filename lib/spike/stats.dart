import 'dart:io';

String pct(List<num> xs) {
  if (xs.isEmpty) return 'n=0';
  final s = [...xs]..sort();
  num at(double p) => s[((s.length - 1) * p).round()];
  String f(num v) => v.toStringAsFixed(2);
  return 'n=${s.length} p50=${f(at(.5))} p95=${f(at(.95))} max=${f(s.last)}';
}

/// CPU ticks (utime+stime) per thread name, summed over threads sharing a name.
Map<String, int> threadTicks() {
  final out = <String, int>{};
  try {
    for (final task in Directory('/proc/self/task').listSync()) {
      try {
        final stat = File('${task.path}/stat').readAsStringSync();
        final open = stat.indexOf('(');
        final close = stat.lastIndexOf(')');
        final name = stat.substring(open + 1, close);
        final fields = stat.substring(close + 2).split(' ');
        // Fields after ')' start at index 3 of stat(5); utime=14, stime=15.
        final ticks = int.parse(fields[11]) + int.parse(fields[12]);
        out[name] = (out[name] ?? 0) + ticks;
      } catch (_) {}
    }
  } catch (e) {
    out['error:$e'] = 0;
  }
  return out;
}

/// CPU ms per second, per thread group, between two [threadTicks] snapshots.
/// Assumes USER_HZ = 100 (Android default).
String cpuDelta(Map<String, int> a, Map<String, int> b, double seconds) {
  final d = <String, int>{
    for (final e in b.entries) e.key: e.value - (a[e.key] ?? 0),
  };
  final total = d.values.fold<int>(0, (s, v) => s + v);
  final top = d.entries.where((e) => e.value > 0).toList()
    ..sort((x, y) => y.value.compareTo(x.value));
  String rate(int ticks) => (ticks * 10 / seconds).toStringAsFixed(0);
  final parts = top.take(8).map((e) => '${e.key}=${rate(e.value)}');
  return 'total=${rate(total)}ms/s ${parts.join(' ')}';
}
