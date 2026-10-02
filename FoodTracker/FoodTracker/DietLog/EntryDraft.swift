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
//  自然份量（第七轮）：认得的食物（食物库、我的食物）可以按「碗、个、杯」选份量。
//  选了「1.5 碗」就是把重量框填成 225 克，热量照上面的规则跟着变：份量只是另一种填重量的方式，不另算一套。
//  切到「克」可以直接填克数（有秤的人照样精确）
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
    /// 记到哪一天：20260929 这样的数字，一直带到保存（中途手机换了时区也不会变成别的一天）
    var dayKey: Int

    /// 显示用的日期（那天的 0 点，按手机现在的时区），也给「日期」选择器用：
    /// 用户选了新日期，马上换回数字存起来
    var displayDay: Date {
        get { DayMath.date(fromDayKey: dayKey) }
        set { dayKey = DayMath.dayKey(for: newValue) }
    }

    /// 每 100 克含多少热量和营养素（不四舍五入）；nil = 还不能按比例换算
    private(set) var per100: NutrientValues?

    /// 打开时的样子：用来判断「改过没有」，并保留原来的 id 和 AI 的把握程度
    private let original: EditableItem?
    private let id: UUID
    /// 上一次看到的五个输入框：用来判断这次用户改的是哪一个（界面不需要它，所以不触发刷新）
    @ObservationIgnored private var lastTexts: [String] = []
    /// 「每 100 克含量」是在多少克时记下的：重量删空（或填 0）时，按这个重量把数字换算回来
    @ObservationIgnored private var baseWeightG: Double?

    /// 重量框的单位：克，或者毫升（牛奶这类）
    private(set) var amountUnit: AmountUnit = .gram
    /// 这种食物能选的自然份量单位（碗、个……）；空的 = 只能填克数
    private(set) var servingUnits: [ServingUnit] = []
    /// 现在选的是某个自然单位的几份；nil = 直接填克数
    private(set) var naturalServing: (unitID: String, quantity: Double)?
    /// 来自哪种食物（catalog:rice、custom:<UUID>）
    private(set) var foodRef: String?

    /// 五个输入框，顺序：重量、热量、蛋白质、碳水、脂肪（给 .onChange 用）
    var allTexts: [String] { [weightText, caloriesText, proteinText, carbsText, fatText] }

    /// 空白的草稿：手动添加、识别结果页的「添加一项」
    init(meal: MealType, dayKey: Int) {
        self.meal = meal
        self.dayKey = dayKey
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
        dayKey = item.dayKey
        per100 = DietLogMath.per100(item.values, weightG: item.weightG)
        baseWeightG = item.weightG
        original = item
        id = item.id
        amountUnit = item.amountUnit
        foodRef = item.foodRef
        if let serving = item.serving { naturalServing = (serving.unitID, serving.quantity) }
        lastTexts = allTexts
        // 打开时营养素就比重量还多：「每 100 克含量」不可信，不拿来换算
        if macrosExceedWeightWarning != nil { per100 = nil }
    }

    // MARK: - 自然份量

    /// 告诉草稿这种食物有哪些自然单位（打开表单时，由页面按来源或名字从食物库 / 我的食物里找到）。
    /// fallbackPer100：草稿自己还算不出「每 100 克含量」时（比如还没填重量），用食物库里的
    func link(units: [ServingUnit], amountUnit: AmountUnit, foodRef: String?, fallbackPer100: NutrientValues?) {
        servingUnits = units.filter { $0.amount > 0 }
        self.amountUnit = amountUnit
        self.foodRef = foodRef
        if per100 == nil, weightG == nil, let fallbackPer100 { per100 = fallbackPer100 }
        // 打开时：记录里存着选的是哪个单位就用它；否则看重量是不是正好某个单位的整数倍（150 克 = 1 碗）
        if let current = naturalServing, servingUnits.contains(where: { $0.id == current.unitID }) { return }
        naturalServing = nil
        guard let grams = weightG else { return }
        for unit in servingUnits {
            if let quantity = ServingMath.quantity(forAmount: grams, unit: unit) {
                naturalServing = (unit.id, quantity)
                return
            }
        }
    }

    /// 名字改成了不认识的食物：不再提供自然单位（已经填的克数留着）
    func unlinkServing() {
        guard !servingUnits.isEmpty || naturalServing != nil else { return }
        servingUnits = []
        naturalServing = nil
        foodRef = original?.foodRef
    }

    /// 选了某个自然单位（数量不变；刚从「克」切过来时从 1 份开始）
    func selectServingUnit(_ unitID: String) {
        guard let unit = servingUnits.first(where: { $0.id == unitID }) else { return }
        setServing(unit: unit, quantity: naturalServing?.unitID == unitID ? naturalServing?.quantity ?? 1 : 1)
    }

    /// 加一步 / 减一步（direction 是 +1 或 -1）
    func stepServing(by direction: Int) {
        guard let current = naturalServing, let unit = servingUnits.first(where: { $0.id == current.unitID }) else { return }
        setServing(unit: unit, quantity: ServingMath.stepped(current.quantity, by: direction, step: unit.step))
    }

    /// 切到直接填克数：重量框里的数字留着，接着改
    func selectAmountInput() {
        naturalServing = nil
    }

    /// 选好的自然份量：把重量框填成对应的克数（已经有数字的框由 textsChanged 按比例跟着变）。
    /// 热量还空着（比如手动填写时刚打了「米饭」）：按食物库的含量直接填上，用户可以再改
    private func setServing(unit: ServingUnit, quantity: Double) {
        naturalServing = (unit.id, quantity)
        let grams = DietLogMath.round1(quantity * unit.amount)
        weightText = NumberText.text(from: grams)
        guard NumberText.isBlank(caloriesText), let per100 else { return }
        let values = DietLogMath.rounded(DietLogMath.scaled(per100, toWeightG: grams))
        caloriesText = NumberText.text(from: values.caloriesKcal)
        if per100.proteinG > 0 || per100.carbsG > 0 || per100.fatG > 0 {
            if NumberText.isBlank(proteinText) { proteinText = NumberText.text(from: values.proteinG) }
            if NumberText.isBlank(carbsText) { carbsText = NumberText.text(from: values.carbsG) }
            if NumberText.isBlank(fatText) { fatText = NumberText.text(from: values.fatG) }
        }
        baseWeightG = grams
    }

    /// 现在选的自然单位（给界面显示「1.5 碗」）
    var selectedServingUnit: ServingUnit? {
        naturalServing.flatMap { current in servingUnits.first { $0.id == current.unitID } }
    }

    /// 存进记录的自然份量：重量框还是这个份量对应的克数时才算（用户后来改了克数就不算了）
    private var servingOutput: ServingChoice? {
        guard let current = naturalServing, let unit = selectedServingUnit, let grams = weightG,
            abs(grams - DietLogMath.round1(current.quantity * unit.amount)) < 0.05
        else { return nil }
        return ServingChoice(unitID: unit.id, unitName: unit.displayName(quantity: current.quantity), quantity: current.quantity)
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

    // MARK: - 从「最近使用」预填

    /// 从「最近使用」里点了一种食物：填上名字；空着的框填上上次的份量和营养（已经填了的不动），用户可以再改。
    /// 和打开已有的一项一样记下「每 100 克含量」，之后改份量会按比例换算
    func prefill(from food: RecentFood) {
        name = food.name
        if NumberText.isBlank(weightText), let grams = food.weightG { weightText = NumberText.text(from: grams) }
        if NumberText.isBlank(caloriesText) { caloriesText = NumberText.text(from: food.values.caloriesKcal) }
        // 上次只填了热量（三种营养素都是 0）：营养素的框继续空着，不填一排 0
        if food.values.proteinG > 0 || food.values.carbsG > 0 || food.values.fatG > 0 {
            if NumberText.isBlank(proteinText) { proteinText = NumberText.text(from: food.values.proteinG) }
            if NumberText.isBlank(carbsText) { carbsText = NumberText.text(from: food.values.carbsG) }
            if NumberText.isBlank(fatText) { fatText = NumberText.text(from: food.values.fatG) }
        }
        per100 = DietLogMath.per100(currentValues, weightG: weightG)
        baseWeightG = weightG
        if macrosExceedWeightWarning != nil { per100 = nil }
        // 这次是 App 自己填的，不算用户改的：下一次 textsChanged() 不会拿它去换算
        lastTexts = allTexts
    }

    // MARK: - 检查结果（nil 表示没问题）

    var nameError: String? { EntryValidator.nameError(name) }
    var weightError: String? { EntryValidator.weightError(text: weightText) }
    var caloriesError: String? { EntryValidator.caloriesError(text: caloriesText) }
    var proteinError: String? { EntryValidator.macroError(text: proteinText, name: String(localized: "蛋白质")) }
    var carbsError: String? { EntryValidator.macroError(text: carbsText, name: String(localized: "碳水")) }
    var fatError: String? { EntryValidator.macroError(text: fatText, name: String(localized: "脂肪")) }

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
            dayKey: dayKey,
            amountUnit: amountUnit,
            serving: servingOutput,
            foodRef: foodRef)
    }
}
