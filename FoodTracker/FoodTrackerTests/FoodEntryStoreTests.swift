//
//  FoodEntryStoreTests.swift
//  FoodTrackerTests
//
//  饮食记录存进数据库、按日期查出来、修改、删除的测试。
//  每个测试都新建一个「只在内存里」的数据库，跑完就没了，不会碰到模拟器里真实的记录。
//  这里执行的是 SwiftData 真正的查询，所以查询条件写错（比如用了算出来的属性）会在这里失败，而不是在 App 里闪退。
//

import Foundation
import SwiftData
import Testing

@testable import FoodTracker

// FoodEntry 只能在主线程使用，所以整组测试标上 @MainActor
@MainActor
@Suite("饮食记录存储")
struct FoodEntryStoreTests {
    let container: ModelContainer
    let context: ModelContext
    let shanghai = DayMath.makeCalendar(timeZone: TimeZone(identifier: "Asia/Shanghai")!)
    let losAngeles = DayMath.makeCalendar(timeZone: TimeZone(identifier: "America/Los_Angeles")!)

    init() throws {
        // isStoredInMemoryOnly 必须是 true：测试是在 App 里面跑的，否则会写进模拟器的真实数据库
        container = try ModelContainer(
            for: UserProfile.self, FoodEntry.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        context = container.mainContext
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 0, _ cal: Calendar) -> Date {
        cal.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    /// 插入一条记录（热量 100，午餐）
    @discardableResult
    private func insert(
        _ name: String, on day: Date, _ cal: Calendar, meal: MealType = .lunch, createdAt: Date = .now
    ) -> FoodEntry {
        let entry = FoodEntry(
            dayKey: DayMath.dayKey(for: day, calendar: cal), meal: meal, name: name, weightG: 100,
            values: NutrientValues(caloriesKcal: 100), source: .manual, createdAt: createdAt)
        context.insert(entry)
        return entry
    }

    private func names(on day: Date, _ cal: Calendar) throws -> [String] {
        let descriptor = FetchDescriptor(
            predicate: FoodEntry.predicate(day: day, calendar: cal), sortBy: [SortDescriptor(\FoodEntry.createdAt)])
        return try context.fetch(descriptor).map(\.name)
    }

    @Test("按日期查询，同一天按添加的先后排")
    func queryByDay() throws {
        let base = Date(timeIntervalSince1970: 1_790_000_000)
        insert("午饭", on: date(2026, 9, 29, hour: 12, shanghai), shanghai, createdAt: base)
        insert("前一天", on: date(2026, 9, 28, hour: 20, shanghai), shanghai, createdAt: base)
        insert("早饭", on: date(2026, 9, 29, hour: 8, shanghai), shanghai, createdAt: base.addingTimeInterval(-60))
        try context.save()

        #expect(try names(on: date(2026, 9, 29, shanghai), shanghai) == ["早饭", "午饭"])
        #expect(try names(on: date(2026, 9, 28, shanghai), shanghai) == ["前一天"])
        #expect(try names(on: date(2026, 9, 30, shanghai), shanghai).isEmpty)
    }

    @Test("按日期范围查询：包括开始那天，不包括结束那天")
    func queryRange() throws {
        insert("27日", on: date(2026, 9, 27, shanghai), shanghai)
        insert("28日", on: date(2026, 9, 28, shanghai), shanghai)
        insert("10月5日", on: date(2026, 10, 5, shanghai), shanghai)
        try context.save()
        let descriptor = FetchDescriptor(
            predicate: FoodEntry.predicate(from: date(2026, 9, 28, shanghai), to: date(2026, 10, 5, shanghai), calendar: shanghai))
        #expect(try context.fetch(descriptor).map(\.name) == ["28日"])
    }

    @Test("改到另一天、删除")
    func moveAndDelete() throws {
        let entry = insert("午饭", on: date(2026, 9, 29, shanghai), shanghai)
        insert("另一条", on: date(2026, 9, 29, shanghai), shanghai)
        try context.save()

        // 改到 28 日
        var item = EditableItem(entry: entry)
        item.dayKey = 20260928
        entry.apply(item)
        try context.save()
        #expect(try names(on: date(2026, 9, 29, shanghai), shanghai) == ["另一条"])
        #expect(try names(on: date(2026, 9, 28, shanghai), shanghai) == ["午饭"])

        // 删除
        let before = try context.fetchCount(FetchDescriptor<FoodEntry>())
        context.delete(entry)
        try context.save()
        #expect(try context.fetchCount(FetchDescriptor<FoodEntry>()) == before - 1)
    }

    @Test("餐次和来源存成英文，读不懂的餐次当作加餐")
    func storedNames() {
        let entry = insert("酸奶", on: date(2026, 9, 29, shanghai), shanghai, meal: .breakfast)
        #expect(entry.mealRaw == "breakfast")
        entry.meal = .snack
        #expect(entry.mealRaw == "snack")
        entry.mealRaw = "brunch"
        #expect(entry.meal == .snack)
        #expect(entry.source == .manual)
        entry.sourceRaw = "recipe"
        #expect(entry.source == .recipe)
    }

    // 在上海 9 月 29 日记的一餐，回到洛杉矶以后还是 9 月 29 日（不会跑到 28 日）
    @Test("换了时区，记录还在原来那天")
    func timeZoneTravel() throws {
        let entry = insert("上海的午饭", on: date(2026, 9, 29, hour: 12, shanghai), shanghai)
        try context.save()
        #expect(entry.dayKey == 20260929)
        #expect(try names(on: date(2026, 9, 29, losAngeles), losAngeles) == ["上海的午饭"])
        #expect(try names(on: date(2026, 9, 28, losAngeles), losAngeles).isEmpty)
        #expect(entry.day(calendar: losAngeles) == date(2026, 9, 29, losAngeles))
    }

    @Test("只改数字时日期不变；改了日期才换到别的一天")
    func applyKeepsDay() throws {
        let entry = insert("上海的午饭", on: date(2026, 9, 29, hour: 12, shanghai), shanghai)
        try context.save()

        // 打开这条记录，只改热量：日期跟着记录里的数字走，不经过时区换算
        var item = EditableItem(entry: entry)
        item.values.caloriesKcal = 200
        entry.apply(item)
        #expect(entry.dayKey == 20260929)
        #expect(entry.caloriesKcal == 200)

        // 把日期改成 27 日
        item.dayKey = 20260927
        entry.apply(item)
        #expect(entry.dayKey == 20260927)
    }

    // 在上海打开「修改记录」，飞到洛杉矶以后才改热量、保存：还是 9 月 29 日。
    // 以前表单里存的是「上海 29 日 0 点」这个时刻，到洛杉矶再换回日期就成了 28 日
    @Test("打开表单后手机换了时区再保存，记录还在原来那天")
    func editAcrossTimeZoneChange() throws {
        let entry = insert("上海的午饭", on: date(2026, 9, 29, hour: 12, shanghai), shanghai)
        try context.save()
        let draft = EntryDraft(item: EditableItem(entry: entry))  // 在上海打开
        draft.caloriesText = "450"  // 落地以后才改
        draft.textsChanged()
        entry.apply(try #require(draft.output))
        try context.save()
        #expect(entry.dayKey == 20260929)
        #expect(entry.caloriesKcal == 450)
        #expect(try names(on: date(2026, 9, 29, losAngeles), losAngeles) == ["上海的午饭"])
        #expect(try names(on: date(2026, 9, 28, losAngeles), losAngeles).isEmpty)
    }

    // 结果页点「保存到今日」：两项一起存，顺序和列表一样，都记到选好的那一餐、那一天
    @Test("保存识别结果：几项一起存，顺序不变")
    func insertMeal() throws {
        var items = SampleData.analyzeResult.items.map { EditableItem($0, meal: .snack, dayKey: 20260901) }
        items[0].values.proteinG = 3.94  // 用户改过的数字，存之前要取整
        let day = date(2026, 9, 29, shanghai)
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let saved = FoodEntry.insert(items, meal: .dinner, dayKey: 20260929, source: .photo, into: context, now: now)
        try context.save()

        #expect(saved.count == 2)
        // 每一项自己记的餐次（加餐）和日期（9 月 1 日）不算：以整餐选的为准
        #expect(saved.allSatisfy { $0.meal == .dinner && $0.dayKey == 20260929 && $0.source == .photo })
        #expect(saved[0].createdAt == now)
        #expect(saved[1].createdAt == now.addingTimeInterval(0.001))
        #expect(saved[0].proteinG == 3.9)
        #expect(saved[1].caloriesKcal == 398)
        #expect(try names(on: day, shanghai) == ["米饭", "宫保鸡丁"])
    }

    @Test("修改表单里显示的内容和记录一致")
    func editableItemFromEntry() {
        let entry = FoodEntry(
            dayKey: 20260929, meal: .dinner, name: "米饭", weightG: nil,
            values: NutrientValues(caloriesKcal: 174, proteinG: 3.9, carbsG: 38.1, fatG: 0.5), source: .photo)
        let item = EditableItem(entry: entry)
        #expect(item.name == "米饭")
        #expect(item.weightG == nil)
        #expect(item.values == entry.values)
        #expect(item.confidence == nil)
        #expect(item.meal == .dinner)
        #expect(item.dayKey == 20260929)
    }
}
