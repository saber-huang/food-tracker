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

/// 一种食物。
/// nonisolated：纯数据，不需要限定在主线程，计算模块和单元测试都能直接用（和 NutritionCalculator 里的类型一样）
nonisolated struct FoodItem: Codable, Hashable {
    let name: String  // 名称
    let weightG: Double  // 估算重量（克）
    let caloriesKcal: Double  // 热量（千卡）
    let proteinG: Double  // 蛋白质（克）
    let carbsG: Double  // 碳水化合物（克）
    let fatG: Double  // 脂肪（克）
    let confidence: Confidence  // 识别可信度
}

/// 整餐合计
nonisolated struct MealTotal: Codable, Hashable {
    let weightG: Double
    let caloriesKcal: Double
    let proteinG: Double
    let carbsG: Double
    let fatG: Double
}

/// 饭后拍剩下的（/leftovers）返回的结果，和 backend/leftovers_ai.py 里的 LeftoversResult 一一对应
struct LeftoversResponse: Codable, Hashable {
    let isLeftoverPhoto: Bool  // 照片里是不是吃剩的食物（或吃完的空碗空盘）
    let message: String  // 给用户看的一句话：「米饭吃完了，宫保鸡丁剩了大约四分之一」
    let eaten: [Double]  // 和发过去的清单一一对应：每样吃掉了几成（0～1）；照片不对时是空的
    let model: String
    let remainingToday: Int?  // 今天还能拍照识别几次（和拍照识别共用次数）
}

/// 发给 /leftovers 的清单里的一样：名字和原来大约多少克（不知道重量就不写）
nonisolated struct LeftoverServedItem: Codable, Hashable {
    let name: String
    let weightG: Double?
}

/// 识别可信度：后端只会返回 high、medium、low 三种
/// AI 对一项的把握程度。界面上不直接显示（不展示内部的把握程度），只在 low 时提示「份量不确定」
nonisolated enum Confidence: String, Codable, Hashable {
    case high, medium, low
}

// 只是把数字变成文字，哪里都能用（不限主线程）
nonisolated extension Double {
    /// 最多保留 1 位小数，例如 24.0 → "24"，3.86 → "3.9"
    var oneDecimal: String { formatted(.number.precision(.fractionLength(0...1))) }

    /// 取整，例如 174.6 → "175"
    var noDecimal: String { formatted(.number.precision(.fractionLength(0))) }
}
