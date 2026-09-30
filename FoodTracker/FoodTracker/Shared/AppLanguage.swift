//
//  AppLanguage.swift
//  FoodTracker
//
//  App 现在用哪种语言显示：简体中文或英文。
//  跟着手机的语言走（也可以在手机「设置」→ FoodTracker →「语言」里单独选）；
//  手机是其他语言（比如西班牙语）时显示英文。
//
//  界面上的文字大多由系统按 Localizable.xcstrings 自动换成对应的语言；
//  这里给需要在代码里判断语言的地方用：日期怎么拼（DayMath）、要 AI 用哪种语言回答。
//

import Foundation

nonisolated enum AppLanguage: String, CaseIterable {
    case zh, en

    /// App 现在显示的语言。系统在 App 启动时按手机设置选好，运行中不会变（改了手机语言，App 会重新启动）
    static var current: AppLanguage { from(Bundle.main.preferredLocalizations.first) }

    /// 把系统给的语言代码（zh-Hans、en、es……）换成 App 支持的两种之一：中文开头的算中文，其他都算英文
    static func from(_ identifier: String?) -> AppLanguage {
        (identifier ?? "").lowercased().hasPrefix("zh") ? .zh : .en
    }

    /// 发给后端的语言代码：识别结果和食谱用这种语言写
    var apiCode: String { rawValue }
}
