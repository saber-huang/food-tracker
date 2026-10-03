//
//  OnboardingProgress.swift
//  FoodTracker
//
//  引导流程的「进度存档」：填到一半退出 App（或者被系统关掉），下次打开从上次那一步接着填，填过的内容都还在。
//  存在手机本地（UserDefaults），只有几个选项和数字；保存资料（点「记录第一餐」或「稍后再说」）后就删掉。
//  还有引导第 5 步「饮食偏好」的选项和它们怎么写进「偏好和忌口」。
//  这个文件只做数据和规则，不涉及界面，可以单独写单元测试（FoodTrackerTests/OnboardingTests.swift）。
//

import Foundation

/// 引导的每一步（rawValue 就是顺序）
nonisolated enum OnboardingStep: Int, CaseIterable, Codable {
    case welcome, goal, basicInfo, activity, preferences, result

    /// 欢迎页之后一共几步（进度条用：「第 2 步，共 5 步」）
    static let countedSteps = allCases.count - 1
}

// MARK: - 饮食偏好（第 5 步，可以跳过）

/// 几个快捷选项。选了的写进「偏好和忌口」，生成食谱时会参考
nonisolated enum FoodPreferenceTag: String, CaseIterable, Codable {
    case noPreference, chinese, light, highProtein, quick, vegetarian

    var title: String {
        switch self {
        case .noPreference: String(localized: "无特别偏好")
        case .chinese: String(localized: "中式为主")
        case .light: String(localized: "清淡少油")
        case .highProtein: String(localized: "高蛋白")
        case .quick: String(localized: "简单快手")
        case .vegetarian: String(localized: "素食")
        }
    }
}

/// 第 5 步选了什么
nonisolated struct PreferenceChoices: Codable, Equatable {
    var tags: Set<FoodPreferenceTag> = []
    var allergies = ""
    /// 点过「添加过敏食材」：输入框展开着
    var showsAllergies = false

    /// 「简单快手」对应的烹饪时间（分钟）
    static let quickCookingMinutes = 15

    /// 点了一个选项：再点一次取消；「无特别偏好」和其他选项不能同时选
    mutating func toggle(_ tag: FoodPreferenceTag) {
        if tags.contains(tag) {
            tags.remove(tag)
        } else if tag == .noPreference {
            tags = [.noPreference]
        } else {
            tags.remove(.noPreference)
            tags.insert(tag)
        }
    }

    /// 写进「饮食偏好」的文字：按选项的顺序用逗号连起来（「清淡少油，高蛋白」）。
    /// 「无特别偏好」不写；「简单快手」改的是烹饪时间（15 分钟），也不写进文字
    func preferenceText(language: AppLanguage = .current) -> String {
        FoodPreferenceTag.allCases
            .filter { tags.contains($0) && $0 != .noPreference && $0 != .quick }
            .map(\.title)
            .joined(separator: language == .zh ? "，" : ", ")
    }

    /// 保存资料时写进「偏好和忌口」（和「我的」→「偏好和忌口」是同一份）。
    /// 没选、没填的不写：不会把已经有的内容清空
    func save(to defaults: UserDefaults = .standard, language: AppLanguage = .current) {
        let text = preferenceText(language: language)
        if !text.isEmpty {
            defaults.set(text, forKey: RecipePrefKeys.preferences)
        }
        let allergyText = allergies.trimmingCharacters(in: .whitespacesAndNewlines)
        if !allergyText.isEmpty {
            defaults.set(allergyText, forKey: RecipePrefKeys.allergies)
        }
        if tags.contains(.quick) {
            defaults.set(Self.quickCookingMinutes, forKey: RecipePrefKeys.cookingMinutes)
        }
    }
}

// MARK: - 进度存档

nonisolated struct OnboardingProgress: Codable, Equatable {
    var step: OnboardingStep = .welcome
    var profile = ProfileDraftSnapshot()
    var preferences = PreferenceChoices()
    /// 先选了「减脂」，填完资料发现不适合减脂，自动换成了「维持」：结果页说明一下原因
    var goalWasAdjusted = false

    static let key = "onboardingDraft"

    /// 读出上次的进度；没有（或者读不懂）就是 nil，从头开始
    static func load(from defaults: UserDefaults = .standard) -> OnboardingProgress? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(OnboardingProgress.self, from: data)
    }

    func save(to defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.key)
    }

    static func clear(from defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key)
    }

    /// 接着填时从哪一步开始：一般就是上次那一步；
    /// 前面有没填好的（比如存档里的年龄现在不合规了），退回到第一个没填好的那一步
    static func resumeStep(saved: OnboardingStep, goalChosen: Bool, basicInfoValid: Bool, activityChosen: Bool) -> OnboardingStep {
        let firstIncomplete: OnboardingStep? =
            if !goalChosen { .goal } else if !basicInfoValid { .basicInfo } else if !activityChosen { .activity } else { nil }
        if let firstIncomplete, saved.rawValue > firstIncomplete.rawValue {
            return firstIncomplete
        }
        return saved
    }
}
