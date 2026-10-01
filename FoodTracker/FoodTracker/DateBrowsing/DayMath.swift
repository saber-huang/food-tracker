//
//  DayMath.swift
//  FoodTracker
//
//  和「哪一天」有关的计算：一天从几点开始、记录存在哪一天、日期怎么显示。
//  只做计算，不涉及界面和存储，所以可以单独写单元测试（FoodTrackerTests/DayMathTests.swift）。
//
//  几个约定：
//  - 一周从周一开始，不跟手机的地区设置走（中文和英文都一样）
//  - 显示用的文字按 App 的语言拼：中文「9月20日 周日」，英文「Sun, Sep 20」。
//    每个拼文字的函数都有 language 参数：App 里用默认值（App 当前的语言），测试里可以指定
//  - 「加一天」都用日历来算，不直接加 86400 秒：夏令时切换那天只有 23 或 25 个小时
//  - 每个函数都有 calendar 参数：App 里用默认值（手机当前的时区）；测试里传固定时区的日历，
//    这样测试结果不会因为电脑在哪个时区而变化
//

import Foundation

nonisolated enum DayMath {

    // MARK: - 日历设置

    /// 日期选择器、月历用的语言和地区：跟着 App 的语言，一周都从周一开始。
    /// 只写 "zh_CN" 或 "en_US" 的话，系统认为一周从周日开始，所以加上 @fw=mon（第一天是周一）
    static let locale: Locale = locale(for: .current)

    static func locale(for language: AppLanguage) -> Locale {
        switch language {
        case .zh: Locale(identifier: "zh_CN@fw=mon")
        case .en: Locale(identifier: "en_US@fw=mon")
        }
    }

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

    /// 星期几的名字，周一在前：「周一」「Mon」
    static let weekdayNames: [String] = weekdayNames(in: .current)

    static func weekdayNames(in language: AppLanguage) -> [String] {
        switch language {
        case .zh: ["周一", "周二", "周三", "周四", "周五", "周六", "周日"]
        case .en: ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
        }
    }

    /// 周横条上每一列顶上的字：「一」「M」
    static let weekdayLetters: [String] = weekdayLetters(in: .current)

    static func weekdayLetters(in language: AppLanguage) -> [String] {
        switch language {
        case .zh: ["一", "二", "三", "四", "五", "六", "日"]
        case .en: ["M", "T", "W", "T", "F", "S", "S"]
        }
    }

    /// 英文月份：月份标题用全称，其他地方用缩写
    private static let englishMonths = [
        "January", "February", "March", "April", "May", "June",
        "July", "August", "September", "October", "November", "December",
    ]
    private static let englishShortMonths = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

    /// 1～12 月 → 英文月份（超出范围时返回空字符串，不会闪退）
    private static func englishMonth(_ month: Int?, short: Bool) -> String {
        let names = short ? englishShortMonths : englishMonths
        guard let month, (1...12).contains(month) else { return "" }
        return names[month - 1]
    }

    /// 周一 = 0，周二 = 1 … 周日 = 6
    static func weekdayIndex(of date: Date, calendar: Calendar = DayMath.calendar) -> Int {
        // 系统的 weekday 是周日 = 1、周一 = 2 … 周六 = 7，这里换算成从周一开始
        (calendar.component(.weekday, from: date) + 5) % 7
    }

    // MARK: - 周（周横条用）
    // 周横条的每一页是一周，用「离本周几周」这个整数当页码：0 = 本周，-1 = 上周 … 最早到 -520

    /// 最多往前翻多少周（10 年）
    static let weeksBack = 520
    static var weekOffsetRange: ClosedRange<Int> { -weeksBack...0 }

    /// 这一天所在那一周的周一 0 点
    static func weekStart(containing date: Date, calendar: Calendar = DayMath.calendar) -> Date {
        calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? startOfDay(date, calendar: calendar)
    }

    /// 从周一开始的 7 天
    static func days(inWeekStarting start: Date, calendar: Calendar = DayMath.calendar) -> [Date] {
        (0..<7).map { addingDays($0, to: start, calendar: calendar) }
    }

    /// 从本周的周一往前（或往后）数 offset 周的周一
    static func weekStart(offset: Int, from thisWeekStart: Date, calendar: Calendar = DayMath.calendar) -> Date {
        calendar.date(byAdding: .weekOfYear, value: offset, to: thisWeekStart) ?? thisWeekStart
    }

    /// 这一天在第几页：0 = 本周，-1 = 上周 …
    static func weekOffset(of day: Date, relativeTo today: Date, calendar: Calendar = DayMath.calendar) -> Int {
        calendar.dateComponents(
            [.weekOfYear], from: weekStart(containing: today, calendar: calendar), to: weekStart(containing: day, calendar: calendar)
        ).weekOfYear ?? 0
    }

    /// 能翻到的最早一天（520 周前的周一）
    static func oldestDay(today: Date, calendar: Calendar = DayMath.calendar) -> Date {
        weekStart(offset: -weeksBack, from: weekStart(containing: today, calendar: calendar), calendar: calendar)
    }

    /// 这一天能不能选：不能是未来，也不能早于能翻到的最早一天
    static func isSelectable(_ day: Date, today: Date, calendar: Calendar = DayMath.calendar) -> Bool {
        let d = startOfDay(day, calendar: calendar)
        return d >= oldestDay(today: today, calendar: calendar) && d <= startOfDay(today, calendar: calendar)
    }

    /// 翻到新的一周后该选中哪一天：原来选的那天还在这一周就不动；
    /// 否则选同一个星期几，但不能超过今天（比如从上周六翻回本周，本周六还没到，就选今天）
    static func selection(afterShowingWeekStarting start: Date, previous: Date, today: Date, calendar: Calendar = DayMath.calendar) -> Date {
        let end = addingDays(7, to: start, calendar: calendar)
        if previous >= start && previous < end { return previous }
        let sameWeekday = addingDays(weekdayIndex(of: previous, calendar: calendar), to: start, calendar: calendar)
        return min(sameWeekday, startOfDay(today, calendar: calendar))
    }

    // MARK: - 月历（系统的 UICalendarView）

    /// 月历能显示、能选的范围：最早一天的 0 点 ～ 今天的最后一秒（DateInterval 包含结束时刻，所以减 1 秒，不含明天 0 点）
    static func availableRange(today: Date, calendar: Calendar = DayMath.calendar) -> DateInterval {
        let t = startOfDay(today, calendar: calendar)
        return DateInterval(
            start: oldestDay(today: t, calendar: calendar), end: addingDays(1, to: t, calendar: calendar).addingTimeInterval(-1))
    }

    /// 给月历用的年月日（月历按它自己的日历理解这三个数）
    static func components(of day: Date, calendar: Calendar = DayMath.calendar) -> DateComponents {
        calendar.dateComponents([.year, .month, .day], from: day)
    }

    /// 月历给回来的年月日 → 这一天的 0 点。只看年月日，带着别的时区信息也不影响
    static func day(from components: DateComponents, calendar: Calendar = DayMath.calendar) -> Date? {
        guard let year = components.year, let month = components.month, let day = components.day else { return nil }
        return calendar.date(from: DateComponents(year: year, month: month, day: day))
    }

    // MARK: - 今天可能换了（过了午夜、回到 App、换了时区）

    /// 今天变了以后该显示哪一天。按顺序判断：
    /// 1. 正在看的那天不再是当地的 0 点 → 手机换了时区，直接看新的今天
    /// 2. 是回到 App（不是在前台过午夜），而且用户最后选的是「今天」→ 跟到新的今天
    /// 3. 其他情况保持不动，只有时钟被往回调时才退回到新的今天（不能停在未来）
    static func dayToShow(
        newToday: Date, selectedDay: Date, followsToday: Bool, appBecameActive: Bool, calendar: Calendar = DayMath.calendar
    ) -> Date {
        if startOfDay(selectedDay, calendar: calendar) != selectedDay { return newToday }
        if appBecameActive && followsToday { return newToday }
        return min(selectedDay, newToday)
    }

    // MARK: - 圆环

    /// 圆环画多满：吃了多少 ÷ 目标，限制在 0～1 之间（超过目标也只画满一圈）
    static func ringFraction(kcal: Double, target: Double) -> Double {
        target > 0 ? min(1, max(0, kcal / target)) : 0
    }

    /// 把一条条记录按天加总：[那天的 0 点: 热量]
    static func kcalByDay(_ samples: [DayKcal], calendar: Calendar = DayMath.calendar) -> [Date: Double] {
        var result: [Date: Double] = [:]
        for sample in samples {
            result[startOfDay(sample.day, calendar: calendar), default: 0] += sample.kcal
        }
        return result
    }

    // MARK: - 显示用的文字（直接拼数字，不用系统的日期格式，结果固定，也不会出现「2,026」）

    /// 中文「9月20日」，英文「Sep 20」；不是今年的日期带上年份：「2025年12月31日」「Dec 31, 2025」
    static func shortDate(
        _ date: Date, today: Date, calendar: Calendar = DayMath.calendar, language: AppLanguage = .current
    ) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        let isThisYear = c.year == calendar.component(.year, from: today)
        switch language {
        case .zh:
            let monthDay = "\(c.month ?? 0)月\(c.day ?? 0)日"
            return isThisYear ? monthDay : "\(c.year ?? 0)年" + monthDay
        case .en:
            let monthDay = "\(englishMonth(c.month, short: true)) \(c.day ?? 0)"
            return isThisYear ? monthDay : monthDay + ", \(c.year ?? 0)"
        }
    }

    /// 日期加星期：中文「9月20日 周日」，英文「Sun, Sep 20」
    private static func dateWithWeekday(_ day: Date, today: Date, calendar: Calendar, language: AppLanguage) -> String {
        let date = shortDate(day, today: today, calendar: calendar, language: language)
        let weekday = weekdayNames(in: language)[weekdayIndex(of: day, calendar: calendar)]
        switch language {
        case .zh: return date + " " + weekday
        case .en: return weekday + ", " + date
        }
    }

    /// 标题：「今天」「昨天」「9月20日 周日」「2025年12月31日 周三」；英文「Today」「Yesterday」「Sun, Sep 20」
    static func dayTitle(
        for day: Date, today: Date, calendar: Calendar = DayMath.calendar, language: AppLanguage = .current
    ) -> String {
        let d = startOfDay(day, calendar: calendar)
        let t = startOfDay(today, calendar: calendar)
        if d == t { return language == .zh ? "今天" : "Today" }
        // 有的地方夏令时从 0 点开始（比如古巴），「今天 0 点往前一天」可能落在昨天 1 点，所以再取一次那天的 0 点
        if d == startOfDay(addingDays(-1, to: t, calendar: calendar), calendar: calendar) {
            return language == .zh ? "昨天" : "Yesterday"
        }
        return dateWithWeekday(d, today: t, calendar: calendar, language: language)
    }

    /// 保存按钮上的字：今天是「保存这餐」，往日写明哪一天「保存到 9月20日」（免得记错日子）；
    /// 英文「Save Meal」「Save to Sep 20」
    static func saveButtonTitle(
        day: Date, today: Date, calendar: Calendar = DayMath.calendar, language: AppLanguage = .current
    ) -> String {
        let isToday = startOfDay(day, calendar: calendar) == startOfDay(today, calendar: calendar)
        switch language {
        case .zh: return isToday ? "保存这餐" : "保存到 " + shortDate(day, today: today, calendar: calendar, language: .zh)
        case .en: return isToday ? "Save Meal" : "Save to " + shortDate(day, today: today, calendar: calendar, language: .en)
        }
    }

    /// 记好一条以后的轻提示：今天写「已记录到午餐」；往日写上是哪天，「已记录到 9月28日 午餐」
    static func loggedMessage(
        meal: MealType, dayKey: Int, today: Date, calendar: Calendar = DayMath.calendar, language: AppLanguage = .current
    ) -> String {
        let day = date(fromDayKey: dayKey, calendar: calendar)
        let isToday = startOfDay(day, calendar: calendar) == startOfDay(today, calendar: calendar)
        switch language {
        case .zh:
            return isToday ? "已记录到" + meal.title : "已记录到 " + shortDate(day, today: today, calendar: calendar, language: .zh) + " " + meal.title
        case .en:
            return isToday ? "Logged to " + meal.title : "Logged to " + meal.title + " · " + shortDate(day, today: today, calendar: calendar, language: .en)
        }
    }

    /// 查看往日时，底部提示新记录会存到哪一天：「记录到 9月28日 周一」「Logging to Mon, Sep 28」；今天不需要提示（nil）
    static func recordCaption(
        day: Date, today: Date, calendar: Calendar = DayMath.calendar, language: AppLanguage = .current
    ) -> String? {
        let d = startOfDay(day, calendar: calendar)
        if d == startOfDay(today, calendar: calendar) { return nil }
        let date = dateWithWeekday(d, today: today, calendar: calendar, language: language)
        return language == .zh ? "记录到 " + date : "Logging to " + date
    }

    /// 顶栏中间的月份：「2026年9月」「September 2026」
    static func monthTitle(for day: Date, calendar: Calendar = DayMath.calendar, language: AppLanguage = .current) -> String {
        let c = calendar.dateComponents([.year, .month], from: day)
        switch language {
        case .zh: return "\(c.year ?? 0)年\(c.month ?? 0)月"
        case .en: return "\(englishMonth(c.month, short: false)) \(c.year ?? 0)"
        }
    }

    /// 周横条格子里的数字：「1」「28」
    static func dayNumber(_ day: Date, calendar: Calendar = DayMath.calendar) -> String {
        "\(calendar.component(.day, from: day))"
    }

    /// 旁白（VoiceOver）念的进度：「占目标 42%」「42% of target」；没吃就是「没有记录」。念的数字不封顶，画圆环时才封顶
    static func percentText(kcal: Double, target: Double, language: AppLanguage = .current) -> String {
        if kcal <= 0 { return language == .zh ? "没有记录" : "No entries" }
        guard target > 0 else { return language == .zh ? "已记录" : "Logged" }
        let percent = Int((kcal / target * 100).rounded())
        return language == .zh ? "占目标 \(percent)%" : "\(percent)% of target"
    }

    /// 周横条一个格子的旁白文字：「今天，9月29日 周二，已记录 300 千卡，占目标 15%」「9月30日 周三，未来的日期」；
    /// 英文「Today, Tue, Sep 29, 300 kcal logged, 15% of target」「Wed, Sep 30, future date」
    static func cellAccessibilityLabel(
        day: Date, today: Date, kcal: Double, target: Double, calendar: Calendar = DayMath.calendar,
        language: AppLanguage = .current
    ) -> String {
        let d = startOfDay(day, calendar: calendar)
        let t = startOfDay(today, calendar: calendar)
        let date = dateWithWeekday(d, today: t, calendar: calendar, language: language)
        let kcalText = NumberText.text(from: kcal.rounded())
        let percent = percentText(kcal: kcal, target: target, language: language)
        switch language {
        case .zh:
            let text = (d == t ? "今天，" : "") + date
            if d > t { return text + "，未来的日期" }
            if kcal <= 0 { return text + "，没有记录" }
            return text + "，已记录 \(kcalText) 千卡，" + percent
        case .en:
            let text = (d == t ? "Today, " : "") + date
            if d > t { return text + ", future date" }
            if kcal <= 0 { return text + ", no entries" }
            return text + ", \(kcalText) kcal logged, " + percent
        }
    }
}

/// 一条记录的「哪一天 + 多少热量」，给 kcalByDay 用
nonisolated struct DayKcal: Equatable {
    let day: Date
    let kcal: Double
}
