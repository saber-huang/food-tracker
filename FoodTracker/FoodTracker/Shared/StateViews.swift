//
//  StateViews.swift
//  FoodTracker
//
//  全 App 统一的几种「状态」，各个页面不再各自做转圈、各自写出错弹窗：
//  - AppLoadingIndicator：小的加载动画（按钮里、一行字旁边），就是一只慢慢装满又落下的碗
//  - LoadingStateView：大的加载状态（识别照片、生成食谱）：碗 + 标题 + 轮流出现的阶段说明。
//    阶段说明只表示「现在大概在做什么」，按时间往下走、停在最后一句，不显示假的百分比
//  - EmptyStateView：没有内容时（今天还没有记录、还没有食谱、没认出食物）：小碗或图标 + 标题 + 一句说明，
//    要不要放按钮由页面决定（旁边已经有入口的就不放）
//  - ErrorStateView：出错时：图标 + 标题 + 一句能照着做的话 +「重试」。技术细节（错误码、HTTP 状态）只写进日志
//  品牌的碗只出现在这些状态里（空、加载），平时不到处放
//

import SwiftUI

// MARK: - 加载

/// 小的加载动画：一只小碗。放在橄榄绿的按钮上时用 onBrand: true（暖白色的碗）
struct AppLoadingIndicator: View {
    var onBrand = false
    @ScaledMetric(relativeTo: .body) private var size: CGFloat = 20

    var body: some View {
        Group {
            if onBrand {
                BowlLoadingMark(
                    emptyColor: AppColors.onBrand.opacity(0.28), fillColor: AppColors.onBrand,
                    rimColor: AppColors.onBrand.opacity(0.85))
            } else {
                BowlLoadingMark()
            }
        }
        .frame(width: size)
    }
}

/// 大的加载状态：碗的动画、标题、阶段说明（每隔几秒换下一句，到最后一句就停住）、一行小字
struct LoadingStateView: View {
    let title: String
    var stages: [String] = []
    var footnote: String?

    @State private var stageIndex = 0
    @ScaledMetric(relativeTo: .largeTitle) private var bowlWidth: CGFloat = 76

    var body: some View {
        VStack(spacing: AppSpacing.md) {
            BowlLoadingMark()
                .frame(width: bowlWidth)
                .padding(.bottom, AppSpacing.xxs)
            VStack(spacing: 6) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(AppColors.textPrimary)
                if stages.indices.contains(stageIndex) {
                    Text(stages[stageIndex])
                        .font(.subheadline)
                        .foregroundStyle(AppColors.textSecondary)
                        .id(stageIndex)  // 换一句时淡入淡出
                        .transition(.opacity)
                }
                if let footnote {
                    Text(footnote)
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textTertiary)
                        .padding(.top, AppSpacing.xxs)
                }
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppSpacing.lg)
        // 阶段说明按时间往下走：每句停 2.8 秒，到最后一句就停住（真正的进度不知道，所以不假装）
        .task(id: stages) {
            stageIndex = 0
            while stageIndex < stages.count - 1 {
                try? await Task.sleep(for: .seconds(2.8))
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.2)) { stageIndex += 1 }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
    }
}

// MARK: - 没有内容

/// 没有内容时：小碗（或一个系统图标）、标题、一句说明；actions 里放按钮（可以没有）
struct EmptyStateView<Actions: View>: View {
    enum Icon {
        case bowl  // 品牌的碗
        case symbol(String)  // 系统图标，放在燕麦色的圆里
    }

    let icon: Icon
    let title: String
    var message: String?
    @ViewBuilder var actions: Actions

    @ScaledMetric(relativeTo: .largeTitle) private var iconSize: CGFloat = 52

    var body: some View {
        VStack(spacing: AppSpacing.md) {
            iconView
            VStack(spacing: 6) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(AppColors.textPrimary)
                if let message {
                    Text(message)
                        .font(AppTypography.detail)
                        .foregroundStyle(AppColors.textSecondary)
                }
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .combine)
            actions
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppSpacing.md)
    }

    @ViewBuilder
    private var iconView: some View {
        switch icon {
        case .bowl:
            // 完整的碗图案（燕麦色，和 App 图标一样）；空碗的颜色太接近页面底色，看不清
            KindbiteMark()
                .frame(width: iconSize)
        case .symbol(let name):
            AppIconTile(systemImage: name, size: iconSize)
        }
    }
}

extension EmptyStateView where Actions == EmptyView {
    init(icon: Icon, title: String, message: String? = nil) {
        self.init(icon: icon, title: title, message: message) { EmptyView() }
    }
}

// MARK: - 出错

/// 出错时的一张小卡片：图标 + 标题，下面一句能照着做的话，再下面是「重试」和一个备选的做法（比如「手动添加」）。
/// 不弹大的警告框：页面还能照常用，用户可以先做别的
struct ErrorStateView: View {
    let title: String
    let message: String
    var retryTitle = String(localized: "重试")
    var onRetry: (() -> Void)?
    var secondaryTitle: String?
    var onSecondary: (() -> Void)?
    var onDismiss: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            HStack(alignment: .firstTextBaseline, spacing: AppSpacing.xs) {
                Image(systemName: "exclamationmark.circle")
                    .foregroundStyle(AppColors.confidenceLow)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppColors.textPrimary)
                Spacer(minLength: AppSpacing.xs)
                if let onDismiss {
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppColors.textTertiary)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                    .padding(-AppSpacing.sm)
                    .accessibilityLabel("关闭")
                }
            }
            Text(message)
                .font(AppTypography.detail)
                .foregroundStyle(AppColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if onRetry != nil || onSecondary != nil {
                HStack(spacing: AppSpacing.md) {
                    if let onRetry {
                        Button(action: onRetry) {
                            Label(retryTitle, systemImage: "arrow.clockwise")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(AppColors.onBrand)
                                .padding(.horizontal, AppSpacing.md)
                                .frame(minHeight: 40)
                                .background(AppColors.brand, in: Capsule())
                                .frame(minHeight: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(AppPressStyle())
                    }
                    if let secondaryTitle, let onSecondary {
                        Button(secondaryTitle, action: onSecondary)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(AppColors.brand)
                            .frame(minHeight: 44)
                            .buttonStyle(.borderless)
                    }
                }
            }
        }
        .padding(AppSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.surfacePrimary, in: RoundedRectangle(cornerRadius: AppRadius.compact, style: .continuous))
        .accessibilityElement(children: .contain)
    }
}

#Preview("加载、空、出错") {
    ScrollView {
        VStack(spacing: 24) {
            LoadingStateView(
                title: "正在分析 3 张照片", stages: ["正在识别食物…", "正在合并不同角度…", "正在估算份量和营养…"],
                footnote: "通常需要 10～20 秒")
            EmptyStateView(icon: .bowl, title: "今天还没有记录", message: "拍一张照片，或手动添加第一餐。")
            ErrorStateView(
                title: "无法完成识别", message: "没有联网。检查网络后再试一次。", onRetry: {}, secondaryTitle: "手动添加",
                onSecondary: {}, onDismiss: {})
            HStack {
                AppLoadingIndicator()
                Text("正在换…")
            }
        }
        .padding()
    }
    .background(AppColors.background)
}
