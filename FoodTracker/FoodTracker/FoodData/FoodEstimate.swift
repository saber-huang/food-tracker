//
//  FoodEstimate.swift
//  FoodTracker
//
//  AI 估算：食物库和我的食物里都搜不到时，把用户输入的食物名称发给后端 /estimate，
//  由 AI 估算这种食物每 100 克（饮品每 100 毫升）的营养，和一个常见的份量（「1 份 约 200 克」）。
//  和 backend/estimate_ai.py 里的格式一一对应（后端用下划线命名，解析时自动转成 isFood 这种写法）。
//  结果只是估算：界面上标「AI 估算 ⓘ」、数字取整加「约」；用户确认后可以保存到「我的食物」，
//  不会写进内置食物库
//

import Foundation

/// 后端返回的营养数字
nonisolated struct EstimatedNutrients: Codable, Hashable, Sendable {
    let caloriesKcal: Double
    let proteinG: Double
    let carbsG: Double
    let fatG: Double
}

/// /estimate 返回的完整结果
nonisolated struct EstimateResponse: Codable, Hashable, Sendable {
    let isFood: Bool  // 输入的是不是一种食物
    let name: String  // 整理过的名字（「山西过油肉」）
    let baseUnit: String  // "g" 每 100 克 / "ml" 每 100 毫升
    let per100: EstimatedNutrients
    let servingName: String  // 常见份量的单位：「份」「碗」「个」
    let servingAmount: Double  // 1 个这样的单位大约多少克（毫升）
    let message: String  // 不是食物时，给用户看的一句话
    let model: String
    let remainingToday: Int?  // 今天还能估算几次
}

/// App 里用的 AI 估算结果
nonisolated struct FoodEstimate: Hashable, Sendable {
    let name: String
    let per100: NutrientValues
    let amountUnit: AmountUnit
    let servingName: String
    let servingAmount: Double

    init(name: String, per100: NutrientValues, amountUnit: AmountUnit, servingName: String, servingAmount: Double) {
        self.name = name
        self.per100 = per100
        self.amountUnit = amountUnit
        self.servingName = servingName
        self.servingAmount = servingAmount
    }

    /// 从后端的结果来：名字为空就用用户输入的；份量不合理（0 或太大）就当作「1 份 约 100 克」
    init(_ response: EstimateResponse, query: String) {
        let trimmed = response.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let serving = response.servingName.trimmingCharacters(in: .whitespacesAndNewlines)
        let amountOK = response.servingAmount > 0 && response.servingAmount <= 2000
        self.init(
            name: trimmed.isEmpty ? query : trimmed,
            per100: NutrientValues(
                caloriesKcal: response.per100.caloriesKcal, proteinG: response.per100.proteinG,
                carbsG: response.per100.carbsG, fatG: response.per100.fatG),
            amountUnit: response.baseUnit == "ml" ? .milliliter : .gram,
            servingName: serving.isEmpty ? String(localized: "份") : serving,
            servingAmount: amountOK ? response.servingAmount : 100)
    }
}
