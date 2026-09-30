//
//  MealType.swift
//  FoodTracker
//
//  饮食记录里的餐次（早餐、午餐、晚餐、加餐）和记录的来源。
//
//  注意和食谱的 MealSlot 区分：
//  - MealSlot：食谱后端认识的 3 餐（早、午、晚），后端不接受「加餐」
//  - MealType：饮食记录保存的 4 餐，加餐单独算一类
//  两者之间只通过 MealType(slot:) 转换。
//
//  这里的英文 rawValue 会原样存进手机的数据库，以后不能改名。
//

import Foundation

/// 饮食记录的餐次
nonisolated enum MealType: String, CaseIterable, Codable, Identifiable {
    case breakfast, lunch, dinner, snack

    var id: String { rawValue }

    var title: String {
        switch self {
        case .breakfast: String(localized: "早餐")
        case .lunch: String(localized: "午餐")
        case .dinner: String(localized: "晚餐")
        case .snack: String(localized: "加餐")
        }
    }

    /// 餐次旁边的小图标（前三个和食谱页一样）
    var systemImage: String {
        switch self {
        case .breakfast: "sunrise"
        case .lunch: "sun.max"
        case .dinner: "moon.stars"
        case .snack: "cup.and.saucer"
        }
    }

    /// 把食谱的餐次换成记录的餐次
    init(slot: MealSlot) {
        switch slot {
        case .breakfast: self = .breakfast
        case .lunch: self = .lunch
        case .dinner: self = .dinner
        }
    }
}

/// 一条记录是怎么来的：拍照识别、手动添加、从食谱记录
nonisolated enum EntrySource: String, Codable {
    case photo, manual, recipe
}
