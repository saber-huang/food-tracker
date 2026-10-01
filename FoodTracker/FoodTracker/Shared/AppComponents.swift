//
//  AppComponents.swift
//  FoodTracker
//
//  全 App 共用的几种控件，新页面直接用，不另外设计：
//  - AppButtonStyle：四种按钮
//      主要（primary）：橄榄绿底、暖白字，50pt 高、中圆角 18。一页最多一个
//      次要（secondary）：燕麦色底、深橄榄字
//      第三级（tertiary）：没有底色，灰色字（「取消分析」「暂不使用」这类）
//      删除（destructive）：砖红字，只给真正会删东西的按钮
//  - AppSegmentedControl：分段选择（早餐 / 午餐 / 晚餐 / 加餐、15 / 30 / 45 分钟…）：
//    燕麦色的胶囊槽，选中的一格是暖白小胶囊、深橄榄字，和底部标签栏选中的样子是同一种语言
//  - AppSheetHeader + appSheet()：弹出页（手动添加、偏好和忌口、编辑资料…）统一的顶栏和背景：
//    左边「取消」（灰字），中间标题，右边「保存」（橄榄绿字），不用系统顶栏那种悬浮的白色胶囊按钮。
//    表单都在顶栏右边保存，不在页面底部另放一个大按钮
//

import SwiftUI

// MARK: - 按钮

struct AppButtonStyle: ButtonStyle {
    enum Kind {
        case primary, secondary, tertiary, destructive
    }

    var kind: Kind = .primary
    /// 看起来是「还不能点」的浅色，但仍然可以点（比如还没填完的表单：点了会提示缺什么）
    var dimmed = false
    /// 第三级按钮的字也可以是橄榄绿（「再拍一张」这类和主操作相关、但更轻的动作）；不写就是灰色
    var tint: Color?
    /// 铺满一整行（默认）；false 时按文字的宽度
    var fullWidth = true

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(kind == .tertiary ? .subheadline.weight(.medium) : .body.weight(.semibold))
            .foregroundStyle(foreground)
            .lineLimit(2)
            .multilineTextAlignment(.center)
            .padding(.horizontal, AppSpacing.md)
            .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: kind == .tertiary ? 44 : 50)
            .background {
                if let background {
                    RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous)
                        .fill(background)
                }
            }
            .contentShape(Rectangle())
            .opacity(isEnabled && !dimmed ? 1 : 0.45)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion && kind != .tertiary ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }

    private var foreground: Color {
        switch kind {
        case .primary: AppColors.onBrand
        case .secondary: AppColors.brandDeep
        case .tertiary: tint ?? AppColors.textSecondary
        case .destructive: AppColors.destructive
        }
    }

    private var background: Color? {
        switch kind {
        case .primary: AppColors.brand
        case .secondary, .destructive: AppColors.surfaceSecondary
        case .tertiary: nil
        }
    }
}

extension ButtonStyle where Self == AppButtonStyle {
    static var appPrimary: AppButtonStyle { AppButtonStyle(kind: .primary) }
    static var appSecondary: AppButtonStyle { AppButtonStyle(kind: .secondary) }
    static var appTertiary: AppButtonStyle { AppButtonStyle(kind: .tertiary) }
    static var appDestructive: AppButtonStyle { AppButtonStyle(kind: .destructive) }
}

// MARK: - 分段选择

/// 分段选择：一排胶囊。每一格是一个按钮（旁白读「已选择」），点了轻轻震一下。
/// 字号特别大时文字可以换行，格子跟着变高
struct AppSegmentedControl<Value: Hashable>: View {
    let title: String  // 给旁白读的名字（「记到哪一餐」）
    @Binding var selection: Value
    let options: [Value]
    let label: (Value) -> String
    /// 旁白读的文字（不写就和屏幕上一样）。比如屏幕上只写「30」，旁白读「30 分钟」
    var accessibilityLabel: ((Value) -> String)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var pill

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.self) { option in
                let isSelected = option == selection
                Button {
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) { selection = option }
                } label: {
                    Text(label(option))
                        .font(.subheadline.weight(isSelected ? .semibold : .medium))
                        .foregroundStyle(isSelected ? AppColors.brandDeep : AppColors.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, AppSpacing.xxs)
                        .padding(.vertical, AppSpacing.xs)
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .background {
                            if isSelected {
                                Capsule()
                                    .fill(AppColors.segmentSelected)
                                    .appShadow(AppShadowStyle(opacity: 0.04, radius: 4, y: 1))
                                    .matchedGeometryEffect(id: "pill", in: pill)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(accessibilityLabel?(option) ?? label(option))
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(AppSpacing.xxs)
        .frame(minHeight: 44)
        .background(AppColors.segmentTrack, in: Capsule())
        .sensoryFeedback(.selection, trigger: selection)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }
}

// MARK: - 弹出页

/// 弹出页的顶栏：左「取消」、中间标题、右边一个可选的文字按钮（「保存」「完成」）。
/// 标题始终在正中间；按钮是普通文字，不是悬浮的胶囊
struct AppSheetHeader: View {
    let title: String
    var cancelTitle = String(localized: "取消")
    var onCancel: (() -> Void)?
    var confirmTitle: String?
    var confirmEnabled = true
    /// 看起来是浅色的「还不能保存」，但仍然可以点：点了由页面提示还缺什么（手动添加）
    var confirmDimmed = false
    var onConfirm: (() -> Void)?

    var body: some View {
        ZStack {
            Text(title)
                .font(.headline)
                .foregroundStyle(AppColors.textPrimary)
                .lineLimit(1)
                .padding(.horizontal, 88)  // 不和两边的按钮叠在一起
                .accessibilityAddTraits(.isHeader)
            HStack {
                if let onCancel {
                    Button(cancelTitle, action: onCancel)
                        .font(.body)
                        .foregroundStyle(AppColors.textSecondary)
                        .frame(minWidth: 44, minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                }
                Spacer()
                if let confirmTitle, let onConfirm {
                    Button(confirmTitle, action: onConfirm)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(AppColors.brand)
                        .opacity(confirmEnabled && !confirmDimmed ? 1 : 0.45)
                        .disabled(!confirmEnabled)
                        .accessibilityHint(confirmDimmed ? String(localized: "还有必填项没有填") : "")
                        .frame(minWidth: 44, minHeight: 44, alignment: .trailing)
                        .contentShape(Rectangle())
                }
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, AppSpacing.pageMargin)
        .padding(.top, AppSpacing.sm)
        .padding(.bottom, AppSpacing.xxs)
        .frame(maxWidth: .infinity)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }
}

extension View {
    /// 弹出页统一的底色：App 的暖色背景（不用系统的冷灰色）
    func appSheet() -> some View {
        presentationBackground(AppColors.background)
    }

    /// 把 AppSheetHeader 固定在弹出页最上面：背景和页面顶部同一个颜色，下边缘淡出，内容滑上去时被柔和地盖住
    func appSheetHeader(_ header: AppSheetHeader) -> some View {
        safeAreaInset(edge: .top, spacing: 0) {
            header
                .background {
                    AppColors.backgroundTop
                        .ignoresSafeArea(edges: .top)
                }
                .overlay(alignment: .bottom) {
                    LinearGradient(
                        colors: [AppColors.backgroundTop, AppColors.backgroundTop.opacity(0)], startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: AppSpacing.sm)
                    .offset(y: AppSpacing.sm)
                    .allowsHitTesting(false)
                }
        }
    }
}

#Preview("按钮和分段选择") {
    @Previewable @State var meal = "午餐"
    VStack(spacing: 16) {
        AppSheetHeader(title: "偏好和忌口", onCancel: {}, confirmTitle: "保存", onConfirm: {})
        Button("保存") {}.buttonStyle(.appPrimary)
        Button("重新生成一日三餐") {}.buttonStyle(.appSecondary)
        Button("取消分析") {}.buttonStyle(.appTertiary)
        Button("删除所有数据") {}.buttonStyle(.appDestructive)
        AppSegmentedControl(title: "记到哪一餐", selection: $meal, options: ["早餐", "午餐", "晚餐", "加餐"]) { $0 }
    }
    .padding()
    .background(AppColors.background)
}
