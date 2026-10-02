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
                    .foregroundStyle(AppColors.textSecondary)
                    .hintRow()
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
                    .hintRow()
                Button {
                    // 按今天真正剩下的热量（目标 − 已记录）推荐，不用四舍五入过的数
                    let todayKcal = history.first { DayMath.calendar.isDate($0.day, inSameDayAs: now) }?.kcal ?? 0
                    sheet = .nextMeal(NextMealBudget(meal: meal, remainingKcal: targets.calories - todayKcal, targets: targets))
                } label: {
                    Label(HintCopy.recommendNextMeal, systemImage: "sparkles")
                }
                .accessibilityHint(HintCopy.recommendNextMealA11y)
                .hintRow()
            }
        case .over(let byKcal, let meal):
            Section {
                note(HintCopy.over(byKcal: byKcal, nextMealName: meal?.title), icon: "heart.circle")
                    .hintRow()
            }
        case .belowPlan:
            Section {
                note(HintCopy.belowPlan, icon: "heart.circle")
                    .hintRow()
            }
        case .adjustTarget(let days):
            // 连续几天明显高于目标：温和地问一句要不要调整目标。两个按钮都会让这张卡片 7 天内不再出现
            Section {
                note(HintCopy.adjustTarget(consecutiveDays: days), icon: "heart.circle")
                    .hintRow()
                Button(HintCopy.adjustTargetAction) {
                    snoozeAdjust(from: now)
                    sheet = .editProfile
                }
                .accessibilityHint(HintCopy.adjustTargetA11y)
                .hintRow()
                Button(HintCopy.adjustTargetLater) {
                    snoozeAdjust(from: now)
                }
                .foregroundStyle(AppColors.textSecondary)
                .hintRow()
            }
        case .weeklySummary(let summary):
            weeklySection(summary)
        }
    }

    /// 每周小结：上一个完整的周一～周日。点「知道了」这一周就不再显示；下周一换成新的一周
    private func weeklySection(_ summary: WeeklySummary) -> some View {
        Section {
            // 只记了 1～2 天时算不出有参考价值的平均，不显示数字
            if summary.trend != .fewDays {
                Text(
                    HintCopy.weeklyNumbers(
                        averageKcal: summary.averageKcal, targetKcal: summary.targetKcal, daysCounted: summary.daysCounted)
                )
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(AppColors.textPrimary)
                .hintRow()
            }
            Text(verdict(for: summary))
                .font(.callout)
                .foregroundStyle(AppColors.textSecondary)
                .hintRow()
            if summary.targetChangedRecently {
                Text(HintCopy.weeklyTargetChangedNote)
                    .font(.caption)
                    .foregroundStyle(AppColors.textSecondary)
                    .hintRow()
            }
            if summary.suggestsAdjustingTarget {
                Text(HintCopy.weeklyAdjustSuggestion)
                    .font(.callout)
                    .foregroundStyle(AppColors.textSecondary)
                    .hintRow()
                Button(HintCopy.adjustTargetAction) { sheet = .editProfile }
                    .accessibilityHint(HintCopy.adjustTargetA11y)
                    .hintRow()
            }
            Button(HintCopy.weeklyDismiss) { weeklyDismissedWeek = summary.weekKey }
                .hintRow()
        } header: {
            Label(HintCopy.weeklyTitle, systemImage: "calendar")
                .font(AppTypography.sectionTitle)
                .foregroundStyle(AppColors.textPrimary)
                .textCase(nil)
        }
    }

    /// 小结里的那句话：一致 / 偏高 / 偏低 / 记录太少
    private func verdict(for summary: WeeklySummary) -> String {
        switch summary.trend {
        case .onTarget: HintCopy.weeklyOnTarget
        case .above: HintCopy.weeklyAbove(differenceKcal: summary.differenceKcal)
        case .below: HintCopy.weeklyBelow(differenceKcal: -summary.differenceKcal)
        case .fewDays: HintCopy.weeklyFewDays(daysCounted: summary.daysCounted)
        }
    }

    /// 灰色说明文字，样式和「我的」页的 FloorNotice、GoalNotesView 一样
    private func note(_ text: String, icon: String) -> some View {
        Label(text, systemImage: icon)
            .font(.callout)
            .foregroundStyle(AppColors.textSecondary)
    }

    /// 7 天内不再问要不要调整目标（按提示用的「现在」算，模拟器里假装的时间也一样）
    private func snoozeAdjust(from now: Date) {
        adjustSnoozedUntil = now.addingTimeInterval(Double(HintEngine.adjustSnoozeDays) * 86_400).timeIntervalSince1970
    }
}

private extension View {
    /// 提示卡片里的一行：卡片底色和「今日」页的其他卡片一样（暖白）
    func hintRow() -> some View {
        listRowBackground(AppColors.surfacePrimary)
    }
}
