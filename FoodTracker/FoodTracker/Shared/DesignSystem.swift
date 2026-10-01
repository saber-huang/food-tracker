//
//  DesignSystem.swift
//  FoodTracker
//
//  App 的设计规范写成代码：颜色（AppColors）、间距（AppSpacing）、圆角（AppRadius）、字体（AppTypography），
//  再加上页面背景（AppBackground）和卡片样式。各个页面只从这里取值，不在页面里直接写颜色和数字。
//  为什么这样选、每样东西用在哪里，见仓库里的 design-system/kindbite/MASTER.md；
//  颜色的对比度由 DesignSystemTests.swift 检查。
//

import SwiftUI
import UIKit

/// 一种颜色在浅色、深色模式下的两个值（0xRRGGBB）。单独存数字，测试可以直接算对比度
nonisolated struct ColorPair: Sendable {
    let light: UInt32
    let dark: UInt32
}

// MARK: - 颜色

enum AppColors {
    /// 所有颜色的数值（浅色 / 深色）
    nonisolated enum Pair {
        // 页面和卡片：暖白、燕麦色，不用大面积纯白
        static let background = ColorPair(light: 0xF4F0E8, dark: 0x12110F)  // 页面底色：暖一点、灰一点，卡片更分得出来
        static let backgroundTop = ColorPair(light: 0xF9F6F0, dark: 0x191714)  // 页面顶部，比底色略亮
        static let surfacePrimary = ColorPair(light: 0xFFFDF9, dark: 0x1E1C19)  // 卡片
        static let surfaceSecondary = ColorPair(light: 0xF0E9DE, dark: 0x2A2621)  // 次要按钮的圆底
        static let surfaceMuted = ColorPair(light: 0xEBE6DE, dark: 0x2C2924)  // 进度条的底槽
        static let divider = ColorPair(light: 0xE6E0D7, dark: 0x2E2A25)

        // 文字：不用纯黑。次要文字按设计稿用 #777169：在卡片上 4.75:1，直接放在页面底色上 4.25:1
        // （略低于小字的 4.5:1；设计稿指定的颜色和底色，用户确认过）
        static let textPrimary = ColorPair(light: 0x262522, dark: 0xF2EEE7)
        static let textSecondary = ColorPair(light: 0x777169, dark: 0xA8A196)
        static let textTertiary = ColorPair(light: 0xAAA39A, dark: 0x6F6961)  // 对比度低，只给不能点的未来日期这类地方

        // 品牌主色：深橄榄绿。选中、主按钮、可以点的文字都用它，全 App 只有这一种绿
        static let brand = ColorPair(light: 0x4F624D, dark: 0x6E8B6A)
        static let brandDeep = ColorPair(light: 0x354A38, dark: 0xC3D3B9)  // 选中的标签文字
        static let brandSoft = ColorPair(light: 0xE7E9DF, dark: 0x2B3128)  // 选中的标签底色
        static let onBrand = ColorPair(light: 0xFAF7F1, dark: 0xFAF7F1)  // 主色上面的文字、图标（暖白）
        static let iconSecondary = ColorPair(light: 0x756B5E, dark: 0xB5AA9A)  // 次要按钮的图标
        static let tabInactive = ColorPair(light: 0x8D887F, dark: 0x8D887F)  // 标签栏没选中的图标和文字（设计稿指定）

        // 燕麦色：和 App 图标里的碗是同一组颜色
        static let oatBowl = ColorPair(light: 0xDED2BF, dark: 0xB9AC96)  // 碗身 = 已经吃了的部分
        static let oatRim = ColorPair(light: 0xBDAD95, dark: 0x8F826E)  // 碗沿
        static let oatEmpty = ColorPair(light: 0xF1EBE1, dark: 0x2E2A25)  // 碗里还空着的部分
        static let oatMark = ColorPair(light: 0xA8957A, dark: 0xA39680)  // 日期下面的小进度条（吃了几成）
        static let glow = ColorPair(light: 0xC9D2BE, dark: 0x3A4334)  // 主卡片背后很淡的一团光

        // 三大营养素：低饱和；只给进度条、小色条用，不给文字用（用 dataviz 的校验脚本挑过，色盲也分得开）
        static let protein = ColorPair(light: 0x9AC0A0, dark: 0x94BD9C)  // 鼠尾草绿
        static let carbs = ColorPair(light: 0xAF874D, dark: 0xA97D3A)  // 燕麦黄
        static let fat = ColorPair(light: 0x8D585A, dark: 0x86495A)  // 灰玫瑰

        // 识别结果的可信度小标签（字的颜色；底色是同一个颜色的 12%）
        static let confidenceHigh = ColorPair(light: 0x4F624D, dark: 0xA9C1A1)
        static let confidenceMedium = ColorPair(light: 0x7E5A22, dark: 0xD3AC6A)
        static let confidenceLow = ColorPair(light: 0x8D4A45, dark: 0xDD958C)

        // 三餐的小标签底色：很淡的燕麦、鼠尾草、灰褐，只用来区分是哪一餐
        static let tintBreakfast = ColorPair(light: 0xF4ECDF, dark: 0x2F2A23)
        static let tintLunch = ColorPair(light: 0xE9EEE4, dark: 0x262C24)
        static let tintDinner = ColorPair(light: 0xECE7E3, dark: 0x2B2725)

        static let destructive = ColorPair(light: 0xA54A3F, dark: 0xE08A7E)  // 删除：柔和的砖红，不用系统的大红

        static let shadow = ColorPair(light: 0x3B3428, dark: 0x000000)  // 阴影用暖色，不用纯黑
    }

    static let background = Color(Pair.background)
    static let backgroundTop = Color(Pair.backgroundTop)
    static let surfacePrimary = Color(Pair.surfacePrimary)
    static let surfaceSecondary = Color(Pair.surfaceSecondary)
    static let surfaceMuted = Color(Pair.surfaceMuted)
    static let divider = Color(Pair.divider)
    static let textPrimary = Color(Pair.textPrimary)
    static let textSecondary = Color(Pair.textSecondary)
    static let textTertiary = Color(Pair.textTertiary)
    static let brand = Color(Pair.brand)
    static let brandDeep = Color(Pair.brandDeep)
    static let brandSoft = Color(Pair.brandSoft)
    static let onBrand = Color(Pair.onBrand)
    static let iconSecondary = Color(Pair.iconSecondary)
    static let tabInactive = Color(Pair.tabInactive)
    static let oatBowl = Color(Pair.oatBowl)
    static let oatRim = Color(Pair.oatRim)
    static let oatEmpty = Color(Pair.oatEmpty)
    static let oatMark = Color(Pair.oatMark)
    static let glow = Color(Pair.glow)
    static let protein = Color(Pair.protein)
    static let carbs = Color(Pair.carbs)
    static let fat = Color(Pair.fat)
    static let confidenceHigh = Color(Pair.confidenceHigh)
    static let confidenceMedium = Color(Pair.confidenceMedium)
    static let confidenceLow = Color(Pair.confidenceLow)
    static let tintBreakfast = Color(Pair.tintBreakfast)
    static let tintLunch = Color(Pair.tintLunch)
    static let tintDinner = Color(Pair.tintDinner)
    static let destructive = Color(Pair.destructive)
    static let shadow = Color(Pair.shadow)

    /// 可信度小标签的底色：字的颜色的 12%
    nonisolated static let badgeOpacity = 0.12
}

// MARK: - 间距、圆角

/// 间距只用这几个数（4 的倍数）
enum AppSpacing {
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 8
    static let sm: CGFloat = 12
    static let md: CGFloat = 16
    static let lg: CGFloat = 20
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32

    static let pageMargin: CGFloat = 20  // 页面左右留白（三个标签页都一样）
    static let cardGap: CGFloat = 12  // 同一块里，卡片和卡片之间（比如早餐和午餐）
    static let sectionGap: CGFloat = 28  // 两大块内容之间（块标题上面多出来的那段，见 AppSectionHeader）
    static let cardPadding: CGFloat = 18  // 卡片里面的留白
    static let heroPadding: CGFloat = 22  // 主卡片里面的留白（比普通卡片多一点）
}

/// 圆角：所有卡片都是 26（和系统列表卡片的圆角一样，三个标签页看起来是同一套）。
/// 卡片的层级靠大小、字号和阴影区分，不靠圆角
enum AppRadius {
    static let card: CGFloat = 26  // 所有卡片：主卡片、快速记录、列表卡片
    static let compact: CGFloat = 20  // 小一号的辅助卡片（食谱页的每日目标摘要）
    static let button: CGFloat = 18  // 整行宽的按钮（重新生成一日三餐）
    static let tabBar: CGFloat = 32  // 底部悬浮的标签栏
    static let thumbnail: CGFloat = 14  // 照片缩略图
    static let tag: CGFloat = 8  // 小标签（早餐、午餐…）
}

// MARK: - 字体

/// 文字用系统字体；数字用系统的圆体（和「健康」App 一样），一眼就能看出哪些是数字
enum AppTypography {
    static let pageTitleSize: CGFloat = 30  // 「食谱」「我的」的页面大标题（见 PageHeader）
    static let pageSubtitle = Font.subheadline  // 大标题下面的一句说明
    static let heroNumberSize: CGFloat = 42  // 页面上最大的数字（用 @ScaledMetric 跟着系统字号变大）
    static func heroNumber(size: CGFloat) -> Font { .system(size: size, weight: .semibold, design: .rounded) }
    static let heroCaption = Font.subheadline  // 大数字下面的说明
    static let sectionTitle = Font.headline  // 「快速记录」「今日饮食」
    static let cardTitle = Font.subheadline.weight(.semibold)  // 卡片左上角的小标题（今天、每日目标…）
    static let mealTitle = Font.headline  // 早餐、午餐…（一餐的卡片标题）
    static let recipeName = Font.headline  // 食谱卡片上的菜名（17pt 半粗）
    static let itemName = Font.callout.weight(.medium)  // 食物名称
    static let detail = Font.footnote  // 说明文字
    static let caption = Font.caption  // 最小的说明
    static let number = Font.system(.subheadline, design: .rounded, weight: .semibold)  // 卡片里的数字
    static let numberSmall = Font.system(.footnote, design: .rounded, weight: .medium)
    static let actionLabel = Font.subheadline.weight(.medium)  // 快速记录的按钮文字
    static let tabLabel = Font.caption2.weight(.medium)  // 标签栏
}

// MARK: - 页面背景、卡片

/// 页面背景：暖白底色，顶部略亮，主卡片背后有一团很淡的光。整块固定在屏幕上，不跟着内容滚动
struct AppBackground: View {
    var glow = true

    var body: some View {
        GeometryReader { proxy in
            let height = proxy.size.height
            ZStack(alignment: .top) {
                AppColors.background
                // 顶部略亮，往下慢慢变成底色
                LinearGradient(
                    stops: [
                        .init(color: AppColors.backgroundTop, location: 0),
                        .init(color: AppColors.backgroundTop, location: 0.16),
                        .init(color: AppColors.background, location: 0.5),
                    ], startPoint: .top, endPoint: .bottom)
                if glow {
                    // 一团很大、很模糊的光，只为了让主卡片周围有一点空间感；第一眼看不出是一个圆
                    Ellipse()
                        .fill(AppColors.glow.opacity(0.32))
                        .frame(width: proxy.size.width * 1.3, height: height * 0.36)
                        .blur(radius: 90)
                        .offset(x: proxy.size.width * 0.18, y: height * 0.16)
                    Ellipse()
                        .fill(AppColors.oatBowl.opacity(0.22))
                        .frame(width: proxy.size.width * 1.1, height: height * 0.28)
                        .blur(radius: 100)
                        .offset(x: -proxy.size.width * 0.25, y: height * 0.34)
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// 「食谱」「我的」的页面标题：左对齐的大标题 + 下面一句说明，右边可以放一个小按钮。
/// 这两页都不用系统的导航栏标题（滚动时会变成居中的小标题），三个标签页的标题位置一致
struct PageHeader<Trailing: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var trailing: () -> Trailing

    @ScaledMetric(relativeTo: .largeTitle) private var titleSize: CGFloat = AppTypography.pageTitleSize

    var body: some View {
        HStack(alignment: .top, spacing: AppSpacing.sm) {
            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                Text(title)
                    .font(.system(size: titleSize, weight: .bold))
                    .foregroundStyle(AppColors.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Text(subtitle)
                    .font(AppTypography.pageSubtitle)
                    .foregroundStyle(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            trailing()
        }
        .padding(.top, AppSpacing.md)
        .padding(.bottom, AppSpacing.xxs)
        // 左边留一点点：有的汉字（比如「为」的那一点）会比文字起点稍微往左伸，贴着边会被列表裁掉
        .padding(.leading, AppSpacing.xxs)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension PageHeader where Trailing == EmptyView {
    init(title: String, subtitle: String) {
        self.init(title: title, subtitle: subtitle) { EmptyView() }
    }
}

/// 一块内容的标题：左边标题（「快速记录」「今日饮食」），右边一行小字（「记录一餐」、合计千卡）
struct AppSectionHeader: View {
    let title: String
    var trailing: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(AppTypography.sectionTitle)
                .foregroundStyle(AppColors.textPrimary)
            Spacer(minLength: AppSpacing.sm)
            if let trailing {
                Text(trailing)
                    .font(AppTypography.detail)
                    .foregroundStyle(AppColors.textSecondary)
                    .monospacedDigit()
            }
        }
        .textCase(nil)
        .padding(.top, AppSpacing.sectionGap - AppSpacing.cardGap)  // 列表的卡片间距只有 12，块标题上面补足到 28
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// 块标题右边是一个按钮（比如「个人资料」右边的「编辑」）
struct AppSectionHeaderWithAction: View {
    let title: String
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(AppTypography.sectionTitle)
                .foregroundStyle(AppColors.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: AppSpacing.sm)
            Button(actionTitle, action: action)
                .font(AppTypography.detail.weight(.medium))
                .foregroundStyle(AppColors.brand)
                .frame(minWidth: 44, minHeight: 32, alignment: .trailing)
                .contentShape(Rectangle())
        }
        .textCase(nil)
        .padding(.top, AppSpacing.sectionGap - AppSpacing.cardGap)
    }
}

// MARK: - 小组件：按下去的反馈、箭头、图标底

/// 统一的按下反馈：轻轻缩到 0.98、稍微变淡，0.12 秒，不弹跳。
/// scales 为 false 时只变淡（列表里的一整行用这个，缩放一整行看起来会晃）
struct AppPressStyle: ButtonStyle {
    var scales = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && scales && !reduceMotion ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.94 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// 统一的小箭头（表示点了会进入下一页）：所有自己画的箭头都用它，大小和颜色一样
struct AppChevron: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(AppColors.textTertiary)
            .accessibilityHidden(true)
    }
}

/// 圆形的图标底：燕麦色的圆 + 棕灰色的描边图标（餐次、快速记录的次要按钮都用它）
struct AppIconTile: View {
    let systemImage: String
    var size: CGFloat = 36
    var tint: Color = AppColors.surfaceSecondary
    var iconColor: Color = AppColors.iconSecondary

    var body: some View {
        Circle()
            .fill(tint)
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: systemImage)
                    .font(.system(size: size * 0.42, weight: .medium))
                    .foregroundStyle(iconColor)
            }
            .accessibilityHidden(true)
    }
}

extension View {
    /// 卡片：暖白底、圆角，不描边。普通卡片没有阴影，靠和页面底色的差别分出来；
    /// elevated 为 true 时加一层很轻的暖色阴影，只给每一页的主卡片（首页的热量卡片、「我的」的每日目标）
    func appCard(radius: CGFloat = AppRadius.card, elevated: Bool = false) -> some View {
        background {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(AppColors.surfacePrimary)
                .shadow(color: AppColors.shadow.opacity(elevated ? 0.05 : 0), radius: elevated ? 22 : 0, y: elevated ? 6 : 0)
        }
    }

    /// 列表里一张卡片的一行：暖白底，分隔线很淡（三个标签页的列表卡片都用它）
    func appCardRow() -> some View {
        listRowBackground(AppColors.surfacePrimary)
            .listRowSeparatorTint(AppColors.divider)
    }

    /// 固定在页面底部的一条（保存按钮、提示文字）：和页面同样的暖色，上边缘淡出，不用系统的灰色毛玻璃。
    /// 字号最多放大到「特特大」：这一条一直占着屏幕底部，再大就会挡住小半个屏幕
    func appBottomBar() -> some View {
        dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .background {
            LinearGradient(
                stops: [
                    .init(color: AppColors.background.opacity(0), location: 0),
                    .init(color: AppColors.background.opacity(0.96), location: 0.25),
                ], startPoint: .top, endPoint: .bottom
            )
            .padding(.top, -AppSpacing.md)  // 淡出的那一段往上多伸出一点
            .ignoresSafeArea(edges: .bottom)  // 一直铺到屏幕最底下（Home 条那一段）：滚动的内容不会从按钮下面露出来
        }
    }

    /// 没有导航栏的页面（「食谱」「我的」）：状态栏那一条盖上页面顶部的颜色，下边缘淡出。
    /// 内容往上滑时从这里柔和地消失，不会和时间、电量叠在一起
    func appStatusBarCover() -> some View {
        safeAreaInset(edge: .top, spacing: 0) {
            Color.clear
                .frame(height: 0)
                .background {
                    // 这个视图本身高度是 0；它的背景伸进状态栏，正好盖住状态栏那一条
                    AppColors.backgroundTop
                        .ignoresSafeArea(edges: .top)
                }
                .overlay(alignment: .top) {
                    LinearGradient(
                        colors: [AppColors.backgroundTop, AppColors.backgroundTop.opacity(0)], startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: AppSpacing.md)
                    .allowsHitTesting(false)
                }
        }
    }

    /// 列表页面用的暖色背景（「食谱」「我的」、识别结果等页面）：去掉系统的灰底，换成 App 的背景
    func appListBackground(glow: Bool = false) -> some View {
        scrollContentBackground(.hidden)
            .background { AppBackground(glow: glow) }
    }
}

extension Color {
    /// 浅色、深色模式各用一个颜色：系统切换外观时自动换
    init(_ pair: ColorPair) {
        self.init(
            uiColor: UIColor { traits in
                UIColor(hex: traits.userInterfaceStyle == .dark ? pair.dark : pair.light)
            })
    }
}

extension UIColor {
    /// 0xRRGGBB → 颜色
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}
