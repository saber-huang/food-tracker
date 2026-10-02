//
//  CustomFoodEditView.swift
//  FoodTracker
//
//  照包装填写「我的食物」：只给有营养成分表的包装食品（饮料、零食、速冻食品……）用。
//  菜品没有营养成分表，谁也说不准有几克脂肪，所以菜走 AI 估算或「选一道差不多的菜」，不在这里填。
//  表单照营养成分表的样子排：
//  - 表上写的是：每 100 克 / 每 100 毫升 / 每份（每份多少克可以不填）
//  - 能量照抄，单位可以选千焦（中国的包装大多写千焦，App 换算成千卡）或千卡
//  - 蛋白质、脂肪、碳水化合物（顺序和中国的营养成分表一样，都可以不填）
//  - 一包有多少（选填）：单位从「包、瓶、盒……」里选，不让随便打字（第一版能打字，打了「1」标题就成了「11大约」）
//  换算和检查都在 NutritionLabel.swift；保存后打开份量页
//

import SwiftData
import SwiftUI

struct CustomFoodEditView: View {
    /// 新建时的初始值（搜索的名字）
    let seed: CustomFoodSeed?
    /// 修改已有的我的食物（新建时为 nil）
    let editing: CustomFood?
    /// 保存好了：把新的样子交回去（打开份量页）
    let onSaved: (CustomFoodSnapshot) -> Void
    var onDeleted: (() -> Void)?

    @Environment(\.modelContext) private var modelContext
    @State private var name: String
    @State private var column: LabelColumn
    @State private var servingUnit: AmountUnit
    @State private var servingSizeText: String
    @State private var energyUnit: EnergyUnit
    @State private var energyText: String
    @State private var proteinText: String
    @State private var fatText: String
    @State private var carbsText: String
    @State private var packageID: String
    @State private var packageAmountText: String
    @State private var saveAttempted = false
    @State private var missingTick = 0  // 每次没保存成功加 1：轻轻震一下
    @State private var confirmingDelete = false
    @FocusState private var focusedField: Field?
    private enum Field { case name, servingSize, energy, protein, fat, carbs, packageAmount }

    init(seed: CustomFoodSeed?, editing: CustomFood? = nil, onSaved: @escaping (CustomFoodSnapshot) -> Void, onDeleted: (() -> Void)? = nil) {
        self.seed = seed
        self.editing = editing
        self.onSaved = onSaved
        self.onDeleted = onDeleted
        let input = editing.map { NutritionLabelInput(food: $0.snapshot) } ?? NutritionLabelInput(name: seed?.name ?? "")
        let text: (Double?) -> String = { $0.map { NumberText.text(from: DietLogMath.round1($0)) } ?? "" }
        _name = State(initialValue: input.name)
        _column = State(initialValue: input.column)
        _servingUnit = State(initialValue: input.servingUnit)
        _servingSizeText = State(initialValue: text(input.servingSize))
        _energyUnit = State(initialValue: input.energyUnit)
        _energyText = State(initialValue: text(input.energy))
        _proteinText = State(initialValue: text(input.protein))
        _fatText = State(initialValue: text(input.fat))
        _carbsText = State(initialValue: text(input.carbs))
        _packageID = State(initialValue: input.packageID)
        _packageAmountText = State(initialValue: text(input.packageAmount))
    }

    // MARK: - 表单里填的内容

    private var input: NutritionLabelInput {
        NutritionLabelInput(
            name: name, column: column, servingUnit: servingUnit, servingSize: NumberText.number(from: servingSizeText),
            energy: NumberText.number(from: energyText), energyUnit: energyUnit, protein: NumberText.number(from: proteinText),
            fat: NumberText.number(from: fatText), carbs: NumberText.number(from: carbsText), packageID: packageID,
            packageAmount: NumberText.number(from: packageAmountText))
    }

    /// 营养素：没填可以；填了要是 0～1000 克的数
    private func numberError(_ text: String, name: String) -> String? {
        EntryValidator.macroError(text: text, name: name)
    }

    /// 每份、净含量：没填可以；填了要是 0～5000 的数（克或毫升）
    private func amountError(_ text: String) -> String? {
        if NumberText.isBlank(text) { return nil }
        guard let value = NumberText.number(from: text) else { return String(localized: "请输入数字") }
        return value > 0 && value <= 5000 ? nil : String(localized: "需要在 0～5000 之间")
    }

    /// 能量那一行的提示：没填先不说（保存时再提示）；填了先看是不是数，再看合不合理
    private var energyRowError: String? {
        if NumberText.isBlank(energyText) { return nil }
        guard NumberText.number(from: energyText) != nil else { return String(localized: "请输入数字") }
        return input.energyError
    }

    private var isComplete: Bool {
        input.isComplete
            && [proteinText, fatText, carbsText].allSatisfy { numberError($0, name: "") == nil }
            && amountError(servingSizeText) == nil && amountError(packageAmountText) == nil
    }

    // MARK: - 页面

    var body: some View {
        AppForm {
            AppFormSection(String(localized: "名称")) {
                TextField("名称", text: $name, prompt: Text("例如：某某牌燕麦奶").foregroundStyle(AppColors.textTertiary))
                    .foregroundStyle(AppColors.textPrimary)
                    .focused($focusedField, equals: .name)
                    .submitLabel(.next)
                    .onSubmit { focusedField = .energy }
                    .padding(.horizontal, AppSpacing.cardPadding)
                    .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture { focusedField = .name }
                if saveAttempted, let error = input.nameError { hint(error) }
            }

            labelSection
            packageSection

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
        .navigationTitle(editing == nil ? String(localized: "添加包装食品") : String(localized: "修改营养成分表"))
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

    /// 营养成分表：按什么写、能量、三种营养素
    private var labelSection: some View {
        AppFormSection(
            String(localized: "营养成分表"),
            footer: String(localized: "照着包装背面的表抄。中国的包装能量一般写千焦（kJ），直接照抄，App 会换算成千卡。")
        ) {
            AppSegmentedControl(title: String(localized: "表上写的是"), selection: $column, options: LabelColumn.allCases) {
                $0.title
            }
            .padding(AppSpacing.sm)
            if column == .perServing {
                AppFormDivider()
                NumberRow(
                    title: String(localized: "每份"), unit: servingUnit.symbol, text: $servingSizeText, keyboard: .decimalPad,
                    error: amountError(servingSizeText), focus: $focusedField,
                    field: .servingSize, prompt: String(localized: "选填"))
                AppSegmentedControl(title: String(localized: "每份按"), selection: $servingUnit, options: [.gram, .milliliter]) {
                    $0.symbol
                }
                .padding(.horizontal, AppSpacing.sm)
                .padding(.bottom, AppSpacing.sm)
            }
            AppFormDivider()
            AppSegmentedControl(title: String(localized: "能量的单位"), selection: $energyUnit, options: EnergyUnit.allCases) {
                $0.symbol
            }
            .padding(AppSpacing.sm)
            AppFormDivider()
            NumberRow(
                title: String(localized: "能量"), unit: energyUnit.symbol, text: $energyText, keyboard: .decimalPad,
                error: energyRowError, focus: $focusedField, field: .energy, prompt: String(localized: "必填"))
            if energyUnit == .kilojoule, let kcal = input.kcal, input.energyError == nil {
                Text("约 \(kcal.noDecimal) 千卡")
                    .font(AppTypography.detail)
                    .foregroundStyle(AppColors.textSecondary)
                    .padding(.horizontal, AppSpacing.cardPadding)
                    .padding(.bottom, AppSpacing.sm)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            if saveAttempted, input.energy == nil { hint(String(localized: "请输入能量")) }
            AppFormDivider()
            macroRow(String(localized: "蛋白质"), text: $proteinText, field: .protein)
            AppFormDivider()
            macroRow(String(localized: "脂肪"), text: $fatText, field: .fat)
            AppFormDivider()
            macroRow(String(localized: "碳水化合物"), text: $carbsText, field: .carbs)
            if let error = input.macrosError { hint(error) }
        }
    }

    private func macroRow(_ title: String, text: Binding<String>, field: Field) -> some View {
        NumberRow(
            title: title, unit: String(localized: "克"), text: text, keyboard: .decimalPad,
            error: numberError(text.wrappedValue, name: title), focus: $focusedField, field: field,
            prompt: String(localized: "选填"))
    }

    /// 一包有多少：单位从几个常见的里选
    private var packageSection: some View {
        AppFormSection(
            String(localized: "一包有多少"),
            footer: input.canUsePackage
                ? String(localized: "选填。填了以后，记录时可以直接选「1 包」「半包」。")
                : String(localized: "先填上面「每份」是多少克（毫升），才能按一包记录。")
        ) {
            AppFormRow {
                Text("单位")
                    .foregroundStyle(AppColors.textPrimary)
                Spacer(minLength: AppSpacing.xs)
                Menu {
                    Picker("单位", selection: $packageID) {
                        ForEach(PackageUnit.all) { unit in
                            Text(unit.displayName).tag(unit.id)
                        }
                    }
                } label: {
                    HStack(spacing: AppSpacing.xxs) {
                        Text(PackageUnit.named(packageID)?.displayName ?? "")
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.footnote.weight(.semibold))
                    }
                    .foregroundStyle(AppColors.brand)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .accessibilityLabel(String(localized: "一包的单位"))
            }
            AppFormDivider()
            NumberRow(
                title: String(localized: "净含量"), unit: input.amountUnit.symbol, text: $packageAmountText,
                keyboard: .decimalPad, error: amountError(packageAmountText),
                focus: $focusedField, field: .packageAmount, prompt: String(localized: "选填"))
        }
        .disabled(!input.canUsePackage)
        .opacity(input.canUsePackage ? 1 : 0.5)
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
        guard isComplete, let fields = input.fields else {
            saveAttempted = true
            missingTick += 1
            focusedField = input.nameError != nil ? .name : (input.energy == nil ? .energy : nil)
            return
        }
        let food: CustomFood
        if let editing {
            editing.apply(fields)
            food = editing
        } else {
            food = CustomFood.fromLabel(fields)
            modelContext.insert(food)
            ProductLog.log(.customFoodCreated, detail: "label")
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
