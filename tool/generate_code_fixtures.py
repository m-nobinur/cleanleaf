"""Writes camera-like 640x480 code frames to test/fixtures/codes (T-029).

Needs segno, python-barcode and Pillow (a throwaway venv is enough). Each frame is
a code at a known pixels-per-module, slightly rotated, blurred and low-contrast
on a grey desk, as a phone's analysis frame sees it. The expected text of each
file is in expected.json.
"""

import io
import json
import pathlib

import barcode
import segno
from PIL import Image, ImageFilter

OUT = pathlib.Path(__file__).resolve().parent.parent / "test" / "fixtures" / "codes"
FRAME = (640, 480)

DENSE = (
    "https://example.org/cleanleaf/receipt?id=8f3a2c91&total=1249.50&currency=BDT"
    "&items=12&note=Thanks+for+shopping+with+us.+Keep+this+code+for+returns+within"
    "+30+days.+Store+4471"
)
SMALL = "https://example.org/a"
UTF8 = "নমস্কার, Cleanleaf ✓ 📄"
EAN13 = "5901234123457"
CODE128 = "CL-2026-000731"


def qr(text, version, scale):
    code = segno.make_qr(text, version=version, error="m", boost_error=False)
    buf = io.BytesIO()
    code.save(buf, kind="png", scale=1, border=4)
    img = Image.open(io.BytesIO(buf.getvalue())).convert("L")
    side = round(img.width * scale)
    # BOX averages partial modules the way a sensor's pixels do.
    return img.resize((side, side), Image.BOX)


def linear(kind, text, module_px):
    modules = barcode.get(kind, text).build()[0]
    quiet = "0" * 10
    row = [0 if m == "1" else 255 for m in quiet + modules + quiet]
    img = Image.new("L", (len(row), 50))
    img.putdata(row * 50)
    return img.resize((round(img.width * module_px), round(img.height * module_px)), Image.BOX)


def frame(code, size=FRAME, angle=4, blur=0.8):
    canvas = Image.new("L", size, 96)
    # Ink and paper as a camera sees them: no pure black or white.
    code = code.point(lambda v: 40 if v < 128 else 205)
    code = code.rotate(angle, expand=True, fillcolor=96, resample=Image.BILINEAR)
    canvas.paste(code, ((size[0] - code.width) // 2, (size[1] - code.height) // 2))
    canvas = canvas.filter(ImageFilter.GaussianBlur(blur))
    # Sensor noise; effect_noise is unseeded, so regenerated files differ slightly.
    return Image.blend(canvas, Image.effect_noise(size, 30), 0.08)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    expected = {}

    def save(name, img, text):
        img.save(OUT / f"{name}.jpg", quality=90)
        expected[f"{name}.jpg"] = text

    # Version 10 is 57 modules: 4 px/module fills about half the frame height.
    for ppm in (1.5, 2.0, 2.5, 3.0, 4.0):
        save(f"qr_v10_{ppm:.1f}ppm", frame(qr(DENSE, 10, ppm)), DENSE)
    save("qr_v2_small", frame(qr(SMALL, 2, 2.5)), SMALL)
    save("qr_utf8", frame(qr(UTF8, None, 4)), UTF8)
    for ppm in (1.0, 1.5, 2.0):
        save(f"ean13_{ppm:.1f}ppm", frame(linear("ean13", EAN13, ppm), angle=2), EAN13)
        save(f"code128_{ppm:.1f}ppm", frame(linear("code128", CODE128, ppm), angle=2), CODE128)
    # The dense code at reticle size in a 1280x960 frame, for the resolution question.
    save("qr_v10_1280", frame(qr(DENSE, 10, 5.0), size=(1280, 960), blur=1.6), DENSE)
    blank = Image.new("L", FRAME, 96).filter(ImageFilter.GaussianBlur(1))
    save("no_code", blank, None)

    (OUT / "expected.json").write_text(json.dumps(expected, ensure_ascii=False, indent=1) + "\n")


if __name__ == "__main__":
    main()
