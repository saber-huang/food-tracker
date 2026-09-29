//
//  Models.swift
//  FoodTracker
//
//  后端 /analyze 返回的数据格式，和 backend/food_ai.py 里的定义一一对应。
//  后端用下划线命名（比如 is_food），解析时会自动转成 Swift 习惯的写法（isFood）。
//

import Foundation

/// 一次识别的完整结果
struct AnalyzeResult: Codable, Hashable {
    let isFood: Bool  // 照片里有没有食物
    let message: String  // 给用户看的一句话
    let items: [FoodItem]  // 识别出的每一种食物
    let total: MealTotal  // 整餐合计
    let model: String  // 用的是哪个 AI 模型
}

/// 一种食物
struct FoodItem: Codable, Hashable {
    let name: String  // 名称
    let weightG: Double  // 估算重量（克）
    let caloriesKcal: Double  // 热量（千卡）
    let proteinG: Double  // 蛋白质（克）
    let carbsG: Double  // 碳水化合物（克）
    let fatG: Double  // 脂肪（克）
    let confidence: Confidence  // 识别可信度
}

/// 整餐合计
struct MealTotal: Codable, Hashable {
    let weightG: Double
    let caloriesKcal: Double
    let proteinG: Double
    let carbsG: Double
    let fatG: Double
}

/// 识别可信度：后端只会返回 high、medium、low 三种
enum Confidence: String, Codable, Hashable {
    case high, medium, low

    /// 显示在界面上的文字
    var label: String {
        switch self {
        case .high: "把握高"
        case .medium: "把握中"
        case .low: "请核对"
        }
    }
}

extension Double {
    /// 最多保留 1 位小数，例如 24.0 → "24"，3.86 → "3.9"
    var oneDecimal: String { formatted(.number.precision(.fractionLength(0...1))) }

    /// 取整，例如 174.6 → "175"
    var noDecimal: String { formatted(.number.precision(.fractionLength(0))) }
}
