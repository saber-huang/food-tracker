//
//  HintEngineTests.swift
//  FoodTrackerTests
//
//  热量提示判断逻辑的测试。固定用上海时区、固定「现在」是 2026 年 9 月 30 日（周三）、目标 1460 千卡，
//  这样每条规则的边界（85% = 1241 千卡、120% = 1752 千卡）都能精确验证。
//  history 里的每一行是「某一天吃了多少、记过哪几顿正餐」，由测试直接构造，不经过数据库。
//

import Foundation
import Testing

@testable import FoodTracker

@Suite("热量提示判断")
struct HintEngineTests {
    let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return c
    }()
    let target = 1460.0
    let all = Set(MealSlot.allCases)

    /// 上海时间的某个时刻
    func at(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ mi: Int = 0) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: mi))!
    }

    /// 「现在」：2026 年 9 月 30 日 14 点（周三，ISO 第 40 周）
    var now: Date { at(2026, 9, 30, 14) }

    /// 从 base 那天算起往前（负数）或往后几天的 0 点
    func day(_ offset: Int, from base: Date? = nil) -> Date {
        cal.date(byAdding: .day, value: offset, to: cal.startOfDay(for: base ?? now))!
    }

    func intake(_ offset: Int, _ kcal: Double, _ meals: Set<MealSlot> = [.breakfast, .lunch], base: Date? = nil) -> DayIntake {
        DayIntake(day: day(offset, from: base), kcal: kcal, mainMeals: meals)
    }

    func input(
        _ history: [DayIntake], now n: Date? = nil, goal: Goal = .loseFat, level: HintLevel = .all,
        state: HintState = HintState(), changedAt: Date? = nil, target t: Double? = nil
    ) -> HintInput {
        let n = n ?? now
        return HintInput(
            goal: goal, targetKcal: t ?? target, targetChangedAt: changedAt ?? day(-60, from: n), history: history,
            now: n, calendar: cal, level: level, state: state)
    }

    /// 今天吃了 kcal、记了 meals 这几顿正餐，现在 hour 点：今天的提示是什么
    func today(_ kcal: Double, _ meals: Set<MealSlot>, hour: Int, changedAt: Date? = nil) -> CalorieHint? {
        let n = at(2026, 9, 30, hour)
        return HintEngine.todayHint(
            today: DayIntake(day: day(0, from: n), kcal: kcal, mainMeals: meals), targetKcal: target,
            targetChangedAt: changedAt ?? day(-60, from: n), now: n, calendar: cal)
    }

    func weekly(
        _ history: [DayIntake], goal: Goal = .loseFat, changedAt: Date? = nil, dismissed: String = "",
        target t: Double? = nil, now n: Date? = nil
    ) -> WeeklySummary? {
        let n = n ?? now
        return HintEngine.weeklySummary(
            history: history, targetKcal: t ?? target, goal: goal, targetChangedAt: changedAt ?? day(-60, from: n), now: n,
            calendar: cal, dismissedWeek: dismissed)
    }

    /// 上周（9 月 21 日周一起）5 天，每天 1500 千卡、记了早餐和午餐
    var lastWeek5: [DayIntake] {
        (0..<5).map {
            DayIntake(day: cal.date(byAdding: .day, value: $0, to: at(2026, 9, 21))!, kcal: 1500, mainMeals: [.breakfast, .lunch])
        }
    }

    /// 昨天、前天、大前天都吃了 1800（目标的 123%）
    var streak3: [DayIntake] { [intake(-1, 1800), intake(-2, 1800), intake(-3, 1800)] }

    // MARK: - 今天的提示

    @Test("接近目标：85% 的边界（1241 千卡）按整千卡算，还得有来得及吃的正餐")
    func nearLimit() {
        #expect(today(1240, [.breakfast, .lunch], hour: 18) == nil)
        #expect(today(1242, [.breakfast, .lunch], hour: 18) == .nearLimit(remainingKcal: 220, nextMeal: .dinner))
        #expect(today(1240.6, [.breakfast, .lunch], hour: 18) == .nearLimit(remainingKcal: 220, nextMeal: .dinner))  // 四舍五入到 1241
        #expect(!HintEngine.reaches(1240, 0.85, of: 1460))
        #expect(HintEngine.reaches(1240.6, 0.85, of: 1460))
        #expect(today(1300, [.breakfast, .lunch, .dinner], hour: 18) == nil)  // 正餐都记过了：今天走得很稳
        #expect(today(1300, [.breakfast, .lunch], hour: 18) == .nearLimit(remainingKcal: 160, nextMeal: .dinner))
        #expect(today(1300, [.breakfast, .dinner], hour: 20) == nil)  // 只剩午餐没记，但 20 点已经过了午餐时间
        #expect(today(1300, [], hour: 18) == .nearLimit(remainingKcal: 160, nextMeal: .dinner))  // 只记了加餐
    }

    @Test("下一餐：早餐 11 点前、午餐 16 点前、晚餐一直算")
    func nextMeal() {
        let cases: [(Set<MealSlot>, Int, MealSlot?)] = [
            (all, 8, .breakfast), (all, 11, .lunch), ([.lunch, .dinner], 8, .lunch), ([.breakfast, .dinner], 12, .dinner),
            ([.breakfast], 20, nil), ([.lunch], 16, nil), ([.lunch], 15, .lunch), ([.dinner], 23, .dinner), ([], 12, nil),
            (all, 10, .breakfast), (all, 16, .dinner),
        ]
        for (unlogged, hour, expected) in cases {
            #expect(HintEngine.nextMeal(unlogged: unlogged, hour: hour) == expected, "\(unlogged) \(hour) 点")
        }
    }

    @Test("到达或多于目标：数字四舍五入到 10，改资料当天不提示")
    func over() {
        #expect(today(1500, all, hour: 20) == .over(byKcal: 40, nextMeal: nil))
        #expect(today(1462, all, hour: 20) == .over(byKcal: 0, nextMeal: nil))
        #expect(today(1459.6, all, hour: 20) == .over(byKcal: 0, nextMeal: nil))  // 按整千卡算就是 1460
        #expect(today(1459.4, all, hour: 20) == nil)  // 没到目标，正餐又都记过了
        #expect(today(1500, [.lunch], hour: 13) == .over(byKcal: 40, nextMeal: .dinner))
        let changedToday = at(2026, 9, 30, 9)
        #expect(today(1800, all, hour: 20, changedAt: changedToday) == nil)  // 改资料的当天不说「比目标多」
        #expect(today(1800, all, hour: 20, changedAt: at(2026, 9, 29, 20)) == .over(byKcal: 340, nextMeal: nil))
        #expect(today(1300, [.breakfast, .lunch], hour: 18, changedAt: changedToday) == .nearLimit(remainingKcal: 160, nextMeal: .dinner))
    }

    // MARK: - 按目标和设置过滤

    @Test("没有记录就没有提示")
    func noEntries() {
        for level in HintLevel.allCases {
            for goal in Goal.allCases {
                #expect(HintEngine.hints(input([], goal: goal, level: level)).isEmpty)
            }
        }
    }

    @Test("按目标：减脂看全部，维持只看每周小结，增肌什么都不看")
    func goalGating() {
        let n18 = at(2026, 9, 30, 18)
        let nearToday = intake(0, 1300, [.breakfast, .lunch], base: n18)
        #expect(HintEngine.hints(input([nearToday], now: n18, goal: .loseFat)) == [.nearLimit(remainingKcal: 160, nextMeal: .dinner)])
        #expect(HintEngine.hints(input([nearToday], now: n18, goal: .maintain)).isEmpty)
        #expect(HintEngine.hints(input([nearToday], now: n18, goal: .gainMuscle)).isEmpty)
        let maintain = HintEngine.hints(input(lastWeek5, goal: .maintain))
        #expect(maintain.count == 1)
        if case .weeklySummary = maintain.first {} else { Issue.record("维持目标应该看到每周小结") }
        #expect(HintEngine.hints(input(lastWeek5, goal: .gainMuscle)).isEmpty)
    }

    @Test("按设置：关闭、只看每周小结、全部开启")
    func levelGating() {
        let n18 = at(2026, 9, 30, 18)
        let nearToday = intake(0, 1300, [.breakfast, .lunch], base: n18)
        let everything = [nearToday] + streak3 + lastWeek5
        #expect(HintEngine.hints(input(everything, now: n18, level: .off)).isEmpty)
        let weeklyOnly = HintEngine.hints(input(everything, now: n18, level: .weeklyOnly))
        #expect(weeklyOnly.count == 1)
        if case .weeklySummary = weeklyOnly.first {} else { Issue.record("只看每周小结时应该只有小结") }
        #expect(
            HintEngine.hints(input(everything, now: n18, level: .all)) == [
                .nearLimit(remainingKcal: 160, nextMeal: .dinner), .adjustTarget(consecutiveDays: 3),
            ])
    }

    // MARK: - 连续几天明显偏高

    @Test("连续几天明显偏高：从昨天往前数，缺一天就中断，最多 7 天")
    func streak() {
        func streak(_ history: [DayIntake], changedAt: Date? = nil) -> Int {
            HintEngine.overStreak(
                history: history, targetKcal: target, targetChangedAt: changedAt ?? day(-60), now: now, calendar: cal)
        }
        #expect(streak(streak3) == 3)
        #expect(streak([intake(-1, 1800), intake(-2, 1700), intake(-3, 1800)]) == 1)
        #expect(streak([intake(-1, 1751), intake(-2, 1800), intake(-3, 1800)]) == 0)  // 120% 是 1752
        #expect(streak([intake(-1, 1752), intake(-2, 1751.6), intake(-3, 1800)]) == 3)
        #expect(streak([intake(0, 1800), intake(-1, 1800), intake(-2, 1800), intake(-3, 1000)]) == 2)  // 今天还没吃完，不算
        #expect(streak([intake(-1, 1800), intake(-3, 1800), intake(-4, 1800)]) == 1)  // 前天没记录：中断
        #expect(streak(streak3, changedAt: at(2026, 9, 28, 12)) == 1)  // 改资料那天和之前的天不算
        #expect(streak(streak3, changedAt: at(2026, 9, 30, 9)) == 0)
        #expect(streak((1...10).map { intake(-$0, 1800) }) == 7)
    }

    @Test("点过「先不用」：7 天内不再问，小结照常显示")
    func snooze() {
        let snoozed = HintEngine.hints(
            input(streak3 + lastWeek5, state: HintState(weeklyDismissedWeek: "", adjustSnoozedUntil: now.addingTimeInterval(86400))))
        #expect(!snoozed.contains(.adjustTarget(consecutiveDays: 3)))
        if case .weeklySummary = snoozed.last {} else { Issue.record("先不用之后应该显示小结") }
        let expired = HintEngine.hints(
            input(streak3, state: HintState(weeklyDismissedWeek: "", adjustSnoozedUntil: now.addingTimeInterval(-1))))
        #expect(expired.contains(.adjustTarget(consecutiveDays: 3)))
    }

    // MARK: - 每周小结

    @Test("周的编号和上一周：固定按周一～周日")
    func weeks() {
        #expect(HintEngine.weekKey(for: at(2025, 12, 28, 12), calendar: cal) == "2025-W52")
        #expect(HintEngine.weekKey(for: at(2025, 12, 29, 12), calendar: cal) == "2026-W01")
        #expect(HintEngine.weekKey(for: at(2027, 1, 3, 12), calendar: cal) == "2026-W53")
        #expect(HintEngine.weekKey(for: at(2027, 1, 4, 12), calendar: cal) == "2027-W01")
        #expect(HintEngine.weekKey(for: at(2026, 9, 30, 12), calendar: cal) == "2026-W40")
        let previous = HintEngine.previousWeek(containing: now, calendar: cal)
        #expect(previous.start == at(2026, 9, 21) && previous.end == at(2026, 9, 28))
        #expect(HintEngine.previousWeek(containing: at(2026, 10, 4, 23), calendar: cal).start == at(2026, 9, 21))
        #expect(HintEngine.previousWeek(containing: at(2026, 10, 5, 9), calendar: cal).start == at(2026, 9, 28))
        #expect(HintEngine.previousWeek(containing: at(2026, 10, 5), calendar: cal).start == at(2026, 9, 28))
        #expect(HintEngine.weekKey(for: at(2026, 10, 5), calendar: cal) == "2026-W41")
    }

    @Test("每周小结：只算记了至少 2 顿正餐的天，本周的记录不算")
    func weeklyCounting() {
        let w1 = weekly(lastWeek5 + [DayIntake(day: at(2026, 9, 26), kcal: 400, mainMeals: [.lunch])])
        #expect(
            w1 == WeeklySummary(
                weekKey: "2026-W39", daysCounted: 5, averageKcal: 1500, targetKcal: 1460, differenceKcal: 40, trend: .onTarget,
                suggestsAdjustingTarget: false, targetChangedRecently: false))
        let thisWeek = (0..<3).map {
            DayIntake(day: cal.date(byAdding: .day, value: $0, to: at(2026, 9, 28))!, kcal: 2500, mainMeals: all)
        }
        let w2 = weekly(lastWeek5 + thisWeek)
        #expect(w2?.averageKcal == 1500 && w2?.trend == .onTarget && w2?.daysCounted == 5)
        let w3 = weekly(Array(lastWeek5.prefix(2)), changedAt: at(2026, 9, 23, 10))
        #expect(w3?.trend == .fewDays && w3?.daysCounted == 2 && w3?.targetChangedRecently == false)
        #expect(weekly(lastWeek5.map { DayIntake(day: $0.day, kcal: $0.kcal, mainMeals: []) }) == nil)  // 只有加餐：不算
    }

    @Test("每周小结：相差 10% 以内算一致；明显偏高（120%）且减脂才建议调整目标")
    func weeklyBands() {
        func band(_ kcal: Double, goal: Goal = .loseFat) -> WeeklySummary? {
            weekly(lastWeek5.map { DayIntake(day: $0.day, kcal: kcal, mainMeals: $0.mainMeals) }, goal: goal)
        }
        #expect(band(1600)?.trend == .onTarget)
        #expect(band(1620)?.trend == .above && band(1620)?.differenceKcal == 160 && band(1620)?.suggestsAdjustingTarget == false)
        #expect(band(1800)?.trend == .above && band(1800)?.differenceKcal == 340 && band(1800)?.suggestsAdjustingTarget == true)
        #expect(band(1800, goal: .maintain)?.suggestsAdjustingTarget == false)
        #expect(band(1300)?.trend == .below && band(1300)?.differenceKcal == -160)
        #expect(band(1320)?.trend == .onTarget)
        // 目标不是整数（1463.28）：平均四舍五入到 10，目标取整，差值就是这两个数相减
        let tt = 1463.28
        let seven = (0..<7).map {
            DayIntake(day: cal.date(byAdding: .day, value: $0, to: at(2026, 9, 21))!, kcal: 1.25 * tt, mainMeals: all)
        }
        let w4 = weekly(seven, target: tt)
        #expect(
            w4?.averageKcal == 1830 && w4?.targetKcal == 1463 && w4?.differenceKcal == 367 && w4?.trend == .above
                && w4?.suggestsAdjustingTarget == true)
        let five103 = (0..<5).map {
            DayIntake(day: cal.date(byAdding: .day, value: $0, to: at(2026, 9, 21))!, kcal: 1.03 * tt, mainMeals: all)
        }
        let w5 = weekly(five103, target: tt)
        #expect(w5?.averageKcal == 1510 && w5?.targetKcal == 1463 && w5?.trend == .onTarget)
    }

    @Test("每周小结：点过「知道了」的那一周不再显示；改过资料要说明")
    func weeklyDismissAndChange() {
        #expect(weekly(lastWeek5, dismissed: "2026-W39") == nil)
        #expect(weekly(lastWeek5, dismissed: "2026-W38") != nil)
        #expect(weekly(lastWeek5, changedAt: at(2026, 9, 23))?.targetChangedRecently == true)
        #expect(weekly(lastWeek5, changedAt: at(2026, 9, 10))?.targetChangedRecently == false)
        #expect(weekly(lastWeek5, changedAt: at(2026, 9, 21, 10))?.targetChangedRecently == false)  // 第一个完整天当天改的不算
        let tueFri = (1..<5).map {
            DayIntake(day: cal.date(byAdding: .day, value: $0, to: at(2026, 9, 21))!, kcal: 1500, mainMeals: [.breakfast, .lunch])
        }
        #expect(weekly(tueFri, changedAt: at(2026, 9, 22, 10))?.targetChangedRecently == false)
        #expect(weekly(tueFri, changedAt: at(2026, 9, 23, 15))?.targetChangedRecently == true)
        #expect(weekly(tueFri, changedAt: at(2026, 9, 29, 8))?.targetChangedRecently == true)  // 这周改的也算
    }

    // MARK: - 显示顺序

    @Test("最多两条：今天的一条在前，卡片在后；连续偏高的卡片优先于小结")
    func priorityAndCap() {
        let n18 = at(2026, 9, 30, 18)
        let nearToday = intake(0, 1300, [.breakfast, .lunch], base: n18)
        let everything = [nearToday] + streak3 + lastWeek5
        #expect(
            HintEngine.hints(input(everything, now: n18)) == [
                .nearLimit(remainingKcal: 160, nextMeal: .dinner), .adjustTarget(consecutiveDays: 3),
            ])
        let snoozedAll = HintEngine.hints(
            input(everything, now: n18, state: HintState(weeklyDismissedWeek: "", adjustSnoozedUntil: n18.addingTimeInterval(3600))))
        #expect(snoozedAll.count == 2)
        if case .weeklySummary = snoozedAll.last {} else { Issue.record("先不用之后第二条应该是小结") }
        // 各种组合都不会多于两条，第一条也不会是卡片
        for kcal in [0.0, 1000, 1300, 1460, 1800] {
            for hour in [8, 12, 18, 22] {
                for history in [[], streak3, lastWeek5, streak3 + lastWeek5] {
                    let n = at(2026, 9, 30, hour)
                    let todayRows = kcal > 0 ? [DayIntake(day: day(0, from: n), kcal: kcal, mainMeals: [.breakfast])] : []
                    let result = HintEngine.hints(input(history + todayRows, now: n))
                    #expect(result.count <= 2)
                    if result.count == 2, let first = result.first {
                        switch first {
                        case .weeklySummary, .adjustTarget: Issue.record("第一条不应该是卡片：\(result)")
                        default: break
                        }
                    }
                }
            }
        }
    }

    // MARK: - 小工具

    @Test("四舍五入到 10、按天整理、从记录汇总")
    func tools() {
        for (x, expected) in [(213.0, 210), (215, 220), (4, 0), (5, 10), (1246, 1250), (-44, -40), (146.33, 150), (219.28, 220), (0, 0)] {
            #expect(HintEngine.roundToTen(x) == expected, "\(x)")
        }
        let dup = HintEngine.byDay(
            [DayIntake(day: at(2026, 9, 30, 23, 59), kcal: 1, mainMeals: []), DayIntake(day: at(2026, 9, 30), kcal: 2, mainMeals: [])],
            calendar: cal)
        #expect(dup.count == 1 && dup[at(2026, 9, 30)]?.kcal == 1)  // 同一天出现两次：用第一条
        let records: [(day: Date, mealRaw: String, kcal: Double)] = [
            (at(2026, 9, 30), "breakfast", 300), (at(2026, 9, 30), "lunch", 500), (at(2026, 9, 30), "snack", 150),
            (at(2026, 9, 30), "brunch", 50), (at(2026, 9, 29), "snack", 200),
        ]
        let summary = HintEngine.byDay(DayIntake.summarize(records, calendar: cal), calendar: cal)
        #expect(summary.count == 2)
        #expect(summary[at(2026, 9, 30)]?.kcal == 1000 && summary[at(2026, 9, 30)]?.mainMeals == [.breakfast, .lunch])
        #expect(summary[at(2026, 9, 29)]?.kcal == 200 && summary[at(2026, 9, 29)]?.mainMeals == [])
    }

    // MARK: - 资料没改就不算修改（UserProfile.update 靠它判断）

    // 「编辑资料」页把数字变成文字再变回来，必须一模一样，否则没改任何东西点「保存」也会被当成改过资料
    @MainActor
    @Test("资料在编辑表单里走一圈，数字不变")
    func profileDraftRoundTrip() {
        for weight in [60.0, 62.3, 72.35, 58.7] {
            let body = BodyInfo(sex: .female, age: 28, heightCm: 165.5, weightKg: weight, activity: .light, goal: .loseFat)
            #expect(ProfileDraft(from: body).bodyInfo == body)
        }
    }

    // MARK: - 推荐下一餐发给后端的请求

    // 例 2 的晚餐只剩约 213 千卡：按 320 千卡推荐，只要晚餐这一餐，数字是缩小后的每日目标
    @MainActor
    @Test("推荐下一餐：只请求这一餐，发的是缩小后的每日目标")
    func nextMealRequest() {
        let targets = NutritionCalculator.targets(
            for: BodyInfo(sex: .female, age: 28, heightCm: 165, weightKg: 60, activity: .light, goal: .loseFat))
        let budget = NextMealBudget(meal: .dinner, remainingKcal: 213.28, targets: targets)
        let request = RecipeRequest.make(
            goal: .loseFat, targets: budget.requestTargets, preferencesText: "  清淡  ", allergiesText: "花生、虾",
            dislikesText: "", cookingMinutes: 30, meals: [budget.meal], excludeNames: [])
        #expect(request.meals == [.dinner])
        #expect(request.goal == "loseFat")
        #expect(abs(request.dailyCalories - 1066.67) < 0.01)  // × 30% = 320 千卡
        #expect(abs(request.dailyCalories * 0.30 - 320) < 0.01)
        #expect(request.preferences == "清淡")
        #expect(request.allergies == ["花生", "虾"])
        #expect(request.dislikes.isEmpty)
        // 「食谱」页用的是原样的每日目标
        let full = RecipeRequest.make(
            goal: .loseFat, targets: RequestTargets(targets), preferencesText: "", allergiesText: "", dislikesText: "",
            cookingMinutes: 30, meals: MealSlot.allCases, excludeNames: [])
        #expect(full.dailyCalories == targets.calories && full.dailyProteinG == targets.proteinG)
    }

    // MARK: - 推荐下一餐的预算

    @Test("推荐下一餐：不少于 320 千卡、不多于平时这一餐；发给后端的数在它接受的范围内")
    func nextMealBudget() {
        let example = NutritionCalculator.targets(
            for: BodyInfo(sex: .female, age: 28, heightCm: 165, weightKg: 60, activity: .light, goal: .loseFat))
        func close(_ a: Double, _ b: Double, _ tolerance: Double = 0.01) -> Bool { abs(a - b) <= tolerance }
        let b1 = NextMealBudget(meal: .dinner, remainingKcal: 213.28, targets: example)
        #expect(b1.mealKcal == 320 && b1.wasRaisedToFloor)
        #expect(
            close(b1.requestTargets.calories, 1066.67) && close(b1.requestTargets.proteinG, 87.47)
                && close(b1.requestTargets.carbsG, 112.52) && close(b1.requestTargets.fatG, 29.63))
        #expect(
            close(b1.mealTargets.calories, 320) && close(b1.mealTargets.proteinG, 26.24) && close(b1.mealTargets.carbsG, 33.76)
                && close(b1.mealTargets.fatG, 8.89))
        let b2 = NextMealBudget(meal: .lunch, remainingKcal: 400, targets: example)
        #expect(!b2.wasRaisedToFloor && b2.requestTargets.calories == 1000)
        let b3 = NextMealBudget(meal: .lunch, remainingKcal: 250, targets: example)
        #expect(b3.mealKcal == 320 && b3.requestTargets.calories == 800)  // 正好是后端的下限
        let b4 = NextMealBudget(meal: .breakfast, remainingKcal: 3000, targets: example)
        #expect(
            close(b4.mealKcal, 438.98) && !b4.wasRaisedToFloor && close(b4.requestTargets.calories, example.calories, 1e-6)
                && close(b4.requestTargets.proteinG, 120, 1e-6))
        // 各种极端身材 × 各种剩余量：发给后端的数都在它接受的范围内
        let bodies = [
            BodyInfo(sex: .male, age: 30, heightCm: 180, weightKg: 80, activity: .moderate, goal: .maintain),
            BodyInfo(sex: .female, age: 28, heightCm: 165, weightKg: 60, activity: .light, goal: .loseFat),
            BodyInfo(sex: .female, age: 50, heightCm: 155, weightKg: 50, activity: .sedentary, goal: .loseFat),
            BodyInfo(sex: .male, age: 18, heightCm: 230, weightKg: 250, activity: .veryActive, goal: .gainMuscle),
            BodyInfo(sex: .male, age: 18, heightCm: 230, weightKg: 250, activity: .veryActive, goal: .loseFat),
            BodyInfo(sex: .female, age: 80, heightCm: 120, weightKg: 30, activity: .sedentary, goal: .maintain),
        ]
        for body in bodies {
            let targets = NutritionCalculator.targets(for: body)
            for meal in MealSlot.allCases {
                for remaining in [0.0, 3, 50, 150, 319.9, 320, 0.15 * targets.calories, 0.5 * targets.calories, targets.calories, 3000] {
                    let budget = NextMealBudget(meal: meal, remainingKcal: remaining, targets: targets)
                    let request = budget.requestTargets
                    #expect(
                        request.calories >= 800 && request.calories <= 8000 && request.proteinG <= 600 && request.carbsG <= 1500
                            && request.fatG <= 500, "\(body) \(meal) \(remaining)")
                    #expect(abs(budget.mealTargets.calories - budget.mealKcal) < 0.01)
                    #expect(budget.mealKcal >= 320 && budget.mealKcal <= budget.usualMealKcal + 1e-9)
                }
            }
        }
    }
}
