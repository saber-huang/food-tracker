//
//  ProfileFormSections.swift
//  FoodTracker
//
//  填写资料用的三块表单：基本信息、活动量、目标。和其他表单页同一套样子（AppFormSection，见 AppForm.swift）。
//  引导页每一步用其中一块，「编辑资料」页把三块放在一起用（都放在 AppForm 里）。
//  @Bindable 让这些界面可以直接修改 ProfileDraft 里的数据。
//

import Accessibility
import SwiftUI

// MARK: - 基本信息：性别、年龄、身高、体重

struct BasicInfoSection: View {
    @Bindable var draft: ProfileDraft
    /// 身高、体重用哪种单位（和「我的」页的设置是同一个）
    @AppStorage(UnitSystem.key) private var units: UnitSystem = UnitSystem.regionDefault()

    /// 记住当前正在输入的是哪个框，用来收起键盘
    @FocusState private var focusedField: Field?
    private enum Field { case age, height, feet, inches, weight }

    var body: some View {
        AppFormSection(String(localized: "基本信息"), footer: String(localized: "性别只用于计算基础代谢，公式里男女的数值不同。")) {
            AppSegmentedControl(title: String(localized: "性别"), selection: $draft.sex, options: Sex.allCases) { $0.title }
                .padding(AppSpacing.sm)
                // 数字键盘没有「完成」键，在键盘上方加一个。
                // 注意只挂在这一个地方：挂在每一行上会出现好几个「完成」
                .toolbar {
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button("完成") { focusedField = nil }
                    }
                }
            AppFormDivider()

            NumberRow(
                title: String(localized: "年龄"), unit: String(localized: "岁"), text: $draft.ageText,
                keyboard: .numberPad, error: draft.ageError,
                focus: $focusedField, field: .age
            )
            AppFormDivider()

            // 单位：切换时已经填好的身高、体重会换算过去
            AppSegmentedControl(title: String(localized: "单位"), selection: $units, options: UnitSystem.allCases) {
                $0.shortTitle
            }
            .padding(AppSpacing.sm)
            AppFormDivider()

            switch draft.units {
            case .metric:
                NumberRow(
                    title: String(localized: "身高"), unit: String(localized: "厘米"), text: $draft.heightText,
                    keyboard: .decimalPad, error: draft.heightError,
                    focus: $focusedField, field: .height
                )
            case .imperial:
                FeetInchesRow(
                    feet: $draft.feetText, inches: $draft.inchesText, error: draft.heightError,
                    focus: $focusedField, feetField: .feet, inchesField: .inches
                )
            }

            AppFormDivider()
            NumberRow(
                title: String(localized: "体重"), unit: draft.units == .metric ? String(localized: "公斤") : String(localized: "磅"),
                text: $draft.weightText,
                keyboard: .decimalPad, error: draft.weightError ?? draft.plausibilityError,
                focus: $focusedField, field: .weight
            )

            // BMI 很高时提醒确认单位（不阻止继续）
            if let warning = draft.unitWarning {
                Label(warning, systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(AppColors.textSecondary)
                    .padding(.horizontal, AppSpacing.cardPadding)
                    .padding(.bottom, AppSpacing.sm)
            }
        }
        // 草稿的单位跟着设置走：打开页面时对齐一次，之后设置一变就换算
        .onAppear { draft.switchUnits(to: units) }
        .onChange(of: units) { _, newUnits in
            focusedField = nil
            draft.switchUnits(to: newUnits)
        }
    }
}

/// 英制身高：一行里两个输入框，「5 英尺 7 英寸」
private struct FeetInchesRow<Field: Hashable>: View {
    @Binding var feet: String
    @Binding var inches: String
    let error: String?
    let focus: FocusState<Field?>.Binding
    let feetField: Field
    let inchesField: Field

    private var isEditing: Bool { focus.wrappedValue == feetField || focus.wrappedValue == inchesField }

    /// 和 NumberRow 一样：还没输入、或者正在输入时不显示错误
    private var shownError: String? {
        let hasText = !feet.isEmpty || !inches.isEmpty
        return hasText && !isEditing ? error : nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("身高")
                    .foregroundStyle(AppColors.textPrimary)
                    .accessibilityHidden(true)
                Spacer()
                TextField("身高（英尺）", text: $feet, prompt: Text(verbatim: "5"))
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 56)
                    .focused(focus, equals: feetField)
                Text("英尺")
                    .foregroundStyle(AppColors.textSecondary)
                    .accessibilityHidden(true)
                TextField("身高（英寸）", text: $inches, prompt: Text(verbatim: "7"))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 56)
                    .focused(focus, equals: inchesField)
                Text("英寸")
                    .foregroundStyle(AppColors.textSecondary)
                    .accessibilityHidden(true)
            }

            if let shownError {
                Text(shownError)
                    .font(.caption)
                    .foregroundStyle(AppColors.destructive)
            }
        }
        .padding(.horizontal, AppSpacing.cardPadding)
        .padding(.vertical, AppSpacing.sm)
        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
        // 红色提示出现时，让旁白念出来
        .onChange(of: shownError) { _, newError in
            if let newError {
                AccessibilityNotification.Announcement(newError).post()
            }
        }
    }
}

// MARK: - 活动量

struct ActivitySection: View {
    @Bindable var draft: ProfileDraft

    var body: some View {
        AppFormSection(String(localized: "日常活动量"), footer: String(localized: "按大多数星期的实际情况选；2～3 周后再根据体重变化调整。")) {
            ForEach(Array(ActivityLevel.allCases.enumerated()), id: \.element) { index, level in
                if index > 0 { AppFormDivider() }
                AppChoiceRow(title: level.title, detail: level.detail, isSelected: draft.activity == level) {
                    draft.activity = level
                }
            }
        }
    }
}

// MARK: - 目标

struct GoalSection: View {
    @Bindable var draft: ProfileDraft

    var body: some View {
        AppFormSection(String(localized: "你的目标")) {
            ForEach(Array(Goal.allCases.enumerated()), id: \.element) { index, goal in
                // 不适合减脂的人（体重偏轻，或 65 岁以上且 BMI 低于 30），「减脂」这一项不能选
                let disabled = goal == .loseFat && draft.fatLossRestriction != nil
                if index > 0 { AppFormDivider() }
                AppChoiceRow(title: goal.title, detail: goal.detail, isSelected: draft.goal == goal) {
                    draft.goal = goal
                }
                .disabled(disabled)
                .opacity(disabled ? 0.4 : 1)
            }
            // 用平静的灰色说明，不用红色或橙色的「警告」样式
            if let message = draft.fatLossRestriction {
                AppFormDivider()
                note(message)
            }
            ForEach(draft.goalNotes, id: \.self) { message in
                AppFormDivider()
                note(message)
            }
        }
    }

    private func note(_ text: String) -> some View {
        Label(text, systemImage: "info.circle")
            .font(.callout)
            .foregroundStyle(AppColors.textSecondary)
            .padding(.horizontal, AppSpacing.cardPadding)
            .padding(.vertical, AppSpacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
