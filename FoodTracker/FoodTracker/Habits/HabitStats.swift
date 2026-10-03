//
//  HabitStats.swift
//  FoodTracker
//
//  「记录习惯」的统计：这周记了几天、一共记了几天、最长连续几天、记过几餐、几种食物……
//  只看「有没有记录」，完全不看吃了多少：比目标多的日子照样算一天，吃得少也不会多得什么（这里根本没有热量）。
//  漏记一天不算「失败」：只有「最长连续」（只会变长、不会清零），没有一断就归零的「当前连续」。
//  只做计算，不涉及界面和存储，可以单独写单元测试（FoodTrackerTests/HabitTests.swift）
//

import Foundation

/// 统计只需要每条记录的这几样。故意不带热量：统计和吃多吃少无关
nonisolated struct HabitEntry: Equatable {
    let dayKey: Int  // 20260929 这样的数字
    let meal: String  // MealType 的英文名
    let name: String
    let isPhoto: Bool  // 是不是拍照识别记的
}

nonisolated struct HabitStats: Equatable {
    /// 有记录的天数（累计）
    var loggedDays = 0
    /// 记过几餐：同一天的同一餐算一餐（一餐里记了 3 种食物也是一餐）
    var mealCount = 0
    /// 记过几种不同的食物（名字规范化后一样的算一种：「米饭」「米饭 」）
    var distinctFoods = 0
    /// 用拍照记过
    var usedPhoto = false
    /// 这周（周一到周日）有几天有记录
    var daysThisWeek = 0
    /// 最长连续几天有记录
    var longestStreak = 0
    /// 记录最多的那一周有几天
    var bestWeekDays = 0
    /// 最长连续几周、每周都至少有 4 天的记录
    var longestSteadyWeeks = 0

    static let empty = HabitStats()
    /// 一周至少记了几天算「稳定的一周」
    static let steadyWeekDays = 4

    /// today：今天（决定「这周」是哪一周）
    static func make(entries: [HabitEntry], today: Date, calendar: Calendar = DayMath.calendar) -> HabitStats {
        guard !entries.isEmpty else { return .empty }
        var stats = HabitStats()
        let dayKeys = Set(entries.map(\.dayKey))
        stats.loggedDays = dayKeys.count
        stats.mealCount = Set(entries.map { "\($0.dayKey)-\($0.meal)" }).count
        stats.distinctFoods = Set(entries.map { FoodNameKey.normalize($0.name) }.filter { !$0.isEmpty }).count
        stats.usedPhoto = entries.contains(where: \.isPhoto)

        let days = dayKeys.map { DayMath.date(fromDayKey: $0, calendar: calendar) }.sorted()
        stats.longestStreak = longestRun(days) { DayMath.addingDays(1, to: $0, calendar: calendar) }

        // 每一周（用那周的周一表示）有几天有记录
        var daysPerWeek: [Date: Int] = [:]
        for day in days {
            daysPerWeek[DayMath.weekStart(containing: day, calendar: calendar), default: 0] += 1
        }
        stats.daysThisWeek = daysPerWeek[DayMath.weekStart(containing: today, calendar: calendar)] ?? 0
        stats.bestWeekDays = daysPerWeek.values.max() ?? 0
        let steadyWeeks = daysPerWeek.filter { $0.value >= steadyWeekDays }.keys.sorted()
        stats.longestSteadyWeeks = longestRun(steadyWeeks) { DayMath.weekStart(offset: 1, from: $0, calendar: calendar) }
        return stats
    }

    /// 排好序的日期里，最多有几个一个接一个（后一个正好是前一个的「下一个」）
    private static func longestRun(_ sorted: [Date], next: (Date) -> Date) -> Int {
        var longest = 0
        var run = 0
        var previous: Date?
        for date in sorted {
            run = (previous.map(next) == date) ? run + 1 : 1
            longest = max(longest, run)
            previous = date
        }
        return longest
    }
}
