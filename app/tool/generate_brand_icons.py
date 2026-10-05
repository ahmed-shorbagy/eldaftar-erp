"""Resize the Flutter vector-painter export for installed application icons.

First run brand_feedback_test.dart with ELDAFTTAR_EXPORT_BRAND=1.
Then run this file with Python and Pillow. No private reference files are used.
"""
import json
from pathlib import Path
from PIL import Image

app = Path(__file__).resolve().parents[1]
mark = Image.open(app / 'assets/brand/launcher.png').convert('RGBA')
base = Image.new('RGBA', (1024, 1024), '#FFFBF5')
mark.thumbnail((880, 880), Image.Resampling.LANCZOS)
base.alpha_composite(mark, ((1024 - mark.width) // 2, (1024 - mark.height) // 2))
base = base.convert('RGB')
for density, size in {'mdpi': 48, 'hdpi': 72, 'xhdpi': 96, 'xxhdpi': 144, 'xxxhdpi': 192}.items():
    base.resize((size, size), Image.Resampling.LANCZOS).save(
        app / f'android/app/src/main/res/mipmap-{density}/ic_launcher.png'
    )
ios = app / 'ios/Runner/Assets.xcassets/AppIcon.appiconset'
for entry in json.loads((ios / 'Contents.json').read_text())['images']:
    size = round(float(entry['size'].split('x')[0]) * float(entry['scale'][:-1]))
    base.resize((size, size), Image.Resampling.LANCZOS).save(ios / entry['filename'])
base.save(app / 'windows/runner/resources/app_icon.ico', sizes=[(16, 16), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])
