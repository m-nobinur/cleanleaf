"""Detection candidates for the T-018 spike (study code, never shipped).

All detectors take a BGR uint8 image and return a 4x2 float array of pixel
corners (canonical order: clockwise from the min x+y corner) or None.

Frozen parameters (fixed before any fixture labels existed):
- B: DocAligner's own post-processing, heatmap threshold 0.3; a channel with
  no blob means "no clear peak" (CONF_THRESHOLD = 0.3 on the min channel peak).
- C: edge search radius 2.5% of the image diagonal, Gaussian prior sigma R/2.
- A: still path at 1000 px long side, passes and limits as written below.
"""

from dataclasses import dataclass

import cv2
import numpy as np
from ai_edge_litert.interpreter import Interpreter

CONF_THRESHOLD = 0.3
HEATMAP_THRESHOLD = 0.3
REFINE_RADIUS = 0.025
CLASSICAL_SIDE = 1000


def canonical(pts: np.ndarray) -> np.ndarray:
    c = pts.mean(0)
    pts = pts[np.argsort(np.arctan2(pts[:, 1] - c[1], pts[:, 0] - c[0]))]
    return np.roll(pts, -int(np.argmin(pts.sum(1))), axis=0)


# ---------------------------------------------------------------- B: model

@dataclass
class ModelOutput:
    corners: np.ndarray | None  # canonical pixel corners, None if a channel has no blob
    raw_corners: np.ndarray | None  # channel order, before canonical()
    peaks: np.ndarray  # max value per heatmap channel
    heatmap: np.ndarray  # (128, 128, 4)


class DocAligner:
    def __init__(self, model_path: str, threads: int = 4):
        self.it = Interpreter(model_path=model_path, num_threads=threads)
        self.it.allocate_tensors()
        self.inp = self.it.get_input_details()[0]["index"]
        self.out = self.it.get_output_details()[0]["index"]

    def heatmap(self, bgr: np.ndarray) -> np.ndarray:
        x = cv2.resize(bgr, (256, 256), interpolation=cv2.INTER_LINEAR).astype(np.float32) / 255.0
        self.it.set_tensor(self.inp, x[None])
        self.it.invoke()
        return self.it.get_tensor(self.out)[0]

    def __call__(self, bgr: np.ndarray, fast_post: bool = False) -> ModelOutput:
        hm = self.heatmap(bgr)
        h, w = bgr.shape[:2]
        peaks = hm.reshape(-1, 4).max(0)
        pts = []
        for k in range(4):
            p = blob_centroid_lowres(hm[..., k], w, h) if fast_post else blob_centroid_fullres(hm[..., k], w, h)
            if p is None:
                return ModelOutput(None, None, peaks, hm)
            pts.append(p)
        raw = np.array(pts, np.float64)
        return ModelOutput(canonical(raw), raw, peaks, hm)


def _largest_blob_centroid(mask: np.ndarray) -> tuple[float, float] | None:
    n, _, stats, cents = cv2.connectedComponentsWithStats(mask.astype(np.uint8), connectivity=8)
    if n <= 1:
        return None
    k = 1 + int(np.argmax(stats[1:, cv2.CC_STAT_AREA]))
    return float(cents[k][0]), float(cents[k][1])


def blob_centroid_fullres(ch: np.ndarray, w: int, h: int):
    """DocAligner infer.py: upsample to image size, threshold, largest blob centroid."""
    up = cv2.resize(ch, (w, h), interpolation=cv2.INTER_LINEAR)
    return _largest_blob_centroid(up >= HEATMAP_THRESHOLD)


def blob_centroid_lowres(ch: np.ndarray, w: int, h: int):
    """Same rule on the 128x128 map, mapped with pixel-centre alignment (device version)."""
    c = _largest_blob_centroid(ch >= HEATMAP_THRESHOLD)
    if c is None:
        return None
    s = ch.shape[0]
    return (c[0] + 0.5) * w / s - 0.5, (c[1] + 0.5) * h / s - 0.5


# ---------------------------------------------------------- C: refinement

def refine(bgr: np.ndarray, quad: np.ndarray, radius_frac: float = REFINE_RADIUS) -> np.ndarray:
    """Snap each corner to the intersection of the two nearby page edges.

    For every side, sample the half next to each corner, search along the side
    normal (+-R) for the strongest directional gradient with a consistent sign,
    weighted by a Gaussian prior around the model's line, robust-fit a line,
    then intersect. A corner keeps the model position when the edge support is
    weak or the snap moves further than R.
    """
    h, w = bgr.shape[:2]
    R = radius_frac * float(np.hypot(w, h))
    gray = cv2.GaussianBlur(cv2.cvtColor(bgr, cv2.COLOR_BGR2GRAY).astype(np.float32), (0, 0), 1.5)
    gx = cv2.Sobel(gray, cv2.CV_32F, 1, 0, ksize=3)
    gy = cv2.Sobel(gray, cv2.CV_32F, 0, 1, ksize=3)
    offsets = np.arange(-R, R + 1, 1.0, dtype=np.float32)
    prior = np.exp(-0.5 * (offsets / (R / 2)) ** 2)

    def half_line(a: np.ndarray, b: np.ndarray):
        """Line fitted to the half of side a->b nearest a. Returns (point, dir) or None."""
        d = b - a
        L = float(np.hypot(*d))
        if L < 4:
            return None
        u = d / L
        n = np.array([-u[1], u[0]])
        ts = np.linspace(0.03, 0.5, 24)
        base = a[None] + ts[:, None] * d[None]
        pts = base[:, None, :] + offsets[None, :, None] * n[None, None, :]
        mx, my = pts[..., 0].astype(np.float32), pts[..., 1].astype(np.float32)
        gn = (cv2.remap(gx, mx, my, cv2.INTER_LINEAR, borderMode=cv2.BORDER_REPLICATE) * n[0]
              + cv2.remap(gy, mx, my, cv2.INTER_LINEAR, borderMode=cv2.BORDER_REPLICATE) * n[1])
        inside = (mx >= 0) & (mx < w) & (my >= 0) & (my < h)
        best = []
        for sign in (1.0, -1.0):
            score = np.where(inside, np.maximum(sign * gn, 0) * prior[None], 0)
            j = score.argmax(1)
            best.append((score[np.arange(len(ts)), j], j))
        s_pos, s_neg = best[0][0].sum(), best[1][0].sum()
        strength, j = best[0] if s_pos >= s_neg else best[1]
        strong = strength > 0.35 * np.median(strength[strength > 0]) if (strength > 0).any() else strength > 0
        if strong.sum() < 8 or np.median(strength) < 4.0:
            return None
        found = base[strong] + offsets[j[strong], None] * n[None]
        vx, vy, x0, y0 = cv2.fitLine(found.astype(np.float32), cv2.DIST_HUBER, 0, 0.01, 0.01).ravel()
        return np.array([x0, y0]), np.array([vx, vy])

    def intersect(l1, l2):
        (p, r), (q, s) = l1, l2
        den = r[0] * s[1] - r[1] * s[0]
        if abs(den) < 1e-6:
            return None
        t = ((q[0] - p[0]) * s[1] - (q[1] - p[1]) * s[0]) / den
        return p + t * r

    out = quad.copy().astype(np.float64)
    for i in range(4):
        prev, cur, nxt = quad[(i - 1) % 4], quad[i], quad[(i + 1) % 4]
        l_in = half_line(cur, prev)  # side prev-cur, half nearest cur
        l_out = half_line(cur, nxt)
        if l_in is None or l_out is None:
            continue
        p = intersect(l_in, l_out)
        if p is not None and np.hypot(*(p - cur)) <= R:
            out[i] = p
    return out


# ------------------------------------------------------------ A: classical

def _valid_quad(q: np.ndarray, img_area: float) -> bool:
    if len(q) != 4 or not cv2.isContourConvex(q.astype(np.float32)):
        return False
    area = cv2.contourArea(q.astype(np.float32))
    if not (0.08 * img_area <= area <= 0.98 * img_area):
        return False
    for i in range(4):
        a, b, c = q[i - 1], q[i], q[(i + 1) % 4]
        v1, v2 = a - b, c - b
        cos = np.dot(v1, v2) / (np.linalg.norm(v1) * np.linalg.norm(v2) + 1e-9)
        if not (np.cos(np.deg2rad(150)) <= cos <= np.cos(np.deg2rad(30))):
            return False
    return True


def _quad_from_contours(edges: np.ndarray, img_area: float) -> np.ndarray | None:
    cnts, _ = cv2.findContours(edges, cv2.RETR_LIST, cv2.CHAIN_APPROX_SIMPLE)
    for c in sorted(cnts, key=cv2.contourArea, reverse=True)[:10]:
        hull = cv2.convexHull(c)
        q = cv2.approxPolyDP(hull, 0.02 * cv2.arcLength(hull, True), True).reshape(-1, 2).astype(np.float64)
        if _valid_quad(q, img_area):
            return q
    return None


def _quad_from_longest_sides(edges: np.ndarray, img_area: float) -> np.ndarray | None:
    """Line-segment fallback: the 4 longest sides of the biggest hull, intersected."""
    cnts, _ = cv2.findContours(edges, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    if not cnts:
        return None
    hull = cv2.convexHull(max(cnts, key=cv2.contourArea))
    poly = cv2.approxPolyDP(hull, 0.01 * cv2.arcLength(hull, True), True).reshape(-1, 2).astype(np.float64)
    if len(poly) < 4:
        return None
    sides = [(poly[i], poly[(i + 1) % len(poly)]) for i in range(len(poly))]
    keep = sorted(np.argsort([-np.hypot(*(b - a)) for a, b in sides])[:4])
    lines = [sides[k] for k in keep]
    q = []
    for i in range(4):
        (p1, p2), (p3, p4) = lines[i - 1], lines[i]
        d1, d2 = p2 - p1, p4 - p3
        den = d1[0] * d2[1] - d1[1] * d2[0]
        if abs(den) < 1e-6:
            return None
        t = ((p3[0] - p1[0]) * d2[1] - (p3[1] - p1[1]) * d2[0]) / den
        q.append(p1 + t * d1)
    q = np.array(q)
    return q if _valid_quad(q, img_area) else None


def _auto_canny(img: np.ndarray, sigma: float = 0.33) -> np.ndarray:
    v = float(np.median(img))
    return cv2.Canny(img, int(max(0, (1 - sigma) * v)), int(min(255, (1 + sigma) * v)))


def classical(bgr: np.ndarray) -> np.ndarray | None:
    h, w = bgr.shape[:2]
    s = CLASSICAL_SIDE / max(h, w)
    small = cv2.resize(bgr, (int(w * s), int(h * s)), interpolation=cv2.INTER_AREA)
    area = small.shape[0] * small.shape[1]
    k = cv2.getStructuringElement(cv2.MORPH_RECT, (9, 9))
    dil = cv2.getStructuringElement(cv2.MORPH_RECT, (3, 3))

    gray = cv2.cvtColor(small, cv2.COLOR_BGR2GRAY)
    prep = cv2.morphologyEx(cv2.GaussianBlur(gray, (5, 5), 0), cv2.MORPH_CLOSE, k)
    hsv_s = cv2.cvtColor(small, cv2.COLOR_BGR2HSV)[..., 1]
    lab = cv2.cvtColor(small, cv2.COLOR_BGR2LAB)
    chans = [prep,
             cv2.morphologyEx(cv2.GaussianBlur(hsv_s, (5, 5), 0), cv2.MORPH_CLOSE, k),
             cv2.morphologyEx(cv2.GaussianBlur(lab[..., 0], (5, 5), 0), cv2.MORPH_CLOSE, k)]

    q = None
    for ch in chans:  # 1-2. auto-Canny on gray, then on the HSV S / Lab L channels
        q = _quad_from_contours(cv2.dilate(_auto_canny(ch), dil), area)
        if q is not None:
            break
    if q is None:  # 3. Otsu
        _, bw = cv2.threshold(prep, 0, 255, cv2.THRESH_BINARY + cv2.THRESH_OTSU)
        q = _quad_from_contours(bw, area)
    if q is None:  # 4. line-segment intersection on the strongest edges
        q = _quad_from_longest_sides(cv2.dilate(_auto_canny(prep), dil), area)
    return None if q is None else canonical(q / s)


# ------------------------------------------------------------- candidates

def candidates(model: DocAligner):
    """Name -> fn(bgr) -> (corners | None, peaks | None)."""

    def b(bgr):
        o = model(bgr)
        ok = o.corners is not None and o.peaks.min() >= CONF_THRESHOLD
        return (o.corners if ok else None), o.peaks

    def c(bgr):
        o = model(bgr)
        ok = o.corners is not None and o.peaks.min() >= CONF_THRESHOLD
        return (canonical(refine(bgr, o.corners)) if ok else None), o.peaks

    def with_fallback(fn):
        def run(bgr):
            q, peaks = fn(bgr)
            return (q if q is not None else classical(bgr)), peaks
        return run

    return {
        "A classical": lambda bgr: (classical(bgr), None),
        "B model": b,
        "B + A fallback": with_fallback(b),
        "C model+refine": c,
        "C + A fallback": with_fallback(c),
    }
