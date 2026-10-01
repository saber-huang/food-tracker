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
        static let background = ColorPair(light: 0xF7F4EE, dark: 0x12110F)  // 页面底色
        static let backgroundTop = ColorPair(light: 0xFBF9F5, dark: 0x191714)  // 页面顶部，比底色略亮
        static let surfacePrimary = ColorPair(light: 0xFFFDF9, dark: 0x1E1C19)  // 卡片
        static let surfaceSecondary = ColorPair(light: 0xF0E9DE, dark: 0x2A2621)  // 次要按钮的圆底
        static let surfaceMuted = ColorPair(light: 0xEBE6DE, dark: 0x2C2924)  // 进度条的底槽
        static let divider = ColorPair(light: 0xE6E0D7, dark: 0x2E2A25)

        // 文字：不用纯黑。次要文字比设计稿的 #777169 深一点点，在页面底色上也够 4.5:1
        static let textPrimary = ColorPair(light: 0x262522, dark: 0xF2EEE7)
        static let textSecondary = ColorPair(light: 0x6F695F, dark: 0xA8A196)
        static let textTertiary = ColorPair(light: 0xAAA39A, dark: 0x6F6961)  // 对比度低，只给不能点的未来日期这类地方

        // 品牌主色：深橄榄绿。选中、主按钮、可以点的文字都用它，全 App 只有这一种绿
        static let brand = ColorPair(light: 0x4F624D, dark: 0x6E8B6A)
        static let brandDeep = ColorPair(light: 0x354A38, dark: 0xC3D3B9)  // 选中的标签文字
        static let brandSoft = ColorPair(light: 0xE7E9DF, dark: 0x2B3128)  // 选中的标签底色
        static let onBrand = ColorPair(light: 0xFAF7F1, dark: 0xFAF7F1)  // 主色上面的文字、图标（暖白）
        static let iconSecondary = ColorPair(light: 0x756B5E, dark: 0xB5AA9A)  // 次要按钮的图标

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

    static let pageMargin: CGFloat = 20  // 页面左右留白
    static let sectionGap: CGFloat = 28  // 两块内容之间
    static let cardPadding: CGFloat = 20  // 卡片里面的留白
}

/// 圆角按层级分：越重要、越大的卡片圆角越大
enum AppRadius {
    static let hero: CGFloat = 30  // 首页的主卡片
    static let dock: CGFloat = 26  // 快速记录
    static let tabBar: CGFloat = 32  // 底部悬浮的标签栏
    static let thumbnail: CGFloat = 14  // 照片缩略图
}

// MARK: - 字体

/// 文字用系统字体；数字用系统的圆体（和「健康」App 一样），一眼就能看出哪些是数字
enum AppTypography {
    static let heroNumberSize: CGFloat = 40  // 首页的大数字（用 @ScaledMetric 跟着系统字号变大）
    static func heroNumber(size: CGFloat) -> Font { .system(size: size, weight: .semibold, design: .rounded) }
    static let heroCaption = Font.subheadline.weight(.medium)  // 大数字下面的说明
    static let sectionTitle = Font.headline  // 「快速记录」「今日饮食」
    static let cardTitle = Font.subheadline.weight(.semibold)  // 卡片里的小标题（早餐、午餐…）
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
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

extension View {
    /// 卡片：暖白底、圆角，不描边。elevated 为 true 时加一层很轻的暖色阴影（只给首页主卡片这种最上层的卡片）
    func appCard(radius: CGFloat, elevated: Bool = false) -> some View {
        background {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(AppColors.surfacePrimary)
                .shadow(color: AppColors.shadow.opacity(elevated ? 0.06 : 0.035), radius: elevated ? 24 : 14, y: elevated ? 8 : 4)
        }
    }

    /// 固定在页面底部的一条（保存按钮、提示文字）：和页面同样的暖色，上边缘淡出，不用系统的灰色毛玻璃
    func appBottomBar() -> some View {
        background {
            LinearGradient(
                stops: [
                    .init(color: AppColors.background.opacity(0), location: 0),
                    .init(color: AppColors.background.opacity(0.96), location: 0.25),
                ], startPoint: .top, endPoint: .bottom
            )
            .padding(.top, -AppSpacing.md)  // 淡出的那一段往上多伸出一点
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
