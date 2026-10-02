//
//  AIEstimateView.swift
//  FoodTracker
//
//  AI 估算一种搜不到的食物（「山西过油肉」）：只把名字发给后端，AI 估算每 100 克的营养和一个常见份量。
//  第一次用 AI 前先弹出说明征得同意（和拍照识别一样）。
//  - 估算中：冒热气的碗 +「正在估算「山西过油肉」」，可以返回
//  - 估好了：直接变成份量页（标「AI 估算 ⓘ」、数字取整加「约」），可以顺手保存到「我的食物」
//  - 出错 / 不是食物：说清楚，给「重试」或「创建自定义食物」，不会走进死路
//

import SwiftUI

struct AIEstimateView: View {
    let query: String
    let meal: MealType
    let dayKey: Int
    let onAdd: (EditableItem) -> Void
    /// 「修改营养数据」：打开我的食物编辑页
    let onEditEstimate: (CustomFoodSeed) -> Void
    /// 「创建自定义食物」
    let onCreateCustom: (String) -> Void

    private enum Phase: Equatable {
        case waitingConsent  // 还没同意使用 AI（说明弹出来后点了「暂不使用」）
        case loading
        case failed(String)
        case notFood(String)
        case done(FoodChoice)
    }

    @Environment(\.dismiss) private var dismiss
    @State private var phase: Phase = .loading
    @State private var pendingAIAction: PendingAIAction?
    @State private var task: Task<Void, Never>?

    var body: some View {
        Group {
            if case .done(let choice) = phase {
                FoodServingView(choice: choice, meal: meal, dayKey: dayKey, onEditEstimate: onEditEstimate, onAdd: onAdd)
            } else {
                stateContent
                    .toolbar(.visible, for: .navigationBar)
                    .navigationTitle(String(localized: "AI 估算"))
                    .navigationBarTitleDisplayMode(.inline)
            }
        }
        // 说明弹出来后点了「暂不使用」：停在「需要先同意」，什么都不发送
        .aiConsentSheet(pending: $pendingAIAction)
        .task { start() }
        .onDisappear { task?.cancel() }
    }

    private var stateContent: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    Color.clear.frame(height: max(AppSpacing.lg, proxy.size.height * 0.16))
                    state
                        .padding(.horizontal, AppSpacing.pageMargin)
                    Color.clear.frame(height: AppSpacing.xxl)
                }
                .frame(maxWidth: .infinity, minHeight: proxy.size.height, alignment: .top)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .background { AppBackground(glow: false) }
    }

    @ViewBuilder
    private var state: some View {
        switch phase {
        case .loading, .done:
            BrandedStateView(
                kind: .loading, title: String(localized: "正在估算「\(query)」"),
                message: String(localized: "按常见做法估算份量和营养…")
            ) {
                Button("返回", action: { dismiss() })
                    .buttonStyle(.appTertiary)
            }
        case .waitingConsent:
            BrandedStateView(
                kind: .empty, title: String(localized: "需要先同意使用 AI"),
                message: String(localized: "AI 估算会把你输入的食物名称发给 AI。也可以不用 AI，自己创建这个食物。"), visualWidth: 72
            ) {
                Button("查看说明", action: start)
                    .buttonStyle(.appPrimary)
                Button("创建自定义食物") { onCreateCustom(query) }
                    .buttonStyle(.appSecondary)
            }
        case .failed(let message):
            BrandedStateView(kind: .error, title: String(localized: "没有完成估算"), message: message, visualWidth: 72) {
                Button("重试", action: start)
                    .buttonStyle(.appPrimary)
                Button("创建自定义食物") { onCreateCustom(query) }
                    .buttonStyle(.appSecondary)
            }
        case .notFood(let message):
            BrandedStateView(
                kind: .error, title: String(localized: "没能估算这个名字"),
                message: message.isEmpty ? String(localized: "换个更具体的叫法试试，或者自己创建这个食物。") : message,
                visualWidth: 72
            ) {
                Button("创建自定义食物") { onCreateCustom(query) }
                    .buttonStyle(.appPrimary)
                Button("换个说法", action: { dismiss() })
                    .buttonStyle(.appTertiary)
            }
        }
    }

    // MARK: - 估算

    private func start() {
        phase = .waitingConsent
        AIConsent.perform(pending: $pendingAIAction) { run() }
    }

    private func run() {
        task?.cancel()
        phase = .loading
        task = Task {
            do {
                let response = try await APIClient.estimate(name: query)
                guard !Task.isCancelled else { return }
                if response.isFood {
                    phase = .done(.aiEstimate(FoodEstimate(response, query: query)))
                    ProductLog.log(.aiFoodEstimateUsed, name: query)
                } else {
                    phase = .notFood(response.message)
                }
            } catch {
                guard !Task.isCancelled else { return }
                phase = .failed(
                    (error as? LocalizedError)?.errorDescription ?? String(localized: "这次没有完成，请再试一次。"))
            }
        }
    }
}
