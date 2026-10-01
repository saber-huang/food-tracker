//
//  FloatingTabBar.swift
//  FoodTracker
//
//  底部悬浮的标签栏：一个完整的圆角条，左右和底部都留出空隙，像浮在页面上。
//  三个标签：今日、食谱、我的。没选中是暖灰色；选中的是深橄榄绿，背后一块很浅的橄榄色圆角底（比格子窄一点）。
//  图标都用同一种描边样式（不在选中时换成实心的）。系统自带的标签栏藏起来，由这个代替（见 RootView）。
//

import SwiftUI

/// 主界面的三个标签
enum AppTab: String, Hashable, CaseIterable, Identifiable {
    case today, recipes, profile

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .today: "今日"
        case .recipes: "食谱"
        case .profile: "我的"
        }
    }

    var systemImage: String {
        switch self {
        case .today: "fork.knife"
        case .recipes: "book"
        case .profile: "person.crop.circle"
        }
    }
}

struct FloatingTabBar: View {
    @Binding var selection: AppTab

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: AppSpacing.xxs) {
            ForEach(AppTab.allCases) { tab in
                let isSelected = tab == selection
                Button {
                    selection = tab
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: tab.systemImage)
                            .font(.system(size: 19, weight: .medium))
                            .frame(height: 22)
                        Text(tab.title)
                            .font(AppTypography.tabLabel)
                    }
                    .foregroundStyle(isSelected ? AppColors.brandDeep : AppColors.tabInactive)
                    .frame(maxWidth: .infinity, minHeight: 54)
                    .background {
                        if isSelected {
                            // 比格子窄四分之一左右、颜色很淡：选中很明确，但不像一个大按钮
                            Capsule()
                                .fill(AppColors.brandSoft.opacity(0.7))
                                .padding(.horizontal, AppSpacing.md)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(AppPressStyle())
                .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            }
        }
        .padding(AppSpacing.xs)
        .background {
            RoundedRectangle(cornerRadius: AppRadius.extraLarge, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    // 一层暖白，盖住大部分模糊：只有一点点透出下面的内容，不是明显的毛玻璃
                    RoundedRectangle(cornerRadius: AppRadius.extraLarge, style: .continuous)
                        .fill(AppColors.surfacePrimary.opacity(0.92))
                }
                .appShadow(AppShadow.floating)
        }
        .padding(.horizontal, AppSpacing.md + 2)
        .padding(.top, AppSpacing.xxs)
        .padding(.bottom, AppSpacing.xs)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: selection)
        .sensoryFeedback(.selection, trigger: selection)
        // 字号最多放大到「特特大」：标签栏高度固定，字再大就放不下（和系统的标签栏一样；长按可以看放大的文字）
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .accessibilityShowsLargeContentViewer()
    }
}

#Preview {
    @Previewable @State var selection = AppTab.today
    ZStack(alignment: .bottom) {
        AppBackground()
        FloatingTabBar(selection: $selection)
    }
}

// MARK: - 二级页面藏起标签栏

/// 底部标签栏现在要不要藏起来。一级页面（今日、食谱、我的）显示；二级页面（食谱详情、识别结果、设置的下一页……）
/// 出现时藏起来、离开时再显示（见 hidesFloatingTabBar）。用计数而不是开关：
/// 二级页面上再进一层时，先出现的那页离开、后出现的那页还在，标签栏仍然藏着
@Observable
final class TabBarVisibility {
    private(set) var hiddenCount = 0

    var isHidden: Bool { hiddenCount > 0 }

    func hide() { hiddenCount += 1 }
    func show() { hiddenCount = max(0, hiddenCount - 1) }
}

extension View {
    /// 二级页面加上这一句：出现时藏起底部标签栏，离开时再显示。
    /// 不在主界面里（比如引导页里打开的「怎么算的」、Xcode 预览）时什么都不做
    func hidesFloatingTabBar() -> some View {
        modifier(HidesFloatingTabBar())
    }
}

private struct HidesFloatingTabBar: ViewModifier {
    @Environment(TabBarVisibility.self) private var visibility: TabBarVisibility?

    func body(content: Content) -> some View {
        content
            .onAppear { visibility?.hide() }
            .onDisappear { visibility?.show() }
    }
}
