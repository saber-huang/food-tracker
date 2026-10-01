# Kindbite（一拍即食）设计规范

这份文件是 App 界面的「总规范」：以后改界面、加页面，先看这里。
某个页面需要例外时，在 `pages/<页面名>.md` 里单独写，那一页以那份为准。
所有数值都写在代码里：`FoodTracker/FoodTracker/Shared/DesignSystem.swift`（AppColors、AppSpacing、AppRadius、AppTypography、AppBackground 和几个小组件）。
颜色对比度由 `FoodTrackerTests/DesignSystemTests.swift` 检查。

## 方向

warm minimal · calm · organic · premium · iOS-native。每天会打开很多次的饮食记录，要让人愿意长期用，而不是第一眼很炫。

- **背景也是设计的一部分**：暖白燕麦色的底，顶部略亮，首页主卡片背后有一团很淡的光。不用大面积纯白、不用纹理图片。
- **卡片分区，但有层级**：主卡片最大、有很轻的阴影；普通卡片没有阴影，靠和背景的底色差分出来；次要信息（小链接、说明）可以不放卡片。
- **一种绿色**：所有选中、主按钮、可以点的文字都用深橄榄绿。营养素颜色只给数据图形。
- **先数据，后品牌**：首页的大数字是第一眼看到的东西；碗（App 图标）只是数字旁边的点缀。
- **超过目标不用红色**：多吃了只用灰色写出多了多少；碗也只是满碗。

## 三个标签页共用的结构

| 标签 | 第一眼（主卡片） | 主要动作 | 内容卡片 |
|------|------------------|----------|----------|
| 今日 | 还可以吃多少（42pt 大数字） | 快速记录：拍照 | 今日饮食：早餐 / 午餐 / 晚餐 / 加餐各一张卡片 |
| 食谱 | 每日目标摘要 → 今日推荐 | 生成 / 重新生成一日三餐 | 早餐 / 午餐 / 晚餐各一张食谱卡片；饮食偏好 |
| 我的 | 每日目标（42pt 大数字） | 编辑资料 | 个人资料、目标与活动、设置、隐私与数据、关于 |

每一页：大标题 30pt（今日的顶部是日期栏）→ 主卡片 → 块标题 + 卡片。左右留白 20，卡片圆角 26，块与块之间 28。

## 颜色（AppColors）

| 名称 | 浅色 | 深色 | 用在哪 |
|------|------|------|--------|
| background | `#F7F4EE` | `#12110F` | 页面底色 |
| backgroundTop | `#FBF9F5` | `#191714` | 页面顶部、日期栏 |
| surfacePrimary | `#FFFDF9` | `#1E1C19` | 卡片 |
| surfaceSecondary | `#F0E9DE` | `#2A2621` | 图标的圆底（次要按钮、餐次） |
| surfaceMuted | `#EBE6DE` | `#2C2924` | 进度条底槽 |
| divider | `#E6E0D7` | `#2E2A25` | 卡片里很淡的分隔线 |
| textPrimary | `#262522` | `#F2EEE7` | 正文、数字 |
| textSecondary | `#777169` | `#A8A196` | 说明、标签 |
| textTertiary | `#AAA39A` | `#6F6961` | 小箭头、不能点的未来日期 |
| brand 橄榄绿 | `#4F624D` | `#6E8B6A` | 主按钮、选中、可以点的文字（= AccentColor） |
| brandDeep | `#354A38` | `#C3D3B9` | 选中的标签栏文字 |
| brandSoft | `#E7E9DF` | `#2B3128` | 选中的标签栏底色（80%）、「+」的圆底 |
| onBrand | `#FAF7F1` | `#FAF7F1` | 主色上面的字和图标 |
| iconSecondary | `#756B5E` | `#B5AA9A` | 次要图标 |
| tabInactive | `#8D887F` | `#8D887F` | 标签栏没选中的图标和文字 |
| 燕麦（碗身/碗沿/空碗/小进度条） | `#DED2BF` / `#BDAD95` / `#F1EBE1` / `#A8957A` | `#B9AC96` / `#8F826E` / `#2E2A25` / `#A39680` | 碗、日期下的小进度条 |
| 三餐标签底（早/午/晚） | `#F4ECDF` / `#E9EEE4` / `#ECE7E3` | `#2F2A23` / `#262C24` / `#2B2725` | 食谱卡片上的餐次小标签 |
| destructive | `#A54A3F` | `#E08A7E` | 删除所有数据（柔和的砖红） |
| 蛋白质 / 碳水 / 脂肪 | `#9AC0A0` / `#AF874D` / `#8D585A` | `#94BD9C` / `#A97D3A` / `#86495A` | 只给进度条、小色条、小圆点 |

**和 WCAG 4.5:1 的两处出入（用户指定的颜色）**：次要文字 `#777169` 放在页面底色上是 4.4:1（卡片上 4.75:1）；标签栏没选中 `#8D887F` 是 3.5:1（图标 ≥ 3:1）。测试守住不再更低。

**营养素三色**用 dataviz 技能的 `validate_palette.js` 搜出来：饱和度低，色盲模拟下两两 ΔE ≥ 13（浅色）/ 15（深色）。旁边一直有文字名称，不靠颜色区分。

## 间距、圆角、阴影

- 间距只用 4 / 8 / 12 / 16 / 20 / 24 / 32。页面左右 20；同一块里卡片之间 12；两大块之间 28（块标题上方补足）；卡片内 18；主卡片内 22。
- 圆角：所有卡片 26（和系统列表卡片一样）；标签栏 32；照片缩略图 14；小标签 8。
- 阴影：只有主卡片（今日的热量卡片、我的的每日目标）和悬浮标签栏有很轻的暖色阴影（5%，模糊 22，下移 6）。其他卡片没有阴影。

## 字体（AppTypography）

- 文字用系统字体（中文是苹方）；数字用系统圆体。
- 页面大标题 30pt 粗体；主卡片大数字 42pt 半粗圆体，字距 +0.6；食谱卡片的热量 26pt、每日目标摘要 28pt（都跟着系统字号变）。
- 块标题 17pt 半粗；餐次标题 17pt 半粗；菜名 20pt 半粗；食物名称 16pt 中等；说明 13pt；最小说明 12pt。
- 不到处用粗体：层级靠字号和颜色。

## 组件

| 组件 | 文件 | 说明 |
|------|------|------|
| AppBackground、appCard、appCardRow、appListBackground、appBottomBar | Shared/DesignSystem.swift | 背景、卡片、列表卡片的行、底部固定条 |
| AppSectionHeader、AppSectionHeaderWithAction | Shared/DesignSystem.swift | 块标题（右边小字 / 右边按钮「编辑」） |
| AppPressStyle | Shared/DesignSystem.swift | 统一的按下反馈：缩到 0.98、透明度 0.94、0.12 秒，不弹跳；列表的整行只变淡 |
| AppChevron、AppIconTile | Shared/DesignSystem.swift | 统一的小箭头；燕麦色圆底 + 描边图标 |
| DateStrip | DateBrowsing/DateStrip.swift | 今日顶部的日期栏 |
| NutritionHeroCard、MacroProgress、SlimProgressBar | DietLog/NutritionHeroCard.swift | 今日的主卡片 |
| BowlGauge、KindbiteMark | DietLog/BowlGauge.swift | 碗形进度、图标图案 |
| QuickLogDock | DietLog/QuickLogDock.swift | 快速记录：拍照（56pt 橄榄绿圆 + 文字）是主要动作，相册、手动（42pt 燕麦色圆）是次要动作 |
| MealCardHeader、MealRow、EmptyMealCard | DietLog/MealCard.swift | 今日饮食：每一餐一张卡片；没记录的一餐点 + 直接给这一餐手动添加 |
| RecipeGoalSummary、RecipeCard、RecipeCardFooter、EmptyRecipesCard、RegenerateButton、PreferenceSummary、MealSlotTag | Recipes/RecipeCards.swift | 食谱页 |
| GoalHeroCard、ProfileInfoRow | Profile/GoalHeroCard.swift | 我的：每日目标主卡片、资料行（至少 56pt 高） |
| MacroStat、MacroStatsRow | Profile/TargetsViews.swift | 三种营养素的目标（食谱和我的共用）；最大字号时改成上下三行 |
| FloatingTabBar、AppTab | Shared/FloatingTabBar.swift | 悬浮标签栏；选中的底比格子窄一点、淡一点 |

## 不要做

- 不用纯黑 `#000000`、不用大面积纯白、不用第二种绿色当按钮或选中。
- 不用明显的渐变、强阴影、到处都是的毛玻璃；不用表情符号当图标（用 SF Symbols，描边风格）。
- 不给每张卡片都加阴影；不在一个页面放两个实心主按钮。
- 营养素颜色不给文字用；数字一律用正文颜色。
- 不在页面里直接写颜色和数字：新颜色先加到 DesignSystem.swift，再在这份文件里登记。

## 交付前检查（第二轮都做过）

- [x] 尺寸：iPhone SE（375×667）、iPhone 17（402×874）、iPhone 18 Pro Max（440×956）。
- [x] 字号：默认和辅助功能特大都看过；最大字号时营养素改成上下三行，底部的 AI 提示最多放大到「特特大」。
- [x] 长中文：36 个字的菜名换两行、很长的偏好文字两行后「…」，都不溢出。
- [x] 标签栏不挡内容：标签栏放在页面下面，三个标签页滑到底时最后一张卡片都完整露出来。
- [x] 交互：拍照、相册、手动、点 + 给某一餐添加（默认选中那一餐）、点记录修改、左滑删除、ⓘ、食谱卡片打开详情、换一个、编辑资料、这些目标是如何计算的。
- [x] 深色模式、英文界面（启动参数 `-AppleLanguages "(en)" -AppleLocale en_US`）。
- 模拟器专用：启动参数 `-startTab recipes|profile` 直接打开某个标签；食谱页右上角「调试」→「用示例食谱」不花钱就能看食谱卡片。

## 这份规范是怎么来的

- 用户的两轮设计稿：第一轮定下暖白燕麦底、橄榄绿、主卡片、快速记录、悬浮标签栏；第二轮精修层级（先数据后品牌、拍照是主功能、今日饮食卡片化、食谱和我的重新组织、三个标签统一）。参考了 Canvas 和不背单词。
- **frontend-design**：只有一个招牌（碗），其余保持安静；避开 AI 设计常见的「奶油底 + 衬线字 + 陶土色」。
- **ui-ux-pro-max**：点击范围 ≥ 44pt、对比度、安全区域、按下反馈、减弱动态效果、Dynamic Type。
- **dataviz**：数字用正文颜色、颜色只给图形；营养素配色用校验脚本算过。
