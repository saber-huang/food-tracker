//
//  TodayHints.swift
//  FoodTracker
//
//  「今日」页上的热量提示：放在今日摄入卡片下面，最多两条，每条一个分组。
//  文案全部来自 HintCopy，判断全部来自 HintEngine；这里只负责摆放和按钮。
//  没有提示时什么都不显示（连空行都没有）。
//

import SwiftData
import SwiftUI

/// 提示里的按钮要打开的页面。由「今日」页负责弹出：「今日」页一直都在，
/// 而提示自己可能在按钮点完之后就消失（比如点了「调整目标」，那张卡片会马上收起来）
enum HintSheet: Identifiable {
    case nextMeal(NextMealBudget)
    case editProfile

    var id: String {
        switch self {
        case .nextMeal(let budget): "nextMeal-\(budget.id)"
        case .editProfile: "editProfile"
        }
    }
}

/// 提示用的「现在」。模拟器里的测试版可以在「我的」→「开发者」里假装成别的时间
enum HintClock {
    /// 「假装现在是」最多往前、往后调 30 天
    static let fakeRangeDays = 30
    /// 「今日」页读取多少天的记录：判断要用 14 天，再加上「假装现在是」最多往前调的 30 天
    static let lookbackDays = HintEngine.historyDays + fakeRangeDays

    static var now: Date {
        #if DEBUG && targetEnvironment(simulator)
        let fake = UserDefaults.standard.double(forKey: HintKeys.debugNowOverride)
        if fake > 0 { return Date(timeIntervalSince1970: fake) }
        #endif
        return .now
    }
}

struct TodayHints: View {
    let profile: UserProfile
    @Binding var sheet: HintSheet?

    @Query private var entries: [FoodEntry]
    @AppStorage(HintKeys.level) private var level: HintLevel = .all
    @AppStorage(HintKeys.weeklyDismissedWeek) private var weeklyDismissedWeek = ""
    @AppStorage(HintKeys.adjustSnoozedUntil) private var adjustSnoozedUntil = 0.0
    #if DEBUG && targetEnvironment(simulator)
    @AppStorage(HintKeys.debugNowOverride) private var debugNow = 0.0  // 改了「假装现在是」，这里马上刷新
    #endif
    @Environment(\.scenePhase) private var scenePhase

    init(profile: UserProfile, sheet: Binding<HintSheet?>) {
        self.profile = profile
        _sheet = sheet
        // 查询范围按真实的今天算，前后都留够「假装现在是」能调到的天数（多读几天没关系，少读会漏）
        _entries = Query(filter: FoodEntry.hintHistoryPredicate(realToday: DayMath.startOfDay(.now)))
    }

    var body: some View {
        let _ = scenePhase  // 读一下：App 回到前台时，这里会重新计算，拿到最新的时间
        let now = HintClock.now  // 每次刷新都重新读：记一餐、回到前台、改设置都会刷新
        let calendar = DayMath.calendar
        let history = DayIntake.history(from: entries, calendar: calendar)
        let targets = profile.targets
        let hints = HintEngine.hints(
            HintInput(
                goal: profile.bodyInfo.goal,
                targetKcal: targets.calories,
                targetChangedAt: profile.updatedAt,
                history: history,
                now: now,
                calendar: calendar,
                level: level,
                state: HintState(
                    weeklyDismissedWeek: weeklyDismissedWeek,
                    adjustSnoozedUntil: adjustSnoozedUntil > 0 ? Date(timeIntervalSince1970: adjustSnoozedUntil) : nil)))

        #if DEBUG && targetEnvironment(simulator)
        if debugNow > 0 {
            Section {
                Text(HintCopy.debugFakeNowCaption(now))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        #endif
        ForEach(hints, id: \.self) { hint in
            section(for: hint, now: now, history: history, targets: targets)
        }
    }

    // MARK: - 每一种提示的样子（灰色文字 + 普通按钮，不用红色、不用警告图标）

    @ViewBuilder
    private func section(for hint: CalorieHint, now: Date, history: [DayIntake], targets: DailyTargets) -> some View {
        switch hint {
        case .nearLimit(let remaining, let meal):
            Section {
                note(HintCopy.nearLimit(remainingKcal: remaining, mealName: meal.title), icon: "info.circle")
                Button {
                    // 按今天真正剩下的热量（目标 − 已记录）推荐，不用四舍五入过的数
                    let todayKcal = history.first { DayMath.calendar.isDate($0.day, inSameDayAs: now) }?.kcal ?? 0
                    sheet = .nextMeal(NextMealBudget(meal: meal, remainingKcal: targets.calories - todayKcal, targets: targets))
                } label: {
                    Label(HintCopy.recommendNextMeal, systemImage: "sparkles")
                }
                .accessibilityHint(HintCopy.recommendNextMealA11y)
            }
        case .over(let byKcal, let meal):
            Section {
                note(HintCopy.over(byKcal: byKcal, nextMealName: meal?.title), icon: "heart.circle")
            }
        case .adjustTarget, .weeklySummary:
            // 第 11 步再做：连续多天的询问卡片、每周小结
            EmptyView()
        }
    }

    /// 灰色说明文字，样式和「我的」页的 FloorNotice、GoalNotesView 一样
    private func note(_ text: String, icon: String) -> some View {
        Label(text, systemImage: icon)
            .font(.callout)
            .foregroundStyle(.secondary)
    }
}
