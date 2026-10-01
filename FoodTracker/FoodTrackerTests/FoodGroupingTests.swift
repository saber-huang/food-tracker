//
//  FoodGroupingTests.swift
//  FoodTrackerTests
//
//  第五轮新加的几处逻辑：
//  - 同一种食物怎么判断（名字规范化、份量和热量差不多才算），「今日」里怎么合并显示
//  - 手动添加的「最近使用」：去重、按输入筛选，点了以后怎么预填
//  - 离开输入框时数字的整理，记好以后轻提示的文字
//

import Foundation
import Testing

@testable import FoodTracker

@Suite("同一种食物：合并显示和最近使用")
struct FoodGroupingTests {
    private func item(_ name: String, _ weight: Double?, _ kcal: Double) -> GroupingItem {
        GroupingItem(name: name, weightG: weight, caloriesKcal: kcal)
    }

    @Test("名字规范化：空格、标点、全角半角、英文大小写都不影响")
    func normalizeNames() {
        #expect(FoodNameKey.normalize("米饭 ") == FoodNameKey.normalize("米饭"))
        #expect(FoodNameKey.normalize("Rice") == FoodNameKey.normalize("rice"))
        #expect(FoodNameKey.normalize("ＲＩＣＥ") == FoodNameKey.normalize("rice"))
        #expect(FoodNameKey.normalize("番茄炒蛋（少油）") == FoodNameKey.normalize("番茄炒蛋(少油)"))
        #expect(FoodNameKey.normalize("米饭") != FoodNameKey.normalize("炒饭"))
    }

    @Test("名字一样、份量和热量差不多才算同一种；一小碗和一大碗不合并")
    func sameFood() {
        #expect(FoodGrouping.isSameFood(item("米饭", 150, 174), item("米饭", 150, 174)))
        #expect(FoodGrouping.isSameFood(item("米饭", 150, 174), item("米饭 ", 155, 180)))  // 差不到 10%
        #expect(!FoodGrouping.isSameFood(item("米饭", 150, 174), item("米饭", 300, 348)))  // 份量差一倍
        #expect(!FoodGrouping.isSameFood(item("米饭", 150, 174), item("米饭", 150, 230)))  // 热量差太多
        #expect(FoodGrouping.isSameFood(item("苹果", nil, 95), item("苹果", nil, 95)))  // 都没填份量
        #expect(!FoodGrouping.isSameFood(item("苹果", nil, 95), item("苹果", 180, 95)))  // 只有一条填了份量
        #expect(!FoodGrouping.isSameFood(item("米饭", 150, 174), item("宫保鸡丁", 150, 174)))
    }

    @Test("分组：按第一次出现的先后，组里也按先后；不同量的同名食物单独一组")
    func groups() {
        let items = [
            item("米饭", 150, 174), item("宫保鸡丁", 200, 398), item("米饭", 150, 174), item("宫保鸡丁", 200, 398),
            item("米饭", 300, 348),
        ]
        #expect(FoodGrouping.groups(items) == [[0, 2], [1, 3], [4]])
        #expect(FoodGrouping.groups([]) == [])
    }

    @Test("最近使用：同一种只留最近的一次，按从新到旧排")
    func recentFoods() {
        let records = [
            RecentFood(name: "米饭", weightG: 200, values: NutrientValues(caloriesKcal: 232)),
            RecentFood(name: "鸡蛋", weightG: 50, values: NutrientValues(caloriesKcal: 72)),
            RecentFood(name: "米饭 ", weightG: 150, values: NutrientValues(caloriesKcal: 174)),  // 更早的一次，丢掉
            RecentFood(name: "  ", weightG: nil, values: NutrientValues(caloriesKcal: 10)),  // 没有名字，丢掉
        ]
        let foods = RecentFoods.from(records)
        #expect(foods.map(\.name) == ["米饭", "鸡蛋"])
        #expect(foods.first?.weightG == 200)
        #expect(RecentFoods.from(records, limit: 1).count == 1)
    }

    @Test("最近使用按输入筛选：一模一样的最前，开头一样的其次；什么都没打就是最近的几种")
    func matching() {
        let foods = ["牛奶", "米饭", "炒米饭", "米粉", "鸡蛋"].map {
            RecentFood(name: $0, weightG: nil, values: NutrientValues(caloriesKcal: 100))
        }
        #expect(RecentFoods.matching(foods, query: "").map(\.name) == ["牛奶", "米饭", "炒米饭", "米粉", "鸡蛋"])
        #expect(RecentFoods.matching(foods, query: "", limit: 2).count == 2)
        #expect(RecentFoods.matching(foods, query: "米饭").map(\.name) == ["米饭", "炒米饭"])
        #expect(RecentFoods.matching(foods, query: "米").map(\.name) == ["米饭", "米粉", "炒米饭"])
        #expect(RecentFoods.matching(foods, query: "面条").isEmpty)
    }
}

@MainActor
@Suite("手动添加提速")
struct ManualEntrySpeedTests {
    private let rice = RecentFood(
        name: "米饭", weightG: 150, values: NutrientValues(caloriesKcal: 174, proteinG: 3.9, carbsG: 38.1, fatG: 0.5))

    @Test("点了最近使用：填上名字和上次的份量、营养；之后改份量会按比例换算")
    func prefill() {
        let draft = EntryDraft(meal: .lunch, dayKey: 20261001)
        draft.prefill(from: rice)
        #expect(draft.name == "米饭")
        #expect(draft.weightText == "150")
        #expect(draft.caloriesText == "174")
        #expect(draft.proteinText == "3.9")
        #expect(draft.output != nil)  // 直接就能保存
        // 吃了两碗：份量改成 300，热量和营养素一起翻倍
        draft.weightText = "300"
        draft.textsChanged()
        #expect(draft.caloriesText == "348")
        #expect(draft.carbsText == "76.2")
    }

    @Test("已经填了的框不被覆盖；上次只填了热量时，营养素的框继续空着")
    func prefillKeepsTypedValues() {
        let draft = EntryDraft(meal: .lunch, dayKey: 20261001)
        draft.caloriesText = "200"
        draft.textsChanged()
        draft.prefill(from: rice)
        #expect(draft.caloriesText == "200")
        #expect(draft.weightText == "150")

        let apple = RecentFood(name: "苹果", weightG: nil, values: NutrientValues(caloriesKcal: 95))
        let other = EntryDraft(meal: .snack, dayKey: 20261001)
        other.prefill(from: apple)
        #expect(other.caloriesText == "95")
        #expect(other.proteinText.isEmpty && other.carbsText.isEmpty && other.fatText.isEmpty)
    }

    @Test("缺了必填项时的提示：一句话说清楚缺什么")
    func missingMessages() {
        #expect(EntryValidator.nameError("  ") == "请输入食物名称")
        #expect(EntryValidator.caloriesError(text: "") == "请输入热量")
    }

    @Test("离开输入框时整理数字的写法；不用改或不是数字时保持原样")
    func tidyNumbers() {
        #expect(NumberText.normalized("0450") == "450")
        #expect(NumberText.normalized("12.50") == "12.5")
        #expect(NumberText.normalized("1,5") == "1.5")
        #expect(NumberText.normalized("45.") == "45")
        #expect(NumberText.normalized(" 60 ") == "60")
        #expect(NumberText.normalized("60") == nil)
        #expect(NumberText.normalized("") == nil)
        #expect(NumberText.normalized("abc") == nil)
    }

    @Test("记好以后的轻提示：今天写餐次，往日写上是哪天")
    func loggedMessage() {
        let today = DayMath.date(fromDayKey: 20261001)
        #expect(DayMath.loggedMessage(meal: .lunch, dayKey: 20261001, today: today, language: .zh) == "已记录到午餐")
        #expect(DayMath.loggedMessage(meal: .lunch, dayKey: 20260928, today: today, language: .zh) == "已记录到 9月28日 午餐")
    }
}
