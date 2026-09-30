//
//  DayIntake+Log.swift
//  FoodTracker
//
//  把饮食记录（FoodEntry）换算成提示需要的「每天一行」（DayIntake）。
//  这是提示功能和饮食记录功能唯一的连接点：记录那边改了名字，只改这个文件。
//

import Foundation
import SwiftData

extension FoodEntry {
    /// 提示要用到的记录：判断只看最近 14 天，但查询范围前后都留够「假装现在是」能调到的 30 天，
    /// 这样模拟器里把时间调到别的日子，提示和记录用的还是同一份数据。查询条件的日期在 #Predicate 外面先算好
    static func hintHistoryPredicate(realToday: Date, calendar: Calendar = DayMath.calendar) -> Predicate<FoodEntry> {
        predicate(
            from: DayMath.addingDays(-HintClock.lookbackDays, to: realToday, calendar: calendar),
            to: DayMath.addingDays(HintClock.fakeRangeDays + 1, to: realToday, calendar: calendar), calendar: calendar)
    }
}

extension DayIntake {
    /// 把饮食记录换算成提示需要的「每天一行」（加餐只算热量，不算正餐）
    static func history(from entries: [FoodEntry], calendar: Calendar = DayMath.calendar) -> [DayIntake] {
        summarize(
            entries.map { (day: $0.day(calendar: calendar), mealRaw: $0.mealRaw, kcal: $0.caloriesKcal) }, calendar: calendar)
    }
}
