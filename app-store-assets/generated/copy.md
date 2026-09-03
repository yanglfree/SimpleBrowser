# Store Screenshot Copy

Template: focus-callout. Locale: zh-Hans only. Target: HarmonyOS AGC phone, portrait 1080 x 1920 PNG, three images under 5 MB each.

Real screenshots were captured from the installed 1.0.1 app. System status and gesture bars are cropped; in-app navigation remains. Each magnified region is taken from the same screenshot. Image 3 focuses on the actual reader controls. No third-party article or invented interface was used.

| Order | Source | Title | Subtitle |
| --- | --- | --- | --- |
| 1 | source/harmony-phone/zh-Hans/01-home.jpeg | 安静浏览 | 常用网站，一触即达 |
| 2 | source/harmony-phone/zh-Hans/02-open-options.jpeg | 按需打开 | 清洁、私密，随心选择 |
| 3 | source/harmony-phone/zh-Hans/03-reader.jpeg | 自在阅读 | 字号、行距，随你调整 |

Natural narrative order: home access, external-link choices, reading controls. Tablet and PC/2in1 exports are blocked pending current-version screenshots. Contact sheets are preview-only. Dimensions and byte sizes are recorded in manifest.json.

Render again with:

```bash
uv run --no-project --with pillow python app-store-assets/render_store_screenshots.py
```
