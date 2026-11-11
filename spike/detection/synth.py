"""Synthetic detection set (study only): pages composited onto backgrounds.

Usage: python synth.py <out_dir> [seed]

Writes f001.jpg ... (1200x1600 portrait, like the 1600 px fixtures) and a
labels.json in the T-007 schema: {file: {corners: [[x,y]x4 normalized,
clockwise from top-left] | null, tags: [...]}}.
"""

import json
import string
import sys
from pathlib import Path

import cv2
import numpy as np
import skimage.data as skd

W, H = 1200, 1600
BG_NAMES = ["astronaut", "brick", "camera", "chelsea", "coffee", "coins", "grass",
            "gravel", "rocket", "moon", "hubble_deep_field", "immunohistochemistry",
            "clock", "horse", "logo", "colorwheel"]


def natural_backgrounds() -> list[np.ndarray]:
    out = []
    for name in BG_NAMES:
        try:
            im = getattr(skd, name)()
        except Exception:
            continue
        if im.dtype != np.uint8:
            im = (im * 255 if im.max() <= 1 else im).astype(np.uint8)
        if im.ndim == 2:
            im = cv2.cvtColor(im, cv2.COLOR_GRAY2BGR)
        elif im.shape[2] == 4:
            im = cv2.cvtColor(im, cv2.COLOR_RGBA2BGR)
        else:
            im = cv2.cvtColor(im, cv2.COLOR_RGB2BGR)
        out.append(im)
    return out


def fit(im: np.ndarray, rng) -> np.ndarray:
    h, w = im.shape[:2]
    s = max(W / w, H / h) * rng.uniform(1.0, 1.4)
    im = cv2.resize(im, (int(w * s) + 1, int(h * s) + 1))
    y = rng.integers(0, im.shape[0] - H + 1)
    x = rng.integers(0, im.shape[1] - W + 1)
    return im[y:y + H, x:x + W].copy()


def procedural(kind: str, rng) -> np.ndarray:
    if kind == "light":  # white-ish table: the low-contrast case
        base = rng.uniform(205, 240)
        im = np.full((H, W, 3), base, np.float32)
        im += cv2.GaussianBlur(rng.normal(0, 6, (H, W)).astype(np.float32), (0, 0), 3)[..., None]
        im *= rng.uniform(0.97, 1.03, 3)
    elif kind == "dark":
        im = np.full((H, W, 3), rng.uniform(15, 60), np.float32)
        im += rng.normal(0, 4, (H, W))[..., None]
    elif kind == "wood":
        y, x = np.mgrid[0:H, 0:W].astype(np.float32)
        a = rng.uniform(0, np.pi)
        u = x * np.cos(a) + y * np.sin(a)
        g = np.sin(u / rng.uniform(6, 20) + 3 * np.sin(u / 90)) * 0.5 + 0.5
        tone = np.array([rng.uniform(60, 110), rng.uniform(100, 150), rng.uniform(140, 190)])
        im = tone * (0.75 + 0.35 * g[..., None])
    else:  # pattern: stripes / checks / dots like bedsheets
        y, x = np.mgrid[0:H, 0:W]
        p = rng.integers(20, 70)
        c1, c2 = rng.uniform(40, 230, 3), rng.uniform(40, 230, 3)
        mask = ((x // p + y // p) % 2 == 0) if rng.random() < 0.5 else ((x + y) // p % 2 == 0)
        im = np.where(mask[..., None], c1, c2).astype(np.float32)
        im = cv2.GaussianBlur(im, (0, 0), 1.5)
    return np.clip(im, 0, 255).astype(np.uint8)


def page(kind: str, rng) -> np.ndarray:
    aspect = {"a4": 1.414, "receipt": rng.uniform(2.5, 3.5), "card": 1.586}[kind]
    pw = 700 if kind != "receipt" else 300
    ph = int(pw * aspect)
    if kind == "card":
        pw, ph = ph, pw
    tone = rng.uniform(225, 255)
    pg = np.full((ph, pw, 3), tone, np.uint8)
    if kind == "card":
        pg[:] = rng.uniform(60, 240, 3)
    margin = int(pw * 0.08)
    yy = margin
    letters = string.ascii_letters + "     "
    while yy < ph - margin:
        if rng.random() < 0.08:
            h = int(rng.uniform(30, 120))
            cv2.rectangle(pg, (margin, yy), (pw - margin, min(ph - margin, yy + h)),
                          tuple(int(v) for v in rng.uniform(80, 200, 3)), -1)
            yy += h + 10
            continue
        txt = "".join(rng.choice(list(letters), int(rng.uniform(20, 60))))
        scale = pw / 900
        cv2.putText(pg, txt, (margin, yy + int(20 * scale)), cv2.FONT_HERSHEY_SIMPLEX,
                    scale * 0.8, (30, 30, 30), max(1, int(2 * scale)), cv2.LINE_AA)
        yy += int(rng.uniform(26, 40) * scale)
    return pg


def random_quad(pw: int, ph: int, rng) -> np.ndarray:
    while True:  # the shot list keeps the whole page in frame
        q = _random_quad(pw, ph, rng)
        if q.min() >= 15 and (q[:, 0] <= W - 15).all() and (q[:, 1] <= H - 15).all():
            return q


def _random_quad(pw: int, ph: int, rng) -> np.ndarray:
    area_frac = rng.uniform(0.18, 0.6)
    s = np.sqrt(area_frac * W * H / (pw * ph))
    w, h = pw * s, ph * s
    ang = np.deg2rad(rng.choice([rng.uniform(-12, 12), rng.uniform(-45, 45)], p=[0.6, 0.4]))
    pts = np.array([[-w / 2, -h / 2], [w / 2, -h / 2], [w / 2, h / 2], [-w / 2, h / 2]])
    pts += rng.normal(0, 0.06 * min(w, h), pts.shape)  # perspective
    if rng.random() < 0.5:  # keystone, as from a ~30 degree tilt
        k = rng.uniform(0.0, 0.18) * w
        pts[0, 0] += k; pts[1, 0] -= k
    r = np.array([[np.cos(ang), -np.sin(ang)], [np.sin(ang), np.cos(ang)]])
    pts = pts @ r.T
    span = pts.max(0) - pts.min(0)
    cx = rng.uniform(span[0] / 2 + 20, W - span[0] / 2 - 20) if span[0] < W - 40 else W / 2
    cy = rng.uniform(span[1] / 2 + 20, H - span[1] / 2 - 20) if span[1] < H - 40 else H / 2
    return (pts + [cx, cy]).astype(np.float32)


def canonical(pts: np.ndarray) -> np.ndarray:
    """Clockwise in image coords (y down), starting at the min x+y corner."""
    c = pts.mean(0)
    order = np.argsort(np.arctan2(pts[:, 1] - c[1], pts[:, 0] - c[0]))
    pts = pts[order]
    start = int(np.argmin(pts.sum(1)))
    return np.roll(pts, -start, axis=0)


def light_and_camera(im: np.ndarray, rng, shadow: bool) -> np.ndarray:
    f = im.astype(np.float32)
    y, x = np.mgrid[0:H, 0:W].astype(np.float32)
    a = rng.uniform(0, 2 * np.pi)
    grad = 1 + rng.uniform(0.0, 0.25) * ((x / W - 0.5) * np.cos(a) + (y / H - 0.5) * np.sin(a))
    f *= grad[..., None]
    if shadow:
        poly = (rng.uniform(0, 1, (5, 2)) * [W, H]).astype(np.int32)
        m = np.zeros((H, W), np.float32)
        cv2.fillPoly(m, [cv2.convexHull(poly)], 1.0)
        m = cv2.GaussianBlur(m, (0, 0), rng.uniform(10, 40))
        f *= (1 - rng.uniform(0.25, 0.5) * m)[..., None]
    f += rng.normal(0, rng.uniform(1, 5), f.shape)
    f = cv2.GaussianBlur(f, (0, 0), rng.uniform(0.3, 1.4))
    out = np.clip(f, 0, 255).astype(np.uint8)
    ok, enc = cv2.imencode(".jpg", out, [cv2.IMWRITE_JPEG_QUALITY, int(rng.uniform(75, 95))])
    return cv2.imdecode(enc, cv2.IMREAD_COLOR)


def main() -> None:
    out = Path(sys.argv[1]); out.mkdir(parents=True, exist_ok=True)
    rng = np.random.default_rng(int(sys.argv[2]) if len(sys.argv) > 2 else 7)
    nat = natural_backgrounds()
    plan = ([("light", "a4", ["low-contrast", "light"])] * 16
            + [("light", "receipt", ["low-contrast", "light"])] * 4
            + [("dark", "a4", ["dark"])] * 8 + [("dark", "receipt", ["dark"])] * 2
            + [("wood", "a4", [])] * 10 + [("wood", "card", [])] * 3
            + [("pattern", "a4", ["pattern"])] * 8
            + [("natural", "a4", ["pattern"])] * 9)
    labels, n = {}, 0
    for bg_kind, pkind, tags in plan:
        n += 1
        bg = fit(nat[rng.integers(len(nat))], rng) if bg_kind == "natural" else procedural(bg_kind, rng)
        pg = page(pkind, rng)
        ph, pw = pg.shape[:2]
        dst = random_quad(pw, ph, rng)
        hm = cv2.getPerspectiveTransform(np.float32([[0, 0], [pw, 0], [pw, ph], [0, ph]]), dst)
        warped = cv2.warpPerspective(pg, hm, (W, H), flags=cv2.INTER_LINEAR)
        mask = cv2.warpPerspective(np.full((ph, pw), 255, np.uint8), hm, (W, H))
        m = cv2.GaussianBlur(mask, (3, 3), 0).astype(np.float32)[..., None] / 255
        im = (warped * m + bg * (1 - m)).astype(np.uint8)
        shadow = rng.random() < 0.3
        im = light_and_camera(im, rng, shadow)
        name = f"s{n:03d}.jpg"
        cv2.imwrite(str(out / name), im, [cv2.IMWRITE_JPEG_QUALITY, 95])
        corners = canonical(dst / [W, H])  # T-007 order: min x+y in normalized coords
        labels[name] = {"corners": corners.round(5).tolist(),
                        "tags": tags + [pkind] + (["shadow"] if shadow else [])}
    for i in range(20):
        n += 1
        if i < 12:
            im = fit(nat[i % len(nat)], rng)
        else:
            im = procedural(["light", "dark", "wood", "pattern"][i % 4], rng)
            if i >= 16:  # rectangular non-paper distractor: a dark screen / book cover
                q = random_quad(700, 500, rng).astype(np.int32)
                cv2.fillPoly(im, [q], tuple(int(v) for v in rng.uniform(10, 120, 3)))
        im = light_and_camera(im, rng, False)
        name = f"s{n:03d}.jpg"
        cv2.imwrite(str(out / name), im, [cv2.IMWRITE_JPEG_QUALITY, 95])
        labels[name] = {"corners": None, "tags": ["no-document"]}
    (out / "labels.json").write_text(json.dumps(labels, indent=1))
    print(f"wrote {n} images to {out}")


if __name__ == "__main__":
    main()
