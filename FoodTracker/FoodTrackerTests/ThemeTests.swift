//
//  ThemeTests.swift
//  FoodTrackerTests
//
//  配色的检查：文字和按钮的对比度够不够（WCAG：普通文字 4.5:1，粗体大字和图形 3:1），
//  Assets 里的 AccentColor 和代码里的主色是不是同一个颜色，以及「今日」卡片里那只碗的装满高度。
//

import Foundation
import SwiftUI
import Testing
import UIKit

@testable import FoodTracker

/// 颜色的相对亮度（WCAG 的算法）
private func luminance(_ hex: UInt32) -> Double {
    func channel(_ value: UInt32) -> Double {
        let c = Double(value) / 255
        return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }
    return 0.2126 * channel((hex >> 16) & 0xFF) + 0.7152 * channel((hex >> 8) & 0xFF) + 0.0722 * channel(hex & 0xFF)
}

/// 两个颜色的对比度（1～21）
private func contrast(_ a: UInt32, _ b: UInt32) -> Double {
    let (high, low) = (max(luminance(a), luminance(b)), min(luminance(a), luminance(b)))
    return (high + 0.05) / (low + 0.05)
}

/// 颜色 color 以 opacity 的透明度叠在 background 上，看起来是什么颜色
private func blend(_ color: UInt32, over background: UInt32, opacity: Double) -> UInt32 {
    func mix(_ shift: UInt32) -> UInt32 {
        let c = Double((color >> shift) & 0xFF)
        let b = Double((background >> shift) & 0xFF)
        return UInt32((b * (1 - opacity) + c * opacity).rounded()) << shift
    }
    return mix(16) | mix(8) | mix(0)
}

private let white: UInt32 = 0xFFFFFF
private let lightPage: UInt32 = 0xF2F2F7  // 浅色模式的页面底色（卡片是白色）
private let darkCard: UInt32 = 0x1C1C1E  // 深色模式的卡片
private let black: UInt32 = 0x000000  // 深色模式的页面底色

@Suite("配色")
struct ThemeTests {
    @Test("主色当文字时看得清，白字放在主色按钮上也看得清", arguments: [Theme.AccentChoice.matcha, .ink, .roast])
    func accentContrast(_ choice: Theme.AccentChoice) {
        let pair = choice.pair
        #expect(contrast(pair.light, white) >= 4.5)
        #expect(contrast(pair.light, lightPage) >= 4.5)
        #expect(contrast(white, pair.light) >= 4.5)
        #expect(contrast(pair.dark, darkCard) >= 4.5)
        #expect(contrast(pair.dark, black) >= 4.5)
        // 深色模式的按钮：白色粗体大字，3:1 就够（系统蓝在深色模式下也是这样）
        #expect(contrast(white, pair.dark) >= 3)
    }

    @Test("正式版的主色是抹茶绿；可以点的字和旁边的黑字也分得开（墨色就分不开，所以没选它）")
    func defaultAccent() {
        #expect(Theme.AccentChoice.matcha.pair.light == 0x357A4C)
        #expect(contrast(Theme.AccentChoice.matcha.pair.light, black) >= 3)
    }

    @Test("Assets 里的 AccentColor 和代码里的抹茶绿完全一样（浅色、深色都是）")
    func accentAssetMatchesCode() throws {
        // 测试跑在 App 里面，Bundle.main 就是 App 本身
        let asset = try #require(UIColor(named: "AccentColor", in: .main, compatibleWith: nil))
        let pair = Theme.AccentChoice.matcha.pair
        for (style, hex) in [(UIUserInterfaceStyle.light, pair.light), (.dark, pair.dark)] {
            var (r, g, b, a): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
            asset.resolvedColor(with: UITraitCollection(userInterfaceStyle: style)).getRed(&r, green: &g, blue: &b, alpha: &a)
            let expected = [(hex >> 16) & 0xFF, (hex >> 8) & 0xFF, hex & 0xFF].map { CGFloat($0) / 255 }
            for (actual, wanted) in zip([r, g, b], expected) {
                #expect(abs(actual - wanted) < 1.0 / 255, "AccentColor（\(style == .dark ? "深色" : "浅色")）和 Theme 不一样")
            }
        }
    }

    @Test("营养素的进度条：深色模式都 >= 3:1；浅色模式蛋白质、脂肪 >= 3:1，碳水浅一些但旁边一直有文字标签")
    func macroBars() {
        let macros = [Theme.Macro.protein, Theme.Macro.carbs, Theme.Macro.fat]
        for pair in macros {
            #expect(contrast(pair.dark, darkCard) >= 3)
        }
        #expect(contrast(Theme.Macro.protein.light, white) >= 3)
        #expect(contrast(Theme.Macro.fat.light, white) >= 3)
        #expect(contrast(Theme.Macro.carbs.light, white) >= 2.2)
    }

    @Test("可信度小标签：字放在 12% 的同色底上 >= 4.5:1", arguments: [
        Theme.ConfidencePair.high, Theme.ConfidencePair.medium, Theme.ConfidencePair.low,
    ])
    func confidenceBadges(_ pair: ColorPair) {
        let lightBackground = blend(pair.light, over: white, opacity: Theme.badgeOpacity)
        let darkBackground = blend(pair.dark, over: darkCard, opacity: Theme.badgeOpacity)
        #expect(contrast(pair.light, lightBackground) >= 4.5)
        #expect(contrast(pair.dark, darkBackground) >= 4.5)
    }
}

@Suite("碗形进度")
struct BowlGeometryTests {
    @Test("空碗在碗底，满碗正好到碗沿；装得越多，食物上沿越高")
    func fillTop() {
        #expect(abs(BowlGeometry.fillTop(fraction: 0) - 780) < 0.01)
        #expect(abs(BowlGeometry.fillTop(fraction: 1) - BowlGeometry.rimBottom) < 0.01)
        var previous = BowlGeometry.fillTop(fraction: 0)
        for step in 1...20 {
            let y = BowlGeometry.fillTop(fraction: Double(step) / 20)
            #expect(y < previous)  // y 越小越高
            previous = y
        }
    }

    @Test("超出范围的比例当成空碗或满碗（吃超了也只是满碗）")
    func clamps() {
        #expect(BowlGeometry.fillTop(fraction: -1) == BowlGeometry.fillTop(fraction: 0))
        #expect(BowlGeometry.fillTop(fraction: 2.5) == BowlGeometry.fillTop(fraction: 1))
    }

    @Test("按面积算：碗底窄，装一半的量时食物上沿要高过一半高度")
    func halfIsAboveMiddle() {
        let middle = (780 + BowlGeometry.rimBottom) / 2
        #expect(BowlGeometry.fillTop(fraction: 0.5) < middle)  // y 越小越高
    }

    @Test("碗身、碗沿、笑脸都画得出来")
    func shapes() {
        #expect(!BowlGeometry.body.isEmpty)
        #expect(!BowlGeometry.rim.isEmpty)
        #expect(!BowlGeometry.smile.isEmpty)
        // 碗沿右端被咬掉一口：碗沿的右边界比原来的长条短
        #expect(BowlGeometry.rim.boundingRect.maxX < BowlGeometry.rimRect.maxX)
    }
}
