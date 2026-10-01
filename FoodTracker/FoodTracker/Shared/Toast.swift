//
//  Toast.swift
//  FoodTracker
//
//  轻提示：屏幕下方出现一个小胶囊，1～1.5 秒后自己消失，不打断用户（不弹「保存成功」的大警告框）。
//  - 保存一餐后：「已记录到午餐」「已记录 3 项食物」，同时轻轻震一下
//  - 删除一条记录后：「已删除「米饭」  撤销」，停 5 秒，点「撤销」就恢复
//  用法：页面里写 @Environment(ToastCenter.self) private var toasts: ToastCenter?，然后 toasts?.show(...)。
//  ToastCenter 由主界面（MainTabView）创建、放进环境；胶囊也由主界面统一显示（见 toastHost()）
//

import Accessibility
import SwiftUI

@Observable
final class ToastCenter {
    struct Toast: Identifiable {
        enum Kind { case success, deletion }

        let id = UUID()
        let message: String
        let systemImage: String
        let kind: Kind
        let actionTitle: String?
        let action: (() -> Void)?
    }

    private(set) var current: Toast?
    @ObservationIgnored private var dismissTask: Task<Void, Never>?

    /// 完成了一件事：「已记录到午餐」。没有按钮，1.4 秒后消失
    func success(_ message: String) {
        show(Toast(message: message, systemImage: "checkmark.circle.fill", kind: .success, actionTitle: nil, action: nil), seconds: 1.4)
    }

    /// 删除了东西：「已删除「米饭」」+「撤销」。停 5 秒，给用户时间反悔
    func deleted(_ message: String, undo: @escaping () -> Void) {
        show(
            Toast(message: message, systemImage: "trash", kind: .deletion, actionTitle: String(localized: "撤销"), action: undo),
            seconds: 5)
    }

    /// 点了「撤销」：先关掉提示再恢复，不会恢复两次
    func performAction() {
        guard let action = current?.action else { return }
        dismiss()
        action()
    }

    func dismiss() {
        dismissTask?.cancel()
        withAnimation(.easeOut(duration: 0.18)) { current = nil }
    }

    private func show(_ toast: Toast, seconds: Double) {
        dismissTask?.cancel()
        withAnimation(.easeOut(duration: 0.18)) { current = toast }
        // 旁白念出来：看不见屏幕的用户也知道保存成功了 / 可以撤销
        AccessibilityNotification.Announcement(toast.message).post()
        let id = toast.id
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled, self?.current?.id == id else { return }
            self?.dismiss()
        }
    }
}

/// 小胶囊：图标 + 一句话，有「撤销」时右边多一个按钮
private struct ToastView: View {
    let toast: ToastCenter.Toast
    let onAction: () -> Void

    var body: some View {
        HStack(spacing: AppSpacing.sm) {
            Image(systemName: toast.systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppColors.toastAction)
                .accessibilityHidden(true)
            Text(toast.message)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(AppColors.toastText)
                .lineLimit(2)
            if let actionTitle = toast.actionTitle {
                Spacer(minLength: AppSpacing.xs)
                Button(actionTitle, action: onAction)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppColors.toastAction)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
                    .buttonStyle(.borderless)
            }
        }
        .padding(.leading, AppSpacing.md)
        .padding(.trailing, toast.actionTitle == nil ? AppSpacing.md : AppSpacing.xs)
        .frame(minHeight: 48)
        .background(AppColors.toastBackground, in: Capsule())
        .shadow(color: AppColors.shadow.opacity(0.12), radius: 12, y: 4)
        .padding(.horizontal, AppSpacing.pageMargin)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .accessibilityElement(children: .contain)
    }
}

extension View {
    /// 在这个视图底部显示轻提示（主界面用一次就够了）。出现时轻轻震一下：保存成功是「成功」，删除是轻轻一下
    func toastHost(_ center: ToastCenter) -> some View {
        overlay(alignment: .bottom) {
            if let toast = center.current {
                ToastView(toast: toast) { center.performAction() }
                    .padding(.bottom, AppSpacing.sm)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .id(toast.id)
            }
        }
        .sensoryFeedback(trigger: center.current?.id) { _, newID in
            guard newID != nil, let kind = center.current?.kind else { return nil }
            return kind == .success ? .success : .impact(weight: .light)
        }
    }
}

#Preview {
    @Previewable @State var center = ToastCenter()
    VStack(spacing: 16) {
        Button("已记录") { center.success("已记录到午餐") }
        Button("删除") { center.deleted("已删除「米饭」") {} }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(AppColors.background)
    .toastHost(center)
}
