"""Score the T-018 candidates on a labelled fixture dir (T-007 labels.json schema).

Usage: python evaluate.py <fixture_dir> <model.tflite> [--json out.json]

Hit rule (T-007): a document is a hit when every corner is within 2% of the
image diagonal; a no-document frame is a hit when the detector returns None.
Corners are compared under the best cyclic rotation (orientation is a separate
feature); the strict-order rate is printed too.
"""

import argparse
import json
import time
from collections import defaultdict
from pathlib import Path

import cv2
import numpy as np

import detectors as det

TOL = 0.02


def corner_error(pred: np.ndarray, gt: np.ndarray, diag: float) -> tuple[float, float]:
    """(best-rotation max error, strict-order max error), as a fraction of the diagonal."""
    strict = float(np.linalg.norm(pred - gt, axis=1).max()) / diag
    best = min(float(np.linalg.norm(np.roll(pred, r, 0) - gt, axis=1).max()) for r in range(4)) / diag
    return best, strict


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("fixtures")
    ap.add_argument("model")
    ap.add_argument("--json")
    args = ap.parse_args()

    root = Path(args.fixtures)
    labels = json.loads((root / "labels.json").read_text())
    model = det.DocAligner(args.model, threads=4)
    cands = det.candidates(model)

    rows = {name: [] for name in cands}
    conf = []  # (is_doc, min_peak, mean_peak, name)
    post_diff = []
    for fname, lab in sorted(labels.items()):
        bgr = cv2.imread(str(root / fname), cv2.IMREAD_COLOR)
        h, w = bgr.shape[:2]
        diag = float(np.hypot(w, h))
        gt = None if lab["corners"] is None else np.array(lab["corners"], np.float64) * [w, h]
        tags = set(lab.get("tags", [])) | ({"no-document"} if gt is None else {"document"})

        full, fast = model(bgr), model(bgr, fast_post=True)
        conf.append((gt is not None, float(full.peaks.min()), float(full.peaks.mean()), fname))
        if full.raw_corners is not None and fast.raw_corners is not None:
            post_diff.append(float(np.linalg.norm(full.raw_corners - fast.raw_corners, axis=1).max()) / diag)

        for name, fn in cands.items():
            t0 = time.perf_counter()
            pred, _ = fn(bgr)
            ms = (time.perf_counter() - t0) * 1000
            if gt is None:
                hit = hit_strict = pred is None
                err = None
            elif pred is None:
                hit = hit_strict = False
                err = None
            else:
                err, err_strict = corner_error(pred, gt, diag)
                hit, hit_strict = err <= TOL, err_strict <= TOL
            rows[name].append({"file": fname, "tags": sorted(tags), "hit": hit, "hit_strict": hit_strict,
                               "err": err, "ms": ms,
                               "pred": None if pred is None else (pred / [w, h]).round(5).tolist()})

    tag_names = sorted({t for r in next(iter(rows.values())) for t in r["tags"]})
    print(f"\n{len(labels)} images, tolerance {TOL:.0%} of diagonal, frozen conf threshold {det.CONF_THRESHOLD}")
    hdr = f"{'candidate':<16} {'overall':>8} {'strict':>7} {'docs':>7} {'no-doc':>7} {'low-con':>8} {'med err':>8} {'Mac ms':>7}"
    print(hdr)
    summary = {}
    for name, rs in rows.items():
        def rate(sel, key="hit"):
            sel = list(sel)
            return (sum(r[key] for r in sel) / len(sel), len(sel)) if sel else (float("nan"), 0)
        ov, _ = rate(rs)
        st, _ = rate(rs, "hit_strict")
        dc, _ = rate(r for r in rs if "document" in r["tags"])
        nd, _ = rate(r for r in rs if "no-document" in r["tags"])
        lc, nlc = rate(r for r in rs if "low-contrast" in r["tags"])
        errs = [r["err"] for r in rs if r["err"] is not None]
        med = float(np.median(errs)) if errs else float("nan")
        ms = float(np.median([r["ms"] for r in rs]))
        print(f"{name:<16} {ov:>8.1%} {st:>7.1%} {dc:>7.1%} {nd:>7.1%} {lc:>8.1%} {med:>8.2%} {ms:>7.1f}")
        summary[name] = {"overall": ov, "strict": st, "docs": dc, "no_doc": nd, "low_contrast": lc,
                         "median_err": med, "mac_ms": ms,
                         "per_tag": {t: rate(r for r in rs if t in r["tags"]) for t in tag_names}}
    print("\nper-tag pass rate (n):")
    print(f"{'tag':<14}" + "".join(f"{n[:14]:>16}" for n in rows))
    for t in tag_names:
        print(f"{t:<14}" + "".join(f"{summary[n]['per_tag'][t][0]:>11.0%} ({summary[n]['per_tag'][t][1]:>2})" for n in rows))

    docs = np.array([c[1] for c in conf if c[0]])
    nodocs = np.array([c[1] for c in conf if not c[0]])
    print("\nconfidence = min over 4 channels of the heatmap peak")
    for label, arr in (("documents", docs), ("no-document", nodocs)):
        if len(arr):
            print(f"  {label:<12} n={len(arr):>3} min={arr.min():.3f} p10={np.percentile(arr, 10):.3f} "
                  f"median={np.median(arr):.3f} p90={np.percentile(arr, 90):.3f} max={arr.max():.3f}")
    if len(docs) and len(nodocs):
        auc = float(np.mean([(d > n) + 0.5 * (d == n) for d in docs for n in nodocs]))
        print(f"  AUC={auc:.3f}")
        for th in (0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7):
            print(f"  threshold {th:.1f}: docs kept {np.mean(docs >= th):6.1%}  no-doc rejected {np.mean(nodocs < th):6.1%}")
    if post_diff:
        print(f"\n128-px vs full-res blob centroid: max diff {max(post_diff):.3%} of diagonal "
              f"(median {np.median(post_diff):.3%})")

    if args.json:
        Path(args.json).write_text(json.dumps({"summary": summary, "rows": rows, "confidence": conf,
                                               "post_diff": post_diff}, indent=1))


if __name__ == "__main__":
    main()
