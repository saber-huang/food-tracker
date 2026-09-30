//
//  WeekStripView.swift
//  FoodTracker
//
//  「今日」页顶部的周横条：一页是一周（周一到周日），左右滑动翻周，点一天就看那一天的记录。
//  每一天下面有一个灰色小圆环，表示那天吃了目标的几成；未来的日期是灰的，不能点。
//  最多往前翻 520 周（10 年）。页码是「离本周几周」：0 = 本周，-1 = 上周 …（见 DayMath）
//

import SwiftData
import SwiftUI

struct WeekStripView: View {
    @Binding var selectedDay: Date  // 正在看的那一天（0 点）
    @Binding var visibleWeekOffset: Int?  // 现在显示的是哪一页（0 = 本周）；改它就会滚到那一页
    let today: Date
    let kcalTarget: Double  // 每日热量目标，算圆环用

    var body: some View {
        let thisWeekStart = DayMath.weekStart(containing: today)
        ScrollView(.horizontal) {
            // LazyHStack：只创建滑到附近的那几页，不会一口气建 521 页
            LazyHStack(spacing: 0) {
                ForEach(DayMath.weekOffsetRange, id: \.self) { offset in
                    WeekPageView(
                        weekStart: DayMath.weekStart(offset: offset, from: thisWeekStart), selectedDay: $selectedDay,
                        today: today, kcalTarget: kcalTarget, onPage: page(by:)
                    )
                    .containerRelativeFrame(.horizontal)  // 每一页和横条一样宽
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)  // 一次翻一整页
        .scrollPosition(id: $visibleWeekOffset, anchor: .center)
        .defaultScrollAnchor(.trailing)  // 打开时停在最后一页，也就是本周
        .scrollIndicators(.hidden)
        // 横向滚动的视图默认会把竖向的空间也全占掉；这里只要格子那么高
        .fixedSize(horizontal: false, vertical: true)
        // 翻到了新的一周：选中同一个星期几（不能超过今天）
        .onChange(of: visibleWeekOffset) { _, offset in
            guard let offset else { return }
            let day = DayMath.selection(
                afterShowingWeekStarting: DayMath.weekStart(offset: offset, from: thisWeekStart), previous: selectedDay,
                today: today)
            if day != selectedDay { selectedDay = day }
        }
        .sensoryFeedback(.selection, trigger: selectedDay)  // 换了一天轻轻震一下
    }

    /// 翻到上一页（-1）或下一页（+1）：给旁白（VoiceOver）用户的「上一周」「下一周」动作用，滑不动的边界就不动
    private func page(by delta: Int) {
        let target = (visibleWeekOffset ?? 0) + delta
        guard DayMath.weekOffsetRange.contains(target) else { return }
        visibleWeekOffset = target
    }
}

/// 一周的 7 个格子。每一页自己查这一周的记录，算出每天吃了多少
struct WeekPageView: View {
    let weekStart: Date
    @Binding var selectedDay: Date
    let today: Date
    let kcalTarget: Double
    let onPage: (Int) -> Void  // 旁白用户在格子上做「上一周」「下一周」动作

    @Query private var entries: [FoodEntry]

    init(weekStart: Date, selectedDay: Binding<Date>, today: Date, kcalTarget: Double, onPage: @escaping (Int) -> Void) {
        self.weekStart = weekStart
        _selectedDay = selectedDay
        self.today = today
        self.kcalTarget = kcalTarget
        self.onPage = onPage
        // 查这一周的记录（周一 0 点起，到下周一 0 点之前）；有新记录时 SwiftData 会自动刷新，圆环马上跟着变
        _entries = Query(filter: FoodEntry.predicate(from: weekStart, to: DayMath.addingDays(7, to: weekStart)))
    }

    var body: some View {
        let kcalByDay = DayMath.kcalByDay(entries.map { DayKcal(day: $0.day(), kcal: $0.caloriesKcal) })
        HStack(spacing: 0) {
            ForEach(DayMath.days(inWeekStarting: weekStart), id: \.self) { day in
                DayCell(
                    day: day, today: today, isSelected: day == selectedDay, kcal: kcalByDay[day] ?? 0,
                    kcalTarget: kcalTarget, onPage: onPage
                ) {
                    selectedDay = day
                }
            }
        }
        .padding(.vertical, 6)
    }
}

/// 一天的格子：星期、日期数字、圆环
private struct DayCell: View {
    let day: Date
    let today: Date
    let isSelected: Bool
    let kcal: Double
    let kcalTarget: Double
    let onPage: (Int) -> Void
    let onTap: () -> Void

    // 跟着系统字体大小一起变
    @ScaledMetric(relativeTo: .body) private var circleSize: CGFloat = 34
    @ScaledMetric(relativeTo: .body) private var ringSize: CGFloat = 18

    private var isSelectable: Bool { DayMath.isSelectable(day, today: today) }
    private var isToday: Bool { day == today }

    /// 日期数字的颜色：选中 = 白字（蓝底），今天 = 蓝字，过去 = 正常，未来 = 灰
    private var numberColor: Color {
        if isSelected { return .white }
        if isToday { return .accentColor }
        return isSelectable ? .primary : Color(.tertiaryLabel)
    }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 4) {
                Text(DayMath.weekdayLetters[DayMath.weekdayIndex(of: day)])
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(DayMath.dayNumber(day))
                    .font(.body.weight(isSelected || isToday ? .semibold : .regular))
                    .foregroundStyle(numberColor)
                    .frame(width: circleSize, height: circleSize)
                    .background {
                        if isSelected {
                            Circle().fill(Color.accentColor)
                        }
                    }
                // 未来的日期不画圆环，但位置留着，让每一列一样高
                IntakeRing(fraction: DayMath.ringFraction(kcal: kcal, target: kcalTarget))
                    .frame(width: ringSize, height: ringSize)
                    .opacity(isSelectable ? 1 : 0)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isSelectable)
        // 旁白（VoiceOver）念的是一整句话，比如「9月28日 周一，已记录 750 千卡，占目标 42%」
        .accessibilityLabel(DayMath.cellAccessibilityLabel(day: day, today: today, kcal: kcal, target: kcalTarget))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        // 旁白用户不方便左右滑动翻页，给两个动作（在格子上上下滑动就能选到）
        .accessibilityAction(named: "上一周") { onPage(-1) }
        .accessibilityAction(named: "下一周") { onPage(1) }
    }
}

/// 灰色小圆环：吃了目标的几成。没记录只有浅色底圈；到了目标是一整圈；超过也还是一整圈、同样的灰色，不用红色
struct IntakeRing: View {
    let fraction: Double  // 0～1

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color(.systemGray5), lineWidth: 3)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(Color(.systemGray), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))  // 从 12 点方向开始画
        }
        .animation(.default, value: fraction)
        .accessibilityHidden(true)  // 数字已经在格子的朗读文字里了
    }
}

#Preview {
    @Previewable @State var selectedDay = DayMath.startOfDay(.now)
    @Previewable @State var visibleWeekOffset: Int? = 0
    VStack {
        WeekStripView(
            selectedDay: $selectedDay, visibleWeekOffset: $visibleWeekOffset, today: DayMath.startOfDay(.now), kcalTarget: 2000
        )
        .background(.bar)
        Text(DayMath.dayTitle(for: selectedDay, today: .now))
        Spacer()
    }
    .modelContainer(SampleData.previewContainer)
}
