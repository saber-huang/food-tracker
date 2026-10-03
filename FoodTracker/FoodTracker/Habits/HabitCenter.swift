//
//  HabitCenter.swift
//  FoodTracker
//
//  「记录习惯」的数据中心：最新的统计、获得过的徽章，以及新徽章的轻提示。
//  主界面（MainTabView）创建一个、放进环境里，「我的」页的记录习惯卡片和徽章页都读它。
//  什么时候重新统计：进主界面时、有新记录时（最新的一条变了）、回到 App 时、打开「我的」时。
//

import Foundation
import SwiftData

@Observable
final class HabitCenter {
    private(set) var stats = HabitStats.empty
    private(set) var ledger: AchievementLedger
    /// 点了新徽章提示里的「查看」：切到「我的」并打开徽章页
    var showsAchievements = false

    /// 新徽章的轻提示显示在哪（主界面的 ToastCenter）
    @ObservationIgnored weak var toasts: ToastCenter?
    @ObservationIgnored private let defaults: UserDefaults

    /// 新徽章的提示等多久再出现：先让「已记录到午餐」显示完（它停 1.4 秒）
    static let milestoneDelay: Duration = .seconds(1.6)

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        ledger = AchievementStore.load(from: defaults)
    }

    /// 重新统计，有新徽章就轻轻提示一下。返回这次新获得的徽章（测试用）
    @discardableResult
    func refresh(context: ModelContext, now: Date = HintClock.now) -> [Achievement] {
        stats = HabitStats.make(entries: Self.fetchEntries(context), today: now)
        let earned = Achievement.earned(by: stats, adjustedAI: AchievementStore.hasAdjustedAI(in: defaults))
        var updated = ledger
        let new = updated.update(earned: earned, now: now)
        if updated != ledger {
            // 先存下来再提示：之后再统计时这些徽章已经「获得过」，不会再提示一次
            ledger = updated
            AchievementStore.save(updated, to: defaults)
        }
        announce(new)
        return new
    }

    /// 新徽章的轻提示：「新徽章：第一餐」+「查看」；一次得到好几个时合成一条
    private func announce(_ new: [Achievement]) {
        guard let first = new.first, let toasts else { return }
        let message =
            new.count == 1
            ? String(localized: "新徽章：\(first.title)")
            : String(localized: "获得了 \(new.count) 个新徽章")
        Task { [weak self] in
            try? await Task.sleep(for: Self.milestoneDelay)
            toasts.milestone(message) { self?.showsAchievements = true }
        }
    }

    /// 读出所有记录里统计要用的几样（只读这几列，记录很多时也很快）
    private static func fetchEntries(_ context: ModelContext) -> [HabitEntry] {
        var descriptor = FetchDescriptor<FoodEntry>()
        descriptor.propertiesToFetch = [\.dayKey, \.mealRaw, \.name, \.sourceRaw]
        let entries = (try? context.fetch(descriptor)) ?? []
        return entries.map {
            HabitEntry(dayKey: $0.dayKey, meal: $0.mealRaw, name: $0.name, isPhoto: $0.sourceRaw == EntrySource.photo.rawValue)
        }
    }

    #if DEBUG && targetEnvironment(simulator)
    /// 模拟器里的开发者工具：清空徽章（下次统计时像第一次获得一样提示）
    func debugReset(context: ModelContext) {
        defaults.removeObject(forKey: AchievementStore.adjustedAIKey)
        ledger = .debugCleared
        AchievementStore.save(ledger, to: defaults)
        refresh(context: context)
    }
    #endif
}

extension FoodEntry {
    /// 最新的一条记录：主界面看它变没变，决定要不要重新统计记录习惯
    static var latestDescriptor: FetchDescriptor<FoodEntry> {
        var descriptor = FetchDescriptor<FoodEntry>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        descriptor.fetchLimit = 1
        return descriptor
    }
}
