---
name: app-icon
description: 设计并生成 iOS App 图标（1024×1024 的 light / dark / tinted 三张 PNG），渲染对比图给用户挑，选定后装进 Xcode 的 AppIcon 资源并在模拟器里检查。做图标、改图标、换图标颜色时用。
---

# App 图标

图标用代码画（SVG），再渲染成 PNG。这样边缘清晰、颜色精确、随时能改，比让图片模型生成更适合 App 图标。
Claude 不能直接生成位图，也不需要：图标本来就该是简单的几何形状。

## 工具（都在 tools/icon 里）

- `concepts.mjs`：每个方案一个函数，传入 light / dark / tinted 返回 SVG 文字。加方案就在这里加。
- `build_icon.mjs`：渲染全部方案到 `tools/icon/out/`，并拼一张 `contact-sheet.png` 对比图；
  `--install <方案名>` 把三张图装进 `FoodTracker/FoodTracker/Assets.xcassets/AppIcon.appiconset` 并写好 Contents.json。
- 渲染库 `sharp`（github.com/lovell/sharp，Node 图片处理库里星星最多的，内置 SVG 渲染），第一次用先在 tools/icon 里 `npm install`。
  `node_modules` 和 `out` 不进 git。

参考过的开源项目（画图案找灵感、看线条粗细和比例）：lucide-icons/lucide、tabler/tabler-icons、tailwindlabs/heroicons。
它们是界面用的线条图标，不要直接拿来当 App 图标：App 图标要粗、要满、一眼能认；自己画形状也避开授权问题。

## 苹果的规则（违反会被审核打回或显示不对）

- light 版：铺满整个 1024×1024，不留透明，不自己切圆角，系统会切成超椭圆。
- dark 版：只画图案，背景透明；系统会在下面垫深色渐变。颜色可以比 light 版亮一点。
- tinted 版：只画白到灰的图案，背景透明；系统按用户选的颜色染色，所以自己不要上色。
- 图案放在中间约 80% 的范围内，四角会被切掉；细线在主屏幕 60 点大小时看不见，线条最细也要 30 像素以上。
- 不要用苹果的商标形状（比如苹果的 logo），也不要用别的品牌标志。
- iOS 26 有 Icon Composer 的 .icon 格式（液态玻璃分层图标）。1024 的 PNG 仍然被接受，系统会自动加玻璃效果；
  .icon 是以后的加分项，不是必需。

## 步骤

1. 先问清楚方向（颜色、气质、要不要文字），或者按 App 的定位出 3～4 个差异明显的方案。
2. 在 `concepts.mjs` 里写方案，每个方案支持三种 variant。
3. `cd tools/icon && node build_icon.mjs`，把 `out/contact-sheet.png` 发给用户（SendUserFile），说明每个方案的想法，等用户挑。
4. `node build_icon.mjs --install <方案名>`，编译、装进模拟器，回到主屏幕截图确认（浅色和深色外观各看一次），
   再在真机上装一次。
5. 提交时只提交 `concepts.mjs`、`build_icon.mjs`、`package.json`、`package-lock.json` 和 AppIcon.appiconset 里的三张 PNG。

## 检查清单

- 三张 PNG 都是 1024×1024；light 版没有透明像素；dark / tinted 版背景透明。
- 主屏幕 60 点大小下图案还认得出来；深色模式下不刺眼。
- 和 App Store 里同类 App 的图标放在一起不会混淆。
