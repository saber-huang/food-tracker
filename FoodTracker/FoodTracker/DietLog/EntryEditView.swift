//
//  EntryEditView.swift
//  FoodTracker
//
//  填写或修改一项食物的表单。它只负责填写；点「保存」后把结果交给打开它的页面，由那个页面决定怎么存。
//  手动添加、修改识别结果里的一项、修改已保存的记录，都用这个表单。
//
//  默认只显示最常用的几项，十秒钟就能记完一条：
//  食物名称 →（记录到哪一餐、哪一天）→ 热量、份量 → 保存。
//  蛋白质、碳水、脂肪收在「更多营养信息」里，点开才显示；已经有数字（比如修改识别结果）时一打开就是展开的。
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
    let onSave: (EditableItem) -> Void
    let onDelete: (() -> Void)?  // 有值时多一个「删除这一项」按钮

    @Environment(\.dismiss) private var dismiss
    @State private var draft: EntryDraft
    @State private var didSave = false  // 防止快速连点两次「保存」存成两条
    @State private var showsNutrition: Bool  // 「更多营养信息」是不是展开的
    @State private var showsDatePicker = false
    @FocusState private var focusedField: Field?
    private enum Field { case name, weight, calories, protein, carbs, fat }

    init(
        draft: EntryDraft, title: String, showsMealPicker: Bool = false, showsDate: Bool = false, note: String? = nil,
        onSave: @escaping (EditableItem) -> Void, onDelete: (() -> Void)? = nil
    ) {
        _draft = State(initialValue: draft)
        _showsNutrition = State(initialValue: Self.startsWithNutritionShown(draft))
        self.title = title
        self.showsMealPicker = showsMealPicker
        self.showsDate = showsDate
        self.note = note
        self.onSave = onSave
        self.onDelete = onDelete
    }

    /// 打开时「更多营养信息」要不要展开：三种营养素有任何一个已经填了，就展开（不然看不到已有的数字）
    static func startsWithNutritionShown(_ draft: EntryDraft) -> Bool {
        ![draft.proteinText, draft.carbsText, draft.fatText].allSatisfy(NumberText.isBlank)
    }

    var body: some View {
        NavigationStack {
            Form {
                Group {
                    nameSection
                    if showsMealPicker || showsDate {
                        whenSection
                    }
                    caloriesSection
                    nutritionSection
                    if let onDelete {
                        Section {
                            // 先关掉表单再删：表单还开着的时候删掉它正在显示的记录，会出错
                            Button("删除这一项", role: .destructive) {
                                dismiss()
                                onDelete()
                            }
                            .foregroundStyle(AppColors.destructive)
                        }
                    }
                }
                .appCardRow()
            }
            .listSectionSpacing(AppSpacing.md)
            .appListBackground()
            // 任何一个数字框变了，交给草稿判断要不要按比例换算
            .onChange(of: draft.allTexts) { draft.textsChanged() }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                // 数字键盘没有「完成」键，在键盘上方加一个
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("完成") { focusedField = nil }
                }
            }
            // 保存按钮固定在最下面：键盘弹出时跟着升上来，填完马上能点
            .safeAreaInset(edge: .bottom) {
                saveButton
            }
            .sheet(isPresented: $showsDatePicker) {
                datePickerSheet
            }
        }
    }

    // MARK: - 表单的几块

    private var nameSection: some View {
        Section {
            TextField("名称", text: $draft.name, prompt: Text("例如：米饭"))
                .focused($focusedField, equals: .name)
                .submitLabel(.next)
                .onSubmit { focusedField = .calories }
                .accessibilityLabel("食物名称")
            if let error = draft.nameError, !draft.name.isEmpty, focusedField != .name {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(AppColors.destructive)
            }
        } header: {
            sectionHeader("食物名称")
        }
    }

    /// 记录到哪一餐、哪一天
    private var whenSection: some View {
        Section {
            if showsMealPicker {
                // 默认按现在的时间选好（或者是从某一餐的 + 打开的那一餐），可以直接改
                Picker("记到哪一餐", selection: $draft.meal) {
                    ForEach(MealType.allCases) { meal in
                        Text(meal.title).tag(meal)
                    }
                }
                .pickerStyle(.segmented)
            }
            if showsDate {
                Button {
                    focusedField = nil
                    showsDatePicker = true
                } label: {
                    HStack {
                        Text("日期")
                            .foregroundStyle(AppColors.textPrimary)
                        Spacer()
                        Text(DayMath.dayTitle(for: draft.displayDay, today: .now))
                            .foregroundStyle(AppColors.textSecondary)
                        AppChevron()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(AppPressStyle(scales: false))
            }
        } header: {
            sectionHeader("记录到")
        }
    }

    /// 热量（必填）和份量（选填）；旁边的 ⓘ 里是千焦换算和按比例换算的说明
    private var caloriesSection: some View {
        Section {
            NumberRow(
                title: String(localized: "热量"), unit: String(localized: "千卡"), text: $draft.caloriesText, keyboard: .decimalPad,
                error: draft.caloriesError, focus: $focusedField, field: .calories, prompt: String(localized: "必填"))
            NumberRow(
                title: String(localized: "份量"), unit: String(localized: "克"), text: $draft.weightText, keyboard: .decimalPad,
                error: draft.weightError, focus: $focusedField, field: .weight, prompt: String(localized: "选填"))
            if let note {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(AppColors.textSecondary)
            }
            // 可能填错了的提醒：不阻止保存，只在真的对不上时出现
            if let warning = draft.kcalMismatchWarning {
                warningRow(warning)
            }
            if let warning = draft.macrosExceedWeightWarning {
                warningRow(warning)
            }
        } header: {
            HStack {
                sectionHeader("热量和份量")
                Spacer()
                InfoButton(topic: .caloriesAndPortion)
                    .padding(.vertical, -AppSpacing.sm)  // 点击范围够大，但不把标题撑高
            }
        }
    }

    /// 更多营养信息：蛋白质、碳水、脂肪，点一下展开或收起
    private var nutritionSection: some View {
        Section {
            Button {
                withAnimation(.easeOut(duration: 0.15)) { showsNutrition.toggle() }
            } label: {
                HStack(spacing: AppSpacing.xs) {
                    Text(showsNutrition ? "收起营养信息" : "更多营养信息")
                        .foregroundStyle(AppColors.brand)
                    Spacer(minLength: AppSpacing.xs)
                    // 收起来的时候，如果已经填了，就在右边写一行摘要，免得以为没填
                    if !showsNutrition, let summary = macroSummary {
                        Text(summary)
                            .font(.caption)
                            .foregroundStyle(AppColors.textSecondary)
                            .lineLimit(1)
                    }
                    Image(systemName: "chevron.down")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(AppColors.textTertiary)
                        .rotationEffect(.degrees(showsNutrition ? 180 : 0))
                }
                .contentShape(Rectangle())
            }
            // 用列表自带的按钮行：整行都能点（高度和其他行一样），按下时整行变灰
            .accessibilityHint(showsNutrition ? "收起蛋白质、碳水、脂肪" : "填写蛋白质、碳水、脂肪")

            if showsNutrition {
                NumberRow(
                    title: String(localized: "蛋白质"), unit: String(localized: "克"), text: $draft.proteinText, keyboard: .decimalPad,
                    error: draft.proteinError, focus: $focusedField, field: .protein, prompt: String(localized: "选填"))
                NumberRow(
                    title: String(localized: "碳水"), unit: String(localized: "克"), text: $draft.carbsText, keyboard: .decimalPad,
                    error: draft.carbsError, focus: $focusedField, field: .carbs, prompt: String(localized: "选填"))
                NumberRow(
                    title: String(localized: "脂肪"), unit: String(localized: "克"), text: $draft.fatText, keyboard: .decimalPad,
                    error: draft.fatError, focus: $focusedField, field: .fat, prompt: String(localized: "选填"))
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

    private func sectionHeader(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(AppTypography.detail.weight(.medium))
            .foregroundStyle(AppColors.textSecondary)
            .textCase(nil)
    }

    private func warningRow(_ text: String) -> some View {
        Label(text, systemImage: "info.circle")
            .font(.caption)
            .foregroundStyle(AppColors.textSecondary)
    }

    /// 最下面的「保存」：填对了才能点
    private var saveButton: some View {
        let canSave = draft.output != nil && !didSave
        return Button(action: save) {
            Text("保存")
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

    /// 选日期：只能选到今天为止，不能记到未来。日期按中文显示（2026年9月29日）；
    /// 月历从周一开始：这要靠日历设置（只设地区的话还是从周日开始）
    private var datePickerSheet: some View {
        NavigationStack {
            DatePicker("日期", selection: $draft.displayDay, in: ...Date.now, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .environment(\.locale, DayMath.locale)
                .environment(\.calendar, DayMath.calendar)
                .tint(AppColors.brand)
                .padding(.horizontal, AppSpacing.md)
                .frame(maxHeight: .infinity, alignment: .top)
                .navigationTitle("选择日期")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("完成") { showsDatePicker = false }
                    }
                }
        }
        .presentationDetents([.height(500), .large])
    }

    private func save() {
        // 按钮变灰要等下一次刷新界面，所以这里再检查一次，连点两下也只存一条
        guard !didSave, let item = draft.output else { return }
        didSave = true
        onSave(item)
        dismiss()
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

    var body: some View {
        EntryEditView(
            draft: EntryDraft(meal: request.meal, dayKey: request.dayKey), title: String(localized: "手动添加"),
            showsMealPicker: true, showsDate: true
        ) { item in
            modelContext.insert(
                FoodEntry(
                    dayKey: item.dayKey, meal: item.meal, name: item.name, weightG: item.weightG, values: item.values,
                    source: .manual))
            try? modelContext.save()
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
