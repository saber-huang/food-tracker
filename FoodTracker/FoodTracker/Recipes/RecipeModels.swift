//
//  RecipeModels.swift
//  FoodTracker
//
//  食谱功能用到的数据格式，和 backend/recipes_ai.py 里的定义一一对应。
//

import Foundation

/// 哪一餐
nonisolated enum MealSlot: String, Codable, CaseIterable, Identifiable {
    case breakfast, lunch, dinner

    var id: String { rawValue }

    var title: String {
        switch self {
        case .breakfast: "早餐"
        case .lunch: "午餐"
        case .dinner: "晚餐"
        }
    }

    var systemImage: String {
        switch self {
        case .breakfast: "sunrise"
        case .lunch: "sun.max"
        case .dinner: "moon.stars"
        }
    }
}

/// 一种食材和用量
struct Ingredient: Codable, Hashable {
    let name: String
    let grams: Double
}

/// 一道菜（一餐）
struct Recipe: Codable, Hashable, Identifiable {
    let meal: MealSlot
    let name: String
    let ingredients: [Ingredient]
    let steps: [String]
    let cookingMinutes: Int
    let caloriesKcal: Double
    let proteinG: Double
    let carbsG: Double
    let fatG: Double

    var id: String { "\(meal.rawValue)-\(name)" }
}

/// 后端 /recipes 返回的内容
struct RecipesResult: Codable {
    let recipes: [Recipe]
    let model: String
    let fromCache: Bool
    let remainingToday: Int
}

/// 发给后端 /recipes 的请求
struct RecipeRequest: Encodable {
    let goal: String  // loseFat / maintain / gainMuscle
    let dailyCalories: Double
    let dailyProteinG: Double
    let dailyCarbsG: Double
    let dailyFatG: Double
    let preferences: String
    let allergies: [String]
    let dislikes: [String]
    let maxCookingMinutes: Int
    let meals: [MealSlot]
    let excludeNames: [String]
    let lang: String
}

extension RecipeRequest {
    /// 组装发给后端的请求。「食谱」页和「推荐下一餐」都用它，两边发出去的格式保证一样。
    /// targets 是「每日目标」：食谱页直接用用户的每日目标；推荐下一餐用按剩余热量缩小后的目标
    static func make(
        goal: Goal, targets: RequestTargets, preferencesText: String, allergiesText: String, dislikesText: String,
        cookingMinutes: Int, meals: [MealSlot], excludeNames: [String]
    ) -> RecipeRequest {
        RecipeRequest(
            goal: goal.rawValue,
            dailyCalories: targets.calories,
            dailyProteinG: targets.proteinG,
            dailyCarbsG: targets.carbsG,
            dailyFatG: targets.fatG,
            preferences: preferencesText.trimmingCharacters(in: .whitespacesAndNewlines),
            allergies: allergiesText.asTermList,
            dislikes: dislikesText.asTermList,
            maxCookingMinutes: cookingMinutes,
            meals: meals,
            excludeNames: excludeNames,
            lang: "zh"  // 界面目前只有中文；以后做英文版时再跟随手机语言
        )
    }
}

/// 后端 /quota 返回的内容：今天还能用几次
struct Quota: Codable {
    let analyzeRemaining: Int
    let analyzePerDay: Int
    let recipesRemaining: Int
    let recipesPerDay: Int
}
