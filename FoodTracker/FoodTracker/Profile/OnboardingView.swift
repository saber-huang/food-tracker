//
//  OnboardingView.swift
//  FoodTracker
//
//  第一次打开 App 时的引导流程：欢迎 → 基本信息 → 活动量 → 目标 → 你的每日目标。
//  最后一步点「开始使用」时，把资料保存到手机本地。
//

import SwiftData
import SwiftUI

struct OnboardingView: View {
    /// SwiftData 的「数据库入口」，用来保存新资料
    @Environment(\.modelContext) private var modelContext

    @State private var draft = ProfileDraft(units: UnitSystem.current())
    @State private var step: Step = .welcome
    @State private var hasAgreed = false  // 是否勾选了「我已了解」

    /// 引导的每一步
    private enum Step: Int, CaseIterable {
        case welcome, basicInfo, activity, goal, result
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 顶部进度条
                ProgressView(value: Double(step.rawValue), total: Double(Step.allCases.count - 1))
                    .padding(.horizontal)

                currentStep
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if step != .welcome {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("上一步") { go(to: step.rawValue - 1) }
                    }
                }
            }
            // 底部的主按钮
            .safeAreaInset(edge: .bottom) {
                Button {
                    if step == .result {
                        save()
                    } else {
                        go(to: step.rawValue + 1)
                    }
                } label: {
                    Text(step == .result ? "开始使用" : "下一步")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!canContinue)
                .padding()
                .background(.bar)
            }
        }
    }

    // MARK: - 每一步的内容

    @ViewBuilder
    private var currentStep: some View {
        switch step {
        case .welcome:
            WelcomeStep(hasAgreed: $hasAgreed)
        case .basicInfo:
            Form { BasicInfoSection(draft: draft) }
        case .activity:
            Form { ActivitySection(draft: draft) }
        case .goal:
            Form { GoalSection(draft: draft) }
        case .result:
            if let bodyInfo = draft.bodyInfo {
                ResultStep(bodyInfo: bodyInfo)
            }
        }
    }

    private var title: String {
        switch step {
        case .welcome: String(localized: "欢迎")
        case .basicInfo: String(localized: "基本信息")
        case .activity: String(localized: "活动量")
        case .goal: String(localized: "目标")
        case .result: String(localized: "你的每日目标")
        }
    }

    /// 当前这一步是否已经填好，可以继续
    private var canContinue: Bool {
        switch step {
        case .welcome: hasAgreed
        case .basicInfo: draft.isBasicInfoValid
        case .activity: draft.activity != nil
        case .goal: draft.goal != nil
        case .result: draft.bodyInfo != nil
        }
    }

    private func go(to rawValue: Int) {
        if let next = Step(rawValue: rawValue) {
            withAnimation { step = next }
        }
    }

    /// 保存资料。保存后 App 会自动切换到主界面（见 RootView）
    private func save() {
        guard let bodyInfo = draft.bodyInfo else { return }
        modelContext.insert(UserProfile(body: bodyInfo))
        try? modelContext.save()
    }
}

// MARK: - 第 1 步：欢迎和说明

private struct WelcomeStep: View {
    @Binding var hasAgreed: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Image(systemName: "fork.knife.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.tint)
                    .frame(maxWidth: .infinity)

                Text("先花 1 分钟填写基本资料，App 会算出适合你的每日热量和三大营养素目标。")
                    .font(.title3)

                VStack(alignment: .leading, spacing: 10) {
                    Label("资料只保存在你的手机上", systemImage: "lock.iphone")
                    Label("计算方法公开透明，随时可以查看", systemImage: "function")
                    Label("资料可以随时修改，目标会自动更新", systemImage: "arrow.triangle.2.circlepath")
                }
                .foregroundStyle(.secondary)

                // 免责说明：必须勾选才能继续
                VStack(alignment: .leading, spacing: 12) {
                    Text("请先了解")
                        .font(.headline)
                    Text("App 给出的热量和营养目标是根据公式估算的参考值，不是医疗建议。本 App 适用于 18 岁以上的成年人。如有疾病（尤其是肾病、糖尿病）、处于孕期或哺乳期，或有饮食失调史，请先咨询医生或注册营养师。")
                        .font(.callout)
                    Toggle("我已了解以上说明", isOn: $hasAgreed)
                        .fontWeight(.medium)
                }
                .padding()
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
            }
            .padding()
        }
    }
}

// MARK: - 最后一步：展示计算结果

private struct ResultStep: View {
    let bodyInfo: BodyInfo

    var body: some View {
        let targets = NutritionCalculator.targets(for: bodyInfo)
        List {
            Section {
                TargetsSummaryView(targets: targets)
                FloorNotice(targets: targets)
                GoalNotesView(bodyInfo: bodyInfo)
            } header: {
                Text("根据你的资料，建议每天摄入")
            } footer: {
                Text("这是估算的起点，之后可以在「我的」页面修改资料，目标会自动重新计算。")
            }

            Section {
                NavigationLink("这些数字是怎么算的？") {
                    ExplanationView(bodyInfo: bodyInfo)
                }
            }
        }
    }
}

#Preview {
    OnboardingView()
        .modelContainer(for: AppModels.all, inMemory: true)
}
