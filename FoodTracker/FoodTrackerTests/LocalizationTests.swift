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

/// App 里某种语言的文件夹（en.lproj、zh-Hans.lproj）
private func languageBundle(_ language: String) -> Bundle? {
    Bundle.main.path(forResource: language, ofType: "lproj").flatMap(Bundle.init(path:))
}

/// 某个语言文件里的全部文字：key → 所有译文（普通文字一条；单复数不同的文字每种写法各一条）
private func translations(_ table: String, _ language: String) -> [String: [String]] {
    guard let bundle = languageBundle(language) else { return [:] }
    var result: [String: [String]] = [:]
    if let url = bundle.url(forResource: table, withExtension: "strings"),
        let dict = NSDictionary(contentsOf: url) as? [String: String]
    {
        for (key, value) in dict { result[key, default: []].append(value) }
    }
    if let url = bundle.url(forResource: table, withExtension: "stringsdict"),
        let dict = NSDictionary(contentsOf: url) as? [String: Any]
    {
        for (key, value) in dict { result[key, default: []] += allStrings(in: value) }
    }
    return result
}

/// 把单复数规则里的每一种写法都取出来（跳过 NSStringFormatSpecTypeKey 这类说明用的值）
private func allStrings(in value: Any) -> [String] {
    if let dict = value as? [String: Any] {
        return dict.filter { !$0.key.hasPrefix("NSStringFormat") }.flatMap { allStrings(in: $0.value) }
    }
    return (value as? String).map { [$0] } ?? []
}

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

    @Test("每一句中文都有英文翻译", arguments: ["Localizable", "HintCopy", "InfoPlist"])
    func everythingTranslated(table: String) {
        let chinese = translations(table, "zh-Hans")
        let english = translations(table, "en")
        #expect(!chinese.isEmpty, "App 里没有找到 \(table) 的中文")
        for key in chinese.keys {
            let values = english[key] ?? []
            #expect(!values.isEmpty, "没有英文：\(key)")
            for value in values {
                #expect(value.range(of: "\\p{Han}", options: .regularExpression) == nil, "英文里还有中文：\(value)")
            }
        }
    }

    /// 英文提示文案不能用的词：和中文版的原则一样，不责备、不建议少吃或补偿、不提运动消耗，也不用感叹号
    static let bannedEnglish = [
        "exceed", "over the limit", "warning", "out of control", "binge", "indulge", "punish", "eat less", "diet",
        "cut back", "make up for", "compensate", "offset", "skip", "exercise", "work out", "workout", "burn", "fail", "!",
    ]

    @Test("英文的热量提示也不用会制造负罪感的词，也不用感叹号")
    func englishHintCopyIsGentle() {
        let english = translations("HintCopy", "en").values.flatMap { $0 }
        #expect(english.count > 40)
        for text in english {
            for word in Self.bannedEnglish {
                #expect(!text.lowercased().contains(word), "「\(word)」出现在：\(text)")
            }
        }
    }

    @Test("英文运行时能查到译文：单复数、调换顺序的数字都正确")
    func englishLookups() throws {
        let en = try #require(languageBundle("en"))
        func text(_ key: String, table: String? = nil) -> String {
            en.localizedString(forKey: key, value: nil, table: table)
        }
        #expect(text("加餐") == "Snack")
        #expect(text("减脂") == "Lose Fat")
        // 单复数：1 次和 3 次。按英文的语法规则选单复数（测试本身用中文运行，中文不分单复数）
        let scans = text("今天还可以识别 %lld 次")
        let english = Locale(identifier: "en")
        #expect(String(format: scans, locale: english, 1) == "1 photo scan left today")
        #expect(String(format: scans, locale: english, 3) == "3 photo scans left today")
        // 调换顺序：英文里先说热量、后说餐名
        let near = text("今天离目标还有约 %@ 千卡，可以留给%@。%@照常吃就好，稍微多一点也没关系。", table: "HintCopy")
        #expect(String(format: near, "210", "dinner", "dinner").hasPrefix("About 210 kcal to go today, which you can save for dinner."))
        let intro = text("按今天剩下的热量，为你推荐一份约 %@ 千卡的%@，份量已经算好了。", table: "HintCopy")
        #expect(String(format: intro, "400", "dinner").contains("a dinner of about 400 kcal"))
        // 相机权限的说明也有英文
        #expect(text("NSCameraUsageDescription", table: "InfoPlist").contains("photos of your meals"))
    }

    @Test("每个发给后端的请求都带上 App 的语言，后端的出错说明用同一种语言")
    @MainActor
    func requestCarriesLanguage() {
        let request = APIClient.makeRequest(path: "quota", method: "GET", timeout: 10)
        #expect(request.value(forHTTPHeaderField: "X-App-Lang") == AppLanguage.current.apiCode)
        #expect(request.value(forHTTPHeaderField: "X-Device-ID") != nil)
    }
}

