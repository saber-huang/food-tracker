//
//  FoodEntry.swift
//  FoodTracker
//
//  一条饮食记录 = 一种食物，存在手机本地（SwiftData）。
//  拍照识别出 3 种食物就是 3 条记录；同一天同一餐的记录（dayKey + mealRaw 相同）显示在一起。
//
//  ⚠️ 以后改这个类只能「加」，不能「改」，否则手机上已有的数据会读不出来：
//  - 新属性只用 String / Int / Double / Bool / Date 这类简单类型，并且要有默认值，或者是可选的（类型后面带 ?）
//  - 选项（枚举）照 mealRaw 的样子存英文文字；不要直接存枚举或自己定义的结构体：
//    旧记录读这个新属性会闪退（枚举），或者整个数据库打不开（结构体）
//  - 想改属性名，要用 @Attribute(originalName: "旧名字")
//  - 不要改已有属性的类型
//
//  「哪一天」一律用 dayKey 这个数字传来传去，只在显示时才换成日期（见 DayMath.date(fromDayKey:)）：
//  先换成日期、过一会儿再换回数字的话，中途手机换了时区，记录就会跑到前一天或后一天
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

    /// dayKey：记到哪一天，20260929 这样的数字。要记到「今天」就写 DayMath.dayKey(for: .now)
    init(
        dayKey: Int, meal: MealType, name: String, weightG: Double?, values: NutrientValues, source: EntrySource,
        createdAt: Date = .now
    ) {
        self.dayKey = dayKey
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

    // ⚠️ 下面的 meal、source、values 是「算出来的属性」，数据库里没有这几列，只能在查出来以后用。
    //    #Predicate 和排序里要写存下来的 mealRaw、sourceRaw、caloriesKcal 等：写 $0.meal 能编译，但运行时会闪退
    var meal: MealType {
        get { MealType(rawValue: mealRaw) ?? .snack }
        set { mealRaw = newValue.rawValue }
    }

    var source: EntrySource { EntrySource(rawValue: sourceRaw) ?? .manual }

    var values: NutrientValues {
        NutrientValues(caloriesKcal: caloriesKcal, proteinG: proteinG, carbsG: carbsG, fatG: fatG)
    }

    /// 修改后保存：把表单里的内容写回这条记录（日期也是数字，直接写回，不经过时区换算）
    func apply(_ item: EditableItem) {
        name = item.name
        weightG = item.weightG
        caloriesKcal = item.values.caloriesKcal
        proteinG = item.values.proteinG
        carbsG = item.values.carbsG
        fatG = item.values.fatG
        meal = item.meal
        if item.dayKey != dayKey { dayKey = item.dayKey }
    }

    /// 把一餐里的几项食物一起存进数据库（识别结果页的「保存到今日」、调试菜单的示例记录都用它）。
    /// 每一项自己记的餐次和日期在这里用不上：整餐记到同一餐、同一天，由调用的地方决定。
    /// 同一次保存的几条记录 createdAt 相差 1 毫秒，保证显示顺序和保存前的列表一样。
    /// 这里不调用 save()，什么时候真正写进数据库由调用的地方决定
    @discardableResult
    static func insert(
        _ items: [EditableItem], meal: MealType, dayKey: Int, source: EntrySource, into context: ModelContext,
        now: Date = .now
    ) -> [FoodEntry] {
        items.enumerated().map { index, item in
            let entry = FoodEntry(
                dayKey: dayKey, meal: meal, name: item.name, weightG: item.weightG,
                values: DietLogMath.rounded(item.values), source: source,
                createdAt: now.addingTimeInterval(Double(index) * 0.001))
            context.insert(entry)
            return entry
        }
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
    init(entry: FoodEntry) {
        self.init(
            id: UUID(),
            name: entry.name,
            weightG: entry.weightG,
            values: entry.values,
            confidence: nil,
            meal: entry.meal,
            dayKey: entry.dayKey
        )
    }
}
