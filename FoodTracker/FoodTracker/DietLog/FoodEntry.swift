//
//  FoodEntry.swift
//  FoodTracker
//
//  一条饮食记录 = 一种食物，存在手机本地（SwiftData）。
//  拍照识别出 3 种食物就是 3 条记录；同一天同一餐的记录（dayKey + mealRaw 相同）显示在一起。
//
//  ⚠️ 以后改这个类只能「加」，不能「改」，否则手机上已有的数据会读不出来：
//  - 新属性要有默认值，或者是可选的（类型后面带 ?）
//  - 想改属性名，要用 @Attribute(originalName: "旧名字")
//  - 不要改已有属性的类型
//

import Foundation
import SwiftData

@Model
final class FoodEntry {
    /// 记在哪一天：20260929 这样的数字（见 DayMath.dayKey）。
    /// 按年月日存，手机换了时区，记录也还在原来那天
    var dayKey: Int
    var mealRaw: String  // MealType 的英文名，存文字最稳妥（和 UserProfile.sexRaw 一样）
    var name: String
    var weightG: Double?  // nil = 不知道重量
    var caloriesKcal: Double  // 存进来之前已经取整
    var proteinG: Double  // 存进来之前已经保留 1 位小数
    var carbsG: Double
    var fatG: Double
    var sourceRaw: String  // EntrySource 的英文名：photo / manual / recipe
    var createdAt: Date  // 同一餐里按添加的先后排

    init(
        day: Date, meal: MealType, name: String, weightG: Double?, values: NutrientValues, source: EntrySource,
        createdAt: Date = .now, calendar: Calendar = DayMath.calendar
    ) {
        self.dayKey = DayMath.dayKey(for: day, calendar: calendar)
        self.mealRaw = meal.rawValue
        self.name = name
        self.weightG = weightG
        self.caloriesKcal = values.caloriesKcal
        self.proteinG = values.proteinG
        self.carbsG = values.carbsG
        self.fatG = values.fatG
        self.sourceRaw = source.rawValue
        self.createdAt = createdAt
    }

    /// 记在哪一天（那天的 0 点，按手机当前的时区）。
    /// 故意写成「方法」而不是「属性」：查询条件里用了算出来的属性，能编译但运行时会闪退；
    /// 写成方法的话，误用时编译器会直接报错
    func day(calendar: Calendar = DayMath.calendar) -> Date {
        DayMath.date(fromDayKey: dayKey, calendar: calendar)
    }

    var meal: MealType {
        get { MealType(rawValue: mealRaw) ?? .snack }
        set { mealRaw = newValue.rawValue }
    }

    var source: EntrySource { EntrySource(rawValue: sourceRaw) ?? .manual }

    var values: NutrientValues {
        NutrientValues(caloriesKcal: caloriesKcal, proteinG: proteinG, carbsG: carbsG, fatG: fatG)
    }

    /// 修改后保存：把表单里的内容写回这条记录
    func apply(_ item: EditableItem, calendar: Calendar = DayMath.calendar) {
        name = item.name
        weightG = item.weightG
        caloriesKcal = item.values.caloriesKcal
        proteinG = item.values.proteinG
        carbsG = item.values.carbsG
        fatG = item.values.fatG
        meal = item.meal
        // 日期真的改了才改：表单里的日期是按这条记录的 dayKey 算出来的，没动过的话算回去还是同一个数
        let newKey = DayMath.dayKey(for: item.day, calendar: calendar)
        if newKey != dayKey { dayKey = newKey }
    }

    // MARK: - 查询条件
    // 所有按日期查记录的地方都用这两个函数。数字在 #Predicate 外面先算好：查询条件里不能调用日历

    /// 某一天的记录
    static func predicate(day: Date, calendar: Calendar = DayMath.calendar) -> Predicate<FoodEntry> {
        let key = DayMath.dayKey(for: day, calendar: calendar)
        return #Predicate<FoodEntry> { $0.dayKey == key }
    }

    /// 从 start 那天到 end 那天之前的记录（包括 start，不包括 end）
    static func predicate(from start: Date, to end: Date, calendar: Calendar = DayMath.calendar) -> Predicate<FoodEntry> {
        let first = DayMath.dayKey(for: start, calendar: calendar)
        let last = DayMath.dayKey(for: end, calendar: calendar)
        return #Predicate<FoodEntry> { $0.dayKey >= first && $0.dayKey < last }
    }
}

extension EditableItem {
    /// 已保存的记录 → 编辑表单用的一项（要读 @Model，所以写在这里）
    init(entry: FoodEntry, calendar: Calendar = DayMath.calendar) {
        self.init(
            id: UUID(),
            name: entry.name,
            weightG: entry.weightG,
            values: entry.values,
            confidence: nil,
            meal: entry.meal,
            day: entry.day(calendar: calendar)
        )
    }
}
