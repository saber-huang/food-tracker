//
//  HintEngine.swift
//  FoodTracker
//
//  热量提示的判断逻辑：只做「算数和判断」，不涉及界面、存储和文案
//  （文案在 HintCopy.swift，测试在 FoodTrackerTests/HintEngineTests.swift）。
//  所有类型都标 nonisolated，和 NutritionCalculator 一样，单元测试可以直接调用。
//

import Foundation

// MARK: - 输入

/// 设置里的三个选项（rawValue 存在 UserDefaults）
nonisolated enum HintLevel: String, CaseIterable, Codable {
    case all, weeklyOnly, off
}

/// 某一天的摄入摘要（由饮食记录换算而来，见 DayIntake+Log.swift）
nonisolated struct DayIntake: Equatable {
    var day: Date                 // 当天 0 点（本地时区），和饮食记录的 day 一致
    var kcal: Double              // 这一天所有记录的热量，含加餐
    var mainMeals: Set<MealSlot>  // 已记录的正餐：早 / 午 / 晚；加餐不算
}

/// 用户点过「知道了」「先不用」的记录（存在 UserDefaults，由界面转换后传进来）
nonisolated struct HintState: Equatable {
    var weeklyDismissedWeek = ""          // 已点「知道了」的那一周，如 "2026-W39"
    var adjustSnoozedUntil: Date? = nil   // 到这个时间之前，不再问要不要调整目标
}

nonisolated struct HintInput {
    var goal: Goal                // profile.bodyInfo.goal
    var targetKcal: Double        // profile.targets.calories
    var targetChangedAt: Date     // profile.updatedAt：资料一改，目标就变
    var history: [DayIntake]      // 最近的记录（至少最近 14 天，含今天）；没有记录的天可以不出现
    var now: Date                 // 界面：HintClock.now；测试：固定时间
    var calendar: Calendar        // 界面：.autoupdatingCurrent；测试：固定时区
    var level: HintLevel
    var state: HintState
}

// MARK: - 输出

nonisolated enum WeeklyTrend: Hashable {
    case onTarget, above, below, fewDays
}

nonisolated struct WeeklySummary: Hashable {
    let weekKey: String               // 被总结的那一周，如 "2026-W39"
    let daysCounted: Int              // 记录较完整（至少 2 顿正餐）的天数
    let averageKcal: Int              // 平均每天，四舍五入到 10
    let targetKcal: Int               // 目标，取整（和首页显示的一样）
    let differenceKcal: Int           // averageKcal − targetKcal：卡片上两个数相减正好是它，可为负
    let trend: WeeklyTrend
    let suggestsAdjustingTarget: Bool // 平均明显高于目标（≥ 120%）且目标是减脂 → 附「调整目标」
    let targetChangedRecently: Bool   // 第一个完整天结束之后改过资料 → 附一句说明
}

nonisolated enum CalorieHint: Hashable {
    case nearLimit(remainingKcal: Int, nextMeal: MealSlot)   // 规则 1：接近目标
    case over(byKcal: Int, nextMeal: MealSlot?)              // 规则 2：到达或多于目标；nextMeal = 还没记录、还来得及吃的正餐
    case weeklySummary(WeeklySummary)                        // 规则 3：每周小结
    case adjustTarget(consecutiveDays: Int)                  // 规则 4：连续几天明显偏高
}

// MARK: - 判断

nonisolated enum HintEngine {
    /// 规则 1：摄入达到目标的 85%
    static let nearLimitShare = 0.85
    /// 「明显高于目标」：≥ 120%。减脂目标 = 消耗 − 20%，所以 120% 约等于吃到了维持热量，也超出了 AI 估算的误差
    static let clearlyOverShare = 1.20
    /// 规则 4：连续 3 天
    static let consecutiveDaysForAdjust = 3
    /// 连续天数最多往前看 7 天
    static let streakLookbackDays = 7
    /// 点「先不用」或「调整目标」后，7 天内不再问
    static let adjustSnoozeDays = 7
    /// 一天至少记了 2 顿正餐（加餐不算）才算进周平均，避免没记全的日子把平均拉低
    static let minMainMealsForCountedDay = 2
    /// 上周至少 3 个完整天才做对比；1～2 天换一种说法；0 天不显示
    static let minCountedDaysForComparison = 3
    /// 平均和目标相差不超过 10% 算「基本一致」
    static let weeklyOnTargetTolerance = 0.10
    /// 早餐 11 点以后、午餐 16 点以后不再算「还来得及吃」；晚餐一直有效。只用来决定「下一餐」是哪一餐
    static let breakfastClosesAtHour = 11
    static let lunchClosesAtHour = 16
    /// 判断最多用到最近 14 天（含今天）的记录：周日看上周要 13 天，连续天数要 7 天
    static let historyDays = 14
    /// 哪些目标显示哪些提示
    static let dailyHintGoals: Set<Goal> = [.loseFat]            // 规则 1、2
    static let adjustHintGoals: Set<Goal> = [.loseFat]           // 规则 4，以及小结里的「调整目标」
    static let weeklyGoals: Set<Goal> = [.loseFat, .maintain]    // 规则 3；增肌暂不显示

    /// 界面只调用这一个函数：按显示顺序返回提示，最多两条（今天的一条 + 一张卡片）
    static func hints(_ input: HintInput) -> [CalorieHint] {
        guard input.level != .off, input.targetKcal > 0 else { return [] }
        let days = byDay(input.history, calendar: input.calendar)
        let todayStart = input.calendar.startOfDay(for: input.now)

        var today: CalorieHint?
        if input.level == .all, dailyHintGoals.contains(input.goal) {
            today = todayHint(today: days[todayStart], targetKcal: input.targetKcal,
                              targetChangedAt: input.targetChangedAt, now: input.now, calendar: input.calendar)
        }
        var adjust: CalorieHint?
        if input.level == .all, adjustHintGoals.contains(input.goal),
           (input.state.adjustSnoozedUntil ?? .distantPast) <= input.now {
            let streak = overStreak(history: input.history, targetKcal: input.targetKcal,
                                    targetChangedAt: input.targetChangedAt, now: input.now, calendar: input.calendar)
            if streak >= consecutiveDaysForAdjust { adjust = .adjustTarget(consecutiveDays: streak) }
        }
        var weekly: CalorieHint?
        if weeklyGoals.contains(input.goal),   // .all 和 .weeklyOnly 都显示
           let summary = weeklySummary(history: input.history, targetKcal: input.targetKcal, goal: input.goal,
                                       targetChangedAt: input.targetChangedAt, now: input.now,
                                       calendar: input.calendar, dismissedWeek: input.state.weeklyDismissedWeek) {
            weekly = .weeklySummary(summary)
        }
        // 连续多天的卡片优先；小结不会因此「用掉」，点了「先不用」之后照常出现
        return [today, adjust ?? weekly].compactMap { $0 }
    }

    /// 今天的提示：接近目标，或到达 / 多于目标
    static func todayHint(today: DayIntake?, targetKcal: Double, targetChangedAt: Date,
                          now: Date, calendar: Calendar) -> CalorieHint? {
        guard let today, targetKcal > 0 else { return nil }   // 今天还没有记录 → 不提示
        let hour = calendar.component(.hour, from: now)
        let next = nextMeal(unlogged: Set(MealSlot.allCases).subtracting(today.mainMeals), hour: hour)
        if reaches(today.kcal, 1.0, of: targetKcal) {
            // 改资料的当天不说「比目标多」：今天有一部分是按原来的目标吃的
            if calendar.isDate(targetChangedAt, inSameDayAs: now) { return nil }
            return .over(byKcal: roundToTen(today.kcal - targetKcal), nextMeal: next)
        }
        // 到了 85%，但没有还来得及吃的正餐 → 今天走得很稳，不提示
        guard reaches(today.kcal, nearLimitShare, of: targetKcal), let next else { return nil }
        return .nearLimit(remainingKcal: roundToTen(targetKcal - today.kcal), nextMeal: next)
    }

    /// 下一餐：按早、午、晚的顺序，第一顿还没记录、也还来得及吃的正餐；没有就是 nil
    static func nextMeal(unlogged: Set<MealSlot>, hour: Int) -> MealSlot? {
        MealSlot.allCases.first { meal in
            guard unlogged.contains(meal) else { return false }
            switch meal {
            case .breakfast: return hour < breakfastClosesAtHour
            case .lunch: return hour < lunchClosesAtHour
            case .dinner: return true
            }
        }
    }

    /// 连续几天明显高于目标：从昨天往前数，今天还没吃完，不算
    static func overStreak(history: [DayIntake], targetKcal: Double, targetChangedAt: Date,
                           now: Date, calendar: Calendar) -> Int {
        let days = byDay(history, calendar: calendar)
        let todayStart = calendar.startOfDay(for: now)
        let changeDay = calendar.startOfDay(for: targetChangedAt)
        var streak = 0
        for back in 1...streakLookbackDays {
            guard let day = calendar.date(byAdding: .day, value: -back, to: todayStart),
                  day > changeDay,                                   // 改资料那天和之前的天不算
                  let intake = days[day],                            // 没有记录的天 → 中断（不知道 ≠ 吃多了）
                  reaches(intake.kcal, clearlyOverShare, of: targetKcal)
            else { break }
            streak += 1
        }
        return streak
    }

    /// 上一个完整的周一～周日的小结；已点「知道了」或一天完整记录都没有 → nil
    static func weeklySummary(history: [DayIntake], targetKcal: Double, goal: Goal, targetChangedAt: Date,
                              now: Date, calendar: Calendar, dismissedWeek: String) -> WeeklySummary? {
        guard targetKcal > 0 else { return nil }
        let week = previousWeek(containing: now, calendar: calendar)
        let key = weekKey(for: week.start, calendar: calendar)
        guard key != dismissedWeek else { return nil }
        let days = byDay(history, calendar: calendar)
        let counted = (0..<7).compactMap { offset -> DayIntake? in
            guard let day = calendar.date(byAdding: .day, value: offset, to: week.start) else { return nil }
            return days[calendar.startOfDay(for: day)]
        }.filter { $0.mainMeals.count >= minMainMealsForCountedDay }     // 没记录或不到 2 顿正餐的天不进平均
        guard let firstDay = counted.map(\.day).min(),                    // 一天都没有 → 什么都不说
              let firstDayEnd = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: firstDay))
        else { return nil }
        let average = counted.map(\.kcal).reduce(0, +) / Double(counted.count)
        let trend: WeeklyTrend
        if counted.count < minCountedDaysForComparison {
            trend = .fewDays
        } else if abs(average - targetKcal) <= weeklyOnTargetTolerance * targetKcal {
            trend = .onTarget
        } else {
            trend = average > targetKcal ? .above : .below
        }
        let comparing = trend != .fewDays
        let averageKcal = roundToTen(average)
        let targetInt = Int(targetKcal.rounded())
        return WeeklySummary(
            weekKey: key, daysCounted: counted.count, averageKcal: averageKcal, targetKcal: targetInt,
            differenceKcal: averageKcal - targetInt,
            trend: trend,
            suggestsAdjustingTarget: comparing && adjustHintGoals.contains(goal) && reaches(average, clearlyOverShare, of: targetKcal),
            // 建资料通常在第一次记录之前，所以只有「第一个完整天结束以后」改的才算
            targetChangedRecently: comparing && targetChangedAt >= firstDayEnd)
    }

    // MARK: - 小工具

    /// 热量一律按整千卡比较：AI 估算本来就有误差，也避免 0.85 × 1460 这类小数运算让边界忽上忽下
    static func reaches(_ kcal: Double, _ share: Double, of targetKcal: Double) -> Bool {
        kcal.rounded() >= (share * targetKcal).rounded()
    }

    /// 固定用 ISO 周（周一～周日），不跟随手机地区设置
    private static func isoCalendar(_ calendar: Calendar) -> Calendar {
        var iso = Calendar(identifier: .iso8601)
        iso.timeZone = calendar.timeZone
        return iso
    }

    /// 上一个完整的周：上周一 0 点 ～ 本周一 0 点
    static func previousWeek(containing now: Date, calendar: Calendar) -> DateInterval {
        let iso = isoCalendar(calendar)
        let thisWeek = iso.dateInterval(of: .weekOfYear, for: now)!
        return DateInterval(start: iso.date(byAdding: .day, value: -7, to: thisWeek.start)!, end: thisWeek.start)
    }

    /// 周的编号，如 "2026-W39"
    static func weekKey(for date: Date, calendar: Calendar) -> String {
        let c = isoCalendar(calendar).dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return String(format: "%04d-W%02d", c.yearForWeekOfYear ?? 0, c.weekOfYear ?? 0)
    }

    /// 四舍五入到 10：213 → 210，215 → 220，4 → 0，−44 → −40
    static func roundToTen(_ x: Double) -> Int { Int((x / 10).rounded()) * 10 }

    /// 按天整理；同一天出现两次时用第一条，不会崩溃
    static func byDay(_ history: [DayIntake], calendar: Calendar) -> [Date: DayIntake] {
        Dictionary(history.map { (calendar.startOfDay(for: $0.day), $0) }, uniquingKeysWith: { first, _ in first })
    }
}

// MARK: - 从饮食记录换算（纯函数，可测试；界面那一层见 DayIntake+Log.swift）

extension DayIntake {
    /// 把一条条记录按天汇总：每天的总热量（含加餐）+ 记过哪几顿正餐。
    /// mealRaw 是记录里存的餐次文字："breakfast" / "lunch" / "dinner" / "snack"；加餐和不认识的文字都不算正餐
    nonisolated static func summarize(_ records: [(day: Date, mealRaw: String, kcal: Double)],
                                      calendar: Calendar) -> [DayIntake] {
        Dictionary(grouping: records) { calendar.startOfDay(for: $0.day) }
            .map { day, items in
                DayIntake(day: day,
                          kcal: items.reduce(0) { $0 + $1.kcal },
                          mainMeals: Set(items.compactMap { MealSlot(rawValue: $0.mealRaw) }))
            }
    }
}

// MARK: - 推荐下一餐：这一餐按多少热量推荐，发给后端什么数字

/// 发给后端 /recipes 的四个「每日目标」数字（后端再按 30% / 40% / 30% 拆到每一餐）
nonisolated struct RequestTargets: Equatable {
    var calories: Double
    var proteinG: Double
    var carbsG: Double
    var fatG: Double
}

extension RequestTargets {
    /// 直接用每日目标（食谱页就是这样发的）
    nonisolated init(_ t: DailyTargets) {
        self.init(calories: t.calories, proteinG: t.proteinG, carbsG: t.carbsG, fatG: t.fatG)
    }
}

nonisolated struct NextMealBudget: Identifiable {
    /// 必须和 backend/recipes_ai.py 的 MEAL_SHARES 一致（早 30% / 午 40% / 晚 30%）
    static let mealShares: [MealSlot: Double] = [.breakfast: 0.30, .lunch: 0.40, .dinner: 0.30]
    /// 一餐最少按 320 千卡推荐 = 800 × 40%：后端能接受的最小午餐，也差不多是一顿清淡正餐；再少就成了「省着吃」
    static let minMealKcal = 320.0
    /// 后端 RecipeRequest.daily_calories 的下限（recipes_ai.py:40，ge=800）
    static let backendMinDailyKcal = 800.0

    let meal: MealSlot
    let remainingKcal: Double     // 今天真正剩下的 = 目标 − 已记录
    let targets: DailyTargets     // 每日目标
    var id: String { meal.rawValue }

    var share: Double { Self.mealShares[meal] ?? 0.30 }
    /// 平时这一餐的量 = 每日目标 × 比例（每日目标最低 1200，平时一餐至少 360，所以总在 320 之上）
    var usualMealKcal: Double { targets.calories * share }
    /// 这一餐按多少推荐：剩下的量，但不少于 320，也不多于平时这一餐
    var mealKcal: Double { min(max(remainingKcal, Self.minMealKcal), usualMealKcal) }
    var wasRaisedToFloor: Bool { remainingKcal < Self.minMealKcal }

    /// 发给后端的「假想每日目标」：四个数按同一个倍数缩小，后端拆出来的这一餐正好是 mealKcal。
    /// 倍数不超过 1，所以一定在后端的上限之内；热量直接用算好的数（不再相乘），不会因为小数误差低于 800
    var requestTargets: RequestTargets {
        let daily = max(mealKcal / share, Self.backendMinDailyKcal)
        let k = daily / targets.calories
        return RequestTargets(calories: daily, proteinG: targets.proteinG * k, carbsG: targets.carbsG * k, fatG: targets.fatG * k)
    }

    /// 页面上给用户看的这一餐目标 = 发给后端的数 × 这一餐的比例
    var mealTargets: RequestTargets {
        let r = requestTargets
        return RequestTargets(calories: r.calories * share, proteinG: r.proteinG * share,
                              carbsG: r.carbsG * share, fatG: r.fatG * share)
    }
}

// MARK: - 本地存储（UserDefaults）里用的名字（写法同 RecipePrefKeys）

nonisolated enum HintKeys {
    static let level = "hintLevel"  // HintLevel 的 rawValue，默认 "all"
    static let weeklyDismissedWeek = "hintWeeklyDismissedWeek"  // 如 "2026-W39"
    static let adjustSnoozedUntil = "hintAdjustSnoozedUntil"  // 1970 年起的秒数；0 = 没有
    #if DEBUG
    static let debugNowOverride = "hintDebugNowOverride"  // 1970 年起的秒数；0 = 用真实时间
    #endif
}
