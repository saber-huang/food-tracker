//
//  BowlGauge.swift
//  FoodTracker
//
//  App 图标里的那只碗，用代码画出来，有两种用法：
//  - BowlGauge：「今日」卡片里的进度。吃了目标的几成，碗里就装到几成；吃到目标正好满碗，和 App 图标一模一样
//  - KindbiteMark：完整的图标图案（笑脸 + 碗），引导页第一页用
//  形状和图标完全一样：坐标照抄 tools/icon/concepts.mjs 里的 bowlFlatSvg（1024 × 1024 的画布）。
//

import SwiftUI

/// 碗的各个部分（1024 × 1024 画布上的坐标，和图标一样）
nonisolated enum BowlGeometry {
    static let center = CGPoint(x: 512, y: 470)  // 碗口的圆心
    static let radius: CGFloat = 310
    static let rimRect = CGRect(x: 182, y: 436, width: 660, height: 64)  // 碗沿
    static let rimBottom: CGFloat = 500  // 碗沿下边：碗身从这里往下才看得见
    static let biteCircle = CGRect(x: 838 - 92, y: 450 - 92, width: 184, height: 184)  // 碗沿右端被咬掉的一口

    /// 进度只画碗（碗沿 + 碗身）
    static let gaugeBox = CGRect(x: 182, y: 436, width: 660, height: 344)
    /// 完整图案：上面多一个笑脸
    static let markBox = CGRect(x: 182, y: 263, width: 660, height: 517)

    /// 碗身：下半个圆，减去咬掉的一口
    static var body: Path {
        var path = Path()
        path.move(to: CGPoint(x: center.x - radius, y: center.y))
        path.addLine(to: CGPoint(x: center.x + radius, y: center.y))
        // SwiftUI 的 y 轴朝下：从 0° 转到 180° 经过的是圆的下半部分
        path.addArc(center: center, radius: radius, startAngle: .degrees(0), endAngle: .degrees(180), clockwise: false)
        path.closeSubpath()
        return path.subtracting(Path(ellipseIn: biteCircle))
    }

    /// 碗沿：圆角长条，减去咬掉的一口
    static var rim: Path {
        Path(roundedRect: rimRect, cornerRadius: 32).subtracting(Path(ellipseIn: biteCircle))
    }

    /// 碗上方的笑脸（一条粗的圆头弧线）
    static var smile: Path {
        var path = Path()
        path.move(to: CGPoint(x: 388, y: 292))
        path.addQuadCurve(to: CGPoint(x: 636, y: 292), control: CGPoint(x: 512, y: 408))
        return path.strokedPath(StrokeStyle(lineWidth: 58, lineCap: .round))
    }

    /// 装到几成时，碗里食物的上沿在哪里（y 坐标）。
    /// 按面积算：碗底窄、碗口宽，装一半的量时食物上沿要比一半高度高一些（大约到六成高）。
    /// 只算碗沿下面看得见的部分，满碗（1）时正好到碗沿
    static func fillTop(fraction: Double) -> CGFloat {
        let f = min(max(fraction, 0), 1)
        let r = Double(radius)
        let bottom = Double(center.y) + r
        let visibleHeight = bottom - Double(rimBottom)
        // 从碗底往上 h 高的那一块（弓形）的面积
        func area(_ h: Double) -> Double {
            let d = r - h
            return r * r * acos(d / r) - d * (2 * r * h - h * h).squareRoot()
        }
        let target = f * area(visibleHeight)
        var low = 0.0
        var high = visibleHeight
        for _ in 0..<40 {  // 二分法：40 次后误差远小于一个像素
            let mid = (low + high) / 2
            if area(mid) < target { low = mid } else { high = mid }
        }
        return CGFloat(bottom - (low + high) / 2)
    }

    /// 把画布上的一块（box）等比例缩放、居中放进 rect
    static func transform(from box: CGRect, to rect: CGRect) -> CGAffineTransform {
        let scale = min(rect.width / box.width, rect.height / box.height)
        return CGAffineTransform(
            a: scale, b: 0, c: 0, d: scale,
            tx: rect.midX - box.midX * scale, ty: rect.midY - box.midY * scale)
    }
}

/// 碗的一个部分，按 box 缩放进给它的位置
private struct BowlPart: Shape {
    let path: Path
    let box: CGRect

    func path(in rect: CGRect) -> Path {
        path.applying(BowlGeometry.transform(from: box, to: rect))
    }
}

/// 碗里装的食物：从碗底装到 fraction 那么多。fraction 变化时会有动画
private struct BowlContents: Shape {
    var fraction: Double
    let box: CGRect

    var animatableData: Double {
        get { fraction }
        set { fraction = newValue }
    }

    func path(in rect: CGRect) -> Path {
        guard fraction > 0 else { return Path() }
        let top = BowlGeometry.fillTop(fraction: fraction)
        let band = Path(CGRect(x: 0, y: top, width: 1024, height: 1024 - top))
        return BowlGeometry.body.intersection(band).applying(BowlGeometry.transform(from: box, to: rect))
    }
}

/// 「今日」卡片里的碗：吃了目标的几成，碗里就装到几成（超过目标也是满碗，不用别的颜色）
struct BowlGauge: View {
    let fraction: Double  // 0～1：已经吃了目标的几成

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let box = BowlGeometry.gaugeBox
        ZStack {
            BowlPart(path: BowlGeometry.body, box: box).fill(AppColors.oatEmpty)
            BowlContents(fraction: fraction, box: box).fill(AppColors.oatBowl)
            BowlPart(path: BowlGeometry.rim, box: box).fill(AppColors.oatRim)
        }
        .aspectRatio(box.width / box.height, contentMode: .fit)
        // 记了一餐，碗里慢慢装上去；系统设置了「减弱动态效果」就直接变
        .animation(reduceMotion ? nil : .spring(duration: 0.7, bounce: 0.15), value: fraction)
        .accessibilityHidden(true)  // 数字已经写在旁边的文字里
    }
}

/// 完整的图标图案：笑脸 + 满满一碗（和 App 图标一样，没有背景）
struct KindbiteMark: View {
    var body: some View {
        let box = BowlGeometry.markBox
        ZStack {
            BowlPart(path: BowlGeometry.smile, box: box).fill(AppColors.oatBowl)
            BowlPart(path: BowlGeometry.body, box: box).fill(AppColors.oatBowl)
            BowlPart(path: BowlGeometry.rim, box: box).fill(AppColors.oatRim)
        }
        .aspectRatio(box.width / box.height, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

#Preview("碗形进度") {
    VStack(spacing: 24) {
        ForEach([0, 0.35, 0.7, 1], id: \.self) { fraction in
            BowlGauge(fraction: fraction).frame(width: 120)
        }
        KindbiteMark().frame(width: 120)
    }
    .padding()
}
