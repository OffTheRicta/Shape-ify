#!/usr/bin/env python3
"""Create branded legacy and adaptive Android launcher icons from the shared logo."""

from pathlib import Path
from PIL import Image, ImageOps

root = Path(__file__).resolve().parents[1]
res = root / "android/app/src/main/res"
logo = Image.open(root / "assets/logo512.png").convert("RGBA")
background = "#080D14"

for density, size in (("mdpi", 48), ("hdpi", 72), ("xhdpi", 96), ("xxhdpi", 144), ("xxxhdpi", 192)):
    scaled = ImageOps.contain(logo, (size, size), Image.Resampling.LANCZOS)
    canvas = Image.new("RGBA", (size, size), background)
    canvas.alpha_composite(scaled, ((size - scaled.width) // 2, (size - scaled.height) // 2))
    directory = res / f"mipmap-{density}"
    directory.mkdir(parents=True, exist_ok=True)
    canvas.convert("RGB").save(directory / "ic_launcher.png")

foreground = Image.new("RGBA", (432, 432), (0, 0, 0, 0))
scaled = ImageOps.contain(logo, (320, 320), Image.Resampling.LANCZOS)
foreground.alpha_composite(scaled, ((432 - scaled.width) // 2, (432 - scaled.height) // 2))
drawable = res / "drawable"
drawable.mkdir(parents=True, exist_ok=True)
foreground.save(drawable / "shapeify_adaptive_foreground.png")

colors = res / "values" / "icon_colors.xml"
colors.write_text(f'<?xml version="1.0" encoding="utf-8"?>\n<resources><color name="shapeify_icon_background">{background}</color></resources>\n')
adaptive = res / "mipmap-anydpi-v26"
adaptive.mkdir(parents=True, exist_ok=True)
for name in ("ic_launcher", "ic_launcher_round"):
    (adaptive / f"{name}.xml").write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
        '    <background android:drawable="@color/shapeify_icon_background" />\n'
        '    <foreground android:drawable="@drawable/shapeify_adaptive_foreground" />\n'
        '</adaptive-icon>\n'
    )
print("Generated Shape-ify Android icons from assets/logo512.png")
