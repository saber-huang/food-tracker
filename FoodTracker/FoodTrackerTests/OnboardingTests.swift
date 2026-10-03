//
//  OnboardingTests.swift
//  FoodTrackerTests
//
//  引导流程的测试（界面以外的部分）：
//  - 进度存档：存了能读回来；接着填时从哪一步开始（前面有没填好的就退回去）
//  - 草稿的快照：身高、体重换了单位也能准确填回去
//  - 饮食偏好：「无特别偏好」和其他选项互斥；写进「偏好和忌口」的内容；跳过时不清空已有的内容
//  - 每日目标用的是原来的公式（CASE 4），改资料后目标跟着变（CASE 9）
//  用单独的一份设置，不会动模拟器里 App 的真实数据。
//

import Foundation
import Testing

@testable import FoodTracker

@MainActor
@Suite("引导流程")
struct OnboardingTests {
    func makeDefaults() throws -> UserDefaults {
        try #require(UserDefaults(suiteName: "OnboardingTests-\(UUID().uuidString)"))
    }

    /// 填好前四步的草稿（公制）
    func filledDraft(goal: Goal = .loseFat) -> ProfileDraft {
        let draft = ProfileDraft(units: .metric)
        draft.goal = goal
        draft.sex = .female
        draft.ageText = "30"
        draft.heightText = "165"
        draft.weightText = "62"
        draft.activity = .light
        return draft
    }

    // MARK: - 进度存档

    @Test("进度存了能读回来；删掉以后没有了；读不懂的数据当作没有")
    func progressRoundTrip() throws {
        let defaults = try makeDefaults()
        #expect(OnboardingProgress.load(from: defaults) == nil)

        var choices = PreferenceChoices()
        choices.toggle(.light)
        choices.allergies = "花生"
        choices.showsAllergies = true
        let progress = OnboardingProgress(
            step: .preferences, profile: filledDraft().snapshot, preferences: choices, goalWasAdjusted: true)
        progress.save(to: defaults)
        #expect(OnboardingProgress.load(from: defaults) == progress)

        OnboardingProgress.clear(from: defaults)
        #expect(OnboardingProgress.load(from: defaults) == nil)

        defaults.set(Data("坏数据".utf8), forKey: OnboardingProgress.key)
        #expect(OnboardingProgress.load(from: defaults) == nil)
    }

    @Test("接着填：一般回到上次那一步；前面有没填好的，退回到第一个没填好的（CASE 2）")
    func resumeStep() {
        typealias P = OnboardingProgress
        #expect(P.resumeStep(saved: .welcome, goalChosen: false, basicInfoValid: false, activityChosen: false) == .welcome)
        #expect(P.resumeStep(saved: .basicInfo, goalChosen: true, basicInfoValid: false, activityChosen: false) == .basicInfo)
        #expect(P.resumeStep(saved: .preferences, goalChosen: true, basicInfoValid: true, activityChosen: true) == .preferences)
        #expect(P.resumeStep(saved: .result, goalChosen: true, basicInfoValid: true, activityChosen: true) == .result)
        // 存档里的资料不完整：退回去补
        #expect(P.resumeStep(saved: .result, goalChosen: true, basicInfoValid: false, activityChosen: true) == .basicInfo)
        #expect(P.resumeStep(saved: .activity, goalChosen: false, basicInfoValid: true, activityChosen: false) == .goal)
        #expect(P.resumeStep(saved: .preferences, goalChosen: true, basicInfoValid: true, activityChosen: false) == .activity)
    }

    @Test("草稿的快照：换了单位也能准确填回去，没填的还是空的")
    func draftSnapshot() {
        let draft = filledDraft()
        let snapshot = draft.snapshot
        #expect(snapshot.heightCm == 165 && snapshot.weightKg == 62 && snapshot.ageText == "30")

        // 下次打开时手机设成了英制：输入框显示英尺、磅，但数值和原来一样（不会因为来回换算变成 164.9）
        let restored = ProfileDraft(snapshot: snapshot, units: .imperial)
        #expect(restored.heightCm == 165)
        #expect(restored.weightKg == 62)
        #expect(restored.goal == .loseFat && restored.activity == .light && restored.sex == .female)
        #expect(restored.bodyInfo == draft.bodyInfo)

        // 只填了一半：没填的保持空白
        let partial = ProfileDraft(snapshot: ProfileDraftSnapshot(ageText: "28", goal: .maintain), units: .metric)
        #expect(partial.heightText.isEmpty && partial.weightText.isEmpty && partial.activity == nil)
        #expect(!partial.isBasicInfoValid)
    }

    // MARK: - 饮食偏好

    @Test("「无特别偏好」和其他选项不能同时选；再点一次取消")
    func preferenceToggle() {
        var choices = PreferenceChoices()
        choices.toggle(.chinese)
        choices.toggle(.light)
        #expect(choices.tags == [.chinese, .light])
        choices.toggle(.noPreference)
        #expect(choices.tags == [.noPreference])
        choices.toggle(.highProtein)
        #expect(choices.tags == [.highProtein])
        choices.toggle(.highProtein)
        #expect(choices.tags.isEmpty)
    }

    @Test("写进「饮食偏好」的文字按选项的顺序用逗号连起来；「简单快手」变成 15 分钟")
    func preferenceText() {
        var choices = PreferenceChoices()
        for tag in [FoodPreferenceTag.highProtein, .quick, .light, .chinese] {
            choices.toggle(tag)
        }
        let zh = choices.preferenceText(language: .zh)
        let titles = [FoodPreferenceTag.chinese, .light, .highProtein].map(\.title)
        #expect(zh == titles.joined(separator: "，"))
        #expect(!zh.contains(FoodPreferenceTag.quick.title))
        #expect(choices.preferenceText(language: .en) == titles.joined(separator: ", "))
        // 能被「偏好和忌口」拆回成一项一项
        #expect(zh.asTermList == titles)

        choices.toggle(.noPreference)
        #expect(choices.preferenceText().isEmpty)
    }

    @Test("保存偏好：写进「偏好和忌口」；没选、跳过时不清空已有的内容")
    func preferenceSave() throws {
        let defaults = try makeDefaults()
        var choices = PreferenceChoices()
        choices.toggle(.light)
        choices.toggle(.quick)
        choices.allergies = "  花生、虾 \n"
        choices.save(to: defaults, language: .zh)
        #expect(defaults.string(forKey: RecipePrefKeys.preferences) == FoodPreferenceTag.light.title)
        #expect(defaults.string(forKey: RecipePrefKeys.allergies) == "花生、虾")
        #expect(defaults.integer(forKey: RecipePrefKeys.cookingMinutes) == PreferenceChoices.quickCookingMinutes)
        #expect(RecipePreferencesView.cookingOptions.contains(PreferenceChoices.quickCookingMinutes))

        // 跳过（什么都没选）：原来的内容保持不变
        PreferenceChoices().save(to: defaults, language: .zh)
        #expect(defaults.string(forKey: RecipePrefKeys.preferences) == FoodPreferenceTag.light.title)
        #expect(defaults.string(forKey: RecipePrefKeys.allergies) == "花生、虾")
    }

    // MARK: - 每日目标

    @Test("引导算出的目标就是原来的公式；保存的资料和填的一样（CASE 1、4）")
    func targetsUseExistingFormula() throws {
        let draft = filledDraft(goal: .loseFat)
        let bodyInfo = try #require(draft.bodyInfo)
        let profile = UserProfile(body: bodyInfo)
        #expect(profile.bodyInfo == bodyInfo)
        #expect(profile.targets == NutritionCalculator.targets(for: bodyInfo))
        // 减脂：比每日总消耗少
        #expect(profile.targets.calories < profile.targets.tdee)
    }

    @Test("不适合减脂的人选了减脂：资料填完后不能直接用，要换成维持")
    func fatLossRestriction() {
        let draft = filledDraft(goal: .loseFat)
        draft.weightText = "45"  // 165 厘米、45 公斤：BMI 约 16.5，偏轻
        #expect(draft.isBasicInfoValid)
        #expect(draft.fatLossRestriction != nil)
        #expect(draft.bodyInfo == nil)  // 还是减脂时算不出目标
        draft.goal = .maintain
        #expect(draft.bodyInfo != nil)
    }

    @Test("改了资料，目标重新计算（CASE 9）")
    func editingRecalculates() throws {
        let profile = UserProfile(body: try #require(filledDraft(goal: .maintain).bodyInfo))
        let before = profile.targets
        var changed = profile.bodyInfo
        changed.activity = .active
        changed.goal = .gainMuscle
        profile.update(with: changed)
        #expect(profile.targets == NutritionCalculator.targets(for: changed))
        #expect(profile.targets.calories > before.calories)
    }

    @Test("年龄只能填 18～80 岁")
    func ageLimit() {
        let draft = filledDraft()
        draft.ageText = "17"
        #expect(!draft.isBasicInfoValid)
        draft.ageText = "81"
        #expect(!draft.isBasicInfoValid)
        draft.ageText = "18"
        #expect(draft.isBasicInfoValid)
    }
}
