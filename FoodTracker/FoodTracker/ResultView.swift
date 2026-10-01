//
//  ResultView.swift
//  FoodTracker
//
//  识别结果（保存前的确认页）：从上到下是这一餐的照片（1～4 张）和 AI 的一句话总结、识别到的每种食物
//  （点一项可以修改份量和数字，向左滑可以删掉，也能补一项 AI 没认出来的）、整餐合计（旁边是「AI 估算 ⓘ」）、
//  记到哪一天哪一餐；最下面固定着「保存这餐」。识别后不会自动保存，一定要用户点了才存。
//  AI 没把握的份量写「份量不确定」，不假装很准。照片不保存，只保存食物和营养数据。
//

import SwiftData
import SwiftUI

struct ResultView: View {
    let result: AnalyzeResult
    let photos: [UIImage]  // 这一餐的照片（调试菜单里的示例结果没有照片）
    /// 记到哪一天：按下「开始识别」时「今日」页正在看的那天（20260929 这样的数字），这页里不能改
    let dayKey: Int
    let today: Date  // 今天是哪一天：决定按钮上写「保存到今日」还是「保存到 9月20日」
    let onSaved: () -> Void  // 保存成功后由「今日」页关掉这一页、清掉照片

    /// 显示用的日期（那天的 0 点）
    private var day: Date { DayMath.date(fromDayKey: dayKey) }

    @Environment(\.modelContext) private var modelContext
    @State private var items: [EditableItem]  // 识别到的食物，用户可以改、删、加
    @State private var meal: MealType  // 记到哪一餐
    @State private var editingItem: EditableItem?  // 正在修改的一项，有值时弹出表单
    @State private var isAddingItem = false  // 是否弹出「添加食物」
    @State private var isSaving = false  // 防止快速连点两次「保存」存成两份

    init(result: AnalyzeResult, photos: [UIImage], dayKey: Int, today: Date, onSaved: @escaping () -> Void) {
        self.result = result
        self.photos = photos
        self.dayKey = dayKey
        self.today = today
        self.onSaved = onSaved
        // 按现在几点默认选一餐；识别结果先复制成可以修改的一份，用户改的是这份，原始结果不动
        let meal = DietLogMath.suggestedMeal(at: .now)
        _meal = State(initialValue: meal)
        _items = State(initialValue: result.items.map { EditableItem($0, meal: meal, dayKey: dayKey) })
    }

    /// 有食物时显示列表和保存按钮；没识别到食物时显示提示
    private var showsList: Bool { result.isFood || !items.isEmpty }

    var body: some View {
        List {
            Group {
                // 照片（小图）和 AI 的一句话总结：下面的食物列表不用往下翻就看得到。
                // 一张照片时并排；几张照片时先一排缩略图，下面是总结
                Section {
                    if photos.count > 1 {
                        VStack(alignment: .leading, spacing: AppSpacing.sm) {
                            HStack(spacing: AppSpacing.xs) {
                                ForEach(photos.indices, id: \.self) { index in
                                    thumbnail(photos[index], size: 60)
                                }
                            }
                            Text(result.message)
                        }
                    } else {
                        HStack(alignment: .top, spacing: AppSpacing.sm) {
                            if let photo = photos.first {
                                thumbnail(photo, size: 76)
                            }
                            Text(result.message)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }

                if showsList {
                    Section {
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
                    } header: {
                        AppSectionHeader(title: String(localized: "识别到的食物"))
                    }

                    Section {
                        TotalView(items: items)
                    } header: {
                        HStack(alignment: .center) {
                            Text("整餐合计")
                                .font(AppTypography.sectionTitle)
                                .foregroundStyle(AppColors.textPrimary)
                            Spacer()
                            AIEstimateBadge()
                                .padding(.vertical, -AppSpacing.sm)
                        }
                        .textCase(nil)
                    }

                    // 记到哪一天（打开这页时就定好了，这里只显示）、哪一餐；紧挨着下面的保存按钮，保存前最后看一眼
                    Section {
                        LabeledContent("记录日期", value: DayMath.dayTitle(for: day, today: today))
                        Picker("记到哪一餐", selection: $meal) {
                            ForEach(MealType.allCases) { meal in
                                Text(meal.title).tag(meal)
                            }
                        }
                        .pickerStyle(.segmented)  // 四个餐次一看就懂，不另写标题；旁白会读出「记到哪一餐」
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
            .appCardRow()  // 卡片用暖白，分隔线很淡
        }
        .appListBackground()  // 页面用 App 的暖色背景（和「今日」页一样）
        .navigationTitle("识别结果")
        .navigationBarTitleDisplayMode(.inline)
        .hidesFloatingTabBar()
        // 固定在页面最底部：「保存这餐」（和其他页面的主按钮同一种样子）
        .safeAreaInset(edge: .bottom) {
            if showsList {
                let canSave = !items.isEmpty && !isSaving
                Button(action: save) {
                    Text(DayMath.saveButtonTitle(day: day, today: today))
                        .font(.body.weight(.semibold))
                        .foregroundStyle(AppColors.onBrand)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(
                            AppColors.brand.opacity(canSave ? 1 : 0.4),
                            in: RoundedRectangle(cornerRadius: AppRadius.button, style: .continuous))
                }
                .buttonStyle(AppPressStyle())
                .disabled(!canSave)
                .padding(.horizontal, AppSpacing.pageMargin)
                .padding(.vertical, AppSpacing.xs)
                .appBottomBar()
            }
        }
        // 修改一项：保存后替换掉列表里 id 相同的那一项；表单里也能删掉这一项
        .sheet(item: $editingItem) { item in
            EntryEditView(
                draft: EntryDraft(item: item), title: String(localized: "修改食物"),
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
            EntryEditView(draft: EntryDraft(meal: meal, dayKey: dayKey), title: String(localized: "添加食物")) { item in
                items.append(item)
            }
        }
    }

    /// 照片缩略图（就是刚才拍的或选的照片，旁白不用读）
    private func thumbnail(_ photo: UIImage, size: CGFloat) -> some View {
        Image(uiImage: photo)
            .resizable()
            .scaledToFill()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.thumbnail, style: .continuous))
            .accessibilityHidden(true)
    }

    private func save() {
        // 按钮变灰要等下一次刷新界面，所以这里再检查一次，连点两下也只存一份
        guard !isSaving else { return }
        isSaving = true
        // 每一项自己记的餐次和日期在这页用不上：以这页选的餐次、打开时定好的日期为准
        FoodEntry.insert(items, meal: meal, dayKey: dayKey, source: .photo, into: modelContext)
        try? modelContext.save()
        onSaved()
    }
}

/// 一种食物占一行：名称、可信度、热量、份量、三大营养素；右边的小箭头表示点了可以修改
private struct FoodRow: View {
    let item: EditableItem

    var body: some View {
        HStack(alignment: .center, spacing: AppSpacing.xs) {
            details
            AppChevron()
        }
        .contentShape(Rectangle())
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(item.name)
                    .font(.headline)
                ConfidenceBadge(confidence: item.confidence)
                Spacer()
                Text("\(item.values.caloriesKcal.noDecimal) 千卡")
                    .font(.headline)
            }
            // AI 没把握（可信度低）时不假装准确：写「份量不确定」，点这一行就能调整
            if item.confidence == .low {
                Text("份量不确定 · 点按调整")
                    .font(.subheadline)
                    .foregroundStyle(AppColors.confidenceLow)
            } else if let weight = item.weightG {
                // 不知道重量的一项不显示这一行
                Text("约 \(weight.oneDecimal) 克")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            // 三种营养素都是 0（只填了热量）时不显示，免得看起来像「没有蛋白质、碳水、脂肪」
            if item.values.proteinG > 0 || item.values.carbsG > 0 || item.values.fatG > 0 {
                Text(
                    "蛋白质 \(item.values.proteinG.oneDecimal) 克 · 碳水 \(item.values.carbsG.oneDecimal) 克 · 脂肪 \(item.values.fatG.oneDecimal) 克"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        // 整行都能点，不只是文字
        .contentShape(Rectangle())
    }
}

/// 可信度小标签：高是绿色，中是琥珀色，低是砖红色；用户改过或自己添加的显示灰色的「已修改」
private struct ConfidenceBadge: View {
    let confidence: Confidence?

    private var color: Color {
        switch confidence {
        case .high: AppColors.confidenceHigh
        case .medium: AppColors.confidenceMedium
        case .low: AppColors.confidenceLow
        case nil: .secondary
        }
    }

    var body: some View {
        Text(confidence?.label ?? String(localized: "已修改"))
            .font(.caption2.bold())
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundStyle(color)
            .background(color.opacity(AppColors.badgeOpacity), in: Capsule())
    }
}

/// 整餐合计：大号的总热量，下面是三大营养素。按现在列表里的几项算，改了、删了都会跟着变
private struct TotalView: View {
    let items: [EditableItem]

    @ScaledMetric(relativeTo: .largeTitle) private var numberSize: CGFloat = 36

    var body: some View {
        let total = DietLogMath.total(of: items.map(\.values))
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(total.caloriesKcal.noDecimal)
                    .font(AppTypography.heroNumber(size: numberSize))  // 和首页的大数字同一种字，跟着系统字号变大
                Text("千卡")
                    .foregroundStyle(.secondary)
                Spacer()
                // 有一项不知道重量，总重量就算不准，写明「部分未填重量」
                if items.contains(where: { $0.weightG == nil }) {
                    Text("部分未填份量")
                        .foregroundStyle(.secondary)
                } else {
                    Text("共约 \(items.compactMap(\.weightG).reduce(0, +).noDecimal) 克")
                        .foregroundStyle(.secondary)
                }
            }
            HStack {
                NutrientColumn(name: String(localized: "蛋白质"), value: total.proteinG.oneDecimal, color: AppColors.protein)
                NutrientColumn(name: String(localized: "碳水"), value: total.carbsG.oneDecimal, color: AppColors.carbs)
                NutrientColumn(name: String(localized: "脂肪"), value: total.fatG.oneDecimal, color: AppColors.fat)
            }
        }
        .padding(.vertical, 4)
    }
}

// Xcode 右侧画布里的预览，用假数据看看页面长什么样
#Preview("有食物") {
    NavigationStack {
        ResultView(
            result: SampleData.analyzeResult, photos: [], dayKey: DayMath.dayKey(for: .now),
            today: DayMath.startOfDay(.now)
        ) {}
    }
    .modelContainer(for: AppModels.all, inMemory: true)
}

#Preview("没有食物") {
    NavigationStack {
        ResultView(
            result: SampleData.notFoodResult, photos: [], dayKey: DayMath.dayKey(for: .now),
            today: DayMath.startOfDay(.now)
        ) {}
    }
    .modelContainer(for: AppModels.all, inMemory: true)
}
