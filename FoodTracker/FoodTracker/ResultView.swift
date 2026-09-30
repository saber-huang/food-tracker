//
//  ResultView.swift
//  FoodTracker
//
//  结果页：列出识别到的每种食物，点一项可以修改，向左滑可以删掉，也能补一项；
//  选好记到哪一餐，点「保存到今日」就存进饮食记录。底部是「热量为 AI 估算」的提示。
//  照片不保存，只保存食物和营养数据。
//

import SwiftData
import SwiftUI

struct ResultView: View {
    let result: AnalyzeResult
    let photo: UIImage?
    let day: Date  // 记到哪一天：打开这页时「今日」页正在看的那天，这页里不能改
    let today: Date  // 今天是哪一天：决定按钮上写「保存到今日」还是「保存到 9月20日」
    let onSaved: () -> Void  // 保存成功后由「今日」页关掉这一页、清掉照片

    @Environment(\.modelContext) private var modelContext
    @State private var items: [EditableItem]  // 识别到的食物，用户可以改、删、加
    @State private var meal: MealType  // 记到哪一餐
    @State private var editingItem: EditableItem?  // 正在修改的一项，有值时弹出表单
    @State private var isAddingItem = false  // 是否弹出「添加食物」
    @State private var isSaving = false  // 防止快速连点两次「保存」存成两份

    init(result: AnalyzeResult, photo: UIImage?, day: Date, today: Date, onSaved: @escaping () -> Void) {
        self.result = result
        self.photo = photo
        self.day = day
        self.today = today
        self.onSaved = onSaved
        // 按现在几点默认选一餐；识别结果先复制成可以修改的一份，用户改的是这份，原始结果不动
        let meal = DietLogMath.suggestedMeal(hour: DayMath.calendar.component(.hour, from: .now))
        _meal = State(initialValue: meal)
        _items = State(initialValue: result.items.map { EditableItem($0, meal: meal, day: day) })
    }

    /// 有食物时显示列表和保存按钮；没识别到食物时显示提示
    private var showsList: Bool { result.isFood || !items.isEmpty }

    var body: some View {
        List {
            // 照片和 AI 的一句话总结
            Section {
                if let photo {
                    Image(uiImage: photo)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 220)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                Text(result.message)
            }

            if showsList {
                Section {
                    Picker("记到哪一餐", selection: $meal) {
                        ForEach(MealType.allCases) { meal in
                            Text(meal.title).tag(meal)
                        }
                    }
                    .pickerStyle(.segmented)
                    LabeledContent("记录日期", value: DayMath.dayTitle(for: day, today: today))
                } header: {
                    Text("记到哪一餐")
                } footer: {
                    Text("按现在的时间默认推荐，可以改。")
                }

                Section("识别到的食物（点一项可修改）") {
                    // 每一项有自己的 id，删掉一项时列表能正确地动画，弹出的表单也知道改的是哪一项
                    ForEach(items) { item in
                        Button {
                            editingItem = item
                        } label: {
                            FoodRow(item: item)
                        }
                        .buttonStyle(.plain)
                    }
                    // 向左滑动出现「删除」：只是从这个列表里去掉，保存之前都可以反悔（返回重来）
                    .onDelete { offsets in
                        items.remove(atOffsets: offsets)
                    }
                    Button {
                        isAddingItem = true
                    } label: {
                        Label("添加一项", systemImage: "plus.circle")
                    }
                }

                Section("整餐合计") {
                    TotalView(items: items)
                }
            } else {
                Section {
                    ContentUnavailableView(
                        "没有识别到食物",
                        systemImage: "questionmark.circle",
                        description: Text("可以返回换一张照片，也可以手动添加。")
                    )
                    // 手动加的一项会进入上面的列表，之后就和识别到食物一样：可以再改、再加，最后一起保存
                    Button("改为手动添加") { isAddingItem = true }
                }
            }
        }
        .navigationTitle("识别结果")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if showsList {
                    Button(DayMath.saveButtonTitle(day: day, today: today)) { save() }
                        .disabled(items.isEmpty || isSaving)
                }
            }
        }
        // 固定在页面最底部的提示
        .safeAreaInset(edge: .bottom) {
            Text("热量为 AI 估算，仅供参考；保存前可以修改。")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(.bar)
        }
        // 修改一项：保存后替换掉列表里 id 相同的那一项；表单里也能删掉这一项
        .sheet(item: $editingItem) { item in
            EntryEditView(
                draft: EntryDraft(item: item), title: "修改食物",
                onSave: { edited in
                    if let index = items.firstIndex(where: { $0.id == edited.id }) {
                        items[index] = edited
                    }
                },
                onDelete: {
                    items.removeAll { $0.id == item.id }
                })
        }
        // 补一项 AI 没认出来的食物
        .sheet(isPresented: $isAddingItem) {
            EntryEditView(draft: EntryDraft(meal: meal, day: day), title: "添加食物") { item in
                items.append(item)
            }
        }
    }

    private func save() {
        // 按钮变灰要等下一次刷新界面，所以这里再检查一次，连点两下也只存一份
        guard !isSaving else { return }
        isSaving = true
        // 每一项自己记的餐次和日期在这页用不上：以这页选的餐次、打开时定好的日期为准
        FoodEntry.insert(items, meal: meal, day: day, source: .photo, into: modelContext)
        try? modelContext.save()
        onSaved()
    }
}

/// 一种食物占一行：名称、可信度、热量、重量、三大营养素
private struct FoodRow: View {
    let item: EditableItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(item.name)
                    .font(.headline)
                ConfidenceBadge(confidence: item.confidence)
                Spacer()
                Text("\(item.values.caloriesKcal.noDecimal) 千卡")
                    .font(.headline)
            }
            // 不知道重量的一项不显示这一行
            if let weight = item.weightG {
                Text("约 \(weight.oneDecimal) 克")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Text(
                "蛋白质 \(item.values.proteinG.oneDecimal) 克 · 碳水 \(item.values.carbsG.oneDecimal) 克 · 脂肪 \(item.values.fatG.oneDecimal) 克"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        // 整行都能点，不只是文字
        .contentShape(Rectangle())
    }
}

/// 可信度小标签：高是绿色，中是橙色，低是红色；用户改过或自己添加的显示灰色的「已修改」
private struct ConfidenceBadge: View {
    let confidence: Confidence?

    private var color: Color {
        switch confidence {
        case .high: .green
        case .medium: .orange
        case .low: .red
        case nil: .secondary
        }
    }

    var body: some View {
        Text(confidence?.label ?? "已修改")
            .font(.caption2.bold())
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundStyle(color)
            .background(color.opacity(0.15), in: Capsule())
    }
}

/// 整餐合计：大号的总热量，下面是三大营养素。按现在列表里的几项算，改了、删了都会跟着变
private struct TotalView: View {
    let items: [EditableItem]

    var body: some View {
        let total = DietLogMath.total(of: items.map(\.values))
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(total.caloriesKcal.noDecimal)
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                Text("千卡")
                    .foregroundStyle(.secondary)
                Spacer()
                // 有一项不知道重量，总重量就算不准，写明「部分未填重量」
                if items.contains(where: { $0.weightG == nil }) {
                    Text("部分未填重量")
                        .foregroundStyle(.secondary)
                } else {
                    Text("共约 \(items.compactMap(\.weightG).reduce(0, +).noDecimal) 克")
                        .foregroundStyle(.secondary)
                }
            }
            HStack {
                MacroView(name: "蛋白质", grams: total.proteinG, color: .blue)
                MacroView(name: "碳水", grams: total.carbsG, color: .orange)
                MacroView(name: "脂肪", grams: total.fatG, color: .pink)
            }
        }
        .padding(.vertical, 4)
    }
}

/// 一种营养素：数值 + 名称
private struct MacroView: View {
    let name: String
    let grams: Double
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text("\(grams.oneDecimal) 克")
                .font(.headline)
                .foregroundStyle(color)
            Text(name)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// Xcode 右侧画布里的预览，用假数据看看页面长什么样
#Preview("有食物") {
    NavigationStack {
        ResultView(
            result: SampleData.analyzeResult, photo: nil, day: DayMath.startOfDay(.now), today: DayMath.startOfDay(.now)
        ) {}
    }
    .modelContainer(for: AppModels.all, inMemory: true)
}

#Preview("没有食物") {
    NavigationStack {
        ResultView(
            result: SampleData.notFoodResult, photo: nil, day: DayMath.startOfDay(.now), today: DayMath.startOfDay(.now)
        ) {}
    }
    .modelContainer(for: AppModels.all, inMemory: true)
}
