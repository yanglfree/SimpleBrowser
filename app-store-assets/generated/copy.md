# Store Screenshot Copy

Revision: V3. Template: spotlight-card. Targets: HarmonyOS AGC phone and tablet. The phone set is zh-Hans at 1080 x 1920. The tablet set is zh-Hans and English at 2730 x 1820. The phone target contains five PNG images and each tablet locale contains four PNG images under 5 MB each.

The template was changed from focus-callout after quality feedback to make the main screenshots larger and eliminate duplicated overlays. Captures show the real installed 1.0.1 (1000001) app. Home is reused from V1; the remaining captures show user-authorized local placeholder pages. Their text is represented by neutral glyphs; app controls and numeric counters were not modified. Image 2 uses a blue-gray page, image 3 uses actual night reading paper, image 4 shows the actual site blocking panel, and image 5 uses actual sepia reading paper.

System chrome crop: [0, 111, 1084, 2350]. All cropped content is scaled proportionally. No app source changes were needed.

| Order | Source | Title | Subtitle |
| --- | --- | --- | --- |
| 1 | source/harmony-phone-v2/zh-Hans/01-home.jpeg | 安静浏览 | 常用网站，一触即达 |
| 2 | source/harmony-phone-v2/zh-Hans/02-open-options.png | 按需打开 | 清洁、私密，随心选择 |
| 3 | source/harmony-phone-v2/zh-Hans/03-reader-controls.png | 阅读随心 | 字号、行距、纸色可调 |
| 4 | source/harmony-phone-v2/zh-Hans/04-site-blocking.png | 拦截可见 | 本站请求，一目了然 |
| 5 | source/harmony-phone-v2/zh-Hans/05-reader-mode.png | 专注阅读 | 开启阅读模式，少些干扰 |

## Tablet copy

The tablet source set contains real landscape captures from a Huawei MatePad Pro running ZhuoBrowser 1.0.1. System status chrome is cropped at y=86; the app UI is scaled proportionally inside a generic tablet outline. The captures retain the original app and web content. Contact sheets live under `generated/previews/` and are not submission assets.

| Order | Source | 中文主标题 | 中文副标题 | English title | English subtitle |
| --- | --- | --- | --- | --- | --- |
| 1 | source/harmony-tablet/zh-Hans/01-home.png | 大屏浏览 | 横屏空间，尽情展开 | Browse bigger | Built for landscape |
| 2 | source/harmony-tablet/zh-Hans/02-search.jpeg | 搜索尽览 | 结果更宽，信息更多 | See more results | More context at once |
| 3 | source/harmony-tablet/zh-Hans/03-library-search.jpeg | 文章随查 | 正文与笔记都能搜索 | Find any article | Search text and notes |
| 4 | source/harmony-tablet/zh-Hans/04-history-control.jpeg | 隐私可控 | 按类型与时间清理 | Privacy controls | Clear by type and time |
Only final submission images are stored in the phone and tablet target folders. PC/2in1 screenshots remain unavailable because no real 2in1 device capture has been completed.

```bash
uv run --no-project --with pillow python app-store-assets/render_store_screenshots.py
```
