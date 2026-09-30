//
//  DayMathTests.swift
//  FoodTrackerTests
//
//  和「哪一天」有关的计算的测试。
//
//  大部分测试在两个时区各跑一遍（上海和洛杉矶），并且每次调用都把日历传进去。
//  这样测试结果不取决于电脑设在哪个时区；如果哪里忘了传日历，至少有一个时区的结果会不对，测试就会失败。
//  测试失败时要找出忘传日历的地方，不要去改预期结果。
//

import Foundation
import Testing

@testable import FoodTracker

private let zones = ["Asia/Shanghai", "America/Los_Angeles"]

private func calendar(_ zone: String) -> Calendar {
    DayMath.makeCalendar(timeZone: TimeZone(identifier: zone)!)
}

/// 用指定的日历造一个日期，比如 d(2026, 9, 29, cal) 是那天的 0 点
private func d(_ year: Int, _ month: Int, _ day: Int, hour: Int = 0, _ cal: Calendar) -> Date {
    cal.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
}

@Suite("日期计算")
struct DayMathTests {

    @Test("日历设置：公历、一周从周一开始")
    func calendarSetup() {
        let cal = DayMath.calendar
        #expect(cal.identifier == .gregorian)
        #expect(cal.firstWeekday == 2)
        #expect(cal.minimumDaysInFirstWeek == 4)
        // 只写 zh_CN 的话系统认为一周从周日开始，所以地区设置写成 zh_CN@fw=mon
        #expect(DayMath.locale.firstDayOfWeek == .monday)
    }

    @Test("一天从 0 点开始", arguments: zones)
    func startOfDay(zone: String) {
        let cal = calendar(zone)
        #expect(DayMath.startOfDay(d(2026, 9, 29, hour: 23, cal), calendar: cal) == d(2026, 9, 29, cal))
        #expect(DayMath.startOfDay(d(2026, 9, 30, cal), calendar: cal) == d(2026, 9, 30, cal))
        #expect(DayMath.addingDays(1, to: d(2026, 9, 30, cal), calendar: cal) == d(2026, 10, 1, cal))
        #expect(DayMath.addingDays(-1, to: d(2026, 1, 1, cal), calendar: cal) == d(2025, 12, 31, cal))
    }

    // 洛杉矶 2026 年 11 月 1 日夏令时结束（这天 25 小时），3 月 8 日开始（这天 23 小时）
    @Test("夏令时那天也按日历加一天")
    func daylightSaving() {
        let la = calendar("America/Los_Angeles")
        let nov1 = d(2026, 11, 1, la)
        #expect(DayMath.addingDays(1, to: nov1, calendar: la) == d(2026, 11, 2, la))
        #expect(d(2026, 11, 2, la).timeIntervalSince(nov1) == 25 * 3600)
        // 直接加 86400 秒是错的：会停在 11 月 1 日 23 点
        #expect(nov1.addingTimeInterval(86400) == d(2026, 11, 1, hour: 23, la))
        let mar8 = d(2026, 3, 8, la)
        #expect(DayMath.addingDays(1, to: mar8, calendar: la) == d(2026, 3, 9, la))
        #expect(d(2026, 3, 9, la).timeIntervalSince(mar8) == 23 * 3600)
    }

    @Test("记录的日期存成 20260929 这样的数字", arguments: zones)
    func dayKey(zone: String) {
        let cal = calendar(zone)
        #expect(DayMath.dayKey(for: d(2026, 9, 28, hour: 20, cal), calendar: cal) == 20260928)
        #expect(DayMath.date(fromDayKey: 20260928, calendar: cal) == d(2026, 9, 28, cal))
        #expect(DayMath.dayKey(for: d(2024, 2, 29, cal), calendar: cal) == 20240229)
        #expect(DayMath.date(fromDayKey: 20240229, calendar: cal) == d(2024, 2, 29, cal))
        #expect(DayMath.dayKey(for: d(2025, 12, 31, hour: 23, cal), calendar: cal) == 20251231)
    }

    @Test("换了时区，记录还在原来那天")
    func dayKeyAcrossTimeZones() {
        let shanghai = calendar("Asia/Shanghai")
        let losAngeles = calendar("America/Los_Angeles")
        // 在上海 9 月 29 日中午记的一餐
        let lunch = d(2026, 9, 29, hour: 12, shanghai)
        let key = DayMath.dayKey(for: lunch, calendar: shanghai)
        #expect(key == 20260929)
        // 同一个时刻在洛杉矶是 9 月 28 日晚上：如果按时刻存，回到美国后这条记录会跑到前一天
        #expect(DayMath.dayKey(for: lunch, calendar: losAngeles) == 20260928)
        // 按年月日存，在洛杉矶打开也还是 9 月 29 日
        #expect(DayMath.date(fromDayKey: key, calendar: losAngeles) == d(2026, 9, 29, losAngeles))
    }

    @Test("星期几：周一 = 0 … 周日 = 6", arguments: zones)
    func weekday(zone: String) {
        let cal = calendar(zone)
        #expect(DayMath.weekdayIndex(of: d(2026, 9, 28, cal), calendar: cal) == 0)  // 周一
        #expect(DayMath.weekdayIndex(of: d(2026, 9, 29, cal), calendar: cal) == 1)  // 周二
        #expect(DayMath.weekdayIndex(of: d(2026, 10, 4, cal), calendar: cal) == 6)  // 周日
        #expect(DayMath.weekdayIndex(of: d(2025, 12, 31, cal), calendar: cal) == 2)  // 周三
    }

    @Test("日期的显示文字", arguments: zones)
    func titles(zone: String) {
        let cal = calendar(zone)
        let today = d(2026, 9, 29, hour: 10, cal)  // 周二
        #expect(DayMath.dayTitle(for: d(2026, 9, 29, cal), today: today, calendar: cal) == "今天")
        #expect(DayMath.dayTitle(for: d(2026, 9, 28, hour: 23, cal), today: today, calendar: cal) == "昨天")
        #expect(DayMath.dayTitle(for: d(2026, 9, 20, cal), today: today, calendar: cal) == "9月20日 周日")
        #expect(DayMath.dayTitle(for: d(2025, 12, 31, cal), today: today, calendar: cal) == "2025年12月31日 周三")
        #expect(DayMath.saveButtonTitle(day: d(2026, 9, 29, cal), today: today, calendar: cal) == "保存到今日")
        #expect(DayMath.saveButtonTitle(day: d(2026, 9, 20, cal), today: today, calendar: cal) == "保存到 9月20日")
        #expect(DayMath.saveButtonTitle(day: d(2025, 12, 31, cal), today: today, calendar: cal) == "保存到 2025年12月31日")
        #expect(DayMath.recordCaption(day: d(2026, 9, 29, cal), today: today, calendar: cal) == nil)
        #expect(DayMath.recordCaption(day: d(2026, 9, 28, cal), today: today, calendar: cal) == "记录到 9月28日 周一")
    }

    // MARK: - 周横条

    @Test("一周从周一 0 点开始", arguments: zones)
    func weekStart(zone: String) {
        let cal = calendar(zone)
        #expect(DayMath.weekStart(containing: d(2026, 9, 29, hour: 13, cal), calendar: cal) == d(2026, 9, 28, cal))  // 周二
        #expect(DayMath.weekStart(containing: d(2026, 10, 4, hour: 13, cal), calendar: cal) == d(2026, 9, 28, cal))  // 周日
        #expect(DayMath.weekStart(containing: d(2026, 9, 28, cal), calendar: cal) == d(2026, 9, 28, cal))  // 周一本身
        #expect(DayMath.weekStart(containing: d(2026, 1, 1, cal), calendar: cal) == d(2025, 12, 29, cal))  // 跨年
        #expect(DayMath.weekStart(containing: d(2027, 1, 3, cal), calendar: cal) == d(2026, 12, 28, cal))
        #expect(DayMath.weekStart(containing: d(2024, 2, 29, cal), calendar: cal) == d(2024, 2, 26, cal))  // 闰日
        #expect(
            DayMath.days(inWeekStarting: d(2026, 9, 28, cal), calendar: cal) == [
                d(2026, 9, 28, cal), d(2026, 9, 29, cal), d(2026, 9, 30, cal), d(2026, 10, 1, cal),
                d(2026, 10, 2, cal), d(2026, 10, 3, cal), d(2026, 10, 4, cal),
            ])
    }

    @Test("页码：0 = 本周，-1 = 上周 … -520 = 十年前", arguments: zones)
    func weekOffsets(zone: String) {
        let cal = calendar(zone)
        let today = d(2026, 9, 29, cal)
        let thisWeek = d(2026, 9, 28, cal)
        #expect(DayMath.weekStart(offset: -1, from: thisWeek, calendar: cal) == d(2026, 9, 21, cal))
        #expect(DayMath.weekStart(offset: -52, from: thisWeek, calendar: cal) == d(2025, 9, 29, cal))
        #expect(DayMath.weekStart(offset: -520, from: thisWeek, calendar: cal) == d(2016, 10, 10, cal))
        #expect(DayMath.weekOffset(of: d(2026, 9, 20, cal), relativeTo: today, calendar: cal) == -2)
        #expect(DayMath.weekOffset(of: d(2026, 9, 28, cal), relativeTo: today, calendar: cal) == 0)
        #expect(DayMath.weekOffset(of: d(2026, 9, 29, cal), relativeTo: today, calendar: cal) == 0)
        #expect(DayMath.weekOffset(of: d(2026, 8, 15, cal), relativeTo: today, calendar: cal) == -7)
        #expect(DayMath.weekOffset(of: d(2025, 9, 29, cal), relativeTo: today, calendar: cal) == -52)
        #expect(DayMath.weekOffset(of: d(2016, 10, 10, cal), relativeTo: today, calendar: cal) == -520)
        // 每一页的周一算回去都是同一个页码（包括夏令时切换的那几周）
        for offset in DayMath.weekOffsetRange {
            let start = DayMath.weekStart(offset: offset, from: thisWeek, calendar: cal)
            #expect(DayMath.weekOffset(of: start, relativeTo: today, calendar: cal) == offset)
        }
        #expect(DayMath.oldestDay(today: today, calendar: cal) == d(2016, 10, 10, cal))
    }

    // 洛杉矶 2026 年 3 月 8 日开始夏令时：3 月 2 日那一周只有 167 小时，但每一天还是从 0 点开始
    @Test("夏令时那一周的页码和日期")
    func daylightSavingWeek() {
        let la = calendar("America/Los_Angeles")
        let today = d(2026, 9, 29, la)
        #expect(DayMath.weekOffset(of: d(2026, 3, 3, la), relativeTo: today, calendar: la) == -30)
        #expect(DayMath.weekStart(offset: -30, from: d(2026, 9, 28, la), calendar: la) == d(2026, 3, 2, la))
        let days = DayMath.days(inWeekStarting: d(2026, 3, 2, la), calendar: la)
        #expect(days.allSatisfy { la.component(.hour, from: $0) == 0 })
        #expect(days.last == d(2026, 3, 8, la))
        #expect(d(2026, 3, 9, la).timeIntervalSince(d(2026, 3, 2, la)) == 167 * 3600)
    }

    @Test("能选的日期：不能是未来，也不能早于十年前", arguments: zones)
    func selectable(zone: String) {
        let cal = calendar(zone)
        let today = d(2026, 9, 29, cal)
        #expect(DayMath.isSelectable(d(2026, 9, 29, cal), today: today, calendar: cal))
        #expect(DayMath.isSelectable(d(2026, 9, 29, hour: 23, cal), today: today, calendar: cal))
        #expect(!DayMath.isSelectable(d(2026, 9, 30, cal), today: today, calendar: cal))
        #expect(DayMath.isSelectable(d(2016, 10, 10, cal), today: today, calendar: cal))
        #expect(!DayMath.isSelectable(d(2016, 10, 9, cal), today: today, calendar: cal))
    }

    @Test("翻页后选中哪一天", arguments: zones)
    func selectionAfterPaging(zone: String) {
        let cal = calendar(zone)
        let today = d(2026, 9, 29, cal)  // 周二
        // 从本周二翻到上周：选上周二
        #expect(DayMath.selection(afterShowingWeekStarting: d(2026, 9, 21, cal), previous: d(2026, 9, 29, cal), today: today, calendar: cal) == d(2026, 9, 22, cal))
        // 从上周二翻回本周：选本周二（今天）
        #expect(DayMath.selection(afterShowingWeekStarting: d(2026, 9, 28, cal), previous: d(2026, 9, 22, cal), today: today, calendar: cal) == d(2026, 9, 29, cal))
        // 从上周六翻回本周：本周六还没到，选今天
        #expect(DayMath.selection(afterShowingWeekStarting: d(2026, 9, 28, cal), previous: d(2026, 9, 26, cal), today: today, calendar: cal) == d(2026, 9, 29, cal))
        // 选中的那天就在这一周：不动
        #expect(DayMath.selection(afterShowingWeekStarting: d(2026, 9, 28, cal), previous: d(2026, 9, 29, cal), today: today, calendar: cal) == d(2026, 9, 29, cal))
        // 跨年：从 1 月 11 日（周日）翻到 12 月 29 日那一周，选 1 月 4 日（周日）
        #expect(DayMath.selection(afterShowingWeekStarting: d(2025, 12, 29, cal), previous: d(2026, 1, 11, cal), today: today, calendar: cal) == d(2026, 1, 4, cal))
    }

    @Test("月历的可选范围和年月日换算", arguments: zones)
    func calendarBridge(zone: String) {
        let cal = calendar(zone)
        let today = d(2026, 9, 29, hour: 10, cal)
        let range = DayMath.availableRange(today: today, calendar: cal)
        #expect(range.start == d(2016, 10, 10, cal))
        #expect(range.contains(d(2026, 9, 29, hour: 12, cal)))
        #expect(!range.contains(d(2026, 9, 30, cal)))  // 明天 0 点不在范围内
        #expect(DayMath.day(from: DayMath.components(of: d(2026, 9, 29, cal), calendar: cal), calendar: cal) == d(2026, 9, 29, cal))
        #expect(DayMath.day(from: DayMath.components(of: d(2024, 2, 29, cal), calendar: cal), calendar: cal) == d(2024, 2, 29, cal))
        #expect(DayMath.day(from: DateComponents(), calendar: cal) == nil)
        // 带着别的时区的年月日：还是同一个年月日
        var foreign = DateComponents(year: 2026, month: 9, day: 29)
        foreign.timeZone = TimeZone(identifier: "Pacific/Auckland")
        #expect(DayMath.day(from: foreign, calendar: cal) == d(2026, 9, 29, cal))
    }

    @Test("今天变了以后该显示哪一天", arguments: zones)
    func dayToShow(zone: String) {
        let cal = calendar(zone)
        let sep29 = d(2026, 9, 29, cal)
        let sep30 = d(2026, 9, 30, cal)
        let sep20 = d(2026, 9, 20, cal)
        // 在前台过了午夜：看着的还是 29 日，不动（列表不会突然变空）
        #expect(DayMath.dayToShow(newToday: sep30, selectedDay: sep29, followsToday: true, appBecameActive: false, calendar: cal) == sep29)
        // 第二天早上回到 App：用户最后选的是「今天」，跟到 30 日
        #expect(DayMath.dayToShow(newToday: sep30, selectedDay: sep29, followsToday: true, appBecameActive: true, calendar: cal) == sep30)
        // 正在翻看 20 日：怎么样都停在 20 日
        #expect(DayMath.dayToShow(newToday: sep30, selectedDay: sep20, followsToday: false, appBecameActive: true, calendar: cal) == sep20)
        #expect(DayMath.dayToShow(newToday: sep30, selectedDay: sep20, followsToday: false, appBecameActive: false, calendar: cal) == sep20)
        // 同一天回到 App：不变
        #expect(DayMath.dayToShow(newToday: sep29, selectedDay: sep29, followsToday: true, appBecameActive: true, calendar: cal) == sep29)
        // 时钟被往回调：不能停在未来
        #expect(DayMath.dayToShow(newToday: d(2026, 9, 27, cal), selectedDay: sep29, followsToday: true, appBecameActive: false, calendar: cal) == d(2026, 9, 27, cal))
        // 换了时区：看着的那天不再是当地 0 点，直接看新的今天
        let notMidnight = sep20.addingTimeInterval(15 * 3600)
        #expect(DayMath.dayToShow(newToday: sep30, selectedDay: notMidnight, followsToday: false, appBecameActive: false, calendar: cal) == sep30)
    }

    @Test("圆环的比例和按天加总", arguments: zones)
    func ringsAndGrouping(zone: String) {
        let cal = calendar(zone)
        #expect(DayMath.ringFraction(kcal: 900, target: 1800) == 0.5)
        #expect(DayMath.ringFraction(kcal: 1800, target: 1800) == 1)
        #expect(DayMath.ringFraction(kcal: 2500, target: 1800) == 1)  // 超过目标也只画满
        #expect(DayMath.ringFraction(kcal: 0, target: 1800) == 0)
        #expect(DayMath.ringFraction(kcal: 500, target: 0) == 0)
        #expect(DayMath.ringFraction(kcal: -10, target: 1800) == 0)
        let grouped = DayMath.kcalByDay(
            [
                DayKcal(day: d(2026, 9, 28, cal), kcal: 400), DayKcal(day: d(2026, 9, 28, hour: 13, cal), kcal: 350.5),
                DayKcal(day: d(2026, 9, 29, cal), kcal: 600),
            ], calendar: cal)
        #expect(grouped == [d(2026, 9, 28, cal): 750.5, d(2026, 9, 29, cal): 600])
        #expect(DayMath.kcalByDay([], calendar: cal).isEmpty)
    }

    @Test("周横条和顶栏的文字", arguments: zones)
    func stripTexts(zone: String) {
        let cal = calendar(zone)
        let today = d(2026, 9, 29, cal)
        #expect(DayMath.monthTitle(for: d(2026, 9, 29, cal), calendar: cal) == "2026年9月")
        #expect(DayMath.monthTitle(for: d(2025, 12, 31, cal), calendar: cal) == "2025年12月")
        #expect(DayMath.monthTitle(for: d(2026, 1, 4, cal), calendar: cal) == "2026年1月")
        #expect(DayMath.dayNumber(d(2026, 10, 1, cal), calendar: cal) == "1")
        #expect(DayMath.weekdayLetters[DayMath.weekdayIndex(of: d(2026, 9, 28, cal), calendar: cal)] == "一")
        #expect(DayMath.weekdayLetters[DayMath.weekdayIndex(of: d(2026, 10, 4, cal), calendar: cal)] == "日")
        #expect(DayMath.percentText(kcal: 750, target: 1800) == "占目标 42%")
        #expect(DayMath.percentText(kcal: 2600, target: 2000) == "占目标 130%")
        #expect(DayMath.percentText(kcal: 0, target: 2000) == "没有记录")
        #expect(DayMath.cellAccessibilityLabel(day: d(2026, 9, 28, cal), today: today, kcal: 750, target: 1800, calendar: cal) == "9月28日 周一，已记录 750 千卡，占目标 42%")
        #expect(DayMath.cellAccessibilityLabel(day: d(2026, 9, 27, cal), today: today, kcal: 0, target: 1800, calendar: cal) == "9月27日 周日，没有记录")
        #expect(DayMath.cellAccessibilityLabel(day: today, today: today, kcal: 300, target: 2000, calendar: cal) == "今天，9月29日 周二，已记录 300 千卡，占目标 15%")
        #expect(DayMath.cellAccessibilityLabel(day: d(2026, 9, 30, cal), today: today, kcal: 0, target: 2000, calendar: cal) == "9月30日 周三，未来的日期")
    }
}
