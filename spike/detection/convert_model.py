"""Convert DocAligner LC100 (official fp32 ONNX) to an fp16-weight TFLite.

Usage: python convert_model.py <lcnet100_h_e_bifpn_256_fp32.onnx> <out_dir>

Two graph rewrites before onnx2tf, both numerically exact in ONNX:
1. fold constants (onnx2tf 1.28.8 crashes on ReduceSum over the constant
   BiFPN fusion weights);
2. replace each BiFPN `Einsum('i,i...->...', w, Concat(Unsqueeze(x_k)))`
   with `sum_k w_k * x_k` on the 4-D inputs (onnx2tf mis-transposes the
   stacked 5-D tensor, which shifts the heatmaps).
"""

import subprocess
import sys
from pathlib import Path

import numpy as np
import onnx
import onnx_graphsurgeon as gs
import onnxruntime as ort


def rewrite(src: Path, dst: Path, pad_zero: bool) -> None:
    graph = gs.import_onnx(onnx.load(str(src)))
    graph.inputs[0].shape = [1, 3, 256, 256]
    graph.fold_constants().cleanup().toposort()

    for node in [n for n in graph.nodes if n.op == "Einsum"]:
        weights, stacked = node.inputs
        assert node.attrs["equation"].replace(" ", "") == "i,i...->...", node.attrs
        assert isinstance(weights, gs.Constant), node.name
        concat = stacked.inputs[0]
        assert concat.op == "Concat" and concat.attrs["axis"] == 0, concat.name
        parts = []
        for k, unsq_out in enumerate(concat.inputs):
            unsq = unsq_out.inputs[0]
            assert unsq.op == "Unsqueeze", unsq.name
            x = unsq.inputs[0]
            w = gs.Constant(f"{node.name}_w{k}", np.array(weights.values[k], np.float32))
            y = gs.Variable(f"{node.name}_mul{k}", dtype=np.float32)
            graph.nodes.append(gs.Node("Mul", f"{node.name}/mul{k}", inputs=[x, w], outputs=[y]))
            parts.append(y)
        acc = parts[0]
        for k, p in enumerate(parts[1:], 1):
            out = node.outputs[0] if k == len(parts) - 1 else gs.Variable(f"{node.name}_add{k}", dtype=np.float32)
            graph.nodes.append(gs.Node("Add", f"{node.name}/add{k}", inputs=[acc, p], outputs=[out]))
            acc = out
        node.outputs.clear()

    if pad_zero:
        for node in [n for n in graph.nodes if n.op == "MaxPool"]:
            assert node.inputs[0].inputs[0].op == "Relu", node.name  # zero pad == -inf pad
            top, left, bottom, right = node.attrs["pads"]
            padded = gs.Variable(f"{node.name}_padded", dtype=np.float32)
            pads = gs.Constant(f"{node.name}_pads", np.array([0, 0, top, left, 0, 0, bottom, right], np.int64))
            graph.nodes.append(gs.Node("Pad", f"{node.name}/pad", attrs={"mode": "constant"},
                                       inputs=[node.inputs[0], pads], outputs=[padded]))
            node.inputs[0] = padded
            node.attrs["pads"] = [0, 0, 0, 0]

    graph.cleanup().toposort()
    model = onnx.shape_inference.infer_shapes(gs.export_onnx(graph))
    onnx.save(model, str(dst))


def max_abs_diff(a: Path, b: Path) -> float:
    x = np.random.default_rng(0).random((1, 3, 256, 256), dtype=np.float32)
    ya = ort.InferenceSession(str(a)).run(None, {"img": x})[0]
    yb = ort.InferenceSession(str(b)).run(None, {"img": x})[0]
    return float(np.abs(ya - yb).max())


def main() -> None:
    src, out_dir = Path(sys.argv[1]), Path(sys.argv[2])
    pad_zero = "--pad-zero" in sys.argv
    out_dir.mkdir(parents=True, exist_ok=True)
    rewritten = out_dir / ("lc100_padzero.onnx" if pad_zero else "lc100_rewritten.onnx")
    rewrite(src, rewritten, pad_zero)
    print("rewritten vs original ONNX max abs diff:", max_abs_diff(src, rewritten))
    subprocess.run(["onnx2tf", "-i", str(rewritten), "-o", str(out_dir)], check=True)


if __name__ == "__main__":
    main()
