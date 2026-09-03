"""Render the store-screenshot-composer focus-callout template from real captures."""

from pathlib import Path
import hashlib
import json

from PIL import Image, ImageDraw, ImageFilter, ImageFont, ImageOps


ROOT = Path(__file__).resolve().parent
SOURCE = ROOT / 'source/harmony-phone/zh-Hans'
OUTPUT = ROOT / 'generated/harmony-agc-phone/zh-Hans'
FONT = '/System/Library/Fonts/STHeiti Medium.ttc'
SLIDES = [
    ('01-home.jpeg', '安静浏览', '常用网站，一触即达', (40, 820, 1040, 1470)),
    ('02-open-options.jpeg', '按需打开', '清洁、私密，随心选择', (70, 970, 1010, 1450)),
    ('03-reader.jpeg', '自在阅读', '字号、行距，随你调整', (40, 110, 900, 245)),
]


def rounded_image(image, radius):
    mask = Image.new('L', image.size)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, image.width-1, image.height-1), radius, fill=255)
    result = image.convert('RGBA')
    result.putalpha(mask)
    return result


def centered(draw, text, y, size, color):
    font = ImageFont.truetype(FONT, size)
    width = draw.textlength(text, font=font)
    assert width < 960, 'Headline exceeds horizontal safe area'
    draw.text(((1080-width)/2, y), text, font=font, fill=color)


def render():
    OUTPUT.mkdir(parents=True, exist_ok=True)
    manifest = []
    previews = []
    for index, (filename, title, subtitle, focus) in enumerate(SLIDES, 1):
        source = Image.open(SOURCE / filename).convert('RGB')
        canvas = Image.new('RGBA', (1080, 1920), '#F5F8F4')
        draw = ImageDraw.Draw(canvas)
        centered(draw, '卓阅浏览器', 90, 30, '#397365')
        centered(draw, title, 175, 80, '#142D27')
        centered(draw, subtitle, 287, 37, '#53665D')
        # Remove OS status and gesture bars, retaining in-app controls.
        content = source.crop((0, 105, source.width, 2360))
        phone_width, phone_height = 640, 1330
        phone_x, phone_y = 220, 460
        draw.rounded_rectangle((phone_x-12, phone_y-12, phone_x+phone_width+12,
                                phone_y+phone_height+12), 68, fill='#0E1713')
        phone = ImageOps.fit(content, (phone_width, phone_height), method=Image.Resampling.LANCZOS)
        canvas.alpha_composite(rounded_image(phone, 54), (phone_x, phone_y))
        detail = source.crop(focus)
        detail.thumbnail((820, 400), Image.Resampling.LANCZOS)
        if detail.width < 820:
            detail = detail.resize((820, round(detail.height*820/detail.width)), Image.Resampling.LANCZOS)
        callout = Image.new('RGBA', (detail.width+24, detail.height+24), 'white')
        callout.paste(detail, (12, 12))
        callout = rounded_image(callout, 30)
        x, y = (1080-callout.width)//2, 945
        shadow = Image.new('RGBA', canvas.size)
        shadow_draw = ImageDraw.Draw(shadow)
        shadow_draw.rounded_rectangle((x, y+10, x+callout.width, y+callout.height+10),
                                      30, fill=(20, 45, 39, 48))
        canvas = Image.alpha_composite(canvas, shadow.filter(ImageFilter.GaussianBlur(20)))
        canvas.alpha_composite(callout, (x, y))
        draw = ImageDraw.Draw(canvas)
        centered(draw, 'HarmonyOS 原生浏览体验', 1840, 25, '#6D7B72')
        path = OUTPUT / f'{index:02d}.png'
        canvas.convert('RGB').save(path, optimize=True)
        assert path.stat().st_size < 5_000_000
        manifest.append({
            'file': str(path.relative_to(ROOT)), 'source': str((SOURCE / filename).relative_to(ROOT)),
            'title': title, 'subtitle': subtitle, 'locale': 'zh-Hans', 'device': 'phone',
            'width': 1080, 'height': 1920, 'bytes': path.stat().st_size,
            'sha256': hashlib.sha256(path.read_bytes()).hexdigest(),
            'source_sha256': hashlib.sha256((SOURCE / filename).read_bytes()).hexdigest(),
            'focus': focus, 'crop': [0, 105, source.width, 2360],
        })
        previews.append(canvas.convert('RGB').resize((324, 576), Image.Resampling.LANCZOS))
    sheet = Image.new('RGB', (1012, 636), '#E7ECE6')
    for index, preview in enumerate(previews):
        sheet.paste(preview, (10+index*334, 10))
    ImageDraw.Draw(sheet).text((18, 600), 'PREVIEW ONLY - NOT FOR STORE UPLOAD',
                              font=ImageFont.truetype(FONT, 18), fill='#35473F')
    preview_dir = ROOT / 'generated/previews'
    preview_dir.mkdir(parents=True, exist_ok=True)
    sheet.save(preview_dir / 'contact-sheet-harmony-zh-Hans.jpg', quality=92)
    (ROOT / 'generated/manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2)+'\n')
    print(json.dumps(manifest, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    render()
