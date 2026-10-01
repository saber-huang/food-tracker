# Kindbite（一拍即食）设计规范

这份文件是 App 界面的「总规范」：以后改界面、加页面，先看这里。
某个页面需要例外时，在 `pages/<页面名>.md` 里单独写，那一页以那份为准。
所有数值都写在代码里：`FoodTracker/FoodTracker/Shared/DesignSystem.swift`（AppColors、AppSpacing、AppRadius、AppTypography、AppBackground）。
颜色对比度由 `FoodTrackerTests/DesignSystemTests.swift` 检查。

## 方向

warm minimal · calm · organic · iOS-native。每天会打开很多次的饮食记录，要让人愿意长期用，而不是第一眼很炫。

- **背景也是设计的一部分**：暖白燕麦色的底，顶部略亮，主卡片背后有一团很淡的光。不用大面积纯白、不用纹理图片。
- **卡片分区**：暖白卡片放在燕麦色背景上，靠底色差、留白和很轻的暖色阴影分层，不靠描边。
- **一种绿色**：所有选中、主按钮、可以点的文字都用深橄榄绿。营养素颜色只给数据。
- **品牌元素是那只碗**：主卡片里的碗就是 App 图标里的碗，吃了几成装几成；它只是点缀，视觉重点是数字。
- **超过目标不用红色**：多吃了只用灰色写出多了多少；碗也只是满碗。

## 颜色（AppColors）

| 名称 | 浅色 | 深色 | 用在哪 |
|------|------|------|--------|
| background | `#F7F4EE` | `#12110F` | 页面底色 |
| backgroundTop | `#FBF9F5` | `#191714` | 页面顶部、日期栏 |
| surfacePrimary | `#FFFDF9` | `#1E1C19` | 卡片 |
| surfaceSecondary | `#F0E9DE` | `#2A2621` | 次要按钮的圆底 |
| surfaceMuted | `#EBE6DE` | `#2C2924` | 进度条底槽 |
| divider | `#E6E0D7` | `#2E2A25` | 两餐之间的分隔线 |
| textPrimary | `#262522` | `#F2EEE7` | 正文、数字 |
| textSecondary | `#6F695F` | `#A8A196` | 说明、标签、未选中的标签栏 |
| textTertiary | `#AAA39A` | `#6F6961` | 只给不能点的未来日期 |
| brand 橄榄绿 | `#4F624D` | `#6E8B6A` | 主按钮、选中、可以点的文字（= AccentColor） |
| brandDeep | `#354A38` | `#C3D3B9` | 选中的标签栏文字 |
| brandSoft | `#E7E9DF` | `#2B3128` | 选中的标签栏底色 |
| onBrand | `#FAF7F1` | `#FAF7F1` | 主色上面的字和图标 |
| iconSecondary | `#756B5E` | `#B5AA9A` | 次要按钮的图标 |
| 燕麦（碗身/碗沿/空碗/小进度条） | `#DED2BF` / `#BDAD95` / `#F1EBE1` / `#A8957A` | `#B9AC96` / `#8F826E` / `#2E2A25` / `#A39680` | 碗形进度、日期下的小进度条 |
| 蛋白质 鼠尾草绿 | `#9AC0A0` | `#94BD9C` | 只给进度条、小色条 |
| 碳水 燕麦黄 | `#AF874D` | `#A97D3A` | 只给进度条、小色条 |
| 脂肪 灰玫瑰 | `#8D585A` | `#86495A` | 只给进度条、小色条 |

**和设计稿不一样的两处（为了对比度）**：

- 次要文字设计稿是 `#777169`，在页面底色上只有 4.4:1，小字要 4.5:1，所以深了一点点，用 `#6F695F`（4.95:1）。
- 标签栏未选中设计稿是 `#8D887F`，只有 3.5:1，标签栏的字很小，所以也用 `#6F695F`。

**营养素三色**是用 dataviz 技能的 `validate_palette.js` 搜出来的：饱和度低（OKLCH C ≈ 0.06–0.09），三种颜色亮度拉开，色盲模拟下两两 ΔE ≥ 13（浅色）/ 15（深色），正常视力 ΔE ≥ 15。浅色模式的蛋白质条只有 2:1，但旁边一直写着「蛋白质」和数字，不靠颜色区分。

## 间距、圆角（AppSpacing、AppRadius）

- 间距只用 4 / 8 / 12 / 16 / 20 / 24 / 32。
- 页面左右留白 20，两块内容之间 28，卡片内留白 20。
- 圆角：主卡片 30，快速记录 26，标签栏 32，照片缩略图 14。列表分组的圆角是系统默认（约 26），和主卡片接近。

## 字体（AppTypography）

- 文字用系统字体（中文是苹方）；数字用系统圆体，和「健康」App 一样，一眼看出哪些是数字。
- 首页大数字：40pt 半粗圆体（@ScaledMetric，跟着系统字号变）。
- 大数字下的说明：15pt 中等。块标题（快速记录、今日饮食）：17pt 半粗。
- 食物名称：16pt 中等。说明：13pt。卡片里的数字：15pt 半粗圆体。
- 不到处用粗体：层级靠字号和颜色。

## 首页结构

```
日期栏（月份 ⌄ · 一周的日期，选中=橄榄绿实心圆，今天=橄榄绿细圈，下面一条小进度条）
主卡片 NutritionHeroCard（今天 ⓘ / 大数字 + 千卡可摄入 / 碗 / 已摄入 · 目标 / 三大营养素细进度条）
快速记录 QuickLogDock（拍照=主要动作 · 相册 · 手动；选了照片多一行缩略图 + 开始识别）
热量提示（有时才出现）
今日饮食（一张卡片，按餐分组：早餐 / 午餐 / 晚餐 / 加餐）
悬浮标签栏 FloatingTabBar（今日 · 食谱 · 我的）
```

## 组件（文件）

| 组件 | 文件 | 说明 |
|------|------|------|
| AppBackground、appCard、appListBackground、appBottomBar、AppSectionHeader | Shared/DesignSystem.swift | 背景、卡片、块标题 |
| DateStrip、IntakeMark | DateBrowsing/DateStrip.swift | 日期栏 |
| NutritionHeroCard、MacroProgress、SlimProgressBar | DietLog/NutritionHeroCard.swift | 主卡片 |
| BowlGauge、KindbiteMark | DietLog/BowlGauge.swift | 碗形进度、图标图案 |
| QuickLogDock、QuickLogPressStyle | DietLog/QuickLogDock.swift | 快速记录；按下去缩到 0.97、变淡 |
| MealRow、MealHeaderRow、EmptyMealsRow | DietLog/MealRow.swift | 今日饮食 |
| FloatingTabBar、AppTab | Shared/FloatingTabBar.swift | 悬浮标签栏（系统标签栏藏起来） |

「食谱」「我的」、识别结果、怎么算的这几页也换成同样的燕麦色背景和暖白卡片，切换标签时看起来是同一个 App。

## 不要做

- 不用纯黑 `#000000`、不用大面积纯白、不用第二种绿色当按钮或选中。
- 不用明显的渐变、强阴影、到处都是的毛玻璃；不用表情符号当图标（用 SF Symbols，描边风格）。
- 营养素颜色不给文字用；数字一律用正文颜色。
- 一个页面最多一个实心主按钮。
- 不在页面里直接写颜色和数字：新颜色先加到 DesignSystem.swift，再在这份文件里登记。

## 交付前检查（这次都做过）

- [x] 三种尺寸：iPhone SE（375×667，没有底部安全区域）、iPhone 17、iPhone 18 Pro Max。
- [x] 安全区域：日期栏在刘海 / 灵动岛下面；标签栏比底部安全区域再高 8pt，SE 上也不贴底。
- [x] 标签栏不挡内容：标签栏放在页面下面，列表滑到底时最后一行完整停在它上面。
- [x] 长数据：很长的食物名最多两行、千卡数始终完整；四位数的千卡、超过目标 1,000 多千卡都放得下。
- [x] 字号：最小、默认、最大（辅助功能特大）三档都看过；大字号时碗、统计、营养素改成上下排。
- [x] 对比度：所有文字 ≥ 4.5:1（DesignSystemTests 检查），深色模式也查过。
- [x] 点击范围：快速记录每个动作约 120×72pt，标签栏每项 ≥ 54pt 高，日期格约 55×64pt，ⓘ、月份、回到今天、移除照片都 ≥ 44×44。
- [x] 功能：拍照打开相机、相册选照片后出现「开始识别」、手动打开表单、点记录能改、左滑能删、ⓘ 打开「怎么算的」、月份打开月历、往日显示「回到今天」和「记录到 9月28日 周一」。
- [x] 英文界面（启动参数 `-AppleLanguages "(en)" -AppleLocale en_US`）。

## 这份规范是怎么来的

- 用户给的设计稿（暖白燕麦底、橄榄绿、Hero 卡片、快速记录、悬浮标签栏），参考了 Canvas、不背单词和一张水彩背景的 App 截图。
- **frontend-design**：只有一个招牌（碗），其余保持安静；避开 AI 设计常见的「奶油底 + 衬线字 + 陶土色」。
- **ui-ux-pro-max**：点击范围 ≥ 44pt、对比度、安全区域、按下反馈、减弱动态效果。
- **dataviz**：数字用正文颜色、颜色只给图形；营养素配色用校验脚本算过。
