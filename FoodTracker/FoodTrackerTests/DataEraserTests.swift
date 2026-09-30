//
//  DataEraserTests.swift
//  FoodTrackerTests
//
//  「删除所有数据」的测试：资料、饮食记录和设置都删干净。
//  用内存里的临时数据库和单独的一份设置，不会删掉模拟器里 App 的真实数据。
//

import Foundation
import SwiftData
import Testing

@testable import FoodTracker

// SwiftData 的数据只能在主线程使用
@MainActor
@Suite("删除所有数据")
struct DataEraserTests {
    @Test("资料、饮食记录和设置都删掉")
    func eraseAll() throws {
        // isStoredInMemoryOnly 必须是 true：测试是在 App 里面跑的，否则会删掉模拟器里的真实数据
        let container = try ModelContainer(
            for: UserProfile.self, FoodEntry.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext
        context.insert(
            UserProfile(
                body: BodyInfo(sex: .female, age: 28, heightCm: 165, weightKg: 60, activity: .light, goal: .loseFat)))
        for name in ["米饭", "鸡蛋"] {
            context.insert(
                FoodEntry(
                    dayKey: 20260930, meal: .lunch, name: name, weightG: 100,
                    values: NutrientValues(caloriesKcal: 100), source: .manual))
        }
        try context.save()

        let domain = "DataEraserTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: domain))
        defaults.set("all", forKey: HintKeys.level)
        defaults.set(AIConsent.currentVersion, forKey: AIConsent.key)

        try DataEraser.eraseAll(context: context, defaults: defaults, defaultsDomain: domain)

        #expect(try context.fetchCount(FetchDescriptor<UserProfile>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<FoodEntry>()) == 0)
        #expect(defaults.string(forKey: HintKeys.level) == nil)
        // AI 功能的同意也一起清掉：下次用之前会重新询问
        #expect(!AIConsent.isGranted(in: defaults))
    }
}
