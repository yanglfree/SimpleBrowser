# Zhuo浏览器 · Mac 应用图标与品牌方案

版本 1.0.0 · 2026 · macOS 14+

## 1. 命名

| 场景 | 写法 |
|------|------|
| 中文完整名称 | `Zhuo浏览器`（拉丁 `Z` 大写，与「浏览器」之间不留空格） |
| 英文名称 | `Zhuo Browser` |
| 工程 / 文件名 | `ZhuoBrowser`、`ZhuoBrowserMac` |
| 品牌短称 | `Zhuo` |

`Zhuo` 是品牌主词，`浏览器` 是品类说明。两者永远作为一个整体出现，不拆成「Zhuo 浏览器」或「卓浏览器」。

## 2. 概念

> 一页纸，一个字母，一条地平线。

- **Z 是折页。** 三段笔画不是几何字母，而是一张纸被折起后留下的边：上缘、折痕、落点。它同时是品牌首字母和「翻页」这个浏览器最古老的动作。
- **地平线是页边。** 图标下缘一条低对比度的弧线，既是纸张的边缘，也是窗口之外的那片网络。它在 128 px 以上出现，小于 128 px 主动消失，为字形让路。
- **墨绿是安静的界面。** 沿用 `DESIGN.md` 的 ink-green `#2E6B5C` 与暖纸 `#FAF9F7`，让图标、界面和落地页共享同一种气质：留白、克制、可长时间阅读。

这套图形不依赖浏览器控件（地址栏、标签、地球）来表意。它先是一个可信的品牌字母，其次才是一个浏览器图标——这与 Safari 的罗盘、Arc 的彩虹是同一种策略：先建立符号，再让产品赋予它含义。

## 3. 图形构成

以 1024 × 1024 画布为准：

| 元素 | 规格 |
|------|------|
| 图标主体 | 824 × 824，居中于 (100, 100)，圆角 185（macOS 标准安全区） |
| 主体材质 | 垂直渐变 `#3E8C79 → #2E6B5C → #1B473D`，左上 16% 白色柔光 |
| Z 字形 | 三笔连续路径，笔画 108，圆头圆角，端点 (378,336)→(652,336)→(378,656)→(652,656) |
| Z 材质 | 纸白渐变 `#FFFFFF → #F0E9DB`，与主体形成最大对比 |
| 地平线 | 13 宽弧线，纸白 32% 透明，横贯主体下缘 y≈672–792 |
| 内圈高光 | 4 宽、12% 白色内描边，只在边缘出现，避免图标发灰 |

**为什么是圆头笔画**：在 16–32 px 时，圆头端点比平头保留更多像素，字形的「Z」不会碎成三段短线。折角同样使用圆角连接，避免 1 px 渲染下的锯齿。

**为什么不用描边圆环 / 罗盘**：概念稿中的 01（开口圆环）、07（罗盘）都更「浏览器」，但在 16 px 下圆环退化成噪点。最终方案把「浏览器」信息交给地平线与命名，把有限的分辨率全部留给 Z。

## 4. 配色

| 角色 | 色值 | 用途 |
|------|------|------|
| Ink Green | `#2E6B5C` | 品牌主色、图标主体中段、界面强调色 |
| Deep Green | `#1B473D` | 图标底部、深色模式压力测试 |
| Light Green | `#3E8C79` | 图标顶部受光面 |
| Paper | `#FAF9F7` | 图标字形、界面页底 |
| Warm Paper | `#F0E9DB` | 字形暗部、纸本展示背景 |
| Ink | `#1A1A18` | 正文与字标 |
| Dark Accent | `#84A794` | 深色模式下的可选强调色 |
| Border | `#E5E2DB` | 1 px 分隔线、卡片边界 |

绿色只承担「品牌」与「可交互」两种语义，不用于装饰性填充。图标内部不使用第三种颜色。

## 5. 尺寸适配

`.icns` 不是把 1024 缩放到每个槽位，而是三套光学版本：

| 槽位 | 源文件 | 处理 |
|------|--------|------|
| 256 / 512 / 1024 | `zhuo-app-icon.svg` | 完整版：渐变 + 地平线 |
| 64 / 128 | `zhuo-app-icon-small.svg` | 去掉地平线，Z 放大约 5%，主体渐变收窄 |
| 16 / 32 | `zhuo-app-icon-micro.svg` | 纯色主体，Z 放大约 14%，无渐变、无高光 |

小尺寸不是「更小的同一张图」，而是重新配平：笔画在总宽度中的占比从 13.1% 提升到 15.1%，保证 16 px 下仍有约 1.9 px 的有效笔画。

**使用下限**：应用图标不小于 16 px；网页 favicon 使用 micro 版本；菜单栏若使用模板图标，只保留 Z 单色形状，不叠加地平线。

## 6. 品牌留白与禁用

- **留白**：图标主体外保留画布 9.8%（100 px）的安全区；在版式中，图标四周至少留出图标宽度的 1/8。
- **不要**把 Z 单独抽出来当作应用图标（缺少墨绿主体时对比度不足）。
- **不要**在图标内加文字、地址栏、地球或第二个字母。
- **不要**改变 Z 的角度、拉宽比例或改用斜体。
- **不要**把地平线加回 32 px 以下的版本。
- **不要**在彩色照片或高噪点背景上直接放图标；展示时必须留出纯净背景。

## 7. 改名后的品牌一致性

改名不是替换一个字符串，而是让所有「用户能读到产品名」的入口指向同一个名字和同一个符号。

### 已落地（macOS）

| 位置 | 文件 | 处理 |
|------|------|------|
| Dock / Finder / 关于面板 | `ZhuoBrowserMac/Info.plist` | `CFBundleName` 与 `CFBundleDisplayName` = `Zhuo浏览器`；`CFBundleIconName` = `AppIcon` |
| 菜单栏应用菜单 | 同上 | App 菜单标题读取 `CFBundleName`，不再是 `ZhuoBrowserMac` |
| 关于面板图标 | `Assets.xcassets/AppIcon.appiconset` | 10 个槽位的 `.icns` 源，构建后生成 `AppIcon.icns` |
| 起始页字标 | `UI/MinimalStartView.swift` | 「卓阅」→「Zhuo浏览器」；Safari 系统符号 → 品牌 `ZhuoMark` 模板图标 |
| 设置 · 关于 | `UI/SettingsView.swift` | 「关于卓阅 (ZhuoBrowser)」→「关于 Zhuo浏览器」 |
| 窗口菜单 / 调度中心 | `UI/MainWindowView.swift` | 首页窗口标题为 `Zhuo浏览器`，网页标签使用页面标题 |
| 全局强调色 | `Assets.xcassets/AccentColor.colorset` | 浅色 `#2E6B5C`、深色 `#84A794`，替换系统蓝 |
| 图标资源 | `Assets.xcassets/ZhuoMark.imageset` | 模板渲染，随壁纸自动变白 / 墨绿 |

> `PRODUCT_NAME` 仍保留 `ZhuoBrowserMac`，它只是构建产物与可执行文件的内部名；用户可见的名称来自 `CFBundleDisplayName` / `CFBundleName`。如果要把 Finder 里的 `.app` 文件名也改成 `Zhuo浏览器.app`，必须同时修改 `run_release.sh`、签名脚本和更新源路径，不能只改 `PRODUCT_NAME`。

### 后续需要同步的入口

1. **官网与下载页**：标题、`<title>`、OG 图、favicon（micro 图标）、页脚版权名统一为 `Zhuo浏览器`。
2. **安装包与更新源**：DMG 卷标、`appcast.xml` 的 `title`、更新弹窗文案。`PRODUCT_NAME` / bundle id 保持不变，避免破坏签名与更新链路。
3. **账号与云同步**：登录页、邮件模板、隐私协议中的产品名。协议改名需要版本号与生效日期，不能只改标题。
4. **崩溃与日志**：`CFBundleName` 会进入崩溃报告；改名后旧报告仍显示旧名，属正常历史数据，不要回写。
5. **iOS / Android / HarmonyOS**：桌面名称、应用内「关于」、商店 listing 使用同一套字标与图标；各平台图标按本方案的 824/1024 安全区重新裁切，不要直接复用 macOS 圆角图。
6. **搜索与帮助**：帮助中心标题、客服话术、README 首行。保留一次「原卓阅」的说明即可，不要长期并列两个品牌。

### 一致性检查清单

- [ ] `CFBundleName`、`CFBundleDisplayName`、App 菜单、关于面板四处名称一致
- [ ] Dock、Finder、关于面板、通知四处图标一致
- [ ] 起始页字标与图标同时出现，且字号比例稳定（图标 58 pt / 字标 30 pt）
- [ ] 所有可点击控件的强调色来自 `AccentColor`，不出现系统蓝
- [ ] 窗口标题不为空，且首页不显示「新标签页」作为产品名
- [ ] 官网页、商店页、安装包、更新源使用同一名称与同一图标版本
- [ ] 旧名只出现在迁移说明中，不出现在主界面

## 8. 资源与构建

```
branding/zhuo-browser/
  zhuo-app-icon.svg          1024 主图标（完整版）
  zhuo-app-icon-small.svg    64–128 光学版
  zhuo-app-icon-micro.svg    16–32 光学版
  zhuo-mark.svg              界面用单色标记（模板渲染）
  variants/                  8 个概念方向
  showcase/                  4 个展示场景（SVG 源）
  dist/
    Zhuo.icns                可直接拖入项目的图标
    Zhuo.iconset/            iconutil 输入
    png/                     各尺寸 PNG 与 ZhuoMark
    variants/                概念稿 PNG（墨绿）
    showcase/                1600 × 900 展示图
  showcase.html              方案展示页
  build-icons.py             从 SVG 重建 iconset / icns / PNG
```

重建图标：

```bash
cd branding/zhuo-browser
DYLD_LIBRARY_PATH=/opt/homebrew/opt/cairo/lib python3 build-icons.py
```

展示场景的 PNG 使用 Chrome 无头渲染，以保证中文系统字体（PingFang SC）与 SVG 滤镜一致：

```bash
"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
  --headless=new --hide-scrollbars --force-device-scale-factor=1 \
  --window-size=1600,900 --screenshot=dist/showcase/zhuo_frosted.png \
  file:///path/to/scene.html
```
