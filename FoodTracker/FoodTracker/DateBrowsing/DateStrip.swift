//
//  DateStrip.swift
//  FoodTracker
//
//  「今日」页顶部的日期栏：一页是一周（周一到周日），左右滑动翻周，点一天就看那一天的记录。
//  样子尽量轻：选中的那天是橄榄绿的实心圆，今天（没选中时）是橄榄绿的细圈，其他日期只有数字。
//  每个日期下面有一条很短的燕麦色小进度条，表示那天吃了目标的几成；未来的日期是浅灰的，不能点。
//  最多往前翻 520 周（10 年）。页码是「离本周几周」：0 = 本周，-1 = 上周 …（见 DayMath）
//

import SwiftData
import SwiftUI

struct DateStrip: View {
    @Binding var selectedDay: Date  // 正在看的那一天（0 点）
    @Binding var visibleWeekOffset: Int?  // 现在显示的是哪一页（0 = 本周）；改它就会滚到那一页
    let today: Date
    let kcalTarget: Double  // 每日热量目标，算小进度条用

    var body: some View {
        let thisWeekStart = DayMath.weekStart(containing: today)
        ScrollView(.horizontal) {
            // LazyHStack：只创建滑到附近的那几页，不会一口气建 521 页
            LazyHStack(spacing: 0) {
                ForEach(DayMath.weekOffsetRange, id: \.self) { offset in
                    DateStripPage(
                        weekStart: DayMath.weekStart(offset: offset, from: thisWeekStart), selectedDay: $selectedDay,
                        today: today, kcalTarget: kcalTarget, onPage: page(by:)
                    )
                    .containerRelativeFrame(.horizontal)  // 每一页和日期栏一样宽
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
        // 字号最多放大到「特大」：再大一行就放不下 7 天了（和系统的标签栏一样；长按格子可以看放大的日期）
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
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
struct DateStripPage: View {
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
        // 查这一周的记录（周一 0 点起，到下周一 0 点之前）；有新记录时 SwiftData 会自动刷新，小进度条马上跟着变
        _entries = Query(filter: FoodEntry.predicate(from: weekStart, to: DayMath.addingDays(7, to: weekStart)))
    }

    var body: some View {
        let kcalByDay = DayMath.kcalByDay(entries.map { DayKcal(day: $0.day(), kcal: $0.caloriesKcal) })
        HStack(spacing: 0) {
            ForEach(DayMath.days(inWeekStarting: weekStart), id: \.self) { day in
                DateCell(
                    day: day, today: today, isSelected: day == selectedDay, kcal: kcalByDay[day] ?? 0,
                    kcalTarget: kcalTarget, onPage: onPage
                ) {
                    selectedDay = day
                }
            }
        }
        .padding(.vertical, AppSpacing.xxs)
    }
}

/// 一天的格子：星期，日期数字，下面一条小进度条
private struct DateCell: View {
    let day: Date
    let today: Date
    let isSelected: Bool
    let kcal: Double
    let kcalTarget: Double
    let onPage: (Int) -> Void
    let onTap: () -> Void

    // 跟着系统字体大小一起变
    @ScaledMetric(relativeTo: .body) private var circleSize: CGFloat = 36

    private var isSelectable: Bool { DayMath.isSelectable(day, today: today) }
    private var isToday: Bool { day == today }

    /// 日期数字的颜色：选中 = 暖白（橄榄绿底），今天 = 橄榄绿，过去 = 次要文字，未来 = 最浅
    private var numberColor: Color {
        if isSelected { return AppColors.onBrand }
        if isToday { return AppColors.brand }
        return isSelectable ? AppColors.textSecondary : AppColors.textTertiary
    }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 6) {
                Text(DayMath.weekdayLetters[DayMath.weekdayIndex(of: day)])
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(isSelectable ? AppColors.textSecondary : AppColors.textTertiary)
                Text(DayMath.dayNumber(day))
                    .font(.system(.callout, design: .rounded, weight: isSelected || isToday ? .semibold : .regular))
                    .monospacedDigit()
                    .foregroundStyle(numberColor)
                    .frame(width: circleSize, height: circleSize)
                    .background {
                        if isSelected {
                            Circle().fill(AppColors.brand)
                        } else if isToday {
                            Circle().strokeBorder(AppColors.brand, lineWidth: 1.5)
                        }
                    }
                // 未来的日期不画小进度条，但位置留着，让每一列一样高
                IntakeMark(fraction: DayMath.ringFraction(kcal: kcal, target: kcalTarget))
                    .opacity(isSelectable ? 1 : 0)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isSelectable)
        .animation(.easeOut(duration: 0.2), value: isSelected)
        // 旁白（VoiceOver）念的是一整句话，比如「9月28日 周一，已记录 750 千卡，占目标 42%」
        .accessibilityLabel(DayMath.cellAccessibilityLabel(day: day, today: today, kcal: kcal, target: kcalTarget))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        // 旁白用户不方便左右滑动翻页，给两个动作（在格子上上下滑动就能选到）
        .accessibilityAction(named: "上一周") { onPage(-1) }
        .accessibilityAction(named: "下一周") { onPage(1) }
        // 用特大字号的人长按格子，会弹出放大的日期（日期栏的字号有上限，见 DateStrip）
        .accessibilityShowsLargeContentViewer {
            Text(DayMath.dayTitle(for: day, today: today))
        }
    }
}

/// 日期下面的小进度条：那天吃了目标的几成。没记录只有浅色底槽；到了目标是满的；超过也还是满的、同样的颜色，不用红色
struct IntakeMark: View {
    let fraction: Double  // 0～1

    var body: some View {
        Capsule()
            .fill(AppColors.surfaceMuted)
            .frame(width: 18, height: 3)
            .overlay(alignment: .leading) {
                Capsule()
                    .fill(AppColors.oatMark)
                    .frame(width: 18 * min(max(fraction, 0), 1), height: 3)
            }
            .animation(.default, value: fraction)
            .accessibilityHidden(true)  // 数字已经在格子的朗读文字里了
    }
}

#Preview {
    @Previewable @State var selectedDay = DayMath.startOfDay(.now)
    @Previewable @State var visibleWeekOffset: Int? = 0
    VStack {
        DateStrip(
            selectedDay: $selectedDay, visibleWeekOffset: $visibleWeekOffset, today: DayMath.startOfDay(.now), kcalTarget: 2000
        )
        Text(DayMath.dayTitle(for: selectedDay, today: .now))
        Spacer()
    }
    .background(AppColors.background)
    .modelContainer(SampleData.previewContainer)
}
