//
//  DayLogView.swift
//  FoodTracker
//
//  一天的饮食记录页面，从上到下：
//  1. 主卡片：还可以吃多少、碗形进度、已摄入和目标、三大营养素（右上角的 ⓘ 打开「每日目标是怎么算的」）
//  2. 快速记录：拍照、相册、手动（由「今日」页传进来）
//  3. 热量提示（只在看今天时有，由「今日」页传进来）
//  4. 今日饮食：一张卡片里按早餐、午餐、晚餐、加餐分组列出每一条记录
//  点一条记录可以修改（包括改到别的餐、别的日期）或删除；向左滑也能删除。
//  「今日」页用它显示今天；翻看往日也用它。
//

import SwiftData
import SwiftUI

struct DayLogView<QuickLog: View, Hints: View>: View {
    let day: Date  // 显示哪一天
    let today: Date  // 今天是哪一天（用来判断文字怎么写）
    let bodyInfo: BodyInfo  // 算每日目标用
    private let quickLog: QuickLog  // 快速记录（拍照、相册、手动）
    private let hints: Hints  // 热量提示：「今日」页放在快速记录下面；翻看往日时什么都没有

    @Query private var entries: [FoodEntry]
    @Environment(\.modelContext) private var modelContext
    @State private var editingEntry: FoodEntry?  // 正在修改的记录，有值时弹出表单
    @State private var showsExplanation = false  // 是否打开「每日目标是怎么算的」

    init(
        day: Date, today: Date, bodyInfo: BodyInfo, @ViewBuilder quickLog: () -> QuickLog,
        @ViewBuilder hints: () -> Hints
    ) {
        self.day = day
        self.today = today
        self.bodyInfo = bodyInfo
        self.quickLog = quickLog()
        self.hints = hints()
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
            // 往日没有记录时不显示主卡片，只显示「这一天没有记录」
            if isToday || !entries.isEmpty {
                Section {
                    NutritionHeroCard(
                        consumed: DietLogMath.total(of: entries.map(\.values)), bodyInfo: bodyInfo, day: day, today: today
                    ) {
                        showsExplanation = true
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }
            }

            Section {
                quickLog
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            } header: {
                // 看往日时写明新记录会记到哪一天
                AppSectionHeader(
                    title: String(localized: "快速记录"),
                    trailing: DayMath.recordCaption(day: day, today: today) ?? String(localized: "记录一餐"))
            }

            hints

            mealsSection
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(AppSpacing.sectionGap)
        .contentMargins(.horizontal, AppSpacing.pageMargin, for: .scrollContent)
        .contentMargins(.top, AppSpacing.xs, for: .scrollContent)
        .appListBackground(glow: true)
        .navigationDestination(isPresented: $showsExplanation) {
            ExplanationView(bodyInfo: bodyInfo)
        }
        // 整个列表只挂一个修改表单，点哪条就改哪条（每行各挂一个会开出很多份，还会互相干扰）
        .sheet(item: $editingEntry) { entry in
            EntryEditView(
                draft: EntryDraft(item: EditableItem(entry: entry)), title: String(localized: "修改记录"), showsMealPicker: true,
                showsDayPicker: true,
                // 从食谱记的一餐：重量是食材生重加起来的，提醒一下（改重量时数字会按比例换算）
                note: entry.source == .recipe ? String(localized: "重量按食材生重合计。") : nil,
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

    /// 今日饮食：一张卡片，按餐分组；每一餐一个小标题，下面是这一餐的记录
    @ViewBuilder
    private var mealsSection: some View {
        let meals = MealType.allCases.filter { !entries(for: $0).isEmpty }
        Section {
            if entries.isEmpty {
                EmptyMealsRow(isToday: isToday)
                    .listRowBackground(AppColors.surfacePrimary)
            } else {
                ForEach(meals) { meal in
                    let mealEntries = entries(for: meal)
                    MealHeaderRow(
                        meal: meal, kcal: DietLogMath.total(of: mealEntries.map(\.values)).caloriesKcal,
                        showsDivider: meal != meals.first
                    )
                    .listRowInsets(rowInsets)
                    .listRowSeparator(.hidden)
                    .listRowBackground(AppColors.surfacePrimary)

                    ForEach(mealEntries) { entry in
                        // 点一下打开修改表单
                        Button {
                            editingEntry = entry
                        } label: {
                            MealRow(entry: entry)
                        }
                        .buttonStyle(.plain)
                        .listRowInsets(rowInsets)
                        .listRowSeparator(.hidden)
                        .listRowBackground(AppColors.surfacePrimary)
                    }
                    // 向左滑动出现「删除」
                    .onDelete { offsets in
                        delete(offsets.map { mealEntries[$0] })
                    }
                }
            }
        } header: {
            AppSectionHeader(
                title: isToday ? String(localized: "今日饮食") : String(localized: "这一天的饮食"),
                trailing: entries.isEmpty
                    ? nil : String(localized: "\(DietLogMath.total(of: entries.map(\.values)).caloriesKcal.noDecimal) 千卡"))
        }
    }

    /// 卡片里每一行的留白
    private var rowInsets: EdgeInsets {
        EdgeInsets(top: 6, leading: AppSpacing.cardPadding, bottom: 6, trailing: AppSpacing.cardPadding)
    }

    private func delete(_ list: [FoodEntry]) {
        for entry in list {
            modelContext.delete(entry)
        }
        try? modelContext.save()
    }
}

extension DayLogView where QuickLog == EmptyView, Hints == EmptyView {
    /// 只看记录、不放快速记录和提示的写法（预览用）
    init(day: Date, today: Date, bodyInfo: BodyInfo) {
        self.init(day: day, today: today, bodyInfo: bodyInfo) { EmptyView() } hints: { EmptyView() }
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
