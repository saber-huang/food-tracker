//
//  LocalizationTests.swift
//  FoodTrackerTests
//
//  多语言的测试：App 用哪种语言、英文的日期怎么显示。
//  测试固定用简体中文运行（在 scheme 的测试设置里指定了语言和地区），所以别的测试里的中文结果不受电脑语言影响；
//  这里的英文结果都是指定 language: .en 算出来的。
//

import Foundation
import Testing

@testable import FoodTracker

private func calendar(_ zone: String) -> Calendar {
    DayMath.makeCalendar(timeZone: TimeZone(identifier: zone)!)
}

private func d(_ year: Int, _ month: Int, _ day: Int, hour: Int = 0, _ cal: Calendar) -> Date {
    cal.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
}

@Suite("多语言")
struct LocalizationTests {
    @Test("系统给的语言代码 → App 的语言：中文开头的算中文，其他都算英文")
    func languageMapping() {
        #expect(AppLanguage.from("zh-Hans") == .zh)
        #expect(AppLanguage.from("zh-Hans-CN") == .zh)
        #expect(AppLanguage.from("en") == .en)
        #expect(AppLanguage.from("en-GB") == .en)
        #expect(AppLanguage.from("es") == .en)
        #expect(AppLanguage.from(nil) == .en)
        #expect(AppLanguage.zh.apiCode == "zh")
        #expect(AppLanguage.en.apiCode == "en")
    }

    @Test("测试用简体中文运行，App 里有简体中文")
    func testHostRunsInChinese() {
        #expect(Bundle.main.localizations.contains("zh-Hans"))
        #expect(AppLanguage.current == .zh)
        // 可以翻译的文字在中文下还是原来的中文
        #expect(MealType.snack.title == "加餐")
        #expect(Goal.loseFat.title == "减脂")
    }

    @Test("两种语言都是一周从周一开始", arguments: AppLanguage.allCases)
    func mondayFirst(language: AppLanguage) {
        #expect(DayMath.locale(for: language).firstDayOfWeek == .monday)
        #expect(DayMath.weekdayNames(in: language).count == 7)
        #expect(DayMath.weekdayLetters(in: language).count == 7)
    }

    @Test("英文的日期文字", arguments: ["Asia/Shanghai", "America/Los_Angeles"])
    func englishDates(zone: String) {
        let cal = calendar(zone)
        let today = d(2026, 9, 29, hour: 10, cal)  // 周二
        func title(_ day: Date) -> String { DayMath.dayTitle(for: day, today: today, calendar: cal, language: .en) }
        #expect(title(d(2026, 9, 29, cal)) == "Today")
        #expect(title(d(2026, 9, 28, hour: 23, cal)) == "Yesterday")
        #expect(title(d(2026, 9, 20, cal)) == "Sun, Sep 20")
        #expect(title(d(2025, 12, 31, cal)) == "Wed, Dec 31, 2025")
        #expect(DayMath.saveButtonTitle(day: d(2026, 9, 29, cal), today: today, calendar: cal, language: .en) == "Save to Today")
        #expect(DayMath.saveButtonTitle(day: d(2026, 9, 20, cal), today: today, calendar: cal, language: .en) == "Save to Sep 20")
        #expect(DayMath.recordCaption(day: d(2026, 9, 29, cal), today: today, calendar: cal, language: .en) == nil)
        #expect(DayMath.recordCaption(day: d(2026, 9, 28, cal), today: today, calendar: cal, language: .en) == "Logging to Mon, Sep 28")
        #expect(DayMath.monthTitle(for: d(2026, 9, 29, cal), calendar: cal, language: .en) == "September 2026")
        #expect(DayMath.monthTitle(for: d(2026, 1, 4, cal), calendar: cal, language: .en) == "January 2026")
        #expect(DayMath.weekdayLetters(in: .en)[DayMath.weekdayIndex(of: d(2026, 10, 4, cal), calendar: cal)] == "S")
    }

    @Test("英文的旁白文字")
    func englishAccessibility() {
        let cal = calendar("America/Los_Angeles")
        let today = d(2026, 9, 29, cal)
        func label(_ day: Date, _ kcal: Double, _ target: Double) -> String {
            DayMath.cellAccessibilityLabel(day: day, today: today, kcal: kcal, target: target, calendar: cal, language: .en)
        }
        #expect(DayMath.percentText(kcal: 750, target: 1800, language: .en) == "42% of target")
        #expect(DayMath.percentText(kcal: 0, target: 2000, language: .en) == "No entries")
        #expect(label(d(2026, 9, 28, cal), 750, 1800) == "Mon, Sep 28, 750 kcal logged, 42% of target")
        #expect(label(d(2026, 9, 27, cal), 0, 1800) == "Sun, Sep 27, no entries")
        #expect(label(today, 300, 2000) == "Today, Tue, Sep 29, 300 kcal logged, 15% of target")
        #expect(label(d(2026, 9, 30, cal), 0, 2000) == "Wed, Sep 30, future date")
    }
}
