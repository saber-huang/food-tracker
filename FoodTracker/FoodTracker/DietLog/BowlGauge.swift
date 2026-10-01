//
//  BowlGauge.swift
//  FoodTracker
//
//  App 图标里的那只碗，用代码画出来，有两种用法：
//  - BowlGauge：「今日」卡片里的进度。吃了目标的几成，碗里就装到几成；吃到目标正好满碗，和 App 图标一模一样
//  - KindbiteMark：完整的图标图案（笑脸 + 碗），引导页第一页、没有内容时用
//  - SteamBowl：冒着热气的碗，全 App 的加载动画
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

    /// 碗里装了的部分要露出来的那一块：食物上沿以下的长方形（已经换算到页面上的位置）。
    /// 画法是「整个碗身涂上燕麦色，再用这个长方形裁剪」，不用路径求交：
    /// iOS 26 上「碗身 ∩ 长方形」在满碗（吃到或超过目标）时会算错，直接画出一个大方块（2026-10-01 用户手机上出现过）
    static func fillClipRect(fraction: Double, box: CGRect, in rect: CGRect) -> CGRect {
        guard fraction > 0 else { return .zero }  // 空碗：什么都不露
        let transform = transform(from: box, to: rect)
        let top = CGPoint(x: 0, y: fillTop(fraction: fraction)).applying(transform).y
        // 往下、往两边多留一点，碗底和两边的抗锯齿边缘不会被切掉；碗身之外本来就没有东西可露
        return CGRect(x: rect.minX - 2, y: top, width: rect.width + 4, height: max(0, rect.maxY + 2 - top))
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

/// 碗里装了的食物露出来的那一块（食物上沿以下的长方形），用来裁剪碗身。fraction 变化时会有动画
private struct BowlFillMask: Shape {
    var fraction: Double
    let box: CGRect

    var animatableData: Double {
        get { fraction }
        set { fraction = newValue }
    }

    func path(in rect: CGRect) -> Path {
        Path(BowlGeometry.fillClipRect(fraction: fraction, box: box, in: rect))
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
            // 装了的部分：同一个碗身涂上燕麦色，只露出食物上沿以下那一块（裁剪，不用路径求交，见 fillClipRect）
            BowlPart(path: BowlGeometry.body, box: box).fill(AppColors.oatBowl)
                .clipShape(BowlFillMask(fraction: fraction, box: box))
            BowlPart(path: BowlGeometry.rim, box: box).fill(AppColors.oatRim)
        }
        .aspectRatio(box.width / box.height, contentMode: .fit)
        // 记了一餐，碗里慢慢装上去；系统设置了「减弱动态效果」就直接变
        .animation(reduceMotion ? nil : .spring(duration: 0.7, bounce: 0.15), value: fraction)
        .accessibilityHidden(true)  // 数字已经写在旁边的文字里
    }
}

/// 冒着热气的碗：全 App 唯一的加载动画（识别照片、生成食谱、换一个，见 StateViews.swift）。
/// - 碗本身几乎不动，只是很轻地「呼吸」：大小在 0.985～1.015 之间，2 秒一个来回
/// - 碗上方三缕热气，慢慢往上飘、同时变淡，2 秒一轮，三缕错开出现
/// - 完成时（isFinishing）：热气停下、淡出，碗轻轻放大一点
/// - 出错时（showsSteam: false）：只有碗，没有热气
/// 系统设置了「减弱动态效果」时什么都不动：热气停在半空、很淡
struct SteamBowl: View {
    var isFinishing = false
    var showsSteam = true
    var palette = Palette.oat

    /// 颜色：平时是燕麦色；放在橄榄绿按钮上时用暖白
    enum Palette {
        case oat, onBrand
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 整个图案的画布：碗（和图标一样的坐标）+ 上面留给热气的空间
    static let box = CGRect(x: 182, y: 196, width: 660, height: 584)

    var body: some View {
        TimelineView(.animation(paused: reduceMotion || isFinishing || !showsSteam)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            ZStack {
                if showsSteam {
                    SteamLayer(time: reduceMotion ? nil : time, color: steamColor)
                        .opacity(isFinishing ? 0 : 1)
                }
                ZStack {
                    BowlPart(path: BowlGeometry.body, box: Self.box).fill(bodyColor)
                    BowlPart(path: BowlGeometry.rim, box: Self.box).fill(rimColor)
                }
                .scaleEffect(bowlScale(at: time), anchor: .bottom)
            }
        }
        .aspectRatio(Self.box.width / Self.box.height, contentMode: .fit)
        .animation(.easeOut(duration: 0.22), value: isFinishing)
        .accessibilityHidden(true)
    }

    /// 碗的大小：减弱动态效果时一直不动（完成时也不放大）；完成时放大一点；平时很轻地呼吸
    private func bowlScale(at time: TimeInterval) -> CGFloat {
        if reduceMotion || !showsSteam { return 1 }
        if isFinishing { return 1.05 }
        return 1 + 0.015 * sin(time / 2.0 * 2 * .pi)
    }

    private var bodyColor: Color { palette == .oat ? AppColors.oatBowl : AppColors.onBrand }
    private var rimColor: Color { palette == .oat ? AppColors.oatRim : AppColors.onBrand.opacity(0.75) }
    private var steamColor: Color { palette == .oat ? AppColors.oatRim : AppColors.onBrand }
}

/// 三缕热气：每一缕是一条 S 形的圆头细线，从碗沿上方往上飘，飘的同时先变清楚再变淡
struct SteamLayer: View {
    let time: TimeInterval?  // nil = 不动（减弱动态效果）
    let color: Color

    var body: some View {
        Canvas { context, size in
            let transform = BowlGeometry.transform(from: SteamBowl.box, to: CGRect(origin: .zero, size: size))
            for (index, x) in [CGFloat(420), 512, 604].enumerated() {
                let phase = Self.phase(time: time, index: index)
                let rise = 46 * phase
                var path = Path()
                path.move(to: CGPoint(x: x, y: 410 - rise))
                path.addCurve(
                    to: CGPoint(x: x, y: 250 - rise), control1: CGPoint(x: x - 30, y: 358 - rise),
                    control2: CGPoint(x: x + 30, y: 302 - rise))
                let stroke = path.strokedPath(StrokeStyle(lineWidth: 24, lineCap: .round)).applying(transform)
                context.fill(stroke, with: .color(color.opacity(Self.opacity(phase: phase, still: time == nil))))
            }
        }
    }

    /// 这一缕飘到哪了：0～1，三缕错开三分之一
    static func phase(time: TimeInterval?, index: Int) -> Double {
        guard let time else { return [0.45, 0.6, 0.3][index] }
        let cycle = time / 2.0 + Double(index) / 3
        return cycle - cycle.rounded(.down)
    }

    /// 透明度：刚冒出来时淡，中间最清楚，飘到上面又淡掉；不动的时候一直很淡
    static func opacity(phase: Double, still: Bool) -> Double {
        still ? 0.35 : 0.55 * sin(phase * .pi)
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
        SteamBowl().frame(width: 120)
    }
    .padding()
}
