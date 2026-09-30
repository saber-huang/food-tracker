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
}
