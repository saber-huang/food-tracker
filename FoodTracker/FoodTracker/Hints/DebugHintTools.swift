//
//  DebugHintTools.swift
//  FoodTracker
//
//  「我的」页最下面的开发者工具：在模拟器里一键造出各种热量提示，不用真的吃好几天。
//  整个文件只在模拟器里的测试版编译，装到手机上的版本里没有这些按钮。
//

#if DEBUG && targetEnvironment(simulator)
import SwiftData
import SwiftUI

struct DebugHintSection: View {
    let profile: UserProfile

    @Environment(\.modelContext) private var modelContext
    @AppStorage(HintKeys.debugNowOverride) private var debugNow = 0.0
    @AppStorage(HintKeys.weeklyDismissedWeek) private var weeklyDismissedWeek = ""
    @AppStorage(HintKeys.adjustSnoozedUntil) private var adjustSnoozedUntil = 0.0
    @State private var isConfirmingClear = false

    private let calendar = DayMath.calendar

    var body: some View {
        Section {
            Button(HintCopy.debugSeedNearLimit) { seed(days: [today], kcalPerDay: target * 0.90, meals: [.breakfast, .lunch]) }
            Button(HintCopy.debugSeedOver) { seed(days: [today], kcalPerDay: target + 150, meals: [.breakfast, .lunch, .dinner]) }
            Button(HintCopy.debugSeedStreak) { seed(days: [-1, -2, -3].map(daysAgo), kcalPerDay: target * 1.25, meals: [.breakfast, .lunch]) }
            Button(HintCopy.debugSeedLastWeekOnTarget) { seed(days: lastWeek(5), kcalPerDay: target * 1.03, meals: [.breakfast, .lunch, .dinner]) }
            Button(HintCopy.debugSeedLastWeekAbove) { seed(days: lastWeek(7), kcalPerDay: target * 1.25, meals: [.breakfast, .lunch, .dinner]) }
            Button(HintCopy.debugSeedLastWeekFew) { seed(days: lastWeek(2), kcalPerDay: target, meals: [.breakfast, .lunch]) }
            DatePicker(HintCopy.debugFakeNow, selection: fakeNow, in: fakeRange)
            Button(HintCopy.debugUseRealNow) { debugNow = 0 }
            Button(HintCopy.debugResetHintState) {
                weeklyDismissedWeek = ""
                adjustSnoozedUntil = 0
            }
            Button(HintCopy.debugClearLog) { isConfirmingClear = true }
        } header: {
            Text(HintCopy.debugSectionTitle)
        } footer: {
            Text(HintCopy.debugFooter)
        }
        .alert(HintCopy.debugClearLogConfirm, isPresented: $isConfirmingClear) {
            Button(HintCopy.debugClearLogAction, role: .destructive) {
                try? modelContext.delete(model: FoodEntry.self)
                try? modelContext.save()
            }
            Button(HintCopy.debugCancel, role: .cancel) {}
        }
    }

    // MARK: - 日期和目标（日期都按「假装现在是」的时间算）

    private var target: Double { profile.targets.calories }
    private var today: Date { calendar.startOfDay(for: HintClock.now) }

    private func daysAgo(_ offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset, to: today) ?? today
    }

    /// 上一个完整的周一～周日里的前 count 天
    private func lastWeek(_ count: Int) -> [Date] {
        let start = HintEngine.previousWeek(containing: HintClock.now, calendar: calendar).start
        return (0..<count).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    private var fakeNow: Binding<Date> {
        Binding(
            get: { debugNow > 0 ? Date(timeIntervalSince1970: debugNow) : .now },
            set: { debugNow = $0.timeIntervalSince1970 })
    }

    private var fakeRange: ClosedRange<Date> {
        let span = Double(HintClock.fakeRangeDays) * 86_400
        return Date.now.addingTimeInterval(-span)...Date.now.addingTimeInterval(span)
    }

    // MARK: - 写入示例记录

    /// 每一天：先删掉这一天原有的记录（所以多按几次结果一样），再把 kcalPerDay 平均分给 meals 里的几餐
    private func seed(days: [Date], kcalPerDay: Double, meals: [MealType]) {
        let targets = profile.targets
        let kcal = (kcalPerDay / Double(meals.count)).rounded()  // 每一餐的热量，取整
        let share = kcal / targets.calories  // 营养素按每日目标的同样比例给
        for day in days {
            let old = (try? modelContext.fetch(FetchDescriptor(predicate: FoodEntry.predicate(day: day)))) ?? []
            old.forEach { modelContext.delete($0) }
            for meal in meals {
                modelContext.insert(
                    FoodEntry(
                        day: day, meal: meal, name: HintCopy.debugEntryName(meal.title), weightG: nil,
                        values: NutrientValues(
                            caloriesKcal: kcal,
                            proteinG: (targets.proteinG * share * 10).rounded() / 10,
                            carbsG: (targets.carbsG * share * 10).rounded() / 10,
                            fatG: (targets.fatG * share * 10).rounded() / 10),
                        source: .manual))
            }
        }
        // 资料修改时间改到 30 天前：刚建或刚改的资料会让前几天的记录不参与计算
        profile.updatedAt = HintClock.now.addingTimeInterval(-30 * 86_400)
        try? modelContext.save()
    }
}
#endif
