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
        heightText = NumberText.text(from: body.heightCm)
        weightText = NumberText.text(from: body.weightKg)
        activity = body.activity
        goal = body.goal
    }

    // MARK: 把文字转成数字（转不了就是 nil）

    var age: Int? { Int(ageText.trimmingCharacters(in: .whitespaces)) }
    var heightCm: Double? { NumberText.number(from: heightText) }
    var weightKg: Double? { NumberText.number(from: weightText) }

    // MARK: 检查结果（nil 表示没问题）

    var ageError: String? { ProfileValidator.ageError(age) }
    var heightError: String? { ProfileValidator.heightError(heightCm) }
    var weightError: String? { ProfileValidator.weightError(weightKg) }

    /// 身高、体重各自合规，但组合起来离谱（比如单位填错）
    var plausibilityError: String? {
        guard let heightCm, let weightKg, heightError == nil, weightError == nil else { return nil }
        return ProfileValidator.plausibilityError(heightCm: heightCm, weightKg: weightKg)
    }

    /// BMI 很高时提醒确认单位（不阻止继续）
    var unitWarning: String? {
        guard let heightCm, let weightKg, heightError == nil, weightError == nil else { return nil }
        return ProfileValidator.unitWarning(heightCm: heightCm, weightKg: weightKg)
    }

    /// 性别、年龄、身高、体重是否都填对了
    var isBasicInfoValid: Bool {
        ageError == nil && heightError == nil && weightError == nil && plausibilityError == nil
    }

    /// 不能选「减脂」时的说明；nil 表示可以选
    var fatLossRestriction: String? {
        guard isBasicInfoValid, let age, let heightCm, let weightKg else { return nil }
        return ProfileValidator.fatLossRestriction(age: age, heightCm: heightCm, weightKg: weightKg)
    }

    /// 针对当前选择的温和提示
    var goalNotes: [String] {
        guard let bodyInfo else { return [] }
        return ProfileValidator.goalNotes(for: bodyInfo)
    }

    /// 全部填好、填对时，得到可以用来计算和保存的数据；否则是 nil
    var bodyInfo: BodyInfo? {
        guard isBasicInfoValid, let age, let heightCm, let weightKg, let activity, let goal else { return nil }
        // 不适合减脂的人选了减脂（比如编辑资料时体重改小了），要先换目标才能保存
        if goal == .loseFat && fatLossRestriction != nil { return nil }
        return BodyInfo(sex: sex, age: age, heightCm: heightCm, weightKg: weightKg, activity: activity, goal: goal)
    }
}
