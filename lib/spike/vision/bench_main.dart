import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'pipeline_a.dart';
import 'pipeline_b.dart';
import 'spike_types.dart';

// T-003 probe entry (`flutter build apk -t lib/spike/vision/bench_main.dart`).
// Kotlin (VisionBench) drives the run; Dart answers on the "clbench" channel and
// does the A and B-FFI work in one long-lived worker isolate.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const Directionality(
      textDirection: TextDirection.ltr,
      child: Center(child: Text('T-003 vision bench')),
    ),
  );
  final worker = await _Worker.spawn();
  const channel = MethodChannel('clbench');
  channel.setMethodCallHandler((call) async {
    final args = call.arguments;
    final reply = switch (call.method) {
      'corners' => null,
      'setup' => await worker.request(['setup', args['jpeg'], args['dir']]),
      'info' => await worker.request(['info']),
      'frame' => await worker.request([
        'frame',
        args['path'],
        TransferableTypedData.fromList([args['plane'] as Uint8List]),
        args['w'],
        args['h'],
        args['stride'],
      ]),
      'still' => await worker.request([
        'still',
        args['path'],
        args['corners'],
        args['outW'],
        args['outH'],
        args['save'],
      ]),
      _ => throw MissingPluginException(call.method),
    };
    if (reply case ['error', final String message]) {
      throw PlatformException(code: 'worker', message: message);
    }
    return reply;
  });
  await channel.invokeMethod<void>('ready');
}

class _Worker {
  _Worker(this._send, this._replies);

  final SendPort _send;
  final StreamIterator<Object?> _replies;

  static Future<_Worker> spawn() async {
    final port = ReceivePort();
    await Isolate.spawn(_workerMain, port.sendPort);
    final replies = StreamIterator<Object?>(port);
    await replies.moveNext();
    return _Worker(replies.current! as SendPort, replies);
  }

  /// Kotlin issues one request at a time, so replies arrive in order.
  Future<Object?> request(List<Object?> message) async {
    _send.send(message);
    await _replies.moveNext();
    return _replies.current;
  }
}

void _workerMain(SendPort out) {
  final port = ReceivePort();
  out.send(port.sendPort);
  late Uint8List jpeg;
  late String dir;
  port.listen((message) {
    final m = message! as List<Object?>;
    try {
      out.send(switch (m[0]) {
        'setup' => () {
          jpeg = m[1]! as Uint8List;
          dir = m[2]! as String;
          return null;
        }(),
        'info' => {
          'A': buildInfoA(),
          'A_threads': numThreadsA(),
          'B': buildInfoB(),
          'B_threads': numThreadsB(),
        },
        'frame' => _frame(m),
        'still' => _still(m, jpeg, dir),
        _ => ['error', 'unknown ${m[0]}'],
      });
    } catch (e, s) {
      out.send(['error', '$e\n$s']);
    }
  });
}

/// [compute ms (includes A's row repack), corners or null].
List<Object?> _frame(List<Object?> m) {
  final plane = (m[2]! as TransferableTypedData).materialize().asUint8List();
  final (w, h, stride) = (m[3]! as int, m[4]! as int, m[5]! as int);
  final sw = Stopwatch()..start();
  final corners = m[1] == 'A'
      ? detectFrameA(plane, w, h, stride)
      : detectFrameB(plane, w, h, stride);
  return [sw.elapsedMicroseconds / 1000, corners];
}

/// decode, warp, enhance, encode (ms), mean, jpeg bytes.
Float64List _still(List<Object?> m, Uint8List jpeg, String dir) {
  final path = m[1]! as String;
  final corners = m[2]! as Float32List;
  final (outW, outH) = (m[3]! as int, m[4]! as int);
  final StillResult r = path == 'A'
      ? stillA(jpeg, corners, outW, outH)
      : stillB(jpeg, corners, outW, outH);
  if (m[5] == true) File('$dir/out_$path.jpg').writeAsBytesSync(r.jpeg);
  return Float64List.fromList([
    r.decodeMs,
    r.warpMs,
    r.enhanceMs,
    r.encodeMs,
    r.mean,
    r.jpeg.length.toDouble(),
  ]);
}
