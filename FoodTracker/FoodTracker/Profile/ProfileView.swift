//
//  ProfileView.swift
//  FoodTracker
//
//  「我的」页面：查看每日目标和个人资料，点「编辑资料」修改；
//  下面是热量提示的设置、隐私与数据（隐私政策、AI 功能的同意、删除所有数据）和关于（意见反馈、版本号）。
//

import SwiftData
import SwiftUI

struct ProfileView: View {
    let profile: UserProfile
    /// 用户确认「删除所有数据」后调用：由最外层的 RootView 先离开主界面再删（见 RootView.swift）
    let onEraseAll: () -> Void

    @State private var isEditing = false
    @State private var confirmErase = false  // 是否弹出「删除所有数据？」的确认
    // 同意过第几版 AI 数据说明（0 = 没同意或撤回了）；在别的页面点了同意，这里也会马上变
    @AppStorage(AIConsent.key) private var aiConsentVersion = 0
    // 热量提示的设置，存在手机本地（UserDefaults）；默认全部开启
    @AppStorage(HintKeys.level) private var hintLevel: HintLevel = .all
    // 身高、体重用哪种单位显示和填写；没选过时按手机的地区（美国用英制）
    @AppStorage(UnitSystem.key) private var units: UnitSystem = UnitSystem.regionDefault()

    var body: some View {
        let bodyInfo = profile.bodyInfo
        let targets = profile.targets

        NavigationStack {
            List {
                Section("每日目标") {
                    TargetsSummaryView(targets: targets)
                    FloorNotice(targets: targets)
                    GoalNotesView(bodyInfo: bodyInfo)
                    NavigationLink("这些数字是怎么算的？") {
                        ExplanationView(bodyInfo: bodyInfo)
                    }
                }

                Section("个人资料") {
                    LabeledContent("性别", value: bodyInfo.sex.title)
                    LabeledContent("年龄", value: String(localized: "\(bodyInfo.age) 岁"))
                    LabeledContent("身高", value: BodyUnits.heightDisplay(cm: bodyInfo.heightCm, units: units))
                    LabeledContent("体重", value: BodyUnits.weightDisplay(kg: bodyInfo.weightKg, units: units))
                    LabeledContent("活动量", value: bodyInfo.activity.title)
                    LabeledContent("目标", value: bodyInfo.goal.title)
                    Picker("单位", selection: $units) {
                        ForEach(UnitSystem.allCases, id: \.self) { system in
                            Text(system.title).tag(system)
                        }
                    }
                    Button("编辑资料") { isEditing = true }
                }

                // 热量提示：全部开启 / 只看每周小结 / 关闭（文案都在 HintCopy 里）
                Section {
                    Picker(HintCopy.settingsPickerLabel, selection: $hintLevel) {
                        ForEach(HintLevel.allCases, id: \.self) { level in
                            Text(HintCopy.levelTitle(level)).tag(level)
                        }
                    }
                } header: {
                    Text(HintCopy.settingsHeader)
                } footer: {
                    Text(HintCopy.levelExplanation(hintLevel) + "\n\n" + HintCopy.settingsGoalNote)
                }

                // 隐私与数据：隐私政策、AI 功能的同意、删除所有数据
                Section {
                    NavigationLink("隐私政策") {
                        PrivacyPolicyView()
                    }
                    NavigationLink {
                        AIDataInfoView()
                    } label: {
                        LabeledContent("AI 功能", value: AIConsent.isGranted(version: aiConsentVersion) ? String(localized: "已同意") : String(localized: "未同意"))
                    }
                    if AIConsent.isGranted(version: aiConsentVersion) {
                        // 撤回很安全：只是下次用 AI 功能前再问一次，所以不用再确认
                        Button("撤回 AI 功能的同意") { AIConsent.revoke() }
                    }
                    Button("删除所有数据", role: .destructive) { confirmErase = true }
                } header: {
                    Text("隐私与数据")
                } footer: {
                    Text("撤回同意后，下次拍照识别或生成食谱前会再问你，手动记录不受影响。")
                }

                // 关于：意见反馈、版本号，最下面是健康提示
                Section {
                    // 联系邮箱还没定时不显示（见 SupportInfo.swift）
                    if let feedbackURL = SupportInfo.feedbackURL {
                        Link("意见反馈", destination: feedbackURL)
                    }
                    LabeledContent("版本", value: SupportInfo.versionText)
                } header: {
                    Text("关于")
                } footer: {
                    Text("热量和营养目标是根据公式估算的参考值，不是医疗建议。如有疾病（尤其是肾病、糖尿病）、处于孕期或哺乳期，或有饮食失调史，请先咨询医生或注册营养师。")
                }

                #if DEBUG && targetEnvironment(simulator)
                // 只在模拟器里出现的开发者工具：一键造出各种热量提示
                DebugHintSection(profile: profile)
                #endif
            }
            .navigationTitle("我的")
            .sheet(isPresented: $isEditing) {
                ProfileEditView(profile: profile)
            }
            // 删除前再确认一次：删掉就找不回来了
            .confirmationDialog("删除所有数据？", isPresented: $confirmErase, titleVisibility: .visible) {
                Button("删除所有数据", role: .destructive) { onEraseAll() }
                Button("取消", role: .cancel) {}
            } message: {
                Text("会删掉这台手机上的个人资料、全部饮食记录和设置，删除后无法恢复。")
            }
        }
    }
}

/// 编辑资料：改完点「保存」，每日目标会自动重新计算
struct ProfileEditView: View {
    let profile: UserProfile

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var draft: ProfileDraft

    init(profile: UserProfile) {
        self.profile = profile
        // 用原来的资料生成一份草稿；不点保存的话，原来的资料不会变
        _draft = State(initialValue: ProfileDraft(from: profile.bodyInfo, units: UnitSystem.current()))
    }

    var body: some View {
        NavigationStack {
            Form {
                BasicInfoSection(draft: draft)
                ActivitySection(draft: draft)
                GoalSection(draft: draft)

                // 边改边预览新的目标
                if let bodyInfo = draft.bodyInfo {
                    let targets = NutritionCalculator.targets(for: bodyInfo)
                    Section("保存后的每日目标") {
                        TargetsSummaryView(targets: targets)
                        FloorNotice(targets: targets)
                    }
                }
            }
            .navigationTitle("编辑资料")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(draft.bodyInfo == nil)  // 有填错的地方就不能保存
                }
            }
        }
    }

    private func save() {
        guard let bodyInfo = draft.bodyInfo else { return }
        profile.update(with: bodyInfo)
        try? modelContext.save()
        dismiss()
    }
}
