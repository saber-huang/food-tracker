//
//  NumberText.swift
//  FoodTracker
//
//  输入框里的文字和数字之间的转换。资料页和饮食记录的输入框共用这一份。
//

import Foundation

nonisolated enum NumberText {
    /// 去掉空格后什么都没有
    static func isBlank(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// 文字转数字，转不了就是 nil。有些地区的键盘用逗号当小数点，这里一并支持；「无穷大」不算数字
    static func number(from text: String) -> Double? {
        let cleaned = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard let value = Double(cleaned), value.isFinite else { return nil }
        return value
    }

    /// 数字转文字：175.0 → "175"，62.5 → "62.5"。
    /// 特别大的数（绝对值 ≥ 10¹⁵）直接用科学计数法：转成整数会超出范围，App 会闪退
    static func text(from value: Double) -> String {
        guard value.rounded() == value, abs(value) < 1e15 else { return String(value) }
        return String(Int(value))
    }
}
