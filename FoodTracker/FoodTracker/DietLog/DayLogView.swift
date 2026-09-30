//
//  DayLogView.swift
//  FoodTracker
//
//  一天的饮食记录：顶部是和目标比较的卡片，下面按早餐、午餐、晚餐、加餐分组列出每一条记录。
//  点一条记录可以修改（包括改到别的餐、别的日期）或删除；向左滑也能删除。
//  「今日」页用它显示今天；翻看往日也用它。
//

import SwiftData
import SwiftUI

struct DayLogView<BelowCard: View>: View {
    let day: Date  // 显示哪一天
    let today: Date  // 今天是哪一天（用来判断文字怎么写）
    let bodyInfo: BodyInfo  // 算每日目标用
    private let belowCard: BelowCard  // 放在进度卡片正下方的内容：「今日」页放热量提示；翻看往日时什么都没有

    @Query private var entries: [FoodEntry]
    @Environment(\.modelContext) private var modelContext
    @State private var editingEntry: FoodEntry?  // 正在修改的记录，有值时弹出表单

    init(day: Date, today: Date, bodyInfo: BodyInfo, @ViewBuilder belowCard: () -> BelowCard) {
        self.day = day
        self.today = today
        self.bodyInfo = bodyInfo
        self.belowCard = belowCard()
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
                    NavigationLink("每日目标是怎么算的？") {
                        ExplanationView(bodyInfo: bodyInfo)
                    }
                }
            }

            belowCard

            ForEach(MealType.allCases) { meal in
                let mealEntries = entries(for: meal)
                if !mealEntries.isEmpty {
                    Section {
                        ForEach(mealEntries) { entry in
                            // 点一下打开修改表单
                            Button {
                                editingEntry = entry
                            } label: {
                                EntryRow(entry: entry)
                            }
                            .buttonStyle(.plain)
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
        // 整个列表只挂一个修改表单，点哪条就改哪条（每行各挂一个会开出很多份，还会互相干扰）
        .sheet(item: $editingEntry) { entry in
            EntryEditView(
                draft: EntryDraft(item: EditableItem(entry: entry)), title: "修改记录", showsMealPicker: true,
                showsDayPicker: true,
                onSave: { item in
                    // 改到别的餐或别的日期也在这里：这条记录会从这一天消失，出现在新的那天
                    entry.apply(item)
                    try? modelContext.save()
                },
                onDelete: {
                    editingEntry = nil
                    delete([entry])
                })
        }
    }

    private func delete(_ list: [FoodEntry]) {
        for entry in list {
            modelContext.delete(entry)
        }
        try? modelContext.save()
    }
}

extension DayLogView where BelowCard == EmptyView {
    /// 卡片下面不放东西的写法（翻看往日、预览）
    init(day: Date, today: Date, bodyInfo: BodyInfo) {
        self.init(day: day, today: today, bodyInfo: bodyInfo) { EmptyView() }
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
