"""Compose real device captures with the store-screenshot-composer spotlight card."""

from pathlib import Path
import hashlib
import json

from PIL import Image, ImageDraw, ImageFilter, ImageFont


ROOT = Path(__file__).resolve().parent
SOURCE = ROOT / 'source/harmony-phone-v2/zh-Hans'
OUTPUT = ROOT / 'generated/harmony-agc-phone/zh-Hans'
TABLET_SOURCE = ROOT / 'source/harmony-tablet/zh-Hans'
FONT = '/System/Library/Fonts/STHeiti Medium.ttc'
SLIDES = [
    ('01-home.jpeg', '安静浏览', '常用网站，一触即达'),
    ('02-open-options.png', '按需打开', '清洁、私密，随心选择'),
    ('03-reader-controls.png', '阅读随心', '字号、行距、纸色可调'),
    ('04-site-blocking.png', '拦截可见', '本站请求，一目了然'),
    ('05-reader-mode.png', '专注阅读', '开启阅读模式，少些干扰'),
]
TABLET_SLIDES = [
    ('01-home.png', '大屏浏览', '横屏空间，尽情展开', 'Browse bigger', 'Built for landscape'),
    ('02-search.jpeg', '搜索尽览', '结果更宽，信息更多', 'See more results', 'More context at once'),
    ('03-library-search.jpeg', '文章随查', '正文与笔记都能搜索', 'Find any article', 'Search text and notes'),
    ('04-history-control.jpeg', '隐私可控', '按类型与时间清理', 'Privacy controls', 'Clear by type and time'),
]


def rounded_image(image, radius):
    mask = Image.new('L', image.size)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, image.width-1, image.height-1), radius, fill=255)
    result = image.convert('RGBA')
    result.putalpha(mask)
    return result


def centered(draw, text, y, size, color, canvas_width=1080):
    font = ImageFont.truetype(FONT, size)
    width = draw.textlength(text, font=font)
    assert width < 960, 'Headline exceeds horizontal safe area'
    draw.text(((canvas_width-width)/2, y), text, font=font, fill=color)


def render_tablet():
    manifests = []
    previews = []
    for locale, title_index, subtitle_index in [('zh-Hans', 1, 2), ('en', 3, 4)]:
        output = ROOT / f'generated/harmony-agc-tablet/{locale}'
        output.mkdir(parents=True, exist_ok=True)
        locale_previews = []
        for index, slide in enumerate(TABLET_SLIDES, 1):
            filename, title, subtitle = slide[0], slide[title_index], slide[subtitle_index]
            source_path = TABLET_SOURCE / filename
            source = Image.open(source_path).convert('RGB')
            canvas = Image.new('RGBA', (2730, 1820), '#FEFFFB')
            draw = ImageDraw.Draw(canvas)
            draw.ellipse((-420, -470, 740, 650), fill='#FBF3CE')
            draw.ellipse((2140, 1140, 3100, 2090), fill='#E9F3F0')
            centered(draw, '卓阅浏览器' if locale == 'zh-Hans' else 'ZhuoBrowser',
                     48, 38, '#397365', 2730)
            centered(draw, title, 115, 104, '#142D27', 2730)
            centered(draw, subtitle, 250, 48, '#6A746F', 2730)
            draw.rounded_rectangle((1235, 365, 1495, 384), 9, fill='#F4DA6A')

            crop = (0, 86, source.width, source.height)
            content = source.crop(crop)
            frame_width = 2100
            frame_height = round(content.height * frame_width / content.width)
            frame_x, frame_y = (2730-frame_width)//2, 420
            shadow = Image.new('RGBA', canvas.size)
            ImageDraw.Draw(shadow).rounded_rectangle(
                (frame_x-24, frame_y+12, frame_x+frame_width+24, frame_y+frame_height+50),
                54, fill=(20, 45, 39, 34))
            canvas = Image.alpha_composite(canvas, shadow.filter(ImageFilter.GaussianBlur(24)))
            draw = ImageDraw.Draw(canvas)
            draw.rounded_rectangle((frame_x-20, frame_y-20, frame_x+frame_width+20,
                                    frame_y+frame_height+20), 50, fill='#19241E')
            tablet = content.resize((frame_width, frame_height), Image.Resampling.LANCZOS)
            canvas.alpha_composite(rounded_image(tablet, 34), (frame_x, frame_y))
            footer = 'HarmonyOS 平板真机界面' if locale == 'zh-Hans' else 'Real HarmonyOS tablet UI'
            centered(ImageDraw.Draw(canvas), footer, 1770, 24, '#748078', 2730)
            path = output / f'{index:02d}.png'
            canvas.convert('RGB').save(path, optimize=True)
            assert path.stat().st_size < 5_000_000
            manifests.append({
                'file': str(path.relative_to(ROOT)), 'source': str(source_path.relative_to(ROOT)),
                'title': title, 'subtitle': subtitle, 'locale': locale, 'device': 'tablet',
                'width': 2730, 'height': 1820, 'bytes': path.stat().st_size,
                'sha256': hashlib.sha256(path.read_bytes()).hexdigest(),
                'source_sha256': hashlib.sha256(source_path.read_bytes()).hexdigest(),
                'template': 'spotlight-card-tablet', 'crop': crop,
                'page_content': 'real-device-capture',
            })
            locale_previews.append(canvas.convert('RGB').resize((546, 364), Image.Resampling.LANCZOS))
        sheet = Image.new('RGB', (len(locale_previews)*566+20, 424), '#E7ECE6')
        for index, preview in enumerate(locale_previews):
            sheet.paste(preview, (10+index*566, 10))
        ImageDraw.Draw(sheet).text((18, 389), 'PREVIEW ONLY - NOT FOR STORE UPLOAD',
                                  font=ImageFont.truetype(FONT, 18), fill='#35473F')
        preview_dir = ROOT / 'generated/previews'
        preview_dir.mkdir(parents=True, exist_ok=True)
        sheet.save(preview_dir / f'contact-sheet-harmony-tablet-{locale}.jpg', quality=92)
        previews.extend(locale_previews)
    return manifests


def render():
    OUTPUT.mkdir(parents=True, exist_ok=True)
    manifest = []
    previews = []
    for index, (filename, title, subtitle) in enumerate(SLIDES, 1):
        source = Image.open(SOURCE / filename).convert('RGB')
        canvas = Image.new('RGBA', (1080, 1920), '#FEFFFB')
        draw = ImageDraw.Draw(canvas)
        draw.ellipse((-360, -360, 420, 390), fill='#FBF3CE')
        draw.ellipse((610, 1320, 1330, 2080), fill='#E9F3F0')
        centered(draw, '卓阅浏览器', 63, 28, '#397365')
        draw.rounded_rectangle((444, 215, 636, 230), 7, fill='#F4DA6A')
        centered(draw, title, 127, 78, '#142D27')
        centered(draw, subtitle, 261, 35, '#6A746F')
        # Remove OS status and gesture bars, retaining in-app controls.
        crop = (0, 111, source.width, 2350)
        content = source.crop(crop)
        phone_width = 704
        phone_height = round(content.height * phone_width / content.width)
        phone_x, phone_y = (1080-phone_width)//2, 389
        shadow = Image.new('RGBA', canvas.size)
        ImageDraw.Draw(shadow).rounded_rectangle(
            (phone_x-16, phone_y+6, phone_x+phone_width+16, phone_y+phone_height+40),
            70, fill=(20, 45, 39, 35))
        canvas = Image.alpha_composite(canvas, shadow.filter(ImageFilter.GaussianBlur(20)))
        draw = ImageDraw.Draw(canvas)
        draw.rounded_rectangle((phone_x-16, phone_y-16, phone_x+phone_width+16,
                                phone_y+phone_height+16), 68, fill='#19241E')
        phone = content.resize((phone_width, phone_height), Image.Resampling.LANCZOS)
        canvas.alpha_composite(rounded_image(phone, 52), (phone_x, phone_y))
        draw = ImageDraw.Draw(canvas)
        footer = 'HarmonyOS 原生体验' if index == 1 else '示例页面 · 真实 App 界面'
        centered(draw, footer, 1875, 20, '#748078')
        path = OUTPUT / f'{index:02d}.png'
        canvas.convert('RGB').save(path, optimize=True)
        assert path.stat().st_size < 5_000_000
        manifest.append({
            'file': str(path.relative_to(ROOT)), 'source': str((SOURCE / filename).relative_to(ROOT)),
            'title': title, 'subtitle': subtitle, 'locale': 'zh-Hans', 'device': 'phone',
            'width': 1080, 'height': 1920, 'bytes': path.stat().st_size,
            'sha256': hashlib.sha256(path.read_bytes()).hexdigest(),
            'source_sha256': hashlib.sha256((SOURCE / filename).read_bytes()).hexdigest(),
            'template': 'spotlight-card', 'crop': crop,
            'page_content': 'native-home' if index == 1 else 'local-placeholder-fixture',
        })
        previews.append(canvas.convert('RGB').resize((324, 576), Image.Resampling.LANCZOS))
    sheet = Image.new('RGB', (10+len(previews)*334, 636), '#E7ECE6')
    for index, preview in enumerate(previews):
        sheet.paste(preview, (10+index*334, 10))
    ImageDraw.Draw(sheet).text((18, 600), 'PREVIEW ONLY - NOT FOR STORE UPLOAD',
                              font=ImageFont.truetype(FONT, 18), fill='#35473F')
    preview_dir = ROOT / 'generated/previews'
    preview_dir.mkdir(parents=True, exist_ok=True)
    sheet.save(preview_dir / 'contact-sheet-harmony-zh-Hans.jpg', quality=92)
    manifest.extend(render_tablet())
    (ROOT / 'generated/manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2)+'\n')
    print(json.dumps(manifest, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    render()
