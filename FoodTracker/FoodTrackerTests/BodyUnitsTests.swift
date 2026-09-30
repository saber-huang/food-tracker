//
//  BodyUnitsTests.swift
//  FoodTrackerTests
//
//  身高体重单位的测试：换算对不对、默认单位跟着地区、英制填写资料能正确保存，
//  以及换算来回的四舍五入不会让没改过的资料「看起来改过」。
//  测试用中文运行，所以显示文字是中文（英制写成「英尺」「磅」）。
//

import Foundation
import Testing

@testable import FoodTracker

private func isClose(_ a: Double?, _ b: Double, tolerance: Double = 0.01) -> Bool {
    guard let a else { return false }
    return abs(a - b) <= tolerance
}

@Suite("身高体重单位")
struct BodyUnitsTests {
    @Test("换算：英寸、磅用国际约定的准确值")
    func conversions() {
        #expect(isClose(BodyUnits.cm(feet: 5, inches: 7), 170.18))
        #expect(isClose(BodyUnits.cm(feet: 6, inches: 0), 182.88))
        #expect(isClose(BodyUnits.kg(pounds: 150), 68.039))
        #expect(isClose(BodyUnits.pounds(kg: 60), 132.277))
        #expect(isClose(BodyUnits.kg(pounds: BodyUnits.pounds(kg: 72.5)), 72.5, tolerance: 1e-9))
    }

    @Test("厘米 → 几英尺几英寸：英寸 1 位小数，满 12 英寸进位")
    func feetAndInches() {
        #expect(BodyUnits.feetAndInches(cm: 170) == (5, 6.9))
        #expect(BodyUnits.feetAndInches(cm: 182.88) == (6, 0))
        // 71.96 英寸四舍五入是 72.0，要写成 6 英尺 0 英寸，不能是 5 英尺 12 英寸
        #expect(BodyUnits.feetAndInches(cm: 71.96 * 2.54) == (6, 0))
        #expect(BodyUnits.heightTexts(cm: 170.18) == ("5", "7"))
        #expect(BodyUnits.poundsText(kg: 68.0388555) == "150")
    }

    @Test("「我的」页显示：英制身高四舍五入到整英寸，体重 1 位小数")
    func display() {
        #expect(BodyUnits.heightDisplay(cm: 165, units: .imperial) == "5 英尺 5 英寸")
        #expect(BodyUnits.heightDisplay(cm: 182.88, units: .imperial) == "6 英尺 0 英寸")
        #expect(BodyUnits.weightDisplay(kg: 60, units: .imperial) == "132.3 磅")
        #expect(BodyUnits.heightDisplay(cm: 165, units: .metric) == "165 厘米")
        #expect(BodyUnits.weightDisplay(kg: 60.5, units: .metric) == "60.5 公斤")
    }

    @Test("默认单位跟着地区：美国用英制，其他地区用公制；选过就用选的")
    func defaults() {
        #expect(UnitSystem.regionDefault(for: Locale(identifier: "en_US")) == .imperial)
        #expect(UnitSystem.regionDefault(for: Locale(identifier: "zh_CN")) == .metric)
        #expect(UnitSystem.regionDefault(for: Locale(identifier: "en_GB")) == .metric)
        #expect(UnitSystem.regionDefault(for: Locale(identifier: "en_CA")) == .metric)
        let name = "BodyUnitsTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        #expect(UnitSystem.current(in: defaults) == UnitSystem.regionDefault())
        defaults.set(UnitSystem.imperial.rawValue, forKey: UnitSystem.key)
        #expect(UnitSystem.current(in: defaults) == .imperial)
        defaults.set(UnitSystem.metric.rawValue, forKey: UnitSystem.key)
        #expect(UnitSystem.current(in: defaults) == .metric)
    }

    @Test("已经在用的人（有资料、没选过单位）继续用公制；新用户按地区；只判断一次")
    func existingUsersKeepMetric() {
        func freshDefaults() -> UserDefaults {
            let name = "BodyUnitsTests-\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: name)!
            defaults.removePersistentDomain(forName: name)
            return defaults
        }
        // 老用户：有资料 → 定成公制
        let existing = freshDefaults()
        UnitSystem.keepMetricForExistingUser(hasProfile: true, defaults: existing)
        #expect(UnitSystem.current(in: existing) == .metric)
        // 老用户自己选过英制 → 不动
        let chose = freshDefaults()
        chose.set(UnitSystem.imperial.rawValue, forKey: UnitSystem.key)
        UnitSystem.keepMetricForExistingUser(hasProfile: true, defaults: chose)
        #expect(UnitSystem.current(in: chose) == .imperial)
        // 新用户：第一次打开时没有资料 → 按地区；以后建好资料再打开也不会被改成公制
        let newUser = freshDefaults()
        UnitSystem.keepMetricForExistingUser(hasProfile: false, defaults: newUser)
        UnitSystem.keepMetricForExistingUser(hasProfile: true, defaults: newUser)
        #expect(newUser.string(forKey: UnitSystem.key) == nil)
        #expect(UnitSystem.current(in: newUser) == UnitSystem.regionDefault())
    }

    @Test("英制下的检查提示用英尺、磅；范围往里取整，按提示填一定能通过")
    func imperialMessages() {
        #expect(ProfileValidator.heightError(nil, units: .imperial)?.contains("英尺") == true)
        #expect(ProfileValidator.weightError(nil, units: .imperial)?.contains("磅") == true)
        #expect(ProfileValidator.heightError(100, units: .imperial) == "身高需要在 4 英尺 0 英寸～7 英尺 6 英寸之间")
        #expect(ProfileValidator.weightError(20, units: .imperial) == "体重需要在 67～551 磅之间")
        let (low, high) = ProfileValidator.imperialHeightBounds
        #expect(ProfileValidator.heightError(BodyUnits.cm(feet: Double(low.feet), inches: Double(low.inches)), units: .imperial) == nil)
        #expect(ProfileValidator.heightError(BodyUnits.cm(feet: Double(high.feet), inches: Double(high.inches)), units: .imperial) == nil)
        let pounds = ProfileValidator.imperialWeightBounds
        #expect(ProfileValidator.weightError(BodyUnits.kg(pounds: Double(pounds.low)), units: .imperial) == nil)
        #expect(ProfileValidator.weightError(BodyUnits.kg(pounds: Double(pounds.high)), units: .imperial) == nil)
        // 组合不合理、BMI 很低时的提醒也说英制单位
        #expect(ProfileValidator.plausibilityError(heightCm: 180, weightKg: 30, units: .imperial)?.contains("磅") == true)
        #expect(ProfileValidator.unitWarning(heightCm: 175, weightKg: 45, units: .imperial)?.contains("英尺和英寸") == true)
        // 公制不变
        #expect(ProfileValidator.heightError(100) == "身高需要在 120～230 厘米之间")
    }
}

// ProfileDraft 只能在主线程使用
@MainActor
@Suite("英制填写资料")
struct ImperialDraftTests {
    let body = BodyInfo(sex: .female, age: 28, heightCm: 165, weightKg: 60, activity: .light, goal: .loseFat)

    @Test("英制填写：5 英尺 7 英寸、150 磅，保存成厘米和公斤")
    func imperialEntry() throws {
        let draft = ProfileDraft(units: .imperial)
        draft.sex = .male
        draft.ageText = "30"
        draft.feetText = "5"
        draft.inchesText = "7"
        draft.weightText = "150"
        draft.activity = .moderate
        draft.goal = .maintain
        let info = try #require(draft.bodyInfo)
        #expect(isClose(info.heightCm, 170.18))
        #expect(isClose(info.weightKg, 68.039))
        // 英寸不填按 0 算
        draft.inchesText = ""
        #expect(isClose(draft.heightCm, 152.4))
        // 英尺没填就算没填身高
        draft.feetText = ""
        #expect(draft.heightCm == nil)
        #expect(draft.heightError?.contains("英尺") == true)
    }

    @Test("用英制打开已有资料、什么都不改，保存的还是原来的准确数值（不会因为四舍五入算成修改）")
    func noDriftWhenUntouched() {
        for units in UnitSystem.allCases {
            #expect(ProfileDraft(from: body, units: units).bodyInfo == body)
        }
        let odd = BodyInfo(sex: .male, age: 40, heightCm: 170.17999999999998, weightKg: 68.0388555, activity: .active, goal: .gainMuscle)
        #expect(ProfileDraft(from: odd, units: .imperial).bodyInfo == odd)
        #expect(ProfileDraft(from: odd, units: .metric).bodyInfo == odd)
    }

    @Test("来回切换单位也不改数值；改了输入框才按新数字换算")
    func switchingUnits() {
        let draft = ProfileDraft(from: body, units: .metric)
        draft.switchUnits(to: .imperial)
        #expect(draft.feetText == "5" && draft.inchesText == "5")
        #expect(draft.weightText == "132.3")
        #expect(draft.bodyInfo == body)
        draft.switchUnits(to: .metric)
        #expect(draft.heightText == "165" && draft.weightText == "60")
        #expect(draft.bodyInfo == body)
        // 在英制下改体重：按新填的磅数换算
        draft.switchUnits(to: .imperial)
        draft.weightText = "140"
        #expect(isClose(draft.weightKg, 63.503))
        #expect(draft.bodyInfo != body)
        // 没填或填错的，切换后是空的
        draft.weightText = "abc"
        draft.switchUnits(to: .metric)
        #expect(draft.weightText.isEmpty)
    }
}
