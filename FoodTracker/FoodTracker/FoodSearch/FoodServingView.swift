//
//  FoodServingView.swift
//  FoodTracker
//
//  份量页：搜索结果、最近吃过、我的食物、AI 估算点进来都到这里。
//  看这一份有多少热量 → 选份量（1 碗 / 半碗 / 克）→ 底部「添加到午餐」。不用再填一张表。
//  - 自然份量都写「约」（「1 碗 · 约 150 克」）；有秤的人切到「克」直接填（137 克）
//  - 估算的食物（AI 估算、按做法估算的家常菜）热量取整到 10、写「约」，不假装精确
//  - AI 估算：可以顺手保存到「我的食物」（默认打开），下次搜同样的名字直接出现；数字不对可以先改再保存
//  - 我的食物：可以编辑、删除（删掉不影响已经记过的饮食记录）
//

import SwiftData
import SwiftUI

/// AI 估算的数字，交给「我的食物」编辑页时带上的初始值
struct CustomFoodSeed: Hashable {
    var name: String
    var amountUnit: AmountUnit = .gram
    var servingName: String = ""
    var servingAmount: Double?
    var servingValues: NutrientValues?
    var isAIEstimate = false
}

struct FoodServingView: View {
    let choice: FoodChoice
    let meal: MealType
    let dayKey: Int
    /// AI 估算：「修改营养数据」→ 打开「我的食物」编辑页，填好 AI 的数字
    var onEditEstimate: ((CustomFoodSeed) -> Void)?
    /// 我的食物：编辑
    var onEditCustom: ((UUID) -> Void)?
    /// 我的食物删掉了：回到搜索页
    var onDeletedCustom: (() -> Void)?
    /// 点了「添加到午餐」：交给打开它的页面存进去
    let onAdd: (EditableItem) -> Void

    @Environment(\.modelContext) private var modelContext
    @State private var selection: ServingSelection
    @State private var amountText: String
    @State private var saveToMyFoods = true
    @State private var confirmingDelete = false
    @State private var didAdd = false
    @FocusState private var focusedField: Field?
    private enum Field { case amount }

    init(
        choice: FoodChoice, meal: MealType, dayKey: Int, onEditEstimate: ((CustomFoodSeed) -> Void)? = nil,
        onEditCustom: ((UUID) -> Void)? = nil, onDeletedCustom: (() -> Void)? = nil, onAdd: @escaping (EditableItem) -> Void
    ) {
        self.choice = choice
        self.meal = meal
        self.dayKey = dayKey
        self.onEditEstimate = onEditEstimate
        self.onEditCustom = onEditCustom
        self.onDeletedCustom = onDeletedCustom
        self.onAdd = onAdd
        _selection = State(initialValue: choice.initialSelection)
        let amount = ServingMath.amount(of: choice.initialSelection, in: choice)
        _amountText = State(initialValue: amount.map { NumberText.text(from: DietLogMath.round1($0)) } ?? "")
    }

    // MARK: - 现在选的份量和营养

    /// 计算用的份量：直接填克数时，用输入框里的数字
    private var effectiveSelection: ServingSelection {
        if case .amount = selection { return .amount(NumberText.number(from: amountText)) }
        return selection
    }

    private var amount: Double? { ServingMath.amount(of: effectiveSelection, in: choice) }

    /// 显示和保存的数字（估算的已经取整）
    private var shownValues: NutrientValues {
        ServingMath.displayed(ServingMath.values(of: effectiveSelection, in: choice), isEstimate: choice.isEstimate)
    }

    private var amountError: String? {
        guard case .amount = selection else { return nil }
        return EntryValidator.weightError(text: amountText) ?? (amount == nil ? String(localized: "请输入份量") : nil)
    }

    private var canAdd: Bool {
        guard amountError == nil else { return false }
        if case .amount = selection { return (amount ?? 0) > 0 }
        return true
    }

    private var naturalUnitID: String? {
        if case .natural(let id, _) = selection { return id }
        return nil
    }

    private var naturalQuantity: Double {
        if case .natural(_, let quantity) = selection { return quantity }
        return 1
    }

    // MARK: - 页面

    var body: some View {
        AppForm {
            header
            kcalCard
            AppFormSection(String(localized: "份量"), footer: per100Footer) {
                ServingPicker(
                    units: choice.units, amountUnit: choice.basis.amountUnit, selectedUnitID: naturalUnitID,
                    quantity: naturalQuantity, onSelectUnit: selectUnit, onStep: step
                ) {
                    NumberRow(
                        title: String(localized: "份量"), unit: (choice.basis.amountUnit ?? .gram).symbol, text: $amountText,
                        keyboard: .decimalPad, error: amountError, focus: $focusedField, field: .amount,
                        prompt: String(localized: "请输入"))
                }
            }
            if choice.isAIEstimate {
                estimateSection
            }
            if case .custom(let id) = choice.origin {
                customSection(id)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            // 正在填克数（键盘弹出来）时先收起：iOS 26 起键盘上方的「完成」浮在按钮上，会挡住按钮的下半截。
            // 点「完成」收起键盘，按钮就回来了
            if focusedField == nil {
                Button(DayMath.addButtonTitle(meal: meal, dayKey: dayKey, today: .now), action: add)
                    .buttonStyle(AppButtonStyle(kind: .primary, dimmed: !canAdd))
                    .disabled(!canAdd || didAdd)
                    .padding(.horizontal, AppSpacing.pageMargin)
                    .padding(.vertical, AppSpacing.xs)
                    .appBottomBar()
            }
        }
        // 名字已经大大地写在页面上，顶栏只留返回按钮（和食谱详情一样）
        .toolbar(.visible, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("完成") { focusedField = nil }
            }
        }
        .alert(String(localized: "删除「\(choice.name)」？"), isPresented: $confirmingDelete) {
            Button("删除", role: .destructive, action: deleteCustomFood)
            Button("取消", role: .cancel) {}
        } message: {
            Text("只从「我的食物」里删除，已经记过的饮食记录不受影响。")
        }
    }

    /// 名字和小标签：AI 估算 ⓘ / 我的食物 / 按常见做法估算
    private var header: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xxs) {
            Text(choice.name)
                .font(.title2.weight(.semibold))
                .foregroundStyle(AppColors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if choice.isAIEstimate {
                AIEstimateBadge()
            } else if choice.isMine {
                FoodTag(text: String(localized: "我的食物"))
                    .padding(.top, AppSpacing.xxs)
            } else if choice.isEstimate {
                Text("按常见做法估算，仅供参考")
                    .font(AppTypography.detail)
                    .foregroundStyle(AppColors.textSecondary)
            }
        }
        .padding(.horizontal, AppSpacing.xxs)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 这一份的热量（大数字）和三大营养素
    private var kcalCard: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            HStack(alignment: .firstTextBaseline, spacing: AppSpacing.xxs) {
                if choice.isEstimate {
                    Text("约")
                        .font(AppTypography.heroCaption)
                        .foregroundStyle(AppColors.textSecondary)
                }
                Text(shownValues.caloriesKcal.noDecimal)
                    .font(.system(size: 40, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(AppColors.textPrimary)
                    .contentTransition(.numericText())
                Text("千卡")
                    .font(AppTypography.heroCaption)
                    .foregroundStyle(AppColors.textSecondary)
            }
            .accessibilityElement(children: .combine)
            .animation(.easeOut(duration: 0.15), value: shownValues.caloriesKcal)
            if macrosMissing {
                Text("没有填写蛋白质、碳水和脂肪")
                    .font(AppTypography.detail)
                    .foregroundStyle(AppColors.textSecondary)
            } else {
                MacroStatsRow(proteinG: shownValues.proteinG, carbsG: shownValues.carbsG, fatG: shownValues.fatG)
            }
        }
        .padding(AppSpacing.heroPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCard(.primary)
    }

    /// 自己建的食物只填了热量（营养素是选填的）：写「没有填写」，不显示三个「0 克」
    private var macrosMissing: Bool {
        guard choice.isMine else { return false }
        let values: NutrientValues
        switch choice.basis {
        case .per100(let per100, _): values = per100
        case .perServing(let perServing): values = perServing
        }
        return values.caloriesKcal > 0 && values.proteinG == 0 && values.carbsG == 0 && values.fatG == 0
    }

    /// 份量下面的一行灰字：每 100 克多少千卡
    private var per100Footer: String? {
        guard case .per100(let per100, let unit) = choice.basis else { return nil }
        return PortionText.per100(per100.caloriesKcal, unit: unit, isEstimate: choice.isEstimate)
    }

    /// AI 估算：保存到我的食物、修改数字
    private var estimateSection: some View {
        AppFormSection(nil, footer: String(localized: "保存后，下次搜索「\(choice.name)」会直接出现，不用再估算。")) {
            AppFormRow {
                Toggle(isOn: $saveToMyFoods) {
                    Text("同时保存到我的食物")
                        .foregroundStyle(AppColors.textPrimary)
                }
                .tint(AppColors.brand)
            }
            AppFormDivider()
            Button {
                onEditEstimate?(estimateSeed)
            } label: {
                AppFormLinkLabel(title: String(localized: "修改营养数据"))
            }
            .buttonStyle(AppPressStyle(scales: false))
        }
    }

    /// 我的食物：编辑、删除
    private func customSection(_ id: UUID) -> some View {
        AppFormSection(nil) {
            Button {
                onEditCustom?(id)
            } label: {
                AppFormLinkLabel(title: String(localized: "编辑这个食物"))
            }
            .buttonStyle(AppPressStyle(scales: false))
            AppFormDivider()
            Button {
                confirmingDelete = true
            } label: {
                Text("从我的食物中删除")
                    .foregroundStyle(AppColors.destructive)
                    .padding(.horizontal, AppSpacing.cardPadding)
                    .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(AppPressStyle(scales: false))
        }
    }

    // MARK: - 动作

    /// 选单位：nil = 切到直接填克数（把现在的量填进输入框接着改）
    private func selectUnit(_ unitID: String?) {
        focusedField = nil
        guard let unitID else {
            if let grams = amount { amountText = NumberText.text(from: DietLogMath.round1(grams)) }
            selection = .amount(amount)
            ProductLog.log(.gramInputSelected)
            return
        }
        guard let unit = choice.unit(id: unitID) else { return }
        // 从克切回自然单位：克数正好是整数份就保留，否则从 1 份开始
        let quantity = amount.flatMap { ServingMath.quantity(forAmount: $0, unit: unit) } ?? 1
        selection = .natural(unitID: unitID, quantity: quantity)
        ProductLog.log(.servingUnitSelected, detail: unit.id)
    }

    private func step(_ direction: Int) {
        guard case .natural(let id, let quantity) = selection, let unit = choice.unit(id: id) else { return }
        selection = .natural(unitID: id, quantity: ServingMath.stepped(quantity, by: direction, step: unit.step))
    }

    /// AI 估算的这一份，交给编辑页的初始值
    private var estimateSeed: CustomFoodSeed {
        let unit = choice.units.first
        var values: NutrientValues?
        if case .per100(let per100, _) = choice.basis, let unit {
            values = ServingMath.displayed(DietLogMath.scaled(per100, toWeightG: unit.amount), isEstimate: true)
        }
        return CustomFoodSeed(
            name: choice.name, amountUnit: choice.basis.amountUnit ?? .gram, servingName: unit?.name ?? "",
            servingAmount: unit?.amount, servingValues: values, isAIEstimate: true)
    }

    private func add() {
        guard canAdd, !didAdd else { return }
        focusedField = nil
        var foodRef = choice.foodRef
        if choice.isAIEstimate, saveToMyFoods {
            foodRef = saveEstimateToMyFoods()
        }
        if case .custom(let id) = choice.origin {
            markCustomFoodUsed(id)
        }
        var serving: ServingChoice?
        if case .natural(let id, let quantity) = selection, let unit = choice.unit(id: id) {
            serving = ServingChoice(unitID: unit.id, unitName: unit.displayName(quantity: quantity), quantity: quantity)
        }
        let item = EditableItem(
            id: UUID(), name: choice.name, weightG: amount.map(DietLogMath.round1), values: shownValues, confidence: nil,
            meal: meal, dayKey: dayKey, amountUnit: choice.basis.amountUnit ?? .gram, serving: serving, foodRef: foodRef)
        didAdd = true
        ProductLog.log(.foodLogged, detail: originTag, name: choice.name)
        onAdd(item)
    }

    /// 把 AI 估算的结果存成「我的食物」，返回它的来源标记
    private func saveEstimateToMyFoods() -> String? {
        let seed = estimateSeed
        guard let values = seed.servingValues else { return nil }
        let food = CustomFood(
            name: seed.name, amountUnit: seed.amountUnit, servingName: seed.servingName, servingAmount: seed.servingAmount,
            servingValues: values, source: .ai)
        food.lastUsedAt = .now
        modelContext.insert(food)
        ProductLog.log(.customFoodCreated, detail: "ai")
        return FoodRef.custom(food.id)
    }

    private func markCustomFoodUsed(_ id: UUID) {
        let descriptor = FetchDescriptor<CustomFood>(predicate: #Predicate { $0.id == id })
        if let food = try? modelContext.fetch(descriptor).first { food.lastUsedAt = .now }
    }

    private func deleteCustomFood() {
        guard case .custom(let id) = choice.origin else { return }
        let descriptor = FetchDescriptor<CustomFood>(predicate: #Predicate { $0.id == id })
        if let food = try? modelContext.fetch(descriptor).first {
            modelContext.delete(food)
            try? modelContext.save()
        }
        onDeletedCustom?()
    }

    private var originTag: String {
        switch choice.origin {
        case .catalog: "catalog"
        case .custom: "custom"
        case .recent: "recent"
        case .aiEstimate: "ai"
        }
    }
}

/// 小标签：「我的食物」「最近吃过」「AI 估算」
struct FoodTag: View {
    let text: String
    var emphasized = true

    var body: some View {
        Text(text)
            .font(AppTypography.caption.weight(.medium))
            .foregroundStyle(emphasized ? AppColors.brandDeep : AppColors.textSecondary)
            .padding(.horizontal, AppSpacing.xs)
            .padding(.vertical, 2)
            .background(emphasized ? AppColors.brandSoft : AppColors.surfaceSecondary, in: Capsule())
    }
}
