//
//  ResultView.swift
//  FoodTracker
//
//  识别结果（保存前的确认页）：从上到下是这一餐的照片（1～4 张）和 AI 的一句话总结、识别到的每种食物
//  （点一项可以修改份量和数字，向左滑可以删掉，也能补一项 AI 没认出来的）、整餐合计（旁边是「AI 估算 ⓘ」）
//  和「这餐吃了多少」（全部 / ¾ / 一半 / ¼：知道吃不完时直接选，合计按吃了的算）、
//  记到哪一天哪一餐；最下面固定着「保存这餐」。识别后不会自动保存，一定要用户点了才存。
//  不显示 AI 内部的把握程度；只有份量需要确认的那一项写「份量不确定 · 调整份量」，点一下就能改。
//  没认出食物时不给出任何热量：写「没有识别到足够清晰的食物」和几条拍照建议，可以「重新拍摄」或「手动添加」。
//  保存后回到「今日」，下方轻提示「已记录 3 项食物」。照片不保存，只保存食物和营养数据。
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
    @Environment(\.dismiss) private var dismiss
    @Environment(ToastCenter.self) private var toasts: ToastCenter?
    // 最近的记录：「添加一项」时给「最近使用」用
    @Query(FoodEntry.recentDescriptor) private var recentEntries: [FoodEntry]
    @State private var items: [EditableItem]  // 识别到的食物，用户可以改、删、加
    @State private var meal: MealType  // 记到哪一餐
    @State private var editingItem: EditableItem?  // 正在修改的一项，有值时弹出表单
    @State private var isAddingItem = false  // 是否弹出「添加食物」
    @State private var isSaving = false  // 防止快速连点两次「保存」存成两份
    /// 保存前改过识别结果（改了一项、删了一项或补了一项）：记录习惯里的「亲自校对」徽章
    @State private var hasAdjustedItems = false
    /// 这餐吃了多少：1 = 全部（一般拍照时还没吃，默认全部；吃完以后可以在「今日」里再调）
    @State private var eatenFraction = 1.0

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
                // 一张照片时并排；几张照片时先一排缩略图，下面是总结。没认出食物时这句话放进下面的说明里
                if showsList {
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
                            hasAdjustedItems = true
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
                        TotalView(items: items, eatenFraction: eatenFraction)
                        VStack(alignment: .leading, spacing: AppSpacing.xs) {
                            Text("这餐吃了多少")
                                .font(.subheadline)
                                .foregroundStyle(AppColors.textSecondary)
                            AppSegmentedControl(
                                title: String(localized: "这餐吃了多少"), selection: $eatenFraction, options: EatenPortion.mealOptions,
                                label: EatenPortion.mealLabel, accessibilityLabel: EatenPortion.spokenMealLabel)
                        }
                        .padding(.vertical, AppSpacing.xxs)
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
                    } footer: {
                        Text("吃完以后也可以在「今日」里调整，还能拍一张剩下的让 AI 估算。")
                            .font(AppTypography.detail)
                            .foregroundStyle(AppColors.textSecondary)
                    }

                    // 记到哪一天（打开这页时就定好了，这里只显示）、哪一餐；紧挨着下面的保存按钮，保存前最后看一眼
                    Section {
                        LabeledContent("记录日期", value: DayMath.dayTitle(for: day, today: today))
                            .foregroundStyle(AppColors.textPrimary)
                        // 四个餐次一看就懂，不另写标题；旁白会读出「记到哪一餐」
                        AppSegmentedControl(title: String(localized: "记到哪一餐"), selection: $meal, options: MealType.allCases) {
                            $0.title
                        }
                        .listRowInsets(EdgeInsets(top: AppSpacing.sm, leading: AppSpacing.sm, bottom: AppSpacing.sm, trailing: AppSpacing.sm))
                    }
                } else {
                    Section {
                        notFoodState
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
                Button(DayMath.saveButtonTitle(day: day, today: today), action: save)
                    .buttonStyle(.appPrimary)
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
                        if items[index] != edited { hasAdjustedItems = true }
                        items[index] = edited
                    }
                },
                onDelete: {
                    items.removeAll { $0.id == item.id }
                    hasAdjustedItems = true
                })
        }
        // 补一项 AI 没认出来的食物（「最近使用」里点一下就能填好）
        .sheet(isPresented: $isAddingItem) {
            EntryEditView(
                draft: EntryDraft(meal: meal, dayKey: dayKey), title: String(localized: "添加食物"),
                suggestions: RecentFoods.from(recentEntries.map(\.recentFood))
            ) { item in
                items.append(item)
                hasAdjustedItems = true
            }
        }
    }

    /// 没认出食物：不给出任何热量（平时由「确认照片」页处理，这里只在调试的示例结果里出现）。
    /// 和其他出错状态同一个样子：没有热气的碗、一句能照着做的话、「重新拍摄」「手动添加」
    private var notFoodState: some View {
        BrandedStateView(
            kind: .error, title: String(localized: "没有识别到足够清晰的食物"),
            message: String(localized: "这张照片里的食物不够清晰，可以换个角度再试一次。"), visualWidth: 72
        ) {
            // 回到「确认照片」页：照片都还在，可以重拍、补拍
            Button("重新拍摄") { dismiss() }
                .buttonStyle(.appPrimary)
            // 手动加的一项会进入列表，之后就和识别到食物一样：可以再改、再加，最后一起保存
            Button("手动添加") { isAddingItem = true }
                .buttonStyle(.appSecondary)
        }
        .padding(.vertical, AppSpacing.md)
    }

    /// 照片缩略图（就是刚才拍的或选的照片，旁白不用读）
    private func thumbnail(_ photo: UIImage, size: CGFloat) -> some View {
        Image(uiImage: photo)
            .resizable()
            .scaledToFill()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous))
            .accessibilityHidden(true)
    }

    private func save() {
        // 按钮变灰要等下一次刷新界面，所以这里再检查一次，连点两下也只存一份
        guard !isSaving else { return }
        isSaving = true
        // 改过 AI 的结果再保存：先记下来，保存后重新统计记录习惯时就能得到「亲自校对」徽章
        if hasAdjustedItems { AchievementStore.markAdjustedAI() }
        // 每一项自己记的餐次和日期在这页用不上：以这页选的餐次、打开时定好的日期为准。
        // 选了「这餐吃了多少」：每一样按同样的比例记（原来的份量也记住，之后在「今日」里还能改回全部）
        FoodEntry.insert(items, meal: meal, dayKey: dayKey, source: .photo, into: modelContext, eatenFraction: eatenFraction)
        try? modelContext.save()
        // 回到「今日」页，下方轻提示一下，同时轻轻震一下（不弹「保存成功」的大框）
        toasts?.success(String(localized: "已记录 \(items.count) 项食物"))
        onSaved()
    }
}

/// 一种食物占一行：名称、热量、份量、三大营养素；右边的小箭头表示点了可以修改。
/// 不显示 AI 的把握程度；只有份量需要确认时写「份量不确定 · 调整份量」
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
            HStack(alignment: .firstTextBaseline) {
                Text(item.name)
                    .font(.headline)
                    .foregroundStyle(AppColors.textPrimary)
                    .lineLimit(2)
                Spacer(minLength: AppSpacing.xs)
                Text("\(item.values.caloriesKcal.noDecimal) 千卡")
                    .font(AppTypography.number)
                    .foregroundStyle(AppColors.textPrimary)
                    .fixedSize()
            }
            // AI 没把握的份量不假装准确：写「份量不确定」，点这一行就能调整
            if item.confidence == .low {
                LowConfidenceBadge()
            } else if let weight = item.weightG {
                // 不知道重量的一项不显示这一行
                Text("约 \(weight.oneDecimal) 克")
                    .font(.subheadline)
                    .foregroundStyle(AppColors.textSecondary)
            }
            // 三种营养素都是 0（只填了热量）时不显示，免得看起来像「没有蛋白质、碳水、脂肪」
            if item.values.proteinG > 0 || item.values.carbsG > 0 || item.values.fatG > 0 {
                Text(
                    "蛋白质 \(item.values.proteinG.oneDecimal) 克 · 碳水 \(item.values.carbsG.oneDecimal) 克 · 脂肪 \(item.values.fatG.oneDecimal) 克"
                )
                .font(.caption)
                .foregroundStyle(AppColors.textSecondary)
            }
        }
        .padding(.vertical, 4)
        // 整行都能点，不只是文字
        .contentShape(Rectangle())
    }
}

/// 份量需要确认的那一项：「⚠︎ 份量不确定 · 调整份量」（整行都能点，点了打开修改）
private struct LowConfidenceBadge: View {
    var body: some View {
        HStack(spacing: AppSpacing.xxs) {
            Image(systemName: "exclamationmark.circle")
                .accessibilityHidden(true)
            Text("份量不确定")
            Text(verbatim: "·")
                .accessibilityHidden(true)
            Text("调整份量")
                .fontWeight(.semibold)
        }
        .font(.subheadline)
        .foregroundStyle(AppColors.confidenceLow)
        .accessibilityElement(children: .combine)
    }
}

/// 整餐合计：大号的总热量，下面是三大营养素。按现在列表里的几项算，改了、删了都会跟着变。
/// 选了「这餐吃了多少」时按吃了的算（和保存后记录里的数字一样：每一样先取整再乘比例），下面一行「原来 620 千卡」
private struct TotalView: View {
    let items: [EditableItem]
    let eatenFraction: Double

    @ScaledMetric(relativeTo: .largeTitle) private var numberSize: CGFloat = 36

    var body: some View {
        let served = DietLogMath.total(of: items.map(\.values))
        let total = DietLogMath.total(
            of: items.map { EatenPortion.eatenValues(served: DietLogMath.rounded($0.values), fraction: eatenFraction) })
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(total.caloriesKcal.noDecimal)
                    .font(AppTypography.heroNumber(size: numberSize))  // 和首页的大数字同一种字，跟着系统字号变大
                    .foregroundStyle(AppColors.textPrimary)
                    .contentTransition(.numericText())
                Text("千卡")
                    .font(AppTypography.heroCaption)
                    .foregroundStyle(AppColors.textSecondary)
                Spacer()
                // 有一项不知道重量，总重量就算不准，写明「部分未填重量」
                if items.contains(where: { $0.weightG == nil }) {
                    Text("部分未填份量")
                        .foregroundStyle(AppColors.textSecondary)
                } else {
                    Text("共约 \((items.compactMap(\.weightG).reduce(0, +) * eatenFraction).noDecimal) 克")
                        .foregroundStyle(AppColors.textSecondary)
                }
            }
            if eatenFraction < 1 {
                Text("原来 \(served.caloriesKcal.noDecimal) 千卡，按「\(EatenPortion.itemLabel(eatenFraction))」算")
                    .font(AppTypography.detail)
                    .foregroundStyle(AppColors.textSecondary)
                    .monospacedDigit()
            }
            HStack {
                NutrientColumn(name: String(localized: "蛋白质"), value: total.proteinG.oneDecimal, color: AppColors.protein)
                NutrientColumn(name: String(localized: "碳水"), value: total.carbsG.oneDecimal, color: AppColors.carbs)
                NutrientColumn(name: String(localized: "脂肪"), value: total.fatG.oneDecimal, color: AppColors.fat)
            }
        }
        .padding(.vertical, 4)
        .animation(.easeOut(duration: 0.15), value: eatenFraction)
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
