//
//  EntryDraft.swift
//  FoodTracker
//
//  编辑一项食物时的「草稿」：用户边填、App 边检查，填对了才能保存。
//  手动添加、修改识别结果、修改已保存的记录，都用这一个草稿（和资料页的 ProfileDraft 是同一种做法）。
//
//  按比例换算的规则：
//  - 改了重量：热量和三大营养素按「每 100 克的含量」一起变
//  - 直接改热量或某一种营养素：只改那一项，并把它当成新的「每 100 克含量」
//  - 「每 100 克含量」只在填好重量之后、改了热量或营养素时才记下来；打重量的时候不记，
//    因为输入 100 要先经过 1、10，按 1 克算出来的含量全是错的
//  - 重量删空（或填 0）：按记下「每 100 克含量」时的重量把数字换算回来，数字不会停在删到一半（比如 1 克）时的样子
//  - 用户清空的框不自动填回去；改重量时只换算还有数字的框
//  - 三大营养素加起来比重量还多（多半是单位填错了）：这时的「每 100 克含量」不可信，丢掉不用，
//    免得改正重量时所有数字被放大几十倍
//

import Foundation
import Observation

@Observable
final class EntryDraft {
    var name = ""
    // 五个输入框里的文字。先存文字、再转成数字，输到一半也不会出错
    var weightText = ""
    var caloriesText = ""
    var proteinText = ""
    var carbsText = ""
    var fatText = ""
    var meal: MealType
    var day: Date

    /// 每 100 克含多少热量和营养素（不四舍五入）；nil = 还不能按比例换算
    private(set) var per100: NutrientValues?

    /// 打开时的样子：用来判断「改过没有」，并保留原来的 id 和 AI 的把握程度
    private let original: EditableItem?
    private let id: UUID
    /// 上一次看到的五个输入框：用来判断这次用户改的是哪一个（界面不需要它，所以不触发刷新）
    @ObservationIgnored private var lastTexts: [String] = []
    /// 「每 100 克含量」是在多少克时记下的：重量删空（或填 0）时，按这个重量把数字换算回来
    @ObservationIgnored private var baseWeightG: Double?

    /// 五个输入框，顺序：重量、热量、蛋白质、碳水、脂肪（给 .onChange 用）
    var allTexts: [String] { [weightText, caloriesText, proteinText, carbsText, fatText] }

    /// 空白的草稿：手动添加、识别结果页的「添加一项」
    init(meal: MealType, day: Date) {
        self.meal = meal
        self.day = day
        original = nil
        id = UUID()
        lastTexts = allTexts
    }

    /// 修改已有的一项：识别结果里的一项，或者已保存的记录（先用 EditableItem(entry:) 转一下）
    init(item: EditableItem) {
        name = item.name
        weightText = item.weightG.map(NumberText.text(from:)) ?? ""
        caloriesText = NumberText.text(from: item.values.caloriesKcal)
        proteinText = NumberText.text(from: item.values.proteinG)
        carbsText = NumberText.text(from: item.values.carbsG)
        fatText = NumberText.text(from: item.values.fatG)
        meal = item.meal
        day = item.day
        per100 = DietLogMath.per100(item.values, weightG: item.weightG)
        baseWeightG = item.weightG
        original = item
        id = item.id
        lastTexts = allTexts
        // 打开时营养素就比重量还多：「每 100 克含量」不可信，不拿来换算
        if macrosExceedWeightWarning != nil { per100 = nil }
    }

    /// 重量（克），保留 1 位小数；没填、填 0 或小到四舍五入后是 0，都当作「不知道重量」
    var weightG: Double? {
        guard let grams = NumberText.number(from: weightText) else { return nil }
        let rounded = DietLogMath.round1(grams)
        return rounded > 0 ? rounded : nil
    }

    // MARK: - 输入框变了

    /// 五个输入框有变化时调用（多调用几次也没关系：没有新变化就什么都不做）
    func textsChanged() {
        let old = lastTexts
        // 最后记下现在的样子，包括这里自己写进去的数字：自己写的不会被当成用户改的
        defer { lastTexts = allTexts }

        if weightText != old[0] {
            // 用户改了重量：有「每 100 克含量」就把还有数字的框按比例重算；没有就什么都不做。
            // 重量删空了就按记下含量时的重量算，数字回到原样
            guard let per100, let grams = weightG ?? baseWeightG else { return }
            let values = DietLogMath.rounded(DietLogMath.scaled(per100, toWeightG: grams))
            // 用户清空的框不自动填回去（它的「每 100 克含量」可能还停在清空前某一下按键时的数）
            if !NumberText.isBlank(caloriesText) { caloriesText = NumberText.text(from: values.caloriesKcal) }
            if !NumberText.isBlank(proteinText) { proteinText = NumberText.text(from: values.proteinG) }
            if !NumberText.isBlank(carbsText) { carbsText = NumberText.text(from: values.carbsG) }
            if !NumberText.isBlank(fatText) { fatText = NumberText.text(from: values.fatG) }
        } else if allTexts != old {
            nutrientEdited(old: old)
            // 三大营养素比重量还多：重量或数字肯定有一个填错了，这时的「每 100 克含量」不可信，不拿来换算
            if macrosExceedWeightWarning != nil { per100 = nil }
        }
    }

    /// 用户改了热量或某一种营养素
    private func nutrientEdited(old: [String]) {
        // 不知道重量：以前记下的「每 100 克含量」已经对不上了，丢掉
        guard let grams = weightG else {
            per100 = nil
            return
        }
        guard var density = per100 else {
            // 第一次：热量是数字、三种营养素是空（算 0）或数字，才记下「每 100 克含量」
            guard let kcal = NumberText.number(from: caloriesText),
                let protein = blankAsZero(proteinText), let carbs = blankAsZero(carbsText), let fat = blankAsZero(fatText)
            else { return }
            per100 = DietLogMath.per100(
                NutrientValues(caloriesKcal: kcal, proteinG: protein, carbsG: carbs, fatG: fat), weightG: grams)
            baseWeightG = grams
            return
        }
        // 已经有了：只改用户改的那一项（清空的框先不动它）
        if caloriesText != old[1], let kcal = NumberText.number(from: caloriesText) { density.caloriesKcal = kcal / grams * 100 }
        if proteinText != old[2], let protein = NumberText.number(from: proteinText) { density.proteinG = protein / grams * 100 }
        if carbsText != old[3], let carbs = NumberText.number(from: carbsText) { density.carbsG = carbs / grams * 100 }
        if fatText != old[4], let fat = NumberText.number(from: fatText) { density.fatG = fat / grams * 100 }
        per100 = density
        baseWeightG = grams
    }

    /// 营养素的框：空白算 0；填了但不是数字 → nil
    private func blankAsZero(_ text: String) -> Double? {
        NumberText.isBlank(text) ? 0 : NumberText.number(from: text)
    }

    // MARK: - 检查结果（nil 表示没问题）

    var nameError: String? { EntryValidator.nameError(name) }
    var weightError: String? { EntryValidator.weightError(text: weightText) }
    var caloriesError: String? { EntryValidator.caloriesError(text: caloriesText) }
    var proteinError: String? { EntryValidator.macroError(text: proteinText, name: "蛋白质") }
    var carbsError: String? { EntryValidator.macroError(text: carbsText, name: "碳水") }
    var fatError: String? { EntryValidator.macroError(text: fatText, name: "脂肪") }

    private var currentValues: NutrientValues {
        NutrientValues(
            caloriesKcal: NumberText.number(from: caloriesText) ?? 0,
            proteinG: blankAsZero(proteinText) ?? 0,
            carbsG: blankAsZero(carbsText) ?? 0,
            fatG: blankAsZero(fatText) ?? 0)
    }

    // 灰色提醒，不阻止保存
    var kcalMismatchWarning: String? { EntryValidator.kcalMismatchWarning(currentValues) }
    var macrosExceedWeightWarning: String? { EntryValidator.macrosExceedWeightWarning(currentValues, weightG: weightG) }

    // MARK: - 保存

    /// 全部填对时，得到要保存的一项；否则是 nil（保存按钮不能点）
    var output: EditableItem? {
        guard nameError == nil, weightError == nil, caloriesError == nil,
            proteinError == nil, carbsError == nil, fatError == nil
        else { return nil }
        let values = DietLogMath.rounded(currentValues)
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        // 名称、重量和数字都没变时，保留 AI 原来的把握程度；改过任何一项就显示「已修改」
        let unchanged = original.map { $0.name == trimmedName && $0.weightG == weightG && $0.values == values } ?? false
        return EditableItem(
            id: id,
            name: trimmedName,
            weightG: weightG,
            values: values,
            confidence: unchanged ? original?.confidence : nil,
            meal: meal,
            day: day)
    }
}
