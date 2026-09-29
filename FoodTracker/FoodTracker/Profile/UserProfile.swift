//
//  UserProfile.swift
//  FoodTracker
//
//  用户的个人资料，用 SwiftData 保存在手机本地（不上传到服务器）。
//  SwiftData 是苹果自带的数据库：类前面加上 @Model，它就能自动保存和读取。
//

import Foundation
import SwiftData

@Model
final class UserProfile {
    // 性别、活动量、目标这类「选项」存成文字（比如 "male"），
    // 读取时再转换回对应的类型。存文字最稳妥，以后调整选项也方便。
    var sexRaw: String
    var age: Int  // 岁
    var heightCm: Double  // 厘米
    var weightKg: Double  // 公斤
    var activityRaw: String
    var goalRaw: String
    var updatedAt: Date  // 最后修改时间

    init(body: BodyInfo) {
        sexRaw = body.sex.rawValue
        age = body.age
        heightCm = body.heightCm
        weightKg = body.weightKg
        activityRaw = body.activity.rawValue
        goalRaw = body.goal.rawValue
        updatedAt = .now
    }

    /// 转换成计算模块需要的格式
    var bodyInfo: BodyInfo {
        BodyInfo(
            sex: Sex(rawValue: sexRaw) ?? .male,
            age: age,
            heightCm: heightCm,
            weightKg: weightKg,
            activity: ActivityLevel(rawValue: activityRaw) ?? .moderate,
            goal: Goal(rawValue: goalRaw) ?? .maintain
        )
    }

    /// 每日目标：每次都根据最新的资料现算，所以资料一改，目标就自动更新
    var targets: DailyTargets {
        NutritionCalculator.targets(for: bodyInfo)
    }

    /// 用新填的资料覆盖旧资料
    func update(with body: BodyInfo) {
        sexRaw = body.sex.rawValue
        age = body.age
        heightCm = body.heightCm
        weightKg = body.weightKg
        activityRaw = body.activity.rawValue
        goalRaw = body.goal.rawValue
        updatedAt = .now
    }
}
