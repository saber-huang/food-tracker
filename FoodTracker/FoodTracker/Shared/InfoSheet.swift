//
//  InfoSheet.swift
//  FoodTracker
//
//  说明文字的放法：界面上不长期挂着灰色说明。需要解释的地方放一个 ⓘ，点开是一个半屏的说明，看完点「知道了」。
//  - InfoTopic：每一种说明的标题和正文（关于 AI 估算、健康提示、热量和份量、过敏和忌口）
//  - InfoSheet：半屏说明
//  - InfoButton：一个 ⓘ，点开对应的说明
//  - AIEstimateBadge：「AI 估算 ⓘ」小标签，只放在 AI 算出来的数字旁边（识别结果、食谱）
//  - AIFootnote：一行很小的「营养数据为估算值，仅供参考。ⓘ」，一个页面最多放一次，放在最下面
//  用户自己填的数字（手动添加）不是 AI 的数据，不放这些标签。
//

import SwiftUI

/// 一种说明的内容
enum InfoTopic: String, Identifiable {
    case aiEstimate  // 关于 AI 估算
    case health  // 健康提示（每日目标不是医疗建议）
    case caloriesAndPortion  // 热量和份量（千焦换算、按比例换算）
    case allergies  // 过敏和忌口怎么用（食谱偏好里的 ⓘ）

    var id: String { rawValue }

    var title: String {
        switch self {
        case .aiEstimate: String(localized: "关于 AI 估算")
        case .health: String(localized: "健康提示")
        case .caloriesAndPortion: String(localized: "热量和份量")
        case .allergies: String(localized: "过敏和忌口")
        }
    }

    /// 正文的几段话
    var paragraphs: [String] {
        switch self {
        case .aiEstimate:
            [
                String(localized: "营养数据和食谱由 AI 根据你提供的信息进行估算，可能与实际情况存在差异。拍照识别的结果可以在保存前修改。"),
                String(localized: "如涉及以下情况，建议咨询医生或注册营养师："),
            ]
        case .health:
            [
                String(localized: "热量和营养目标是根据公式估算的参考值，不是医疗建议。"),
                String(localized: "如有疾病（尤其是肾病、糖尿病）、处于孕期或哺乳期，或有饮食失调史，请先咨询医生或注册营养师。"),
            ]
        case .caloriesAndPortion:
            [
                String(localized: "包装上的「能量」一般是千焦（kJ），除以 4.2 大约就是千卡。"),
                String(localized: "先填份量、再填热量，之后改份量时，热量和三大营养素会按比例一起变；直接改某一项，就只改那一项。"),
            ]
        case .allergies:
            // 不承诺「绝对不会出现」：后端会检查并重做，但 AI 仍可能有疏漏
            [
                String(localized: "你填写的过敏食材和忌口会用于食谱推荐，推荐会尽量避开这些食材和用它们做的食品。"),
                String(localized: "多个食材用顿号或逗号分开。"),
                String(localized: "有严重过敏时，做菜前请再自己核对一遍食材。"),
            ]
        }
    }

    /// 正文后面要单独列出来的几项（没有就是空的）
    var bullets: [String] {
        switch self {
        case .aiEstimate:
            [String(localized: "疾病"), String(localized: "孕期"), String(localized: "过敏"), String(localized: "特殊饮食需求")]
        case .health, .caloriesAndPortion, .allergies:
            []
        }
    }
}

/// 半屏的说明：标题、几段话、（可能有的）几项列表，最下面一个「知道了」
struct InfoSheet: View {
    let topic: InfoTopic

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.lg) {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.md) {
                    Text(topic.title)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(AppColors.textPrimary)
                        .accessibilityAddTraits(.isHeader)
                    ForEach(topic.paragraphs, id: \.self) { paragraph in
                        Text(paragraph)
                            .font(.callout)
                            .foregroundStyle(AppColors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if !topic.bullets.isEmpty {
                        VStack(alignment: .leading, spacing: AppSpacing.xs) {
                            ForEach(topic.bullets, id: \.self) { bullet in
                                HStack(alignment: .firstTextBaseline, spacing: AppSpacing.xs) {
                                    Circle()
                                        .fill(AppColors.oatMark)
                                        .frame(width: 5, height: 5)
                                        .alignmentGuide(.firstTextBaseline) { $0[.bottom] + 4 }
                                    Text(bullet)
                                        .font(.callout)
                                        .foregroundStyle(AppColors.textPrimary)
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollBounceBehavior(.basedOnSize)

            Button("知道了") { dismiss() }
                .buttonStyle(.appPrimary)
        }
        .padding(.horizontal, AppSpacing.xl)
        .padding(.top, AppSpacing.xxl)
        .padding(.bottom, AppSpacing.md)
        .background(AppColors.surfacePrimary)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(AppColors.surfacePrimary)
    }
}

/// 一个 ⓘ：点开对应的说明。图标小，能点的范围有 44 × 44
struct InfoButton: View {
    let topic: InfoTopic

    @State private var isShowing = false

    var body: some View {
        Button {
            isShowing = true
        } label: {
            Image(systemName: "info.circle")
                .font(.footnote)
                .foregroundStyle(AppColors.textSecondary)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)  // 放在列表的一行里时，只有点到它才打开
        .accessibilityLabel(topic.title)
        .sheet(isPresented: $isShowing) {
            InfoSheet(topic: topic)
        }
    }
}

/// 「AI 估算 ⓘ」：放在 AI 算出来的数字旁边，点开「关于 AI 估算」
struct AIEstimateBadge: View {
    @State private var isShowing = false

    var body: some View {
        Button {
            isShowing = true
        } label: {
            HStack(spacing: 3) {
                Text("AI 估算")
                Image(systemName: "info.circle")
            }
            .font(AppTypography.caption)
            .foregroundStyle(AppColors.textSecondary)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("AI 估算")
        .accessibilityHint("查看关于 AI 估算的说明")
        .sheet(isPresented: $isShowing) {
            InfoSheet(topic: .aiEstimate)
        }
    }
}

/// 页面最下面的一行小字：「营养数据为估算值，仅供参考。ⓘ」，点开「关于 AI 估算」。一个页面最多放一次
struct AIFootnote: View {
    @State private var isShowing = false

    var body: some View {
        Button {
            isShowing = true
        } label: {
            HStack(spacing: 4) {
                Text("营养数据为估算值，仅供参考。")
                Image(systemName: "info.circle")
            }
            .font(.caption2)
            .foregroundStyle(AppColors.textTertiary)
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityHint("查看关于 AI 估算的说明")
        .sheet(isPresented: $isShowing) {
            InfoSheet(topic: .aiEstimate)
        }
    }
}

#Preview("关于 AI 估算") {
    Color.clear.sheet(isPresented: .constant(true)) { InfoSheet(topic: .aiEstimate) }
}
