//
//  EatenPortionTests.swift
//  FoodTrackerTests
//
//  第九轮「没吃完」的测试：
//  - AI 估算的比例换成最接近的一档（全部、¾、一半、¼、没吃）
//  - 记录改成吃了几成：热量、营养素、重量按原来盛的份量算；改几次都不会越乘越小；改回全部原样换回去
//  - 只改名字、餐次、日期还按吃了几成记；改了数字就按新填的算
//  - 删除后撤销、识别结果页选了「这餐吃了多少」、最近使用，都带着原来的份量
//  - 发给后端的清单格式，和后端返回的结果能读懂
//  每个测试都用「只在内存里」的数据库，不会碰到模拟器里真实的记录。
//

import Foundation
import SwiftData
import Testing

@testable import FoodTracker

@MainActor
@Suite("没吃完：吃了几成")
struct EatenPortionTests {
    let container: ModelContainer
    let context: ModelContext

    init() throws {
        container = try ModelContainer(
            for: Schema(AppModels.all), configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        context = container.mainContext
    }

    /// 一碗米饭：1 碗、150 克、263 千卡
    private func rice() -> FoodEntry {
        let entry = FoodEntry(
            dayKey: 20261009, meal: .lunch, name: "米饭", weightG: 150,
            values: NutrientValues(caloriesKcal: 263, proteinG: 5.3, carbsG: 58.2, fatG: 0.6), source: .photo,
            serving: ServingChoice(unitID: "bowl", unitName: "碗", quantity: 1), foodRef: "catalog:rice")
        context.insert(entry)
        return entry
    }

    // MARK: - 换成最接近的一档

    @Test("AI 的比例换成最接近的一档；正好在中间时取多的；超出 0～1 的收回来")
    func snapping() {
        #expect(EatenPortion.snapped(0.6) == 0.5)
        #expect(EatenPortion.snapped(0.9) == 1)
        #expect(EatenPortion.snapped(0.7) == 0.75)
        #expect(EatenPortion.snapped(0.1) == 0)
        #expect(EatenPortion.snapped(0.125) == 0.25)  // 0 和 ¼ 中间：宁可多算一点
        #expect(EatenPortion.snapped(0.875) == 1)
        #expect(EatenPortion.snapped(-0.3) == 0)
        #expect(EatenPortion.snapped(1.4) == 1)
        #expect(EatenPortion.snapped(.nan) == 1)
        for option in EatenPortion.itemOptions {
            #expect(EatenPortion.snapped(option) == option)
        }
    }

    @Test("每一档都有自己的文字（整餐和每一样），旁白的文字也不空")
    func labels() {
        let mealLabels = EatenPortion.mealOptions.map(EatenPortion.mealLabel)
        let itemLabels = EatenPortion.itemOptions.map(EatenPortion.itemLabel)
        #expect(Set(mealLabels).count == EatenPortion.mealOptions.count)
        #expect(Set(itemLabels).count == EatenPortion.itemOptions.count)
        for option in EatenPortion.itemOptions {
            #expect(!EatenPortion.spokenItemLabel(option).isEmpty)
            #expect(!EatenPortion.spokenMealLabel(option).isEmpty)
        }
        // 不在几档里的比例（以后的数据）写成百分比，不会是空的
        #expect(EatenPortion.itemLabel(0.6).contains("60"))
    }

    @Test("吃下去的营养：热量取整、营养素保留 1 位小数；重量保留 1 位小数，不知道重量还是不知道")
    func eatenValues() {
        let served = NutrientValues(caloriesKcal: 263, proteinG: 5.3, carbsG: 58.2, fatG: 0.6)
        let half = EatenPortion.eatenValues(served: served, fraction: 0.5)
        #expect(half.caloriesKcal == 132)  // 131.5 → 132
        #expect(half.proteinG == 2.7)  // 2.65 → 2.7（四舍五入）
        #expect(half.carbsG == 29.1)
        #expect(half.fatG == 0.3)
        #expect(EatenPortion.eatenWeight(served: 150, fraction: 0.75) == 112.5)
        #expect(EatenPortion.eatenWeight(served: nil, fraction: 0.5) == nil)
    }

    // MARK: - 记录

    @Test("改成吃了一半：存的是吃下去的；原来的份量记下来；改回全部原样换回去（不经过四舍五入）")
    func halfThenBack() throws {
        let entry = rice()
        entry.setEaten(0.5)
        #expect(entry.eatenFraction == 0.5)
        #expect(entry.caloriesKcal == 132)
        #expect(entry.weightG == 75)
        #expect(entry.servingQuantity == nil)  // 吃下去的部分只按克记
        #expect(entry.servedServing?.quantity == 1)  // 原来是 1 碗，单位还在
        #expect(entry.servedServing?.unitID == "bowl")
        #expect(entry.servedValues.caloriesKcal == 263)
        #expect(entry.eatenLabel != nil)

        entry.setEaten(1)
        #expect(entry.eatenFraction == nil)
        #expect(entry.servedPortion == nil)
        #expect(entry.caloriesKcal == 263)
        #expect(entry.proteinG == 5.3)
        #expect(entry.carbsG == 58.2)
        #expect(entry.fatG == 0.6)
        #expect(entry.weightG == 150)
        #expect(entry.serving == ServingChoice(unitID: "bowl", unitName: "碗", quantity: 1))
        #expect(entry.servedWeightG == nil && entry.servedCaloriesKcal == nil && entry.servedServingQuantity == nil)
    }

    @Test("改几次都从原来的份量算，不会越乘越小")
    func noCompounding() {
        let entry = rice()
        entry.setEaten(0.5)
        entry.setEaten(0.25)
        entry.setEaten(0.75)
        let expected = EatenPortion.eatenValues(served: entry.servedValues, fraction: 0.75)
        #expect(entry.values == expected)
        #expect(entry.caloriesKcal == 197)  // 263 × 0.75 = 197.25
        #expect(entry.weightG == 112.5)
        #expect(entry.servedValues.caloriesKcal == 263)
    }

    @Test("没吃完的记录存进数据库、重新读出来，比例和原来的份量都还在")
    func persists() throws {
        let entry = rice()
        entry.setEaten(0.25)
        try context.save()
        let fetched = try #require(try context.fetch(FetchDescriptor<FoodEntry>()).first)
        #expect(fetched.eatenFraction == 0.25)
        #expect(fetched.servedPortion?.weightG == 150)
        #expect(fetched.servedPortion?.values.caloriesKcal == 263)
        #expect(fetched.servedPortion?.servingQuantity == 1)
        #expect(fetched.caloriesKcal == 66)  // 65.75 → 66
        // 合计、日历用的还是存着的数字：就是吃下去的
        #expect(DietLogMath.total(of: [fetched.values]).caloriesKcal == 66)
    }

    @Test("份量文字写原来盛的「1 碗 · 约 150 克」，吃了几成另外写")
    func portionText() {
        let entry = rice()
        let before = entry.portionText
        entry.setEaten(0.5)
        #expect(entry.portionText == before)
        #expect(entry.portionText?.contains("150") == true)
        #expect(entry.eatenLabel == EatenPortion.itemLabel(0.5))
    }

    @Test("只改名字、餐次、日期：还按吃了一半记；改了数字：按新填的算，不再是「原来的几成」")
    func applyKeepsOrClears() {
        let entry = rice()
        entry.setEaten(0.5)

        var renamed = EditableItem(entry: entry)
        renamed.name = "白米饭"
        renamed.meal = .dinner
        entry.apply(renamed)
        #expect(entry.name == "白米饭")
        #expect(entry.meal == .dinner)
        #expect(entry.eatenFraction == 0.5)
        #expect(entry.servedValues.caloriesKcal == 263)
        #expect(entry.servedServing?.unitID == "bowl")  // 原来的单位留着，改回全部时还是「1 碗」

        var edited = EditableItem(entry: entry)
        edited.values = NutrientValues(caloriesKcal: 150, proteinG: 3, carbsG: 33, fatG: 0.3)
        edited.weightG = 85
        entry.apply(edited)
        #expect(entry.eatenFraction == nil)
        #expect(entry.servedPortion == nil)
        #expect(entry.caloriesKcal == 150)
        #expect(entry.weightG == 85)
    }

    @Test("删掉没吃完的记录再撤销：比例、原来的份量、单位都原样放回去")
    func snapshotRestore() throws {
        let entry = rice()
        entry.setEaten(0.75)
        try context.save()
        let snapshot = FoodEntrySnapshot(entry)
        context.delete(entry)
        try context.save()
        #expect(try context.fetch(FetchDescriptor<FoodEntry>()).isEmpty)

        snapshot.restore(into: context)
        try context.save()
        let restored = try #require(try context.fetch(FetchDescriptor<FoodEntry>()).first)
        #expect(restored.eatenFraction == 0.75)
        #expect(restored.caloriesKcal == 197)
        #expect(restored.servedPortion?.values.caloriesKcal == 263)
        #expect(restored.servingUnitID == "bowl")
        #expect(restored.servingQuantity == nil)
        restored.setEaten(1)
        #expect(restored.serving == ServingChoice(unitID: "bowl", unitName: "碗", quantity: 1))
        #expect(restored.caloriesKcal == 263)
    }

    @Test("识别结果页选了「这餐吃了多少」：每一样按同样的比例记，原来的份量也记住；选全部和以前一样")
    func insertWithFraction() throws {
        let items = [
            EditableItem(
                id: UUID(), name: "宫保鸡丁", weightG: 200, values: NutrientValues(caloriesKcal: 380, proteinG: 24, carbsG: 14, fatG: 25),
                confidence: .medium, meal: .lunch, dayKey: 20261009),
            EditableItem(
                id: UUID(), name: "米饭", weightG: 150, values: NutrientValues(caloriesKcal: 263.4, proteinG: 5.31, carbsG: 58.2, fatG: 0.6),
                confidence: .high, meal: .lunch, dayKey: 20261009),
        ]
        let half = FoodEntry.insert(items, meal: .lunch, dayKey: 20261009, source: .photo, into: context, eatenFraction: 0.5)
        #expect(half.map(\.eatenFraction) == [0.5, 0.5])
        #expect(half.map(\.caloriesKcal) == [190, 132])
        // 原来的份量是先取整的数字（和全部吃完时存的一样）
        #expect(half[1].servedValues == NutrientValues(caloriesKcal: 263, proteinG: 5.3, carbsG: 58.2, fatG: 0.6))

        let whole = FoodEntry.insert(items, meal: .dinner, dayKey: 20261009, source: .photo, into: context)
        #expect(whole.map(\.eatenFraction) == [nil, nil])
        #expect(whole.map(\.caloriesKcal) == [380, 263])
    }

    @Test("「最近使用」按原来盛的份量：下次一般还是盛这么多")
    func recentUsesServed() {
        let entry = rice()
        entry.setEaten(0.5)
        let recent = entry.recentFood
        #expect(recent.weightG == 150)
        #expect(recent.values.caloriesKcal == 263)
        #expect(recent.servingQuantity == 1)
        #expect(recent.servingUnitID == "bowl")
    }

    // MARK: - 和后端通信

    @Test("发给 /leftovers 的内容：lang、items 两个字段 + 一张 photo；清单是 name 和 weight_g，不知道重量就不写")
    func leftoversBody() throws {
        let boundary = "TestBoundary"
        let body = APIClient.leftoversBody(
            jpeg: Data("剩菜照片".utf8),
            items: [LeftoverServedItem(name: "米饭", weightG: 150), LeftoverServedItem(name: "汤", weightG: nil)],
            lang: "en", boundary: boundary)
        let text = String(decoding: body, as: UTF8.self)
        #expect(text.contains("name=\"lang\"\r\n\r\nen\r\n"))
        #expect(text.contains("name=\"photo\"; filename=\"leftovers.jpg\""))
        #expect(text.contains("剩菜照片"))
        #expect(text.hasSuffix("--\(boundary)--\r\n"))

        // 取出 items 字段的 JSON，按后端的格式读
        let start = try #require(text.range(of: "name=\"items\"\r\n\r\n")).upperBound
        let end = try #require(text[start...].range(of: "\r\n")).lowerBound
        let json = try #require(try JSONSerialization.jsonObject(with: Data(text[start..<end].utf8)) as? [[String: Any]])
        #expect(json.count == 2)
        #expect(json[0]["name"] as? String == "米饭")
        #expect(json[0]["weight_g"] as? Double == 150)
        #expect(json[1]["weight_g"] == nil)
        #expect(APIClient.maxLeftoverItems == 20)  // 和后端 leftovers_ai.MAX_ITEMS 一样
    }

    @Test("后端返回的结果能读懂（下划线命名自动转换）；照片不对时 eaten 是空的")
    func decodeResponse() throws {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let ok = try decoder.decode(
            LeftoversResponse.self,
            from: Data(#"{"is_leftover_photo":true,"message":"米饭吃完了","eaten":[1.0,0.5],"model":"m","remaining_today":9}"#.utf8))
        #expect(ok.isLeftoverPhoto)
        #expect(ok.eaten == [1, 0.5])
        #expect(ok.remainingToday == 9)

        let notPhoto = try decoder.decode(
            LeftoversResponse.self,
            from: Data(#"{"is_leftover_photo":false,"message":"这不是饭菜","eaten":[],"model":"m","remaining_today":null}"#.utf8))
        #expect(!notPhoto.isLeftoverPhoto)
        #expect(notPhoto.eaten.isEmpty)
        #expect(notPhoto.remainingToday == nil)
    }
}
