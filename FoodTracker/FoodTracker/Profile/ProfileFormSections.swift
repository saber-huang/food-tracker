//
//  ProfileFormSections.swift
//  FoodTracker
//
//  填写资料用的三块表单：基本信息、活动量、目标。
//  引导页每一步用其中一块，「编辑资料」页把三块放在一起用。
//  @Bindable 让这些界面可以直接修改 ProfileDraft 里的数据。
//

import SwiftUI

// MARK: - 基本信息：性别、年龄、身高、体重

struct BasicInfoSection: View {
    @Bindable var draft: ProfileDraft

    /// 记住当前正在输入的是哪个框，用来收起键盘
    @FocusState private var focusedField: Field?
    private enum Field { case age, height, weight }

    var body: some View {
        Section {
            Picker("性别", selection: $draft.sex) {
                ForEach(Sex.allCases, id: \.self) { sex in
                    Text(sex.title).tag(sex)
                }
            }
            .pickerStyle(.segmented)
            // 数字键盘没有「完成」键，在键盘上方加一个。
            // 注意只挂在这一行上：挂在整个 Section 上会给每一行各加一个，出现好几个「完成」
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("完成") { focusedField = nil }
                }
            }

            NumberRow(
                title: String(localized: "年龄"), unit: String(localized: "岁"), text: $draft.ageText,
                keyboard: .numberPad, error: draft.ageError,
                focus: $focusedField, field: .age
            )

            NumberRow(
                title: String(localized: "身高"), unit: String(localized: "厘米"), text: $draft.heightText,
                keyboard: .decimalPad, error: draft.heightError,
                focus: $focusedField, field: .height
            )

            NumberRow(
                title: String(localized: "体重"), unit: String(localized: "公斤"), text: $draft.weightText,
                keyboard: .decimalPad, error: draft.weightError ?? draft.plausibilityError,
                focus: $focusedField, field: .weight
            )

            // BMI 很高时提醒确认单位（不阻止继续）
            if let warning = draft.unitWarning {
                Label(warning, systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("基本信息")
        } footer: {
            Text("性别只用于计算基础代谢，公式里男女的数值不同。")
        }
    }
}

// MARK: - 活动量

struct ActivitySection: View {
    @Bindable var draft: ProfileDraft

    var body: some View {
        Section {
            ForEach(ActivityLevel.allCases, id: \.self) { level in
                ChoiceRow(title: level.title, detail: level.detail, isSelected: draft.activity == level) {
                    draft.activity = level
                }
            }
        } header: {
            Text("日常活动量")
        } footer: {
            Text("按大多数星期的实际情况选；2～3 周后再根据体重变化调整。")
        }
    }
}

// MARK: - 目标

struct GoalSection: View {
    @Bindable var draft: ProfileDraft

    var body: some View {
        Section {
            ForEach(Goal.allCases, id: \.self) { goal in
                // 不适合减脂的人（体重偏轻，或 65 岁以上且 BMI 低于 30），「减脂」这一项不能选
                let disabled = goal == .loseFat && draft.fatLossRestriction != nil
                ChoiceRow(title: goal.title, detail: goal.detail, isSelected: draft.goal == goal) {
                    draft.goal = goal
                }
                .disabled(disabled)
                .opacity(disabled ? 0.4 : 1)
            }
            // 用平静的灰色说明，不用红色或橙色的「警告」样式
            if let message = draft.fatLossRestriction {
                Label(message, systemImage: "info.circle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            ForEach(draft.goalNotes, id: \.self) { note in
                Label(note, systemImage: "info.circle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("你的目标")
        }
    }
}

/// 一个可以点选的选项：标题 + 说明 + 选中时的对勾
private struct ChoiceRow: View {
    let title: String
    let detail: String
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .foregroundStyle(.primary)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                        .fontWeight(.semibold)
                }
            }
            .contentShape(Rectangle())  // 整行都可以点
        }
        .buttonStyle(.plain)  // 不用按钮默认的蓝色，标题保持黑色、说明保持灰色
    }
}
