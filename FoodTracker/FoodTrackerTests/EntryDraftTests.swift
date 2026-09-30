//
//  EntryDraftTests.swift
//  FoodTrackerTests
//
//  编辑表单（EntryDraft）的测试：模拟用户一个框一个框地输入，检查按比例换算对不对。
//  每一步先改一个输入框，再调用 textsChanged()：表单里每次输入框变化时，App 也是这样调用的。
//

import Foundation
import Testing

@testable import FoodTracker

// EntryDraft 只能在主线程使用，所以整组测试标上 @MainActor
@MainActor
@Suite("饮食记录草稿")
struct EntryDraftTests {
    let day = Date(timeIntervalSince1970: 1_790_613_000)

    /// 识别结果里的米饭：150 克、174 千卡、蛋白质 3.9、碳水 38.1、脂肪 0.5
    private var rice: EditableItem {
        EditableItem(
            FoodItem(name: "米饭", weightG: 150, caloriesKcal: 174, proteinG: 3.9, carbsG: 38.1, fatG: 0.5, confidence: .high),
            meal: .lunch, day: day)
    }

    /// 模拟用户在重量框里输入
    private func type(weight text: String, _ draft: EntryDraft) {
        draft.weightText = text
        draft.textsChanged()
    }

    /// 模拟用户在热量框里输入
    private func type(calories text: String, _ draft: EntryDraft) {
        draft.caloriesText = text
        draft.textsChanged()
    }

    private func nutrientTexts(_ draft: EntryDraft) -> [String] {
        [draft.caloriesText, draft.proteinText, draft.carbsText, draft.fatText]
    }

    @Test("打开识别结果的一项：数字都填好，可以按比例换算")
    func openItem() {
        let item = rice
        let draft = EntryDraft(item: item)
        #expect(draft.allTexts == ["150", "174", "3.9", "38.1", "0.5"])
        #expect(draft.per100 != nil)
        #expect(draft.output?.confidence == .high)  // 没改过：保留 AI 的把握程度
        #expect(draft.output?.id == item.id)
    }

    // 150 克 → 200 克：232 千卡、蛋白质 5.2、碳水 50.8、脂肪 0.7
    @Test("改重量：热量和营养素按比例一起变")
    func changeWeight() {
        let draft = EntryDraft(item: rice)
        type(weight: "200", draft)
        #expect(nutrientTexts(draft) == ["232", "5.2", "50.8", "0.7"])
        #expect(draft.output?.confidence == nil)  // 改过了：显示「已修改」
        #expect(draft.output?.weightG == 200)

        // 再多调用几次也不会变（界面有时会多通知一次）
        let density = draft.per100
        draft.textsChanged()
        draft.textsChanged()
        #expect(draft.per100 == density)
        #expect(nutrientTexts(draft) == ["232", "5.2", "50.8", "0.7"])
    }

    @Test("来回改重量不会累积误差")
    func weightRoundTrip() {
        let draft = EntryDraft(item: rice)
        type(weight: "75", draft)
        #expect(draft.caloriesText == "87")
        #expect(draft.fatText == "0.3")
        type(weight: "150", draft)
        #expect(nutrientTexts(draft) == ["174", "3.9", "38.1", "0.5"])
        #expect(draft.output?.confidence == .high)  // 改回原样：又是 AI 原来的把握程度

        // 用退格键一个字一个字地把重量删空：数字回到原样，而不是停在「1 克」时换算出的数
        for text in ["15", "1", ""] { type(weight: text, draft) }
        #expect(nutrientTexts(draft) == ["174", "3.9", "38.1", "0.5"])
        // 再一个字一个字地输入 200
        for text in ["2", "20", "200"] { type(weight: text, draft) }
        #expect(nutrientTexts(draft) == ["232", "5.2", "50.8", "0.7"])
        // 全选删除也一样：回到原样
        type(weight: "", draft)
        #expect(nutrientTexts(draft) == ["174", "3.9", "38.1", "0.5"])
    }

    @Test("用户清空的框，改重量时不会自动填回去")
    func clearedBoxStaysBlank() throws {
        // 手动添加：100 克、120 千卡、蛋白质 10，然后把蛋白质删空
        let draft = EntryDraft(meal: .lunch, day: day)
        draft.name = "燕麦"
        type(weight: "100", draft)
        type(calories: "120", draft)
        for text in ["1", "10", "1", ""] {
            draft.proteinText = text
            draft.textsChanged()
        }
        for text in ["2", "20", "200"] { type(weight: text, draft) }
        #expect(draft.caloriesText == "240")
        #expect(draft.proteinText == "")
        #expect(try #require(draft.output).values.proteinG == 0)

        // 识别结果里的米饭：把热量删空再改重量，热量框保持空白，不能保存
        let riceDraft = EntryDraft(item: rice)
        for text in ["17", "1", ""] { type(calories: text, riceDraft) }
        type(weight: "200", riceDraft)
        #expect(riceDraft.caloriesText == "")
        #expect(riceDraft.output == nil)
    }

    // 重量误填成「两」（2），营养素加起来比重量还多；改正成 100 克时，数字不能被放大 50 倍
    @Test("营养素比重量还多时不按比例换算")
    func unitMistakeDoesNotRescale() throws {
        let draft = EntryDraft(meal: .lunch, day: day)
        draft.name = "米饭"
        type(weight: "2", draft)
        for text in ["1", "11", "116"] { type(calories: text, draft) }
        draft.proteinText = "2.6"
        draft.textsChanged()
        draft.carbsText = "25.4"
        draft.textsChanged()
        draft.fatText = "0.3"
        draft.textsChanged()
        #expect(draft.macrosExceedWeightWarning != nil)
        for text in ["", "1", "10", "100"] { type(weight: text, draft) }
        #expect(draft.allTexts == ["100", "116", "2.6", "25.4", "0.3"])
        #expect(draft.macrosExceedWeightWarning == nil)
        #expect(draft.output != nil)
    }

    // 75 克时把热量改成 200：每 100 克含 266.67 千卡；再改回 150 克 → 400 千卡，蛋白质照旧按比例
    @Test("直接改热量：只改热量，并成为新的换算基础")
    func editCalories() {
        let draft = EntryDraft(item: rice)
        type(weight: "75", draft)
        type(calories: "200", draft)
        type(weight: "150", draft)
        #expect(draft.caloriesText == "400")
        #expect(draft.proteinText == "3.9")
    }

    @Test("先填重量、再填热量：之后改重量会按比例换算")
    func weightThenCalories() {
        let draft = EntryDraft(meal: .lunch, day: day)
        type(weight: "100", draft)
        #expect(draft.per100 == nil)
        #expect(draft.caloriesText == "")
        for text in ["1", "12", "120"] { type(calories: text, draft) }
        #expect(draft.per100?.caloriesKcal == 120)
        type(weight: "200", draft)
        #expect(draft.caloriesText == "240")
    }

    @Test("先填热量、再填重量：不换算，热量保持用户填的数")
    func caloriesThenWeight() throws {
        let draft = EntryDraft(meal: .lunch, day: day)
        draft.name = "燕麦"
        type(calories: "120", draft)
        for text in ["1", "10", "100"] { type(weight: text, draft) }
        #expect(draft.per100 == nil)
        #expect(draft.caloriesText == "120")

        // 保存以后再打开：重量和热量都有了，这时可以按比例换算
        let saved = try #require(draft.output)
        let reopened = EntryDraft(item: saved)
        #expect(reopened.weightG == 100)
        #expect(reopened.per100 != nil)
        type(weight: "50", reopened)
        #expect(reopened.caloriesText == "60")
    }

    @Test("手动添加：名称和热量必须填，其他可以不填")
    func manualEntry() throws {
        let draft = EntryDraft(meal: .snack, day: day)
        #expect(draft.output == nil)
        draft.name = "拿铁"
        #expect(draft.output == nil)
        type(calories: "150", draft)
        let item = try #require(draft.output)
        #expect(item.name == "拿铁")
        #expect(item.weightG == nil)
        #expect(item.values == NutrientValues(caloriesKcal: 150))
        #expect(item.confidence == nil)
        #expect(item.meal == .snack)
        #expect(item.day == day)
    }

    @Test("重量填 0 或小到 0 克：当作不知道重量")
    func zeroWeight() throws {
        let draft = EntryDraft(meal: .lunch, day: day)
        draft.name = "水"
        type(calories: "0", draft)
        type(weight: "0", draft)
        #expect(try #require(draft.output).weightG == nil)
        type(weight: "0.04", draft)
        #expect(try #require(draft.output).weightG == nil)
    }

    @Test("特别小或特别大的数字不会闪退")
    func extremeNumbers() {
        let tiny = EntryDraft(meal: .lunch, day: day)
        type(weight: "0.000000000000000001", tiny)
        type(calories: "174", tiny)
        type(weight: "150", tiny)
        #expect(tiny.per100 == nil)
        #expect(tiny.caloriesText == "174")

        let huge = EntryDraft(meal: .lunch, day: day)
        huge.name = "x"
        type(weight: "0.1", huge)
        type(calories: "99999999999999999999", huge)
        type(weight: "5000", huge)
        #expect(!huge.caloriesText.isEmpty)
        #expect(huge.output == nil)  // 超出 5000 千卡，不能保存
    }

    @Test("只改名称也算修改过")
    func renameClearsConfidence() throws {
        let draft = EntryDraft(item: rice)
        draft.name = "糙米饭"
        #expect(try #require(draft.output).confidence == nil)
    }

    @Test("清空重量后改了热量：以后再填重量，不会覆盖用户填的热量")
    func clearWeightThenEdit() {
        let draft = EntryDraft(item: rice)
        for text in ["15", "1", ""] { type(weight: text, draft) }
        type(calories: "300", draft)
        #expect(nutrientTexts(draft) == ["300", "3.9", "38.1", "0.5"])
        for text in ["2", "20", "200"] { type(weight: text, draft) }
        #expect(draft.caloriesText == "300")
        #expect(draft.per100 == nil)
    }

    @Test("AI 给的重量是 0 的食物（比如葱花）")
    func aiItemWithoutWeight() throws {
        let item = EditableItem(
            FoodItem(name: "葱花", weightG: 0, caloriesKcal: 2, proteinG: 0.1, carbsG: 0.3, fatG: 0, confidence: .low),
            meal: .lunch, day: day)
        let draft = EntryDraft(item: item)
        #expect(draft.weightText == "")
        #expect(draft.per100 == nil)
        type(weight: "5", draft)
        #expect(draft.caloriesText == "2")  // 没有换算基础，不动
        #expect(try #require(draft.output).confidence == nil)  // 只填了重量也算改过：显示「已修改」
        type(calories: "3", draft)  // 有了重量再改热量：记下每 100 克 60 千卡
        type(weight: "10", draft)
        #expect(draft.caloriesText == "6")
    }

    @Test("输入检查的提示")
    func errorsAndWarnings() {
        let draft = EntryDraft(meal: .lunch, day: day)
        draft.name = "测试"
        type(calories: "9000", draft)
        #expect(draft.caloriesError == "热量需要在 0～5000 千卡之间")
        #expect(draft.output == nil)
        draft.proteinText = "12,5"
        #expect(draft.proteinError == nil)  // 逗号当小数点
        type(calories: "100", draft)
        draft.proteinText = "50"
        draft.carbsText = "50"
        draft.fatText = "20"
        #expect(draft.kcalMismatchWarning != nil)  // 按营养素算约 580 千卡，和 100 差太多
        #expect(draft.output != nil)  // 灰色提醒不阻止保存
    }
}
