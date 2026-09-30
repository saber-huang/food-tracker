//
//  BodyUnits.swift
//  FoodTracker
//
//  身高、体重的单位：公制（厘米、公斤）或英制（英尺和英寸、磅）。
//  数据库里一直存厘米和公斤，计算公式也用公制；英制只在填写和显示时换算。
//  食物的重量一直用克，不跟这个设置走。
//
//  默认跟着手机的地区：美国用英制，其他地区用公制；「我的」页和填写资料时都可以切换。
//  只做换算和拼文字，不涉及界面，可以单独写单元测试（FoodTrackerTests/BodyUnitsTests.swift）。
//

import Foundation

nonisolated enum UnitSystem: String, CaseIterable, Codable {
    case metric, imperial

    /// 存在 UserDefaults 里用的名字
    static let key = "unitSystem"

    /// 这个地区默认用哪种单位：美国用英制，其他地区用公制
    static func regionDefault(for locale: Locale = .current) -> UnitSystem {
        locale.measurementSystem == .us ? .imperial : .metric
    }

    /// 现在用哪种单位：用户选过就用选的，没选过就按地区
    static func current(in defaults: UserDefaults = .standard) -> UnitSystem {
        defaults.string(forKey: key).flatMap(UnitSystem.init(rawValue:)) ?? regionDefault()
    }

    /// 以前的版本只能用公制。已经在用的人（已经有资料、没选过单位）继续用公制，
    /// 不会因为手机地区是美国就突然变成英尺和磅。只在第一次运行这个版本时判断一次（App 启动时调用）
    static func keepMetricForExistingUser(hasProfile: Bool, defaults: UserDefaults = .standard) {
        let checkedKey = "unitSystemChecked"
        guard !defaults.bool(forKey: checkedKey) else { return }
        defaults.set(true, forKey: checkedKey)
        if hasProfile && defaults.string(forKey: key) == nil {
            defaults.set(UnitSystem.metric.rawValue, forKey: key)
        }
    }

    /// 选项上的字
    var title: String {
        switch self {
        case .metric: String(localized: "公制（厘米、公斤）")
        case .imperial: String(localized: "英制（英尺、磅）")
        }
    }

    /// 填写资料时分段选择上的短写法
    var shortTitle: String {
        switch self {
        case .metric: String(localized: "厘米 / 公斤")
        case .imperial: String(localized: "英尺 / 磅")
        }
    }
}

nonisolated enum BodyUnits {
    /// 1 英寸 = 2.54 厘米，1 磅 = 0.45359237 公斤（都是国际约定的准确值）
    static let cmPerInch = 2.54
    static let kgPerPound = 0.45359237
    static let inchesPerFoot = 12.0

    // MARK: - 换算

    static func cm(feet: Double, inches: Double) -> Double {
        (feet * inchesPerFoot + inches) * cmPerInch
    }

    static func kg(pounds: Double) -> Double {
        pounds * kgPerPound
    }

    static func pounds(kg: Double) -> Double {
        kg / kgPerPound
    }

    /// 厘米 → 几英尺几英寸。英寸保留 1 位小数；四舍五入到 12 英寸时进位成下一英尺（不会出现 5 英尺 12 英寸）
    static func feetAndInches(cm: Double) -> (feet: Int, inches: Double) {
        let totalInches = (cm / cmPerInch * 10).rounded() / 10
        var feet = Int(totalInches / inchesPerFoot)
        var inches = ((totalInches - Double(feet) * inchesPerFoot) * 10).rounded() / 10
        if inches >= inchesPerFoot {
            feet += 1
            inches -= inchesPerFoot
        }
        return (feet, inches)
    }

    // MARK: - 填写资料时输入框里的文字（保留 1 位小数，整数不带小数点）

    static func heightTexts(cm: Double) -> (feet: String, inches: String) {
        let (feet, inches) = feetAndInches(cm: cm)
        return (String(feet), NumberText.text(from: inches))
    }

    static func poundsText(kg: Double) -> String {
        NumberText.text(from: (pounds(kg: kg) * 10).rounded() / 10)
    }

    /// 公制输入框：厘米、公斤保留 1 位小数
    static func metricText(_ value: Double) -> String {
        NumberText.text(from: (value * 10).rounded() / 10)
    }

    // MARK: - 显示用的文字（「我的」页）

    /// 身高：公制「165 厘米」；英制四舍五入到整英寸「5 英尺 5 英寸」
    static func heightDisplay(cm: Double, units: UnitSystem) -> String {
        switch units {
        case .metric:
            return String(localized: "\(cm.oneDecimal) 厘米")
        case .imperial:
            let totalInches = Int((cm / cmPerInch).rounded())
            let feet = totalInches / 12
            let inches = totalInches % 12
            return String(localized: "\(feet) 英尺 \(inches) 英寸")
        }
    }

    /// 体重：公制「60 公斤」；英制保留 1 位小数「132.3 磅」
    static func weightDisplay(kg: Double, units: UnitSystem) -> String {
        switch units {
        case .metric: String(localized: "\(kg.oneDecimal) 公斤")
        case .imperial: String(localized: "\(pounds(kg: kg).oneDecimal) 磅")
        }
    }
}
