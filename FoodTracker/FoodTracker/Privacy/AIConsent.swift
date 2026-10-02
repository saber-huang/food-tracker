//
//  AIConsent.swift
//  FoodTracker
//
//  用 AI 之前先征得同意。拍照识别、生成食谱、推荐下一餐会把照片或饮食目标发给 Anthropic 公司的 Claude；
//  苹果审核指南 5.1.2(i) 要求：把个人数据发给第三方（包括第三方 AI）之前，先说清楚发什么、发给谁，并取得明确同意。
//
//  用法（需要 AI 的按钮都这样写）：
//      @State private var pendingAIAction: PendingAIAction?
//      Button { AIConsent.perform(pending: $pendingAIAction) { Task { await analyze() } } } ...
//      .aiConsentSheet(pending: $pendingAIAction)
//  已经同意过：马上做。没同意过：先弹出说明，点「同意并继续」才做；点「暂不使用」或往下滑关掉，就什么都不发。
//

import SwiftUI

nonisolated enum AIConsent {
    /// 存在 UserDefaults 里的名字：记的是「同意过第几版说明」，没有 = 没同意过或撤回了
    static let key = "aiConsentVersion"
    /// 说明的内容有重要变化（比如多发了一种数据）时加 1：以前同意过的人会被重新询问一次。
    /// 第 2 版（2026-10-02）：多了「AI 估算食物」，会发送用户输入的食物名称
    static let currentVersion = 2

    /// 按存下来的版本号判断（「我的」页用 @AppStorage 读到的数字直接传进来）
    static func isGranted(version: Int) -> Bool {
        version >= currentVersion
    }

    /// 以前同意过旧版说明、现在要再问一次：说明页顶部写清楚改了什么
    static func isUpdate(version: Int) -> Bool {
        version > 0 && version < currentVersion
    }

    static func isGranted(in defaults: UserDefaults = .standard) -> Bool {
        isGranted(version: defaults.integer(forKey: key))
    }

    static func grant(in defaults: UserDefaults = .standard) {
        defaults.set(currentVersion, forKey: key)
    }

    static func revoke(in defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key)
    }
}

/// 等用户同意之后要做的事：弹出说明时先记在这里
struct PendingAIAction: Identifiable {
    let id = UUID()
    let run: () -> Void
}

extension AIConsent {
    /// 已经同意过就马上做；没同意过就先记下来，由 aiConsentSheet 弹出说明
    static func perform(
        pending: Binding<PendingAIAction?>, defaults: UserDefaults = .standard, _ action: @escaping () -> Void
    ) {
        if isGranted(in: defaults) {
            action()
        } else {
            pending.wrappedValue = PendingAIAction(run: action)
        }
    }
}

extension View {
    /// 配合 AIConsent.perform 使用：有等着同意的操作时，弹出「使用 AI 功能前」的说明
    func aiConsentSheet(pending: Binding<PendingAIAction?>) -> some View {
        sheet(item: pending) { action in
            AIConsentSheet { agreed in
                pending.wrappedValue = nil  // 关掉说明
                if agreed {
                    AIConsent.grant()
                    action.run()
                }
            }
        }
    }
}
