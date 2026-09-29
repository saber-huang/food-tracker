//
//  ProfileDraft.swift
//  FoodTracker
//
//  填写资料时的「草稿」：用户边填、App 边检查，全部填对后才保存到 UserProfile。
//  引导页和「编辑资料」页共用它。
//

import Foundation
import Observation

@Observable
final class ProfileDraft {
    var sex: Sex = .male
    // 输入框里的文字。先存文字，再转成数字，这样用户输到一半时也不会出错
    var ageText = ""
    var heightText = ""
    var weightText = ""
    // 还没选时是 nil
    var activity: ActivityLevel?
    var goal: Goal?

    /// 新用户：什么都没填
    init() {}

    /// 编辑已有资料：先把原来的数据填进来
    init(from body: BodyInfo) {
        sex = body.sex
        ageText = String(body.age)
        heightText = Self.text(from: body.heightCm)
        weightText = Self.text(from: body.weightKg)
        activity = body.activity
        goal = body.goal
    }

    // MARK: 把文字转成数字（转不了就是 nil）

    var age: Int? { Int(ageText.trimmingCharacters(in: .whitespaces)) }
    var heightCm: Double? { Self.number(from: heightText) }
    var weightKg: Double? { Self.number(from: weightText) }

    // MARK: 检查结果（nil 表示没问题）

    var ageError: String? { ProfileValidator.ageError(age) }
    var heightError: String? { ProfileValidator.heightError(heightCm) }
    var weightError: String? { ProfileValidator.weightError(weightKg) }

    /// 性别、年龄、身高、体重是否都填对了
    var isBasicInfoValid: Bool {
        ageError == nil && heightError == nil && weightError == nil
    }

    /// 体重是否偏轻（BMI 低于 18.5）。偏轻时不允许选「减脂」
    var isUnderweight: Bool {
        guard let heightCm, let weightKg, heightError == nil, weightError == nil else { return false }
        return ProfileValidator.isUnderweight(heightCm: heightCm, weightKg: weightKg)
    }

    /// 偏轻时给用户看的说明
    var underweightMessage: String? {
        guard let heightCm, let weightKg, heightError == nil, weightError == nil else { return nil }
        return ProfileValidator.underweightMessage(heightCm: heightCm, weightKg: weightKg)
    }

    /// 全部填好、填对时，得到可以用来计算和保存的数据；否则是 nil
    var bodyInfo: BodyInfo? {
        guard isBasicInfoValid, let age, let heightCm, let weightKg, let activity, let goal else { return nil }
        // 偏轻的人选了减脂（比如编辑资料时体重改小了），要先换目标才能保存
        if goal == .loseFat && isUnderweight { return nil }
        return BodyInfo(sex: sex, age: age, heightCm: heightCm, weightKg: weightKg, activity: activity, goal: goal)
    }

    // MARK: 小工具

    /// 文字转数字。有些地区的键盘用逗号当小数点，这里一并支持
    private static func number(from text: String) -> Double? {
        let cleaned = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard let value = Double(cleaned), value.isFinite else { return nil }
        return value
    }

    /// 数字转文字：175.0 → "175"，62.5 → "62.5"
    private static func text(from value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(value)
    }
}
