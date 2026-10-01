//
//  EntryEditView.swift
//  FoodTracker
//
//  填写或修改一项食物的表单。它只负责填写；点「保存」后把结果交给打开它的页面，由那个页面决定怎么存。
//  手动添加、修改识别结果里的一项、修改已保存的记录，都用这个表单。
//
//  默认只显示最常用的几项，十秒钟就能记完一条：
//  食物名称 →（记录到哪一餐、哪一天）→ 热量、份量 → 保存。
//  - 新的一项打开时，光标直接在「食物名称」里；下面是「最近使用」：点一下就填好名字和上次的份量、营养，
//    常吃的东西两下就能记完（没有记录过时不显示这一块）
//  - 数字框用数字键盘，单位（千卡、克）固定写在右边，离开输入框时数字自动整理（见 NumberRow）
//  - 「保存」在顶栏右边（和其他表单一样）。还差必填项时是浅色的，但仍然可以点：点了在最近的那一项下面提示「请输入食物名称」或「请输入热量」，
//    光标跳过去，轻轻震一下。一次只提示一项，不弹警告框
//  - 蛋白质、碳水、脂肪收在「更多营养信息（可选）」里，点开才显示；收起来不会清空已经填的数字
//    （右边写一行摘要）；已经有数字（比如修改识别结果）时一打开就是展开的
//  不长期显示解释文字：千焦换算、按比例换算的说明放在「热量和份量」旁边的 ⓘ 里。
//  手动填写的数字不是 AI 的数据，这里不出现「AI 估算」。
//

import SwiftData
import SwiftUI

struct EntryEditView: View {
    let title: String
    let showsMealPicker: Bool  // 是否显示「记到哪一餐」
    let showsDate: Bool  // 是否显示「日期」（点开可以改到别的一天；手动添加、修改已保存的记录时显示）
    let note: String?  // 份量下面的一行灰字（比如从食谱记的一餐：「份量按食材生重合计。」）
    let suggestions: [RecentFood]  // 「最近使用」：最近吃过的食物（从新到旧）；空的就不显示这一块
    let onSave: (EditableItem) -> Void
    let onDelete: (() -> Void)?  // 有值时多一个「删除这一项」按钮

    @Environment(\.dismiss) private var dismiss
    @State private var draft: EntryDraft
    @State private var didSave = false  // 防止快速连点两次「保存」存成两条
    @State private var showsNutrition: Bool  // 「更多营养信息」是不是展开的
    @State private var showsDatePicker = false
    @State private var saveAttempted = false  // 点过「保存」但还差必填项：在那一项下面提示
    @State private var missingTick = 0  // 每次没保存成功加 1：用来轻轻震一下
    @FocusState private var focusedField: Field?
    private enum Field { case name, weight, calories, protein, carbs, fat }
    private let startsBlank: Bool  // 新的一项（名字是空的）：打开时光标直接放进名称

    init(
        draft: EntryDraft, title: String, showsMealPicker: Bool = false, showsDate: Bool = false, note: String? = nil,
        suggestions: [RecentFood] = [], onSave: @escaping (EditableItem) -> Void, onDelete: (() -> Void)? = nil
    ) {
        _draft = State(initialValue: draft)
        _showsNutrition = State(initialValue: Self.startsWithNutritionShown(draft))
        self.title = title
        self.showsMealPicker = showsMealPicker
        self.showsDate = showsDate
        self.note = note
        self.suggestions = suggestions
        self.onSave = onSave
        self.onDelete = onDelete
        startsBlank = draft.name.isEmpty
    }

    /// 点了「保存」还差的第一项（一次只提示一项）：先是名称，再是热量
    private var firstMissing: Field? {
        guard saveAttempted else { return nil }
        if draft.nameError != nil && draft.name.trimmingCharacters(in: .whitespaces).isEmpty { return .name }
        if NumberText.isBlank(draft.caloriesText) { return .calories }
        return nil
    }

    /// 名称下面要显示的「最近使用」：正在输入名称时才出现，按已经打的字筛选
    private var shownSuggestions: [RecentFood] {
        guard focusedField == .name else { return [] }
        return RecentFoods.matching(suggestions, query: draft.name)
    }

    /// 打开时「更多营养信息」要不要展开：三种营养素有任何一个已经填了，就展开（不然看不到已有的数字）
    static func startsWithNutritionShown(_ draft: EntryDraft) -> Bool {
        ![draft.proteinText, draft.carbsText, draft.fatText].allSatisfy(NumberText.isBlank)
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                AppForm {
                    nameSection
                    if showsMealPicker || showsDate {
                        whenSection
                    }
                    caloriesSection
                    nutritionSection
                    if let onDelete {
                        // 先关掉表单再删：表单还开着的时候删掉它正在显示的记录，会出错
                        Button("删除这一项", role: .destructive) {
                            dismiss()
                            onDelete()
                        }
                        .buttonStyle(.appDestructive)
                    }
                }
                // 光标到了哪一行，就把那一行滚到中间：键盘弹出来也挡不住正在填的框
                .onChange(of: focusedField) { _, field in
                    guard let field else { return }
                    withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(field, anchor: .center) }
                }
            }
            // 任何一个数字框变了，交给草稿判断要不要按比例换算
            .onChange(of: draft.allTexts) { draft.textsChanged() }
            .toolbar(.hidden, for: .navigationBar)
            // 和「偏好和忌口」「编辑资料」同一个顶栏：左「取消」、右「保存」。
            // 还差必填项时「保存」是浅色的，但仍然可以点（点了提示缺什么）；键盘弹出来时也看得见
            .appSheetHeader(
                AppSheetHeader(
                    title: title, onCancel: { dismiss() }, confirmTitle: String(localized: "保存"),
                    confirmEnabled: !didSave, confirmDimmed: draft.output == nil, onConfirm: save))
            .toolbar {
                // 数字键盘没有「完成」键，在键盘上方加一个
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("完成") { focusedField = nil }
                }
            }
            .sheet(isPresented: $showsDatePicker) {
                datePickerSheet
            }
            // 新的一项：表单弹出来以后，光标放进名称（等弹出的动画走完，不然键盘不出来）
            .task {
                guard startsBlank else { return }
                try? await Task.sleep(for: .milliseconds(450))
                if focusedField == nil { focusedField = .name }
            }
            .sensoryFeedback(.warning, trigger: missingTick)
        }
        .appSheet()
    }

    // MARK: - 表单的几块

    private var nameSection: some View {
        AppFormSection(String(localized: "食物名称")) {
            TextField("名称", text: $draft.name, prompt: Text("例如：米饭").foregroundStyle(AppColors.textTertiary))
                .foregroundStyle(AppColors.textPrimary)
                .focused($focusedField, equals: .name)
                .submitLabel(.next)
                .onSubmit { focusedField = .calories }
                .accessibilityLabel("食物名称")
                .padding(.horizontal, AppSpacing.cardPadding)
                .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture { focusedField = .name }  // 点这一行的任何地方都能开始输入
                .id(Field.name)
            if firstMissing == .name {
                fieldHint(String(localized: "请输入食物名称"))
            } else if let error = draft.nameError, !draft.name.isEmpty, focusedField != .name {
                fieldHint(error)
            }
            let shown = shownSuggestions
            if !shown.isEmpty {
                AppFormDivider()
                RecentFoodSuggestions(foods: shown) { food in
                    draft.prefill(from: food)
                    // 填好了：收起键盘，填上的数字和「保存」都看得见
                    focusedField = nil
                }
                .padding(.horizontal, AppSpacing.cardPadding)
                .padding(.vertical, AppSpacing.xs)
            }
        }
    }

    /// 记录到哪一餐、哪一天
    private var whenSection: some View {
        AppFormSection(String(localized: "记录到")) {
            if showsMealPicker {
                // 默认按现在的时间选好（或者是从某一餐的 + 打开的那一餐），可以直接改
                AppSegmentedControl(
                    title: String(localized: "记到哪一餐"), selection: $draft.meal, options: MealType.allCases
                ) { $0.title }
                .padding(AppSpacing.sm)
            }
            if showsMealPicker && showsDate {
                AppFormDivider()
            }
            if showsDate {
                Button {
                    focusedField = nil
                    showsDatePicker = true
                } label: {
                    AppFormLinkLabel(title: String(localized: "日期"), value: DayMath.dayTitle(for: draft.displayDay, today: .now))
                }
                .buttonStyle(AppPressStyle(scales: false))
            }
        }
    }

    /// 热量（必填）和份量（选填）；标题旁边的 ⓘ 里是千焦换算和按比例换算的说明
    private var caloriesSection: some View {
        AppFormSection(title: String(localized: "热量和份量"), accessory: { InfoButton(topic: .caloriesAndPortion) }) {
            NumberRow(
                title: String(localized: "热量"), unit: String(localized: "千卡"), text: $draft.caloriesText, keyboard: .numberPad,
                error: draft.caloriesError, focus: $focusedField, field: .calories, prompt: String(localized: "必填"))
                .id(Field.calories)
            if firstMissing == .calories {
                fieldHint(String(localized: "请输入热量"))
            }
            AppFormDivider()
            NumberRow(
                title: String(localized: "份量"), unit: String(localized: "克"), text: $draft.weightText, keyboard: .decimalPad,
                error: draft.weightError, focus: $focusedField, field: .weight, prompt: String(localized: "选填"))
                .id(Field.weight)
            if let note {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(AppColors.textSecondary)
                    .padding(.horizontal, AppSpacing.cardPadding)
                    .padding(.bottom, AppSpacing.sm)
            }
            // 可能填错了的提醒：不阻止保存，只在真的对不上时出现
            if let warning = draft.kcalMismatchWarning {
                warningRow(warning)
            }
            if let warning = draft.macrosExceedWeightWarning {
                warningRow(warning)
            }
        }
    }

    /// 更多营养信息：蛋白质、碳水、脂肪，点一下展开或收起（收起不会清空已经填的数字）
    private var nutritionSection: some View {
        AppFormSection(nil) {
            Button {
                withAnimation(.easeOut(duration: 0.15)) { showsNutrition.toggle() }
            } label: {
                HStack(spacing: AppSpacing.xs) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(showsNutrition ? "收起营养信息" : "更多营养信息（可选）")
                            .foregroundStyle(AppColors.brand)
                        // 收起来的时候，如果已经填了，就在下面写一行摘要，免得以为没填
                        if !showsNutrition, let summary = macroSummary {
                            Text(summary)
                                .font(.caption)
                                .foregroundStyle(AppColors.textSecondary)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: AppSpacing.xs)
                    Image(systemName: "chevron.down")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(AppColors.textTertiary)
                        .rotationEffect(.degrees(showsNutrition ? 180 : 0))
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, AppSpacing.cardPadding)
                .padding(.vertical, AppSpacing.xs)
                .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(AppPressStyle(scales: false))
            .accessibilityHint(showsNutrition ? "收起蛋白质、碳水、脂肪" : "填写蛋白质、碳水、脂肪")

            if showsNutrition {
                AppFormDivider()
                NumberRow(
                    title: String(localized: "蛋白质"), unit: String(localized: "克"), text: $draft.proteinText, keyboard: .decimalPad,
                    error: draft.proteinError, focus: $focusedField, field: .protein, prompt: String(localized: "选填"))
                    .id(Field.protein)
                AppFormDivider()
                NumberRow(
                    title: String(localized: "碳水"), unit: String(localized: "克"), text: $draft.carbsText, keyboard: .decimalPad,
                    error: draft.carbsError, focus: $focusedField, field: .carbs, prompt: String(localized: "选填"))
                    .id(Field.carbs)
                AppFormDivider()
                NumberRow(
                    title: String(localized: "脂肪"), unit: String(localized: "克"), text: $draft.fatText, keyboard: .decimalPad,
                    error: draft.fatError, focus: $focusedField, field: .fat, prompt: String(localized: "选填"))
                    .id(Field.fat)
            }
        }
    }

    /// 「蛋白质 20 · 碳水 30 · 脂肪 10 克」；三种都没填时是 nil
    private var macroSummary: String? {
        let texts = [draft.proteinText, draft.carbsText, draft.fatText]
        guard !texts.allSatisfy(NumberText.isBlank) else { return nil }
        let shown = texts.map { NumberText.isBlank($0) ? "0" : $0.trimmingCharacters(in: .whitespaces) }
        return String(localized: "蛋白质 \(shown[0]) · 碳水 \(shown[1]) · 脂肪 \(shown[2]) 克")
    }

    /// 就近的一行提示（缺了必填项、填错了）：小字、柔和的砖红
    private func fieldHint(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(AppColors.destructive)
            .padding(.horizontal, AppSpacing.cardPadding)
            .padding(.bottom, AppSpacing.sm)
            .transition(.opacity)
    }

    private func warningRow(_ text: String) -> some View {
        Label(text, systemImage: "info.circle")
            .font(.caption)
            .foregroundStyle(AppColors.textSecondary)
            .padding(.horizontal, AppSpacing.cardPadding)
            .padding(.bottom, AppSpacing.sm)
    }

    /// 选日期：只能选到今天为止，不能记到未来。日期按中文显示（2026年9月29日）；
    /// 月历从周一开始：这要靠日历设置（只设地区的话还是从周日开始）
    private var datePickerSheet: some View {
        DatePicker("日期", selection: $draft.displayDay, in: ...Date.now, displayedComponents: .date)
            .datePickerStyle(.graphical)
            .environment(\.locale, DayMath.locale)
            .environment(\.calendar, DayMath.calendar)
            .tint(AppColors.brand)
            .padding(.horizontal, AppSpacing.md)
            .frame(maxHeight: .infinity, alignment: .top)
            .appSheetHeader(
                AppSheetHeader(title: String(localized: "选择日期"), confirmTitle: String(localized: "完成")) {
                    showsDatePicker = false
                })
            .presentationDetents([.height(500), .large])
            .appSheet()
    }

    private func save() {
        // 按钮变灰要等下一次刷新界面，所以这里再检查一次，连点两下也只存一条
        guard !didSave else { return }
        guard let item = draft.output else {
            // 还差东西：在最近的那一项下面提示，光标跳过去，轻轻震一下
            withAnimation(.easeOut(duration: 0.15)) { saveAttempted = true }
            missingTick += 1
            if draft.nameError != nil {
                focusedField = .name
            } else if NumberText.isBlank(draft.caloriesText) {
                focusedField = .calories
            } else {
                // 其他数字填错了：收起键盘，填错的那一项下面会出现红色提示
                focusedField = nil
            }
            return
        }
        didSave = true
        onSave(item)
        dismiss()
    }
}

/// 名称下面的「最近使用」：最近吃过的食物，一排可以左右滑的小胶囊，点一下填好名字和上次的份量、营养
private struct RecentFoodSuggestions: View {
    let foods: [RecentFood]
    let onPick: (RecentFood) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xxs) {
            Text("最近使用")
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textTertiary)
            ScrollView(.horizontal) {
                HStack(spacing: AppSpacing.xs) {
                    ForEach(foods) { food in
                        Button {
                            onPick(food)
                        } label: {
                            Text(food.name)
                                .font(.subheadline)
                                .foregroundStyle(AppColors.textPrimary)
                                .lineLimit(1)
                                .padding(.horizontal, AppSpacing.sm)
                                .frame(minHeight: 34)
                                .background(AppColors.surfaceSecondary, in: Capsule())
                                .frame(minHeight: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(AppPressStyle())
                        .accessibilityHint(String(localized: "填入名称和上次的 \(food.values.caloriesKcal.noDecimal) 千卡"))
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
        .padding(.vertical, AppSpacing.xxs)
    }
}

/// 打开「手动添加」需要的两样东西：默认记到哪一餐，记到哪一天（20260929 这样的数字）
struct ManualEntryRequest: Identifiable {
    let id = UUID()
    let meal: MealType
    let dayKey: Int
}

/// 「手动添加」：填好后存成一条记录（「今日」页和拍照识别页共用）
struct ManualEntrySheet: View {
    let request: ManualEntryRequest

    @Environment(\.modelContext) private var modelContext
    @Environment(ToastCenter.self) private var toasts: ToastCenter?
    // 最近的几百条记录（从新到旧），挑出「最近使用」的食物
    @Query(FoodEntry.recentDescriptor) private var recentEntries: [FoodEntry]

    var body: some View {
        EntryEditView(
            draft: EntryDraft(meal: request.meal, dayKey: request.dayKey), title: String(localized: "手动添加"),
            showsMealPicker: true, showsDate: true, suggestions: RecentFoods.from(recentEntries.map(\.recentFood))
        ) { item in
            modelContext.insert(
                FoodEntry(
                    dayKey: item.dayKey, meal: item.meal, name: item.name, weightG: item.weightG, values: item.values,
                    source: .manual))
            try? modelContext.save()
            toasts?.success(DayMath.loggedMessage(meal: item.meal, dayKey: item.dayKey, today: .now))
        }
    }
}

#Preview("手动添加") {
    EntryEditView(
        draft: EntryDraft(meal: .lunch, dayKey: DayMath.dayKey(for: .now)), title: "手动添加", showsMealPicker: true,
        showsDate: true
    ) { _ in }
}

#Preview("修改识别结果") {
    EntryEditView(
        draft: EntryDraft(
            item: EditableItem(SampleData.analyzeResult.items[0], meal: .lunch, dayKey: DayMath.dayKey(for: .now))),
        title: "修改食物"
    ) { _ in }
}

#Preview("修改已保存的记录") {
    EntryEditView(
        draft: EntryDraft(
            item: EditableItem(SampleData.analyzeResult.items[0], meal: .lunch, dayKey: DayMath.dayKey(for: .now))),
        title: "修改记录", showsMealPicker: true, showsDate: true, onSave: { _ in }, onDelete: {}
    )
}
