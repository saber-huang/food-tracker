//
//  Theme.swift
//  FoodTracker
//
//  App 的配色。为什么选这些颜色、每种颜色用在哪里，见仓库里的 design-system/kindbite/MASTER.md。
//  - 品牌主色：按钮、可以点的文字、选中的日期都用它（App 最外层用 .tint 设置；
//    Assets 里的 AccentColor 是同一个颜色，测试检查两边一致）
//  - 三大营养素：蛋白质、碳水、脂肪各一种颜色，只用在进度条和小色块上；数字和文字一律用正常的文字颜色
//  - 燕麦色：和 App 图标里的碗是同一组颜色，「今日」卡片里的碗、周横条上的小圆环用它
//  每种颜色都有浅色模式、深色模式两个值，对比度由 ThemeTests.swift 检查。
//

import SwiftUI
import UIKit

/// 一种颜色在浅色、深色模式下的两个值（0xRRGGBB）。单独存数字，测试可以直接算对比度
nonisolated struct ColorPair: Sendable {
    let light: UInt32
    let dark: UInt32
}

enum Theme {
    // MARK: - 品牌主色

    /// 主色的几个候选。正式版用抹茶绿（= Assets 里的 AccentColor）；其余几个只在模拟器里对比用
    nonisolated enum AccentChoice: String, CaseIterable, Sendable {
        case matcha  // 抹茶绿（正式使用）
        case ink  // 墨色
        case roast  // 焙茶棕
        case blue  // 系统蓝（改版前的样子）

        var pair: ColorPair {
            switch self {
            case .matcha: ColorPair(light: 0x357A4C, dark: 0x4F9165)
            case .ink: ColorPair(light: 0x2B2724, dark: 0x8E8271)
            case .roast: ColorPair(light: 0x7A5632, dark: 0xA47C50)
            case .blue: ColorPair(light: 0x007AFF, dark: 0x0A84FF)
            }
        }
    }

    /// 现在用的主色。模拟器里可以用启动参数 -accentPreview ink 临时换成别的候选（截图对比用）
    static let accentChoice: AccentChoice = {
        #if DEBUG && targetEnvironment(simulator)
        if let raw = UserDefaults.standard.string(forKey: "accentPreview"), let choice = AccentChoice(rawValue: raw) {
            return choice
        }
        #endif
        return .matcha
    }()

    static let accent = Color(accentChoice.pair)

    // MARK: - 三大营养素（只给进度条、小色块用，不给文字用）

    nonisolated enum Macro {
        static let protein = ColorPair(light: 0x3D74C4, dark: 0x4F86D6)  // 蓝
        static let carbs = ColorPair(light: 0xE39A3B, dark: 0xC2852F)  // 麦黄
        static let fat = ColorPair(light: 0xC9586F, dark: 0xD4608C)  // 玫红
    }

    static let protein = Color(Macro.protein)
    static let carbs = Color(Macro.carbs)
    static let fat = Color(Macro.fat)

    // MARK: - 燕麦色（和 App 图标里的碗一样）

    nonisolated enum OatPair {
        static let bowl = ColorPair(light: 0xDED2BF, dark: 0xB9AC96)  // 碗身 = 已经吃了的部分
        static let rim = ColorPair(light: 0xBDAD95, dark: 0x8F826E)  // 碗沿、小圆环
        static let empty = ColorPair(light: 0xF1EBE1, dark: 0x2E2A25)  // 碗里还空着的部分
        static let smile = ColorPair(light: 0xDED2BF, dark: 0xB9AC96)  // 图标上方的笑脸
        static let ring = ColorPair(light: 0xA8957A, dark: 0xA39680)  // 周横条上的小圆环（吃了几成）
    }

    enum Oat {
        static let bowl = Color(OatPair.bowl)
        static let rim = Color(OatPair.rim)
        static let empty = Color(OatPair.empty)
        static let smile = Color(OatPair.smile)
        static let ring = Color(OatPair.ring)
    }

    // MARK: - 识别结果的可信度（小标签）

    /// 文字颜色；底色是同一个颜色的 12%（见 badgeOpacity）
    nonisolated enum ConfidencePair {
        static let high = ColorPair(light: 0x2E6B43, dark: 0x6DB383)  // 绿
        static let medium = ColorPair(light: 0x8F5A0E, dark: 0xD9A040)  // 琥珀
        static let low = ColorPair(light: 0xA33F33, dark: 0xE07A6C)  // 砖红
    }

    nonisolated static let badgeOpacity = 0.12
    static let confidenceHigh = Color(ConfidencePair.high)
    static let confidenceMedium = Color(ConfidencePair.medium)
    static let confidenceLow = Color(ConfidencePair.low)
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
