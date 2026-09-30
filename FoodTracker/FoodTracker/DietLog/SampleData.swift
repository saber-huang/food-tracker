//
//  SampleData.swift
//  FoodTracker
//
//  示例数据：Xcode 右侧的预览画面，以及模拟器里的「调试」菜单会用到。
//  和识别结果页预览里的示例一样：一份米饭配宫保鸡丁。
//

import Foundation
import SwiftData

enum SampleData {
    /// 一次识别结果的示例
    static let analyzeResult = AnalyzeResult(
        isFood: true,
        message: "一份米饭配宫保鸡丁，蛋白质和脂肪都比较充足。",
        items: [
            FoodItem(name: "米饭", weightG: 150, caloriesKcal: 174, proteinG: 3.9, carbsG: 38.1, fatG: 0.5, confidence: .high),
            FoodItem(name: "宫保鸡丁", weightG: 200, caloriesKcal: 398, proteinG: 24.7, carbsG: 14, fatG: 26.9, confidence: .medium),
        ],
        total: MealTotal(weightG: 350, caloriesKcal: 572, proteinG: 28.6, carbsG: 52.1, fatG: 27.4),
        model: "claude-opus-5-5"
    )

    /// 照片里没有食物时的示例
    static let notFoodResult = AnalyzeResult(
        isFood: false,
        message: "照片里是一张桌子，没有看到食物。",
        items: [],
        total: MealTotal(weightG: 0, caloriesKcal: 0, proteinG: 0, carbsG: 0, fatG: 0),
        model: "claude-opus-5-5"
    )

    /// 一道食谱的示例（食材生重合计 373 克）
    static let recipe = Recipe(
        meal: .lunch, name: "清蒸鸡胸肉配西兰花糙米饭",
        ingredients: [
            Ingredient(name: "鸡胸肉", grams: 170), Ingredient(name: "糙米", grams: 45),
            Ingredient(name: "西兰花", grams: 150), Ingredient(name: "橄榄油", grams: 8),
        ],
        steps: ["糙米提前浸泡后蒸熟。", "鸡胸肉切片，用生抽腌 5 分钟后蒸 12 分钟。", "西兰花焯水后快炒 1 分钟。", "装盘即可。"],
        cookingMinutes: 30, caloriesKcal: 590, proteinG: 48, carbsG: 63, fatG: 16
    )

    /// 预览用的个人资料
    static let profile = UserProfile(
        body: BodyInfo(sex: .male, age: 30, heightCm: 178, weightKg: 75, activity: .moderate, goal: .maintain))

    /// 在 day 那天的午餐插入两条示例记录（米饭、宫保鸡丁），和结果页「保存到今日」走同一个函数
    static func insertSampleEntries(into context: ModelContext, day: Date) {
        let dayKey = DayMath.dayKey(for: day)
        FoodEntry.insert(
            analyzeResult.items.map { EditableItem($0, meal: .lunch, dayKey: dayKey) },
            meal: .lunch, dayKey: dayKey, source: .photo, into: context)
    }

    /// 往前 days 天（不含今天）每天插入示例记录：单数天午餐 + 晚餐各一份（1144 千卡），双数天只有午餐（572 千卡）。
    /// 用来在模拟器里看周横条上的圆环
    static func insertRecentDays(into context: ModelContext, today: Date, days: Int = 14) {
        for n in 1...days {
            let dayKey = DayMath.dayKey(for: DayMath.addingDays(-n, to: today))
            let meals: [MealType] = n % 2 == 1 ? [.lunch, .dinner] : [.lunch]
            for meal in meals {
                FoodEntry.insert(
                    analyzeResult.items.map { EditableItem($0, meal: meal, dayKey: dayKey) },
                    meal: meal, dayKey: dayKey, source: .photo, into: context)
            }
        }
    }

    /// 预览用的数据库：只在内存里，关掉预览就没了。已经放好一份资料和今天的两条记录
    static let previewContainer: ModelContainer = {
        let container = try! ModelContainer(
            for: UserProfile.self, FoodEntry.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        container.mainContext.insert(profile)
        insertSampleEntries(into: container.mainContext, day: .now)
        return container
    }()
}
