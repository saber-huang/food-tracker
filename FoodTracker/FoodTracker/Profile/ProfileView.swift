//
//  ProfileView.swift
//  FoodTracker
//
//  「我的」页面：查看每日目标和个人资料，点「编辑资料」修改。
//

import SwiftData
import SwiftUI

struct ProfileView: View {
    let profile: UserProfile

    @State private var isEditing = false
    // 热量提示的设置，存在手机本地（UserDefaults）；默认全部开启
    @AppStorage(HintKeys.level) private var hintLevel: HintLevel = .all

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
                    LabeledContent("年龄", value: "\(bodyInfo.age) 岁")
                    LabeledContent("身高", value: "\(bodyInfo.heightCm.oneDecimal) 厘米")
                    LabeledContent("体重", value: "\(bodyInfo.weightKg.oneDecimal) 公斤")
                    LabeledContent("活动量", value: bodyInfo.activity.title)
                    LabeledContent("目标", value: bodyInfo.goal.title)
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

                Section {
                    Text("热量和营养目标是根据公式估算的参考值，不是医疗建议。如有疾病（尤其是肾病、糖尿病）、处于孕期或哺乳期，或有饮食失调史，请先咨询医生或注册营养师。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
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
        _draft = State(initialValue: ProfileDraft(from: profile.bodyInfo))
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
