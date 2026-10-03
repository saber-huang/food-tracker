//
//  ProfileDraft.swift
//  FoodTracker
//
//  填写资料时的「草稿」：用户边填、App 边检查，全部填对后才保存到 UserProfile。
//  引导页和「编辑资料」页共用它。
//
//  身高、体重可以用公制（厘米、公斤）或英制（英尺和英寸、磅）填写，保存时一律换成厘米和公斤。
//  换算来回会有四舍五入：已保存的 170 厘米显示成 5 英尺 6.9 英寸，再换回去是 169.9 厘米。
//  为了不让资料「看起来改过」（改过会影响热量提示），用户没动这几个输入框时，直接用原来的准确数值。
//

import Foundation
import Observation

@Observable
final class ProfileDraft {
    var sex: Sex = .male
    // 输入框里的文字。先存文字，再转成数字，这样用户输到一半时也不会出错
    var ageText = ""
    /// 公制时的身高（厘米）
    var heightText = ""
    /// 英制时的身高：几英尺、几英寸（英寸可以不填，按 0 算）
    var feetText = ""
    var inchesText = ""
    /// 体重：公制时是公斤，英制时是磅
    var weightText = ""
    // 还没选时是 nil
    var activity: ActivityLevel?
    var goal: Goal?
    /// 身高、体重用哪种单位填写（用 switchUnits(to:) 切换）
    private(set) var units: UnitSystem

    /// 填进输入框时的文字和对应的准确数值。输入框里的文字没变，就用准确数值（见文件开头的说明）
    private var heightBaseline: (texts: [String], cm: Double)?
    private var weightBaseline: (text: String, kg: Double)?

    /// 新用户：什么都没填
    init(units: UnitSystem = .metric) {
        self.units = units
    }

    /// 编辑已有资料：先把原来的数据填进来
    init(from body: BodyInfo, units: UnitSystem = .metric) {
        self.units = units
        sex = body.sex
        ageText = String(body.age)
        activity = body.activity
        goal = body.goal
        fillHeight(cm: body.heightCm)
        fillWeight(kg: body.weightKg)
    }

    /// 引导页填到一半退出、再打开时：把上次填的放回来（没填的保持空白）
    init(snapshot: ProfileDraftSnapshot, units: UnitSystem = .metric) {
        self.units = units
        sex = snapshot.sex
        ageText = snapshot.ageText
        activity = snapshot.activity
        goal = snapshot.goal
        if let cm = snapshot.heightCm { fillHeight(cm: cm) }
        if let kg = snapshot.weightKg { fillWeight(kg: kg) }
    }

    /// 现在填了什么（引导页存进度用）。身高、体重存成厘米和公斤：下次打开换了单位也能填回去
    var snapshot: ProfileDraftSnapshot {
        ProfileDraftSnapshot(sex: sex, ageText: ageText, heightCm: heightCm, weightKg: weightKg, activity: activity, goal: goal)
    }

    /// 换一种单位：已经填好的身高、体重换算过去（填错或没填的就清空）
    func switchUnits(to newUnits: UnitSystem) {
        guard newUnits != units else { return }
        let cm = heightCm
        let kg = weightKg
        units = newUnits
        if let cm { fillHeight(cm: cm) } else { clearHeight() }
        if let kg { fillWeight(kg: kg) } else { clearWeight() }
    }

    /// 按现在的单位把身高填进输入框，并记下准确数值
    private func fillHeight(cm: Double) {
        switch units {
        case .metric:
            heightText = BodyUnits.metricText(cm)
            heightBaseline = ([heightText], cm)
        case .imperial:
            (feetText, inchesText) = BodyUnits.heightTexts(cm: cm)
            heightBaseline = ([feetText, inchesText], cm)
        }
    }

    private func fillWeight(kg: Double) {
        weightText = units == .metric ? BodyUnits.metricText(kg) : BodyUnits.poundsText(kg: kg)
        weightBaseline = (weightText, kg)
    }

    private func clearHeight() {
        heightText = ""
        feetText = ""
        inchesText = ""
        heightBaseline = nil
    }

    private func clearWeight() {
        weightText = ""
        weightBaseline = nil
    }

    // MARK: 把文字转成数字（转不了就是 nil）。身高一律换成厘米，体重一律换成公斤

    var age: Int? { Int(ageText.trimmingCharacters(in: .whitespaces)) }

    var heightCm: Double? {
        switch units {
        case .metric:
            if let baseline = heightBaseline, baseline.texts == [heightText] { return baseline.cm }
            return NumberText.number(from: heightText)
        case .imperial:
            if let baseline = heightBaseline, baseline.texts == [feetText, inchesText] { return baseline.cm }
            guard let feet = NumberText.number(from: feetText) else { return nil }
            // 英寸不填按 0 算（正好 6 英尺）；填了但不是数字就算填错
            guard let inches = NumberText.isBlank(inchesText) ? 0 : NumberText.number(from: inchesText) else { return nil }
            return BodyUnits.cm(feet: feet, inches: inches)
        }
    }

    var weightKg: Double? {
        if let baseline = weightBaseline, baseline.text == weightText { return baseline.kg }
        guard let value = NumberText.number(from: weightText) else { return nil }
        return units == .metric ? value : BodyUnits.kg(pounds: value)
    }

    // MARK: 检查结果（nil 表示没问题）。说明里的单位跟着现在的单位

    var ageError: String? { ProfileValidator.ageError(age) }
    var heightError: String? { ProfileValidator.heightError(heightCm, units: units) }
    var weightError: String? { ProfileValidator.weightError(weightKg, units: units) }

    /// 身高、体重各自合规，但组合起来离谱（比如单位填错）
    var plausibilityError: String? {
        guard let heightCm, let weightKg, heightError == nil, weightError == nil else { return nil }
        return ProfileValidator.plausibilityError(heightCm: heightCm, weightKg: weightKg, units: units)
    }

    /// BMI 很高或很低时提醒核对数字和单位（不阻止继续）
    var unitWarning: String? {
        guard let heightCm, let weightKg, heightError == nil, weightError == nil else { return nil }
        return ProfileValidator.unitWarning(heightCm: heightCm, weightKg: weightKg, units: units)
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

/// 草稿里填了什么（引导页的进度存档用，见 OnboardingProgress.swift）。还没填、或者填的不是数字的是 nil
nonisolated struct ProfileDraftSnapshot: Codable, Equatable {
    var sex: Sex = .male
    var ageText = ""
    var heightCm: Double?
    var weightKg: Double?
    var activity: ActivityLevel?
    var goal: Goal?
}
