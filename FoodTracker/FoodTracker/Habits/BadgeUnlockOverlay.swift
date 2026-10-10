//
//  BadgeUnlockOverlay.swift
//  FoodTracker
//
//  获得新徽章时，屏幕中间弹出的一张卡片（盖在整个主界面上，包括底部标签栏）：
//  背景暗下来一点；卡片上「获得新徽章」、一枚带飘带的大徽章（弹出来、轻轻转正，后面一圈光晕散开，旁边几颗小星星闪出来）、
//  徽章名称和做到了什么、一共获得了几个；按钮「好」（后面还排着徽章时是「下一个」）和「查看全部徽章」。
//  点卡片外面也能关掉。一次得到好几个时一个一个弹（排队见 HabitCenter.celebrations）。
//  打开「减少动态效果」时不弹、不转、没有光晕，只是淡入。出现时震一下，旁白念出获得了什么徽章。
//  说的话和徽章本身一样只关于记录：不夸「吃得好」，也不催下一个
//

import Accessibility
import SwiftUI

struct BadgeUnlockOverlay: View {
    let achievement: Achievement
    let unlockedCount: Int  // 一共获得了几个（包括这一个）
    let remainingCount: Int  // 后面还排着几个
    let onDone: () -> Void
    let onViewAll: () -> Void

    @State private var dimmed = false

    var body: some View {
        ZStack {
            // 暗下来的背景（暖色的阴影色，不用纯黑）：点一下关掉这一个。旁白用卡片上的按钮，或者两指来回划「Z」
            AppColors.shadow.opacity(dimmed ? 0.4 : 0)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture(perform: onDone)
                .accessibilityHidden(true)
            // 换了一个徽章就是一张新卡片：重新播放一次弹出来的动画（背景不跟着闪）
            BadgeUnlockCard(
                achievement: achievement, unlockedCount: unlockedCount, remainingCount: remainingCount, onDone: onDone,
                onViewAll: onViewAll
            )
            .id(achievement)
            .transition(.asymmetric(insertion: .identity, removal: .opacity))
            .padding(.horizontal, AppSpacing.xl)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.25)) { dimmed = true }
        }
    }
}

/// 卡片本身
private struct BadgeUnlockCard: View {
    let achievement: Achievement
    let unlockedCount: Int
    let remainingCount: Int
    let onDone: () -> Void
    let onViewAll: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false  // 卡片和徽章弹出来
    @State private var ringSpread = false  // 光晕散开
    @State private var sparkled = false  // 小星星闪出来

    @ScaledMetric(relativeTo: .title) private var medalSize: CGFloat = 112

    var body: some View {
        VStack(spacing: AppSpacing.md) {
            Label("获得新徽章", systemImage: "sparkles")
                .font(AppTypography.caption.weight(.semibold))
                .foregroundStyle(AppColors.brand)
            medal
                .padding(.top, AppSpacing.xs)
                .padding(.bottom, medalSize * 0.26)  // 给飘带留出位置
            VStack(spacing: AppSpacing.xs) {
                Text(achievement.title)
                    .font(.system(.title2, design: .rounded, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                Text(achievement.detail)
                    .font(.subheadline)
                    .foregroundStyle(AppColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Text("已获得 \(unlockedCount) 个徽章，共 \(Achievement.allCases.count) 个")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textSecondary)
                    .monospacedDigit()
                    .padding(.top, AppSpacing.xxs)
            }
            VStack(spacing: AppSpacing.xxs) {
                Button(remainingCount > 0 ? String(localized: "下一个") : String(localized: "好"), action: onDone)
                    .buttonStyle(.appPrimary)
                Button("查看全部徽章", action: onViewAll)
                    .buttonStyle(AppButtonStyle(kind: .tertiary, tint: AppColors.brand))
            }
            .padding(.top, AppSpacing.xs)
        }
        .padding(AppSpacing.xl)
        .frame(maxWidth: 360)
        .background(AppColors.surfacePrimary, in: RoundedRectangle(cornerRadius: AppRadius.extraLarge, style: .continuous))
        .appShadow(AppShadow.hero)
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)  // 字号再大，卡片就放不下了
        .scaleEffect(appeared || reduceMotion ? 1 : 0.9)
        .opacity(appeared ? 1 : 0)
        // 旁白：卡片是一个单独的层，焦点不会跑到后面的页面上；两指划「Z」等于点「好」
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape, onDone)
        .sensoryFeedback(.success, trigger: appeared) { _, isShown in isShown }
        .onAppear(perform: animateIn)
    }

    /// 大徽章：后面一团柔和的底光、一圈散开的光晕，旁边几颗小星星
    private var medal: some View {
        let palette = BadgePalette.of(achievement.tier)
        return ZStack {
            Circle()
                .fill(Color(palette.fill))
                .frame(width: medalSize * 1.45, height: medalSize * 1.45)
                .blur(radius: 18)
                .opacity(appeared ? 0.9 : 0)
            Circle()
                .stroke(Color(palette.ring), lineWidth: 2)
                .frame(width: medalSize, height: medalSize)
                .scaleEffect(ringSpread ? 1.8 : 0.95)
                .opacity(ringSpread || reduceMotion ? 0 : 0.7)
            sparkle(size: 18, x: -0.66, y: -0.36, delay: 0)
            sparkle(size: 12, x: 0.7, y: -0.2, delay: 0.08)
            sparkle(size: 15, x: 0.52, y: 0.46, delay: 0.16)
            BadgeMedal(achievement: achievement, isUnlocked: true, size: medalSize, showsRibbon: true)
                .scaleEffect(appeared || reduceMotion ? 1 : 0.55)
                .rotationEffect(.degrees(appeared || reduceMotion ? 0 : -10))
        }
        .frame(width: medalSize * 1.6, height: medalSize)
        .accessibilityHidden(true)
    }

    /// 一颗小星星（燕麦黄，像一点反光）。x、y 是相对徽章大小的位置
    private func sparkle(size: CGFloat, x: CGFloat, y: CGFloat, delay: Double) -> some View {
        Image(systemName: "sparkle")
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(AppColors.carbs)
            .scaleEffect(sparkled ? 1 : 0.2)
            .opacity(sparkled ? 1 : 0)
            .offset(x: medalSize * x, y: medalSize * y)
            .animation(reduceMotion ? .easeOut(duration: 0.25) : .spring(response: 0.42, dampingFraction: 0.5).delay(0.22 + delay), value: sparkled)
    }

    private func animateIn() {
        AccessibilityNotification.Announcement(String(localized: "获得新徽章：\(achievement.title)。\(achievement.detail)")).post()
        sparkled = true  // 小星星自己带着动画（见 sparkle）
        if reduceMotion {
            withAnimation(.easeOut(duration: 0.25)) { appeared = true }
            return
        }
        withAnimation(.spring(response: 0.5, dampingFraction: 0.62)) { appeared = true }
        withAnimation(.easeOut(duration: 1.1).delay(0.12)) { ringSpread = true }
    }
}

#Preview("新徽章") {
    @Previewable @State var queue: [Achievement] = [.firstMeal, .tenMeals, .fourSteadyWeeks]
    ZStack {
        AppBackground(glow: false)
        if let first = queue.first {
            BadgeUnlockOverlay(
                achievement: first, unlockedCount: 4 - queue.count, remainingCount: queue.count - 1,
                onDone: { queue.removeFirst() }, onViewAll: { queue.removeAll() })
        }
    }
    .animation(.easeOut(duration: 0.2), value: queue.first)
}
