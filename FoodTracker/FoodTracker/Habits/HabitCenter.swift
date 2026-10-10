//
//  HabitCenter.swift
//  FoodTracker
//
//  「记录习惯」的数据中心：最新的统计、获得过的徽章，以及等着弹出的新徽章（celebrations）。
//  主界面（MainTabView）创建一个、放进环境里，「我的」页的记录习惯卡片和徽章页都读它；
//  主界面看 celebrations 有没有徽章，有就在屏幕中间弹出徽章卡片（BadgeUnlockOverlay），一次得到好几个时一个一个弹。
//  什么时候重新统计：进主界面时、有新记录时（最新的一条变了）、回到 App 时、打开「我的」时。
//

import Foundation
import SwiftData

@Observable
final class HabitCenter {
    private(set) var stats = HabitStats.empty
    private(set) var ledger: AchievementLedger
    /// 等着弹出的新徽章：第一个正在显示，后面的排着队
    private(set) var celebrations: [Achievement] = []
    /// 点了徽章卡片上的「查看全部徽章」、或者记录习惯卡片：切到「我的」并打开徽章页
    var showsAchievements = false

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let celebrationDelay: Duration

    /// 新徽章等多久再弹出：先让记录的页面关上、「已记录到午餐」显示完（它停 1.4 秒）
    static let defaultCelebrationDelay: Duration = .seconds(1.5)

    init(defaults: UserDefaults = .standard, celebrationDelay: Duration = HabitCenter.defaultCelebrationDelay) {
        self.defaults = defaults
        self.celebrationDelay = celebrationDelay
        ledger = AchievementStore.load(from: defaults)
    }

    /// 重新统计，有新徽章就（稍等一下）弹出来。返回这次新获得的徽章（测试用）
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

    /// 稍等一下再把新徽章排进队里（主界面看到队里有徽章就弹出来）
    private func announce(_ new: [Achievement]) {
        guard !new.isEmpty else { return }
        Task { [weak self, celebrationDelay] in
            try? await Task.sleep(for: celebrationDelay)
            self?.enqueue(new)
        }
    }

    /// 排进队里：已经在队里的不再排一次（同一个徽章不会弹两次）
    func enqueue(_ new: [Achievement]) {
        for achievement in new where !celebrations.contains(achievement) {
            celebrations.append(achievement)
        }
    }

    /// 徽章卡片上点了「好」（或点了卡片外面）：关掉这一个，下一个接着弹
    func finishCelebration() {
        guard !celebrations.isEmpty else { return }
        celebrations.removeFirst()
    }

    /// 点了「查看全部徽章」：剩下的不再一个一个弹（徽章页里都看得到），切到「我的」打开徽章页
    func viewAllAchievements() {
        celebrations.removeAll()
        showsAchievements = true
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
    /// 模拟器里的开发者工具：清空徽章（下次统计时像第一次获得一样弹出来）
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
