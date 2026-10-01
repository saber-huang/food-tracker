//
//  DesignSystemTests.swift
//  FoodTrackerTests
//
//  设计规范的检查：文字和按钮的对比度够不够（WCAG：普通文字 4.5:1，粗体大字和图形 3:1），
//  Assets 里的 AccentColor 和代码里的主色是不是同一个颜色，圆角、间距、阴影只用规定的几个数，
//  以及「今日」卡片里那只碗的装满高度。
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

private typealias P = AppColors.Pair

@Suite("设计规范：颜色")
struct DesignSystemColorTests {
    @Test("正文：在页面底色和卡片上都至少 4.5:1；次要文字在卡片上至少 4.5:1（浅色、深色模式）")
    func textContrast() {
        for surface in [P.background, P.backgroundTop, P.surfacePrimary, P.surfaceMeal] {
            #expect(contrast(P.textPrimary.light, surface.light) >= 4.5)
            #expect(contrast(P.textPrimary.dark, surface.dark) >= 4.5)
            #expect(contrast(P.textSecondary.dark, surface.dark) >= 4.5)
        }
        #expect(contrast(P.textSecondary.light, P.surfacePrimary.light) >= 4.5)
        #expect(contrast(P.textSecondary.light, P.surfaceMeal.light) >= 4.5)
        // 轻提示：深色胶囊上的浅色字和「撤销」
        #expect(contrast(P.toastText.light, P.toastBackground.light) >= 4.5)
        #expect(contrast(P.toastText.dark, P.toastBackground.dark) >= 4.5)
        #expect(contrast(P.toastAction.light, P.toastBackground.light) >= 4.5)
        #expect(contrast(P.toastAction.dark, P.toastBackground.dark) >= 4.5)
        // 设计稿指定的 #777169 直接放在设计稿指定的页面底色 #F4F0E8 上是 4.25:1（块标题右边的小字），
        // 略低于 4.5:1，用户确认过；这里守住不再更低
        #expect(contrast(P.textSecondary.light, P.background.light) >= 4.2)
        // 次要按钮的燕麦色圆底上，图标至少 3:1
        #expect(contrast(P.iconSecondary.light, P.surfaceSecondary.light) >= 3)
        #expect(contrast(P.iconSecondary.dark, P.surfaceSecondary.dark) >= 3)
    }

    @Test("标签栏没选中的图标至少 3:1（设计稿指定 #8D887F，文字是 3.5:1）；三餐标签、删除按钮的字看得清")
    func tabsTagsAndDestructive() {
        #expect(contrast(P.tabInactive.light, P.surfacePrimary.light) >= 3)
        #expect(contrast(P.tabInactive.dark, P.surfacePrimary.dark) >= 3)
        for tint in [P.tintBreakfast, P.tintLunch, P.tintDinner, P.tintSnack] {
            #expect(contrast(P.textPrimary.light, tint.light) >= 4.5)
            #expect(contrast(P.textPrimary.dark, tint.dark) >= 4.5)
        }
        #expect(contrast(P.destructive.light, P.surfacePrimary.light) >= 4.5)
        #expect(contrast(P.destructive.dark, P.surfacePrimary.dark) >= 4.5)
    }

    @Test("主色橄榄绿：当文字看得清；暖白字放在主色上也看得清")
    func brandContrast() {
        #expect(contrast(P.brand.light, P.surfacePrimary.light) >= 4.5)
        #expect(contrast(P.brand.light, P.background.light) >= 4.5)
        #expect(contrast(P.onBrand.light, P.brand.light) >= 4.5)
        #expect(contrast(P.brand.dark, P.surfacePrimary.dark) >= 4.5)
        // 深色模式的主按钮：暖白粗体大字，3:1 就够（系统蓝在深色模式下也是这样）
        #expect(contrast(P.onBrand.dark, P.brand.dark) >= 3)
        // 选中的标签：深橄榄绿字放在浅橄榄色底上
        #expect(contrast(P.brandDeep.light, P.brandSoft.light) >= 4.5)
        #expect(contrast(P.brandDeep.dark, P.brandSoft.dark) >= 4.5)
    }

    @Test("Assets 里的 AccentColor 和代码里的橄榄绿完全一样（浅色、深色都是）")
    func accentAssetMatchesCode() throws {
        // 测试跑在 App 里面，Bundle.main 就是 App 本身
        let asset = try #require(UIColor(named: "AccentColor", in: .main, compatibleWith: nil))
        for (style, hex) in [(UIUserInterfaceStyle.light, P.brand.light), (.dark, P.brand.dark)] {
            var (r, g, b, a): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
            asset.resolvedColor(with: UITraitCollection(userInterfaceStyle: style)).getRed(&r, green: &g, blue: &b, alpha: &a)
            let expected = [(hex >> 16) & 0xFF, (hex >> 8) & 0xFF, hex & 0xFF].map { CGFloat($0) / 255 }
            for (actual, wanted) in zip([r, g, b], expected) {
                #expect(abs(actual - wanted) < 1.0 / 255, "AccentColor（\(style == .dark ? "深色" : "浅色")）和 AppColors 不一样")
            }
        }
    }

    @Test("营养素的颜色彼此分得开，而且都不是主色（全 App 只有一种橄榄绿）")
    func macroColorsAreDistinct() {
        let macros = [P.protein, P.carbs, P.fat]
        for pair in macros {
            #expect(pair.light != P.brand.light)
            #expect(pair.dark != P.brand.dark)
        }
        // 亮度拉开（色盲时主要靠亮度区分）：浅色模式三种颜色两两的对比度都大于 1.3
        for i in 0..<macros.count {
            for j in (i + 1)..<macros.count {
                #expect(contrast(macros[i].light, macros[j].light) > 1.3)
                #expect(contrast(macros[i].dark, macros[j].dark) > 1.3)
            }
        }
    }

    @Test("可信度小标签：字放在 12% 的同色底上 >= 4.5:1", arguments: [P.confidenceHigh, P.confidenceMedium, P.confidenceLow])
    func confidenceBadges(_ pair: ColorPair) {
        let lightBackground = blend(pair.light, over: P.surfacePrimary.light, opacity: AppColors.badgeOpacity)
        let darkBackground = blend(pair.dark, over: P.surfacePrimary.dark, opacity: AppColors.badgeOpacity)
        #expect(contrast(pair.light, lightBackground) >= 4.5)
        #expect(contrast(pair.dark, darkBackground) >= 4.5)
    }
}

@Suite("设计规范：圆角、间距、阴影、按钮和分段选择")
struct DesignSystemTokenTests {
    @Test("圆角只有 12、18、24、30 四个")
    func radii() {
        #expect([AppRadius.small, AppRadius.medium, AppRadius.large, AppRadius.extraLarge] == [12, 18, 24, 30])
    }

    @Test("间距都是 4 的倍数；页面左右 20，大块之间 24～32，卡片里面 16～20")
    func spacing() {
        let all: [CGFloat] = [
            AppSpacing.xxs, AppSpacing.xs, AppSpacing.sm, AppSpacing.md, AppSpacing.lg, AppSpacing.xl, AppSpacing.xxl,
            AppSpacing.pageMargin, AppSpacing.cardGap, AppSpacing.sectionGap, AppSpacing.formSectionGap,
            AppSpacing.cardPadding, AppSpacing.heroPadding,
        ]
        for value in all {
            #expect(value.truncatingRemainder(dividingBy: 4) == 0)
        }
        #expect(AppSpacing.pageMargin == 20)
        #expect((24...32).contains(AppSpacing.sectionGap))
        #expect((24...32).contains(AppSpacing.formSectionGap))
        #expect((16...20).contains(AppSpacing.cardPadding))
        #expect((16...20).contains(AppSpacing.heroPadding))
    }

    @Test("阴影都很淡：透明度 0.03～0.06，模糊 16～24")
    func shadows() {
        for style in [AppShadow.hero, AppShadow.floating, AppShadow.overlay] {
            #expect((0.03...0.06).contains(style.opacity))
            #expect((16...24).contains(style.radius))
        }
    }

    @Test("次要按钮、删除按钮：字放在燕麦色圆底上 >= 4.5:1")
    func buttonContrast() {
        #expect(contrast(P.brandDeep.light, P.surfaceSecondary.light) >= 4.5)
        #expect(contrast(P.brandDeep.dark, P.surfaceSecondary.dark) >= 4.5)
        #expect(contrast(P.destructive.light, P.surfaceSecondary.light) >= 4.5)
        #expect(contrast(P.destructive.dark, P.surfaceSecondary.dark) >= 4.5)
    }

    @Test("分段选择：选中的深橄榄字在暖白小胶囊上 >= 4.5:1；没选中的灰字守住设计稿的值")
    func segmentContrast() {
        #expect(contrast(P.brandDeep.light, P.segmentSelected.light) >= 4.5)
        #expect(contrast(P.brandDeep.dark, P.segmentSelected.dark) >= 4.5)
        #expect(contrast(P.textSecondary.dark, P.segmentTrack.dark) >= 4.5)
        // 设计稿指定：没选中的字 #777169、槽 #EEE8DE，是 3.96:1（略低于小字的 4.5:1；
        // 选中的一格另外有暖白小胶囊标出来，旁白也会读「已选择」）。这里守住不再更低
        #expect(contrast(P.textSecondary.light, P.segmentTrack.light) >= 3.9)
    }

    @Test("UIKit 用的颜色（月历）和 SwiftUI 的是同一组值，也跟着深色模式换")
    func uiKitColorsMatch() {
        for pair in [P.brand, P.oatMark] {
            for (style, hex) in [(UIUserInterfaceStyle.light, pair.light), (.dark, pair.dark)] {
                var (r, g, b, a): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
                UIColor(pair).resolvedColor(with: UITraitCollection(userInterfaceStyle: style)).getRed(
                    &r, green: &g, blue: &b, alpha: &a)
                let expected = [(hex >> 16) & 0xFF, (hex >> 8) & 0xFF, hex & 0xFF].map { CGFloat($0) / 255 }
                for (actual, wanted) in zip([r, g, b], expected) {
                    #expect(abs(actual - wanted) < 1.0 / 255)
                }
            }
        }
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

    @Test("装了的部分用长方形裁剪：满碗露到碗沿下面、超过目标和满碗一样、空碗什么都不露")
    func fillClipRect() {
        let box = BowlGeometry.gaugeBox
        let rect = CGRect(x: 10, y: 20, width: 66, height: 34.4)  // 和 box 同样的比例
        let toRect = BowlGeometry.transform(from: box, to: rect)
        let full = BowlGeometry.fillClipRect(fraction: 1, box: box, in: rect)
        // 满碗：上沿正好在碗沿下边
        #expect(abs(full.minY - CGPoint(x: 0, y: BowlGeometry.rimBottom).applying(toRect).y) < 0.001)
        // 吃超了（今天 5,349 / 1,563 这种）和满碗完全一样，不会变成更大的一块
        #expect(BowlGeometry.fillClipRect(fraction: 3.42, box: box, in: rect) == full)
        // 空碗：什么都不露
        #expect(BowlGeometry.fillClipRect(fraction: 0, box: box, in: rect).isEmpty)
        // 半碗：上沿在碗沿和碗底之间
        let half = BowlGeometry.fillClipRect(fraction: 0.5, box: box, in: rect)
        #expect(half.minY > full.minY && half.minY < rect.maxY)
        // 裁剪框只比碗所在的那块大一点点（抗锯齿的余量），不会像出错时那样宽出一大截
        #expect(full.minX >= rect.minX - 2 && full.maxX <= rect.maxX + 2)
        #expect(full.maxY <= rect.maxY + 2)
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

@MainActor
@Suite("碗形进度：画出来的样子")
struct BowlRenderingTests {
    /// 把「今日」卡片里的碗画成图片，返回每个点的 RGBA（0～255，一行一行从上往下）
    private func render(fraction: Double, size: CGSize) throws -> (width: Int, height: Int, data: [UInt8]) {
        let renderer = ImageRenderer(content: BowlGauge(fraction: fraction).frame(width: size.width, height: size.height))
        renderer.scale = 1
        let image = try #require(renderer.cgImage)
        let width = image.width
        let height = image.height
        var data = [UInt8](repeating: 0, count: width * height * 4)
        data.withUnsafeMutableBytes { buffer in
            guard
                let context = CGContext(
                    data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        return (width, height, data)
    }

    @Test("吃到或超过目标也只是满碗：碗外面的两个下角是透明的（iOS 26 上曾经画成一个大方块）", arguments: [0.5, 1.0, 3.42])
    func fillStaysInsideBowl(fraction: Double) throws {
        // 宽 132 × 高 68.8：正好是画布 660 × 344 的五分之一
        let (width, height, data) = try render(fraction: fraction, size: CGSize(width: 132, height: 68.8))
        func alpha(_ x: Int, _ y: Int) -> UInt8 { data[(y * width + x) * 4 + 3] }
        // 碗底两边的角落在碗外面：必须什么都没画
        #expect(alpha(2, height - 3) == 0)
        #expect(alpha(width - 3, height - 3) == 0)
        // 碗底正中间在碗里面：画了东西（不透明）
        #expect(alpha(width / 2, height - 6) > 200)
        // 碗沿右端被咬掉的那一口：是空的（「咬掉」也是路径运算，确认它在各个系统版本上都对）
        #expect(alpha(126, 6) == 0)
        // 碗沿左边没被咬：画了东西
        #expect(alpha(10, 6) > 200)
    }
}

