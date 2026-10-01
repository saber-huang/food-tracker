//
//  SettingsPages.swift
//  FoodTracker
//
//  「我的」页点进去的两个设置页（都是二级页面：打开时底部标签栏收起来）：
//  - 热量提示：三个选项一行一个，选中的打勾；每个选项下面一句说明它会提示什么
//  两页都用和其他表单一样的样子（AppForm）
//  - AI 功能：一个开关（打开 = 同意把内容发给 AI，关闭 = 撤回同意），下面是「关于 AI 数据处理」
//  「我的」页本身只显示当前的值（比如「全部开启」「已开启」），说明文字都放在这两页里。
//

import SwiftUI

/// 热量提示：全部开启 / 只看每周小结 / 关闭
struct HintSettingsView: View {
    // 和「我的」页读的是同一个设置，这里一改，那边马上跟着变
    @AppStorage(HintKeys.level) private var hintLevel: HintLevel = .all

    var body: some View {
        AppForm {
            AppFormSection(nil, footer: HintCopy.settingsGoalNote) {
                ForEach(Array(HintLevel.allCases.enumerated()), id: \.element) { index, level in
                    if index > 0 { AppFormDivider() }
                    AppChoiceRow(
                        title: HintCopy.levelTitle(level), detail: HintCopy.levelExplanation(level), isSelected: level == hintLevel
                    ) {
                        hintLevel = level
                    }
                }
            }
        }
        .sensoryFeedback(.selection, trigger: hintLevel)
        .navigationTitle(HintCopy.settingsHeader)
        .navigationBarTitleDisplayMode(.inline)
        .hidesFloatingTabBar()
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
        AppForm {
            AppFormSection(nil, footer: String(localized: "拍照识别、生成食谱和推荐下一餐会用到 AI。关闭后，用到 AI 前会先问你；手动记录不受影响。")) {
                AppFormRow {
                    Toggle("允许使用 AI 功能", isOn: isOn)
                        .foregroundStyle(AppColors.textPrimary)
                        .tint(AppColors.brand)
                }
            }
            AppFormSection(nil) {
                NavigationLink {
                    AIDataInfoView()
                } label: {
                    AppFormLinkLabel(title: String(localized: "关于 AI 数据处理"))
                }
                .buttonStyle(AppPressStyle(scales: false))
            }
        }
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
