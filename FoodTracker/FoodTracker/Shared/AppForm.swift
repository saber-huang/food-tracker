//
//  AppForm.swift
//  FoodTracker
//
//  所有表单、设置页共用的一套样子（手动添加、偏好和忌口、编辑资料、热量提示、AI 功能…），不用系统的 Form：
//  - AppForm：滚动的一列，App 的暖色背景，左右 20，块和块之间 24；往下拖可以收起键盘
//  - AppFormSection：一块 = 标题（17pt 半粗，右边可以放 ⓘ 或一个小操作）+ 一张暖白的中圆角卡片（18）
//    + 可选的一行灰色小字。卡片里一行一行，行之间用 AppFormDivider 隔开（很淡，从文字开始）
//  - AppFormRow：卡片里的一行（左右 16，至少 52pt 高）
//  - AppFormTextField：一行（或几行）输入框，点这一行的任何地方都能开始输入
//  - AppChoiceRow：可以选的一项（标题 + 一句说明，选中的打勾）
//  - AppFormLinkLabel：点了进入下一页的一行（标题、右边的值、小箭头）
//  键盘、旁白、动态字号都还是系统的，只是外观换成 App 自己的
//

import SwiftUI

/// 表单页面的整体：滚动的一列
struct AppForm<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.formSectionGap) {
                content
            }
            .padding(.horizontal, AppSpacing.pageMargin)
            .padding(.top, AppSpacing.md)
            .padding(.bottom, AppSpacing.xxl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollDismissesKeyboard(.interactively)
        .background { AppBackground(glow: false) }
    }
}

/// 表单里的一块：标题 + 一张卡片 + 可选的一行小字
struct AppFormSection<Content: View, Accessory: View>: View {
    let title: String?
    var footer: String?
    @ViewBuilder var accessory: Accessory
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            if let title {
                HStack(alignment: .center, spacing: AppSpacing.xs) {
                    Text(title)
                        .font(AppTypography.sectionTitle)
                        .foregroundStyle(AppColors.textPrimary)
                        .accessibilityAddTraits(.isHeader)
                    Spacer(minLength: AppSpacing.xs)
                    accessory
                        .padding(.vertical, -AppSpacing.sm)  // ⓘ 的点击范围是 44pt，但不把标题撑高
                }
                .padding(.horizontal, AppSpacing.xxs)
            }
            VStack(alignment: .leading, spacing: 0) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .appCard(.form)
            if let footer {
                Text(footer)
                    .font(AppTypography.detail)
                    .foregroundStyle(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, AppSpacing.xxs)
            }
        }
    }
}

extension AppFormSection where Accessory == EmptyView {
    init(_ title: String?, footer: String? = nil, @ViewBuilder content: () -> Content) {
        self.init(title: title, footer: footer, accessory: { EmptyView() }, content: content)
    }
}

/// 卡片里的一行
struct AppFormRow<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: AppSpacing.sm) {
            content
        }
        .padding(.horizontal, AppSpacing.cardPadding)
        .padding(.vertical, AppSpacing.xs)
        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
    }
}

/// 两行之间的分隔线：很淡，从文字开始（左边留 16）
struct AppFormDivider: View {
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Rectangle()
            .fill(AppColors.divider)
            .frame(height: 1 / displayScale)
            .padding(.leading, AppSpacing.cardPadding)
            .accessibilityHidden(true)
    }
}

/// 一行（或几行）输入框：灰色的提示字，点这一行的任何地方都能开始输入
struct AppFormTextField: View {
    let title: String  // 旁白读的名字
    let placeholder: String
    @Binding var text: String
    var multiline = false

    @FocusState private var isFocused: Bool

    var body: some View {
        TextField(
            title, text: $text, prompt: Text(placeholder).foregroundStyle(AppColors.textTertiary),
            axis: multiline ? .vertical : .horizontal
        )
        .lineLimit(multiline ? 1...5 : 1...1)
        .foregroundStyle(AppColors.textPrimary)
        .focused($isFocused)
        .padding(.horizontal, AppSpacing.cardPadding)
        .padding(.vertical, 15)
        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture { isFocused = true }
        .accessibilityLabel(title)
    }
}

/// 可以选的一项：标题 + 一句说明，选中的右边打勾（没选中时对勾占着位置但看不见，文字不会左右跳）
struct AppChoiceRow: View {
    let title: String
    var detail: String?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: AppSpacing.sm) {
                VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                    Text(title)
                        .font(.body)
                        .foregroundStyle(AppColors.textPrimary)
                    if let detail {
                        Text(detail)
                            .font(AppTypography.detail)
                            .foregroundStyle(AppColors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "checkmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(AppColors.brand)
                    .opacity(isSelected ? 1 : 0)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, AppSpacing.cardPadding)
            .padding(.vertical, AppSpacing.sm)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(AppPressStyle(scales: false))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// 点了进入下一页的一行：标题，右边是当前的值和小箭头（放在 NavigationLink 的 label 里）
struct AppFormLinkLabel: View {
    let title: String
    var value: String?

    var body: some View {
        HStack(spacing: AppSpacing.xs) {
            Text(title)
                .foregroundStyle(AppColors.textPrimary)
            Spacer(minLength: AppSpacing.xs)
            if let value {
                Text(value)
                    .foregroundStyle(AppColors.textSecondary)
                    .multilineTextAlignment(.trailing)
            }
            AppChevron()
        }
        .padding(.horizontal, AppSpacing.cardPadding)
        .padding(.vertical, AppSpacing.xs)
        .frame(maxWidth: .infinity, minHeight: 52)
        .contentShape(Rectangle())
    }
}

#Preview {
    @Previewable @State var text = ""
    @Previewable @State var minutes = 30
    AppForm {
        AppFormSection("饮食偏好（可选）") {
            AppFormTextField(title: "饮食偏好", placeholder: "例如：清淡少油", text: $text, multiline: true)
        }
        AppFormSection(title: "过敏食材", accessory: { InfoButton(topic: .allergies) }) {
            AppFormTextField(title: "过敏食材", placeholder: "例如：花生、虾", text: $text)
        }
        AppFormSection("热量提示", footer: "只在目标为「减脂」时显示。") {
            AppChoiceRow(title: "全部开启", detail: "接近目标时提前告诉你。", isSelected: true) {}
            AppFormDivider()
            AppChoiceRow(title: "关闭", isSelected: false) {}
        }
        AppFormSection("每餐可接受的烹饪时间") {
            AppSegmentedControl(title: "烹饪时间", selection: $minutes, options: [15, 30, 45, 60, 90]) { "\($0)" }
                .padding(AppSpacing.sm)
        }
    }
}
