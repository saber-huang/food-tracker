//
//  StateViews.swift
//  FoodTracker
//
//  全 App 统一的「状态」：加载、没有内容、出错都用 BrandedStateView，同一只碗、同样的字号、留白和按钮层级。
//  成功不做成一整页：用轻提示（见 Toast.swift）。
//  - 加载：冒着热气的碗（SteamBowl）+ 标题 + 一句正在做什么（等得久了自然换一句，不显示假的百分比和「通常要几秒」）
//  - 没有内容：完整的碗图案（笑脸 + 碗）+ 标题 + 一句说明；要不要放按钮由页面决定（旁边已经有入口的就不放）
//  - 出错：一只没有热气的碗 + 标题 + 一句能照着做的话 + 按钮（主要：重试 / 重新拍摄；次要：手动添加）。
//    技术细节（错误码、HTTP、JSON）不给用户看，只写进日志
//  - AppLoadingIndicator：按钮里、一行字旁边用的小号加载动画（也是冒热气的碗）
//

import SwiftUI

// MARK: - 统一的状态

struct BrandedStateView<Accessory: View, Actions: View>: View {
    enum Kind {
        case loading, empty, error
    }

    let kind: Kind
    let title: String
    var message: String?
    /// 加载完成：热气停下、碗轻轻放大一点（之后页面再切走）
    var isFinishing = false
    /// 碗的大小：整页的状态用默认的，放在卡片里的小一点
    var visualWidth: CGFloat = 96
    /// 标题下面的附加内容（照片缩略图、几条建议）
    @ViewBuilder var accessory: Accessory
    /// 按钮：从上到下是主要、次要、第三级（用 AppButtonStyle）
    @ViewBuilder var actions: Actions

    @ScaledMetric(relativeTo: .largeTitle) private var scale: CGFloat = 1

    var body: some View {
        VStack(spacing: AppSpacing.lg) {
            visual
                .frame(width: visualWidth * min(scale, 1.4))
            VStack(spacing: AppSpacing.xs) {
                Text(title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(AppColors.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                if let message {
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(AppColors.textSecondary)
                        .id(message)  // 换一句时淡入淡出
                        .transition(.opacity)
                }
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            accessory
            VStack(spacing: AppSpacing.xs) {
                actions
            }
        }
        .frame(maxWidth: .infinity)
        .animation(.easeOut(duration: 0.25), value: message)
    }

    @ViewBuilder
    private var visual: some View {
        switch kind {
        case .loading: SteamBowl(isFinishing: isFinishing)
        case .empty: KindbiteMark()
        case .error: SteamBowl(showsSteam: false).opacity(0.85)
        }
    }
}

extension BrandedStateView where Accessory == EmptyView {
    init(
        kind: Kind, title: String, message: String? = nil, isFinishing: Bool = false, visualWidth: CGFloat = 96,
        @ViewBuilder actions: () -> Actions
    ) {
        self.init(
            kind: kind, title: title, message: message, isFinishing: isFinishing, visualWidth: visualWidth,
            accessory: { EmptyView() }, actions: actions)
    }
}

extension BrandedStateView where Accessory == EmptyView, Actions == EmptyView {
    init(kind: Kind, title: String, message: String? = nil, visualWidth: CGFloat = 96) {
        self.init(
            kind: kind, title: title, message: message, visualWidth: visualWidth, accessory: { EmptyView() },
            actions: { EmptyView() })
    }
}

/// 加载中的几句话：按时间往下走（到最后一句就停住）。真正的进度不知道，所以只换说法，不显示百分比
struct LoadingMessages: Equatable {
    let lines: [String]
    /// 第几秒换到这一句（和 lines 一一对应，第一句是 0）
    let switchAt: [Double]

    /// 等了 elapsed 秒时显示哪一句
    func line(after elapsed: Double) -> String {
        var current = lines.first ?? ""
        for (index, start) in switchAt.enumerated() where elapsed >= start && lines.indices.contains(index) {
            current = lines[index]
        }
        return current
    }
}

// MARK: - 小号的加载动画

/// 按钮里、一行字旁边的加载动画：一只冒热气的小碗。放在橄榄绿按钮上时用 onBrand: true（暖白色）
struct AppLoadingIndicator: View {
    var onBrand = false
    @ScaledMetric(relativeTo: .body) private var size: CGFloat = 22

    var body: some View {
        SteamBowl(palette: onBrand ? .onBrand : .oat)
            .frame(width: size)
    }
}

#Preview("加载、没有内容、出错") {
    ScrollView {
        VStack(spacing: 48) {
            BrandedStateView(kind: .loading, title: "正在分析这顿饭", message: "正在识别食物和估算份量…")
            BrandedStateView(kind: .empty, title: "今天还没有记录", message: "拍一张照片，或手动添加第一餐。", visualWidth: 72)
            BrandedStateView(kind: .error, title: "没有完成识别", message: "手机没有联网。检查网络后再试一次。") {
                Button("重试") {}.buttonStyle(.appPrimary)
                Button("手动添加") {}.buttonStyle(.appSecondary)
            }
            HStack {
                AppLoadingIndicator()
                Text("正在换…")
            }
        }
        .padding()
    }
    .background(AppColors.background)
}
