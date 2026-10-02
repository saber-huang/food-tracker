//
//  FoodSearchView.swift
//  FoodTracker
//
//  「选择食物」：首页的「手动」和每一餐的「+」打开这里。记一种食物只要三步：搜索 → 点一下 → 选份量、添加。
//  - 顶部：记到哪一餐（早餐 / 午餐 / 晚餐 / 加餐）和搜索框
//  - 还没打字：最近吃过、常吃（过去 30 天自动算出来）、我的食物；第一次用时是几种常见食物
//  - 打了字：食物库、我的食物、最近吃过一起搜（排序和去重见 FoodSearch.swift）
//  - 搜不到：「没有找到完全匹配的结果」+「AI 估算」（主要）+「选一道差不多的菜」（次要，不用 AI），永远有路可走。
//    菜品没有营养成分表，所以不让人手动填营养；包装食品可以「照营养成分表填写」；知道热量的可以「直接填写热量」
//  点进一种食物是份量页（FoodServingView），在同一个弹出页里往里推，返回就回到搜索结果
//

import SwiftData
import SwiftUI

/// 选择食物里能推进去的页面
enum FoodRoute: Hashable {
    case serving(FoodChoice)
    case aiEstimate(String)
    case similarDish(String)  // 选一道差不多的菜（用户搜的名字）
    case newCustomFood(CustomFoodSeed)  // 照包装填写
    case editCustomFood(UUID)
}

struct FoodSearchSheet: View {
    let request: ManualEntryRequest

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(ToastCenter.self) private var toasts: ToastCenter?
    // 最近的几百条记录（从新到旧）：挑出「最近吃过」「常吃」
    @Query(FoodEntry.recentDescriptor) private var recentEntries: [FoodEntry]
    @Query(CustomFood.recentFirst) private var customFoods: [CustomFood]

    @State private var meal: MealType
    @State private var query = ""
    @State private var path: [FoodRoute] = []
    @State private var manualForm: ManualFormRequest?
    @State private var closesAfterManualForm = false
    @State private var estimateRemaining: Int?
    @FocusState private var searchFocused: Bool

    private let catalog = FoodCatalog.shared

    /// 第一次用的人还没有记录时，先给几种常见食物
    private static let starterFoodIDs = [
        "rice", "egg", "milk", "banana", "apple", "chicken_breast", "mantou", "noodles", "tomato_egg", "yogurt",
    ]

    init(request: ManualEntryRequest) {
        self.request = request
        _meal = State(initialValue: request.meal)
    }

    // MARK: - 数据

    private var recentFoods: [RecentFood] { RecentFoods.from(recentEntries.map(\.recentFood)) }
    private var shownRecents: [RecentFood] { Array(recentFoods.prefix(8)) }
    private var shownFrequent: [RecentFood] {
        let recentIDs = Set(shownRecents.map(\.id))
        return RecentFoods.frequent(recentEntries.map(\.recentFood), now: .now).filter { !recentIDs.contains($0.id) }
    }
    private var customSnapshots: [CustomFoodSnapshot] { customFoods.map(\.snapshot) }
    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var results: [FoodSearchResult] {
        FoodSearch.results(query: trimmedQuery, catalog: catalog, custom: customSnapshots, recents: recentFoods)
    }

    // MARK: - 页面

    var body: some View {
        NavigationStack(path: $path) {
            searchPage
                .toolbar(.hidden, for: .navigationBar)
                .appSheetHeader(AppSheetHeader(title: String(localized: "选择食物"), onCancel: { dismiss() }))
                .navigationDestination(for: FoodRoute.self, destination: destination)
        }
        .appSheet()
        .sheet(item: $manualForm, onDismiss: { if closesAfterManualForm { dismiss() } }) { form in
            EntryEditView(
                draft: form.draft, title: String(localized: "手动填写"), showsMealPicker: true, showsDate: true,
                suggestions: recentFoods
            ) { item in
                log(item)
                closesAfterManualForm = true  // 表单自己会关上；关上后连同「选择食物」一起关
            }
        }
    }

    private var searchPage: some View {
        VStack(spacing: 0) {
            // 固定在顶部：记到哪一餐、搜索框
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                AppSegmentedControl(
                    title: String(localized: "记到哪一餐"), selection: $meal, options: MealType.allCases
                ) { $0.title }
                if let caption = DayMath.recordCaption(day: DayMath.date(fromDayKey: request.dayKey), today: .now) {
                    Text(caption)
                        .font(AppTypography.detail)
                        .foregroundStyle(AppColors.textSecondary)
                        .padding(.horizontal, AppSpacing.xxs)
                }
                searchField
            }
            .padding(.horizontal, AppSpacing.pageMargin)
            .padding(.top, AppSpacing.xs)
            .padding(.bottom, AppSpacing.sm)

            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.formSectionGap) {
                    if trimmedQuery.isEmpty {
                        browseContent
                    } else {
                        resultsContent
                    }
                }
                .padding(.horizontal, AppSpacing.pageMargin)
                .padding(.top, AppSpacing.xs)
                .padding(.bottom, AppSpacing.xxl)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background { AppBackground(glow: false) }
        .task {
            // 还没有记录过的人多半要打字；有最近吃过的，先让他们直接点（键盘不挡住列表）
            guard recentEntries.isEmpty, customFoods.isEmpty else { return }
            try? await Task.sleep(for: .milliseconds(450))
            searchFocused = true
        }
        .task(id: showsEstimateAction) {
            // 要显示「AI 估算」时，顺便看看今天还能估算几次
            guard showsEstimateAction, estimateRemaining == nil else { return }
            estimateRemaining = try? await APIClient.quota().estimateRemaining
        }
    }

    private var searchField: some View {
        HStack(spacing: AppSpacing.xs) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(AppColors.textSecondary)
                .accessibilityHidden(true)
            TextField("搜索食物", text: $query, prompt: Text("搜索食物").foregroundStyle(AppColors.textTertiary))
                .foregroundStyle(AppColors.textPrimary)
                .focused($searchFocused)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            if !query.isEmpty {
                Button {
                    query = ""
                    searchFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(AppColors.textTertiary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("清除")
            }
        }
        .padding(.leading, AppSpacing.md)
        .padding(.trailing, query.isEmpty ? AppSpacing.md : AppSpacing.xxs)
        .frame(minHeight: 48)
        .background(AppColors.surfacePrimary, in: RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture { searchFocused = true }
    }

    // MARK: - 还没打字

    @ViewBuilder
    private var browseContent: some View {
        if !shownRecents.isEmpty {
            foodList(title: String(localized: "最近吃过"), foods: shownRecents, event: .recentFoodSelected)
        }
        if !shownFrequent.isEmpty {
            foodList(title: String(localized: "常吃"), foods: shownFrequent, event: .frequentFoodSelected)
        }
        if !customSnapshots.isEmpty {
            AppFormSection(String(localized: "我的食物")) {
                ForEach(Array(customSnapshots.prefix(20).enumerated()), id: \.element.id) { index, food in
                    if index > 0 { AppFormDivider() }
                    let choice = FoodChoice.custom(food)
                    FoodChoiceRow(choice: choice, subtitle: FoodRowText.typical(choice), tags: estimateTags(food)) {
                        open(choice)
                    }
                }
            }
        }
        if shownRecents.isEmpty, customSnapshots.isEmpty {
            AppFormSection(String(localized: "常见食物")) {
                let foods = Self.starterFoodIDs.compactMap(catalog.food(id:))
                ForEach(Array(foods.enumerated()), id: \.element.id) { index, food in
                    if index > 0 { AppFormDivider() }
                    let choice = FoodChoice.catalog(food)
                    FoodChoiceRow(choice: choice, subtitle: FoodRowText.typical(choice)) { open(choice) }
                }
            }
        }
        otherWays
    }

    /// 最近吃过 / 常吃：显示上次吃的份量
    private func foodList(title: String, foods: [RecentFood], event: ProductLog.Event) -> some View {
        AppFormSection(title) {
            ForEach(Array(foods.enumerated()), id: \.element.id) { index, food in
                if index > 0 { AppFormDivider() }
                let choice = FoodSearch.choice(for: food, catalog: catalog, custom: customSnapshots)
                FoodChoiceRow(choice: choice, subtitle: FoodRowText.last(choice)) {
                    ProductLog.log(event)
                    open(choice)
                }
            }
        }
    }

    // MARK: - 打了字

    private var showsEstimateAction: Bool {
        !trimmedQuery.isEmpty && !FoodSearch.hasExactMatch(results)
    }

    @ViewBuilder
    private var resultsContent: some View {
        let results = results
        if results.isEmpty {
            noResult
        } else {
            AppFormSection(nil) {
                ForEach(Array(results.enumerated()), id: \.element.id) { index, result in
                    if index > 0 { AppFormDivider() }
                    FoodChoiceRow(
                        choice: result.choice,
                        subtitle: result.isRecent ? FoodRowText.last(result.choice) : FoodRowText.typical(result.choice),
                        tags: tags(for: result)
                    ) {
                        if result.isRecent { ProductLog.log(.recentFoodSelected) }
                        open(result.choice)
                    }
                }
            }
            if !FoodSearch.hasExactMatch(results) {
                notQuiteIt
            } else {
                otherWays
            }
        }
    }

    private func tags(for result: FoodSearchResult) -> [FoodRowTag] {
        var tags: [FoodRowTag] = []
        if case .custom(let id) = result.choice.origin {
            tags.append(.mine)
            if let food = customSnapshots.first(where: { $0.id == id }) { tags += estimateTags(food) }
        }
        // 我的食物不再加「最近吃过」：下面那行写的是上次的份量，已经看得出来；最多两个标签，不挤
        if result.isRecent, !result.choice.isMine { tags.append(.recent) }
        return tags
    }

    /// 我的食物是估算出来的：「AI 估算」或「估算」（差不多的菜）
    private func estimateTags(_ food: CustomFoodSnapshot) -> [FoodRowTag] {
        switch food.source {
        case .ai: [.aiEstimate]
        case .similar: [.estimate]
        case .user: []
        }
    }

    /// 一个都没搜到：不是死路。菜：AI 估算（主要）或者选一道差不多的菜（不用 AI）；
    /// 包装食品照营养成分表填；知道热量的直接填
    private var noResult: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                Text("没有找到完全匹配的结果")
                    .font(AppTypography.sectionTitle)
                    .foregroundStyle(AppColors.textPrimary)
                Text("菜可以让 AI 按常见做法估算，也可以选一道差不多的菜。")
                    .font(AppTypography.detail)
                    .foregroundStyle(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, AppSpacing.xxs)
            estimateButton(kind: .primary)
            Button {
                openSimilarDish()
            } label: {
                Label("选一道差不多的菜", systemImage: "list.bullet")
            }
            .buttonStyle(.appSecondary)
            smallLinks(includeSimilar: false)
        }
    }

    /// 有结果，但没有名字完全一样的：结果下面再给 AI 估算和别的办法
    private var notQuiteIt: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text("没找到想要的？")
                .font(AppTypography.sectionTitle)
                .foregroundStyle(AppColors.textPrimary)
                .padding(.horizontal, AppSpacing.xxs)
            estimateButton(kind: .secondary)
            smallLinks(includeSimilar: true)
        }
    }

    /// 几个小入口（选一道差不多的菜 / 包装食品：照营养成分表填写 / 直接填写热量）：一个一行，左对齐
    private func smallLinks(includeSimilar: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if includeSimilar {
                Button("选一道差不多的菜", action: openSimilarDish)
            }
            Button("包装食品：照营养成分表填写") { path.append(.newCustomFood(CustomFoodSeed(name: trimmedQuery))) }
            Button("直接填写热量", action: openManualForm)
        }
        .buttonStyle(AppButtonStyle(kind: .tertiary, tint: AppColors.brand, fullWidth: false))
        .padding(.horizontal, AppSpacing.xxs)
    }

    /// 没有要搜的、或者已经找到了：页面最下面两个小入口
    private var otherWays: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: AppSpacing.md) { otherWayButtons }
            VStack(spacing: AppSpacing.xxs) { otherWayButtons }
        }
        .buttonStyle(AppButtonStyle(kind: .tertiary, tint: AppColors.brand, fullWidth: false))
        .frame(maxWidth: .infinity)
    }

    /// 「添加包装食品」「直接填写热量」两个小入口
    @ViewBuilder
    private var otherWayButtons: some View {
        Button("添加包装食品") { path.append(.newCustomFood(CustomFoodSeed(name: trimmedQuery))) }
        Button("直接填写热量", action: openManualForm)
    }

    /// 「✦ AI 估算「山西过油肉」」，下面一行今天还能估算几次
    private func estimateButton(kind: AppButtonStyle.Kind) -> some View {
        let usedUp = estimateRemaining == 0
        return VStack(spacing: AppSpacing.xxs) {
            Button {
                ProductLog.log(.foodSearchNoResult, detail: "\(trimmedQuery.count) chars")
                path.append(.aiEstimate(trimmedQuery))
            } label: {
                Label(String(localized: "AI 估算「\(trimmedQuery)」"), systemImage: "sparkles")
            }
            .buttonStyle(AppButtonStyle(kind: kind))
            .disabled(usedUp)
            if let remaining = estimateRemaining {
                Text(remaining > 0 ? String(localized: "今天还可以 AI 估算 \(remaining) 次") : String(localized: "今天的 AI 估算次数用完了，可以先选一道差不多的菜"))
                    .font(.caption)
                    .foregroundStyle(AppColors.textTertiary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - 推进去的页面

    @ViewBuilder
    private func destination(_ route: FoodRoute) -> some View {
        switch route {
        case .serving(let choice):
            FoodServingView(
                choice: choice, meal: meal, dayKey: request.dayKey,
                onFillFromLabel: { name in path.append(.newCustomFood(CustomFoodSeed(name: name))) },
                onEditCustom: { id in path.append(.editCustomFood(id)) },
                onRenamedCustom: { snapshot in path = [.serving(.custom(snapshot))] },
                onDeletedCustom: { if !path.isEmpty { path.removeLast() } },
                onAdd: log)
        case .aiEstimate(let query):
            AIEstimateView(
                query: query, meal: meal, dayKey: request.dayKey, onAdd: log,
                onPickSimilar: { name in path.append(.similarDish(name)) },
                onFillFromLabel: { name in path.append(.newCustomFood(CustomFoodSeed(name: name))) })
        case .similarDish(let query):
            SimilarDishView(query: query) { food in
                path.append(.serving(.similar(name: query, basedOn: food)))
            }
        case .newCustomFood(let seed):
            CustomFoodEditView(seed: seed) { snapshot in
                // 建好了：直接去选份量（返回就回到搜索页，不再回到 AI 估算或编辑页）
                path = [.serving(.custom(snapshot))]
            }
        case .editCustomFood(let id):
            if let food = customFoods.first(where: { $0.id == id }) {
                CustomFoodEditView(
                    seed: nil, editing: food,
                    onSaved: { snapshot in path = [.serving(.custom(snapshot))] },
                    onDeleted: { path = [] })
            }
        }
    }

    // MARK: - 动作

    private func open(_ choice: FoodChoice) {
        searchFocused = false
        path.append(.serving(choice))
    }

    private func openSimilarDish() {
        searchFocused = false
        path.append(.similarDish(trimmedQuery))
    }

    private func openManualForm() {
        searchFocused = false
        let draft = EntryDraft(meal: meal, dayKey: request.dayKey)
        draft.name = trimmedQuery
        manualForm = ManualFormRequest(draft: draft)
    }

    /// 存一条记录、显示轻提示、关上（从「直接填写」来的由表单关上后再关）
    private func log(_ item: EditableItem) {
        modelContext.insert(
            FoodEntry(
                dayKey: item.dayKey, meal: item.meal, name: item.name, weightG: item.weightG, values: item.values,
                source: .manual, amountUnit: item.amountUnit, serving: item.serving, foodRef: item.foodRef,
                oilLevel: item.oilLevel))
        try? modelContext.save()
        toasts?.success(DayMath.loggedMessage(meal: item.meal, dayKey: item.dayKey, today: .now))
        if manualForm == nil { dismiss() }
    }
}

/// 「直接填写热量」：打开手动填写表单
struct ManualFormRequest: Identifiable {
    let id = UUID()
    let draft: EntryDraft
}

// MARK: - 一行食物

/// 一行食物右边的小标签
enum FoodRowTag: Hashable {
    case mine, recent, aiEstimate, estimate

    var text: String {
        switch self {
        case .mine: String(localized: "我的食物")
        case .recent: String(localized: "最近吃过")
        case .aiEstimate: String(localized: "AI 估算")
        case .estimate: String(localized: "估算")
        }
    }
}

/// 列表里的一种食物：名字、一行份量和热量、小标签，点了进份量页
struct FoodChoiceRow: View {
    let choice: FoodChoice
    let subtitle: String
    var tags: [FoodRowTag] = []
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: AppSpacing.sm) {
                VStack(alignment: .leading, spacing: 3) {
                    // 名字和标签放得下就排一行，名字长（或字号很大）时标签换到名字下面
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: AppSpacing.xs) {
                            nameText
                            tagViews
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            nameText
                            HStack(spacing: AppSpacing.xs) { tagViews }
                        }
                    }
                    Text(subtitle)
                        .font(AppTypography.numberSmall)
                        .foregroundStyle(AppColors.textSecondary)
                        .lineLimit(2)
                }
                Spacer(minLength: AppSpacing.xs)
                AppChevron()
            }
            .padding(.horizontal, AppSpacing.cardPadding)
            .padding(.vertical, AppSpacing.sm)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(AppPressStyle(scales: false))
        .accessibilityElement(children: .combine)
        .accessibilityHint("选择份量")
    }

    private var nameText: some View {
        Text(choice.name)
            .font(AppTypography.itemName)
            .foregroundStyle(AppColors.textPrimary)
            .lineLimit(2)
    }

    private var tagViews: some View {
        ForEach(tags, id: \.self) { tag in
            FoodTag(text: tag.text, emphasized: tag == .mine)
        }
    }
}

/// 一行食物下面的那行小字
nonisolated enum FoodRowText {
    /// 搜索结果、常见食物：「116 千卡 / 100 克 · 1 碗 约 150 克」；不知道重量的「1 份 · 348 千卡」
    static func typical(_ choice: FoodChoice) -> String {
        switch choice.basis {
        case .per100(let per100, let unit):
            let density = PortionText.per100(per100.caloriesKcal, unit: unit, isEstimate: choice.isEstimate)
            guard let first = choice.units.first, first.amount > 0 else { return density }
            return "\(density) · \(PortionText.commonServing(first, quantity: 1, amountUnit: unit))"
        case .perServing:
            return last(choice)
        }
    }

    /// 最近吃过：上次的份量和热量（上次选了「多油」就按多油），「1 碗 · 174 千卡」「150 克 · 174 千卡」
    static func last(_ choice: FoodChoice) -> String {
        let values = ServingMath.displayed(
            ServingMath.oilAdjusted(ServingMath.values(of: choice.initialSelection, in: choice), choice.initialOil),
            isEstimate: choice.isEstimate)
        let kcal = PortionText.kcal(values.caloriesKcal, isEstimate: choice.isEstimate)
        switch choice.initialSelection {
        case .natural(let id, let quantity):
            guard let unit = choice.unit(id: id) else { return kcal }
            return "\(PortionText.serving(quantity, unit: unit)) · \(kcal)"
        case .amount(let grams):
            guard let grams, let unit = choice.basis.amountUnit else { return kcal }
            return "\(PortionText.amount(grams, unit: unit, approximate: false)) · \(kcal)"
        }
    }
}
