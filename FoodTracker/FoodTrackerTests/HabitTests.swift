//
//  HabitTests.swift
//  FoodTrackerTests
//
//  记录习惯和徽章的测试：
//  - 统计只看有没有记录：比目标多的日子照样算，吃得多吃得少不影响任何数字和徽章
//  - 漏记一天不会让任何数字变小（只有「最长连续」，没有会清零的「当前连续」）
//  - 一周从周一开始；本周记 5 天就是 5/7，并得到「一周五天」
//  - 第一次统计只悄悄记下已经达到的徽章（老用户不会被一串提示刷屏），之后每个徽章只提示一次
//  用固定时区的日历和单独的一份设置，不受电脑时区影响，也不会动模拟器里 App 的真实数据。
//

import Foundation
import SwiftData
import Testing

@testable import FoodTracker

@MainActor
@Suite("记录习惯和徽章")
struct HabitTests {
    /// 固定用北京时间：2026-10-02 是星期五，这一周是 9月28日（周一）到 10月4日（周日）
    let calendar = DayMath.makeCalendar(timeZone: TimeZone(identifier: "Asia/Shanghai")!)

    func day(_ key: Int) -> Date { DayMath.date(fromDayKey: key, calendar: calendar) }

    func entry(_ dayKey: Int, _ meal: String = "lunch", _ name: String = "米饭", photo: Bool = false) -> HabitEntry {
        HabitEntry(dayKey: dayKey, meal: meal, name: name, isPhoto: photo)
    }

    /// 9月28日（周一）到 10月2日（周五）。注意不能写成 20260928...20261002：整数区间会多出 20260931 这种不存在的日子
    let mondayToFriday = [20260928, 20260929, 20260930, 20261001, 20261002]

    func stats(_ entries: [HabitEntry], today: Int = 20261002) -> HabitStats {
        HabitStats.make(entries: entries, today: day(today), calendar: calendar)
    }

    // MARK: - 统计

    @Test("没有记录时全是 0")
    func empty() {
        #expect(stats([]) == .empty)
        #expect(Achievement.earned(by: .empty, adjustedAI: false).isEmpty)
    }

    @Test("天数、餐数、食物种类、拍照")
    func basicCounts() {
        let result = stats([
            entry(20261001, "lunch", "米饭"),
            entry(20261001, "lunch", "鸡蛋"),  // 同一餐里的第二种食物：还是一餐
            entry(20261001, "dinner", "米饭 "),  // 名字规范化后和「米饭」一样
            entry(20261002, "breakfast", "Rice", photo: true),
            entry(20261002, "snack", "rice"),
        ])
        #expect(result.loggedDays == 2)
        #expect(result.mealCount == 4)
        #expect(result.distinctFoods == 3)  // 米饭、鸡蛋、rice
        #expect(result.usedPhoto)
    }

    @Test("本周记了 5 天：5/7，并得到「一周五天」（CASE 5）")
    func fiveDaysThisWeek() {
        let result = stats(mondayToFriday.map { entry($0) })
        #expect(result.daysThisWeek == 5)
        #expect(result.bestWeekDays == 5)
        #expect(result.longestStreak == 5)
        #expect(Achievement.fiveDaysInWeek.isEarned(by: result, adjustedAI: false))
        #expect(HabitCopy.daysThisWeek(result.daysThisWeek).contains("5/7"))
    }

    @Test("一周从周一开始：周日和前面的周一同一周，下周一重新算")
    func weekStartsOnMonday() {
        let entries = [entry(20260928), entry(20261004)]  // 周一、周日
        #expect(stats(entries, today: 20261004).daysThisWeek == 2)
        #expect(stats(entries, today: 20261005).daysThisWeek == 0)  // 新的一周
        #expect(stats(entries, today: 20261005).bestWeekDays == 2)  // 以前的记录还在
    }

    @Test("昨天没记：最长连续不变，也没有任何「断了」的说法（CASE 6）")
    func missedYesterday() {
        let before = stats([entry(20260929), entry(20260930)], today: 20261001)
        // 10月1日没记，10月2日又记了
        let after = stats([entry(20260929), entry(20260930), entry(20261002)], today: 20261002)
        #expect(after.longestStreak == before.longestStreak)
        #expect(after.loggedDays == before.loggedDays + 1)
        #expect(after.daysThisWeek == 3)
        for days in 0...7 {
            let line = HabitCopy.weekLine(daysThisWeek: days)
            for word in ["断", "失败", "错过", "没有坚持", "可惜", "!", "！"] {
                #expect(!line.contains(word), "「\(word)」出现在：\(line)")
            }
        }
    }

    @Test("最长连续跨月也能接上")
    func streakAcrossMonths() {
        let result = stats([entry(20260929), entry(20260930), entry(20261001), entry(20261002), entry(20260925)])
        #expect(result.longestStreak == 4)
    }

    @Test("连续 4 周、每周至少 4 天：得到「稳定的一个月」；中间空一周就重新数")
    func steadyWeeks() {
        // 9月7日、14日、21日、28日都是周一：四周里每周记周一到周四
        let weeks = [20260907, 20260914, 20260921, 20260928]
        let fourWeeks = weeks.flatMap { monday in (0..<4).map { entry(monday + $0) } }
        let result = stats(fourWeeks)
        #expect(result.longestSteadyWeeks == 4)
        #expect(Achievement.fourSteadyWeeks.isEarned(by: result, adjustedAI: false))

        // 去掉 9月14日那一周：只剩连续两周（21 日、28 日）
        let withGap = fourWeeks.filter { !(20260914...20260917).contains($0.dayKey) }
        #expect(stats(withGap).longestSteadyWeeks == 2)
        // 一周只记 3 天不算「稳定的一周」
        let threeDays = weeks.flatMap { monday in (0..<3).map { entry(monday + $0) } }
        #expect(stats(threeDays).longestSteadyWeeks == 0)
    }

    // MARK: - 和吃多吃少无关

    /// 存一组记录，返回统计和达到的徽章。kcal：每条记录的热量
    func countFromStore(kcal: Double) throws -> (HabitStats, [Achievement]) {
        let container = try ModelContainer(
            for: Schema(AppModels.all), configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext
        for (index, key) in mondayToFriday.enumerated() {
            for meal in [MealType.breakfast, .lunch] {
                context.insert(
                    FoodEntry(
                        dayKey: key, meal: meal, name: "食物\(index)", weightG: nil,
                        values: NutrientValues(caloriesKcal: kcal), source: .manual))
            }
        }
        try context.save()
        let defaults = try #require(UserDefaults(suiteName: "HabitTests-\(UUID().uuidString)"))
        let center = HabitCenter(defaults: defaults)
        center.refresh(context: context, now: day(20261001))  // 第一次：悄悄记下
        let earned = Achievement.allCases.filter(center.ledger.isUnlocked)
        return (center.stats, earned)
    }

    @Test("比目标多很多的日子照样算记录（CASE 7）")
    func overTargetDaysCount() throws {
        let (result, earned) = try countFromStore(kcal: 5000)
        #expect(result.loggedDays == 5)
        #expect(result.mealCount == 10)
        #expect(earned.contains(.fiveDaysInWeek))
        #expect(earned.contains(.tenMeals))
    }

    @Test("吃得少不会多得徽章：热量是 0 还是 5000，统计和徽章完全一样（CASE 8）")
    func noBadgeForEatingLittle() throws {
        let little = try countFromStore(kcal: 0)
        let much = try countFromStore(kcal: 5000)
        #expect(little.0 == much.0)
        #expect(little.1 == much.1)
    }

    // MARK: - 徽章只提示一次

    @Test("第一次统计只悄悄记下（老用户不会被刷屏）；之后每个徽章只提示一次；获得了不会收回")
    func ledger() {
        var ledger = AchievementLedger()
        let now = day(20261002)
        // 老用户第一次统计：已经达到的都记下，但不提示
        #expect(ledger.update(earned: [.firstMeal, .tenMeals], now: now).isEmpty)
        #expect(ledger.isUnlocked(.firstMeal) && ledger.isUnlocked(.tenMeals))
        #expect(ledger.unlockedDate(.firstMeal) == now)
        // 新达到一个：提示这一个
        #expect(ledger.update(earned: [.firstMeal, .tenMeals, .firstPhoto], now: now) == [.firstPhoto])
        // 再统计一次：没有新的，不再提示
        #expect(ledger.update(earned: [.firstMeal, .tenMeals, .firstPhoto], now: now).isEmpty)
        // 删了记录、统计变少：徽章还在
        #expect(ledger.update(earned: [], now: now).isEmpty)
        #expect(ledger.unlockedCount == 3)
    }

    @Test("新用户：第一次统计时还没有记录，记了第一餐就提示「第一餐」")
    func newUserFirstMeal() {
        var ledger = AchievementLedger()
        #expect(ledger.update(earned: [], now: .now).isEmpty)
        #expect(ledger.update(earned: [.firstMeal], now: .now) == [.firstMeal])
        #expect(ledger.update(earned: [.firstMeal], now: .now).isEmpty)
    }

    @Test("徽章存在本地：存了能读回来；读不懂的数据当作还没有徽章")
    func storeRoundTrip() throws {
        let defaults = try #require(UserDefaults(suiteName: "HabitTests-\(UUID().uuidString)"))
        var ledger = AchievementLedger()
        _ = ledger.update(earned: [.firstMeal], now: day(20261002))
        AchievementStore.save(ledger, to: defaults)
        #expect(AchievementStore.load(from: defaults) == ledger)

        defaults.set(Data("不是 JSON".utf8), forKey: AchievementStore.ledgerKey)
        #expect(AchievementStore.load(from: defaults) == AchievementLedger())
    }

    @Test("从数据库统计：老用户第一次不提示；新拍照的一餐只提示一次；改过 AI 结果得到「亲自校对」")
    func centerAnnouncesOnce() throws {
        let container = try ModelContainer(
            for: Schema(AppModels.all), configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext
        for key in 20260921...20260930 {
            context.insert(
                FoodEntry(dayKey: key, meal: .lunch, name: "米饭", weightG: 150, values: NutrientValues(caloriesKcal: 174), source: .manual))
        }
        try context.save()
        let defaults = try #require(UserDefaults(suiteName: "HabitTests-\(UUID().uuidString)"))
        let center = HabitCenter(defaults: defaults)

        // 老用户刚更新：10 天各记了一餐（9月21日那一周记满了 7 天），第一次统计什么都不提示，但徽章已经记下了
        #expect(center.refresh(context: context, now: day(20261001)).isEmpty)
        #expect(center.ledger.isUnlocked(.firstMeal) && center.ledger.isUnlocked(.tenMeals))
        #expect(center.ledger.isUnlocked(.fiveDaysInWeek))
        #expect(center.ledger.unlockedCount == 3)

        // 拍照记了一餐：提示「拍一拍」，只提示一次
        context.insert(
            FoodEntry(dayKey: 20261001, meal: .dinner, name: "番茄炒蛋", weightG: 200, values: NutrientValues(caloriesKcal: 180), source: .photo))
        try context.save()
        #expect(center.refresh(context: context, now: day(20261001)) == [.firstPhoto])
        #expect(center.refresh(context: context, now: day(20261001)).isEmpty)

        // 识别结果页改过 AI 的结果再保存
        AchievementStore.markAdjustedAI(in: defaults)
        #expect(center.refresh(context: context, now: day(20261001)) == [.adjustedAI])

        // 换一个 HabitCenter（相当于重新打开 App）：读回存着的徽章，不会再提示
        let reopened = HabitCenter(defaults: defaults)
        #expect(reopened.refresh(context: context, now: day(20261001)).isEmpty)
        #expect(reopened.ledger.unlockedCount == 5)
    }

    @Test("每个徽章都有名字、说明、获得方法和图标")
    func achievementCopy() {
        #expect(Achievement.allCases.count == 8)
        for achievement in Achievement.allCases {
            #expect(!achievement.title.isEmpty)
            #expect(!achievement.detail.isEmpty)
            #expect(!achievement.requirement.isEmpty)
            #expect(!achievement.systemImage.isEmpty)
            for word in ["少吃", "吃得少", "没超", "热量", "千卡", "!", "！"] {
                #expect(!achievement.title.contains(word) && !achievement.detail.contains(word) && !achievement.requirement.contains(word))
            }
        }
    }
}
