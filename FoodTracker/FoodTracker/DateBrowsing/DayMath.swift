//
//  DayMath.swift
//  FoodTracker
//
//  和「哪一天」有关的计算：一天从几点开始、记录存在哪一天、日期怎么显示。
//  只做计算，不涉及界面和存储，所以可以单独写单元测试（FoodTrackerTests/DayMathTests.swift）。
//
//  几个约定：
//  - 一周从周一开始，不跟手机的地区设置走
//  - 「加一天」都用日历来算，不直接加 86400 秒：夏令时切换那天只有 23 或 25 个小时
//  - 每个函数都有 calendar 参数：App 里用默认值（手机当前的时区）；测试里传固定时区的日历，
//    这样测试结果不会因为电脑在哪个时区而变化
//

import Foundation

nonisolated enum DayMath {

    // MARK: - 日历设置

    /// 中文，一周从周一开始。只写 "zh_CN" 的话，系统认为一周从周日开始
    static let locale = Locale(identifier: "zh_CN@fw=mon")

    /// 公历、一周从周一开始。时区默认跟随手机（换了时区会自动更新）
    static func makeCalendar(timeZone: TimeZone = .autoupdatingCurrent) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        calendar.timeZone = timeZone
        calendar.firstWeekday = 2  // 2 = 周一
        calendar.minimumDaysInFirstWeek = 4
        return calendar
    }

    /// App 里用的日历。每次都新建一个，手机换了时区也能马上生效
    static var calendar: Calendar { makeCalendar() }

    // MARK: - 天

    /// 这一天的 0 点
    static func startOfDay(_ date: Date, calendar: Calendar = DayMath.calendar) -> Date {
        calendar.startOfDay(for: date)
    }

    /// 往后数 n 天（n 为负数就是往前数）
    static func addingDays(_ n: Int, to date: Date, calendar: Calendar = DayMath.calendar) -> Date {
        calendar.date(byAdding: .day, value: n, to: date) ?? date
    }

    // MARK: - 记录存在哪一天

    /// 把日期变成 20260929 这样的数字，存进数据库。
    /// 记录时就把年月日固定下来：以后手机换了时区（比如从中国回到美国），这条记录还是算在这一天
    static func dayKey(for date: Date, calendar: Calendar = DayMath.calendar) -> Int {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return (c.year ?? 0) * 10000 + (c.month ?? 0) * 100 + (c.day ?? 0)
    }

    /// 反过来：20260929 → 这一天的 0 点（按手机当前的时区）
    static func date(fromDayKey key: Int, calendar: Calendar = DayMath.calendar) -> Date {
        let components = DateComponents(year: key / 10000, month: key / 100 % 100, day: key % 100)
        return calendar.date(from: components) ?? .distantPast
    }

    // MARK: - 星期

    static let weekdayNames = ["周一", "周二", "周三", "周四", "周五", "周六", "周日"]

    /// 周一 = 0，周二 = 1 … 周日 = 6
    static func weekdayIndex(of date: Date, calendar: Calendar = DayMath.calendar) -> Int {
        // 系统的 weekday 是周日 = 1、周一 = 2 … 周六 = 7，这里换算成从周一开始
        (calendar.component(.weekday, from: date) + 5) % 7
    }

    // MARK: - 显示用的文字（直接拼数字，不用系统的日期格式，结果固定，也不会出现「2,026」）

    /// 「9月20日」；不是今年的日期带上年份：「2025年12月31日」
    static func shortDate(_ date: Date, today: Date, calendar: Calendar = DayMath.calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        let monthDay = "\(c.month ?? 0)月\(c.day ?? 0)日"
        return c.year == calendar.component(.year, from: today) ? monthDay : "\(c.year ?? 0)年" + monthDay
    }

    /// 标题：「今天」「昨天」「9月20日 周日」「2025年12月31日 周三」
    static func dayTitle(for day: Date, today: Date, calendar: Calendar = DayMath.calendar) -> String {
        let d = startOfDay(day, calendar: calendar)
        let t = startOfDay(today, calendar: calendar)
        if d == t { return "今天" }
        if d == addingDays(-1, to: t, calendar: calendar) { return "昨天" }
        return shortDate(d, today: t, calendar: calendar) + " " + weekdayNames[weekdayIndex(of: d, calendar: calendar)]
    }

    /// 保存按钮上的字：「保存到今日」「保存到 9月20日」
    static func saveButtonTitle(day: Date, today: Date, calendar: Calendar = DayMath.calendar) -> String {
        if startOfDay(day, calendar: calendar) == startOfDay(today, calendar: calendar) { return "保存到今日" }
        return "保存到 " + shortDate(day, today: today, calendar: calendar)
    }

    /// 查看往日时，底部提示新记录会存到哪一天：「记录到 9月28日 周一」；今天不需要提示（nil）
    static func recordCaption(day: Date, today: Date, calendar: Calendar = DayMath.calendar) -> String? {
        let d = startOfDay(day, calendar: calendar)
        if d == startOfDay(today, calendar: calendar) { return nil }
        return "记录到 " + shortDate(d, today: today, calendar: calendar) + " " + weekdayNames[weekdayIndex(of: d, calendar: calendar)]
    }
}
