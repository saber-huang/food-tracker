//
//  MonthCalendar.swift
//  FoodTracker
//
//  月历：把 UIKit 的 UICalendarView 包一层给 SwiftUI 用（和 CameraPicker 包相机是同一种做法）。
//  为什么不用 SwiftUI 自带的日期选择器：它不能在日期下面画小圆点，而我们要用圆点标出有记录的日子。
//  有记录的日期下面一个燕麦色小圆点；未来的日期变灰、不能点；点一天就把它交给 onPick。
//

import SwiftUI
import UIKit

struct MonthCalendar: UIViewRepresentable {
    let recordDays: Set<Date>  // 有记录的日期（每天的 0 点）
    let selectedDay: Date  // 打开时选中、并翻到它所在月份的那一天
    let today: Date
    let onPick: (Date) -> Void

    func makeUIView(context: Context) -> UICalendarView {
        let view = UICalendarView()
        // 和 App 其他地方用同一个日历：公历、中文、一周从周一开始
        view.calendar = DayMath.calendar
        view.locale = DayMath.locale
        // 先设能选的范围，再设显示哪个月（显示的月份必须在范围之内）
        view.availableDateRange = DayMath.availableRange(today: today)
        view.visibleDateComponents = DayMath.components(of: selectedDay)
        view.tintColor = UIColor(AppColors.Pair.brand)  // 选中的日期：品牌绿（不用系统蓝）
        // 月历自己想要的宽度比手机屏幕还宽一点：允许它缩到页面给的宽度，不然整页被撑宽、顶栏的「取消」贴到边上
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.delegate = context.coordinator
        let selection = UICalendarSelectionSingleDate(delegate: context.coordinator)
        selection.selectedDate = DayMath.components(of: selectedDay)
        view.selectionBehavior = selection
        return view
    }

    func updateUIView(_ view: UICalendarView, context: Context) {
        context.coordinator.parent = self
        // 月历开着时过了午夜：把范围放宽到新的今天，让它能选
        let range = DayMath.availableRange(today: today)
        if view.availableDateRange != range {
            view.availableDateRange = range
            view.selectionBehavior?.updateSelectableDates()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    /// 月历的回调都在这里：画圆点、判断能不能选、选了哪天
    final class Coordinator: NSObject, UICalendarViewDelegate, UICalendarSelectionSingleDateDelegate {
        var parent: MonthCalendar

        init(parent: MonthCalendar) {
            self.parent = parent
        }

        /// 这一天下面画什么：有记录就画一个燕麦色小圆点，没有就不画（nil）
        func calendarView(_ calendarView: UICalendarView, decorationFor dateComponents: DateComponents) -> UICalendarView.Decoration? {
            guard let day = DayMath.day(from: dateComponents), parent.recordDays.contains(day) else { return nil }
            return .default(color: UIColor(AppColors.Pair.oatMark), size: .small)
        }

        /// 这一天能不能选：未来的和太早的都不能（月历会把不能选的日期变灰）
        func dateSelection(_ selection: UICalendarSelectionSingleDate, canSelectDate dateComponents: DateComponents?) -> Bool {
            guard let dateComponents, let day = DayMath.day(from: dateComponents) else { return false }
            return DayMath.isSelectable(day, today: parent.today)
        }

        /// 用户点了一天
        func dateSelection(_ selection: UICalendarSelectionSingleDate, didSelectDate dateComponents: DateComponents?) {
            guard let dateComponents, let day = DayMath.day(from: dateComponents) else { return }
            parent.onPick(day)
        }
    }
}
