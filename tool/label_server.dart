// Usage: dart run tool/label_server.dart [fixtures_dir] [port]
// Click 4 corners per photo, pick tags, and labels.json is written in the dir.
import 'dart:convert';
import 'dart:io';

const defaultDir =
    '/Users/nobin/Work/beenwise/cleanleaf/.local/fixtures/detection';
const tags = [
  'light',
  'dark',
  'low-contrast',
  'pattern',
  'handheld',
  'shadow',
  'curl',
  'bangla',
];
final imageName = RegExp(r'^[\w.-]+\.jpe?g$', caseSensitive: false);

Future<void> main(List<String> args) async {
  final dir = Directory(
    args.isNotEmpty
        ? args[0]
        : Platform.environment['CLEANLEAF_FIXTURES'] ?? defaultDir,
  );
  final port = args.length > 1 ? int.parse(args[1]) : 8765;
  if (!dir.existsSync()) {
    stderr.writeln('no such dir: ${dir.path}');
    exit(66);
  }
  final labelsFile = File('${dir.path}/labels.json');
  final labels = <String, Object?>{
    if (labelsFile.existsSync())
      ...jsonDecode(labelsFile.readAsStringSync()) as Map<String, dynamic>,
  };
  List<String> images() =>
      dir
          .listSync()
          .whereType<File>()
          .map((f) => f.uri.pathSegments.last)
          .where(imageName.hasMatch)
          .toList()
        ..sort();

  void save() {
    final sorted = {for (final k in labels.keys.toList()..sort()) k: labels[k]};
    final tmp = File('${labelsFile.path}.tmp')
      ..writeAsStringSync(const JsonEncoder.withIndent('  ').convert(sorted));
    tmp.renameSync(labelsFile.path);
  }

  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
  stdout.writeln('labeling ${images().length} images: http://localhost:$port');
  await for (final req in server) {
    try {
      final path = req.uri.path;
      if (req.method == 'GET' && path == '/') {
        req.response
          ..headers.contentType = ContentType.html
          ..write(_page);
      } else if (req.method == 'GET' && path == '/api/state') {
        req.response
          ..headers.contentType = ContentType.json
          ..write(
            jsonEncode({'images': images(), 'labels': labels, 'tags': tags}),
          );
      } else if (req.method == 'GET' && path.startsWith('/img/')) {
        final name = path.substring(5);
        if (!imageName.hasMatch(name)) throw const FormatException('bad name');
        req.response.headers.contentType = ContentType('image', 'jpeg');
        await req.response.addStream(File('${dir.path}/$name').openRead());
      } else if (req.method == 'POST' && path.startsWith('/api/label/')) {
        // JSON content type forces a CORS preflight, blocking cross-site writes.
        if (req.headers.contentType?.mimeType != 'application/json') {
          throw const FormatException('json only');
        }
        final name = path.substring('/api/label/'.length);
        if (!imageName.hasMatch(name) ||
            !File('${dir.path}/$name').existsSync()) {
          throw const FormatException('bad name');
        }
        final body = jsonDecode(
          await utf8.decoder.bind(req).join(),
        ) as Map<String, dynamic>;
        labels[name] = _validated(body);
        save();
        req.response.write('ok');
      } else {
        req.response.statusCode = HttpStatus.notFound;
      }
    } on Object catch (e) {
      req.response
        ..statusCode = HttpStatus.badRequest
        ..write('$e');
    }
    await req.response.close();
  }
}

Map<String, Object?> _validated(Map<String, dynamic> body) {
  final corners = body['corners'] as List<dynamic>?;
  final picked = (body['tags'] as List<dynamic>).cast<String>().where(
    tags.contains,
  );
  if (corners != null) {
    if (corners.length != 4) throw const FormatException('need 4 corners');
    for (final c in corners) {
      for (final v in (c as List<dynamic>).cast<num>()) {
        if (c.length != 2 || v < 0 || v > 1) {
          throw const FormatException('corner outside 0..1');
        }
      }
    }
  }
  return {
    'corners': corners,
    'tags': [if (corners == null) 'no-document', ...picked],
  };
}

const _page = r'''<!doctype html>
<meta charset="utf-8">
<title>Cleanleaf labeler</title>
<style>
  body { margin: 0; font: 14px system-ui; background: #111; color: #eee; display: flex; height: 100vh; }
  #stage { flex: 1; position: relative; }
  canvas { position: absolute; inset: 0; cursor: crosshair; }
  #side { width: 250px; padding: 12px; background: #1c1c1c; overflow: auto; }
  label { display: block; margin: 4px 0; }
  button { margin: 2px 2px 2px 0; }
  #status { margin: 8px 0; color: #9f9; min-height: 3em; }
  kbd { background: #333; padding: 0 4px; border-radius: 3px; }
</style>
<div id="stage"><canvas id="c"></canvas></div>
<div id="side">
  <h3 id="title"></h3>
  <div id="tags"></div>
  <p><button id="nodoc"><kbd>n</kbd> no document</button>
  <button id="undo"><kbd>u</kbd> undo</button>
  <button id="clear"><kbd>c</kbd> clear</button></p>
  <p><button id="prev"><kbd>&larr;</kbd> prev</button>
  <button id="next"><kbd>&rarr;</kbd>/<kbd>Enter</kbd> save + next</button></p>
  <p><button id="nextTodo"><kbd>t</kbd> next unlabeled</button></p>
  <div id="status"></div>
  <small>Click the 4 corners in any order; they are sorted clockwise from top-left.
  Drag a corner to adjust. The loupe follows the cursor.</small>
</div>
<script>
const $ = id => document.getElementById(id);
const cv = $('c'), ctx = cv.getContext('2d');
let names = [], labels = {}, tagList = [], idx = 0, img = null;
let pts = [], noDoc = false, picked = new Set(), drag = -1, mouse = null, dirty = false;
const R = 10;

async function init() {
  const s = await (await fetch('/api/state')).json();
  names = s.images; labels = s.labels; tagList = s.tags;
  $('tags').innerHTML = tagList.map(t =>
    `<label><input type="checkbox" value="${t}"> ${t}</label>`).join('');
  $('tags').onchange = e => {
    e.target.checked ? picked.add(e.target.value) : picked.delete(e.target.value);
    dirty = true;
  };
  idx = Math.max(0, names.findIndex(n => !labels[n]));
  load();
}

function load() {
  const n = names[idx], l = labels[n];
  img = new Image();
  img.onload = draw;
  img.src = '/img/' + n;
  pts = l && l.corners ? l.corners.map(([x, y]) => ({x, y})) : [];
  noDoc = !!l && !l.corners;
  picked = new Set(l ? l.tags.filter(t => tagList.includes(t)) : []);
  document.querySelectorAll('#tags input').forEach(i => i.checked = picked.has(i.value));
  dirty = false;
  $('title').textContent = `${n}  (${idx + 1}/${names.length}, ${Object.keys(labels).length} labeled)`;
}

function sortClockwise(p) {
  const cx = p.reduce((a, q) => a + q.x, 0) / 4, cy = p.reduce((a, q) => a + q.y, 0) / 4;
  const s = [...p].sort((a, b) => Math.atan2(a.y - cy, a.x - cx) - Math.atan2(b.y - cy, b.x - cx));
  let tl = 0;
  s.forEach((q, i) => { if (q.x + q.y < s[tl].x + s[tl].y) tl = i; });
  return [...s.slice(tl), ...s.slice(0, tl)];
}

function layout() {
  const st = $('stage');
  cv.width = st.clientWidth; cv.height = st.clientHeight;
  const k = Math.min(cv.width / img.width, cv.height / img.height);
  return {k, w: img.width * k, h: img.height * k, ox: (cv.width - img.width * k) / 2, oy: (cv.height - img.height * k) / 2};
}
const toScreen = (p, L) => ({x: L.ox + p.x * L.w, y: L.oy + p.y * L.h});
const toNorm = (e, L) => ({x: Math.min(1, Math.max(0, (e.offsetX - L.ox) / L.w)), y: Math.min(1, Math.max(0, (e.offsetY - L.oy) / L.h))});

function draw() {
  if (!img || !img.complete) return;
  const L = layout();
  ctx.drawImage(img, L.ox, L.oy, L.w, L.h);
  if (pts.length) {
    ctx.strokeStyle = '#0f0'; ctx.lineWidth = 2; ctx.beginPath();
    pts.forEach((p, i) => { const s = toScreen(p, L); i ? ctx.lineTo(s.x, s.y) : ctx.moveTo(s.x, s.y); });
    if (pts.length === 4) ctx.closePath();
    ctx.stroke();
    pts.forEach((p, i) => {
      const s = toScreen(p, L);
      ctx.fillStyle = '#f33'; ctx.beginPath(); ctx.arc(s.x, s.y, 4, 0, 7); ctx.fill();
      ctx.fillStyle = '#ff0'; ctx.font = '14px system-ui'; ctx.fillText(pts.length === 4 ? i + 1 : '•', s.x + 6, s.y - 6);
    });
  }
  if (noDoc) { ctx.fillStyle = '#f90'; ctx.font = '28px system-ui'; ctx.fillText('NO DOCUMENT', 20, 40); }
  if (mouse) {
    const m = 120, z = 5, sw = m / z, sx = (mouse.x - L.ox) / L.k - sw / 2, sy = (mouse.y - L.oy) / L.k - sw / 2;
    const lx = mouse.x > cv.width - m - 30 ? mouse.x - m - 20 : mouse.x + 20, ly = Math.max(5, mouse.y - m - 20);
    ctx.save(); ctx.beginPath(); ctx.rect(lx, ly, m, m); ctx.clip();
    ctx.imageSmoothingEnabled = false;
    ctx.drawImage(img, sx, sy, sw, sw, lx, ly, m, m); ctx.restore();
    ctx.strokeStyle = '#0ff'; ctx.strokeRect(lx, ly, m, m);
    ctx.beginPath(); ctx.moveTo(lx + m / 2, ly); ctx.lineTo(lx + m / 2, ly + m); ctx.moveTo(lx, ly + m / 2); ctx.lineTo(lx + m, ly + m / 2); ctx.stroke();
  }
}

function status(msg) { $('status').textContent = msg; }

async function save() {
  if (!noDoc && pts.length === 0) return true;
  if (!noDoc && pts.length !== 4) { status('place exactly 4 corners (or mark no document)'); return false; }
  const body = {corners: noDoc ? null : pts.map(p => [+p.x.toFixed(5), +p.y.toFixed(5)]), tags: [...picked]};
  const r = await fetch('/api/label/' + names[idx], {method: 'POST', headers: {'Content-Type': 'application/json'}, body: JSON.stringify(body)});
  if (!r.ok) { status('save failed: ' + await r.text()); return false; }
  labels[names[idx]] = {corners: body.corners, tags: noDoc ? ['no-document', ...body.tags] : body.tags};
  return true;
}

async function go(to) {
  if (dirty || (pts.length && !labels[names[idx]])) { if (!await save()) return; }
  idx = Math.min(names.length - 1, Math.max(0, to)); load();
}
const nextTodo = () => { const i = names.findIndex((n, j) => j > idx && !labels[n]); return i < 0 ? idx : i; };

cv.onmousedown = e => {
  if (!img) return;
  const L = layout(), m = toNorm(e, L);
  drag = pts.findIndex(p => Math.hypot(toScreen(p, L).x - e.offsetX, toScreen(p, L).y - e.offsetY) < R * 1.5);
  if (drag < 0 && pts.length < 4 && !noDoc) {
    pts.push(m); if (pts.length === 4) pts = sortClockwise(pts);
    dirty = true; status('');
  }
  draw();
};
cv.onmousemove = e => {
  mouse = {x: e.offsetX, y: e.offsetY};
  if (drag >= 0) { pts[drag] = toNorm(e, layout()); dirty = true; }
  draw();
};
cv.onmouseup = () => { if (drag >= 0 && pts.length === 4) pts = sortClockwise(pts); drag = -1; draw(); };
cv.onmouseleave = () => { mouse = null; draw(); };
window.onresize = draw;

const undo = () => { pts.pop(); dirty = true; draw(); };
const clear = () => { pts = []; noDoc = false; dirty = true; draw(); };
const toggleNoDoc = () => { noDoc = !noDoc; if (noDoc) pts = []; dirty = true; draw(); };
$('undo').onclick = undo; $('clear').onclick = clear; $('nodoc').onclick = toggleNoDoc;
$('prev').onclick = () => go(idx - 1); $('next').onclick = () => go(idx + 1);
$('nextTodo').onclick = () => go(nextTodo());
document.onkeydown = e => {
  if (e.target.tagName === 'INPUT') return;
  if (e.key === 'n') toggleNoDoc(); else if (e.key === 'u') undo(); else if (e.key === 'c') clear();
  else if (e.key === 't') go(nextTodo());
  else if (e.key === 'ArrowRight' || e.key === 'Enter') go(idx + 1);
  else if (e.key === 'ArrowLeft') go(idx - 1);
};
init();
</script>
''';
