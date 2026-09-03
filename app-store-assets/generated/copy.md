# Store Screenshot Copy

Revision: V2. Template: spotlight-card. Locale: zh-Hans only. Target: HarmonyOS AGC phone, portrait 1080 x 1920 PNG, five images under 5 MB each.

The template was changed from focus-callout after quality feedback to make the main screenshots larger and eliminate duplicated overlays. Captures show the real installed 1.0.1 (1000001) app. Home is reused from V1; the remaining captures show user-authorized local placeholder pages. Their text is represented by neutral glyphs; app controls and numeric counters were not modified. Image 2 uses a blue-gray page, image 3 uses actual night reading paper, image 4 shows the actual site blocking panel, and image 5 uses actual sepia reading paper.

System chrome crop: [0, 111, 1084, 2350]. All cropped content is scaled proportionally. No app source changes were needed.

| Order | Source | Title | Subtitle |
| --- | --- | --- | --- |
| 1 | source/harmony-phone-v2/zh-Hans/01-home.jpeg | 安静浏览 | 常用网站，一触即达 |
| 2 | source/harmony-phone-v2/zh-Hans/02-open-options.png | 按需打开 | 清洁、私密，随心选择 |
| 3 | source/harmony-phone-v2/zh-Hans/03-reader-controls.png | 阅读随心 | 字号、行距、纸色可调 |
| 4 | source/harmony-phone-v2/zh-Hans/04-site-blocking.png | 拦截可见 | 本站请求，一目了然 |
| 5 | source/harmony-phone-v2/zh-Hans/05-reader-mode.png | 专注阅读 | 开启阅读模式，少些干扰 |

Only five submission images are in the target folder. Contact sheets live under previews. Tablet and PC/2in1 remain outside scope.

```bash
uv run --no-project --with pillow python app-store-assets/render_store_screenshots.py
```
