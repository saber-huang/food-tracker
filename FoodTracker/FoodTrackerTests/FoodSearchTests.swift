//
//  FoodSearchTests.swift
//  FoodTrackerTests
//
//  第七轮：食物库、搜索、自然份量的测试。
//  - 内置食物库能读出来，每种食物的单位合理（米饭有「碗」，鸡蛋按「个」、没有「碗」，牛奶按毫升、有「杯」）
//  - 同一种食物的不同叫法（西红柿 / 番茄、地瓜 / 红薯）能搜到同一种
//  - 搜索排序：名字完全一样 > 我的食物 > 最近吃过 > 食物库 > 别名、相近的字；同一种只出现一次
//  - 「1.5 碗」→ 225 克 → 营养；直接填 137 克；估算的数字取整
//  - AI 估算的结果、我的食物、最近吃过怎么变成可以选份量的食物；「常吃」怎么算
//

import Foundation
import Testing

@testable import FoodTracker

// MARK: - 食物库

@Suite("内置食物库")
struct FoodCatalogTests {
    let catalog = FoodCatalog.shared

    @Test("能读出来：121 种，每种都有来源、营养和至少一个份量单位")
    func loads() throws {
        #expect(catalog.foods.count == 121)
        #expect(Set(catalog.foods.map(\.id)).count == catalog.foods.count)  // id 不重复
        for food in catalog.foods {
            #expect(["usda", "cn", "estimate"].contains(food.source), "\(food.id) 的来源")
            #expect(!food.sourceRef.isEmpty, "\(food.id) 没写出处")
            #expect(food.per100.kcal >= 0 && food.per100.kcal <= 900, "\(food.id) 的热量")
            #expect(food.per100.protein + food.per100.carbs + food.per100.fat <= 100, "\(food.id) 的营养素")
            #expect(!food.units.isEmpty, "\(food.id) 没有份量单位")
            for unit in food.units {
                #expect(unit.amount > 0 && [0.5, 1].contains(unit.step), "\(food.id) 的 \(unit.id)")
            }
            #expect(food.defaultQuantity > 0)
        }
    }

    @Test("CASE 1：米饭按碗，1 碗约 150 克")
    func rice() throws {
        let rice = try #require(catalog.food(id: "rice"))
        #expect(rice.name == "米饭")
        #expect(rice.baseUnit == .gram)
        let bowl = try #require(rice.units.first)
        #expect(bowl.id == "bowl" && bowl.amount == 150 && bowl.step == 0.5)
        #expect(bowl.displayName(quantity: 1) == "碗")
    }

    @Test("CASE 3：鸡蛋按个（1 个约 50 克），不能选碗")
    func egg() throws {
        let egg = try #require(catalog.food(id: "egg"))
        #expect(egg.units.map(\.id) == ["piece"])
        #expect(egg.units[0].amount == 50 && egg.units[0].step == 1)
        #expect(!egg.units.contains { $0.id == "bowl" })
    }

    @Test("CASE 4：牛奶按毫升，有「杯」（约 250 毫升）")
    func milk() throws {
        let milk = try #require(catalog.food(id: "milk"))
        #expect(milk.baseUnit == .milliliter)
        let cup = try #require(milk.units.first { $0.id == "cup" })
        #expect(cup.amount == 250)
        #expect(cup.displayName(quantity: 1) == "杯")
    }

    @Test("每个名字和别名只指向一种食物")
    func uniqueNames() {
        var owner: [String: String] = [:]
        for food in catalog.foods {
            for name in food.allNames {
                let key = catalog.normalizer.key(name)
                guard !key.isEmpty else { continue }
                if let other = owner[key], other != food.id {
                    Issue.record("「\(name)」同时是 \(other) 和 \(food.id) 的名字")
                }
                owner[key] = food.id
            }
        }
    }

    @Test("来源标记：catalog:rice、custom:<UUID> 能认回来")
    func refs() throws {
        #expect(catalog.food(ref: "catalog:rice")?.id == "rice")
        #expect(catalog.food(ref: "catalog:不存在") == nil)
        #expect(catalog.food(ref: nil) == nil)
        let id = UUID()
        #expect(FoodRef.customID(FoodRef.custom(id)) == id)
        #expect(FoodRef.customID("catalog:rice") == nil)
        #expect(FoodRef.catalogID("catalog:rice") == "rice")
    }
}

// MARK: - 叫法不同

@Suite("同一种食物的不同叫法")
struct FoodSynonymTests {
    let catalog = FoodCatalog.shared

    @Test("西红柿炒鸡蛋 / 番茄炒鸡蛋 / 番茄炒蛋 / 西红柿炒蛋 → 番茄炒蛋")
    func tomatoEgg() {
        for name in ["西红柿炒鸡蛋", "番茄炒鸡蛋", "番茄炒蛋", "西红柿炒蛋"] {
            #expect(catalog.exactMatch(name)?.id == "tomato_egg", "\(name)")
        }
    }

    @Test("白米饭 → 米饭，地瓜 → 红薯，马铃薯 → 土豆，英文名也行")
    func aliases() {
        #expect(catalog.exactMatch("白米饭")?.id == "rice")
        #expect(catalog.exactMatch("Rice")?.id == "rice")
        #expect(catalog.exactMatch("地瓜")?.id == "sweet_potato")
        #expect(catalog.exactMatch("番薯")?.id == "sweet_potato")
        #expect(catalog.exactMatch("马铃薯")?.id == "potato")
        #expect(catalog.exactMatch("煮马铃薯")?.id == "potato")  // 别名「煮土豆」换个叫法
        #expect(catalog.exactMatch(" 米饭 ")?.id == "rice")  // 多余的空格不影响
    }

    @Test("规范化：同义词换成同一个写法，长的词先换")
    func normalizer() {
        let n = FoodNameNormalizer(synonyms: [["番茄", "西红柿"], ["土豆", "马铃薯", "洋芋"]])
        #expect(n.key("西红柿炒蛋") == n.key("番茄炒蛋"))
        #expect(n.key("马铃薯丝") == n.key("土豆丝"))
        #expect(n.key("番茄") != n.key("土豆"))
        #expect(n.key("") == "")
    }
}

// MARK: - 搜索

@Suite("搜索和排序")
struct FoodSearchRankingTests {
    let catalog = FoodCatalog.shared

    private func search(
        _ query: String, custom: [CustomFoodSnapshot] = [], recents: [RecentFood] = []
    ) -> [FoodSearchResult] {
        FoodSearch.results(query: query, catalog: catalog, custom: custom, recents: recents)
    }

    private func myFood(_ name: String, kcal: Double = 350, amount: Double? = 200, ai: Bool = false) -> CustomFoodSnapshot {
        CustomFoodSnapshot(
            id: UUID(), name: name, amountUnit: .gram, servingName: "", servingAmount: amount,
            servingValues: NutrientValues(caloriesKcal: kcal, proteinG: 20, carbsG: 10, fatG: 25), source: ai ? .ai : .user,
            foodType: ai ? .dish : nil)
    }

    @Test("rice / 米饭 / 白米饭：米饭排第一，而且是完全匹配（不显示 AI 估算）")
    func riceFirst() {
        for query in ["rice", "米饭", "白米饭"] {
            let results = search(query)
            #expect(results.first?.choice.foodRef == "catalog:rice", "\(query)")
            #expect(FoodSearch.hasExactMatch(results), "\(query)")
        }
    }

    @Test("CASE 5：山西过油肉搜不到（页面这时给 AI 估算和创建自定义食物）")
    func notFound() {
        let results = search("山西过油肉")
        #expect(results.isEmpty)
        #expect(!FoodSearch.hasExactMatch(results))
        #expect(search("").isEmpty)
        #expect(search("   ").isEmpty)
    }

    @Test("相近的字不乱配：rice 不会配到橙汁（别名 juice），shanxi pork 不会配到鱼香肉丝（yuxiang pork）")
    func fuzzyNotTooLoose() {
        #expect(!search("rice").contains { $0.choice.foodRef == "catalog:orange_juice" })
        let pork = search("shanxi pork")
        #expect(!pork.contains { $0.choice.foodRef == "catalog:yuxiang_pork" })
        // 「pork」（瘦猪肉的别名）整个在打的字里面：算「在里面」，排在后面，页面照样给 AI 估算
        #expect(pork.first { $0.choice.foodRef == "catalog:pork_lean" }?.match == .inside)
        #expect(!FoodSearch.hasExactMatch(pork))
        #expect(FoodMatch.of(query: "rice", key: "juice") == nil)
        #expect(FoodMatch.of(query: "ri", key: "rice") == .prefix)  // 开头一样照样算
        #expect(FoodMatch.of(query: "ab", key: "abx") == .prefix)
        #expect(FoodMatch.of(query: "西兰花炒虾仁", key: "西兰花") == .inside)
        #expect(FoodMatch.of(query: "鸭蛋", key: "蛋") == nil)  // 一个字的名字不算「在里面」
    }

    @Test("匹配程度：完全一样 > 开头一样 > 包含 > 在里面 > 相近")
    func matchOrder() {
        #expect(FoodMatch.of(query: "米饭", key: "米饭") == .exact)
        #expect(FoodMatch.of(query: "米", key: "米饭") == .prefix)
        #expect(FoodMatch.of(query: "饭", key: "米饭") == .contains)
        let order: [FoodMatch] = [.exact, .prefix, .contains, .inside, .similar]
        #expect(order == order.sorted(by: >))
    }

    @Test("CASE 6：保存到我的食物以后，再搜排第一；和食物库同名时我的食物在前")
    func myFoodFirst() {
        let mine = myFood("山西过油肉", ai: true)
        let results = search("山西过油肉", custom: [mine])
        #expect(results.count == 1)
        #expect(results.first?.choice.isMine == true)
        #expect(results.first?.choice.isEstimate == true)  // AI 估算保存的：仍然标「AI 估算」
        #expect(FoodSearch.hasExactMatch(results))

        let myRice = myFood("米饭", kcal: 200)
        let riceResults = search("米饭", custom: [myRice])
        #expect(riceResults.first?.choice.isMine == true)
        #expect(riceResults.dropFirst().first?.choice.foodRef == "catalog:rice")
    }

    @Test("我的食物「开头一样」也排在食物库前面")
    func myFoodPrefix() {
        let results = search("米", custom: [myFood("米其林汉堡")])
        let mineIndex = results.firstIndex { $0.choice.isMine }
        let riceIndex = results.firstIndex { $0.choice.foodRef == "catalog:rice" }
        #expect(mineIndex != nil && riceIndex != nil && mineIndex! < riceIndex!)
    }

    @Test("最近吃过的食物库食物：只出现一次，带「最近吃过」，用上次的份量")
    func recentMerged() throws {
        let recent = RecentFood(
            name: "米饭", weightG: 225, values: NutrientValues(caloriesKcal: 261, proteinG: 5.9, carbsG: 57.2, fatG: 0.8),
            servingQuantity: 1.5, servingUnitID: "bowl", foodRef: "catalog:rice", loggedAt: .now)
        let results = search("米饭", recents: [recent])
        let rice = results.filter { $0.choice.foodRef == "catalog:rice" }
        #expect(rice.count == 1)  // 去重
        let first = try #require(results.first)
        #expect(first.isRecent)
        #expect(first.choice.initialSelection == .natural(unitID: "bowl", quantity: 1.5))
        #expect(Set(results.map(\.id)).count == results.count)
    }

    @Test("以前随手记的（不在食物库里）也能搜到，按上次的量")
    func standaloneRecent() throws {
        let recent = RecentFood(name: "妈妈的饺子", weightG: 300, values: NutrientValues(caloriesKcal: 600), loggedAt: .now)
        let results = search("饺子", recents: [recent])
        let mine = try #require(results.first { $0.choice.name == "妈妈的饺子" })
        #expect(mine.isRecent)
        #expect(mine.choice.foodRef == nil)
    }

    @Test("包含打的字的食物库食物里，最近吃过的排前面")
    func recentBeforeCatalog() {
        // 「鸡」能搜到很多；最近吃过宫保鸡丁，它排在其他同样是「包含」的前面
        let recent = RecentFood(
            name: "宫保鸡丁", weightG: 200, values: NutrientValues(caloriesKcal: 398), foodRef: "catalog:kung_pao_chicken",
            loggedAt: .now)
        let results = search("鸡", recents: [recent])
        let kungPao = results.firstIndex { $0.choice.foodRef == "catalog:kung_pao_chicken" }
        let others = results.enumerated().filter { $0.element.match == .contains && !$0.element.isRecent }.map(\.offset)
        #expect(kungPao != nil)
        if let kungPao, let firstOther = others.first { #expect(kungPao < firstOther) }
    }
}

// MARK: - 份量换算

@Suite("自然份量 → 克 → 营养")
struct ServingMathTests {
    let catalog = FoodCatalog.shared

    private func choice(_ id: String) throws -> FoodChoice {
        .catalog(try #require(catalog.food(id: id)))
    }

    @Test("CASE 1：米饭 1 碗 = 约 150 克 = 174 千卡；1.5 碗 = 225 克 = 261 千卡；半碗 = 75 克")
    func riceBowls() throws {
        let rice = try choice("rice")
        #expect(rice.initialSelection == .natural(unitID: "bowl", quantity: 1))
        #expect(ServingMath.amount(of: .natural(unitID: "bowl", quantity: 1), in: rice) == 150)
        #expect(ServingMath.displayed(ServingMath.values(of: .natural(unitID: "bowl", quantity: 1), in: rice), isEstimate: false).caloriesKcal == 174)
        #expect(ServingMath.amount(of: .natural(unitID: "bowl", quantity: 1.5), in: rice) == 225)
        #expect(ServingMath.displayed(ServingMath.values(of: .natural(unitID: "bowl", quantity: 1.5), in: rice), isEstimate: false).caloriesKcal == 261)
        #expect(ServingMath.amount(of: .natural(unitID: "bowl", quantity: 0.5), in: rice) == 75)
    }

    @Test("CASE 2：直接填 137 克 = 159 千卡；还没填是 0")
    func grams() throws {
        let rice = try choice("rice")
        #expect(ServingMath.amount(of: .amount(137), in: rice) == 137)
        #expect(ServingMath.displayed(ServingMath.values(of: .amount(137), in: rice), isEstimate: false).caloriesKcal == 159)
        #expect(ServingMath.values(of: .amount(nil), in: rice) == .zero)
    }

    @Test("CASE 4：牛奶 1 杯 = 250 毫升，热量按每 100 毫升算")
    func milkCup() throws {
        let food = try #require(catalog.food(id: "milk"))
        let milk = FoodChoice.catalog(food)
        #expect(milk.basis.amountUnit == .milliliter)
        #expect(ServingMath.amount(of: .natural(unitID: "cup", quantity: 1), in: milk) == 250)
        let kcal = ServingMath.values(of: .natural(unitID: "cup", quantity: 1), in: milk).caloriesKcal
        #expect(abs(kcal - food.per100.kcal * 2.5) < 0.01)
    }

    @Test("克数换回自然份量：正好是半碗的整数倍（差不到 2%）才换")
    func quantityForAmount() {
        let bowl = ServingUnit.named("碗", id: "bowl", amount: 150)
        #expect(ServingMath.quantity(forAmount: 150, unit: bowl) == 1)
        #expect(ServingMath.quantity(forAmount: 225, unit: bowl) == 1.5)
        #expect(ServingMath.quantity(forAmount: 152, unit: bowl) == 1)  // 差 1.3%
        #expect(ServingMath.quantity(forAmount: 180, unit: bowl) == nil)  // 不硬说成 1.2 碗
        #expect(ServingMath.quantity(forAmount: 137, unit: bowl) == nil)
        #expect(ServingMath.quantity(forAmount: 30, unit: bowl) == nil)  // 不到半碗
        #expect(ServingMath.quantity(forAmount: 0, unit: bowl) == nil)
        let piece = ServingUnit.named("个", id: "piece", amount: 50, step: 1)
        #expect(ServingMath.quantity(forAmount: 100, unit: piece) == 2)
        #expect(ServingMath.quantity(forAmount: 75, unit: piece) == nil)  // 鸡蛋没有「1.5 个」
    }

    @Test("加减：一次一步，最少一步，最多 99")
    func stepping() {
        #expect(ServingMath.stepped(1, by: 1, step: 0.5) == 1.5)
        #expect(ServingMath.stepped(1, by: -1, step: 0.5) == 0.5)
        #expect(ServingMath.stepped(0.5, by: -1, step: 0.5) == 0.5)
        #expect(ServingMath.stepped(1, by: -1, step: 1) == 1)
        #expect(ServingMath.stepped(99, by: 1, step: 1) == 99)
    }

    @Test("估算的数字取整：热量到 10 千卡，营养素到 1 克；准确的照常")
    func displayedRounding() {
        let v = NutrientValues(caloriesKcal: 354, proteinG: 23.6, carbsG: 12.8, fatG: 23.4)
        #expect(ServingMath.displayed(v, isEstimate: true) == NutrientValues(caloriesKcal: 350, proteinG: 24, carbsG: 13, fatG: 23))
        #expect(ServingMath.displayed(v, isEstimate: false) == NutrientValues(caloriesKcal: 354, proteinG: 23.6, carbsG: 12.8, fatG: 23.4))
    }
}

// MARK: - 份量的写法

// FoodEntry、CustomFood 是数据库的模型，只能在主线程用
@MainActor
@Suite("份量写给人看")
struct PortionTextTests {
    @Test("半碗、1 碗、1.5 碗；约 150 克；250 毫升")
    func texts() {
        let bowl = ServingUnit.named("碗", id: "bowl", amount: 150)
        #expect(PortionText.serving(0.5, unit: bowl) == "半碗")
        #expect(PortionText.serving(1, unit: bowl) == "1 碗")
        #expect(PortionText.serving(1.5, unit: bowl) == "1.5 碗")
        #expect(PortionText.amount(150, unit: .gram, approximate: true) == "约 150 克")
        #expect(PortionText.amount(137, unit: .gram, approximate: false) == "137 克")
        #expect(PortionText.amount(250, unit: .milliliter, approximate: false) == "250 毫升")
        #expect(PortionText.commonServing(bowl, quantity: 1, amountUnit: .gram) == "1 碗 · 约 150 克")
        #expect(PortionText.commonServing(ServingUnit.serving(amount: 0), quantity: 1, amountUnit: nil) == "1 份")
    }

    @Test("热量和每 100 克：估算的写「约」并取整到 10")
    func kcal() {
        #expect(PortionText.kcal(174, isEstimate: false) == "174 千卡")
        #expect(PortionText.kcal(350, isEstimate: true) == "约 350 千卡")
        #expect(PortionText.per100(116, unit: .gram, isEstimate: false) == "116 千卡 / 100 克")
        #expect(PortionText.per100(177, unit: .gram, isEstimate: true) == "约 180 千卡 / 100 克")
        #expect(PortionText.per100(63, unit: .milliliter, isEstimate: false) == "63 千卡 / 100 毫升")
    }

    @Test("记录里的份量：「1.5 碗 · 约 225 克」；只有重量的「约 150 克」；什么都没有是 nil")
    func entryPortion() {
        let withServing = FoodEntry(
            dayKey: 20261002, meal: .lunch, name: "米饭", weightG: 225, values: NutrientValues(caloriesKcal: 261),
            source: .manual, serving: ServingChoice(unitID: "bowl", unitName: "碗", quantity: 1.5), foodRef: "catalog:rice")
        #expect(withServing.portionText == "1.5 碗 · 约 225 克")
        // 以前的记录：没有份量信息，照常显示重量
        let old = FoodEntry(
            dayKey: 20261001, meal: .lunch, name: "米饭", weightG: 150, values: NutrientValues(caloriesKcal: 174), source: .photo)
        #expect(old.portionText == "约 150 克")
        let kcalOnly = FoodEntry(
            dayKey: 20261001, meal: .lunch, name: "奶茶", weightG: nil, values: NutrientValues(caloriesKcal: 300), source: .manual)
        #expect(kcalOnly.portionText == nil)
        let milk = FoodEntry(
            dayKey: 20261002, meal: .breakfast, name: "牛奶", weightG: 250, values: NutrientValues(caloriesKcal: 158),
            source: .manual, amountUnit: .milliliter, serving: ServingChoice(unitID: "cup", unitName: "杯", quantity: 1),
            foodRef: "catalog:milk")
        #expect(milk.portionText == "1 杯 · 约 250 毫升")
    }
}

// MARK: - 各种来源

@MainActor
@Suite("我的食物、最近吃过、AI 估算变成可以选份量的食物")
struct FoodChoiceSourceTests {
    let catalog = FoodCatalog.shared

    @Test("我的食物：知道 1 份多重就按每 100 克算（能切到克）；不知道就按份数乘")
    func customBasis() throws {
        let withWeight = CustomFoodSnapshot(
            id: UUID(), name: "妈妈做的炸酱面", amountUnit: .gram, servingName: "", servingAmount: 450,
            servingValues: NutrientValues(caloriesKcal: 620))
        let a = FoodChoice.custom(withWeight)
        #expect(a.isMine && !a.isEstimate)
        #expect(a.basis.amountUnit == .gram)
        #expect(a.units.first?.name == "份")  // 单位没填就是「份」
        #expect(ServingMath.amount(of: a.initialSelection, in: a) == 450)
        #expect(ServingMath.values(of: .natural(unitID: "custom", quantity: 2), in: a).caloriesKcal == 1240)

        let noWeight = CustomFoodSnapshot(
            id: UUID(), name: "奶茶", amountUnit: .milliliter, servingName: "杯", servingAmount: nil,
            servingValues: NutrientValues(caloriesKcal: 300, proteinG: 2, carbsG: 50, fatG: 10))
        let b = FoodChoice.custom(noWeight)
        #expect(b.basis.amountUnit == nil)  // 没有「克」可选
        #expect(b.units.first?.name == "杯")
        #expect(ServingMath.values(of: .natural(unitID: "custom", quantity: 1.5), in: b).caloriesKcal == 450)
        #expect(ServingMath.amount(of: b.initialSelection, in: b) == nil)
    }

    @Test("CustomFood 存进数据库的样子和快照一致")
    func snapshot() {
        let food = CustomFood(
            name: "山西过油肉", servingName: "份", servingAmount: 200,
            servingValues: NutrientValues(caloriesKcal: 350, proteinG: 24, carbsG: 13, fatG: 23), source: .ai)
        let s = food.snapshot
        #expect(s.id == food.id && s.name == "山西过油肉" && s.isAIEstimate)
        #expect(s.servingAmount == 200 && s.servingValues.caloriesKcal == 350)
        #expect(FoodChoice.custom(s).foodRef == FoodRef.custom(food.id))
    }

    @Test("最近吃过的食物库食物：用上次的数字（可能是拍照识别后改过的），不是食物库的")
    func recentKeepsOwnNumbers() throws {
        let food = try #require(catalog.food(id: "kung_pao_chicken"))
        let recent = RecentFood(
            name: "宫保鸡丁", weightG: 200, values: NutrientValues(caloriesKcal: 398, proteinG: 24.7, carbsG: 14, fatG: 26.9),
            loggedAt: .now)
        let choice = FoodChoice.catalog(food, recent: recent)
        #expect(choice.foodRef == "catalog:kung_pao_chicken")
        #expect(ServingMath.displayed(ServingMath.values(of: choice.initialSelection, in: choice), isEstimate: false).caloriesKcal == 398)
        #expect(!choice.isEstimate)  // 是用户自己记过的数字
    }

    @Test("以前只记了热量的：按上次那一份")
    func recentWithoutWeight() {
        let recent = RecentFood(name: "奶茶", weightG: nil, values: NutrientValues(caloriesKcal: 300))
        let choice = FoodChoice.recent(recent)
        #expect(choice.basis == .perServing(NutrientValues(caloriesKcal: 300)))
        #expect(ServingMath.values(of: choice.initialSelection, in: choice).caloriesKcal == 300)
        #expect(FoodRowText.last(choice) == "1 份 · 300 千卡")
    }

    @Test("AI 估算：标估算、来源为空（还没保存）、按常见份量开始")
    func aiEstimate() {
        let estimate = FoodEstimate(
            name: "山西过油肉", per100: NutrientValues(caloriesKcal: 177, proteinG: 11.8, carbsG: 6.4, fatG: 11.7),
            amountUnit: .gram, servingName: "份", servingAmount: 200)
        let choice = FoodChoice.aiEstimate(estimate)
        #expect(choice.isAIEstimate && choice.isEstimate && choice.foodRef == nil)
        #expect(choice.adjustsOil && !choice.suggestsLabel)  // 旧版后端没说类型、按克算：当作菜
        let shown = ServingMath.displayed(ServingMath.values(of: choice.initialSelection, in: choice), isEstimate: true)
        #expect(shown == NutrientValues(caloriesKcal: 350, proteinG: 24, carbsG: 13, fatG: 23))
        #expect(FoodRowText.typical(choice) == "约 180 千卡 / 100 克 · 1 份 · 约 200 克")
    }

    @Test("后端的估算结果：名字为空用输入的，份量不合理当作 1 份 100 克，饮品按毫升")
    func estimateResponse() {
        func response(name: String, unit: String = "g", servingName: String = "份", amount: Double = 200) -> EstimateResponse {
            EstimateResponse(
                isFood: true, foodType: "dish", name: name, baseUnit: unit,
                per100: EstimatedNutrients(caloriesKcal: 177, proteinG: 11.8, carbsG: 6.4, fatG: 11.7),
                servingName: servingName, servingAmount: amount, message: "", model: "test", remainingToday: 19)
        }
        let a = FoodEstimate(response(name: "  "), query: "山西过油肉")
        #expect(a.name == "山西过油肉" && a.servingAmount == 200 && a.amountUnit == .gram)
        let b = FoodEstimate(response(name: "奶茶", unit: "ml", servingName: " ", amount: 0), query: "奶茶")
        #expect(b.amountUnit == .milliliter && b.servingName == "份" && b.servingAmount == 100)
        let c = FoodEstimate(response(name: "大盘鸡", amount: 5000), query: "大盘鸡")
        #expect(c.servingAmount == 100)
    }

    @Test("后端返回的 JSON（下划线命名）能读出来")
    func decodeResponse() throws {
        let json = """
            {"is_food": true, "name": "山西过油肉", "base_unit": "g",
             "per_100": {"calories_kcal": 177, "protein_g": 11.8, "carbs_g": 6.4, "fat_g": 11.7},
             "serving_name": "份", "serving_amount": 200, "message": "", "model": "claude", "remaining_today": 19}
            """
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let response = try decoder.decode(EstimateResponse.self, from: Data(json.utf8))
        #expect(response.isFood && response.per100.caloriesKcal == 177 && response.remainingToday == 19)
    }
}

// MARK: - 常吃

@Suite("常吃：最近 30 天记了至少 3 次")
struct FrequentFoodTests {
    let now = Date(timeIntervalSince1970: 1_790_900_000)

    private func record(_ name: String, daysAgo: Double, kcal: Double = 100) -> RecentFood {
        RecentFood(name: name, weightG: 100, values: NutrientValues(caloriesKcal: kcal), loggedAt: now.addingTimeInterval(-daysAgo * 86_400))
    }

    @Test("次数多的在前；不到 3 次、超过 30 天的不算；每种给最近一次的份量")
    func frequent() {
        let records = [
            record("米饭", daysAgo: 0, kcal: 261),
            record("鸡蛋", daysAgo: 1),
            record("米饭", daysAgo: 2),
            record("鸡蛋", daysAgo: 3),
            record("米饭", daysAgo: 4),
            record("鸡蛋", daysAgo: 5),
            record("米饭", daysAgo: 6),
            record("牛奶", daysAgo: 1),
            record("牛奶", daysAgo: 2),  // 只有 2 次
            record("苹果", daysAgo: 31),
            record("苹果", daysAgo: 32),
            record("苹果", daysAgo: 33),  // 都在 30 天以前
        ]
        let foods = RecentFoods.frequent(records, now: now)
        #expect(foods.map(\.name) == ["米饭", "鸡蛋"])
        #expect(foods.first?.values.caloriesKcal == 261)  // 最近那一次的份量
    }

    @Test("没有记录时间的（不会出现）、名字为空的不算；最多 limit 种")
    func limits() {
        let records = (0..<4).flatMap { day in ["a", "b", "c"].map { record($0, daysAgo: Double(day)) } }
        #expect(RecentFoods.frequent(records, now: now, limit: 2).count == 2)
        let noDate = Array(repeating: RecentFood(name: "米饭", weightG: 150, values: NutrientValues(caloriesKcal: 174)), count: 5)
        #expect(RecentFoods.frequent(noDate, now: now).isEmpty)
    }
}
