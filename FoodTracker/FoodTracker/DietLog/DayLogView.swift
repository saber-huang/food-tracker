//
//  DayLogView.swift
//  FoodTracker
//
//  一天的饮食记录：顶部是和目标比较的卡片，下面按早餐、午餐、晚餐、加餐分组列出每一条记录。
//  「今日」页用它显示今天；以后翻看往日也用它。
//

import SwiftData
import SwiftUI

struct DayLogView: View {
    let day: Date  // 显示哪一天
    let today: Date  // 今天是哪一天（用来判断文字怎么写）
    let bodyInfo: BodyInfo  // 算每日目标用

    @Query private var entries: [FoodEntry]
    @Environment(\.modelContext) private var modelContext

    init(day: Date, today: Date, bodyInfo: BodyInfo) {
        self.day = day
        self.today = today
        self.bodyInfo = bodyInfo
        // 查询条件在创建页面时算好：换了一天，SwiftUI 会重新创建这个页面，查询也跟着换
        _entries = Query(filter: FoodEntry.predicate(day: day), sort: \FoodEntry.createdAt)
    }

    private var isToday: Bool { DayMath.startOfDay(day) == DayMath.startOfDay(today) }

    /// 某一餐的记录（已经按添加的先后排好）
    private func entries(for meal: MealType) -> [FoodEntry] {
        entries.filter { $0.meal == meal }
    }

    var body: some View {
        List {
            // 往日没有记录时不显示卡片，只显示「这一天没有记录」
            if isToday || !entries.isEmpty {
                Section {
                    DayProgressCard(consumed: DietLogMath.total(of: entries.map(\.values)), bodyInfo: bodyInfo, isToday: isToday)
                    NavigationLink("怎么算的") {
                        ExplanationView(bodyInfo: bodyInfo)
                    }
                }
            }

            ForEach(MealType.allCases) { meal in
                let mealEntries = entries(for: meal)
                if !mealEntries.isEmpty {
                    Section {
                        ForEach(mealEntries) { entry in
                            EntryRow(entry: entry)
                        }
                        // 向左滑动出现「删除」
                        .onDelete { offsets in
                            delete(offsets.map { mealEntries[$0] })
                        }
                    } header: {
                        HStack {
                            Label(meal.title, systemImage: meal.systemImage)
                            Spacer()
                            Text("\(DietLogMath.total(of: mealEntries.map(\.values)).caloriesKcal.noDecimal) 千卡")
                        }
                    }
                }
            }

            if entries.isEmpty {
                Section {
                    ContentUnavailableView(
                        isToday ? "今天还没有记录" : "这一天没有记录",
                        systemImage: "fork.knife",
                        description: Text(isToday ? "拍一张餐食照片，或点「手动添加」。" : "可以用下方的按钮补记。")
                    )
                }
            }
        }
    }

    private func delete(_ list: [FoodEntry]) {
        for entry in list {
            modelContext.delete(entry)
        }
        try? modelContext.save()
    }
}

#Preview("今天有两条记录") {
    NavigationStack {
        DayLogView(day: .now, today: .now, bodyInfo: SampleData.profile.bodyInfo)
            .navigationTitle("今日")
    }
    .modelContainer(SampleData.previewContainer)
}

#Preview("往日没有记录") {
    NavigationStack {
        DayLogView(day: DayMath.addingDays(-3, to: .now), today: .now, bodyInfo: SampleData.profile.bodyInfo)
            .navigationTitle("今日")
    }
    .modelContainer(SampleData.previewContainer)
}
