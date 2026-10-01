//
//  SettingsPages.swift
//  FoodTracker
//
//  「我的」页点进去的两个设置页（都是二级页面：打开时底部标签栏收起来）：
//  - 热量提示：三个选项一行一个，选中的打勾；每个选项下面一句说明它会提示什么
//  - AI 功能：一个开关（打开 = 同意把内容发给 AI，关闭 = 撤回同意），下面是「关于 AI 数据处理」
//  「我的」页本身只显示当前的值（比如「全部开启」「已开启」），说明文字都放在这两页里。
//

import SwiftUI

/// 热量提示：全部开启 / 只看每周小结 / 关闭
struct HintSettingsView: View {
    // 和「我的」页读的是同一个设置，这里一改，那边马上跟着变
    @AppStorage(HintKeys.level) private var hintLevel: HintLevel = .all

    var body: some View {
        List {
            Section {
                ForEach(HintLevel.allCases, id: \.self) { level in
                    Button {
                        hintLevel = level
                    } label: {
                        HintLevelRow(level: level, isSelected: level == hintLevel)
                    }
                    .buttonStyle(AppPressStyle(scales: false))  // 整行只变淡，不缩放
                    .accessibilityAddTraits(level == hintLevel ? .isSelected : [])
                }
            } footer: {
                Text(HintCopy.settingsGoalNote)
            }
            .appCardRow()
        }
        .listStyle(.insetGrouped)
        .contentMargins(.horizontal, AppSpacing.pageMargin, for: .scrollContent)
        .appListBackground()
        .navigationTitle(HintCopy.settingsHeader)
        .navigationBarTitleDisplayMode(.inline)
        .hidesFloatingTabBar()
    }
}

/// 热量提示的一个选项：名称 + 一句说明，选中的右边打勾
private struct HintLevelRow: View {
    let level: HintLevel
    let isSelected: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: AppSpacing.sm) {
            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                Text(HintCopy.levelTitle(level))
                    .foregroundStyle(AppColors.textPrimary)
                Text(HintCopy.levelExplanation(level))
                    .font(AppTypography.detail)
                    .foregroundStyle(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)  // 说明很长时换行，不截断
            }
            Spacer(minLength: 0)
            // 没选中时也占着位置（只是看不见），选来选去时文字不会左右跳
            Image(systemName: "checkmark")
                .font(.body.weight(.semibold))
                .foregroundStyle(AppColors.brand)
                .opacity(isSelected ? 1 : 0)
                .accessibilityHidden(true)
        }
        .padding(.vertical, AppSpacing.xs)
        .frame(minHeight: 44)
        .contentShape(Rectangle())  // 整行都能点，不只是文字
    }
}

/// AI 功能：开关 + 「关于 AI 数据处理」
struct AISettingsView: View {
    // 同意过第几版 AI 数据说明（0 = 没同意或撤回了）
    @AppStorage(AIConsent.key) private var aiConsentVersion = 0
    // 打开开关时，还没同意过的话先弹出说明（和第一次拍照识别时弹的是同一份）
    @State private var pendingAIAction: PendingAIAction?

    /// 开关绑定的是「同意了没有」：打开 = 先看说明、点同意；关闭 = 撤回同意
    private var isOn: Binding<Bool> {
        Binding {
            AIConsent.isGranted(version: aiConsentVersion)
        } set: { turnOn in
            if turnOn {
                // 说明里点「同意并继续」才算打开；点「暂不使用」开关会自己弹回关闭
                AIConsent.perform(pending: $pendingAIAction) {}
            } else {
                // 关闭很安全：只是下次用 AI 之前再问一次，所以不用再确认
                AIConsent.revoke()
            }
        }
    }

    var body: some View {
        List {
            Section {
                Toggle("允许使用 AI 功能", isOn: isOn)
                    .tint(AppColors.brand)
                    .frame(minHeight: 44)
            } footer: {
                Text("拍照识别、生成食谱和推荐下一餐会用到 AI。关闭后，用到 AI 前会先问你；手动记录不受影响。")
            }
            .appCardRow()

            Section {
                NavigationLink("关于 AI 数据处理") {
                    AIDataInfoView()
                }
            }
            .appCardRow()
        }
        .listStyle(.insetGrouped)
        .contentMargins(.horizontal, AppSpacing.pageMargin, for: .scrollContent)
        .appListBackground()
        .navigationTitle("AI 功能")
        .navigationBarTitleDisplayMode(.inline)
        .hidesFloatingTabBar()
        .aiConsentSheet(pending: $pendingAIAction)
    }
}

#Preview("热量提示") {
    NavigationStack {
        HintSettingsView()
    }
}

#Preview("AI 功能") {
    NavigationStack {
        AISettingsView()
    }
}
