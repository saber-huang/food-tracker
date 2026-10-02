//
//  FoodSearch.swift
//  FoodTracker
//
//  「选择食物」页的搜索：在食物库、我的食物、最近吃过里找，排好顺序、去掉重复。
//  排序（越靠前越先显示）：
//  1. 名字完全一样（同一档里：我的食物 > 最近吃过 > 食物库）
//  2. 我的食物
//  3. 最近吃过
//  4. 食物库（名字开头一样的在前，其次是包含）
//  5. 叫法不同、或者打错一两个字也能对上的（同义词换完以后部分重合）
//  最后由页面在下面放「AI 估算」和「创建自定义食物」：搜不到也不会没路走。
//  去重：最近吃过的如果就是食物库或我的食物里的某一种（记录里有来源标记，或者名字完全一样），只显示一行，
//  打开时按上次吃的份量
//

import Foundation

/// 名字对上的程度
nonisolated enum FoodMatch: Int, Comparable, Sendable {
    case similar = 1  // 部分字重合（打错字、叫法不同）
    case inside = 2  // 打的字比名字长，名字在里面（「清炒西兰花」里有「西兰花」）
    case contains = 3  // 名字里包含打的字
    case prefix = 4  // 名字开头就是打的字
    case exact = 5  // 完全一样

    static func < (a: FoodMatch, b: FoodMatch) -> Bool { a.rawValue < b.rawValue }

    /// 「部分字重合」最少要有多像（0～1）
    static let similarThreshold = 0.6

    /// 已经规范化过的两个名字对得上吗、对上到什么程度
    static func of(query: String, key: String) -> FoodMatch? {
        guard !query.isEmpty, !key.isEmpty else { return nil }
        if key == query { return .exact }
        if key.hasPrefix(query) { return .prefix }
        if key.contains(query) { return .contains }
        // 名字至少两个字才算「在里面」：不然搜「鸭蛋」会因为「蛋」对上鸡蛋
        if key.count >= 2, query.contains(key) { return .inside }
        // 部分相同：打的至少 3 个字、六成片段一样才算。0.5 太松：「rice」会因为「juice」对上橙汁，「shanxi pork」对上「lean pork」
        if query.count >= 3, key.count >= 2, similarity(query, key) >= similarThreshold { return .similar }
        return nil
    }

    /// 两个名字的相似度：相邻两个字组成的片段有多少一样（0～1）
    static func similarity(_ a: String, _ b: String) -> Double {
        func pairs(_ s: String) -> Set<String> {
            let chars = Array(s)
            return Set(zip(chars, chars.dropFirst()).map { String([$0, $1]) })
        }
        let x = pairs(a)
        let y = pairs(b)
        guard !x.isEmpty, !y.isEmpty else { return 0 }
        return 2 * Double(x.intersection(y).count) / Double(x.count + y.count)
    }
}

/// 搜索结果的一行
nonisolated struct FoodSearchResult: Identifiable, Hashable, Sendable {
    let choice: FoodChoice
    let match: FoodMatch
    /// 最近吃过（显示「最近吃过」的小字）
    let isRecent: Bool
    /// 打的字对上的是别名（显示「也叫…」时用）；对上的是正式名字时是 nil
    let matchedAlias: String?

    var id: String { choice.id }
}

/// 我的食物，搜索和份量页要用到的样子（不依赖数据库，方便测试）
nonisolated struct CustomFoodSnapshot: Identifiable, Hashable, Sendable {
    let id: UUID
    let name: String
    let amountUnit: AmountUnit
    let servingName: String
    let servingAmount: Double?  // 1 份多少克（毫升）；nil = 不知道重量
    let servingValues: NutrientValues  // 1 份的营养
    var source: CustomFoodSource = .user
    var labelBasis: NutritionLabelBasis? = nil  // 照包装填写的：营养成分表按什么写
    var packageName: String? = nil  // 一包的单位（PackageUnit 的 id）
    var packageAmount: Double? = nil  // 一包多少克（毫升）
    var foodType: EstimatedFoodType? = nil
    var basedOnRef: String? = nil  // 差不多的菜：按哪道菜估算的
    var lastUsedAt: Date? = nil

    var isAIEstimate: Bool { source == .ai }
    /// 数字是估算的（AI 估算、差不多的菜）：取整、写「约」
    var isEstimate: Bool { source != .user }
    /// 能选油量：估算出来的菜（AI 说是菜，或者按一道家常菜估算的；按克算）
    var adjustsOil: Bool { isEstimate && foodType == .dish && amountUnit == .gram }
    /// 按哪道菜估算的（显示「按「青椒肉丝」估算」）
    var basedOnName: String? { FoodCatalog.shared.food(ref: basedOnRef)?.displayName }

    /// 「1 份」：没写单位名就是「份」
    var servingUnit: ServingUnit {
        let name = servingName.trimmingCharacters(in: .whitespaces)
        return ServingUnit.named(name.isEmpty ? String(localized: "份") : name, id: "custom", amount: servingAmount ?? 0)
    }

    /// 「1 包」：照包装填写、填了一包多重的才有（每份的表还要知道每份多重，才能换算）
    var packageUnit: ServingUnit? {
        guard let unit = PackageUnit.named(packageName), let amount = packageAmount, amount > 0 else { return nil }
        if labelBasis == .perServing, (servingAmount ?? 0) <= 0 { return nil }
        return unit.servingUnit(amount: amount)
    }

    /// 记录时能选的自然份量。每 100 克的营养成分表没有「份」：只按克数，或者按一包
    var units: [ServingUnit] {
        var units: [ServingUnit] = labelBasis == .per100 ? [] : [servingUnit]
        if let packageUnit { units.append(packageUnit) }
        return units
    }
}

nonisolated enum FoodSearch {
    /// 搜索。query 为空时返回空（页面这时显示「最近吃过」「常吃」）。
    /// recents 要按时间从新到旧排好（RecentFoods.from 的结果）
    static func results(
        query: String, catalog: FoodCatalog, custom: [CustomFoodSnapshot], recents: [RecentFood], limit: Int = 30
    ) -> [FoodSearchResult] {
        let normalizer = catalog.normalizer
        let q = normalizer.key(query)
        guard !q.isEmpty else { return [] }

        // 先把最近吃过的分好：哪些就是食物库 / 我的食物里的，哪些是单独的
        var recentForCatalog: [String: RecentFood] = [:]
        var recentForCustom: [UUID: RecentFood] = [:]
        var standaloneRecents: [(food: RecentFood, order: Int)] = []
        for (order, recent) in recents.enumerated() {
            if let id = FoodRef.customID(recent.foodRef), custom.contains(where: { $0.id == id }) {
                if recentForCustom[id] == nil { recentForCustom[id] = recent }
            } else if let food = catalog.food(ref: recent.foodRef) ?? catalog.exactMatch(recent.name) {
                if recentForCatalog[food.id] == nil { recentForCatalog[food.id] = recent }
            } else {
                standaloneRecents.append((recent, order))
            }
        }
        let recentOrder = Dictionary(recents.enumerated().map { ($0.element.id, $0.offset) }, uniquingKeysWith: min)

        struct Ranked {
            let result: FoodSearchResult
            let tier: Int
            let sourceRank: Int  // 同样完全一样时：我的食物 0、最近吃过 1、食物库 2
            let recency: Int
        }
        var ranked: [Ranked] = []

        // 我的食物
        for food in custom {
            guard let match = FoodMatch.of(query: q, key: normalizer.key(food.name)) else { continue }
            let recent = recentForCustom[food.id]
            let result = FoodSearchResult(
                choice: .custom(food, recent: recent), match: match, isRecent: recent != nil, matchedAlias: nil)
            let order = recent.flatMap { recentOrder[$0.id] } ?? Int.max
            ranked.append(Ranked(result: result, tier: match == .exact ? 0 : (match >= .contains ? 1 : 4), sourceRank: 0, recency: order))
        }

        // 食物库：每种食物取对得最好的那个名字
        var best: [Int: (match: FoodMatch, key: String)] = [:]
        for entry in catalog.index {
            guard let match = FoodMatch.of(query: q, key: entry.key) else { continue }
            if let current = best[entry.foodIndex], current.match >= match { continue }
            best[entry.foodIndex] = (match, entry.key)
        }
        for (foodIndex, hit) in best {
            let food = catalog.foods[foodIndex]
            let recent = recentForCatalog[food.id]
            let isOwnName = normalizer.key(food.displayName) == hit.key
            let alias = isOwnName ? nil : food.allNames.first { normalizer.key($0) == hit.key }
            let result = FoodSearchResult(
                choice: .catalog(food, recent: recent), match: hit.match, isRecent: recent != nil, matchedAlias: alias)
            let tier: Int
            switch hit.match {
            case .exact: tier = 0
            case .prefix, .contains: tier = recent != nil ? 2 : 3
            case .inside, .similar: tier = 4
            }
            let order = recent.flatMap { recentOrder[$0.id] } ?? Int.max
            ranked.append(Ranked(result: result, tier: tier, sourceRank: recent != nil ? 1 : 2, recency: order))
        }

        // 单独的最近吃过（以前随手记的）
        for item in standaloneRecents {
            guard let match = FoodMatch.of(query: q, key: normalizer.key(item.food.name)) else { continue }
            let units = catalog.exactMatch(item.food.name)?.units ?? []
            let result = FoodSearchResult(
                choice: .recent(item.food, catalogUnits: units), match: match, isRecent: true, matchedAlias: nil)
            ranked.append(Ranked(result: result, tier: match == .exact ? 0 : (match >= .contains ? 2 : 4), sourceRank: 1, recency: item.order))
        }

        ranked.sort { a, b in
            if a.tier != b.tier { return a.tier < b.tier }
            if a.result.match != b.result.match { return a.result.match > b.result.match }
            if a.sourceRank != b.sourceRank { return a.sourceRank < b.sourceRank }
            if a.recency != b.recency { return a.recency < b.recency }
            return a.result.choice.name.count < b.result.choice.name.count
        }
        return Array(ranked.prefix(limit).map(\.result))
    }

    /// 有没有名字完全一样的结果（没有的话，页面把「AI 估算」放得更显眼）
    static func hasExactMatch(_ results: [FoodSearchResult]) -> Bool {
        results.contains { $0.match == .exact }
    }

    /// 最近吃过 / 常吃里的一项点进去：变成可以选份量的食物（是食物库或我的食物里的，就用那边的单位）
    static func choice(for recent: RecentFood, catalog: FoodCatalog, custom: [CustomFoodSnapshot]) -> FoodChoice {
        if let id = FoodRef.customID(recent.foodRef), let food = custom.first(where: { $0.id == id }) {
            return .custom(food, recent: recent)
        }
        if let food = catalog.food(ref: recent.foodRef) ?? catalog.exactMatch(recent.name) {
            return .catalog(food, recent: recent)
        }
        return .recent(recent)
    }
}
