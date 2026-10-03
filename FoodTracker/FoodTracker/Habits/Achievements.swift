//
//  Achievements.swift
//  FoodTracker
//
//  8 个徽章：都只和「记录」有关（记了第一餐、一周记了 5 天、改过 AI 的识别结果……），
//  和吃多吃少无关：没有「吃得少」「没超过目标」这类徽章，比目标多的日子照样算记录。
//  获得了就一直在：删掉记录也不会收回。
//  第一次统计时（新装好、或者老用户刚更新到这个版本）只悄悄记下已经达到的，不连着弹一串提示；
//  之后每个徽章只提示一次（见 AchievementLedger）。
//  只做数据和规则，不涉及界面，可以单独写单元测试（FoodTrackerTests/HabitTests.swift）
//

import Foundation

nonisolated enum Achievement: String, CaseIterable, Codable {
    // 顺序就是徽章页里的顺序：从最容易得到的开始
    case firstMeal, firstPhoto, tenMeals, tenFoods, fiveDaysInWeek, adjustedAI, thirtyMeals, fourSteadyWeeks

    var title: String {
        switch self {
        case .firstMeal: String(localized: "第一餐")
        case .firstPhoto: String(localized: "拍一拍")
        case .tenMeals: String(localized: "十餐")
        case .tenFoods: String(localized: "十种食物")
        case .fiveDaysInWeek: String(localized: "一周五天")
        case .adjustedAI: String(localized: "亲自校对")
        case .thirtyMeals: String(localized: "三十餐")
        case .fourSteadyWeeks: String(localized: "稳定的一个月")
        }
    }

    /// 获得以后显示：做到了什么
    var detail: String {
        switch self {
        case .firstMeal: String(localized: "记下了第一餐。")
        case .firstPhoto: String(localized: "第一次用拍照记录了一餐。")
        case .tenMeals: String(localized: "一共记录了 10 餐。")
        case .tenFoods: String(localized: "记录过 10 种不同的食物。")
        case .fiveDaysInWeek: String(localized: "同一周里有 5 天做了记录。")
        case .adjustedAI: String(localized: "保存前修改过 AI 的识别结果。你最清楚自己吃了什么。")
        case .thirtyMeals: String(localized: "一共记录了 30 餐。")
        case .fourSteadyWeeks: String(localized: "连续 4 周，每周都有 4 天以上的记录。")
        }
    }

    /// 还没获得时显示：怎么得到
    var requirement: String {
        switch self {
        case .firstMeal: String(localized: "记录一餐")
        case .firstPhoto: String(localized: "用拍照记录一餐")
        case .tenMeals: String(localized: "累计记录 10 餐")
        case .tenFoods: String(localized: "记录 10 种不同的食物")
        case .fiveDaysInWeek: String(localized: "同一周里有 5 天做记录")
        case .adjustedAI: String(localized: "拍照识别后，保存前修改一次结果")
        case .thirtyMeals: String(localized: "累计记录 30 餐")
        case .fourSteadyWeeks: String(localized: "连续 4 周，每周记录 4 天以上")
        }
    }

    /// SF Symbols 的描边图标
    var systemImage: String {
        switch self {
        case .firstMeal: "fork.knife"
        case .firstPhoto: "camera"
        case .tenMeals: "list.bullet.clipboard"
        case .tenFoods: "leaf"
        case .fiveDaysInWeek: "calendar"
        case .adjustedAI: "slider.horizontal.3"
        case .thirtyMeals: "square.stack.3d.up"
        case .fourSteadyWeeks: "calendar.badge.checkmark"
        }
    }

    /// 达到了没有。只看记录本身（统计里本来就没有热量）
    func isEarned(by stats: HabitStats, adjustedAI: Bool) -> Bool {
        switch self {
        case .firstMeal: stats.mealCount >= 1
        case .firstPhoto: stats.usedPhoto
        case .tenMeals: stats.mealCount >= 10
        case .tenFoods: stats.distinctFoods >= 10
        case .fiveDaysInWeek: stats.bestWeekDays >= 5
        case .adjustedAI: adjustedAI
        case .thirtyMeals: stats.mealCount >= 30
        case .fourSteadyWeeks: stats.longestSteadyWeeks >= 4
        }
    }

    /// 现在达到了哪些
    static func earned(by stats: HabitStats, adjustedAI: Bool) -> Set<Achievement> {
        Set(allCases.filter { $0.isEarned(by: stats, adjustedAI: adjustedAI) })
    }
}

/// 获得过哪些徽章、什么时候获得的。存在手机本地（见 AchievementStore）
nonisolated struct AchievementLedger: Codable, Equatable {
    /// 徽章的 rawValue → 获得的时间（1970 年起的秒数）。用文字当名字：以后加了新徽章，旧数据照样读得出来
    private(set) var unlockedAt: [String: Double] = [:]
    /// 已经统计过一次了吗。第一次只悄悄记下已经达到的，不弹提示
    private(set) var hasBaseline = false

    func isUnlocked(_ achievement: Achievement) -> Bool {
        unlockedAt[achievement.rawValue] != nil
    }

    func unlockedDate(_ achievement: Achievement) -> Date? {
        unlockedAt[achievement.rawValue].map(Date.init(timeIntervalSince1970:))
    }

    var unlockedCount: Int {
        Achievement.allCases.filter(isUnlocked).count
    }

    /// 用最新的统计更新：记下新达到的徽章，返回这次要提示的（第一次统计时什么都不提示）。
    /// 已经获得过的不会再返回，所以同一个徽章只提示一次
    mutating func update(earned: Set<Achievement>, now: Date) -> [Achievement] {
        let new = Achievement.allCases.filter { earned.contains($0) && !isUnlocked($0) }
        for achievement in new {
            unlockedAt[achievement.rawValue] = now.timeIntervalSince1970
        }
        let isFirstCount = !hasBaseline
        hasBaseline = true
        return isFirstCount ? [] : new
    }

    #if DEBUG
    /// 只给模拟器里的开发者工具用：清空徽章，下次统计时像第一次获得一样弹提示
    static let debugCleared = AchievementLedger(unlockedAt: [:], hasBaseline: true)
    #endif
}

/// 徽章存在手机本地（UserDefaults）。「删除所有数据」时一起删掉
nonisolated enum AchievementStore {
    static let ledgerKey = "achievementLedger"
    /// 拍照识别后，保存前改过结果（改了某一项、删了一项或补了一项）
    static let adjustedAIKey = "habitAdjustedAI"

    static func load(from defaults: UserDefaults = .standard) -> AchievementLedger {
        guard let data = defaults.data(forKey: ledgerKey),
              let ledger = try? JSONDecoder().decode(AchievementLedger.self, from: data)
        else { return AchievementLedger() }
        return ledger
    }

    static func save(_ ledger: AchievementLedger, to defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(ledger) else { return }
        defaults.set(data, forKey: ledgerKey)
    }

    static func hasAdjustedAI(in defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: adjustedAIKey)
    }

    static func markAdjustedAI(in defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: adjustedAIKey)
    }
}
