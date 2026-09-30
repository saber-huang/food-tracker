//
//  MonthPickerSheet.swift
//  FoodTracker
//
//  点「今日」页顶栏的月份弹出的月历：有记录的日期带小圆点，点一天就跳过去。
//

import SwiftData
import SwiftUI

struct MonthPickerSheet: View {
    let selectedDay: Date  // 现在正在看的那一天
    let today: Date
    let onPick: (Date) -> Void

    @Environment(\.dismiss) private var dismiss
    @Query private var entries: [FoodEntry]

    init(selectedDay: Date, today: Date, onPick: @escaping (Date) -> Void) {
        self.selectedDay = selectedDay
        self.today = today
        self.onPick = onPick
        // 一次查出能翻到的整个范围里的记录，每个月的圆点马上就有，翻月不用再查
        _entries = Query(
            filter: FoodEntry.predicate(from: DayMath.oldestDay(today: today), to: DayMath.addingDays(1, to: today)))
    }

    /// 有记录的日期（每天的 0 点）
    private var recordDays: Set<Date> {
        Set(entries.map { $0.day() })
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                MonthCalendar(recordDays: recordDays, selectedDay: selectedDay, today: today) { day in
                    onPick(day)
                    dismiss()
                }
                .padding(.horizontal)
                // 旁白读不出圆点，所以用文字说明一下
                Text("有记录的日期下方有小圆点；未来的日期不能选择")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding()
                Spacer(minLength: 0)
            }
            .navigationTitle("选择日期")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
    }
}

#Preview {
    MonthPickerSheet(selectedDay: DayMath.startOfDay(.now), today: DayMath.startOfDay(.now)) { _ in }
        .modelContainer(SampleData.previewContainer)
}
