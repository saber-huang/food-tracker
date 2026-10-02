//
//  CustomFoodEditView.swift
//  FoodTracker
//
//  创建 / 编辑「我的食物」：名称、参考份量（「1 份 约 220 克」，重量可以不填）、1 份的热量（必填）和营养（选填）。
//  保存后以后搜这个名字会排在最前面。也用来修改 AI 估算的数字（打开时已经填好）。
//  用的是和其他表单一样的样子（AppForm）；从「选择食物」页推进来，所以用系统的返回按钮，保存按钮在底部
//  （正在打字时先收起，点键盘上的「完成」后出现）
//

import SwiftData
import SwiftUI

struct CustomFoodEditView: View {
    /// 新建时的初始值（搜索的名字、AI 估算的数字）
    let seed: CustomFoodSeed?
    /// 编辑已有的我的食物（新建时为 nil）
    let editing: CustomFood?
    /// 保存好了：把新的样子交回去（打开份量页）
    let onSaved: (CustomFoodSnapshot) -> Void
    var onDeleted: (() -> Void)?

    @Environment(\.modelContext) private var modelContext
    @State private var name: String
    @State private var servingName: String
    @State private var amountUnit: AmountUnit
    @State private var amountText: String
    @State private var kcalText: String
    @State private var proteinText: String
    @State private var carbsText: String
    @State private var fatText: String
    @State private var saveAttempted = false
    @State private var missingTick = 0  // 每次没保存成功加 1：轻轻震一下
    @State private var confirmingDelete = false
    @FocusState private var focusedField: Field?
    private enum Field { case name, servingName, amount, kcal, protein, carbs, fat }

    init(seed: CustomFoodSeed?, editing: CustomFood? = nil, onSaved: @escaping (CustomFoodSnapshot) -> Void, onDeleted: (() -> Void)? = nil) {
        self.seed = seed
        self.editing = editing
        self.onSaved = onSaved
        self.onDeleted = onDeleted
        let text: (Double?) -> String = { $0.map { NumberText.text(from: $0) } ?? "" }
        if let food = editing {
            _name = State(initialValue: food.name)
            _servingName = State(initialValue: food.servingName)
            _amountUnit = State(initialValue: food.amountUnit)
            _amountText = State(initialValue: text(food.servingAmount))
            _kcalText = State(initialValue: text(food.servingKcal))
            _proteinText = State(initialValue: food.servingProteinG > 0 ? text(food.servingProteinG) : "")
            _carbsText = State(initialValue: food.servingCarbsG > 0 ? text(food.servingCarbsG) : "")
            _fatText = State(initialValue: food.servingFatG > 0 ? text(food.servingFatG) : "")
        } else {
            let values = seed?.servingValues
            _name = State(initialValue: seed?.name ?? "")
            _servingName = State(initialValue: seed?.servingName ?? "")
            _amountUnit = State(initialValue: seed?.amountUnit ?? .gram)
            _amountText = State(initialValue: text(seed?.servingAmount))
            _kcalText = State(initialValue: text(values?.caloriesKcal))
            _proteinText = State(initialValue: text(values?.proteinG))
            _carbsText = State(initialValue: text(values?.carbsG))
            _fatText = State(initialValue: text(values?.fatG))
        }
    }

    // MARK: - 检查

    private var nameError: String? { EntryValidator.nameError(name) }
    private var amountError: String? { EntryValidator.weightError(text: amountText) }
    private var kcalError: String? { EntryValidator.caloriesError(text: kcalText) }
    private var proteinError: String? { EntryValidator.macroError(text: proteinText, name: String(localized: "蛋白质")) }
    private var carbsError: String? { EntryValidator.macroError(text: carbsText, name: String(localized: "碳水")) }
    private var fatError: String? { EntryValidator.macroError(text: fatText, name: String(localized: "脂肪")) }

    private var isComplete: Bool {
        [nameError, amountError, kcalError, proteinError, carbsError, fatError].allSatisfy { $0 == nil }
    }

    private var unitPlaceholder: String { String(localized: "份") }
    /// 份量单位的名字（没填就是「份」）：「1 碗大约」「1 碗的热量和营养」
    private var unitName: String {
        let trimmed = servingName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? unitPlaceholder : trimmed
    }

    // MARK: - 页面

    var body: some View {
        AppForm {
            AppFormSection(String(localized: "名称")) {
                TextField("名称", text: $name, prompt: Text("例如：妈妈做的红烧肉").foregroundStyle(AppColors.textTertiary))
                    .foregroundStyle(AppColors.textPrimary)
                    .focused($focusedField, equals: .name)
                    .submitLabel(.next)
                    .onSubmit { focusedField = .kcal }
                    .padding(.horizontal, AppSpacing.cardPadding)
                    .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture { focusedField = .name }
                if saveAttempted, let nameError { hint(nameError) }
            }

            AppFormSection(
                String(localized: "参考份量"), footer: String(localized: "比如「1 份 约 220 克」。不知道重量可以不填，之后按份数记。")
            ) {
                AppFormRow {
                    Text("份量单位")
                        .foregroundStyle(AppColors.textPrimary)
                    Spacer(minLength: AppSpacing.xs)
                    TextField("份量单位", text: $servingName, prompt: Text(unitPlaceholder).foregroundStyle(AppColors.textTertiary))
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(AppColors.textPrimary)
                        .focused($focusedField, equals: .servingName)
                        .frame(maxWidth: 140)
                }
                AppFormDivider()
                NumberRow(
                    title: String(localized: "1 \(unitName)大约"), unit: amountUnit.symbol, text: $amountText, keyboard: .decimalPad,
                    error: amountError, focus: $focusedField, field: .amount, prompt: String(localized: "选填"))
                AppFormDivider()
                AppSegmentedControl(
                    title: String(localized: "按重量还是容量"), selection: $amountUnit, options: [.gram, .milliliter]
                ) { $0.symbol }
                .padding(AppSpacing.sm)
            }

            AppFormSection(String(localized: "1 \(unitName)的热量和营养")) {
                NumberRow(
                    title: String(localized: "热量"), unit: String(localized: "千卡"), text: $kcalText, keyboard: .numberPad,
                    error: kcalError, focus: $focusedField, field: .kcal, prompt: String(localized: "必填"))
                if saveAttempted, NumberText.isBlank(kcalText) { hint(String(localized: "请输入热量")) }
                AppFormDivider()
                NumberRow(
                    title: String(localized: "蛋白质"), unit: String(localized: "克"), text: $proteinText, keyboard: .decimalPad,
                    error: proteinError, focus: $focusedField, field: .protein, prompt: String(localized: "选填"))
                AppFormDivider()
                NumberRow(
                    title: String(localized: "碳水"), unit: String(localized: "克"), text: $carbsText, keyboard: .decimalPad,
                    error: carbsError, focus: $focusedField, field: .carbs, prompt: String(localized: "选填"))
                AppFormDivider()
                NumberRow(
                    title: String(localized: "脂肪"), unit: String(localized: "克"), text: $fatText, keyboard: .decimalPad,
                    error: fatError, focus: $focusedField, field: .fat, prompt: String(localized: "选填"))
            }

            if editing != nil {
                Button("从我的食物中删除", role: .destructive) { confirmingDelete = true }
                    .buttonStyle(.appDestructive)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            // 键盘弹出来时先收起：iOS 26 起键盘上方的「完成」浮在按钮上，会挡住按钮的下半截（点了没反应）
            if focusedField == nil {
                Button(String(localized: "保存"), action: save)
                    .buttonStyle(AppButtonStyle(kind: .primary, dimmed: !isComplete))
                    .padding(.horizontal, AppSpacing.pageMargin)
                    .padding(.vertical, AppSpacing.xs)
                    .appBottomBar()
            }
        }
        .toolbar(.visible, for: .navigationBar)
        .navigationTitle(editing == nil ? String(localized: "创建我的食物") : String(localized: "编辑我的食物"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("完成") { focusedField = nil }
            }
        }
        .task {
            // 新建、还没有名字时，光标直接放进名称
            guard editing == nil, name.isEmpty else { return }
            try? await Task.sleep(for: .milliseconds(450))
            if focusedField == nil { focusedField = .name }
        }
        .alert(String(localized: "删除「\(name)」？"), isPresented: $confirmingDelete) {
            Button("删除", role: .destructive, action: delete)
            Button("取消", role: .cancel) {}
        } message: {
            Text("只从「我的食物」里删除，已经记过的饮食记录不受影响。")
        }
        .sensoryFeedback(.warning, trigger: missingTick)
    }

    private func hint(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(AppColors.destructive)
            .padding(.horizontal, AppSpacing.cardPadding)
            .padding(.bottom, AppSpacing.sm)
    }

    // MARK: - 保存

    private func save() {
        guard isComplete else {
            saveAttempted = true
            missingTick += 1
            focusedField = nameError != nil ? .name : (NumberText.isBlank(kcalText) ? .kcal : nil)
            return
        }
        func number(_ text: String) -> Double { NumberText.number(from: text) ?? 0 }
        let values = DietLogMath.rounded(
            NutrientValues(
                caloriesKcal: number(kcalText), proteinG: number(proteinText), carbsG: number(carbsText), fatG: number(fatText)))
        let grams = NumberText.number(from: amountText).map(DietLogMath.round1).flatMap { $0 > 0 ? $0 : nil }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedUnit = servingName.trimmingCharacters(in: .whitespacesAndNewlines)

        let food: CustomFood
        if let editing {
            editing.name = trimmedName
            editing.servingName = trimmedUnit
            editing.amountUnitRaw = amountUnit.rawValue
            editing.servingAmount = grams
            editing.servingValues = values
            food = editing
        } else {
            food = CustomFood(
                name: trimmedName, amountUnit: amountUnit, servingName: trimmedUnit, servingAmount: grams, servingValues: values,
                source: seed?.isAIEstimate == true ? .ai : .user)
            modelContext.insert(food)
            ProductLog.log(.customFoodCreated, detail: seed?.isAIEstimate == true ? "ai_edited" : "user")
        }
        try? modelContext.save()
        focusedField = nil
        onSaved(food.snapshot)
    }

    private func delete() {
        guard let editing else { return }
        modelContext.delete(editing)
        try? modelContext.save()
        onDeleted?()
    }
}
