//
//  FoodCatalog.swift
//  FoodTracker
//
//  内置食物库：App 里自带的常见食物（FoodDatabase.json，由 tools/fooddb/build_food_db.py 生成，数据来源写在那里）。
//  - 每种食物的营养按「每 100 克」（饮品按「每 100 毫升」）存；选「1 碗」时先换算成克，再按克算营养，
//    和手动填写用的是同一套计算（DietLogMath.scaled），不另起一套
//  - 每种食物只带它真的会用的自然份量单位：米饭是碗、鸡蛋是个、牛奶是杯和盒；克 / 毫升总是能选
//  - 名字比较前先「规范化」：去掉空格标点、全角转半角、英文小写，再把同义词换成标准写法（西红柿 → 番茄）
//  食物库只读；用户自己建的、AI 估算后保存的食物存在「我的食物」（CustomFood），两边分开，AI 的结果不会写进这里
//

import Foundation

/// 份量用什么计：克，还是毫升（牛奶、饮料按毫升）
nonisolated enum AmountUnit: String, Codable, Hashable, Sendable {
    case gram = "g"
    case milliliter = "ml"

    /// 显示用的单位：「克」「毫升」
    var symbol: String {
        switch self {
        case .gram: String(localized: "克")
        case .milliliter: String(localized: "毫升")
        }
    }

    /// 读存下来的文字：没有或认不出就是克（旧记录都是克）
    init(storedValue: String?) {
        self = storedValue.flatMap(AmountUnit.init(rawValue:)) ?? .gram
    }
}

/// 一种自然份量单位：碗、个、片、杯……
/// amount 是 1 个单位大约多少克（或毫升），是常见大小的估算，界面上都写「约」；0 表示不知道多重（只按份数算）
nonisolated struct ServingUnit: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let name: String
    let nameEn: String
    let nameEnPlural: String
    let amount: Double
    let step: Double  // 每次加减多少：0.5 或 1

    /// 当前语言下的单位名：中文「碗」；英文 1 个用单数、其他用复数
    func displayName(quantity: Double) -> String {
        switch AppLanguage.current {
        case .zh: name
        case .en: quantity == 1 || quantity == 0.5 ? nameEn : nameEnPlural
        }
    }

    /// 只有一个名字的单位（我的食物、AI 估算给的单位，中英文一样）。名字就是「份」/ serving 时用下面的 serving（英文有复数）
    static func named(_ name: String, id: String, amount: Double, step: Double = 0.5) -> ServingUnit {
        if ["份", "serving", "servings"].contains(name.lowercased()) {
            return serving(id: id, amount: amount, step: step)
        }
        return ServingUnit(id: id, name: name, nameEn: name, nameEnPlural: name, amount: amount, step: step)
    }

    /// 「份」：没有更合适的单位时用
    static func serving(id: String = "serving", amount: Double, step: Double = 0.5) -> ServingUnit {
        ServingUnit(
            id: id, name: String(localized: "份"), nameEn: "serving", nameEnPlural: "servings", amount: amount, step: step)
    }
}

/// 食物库里的一种食物
nonisolated struct CatalogFood: Codable, Identifiable, Hashable, Sendable {
    struct Per100: Codable, Hashable, Sendable {
        let kcal: Double
        let protein: Double
        let carbs: Double
        let fat: Double
    }

    let id: String
    let name: String
    let nameEn: String
    let aliases: [String]
    let aliasesEn: [String]
    let category: String
    let baseUnit: AmountUnit
    let per100: Per100
    let source: String  // usda / cn / estimate
    let sourceRef: String
    let units: [ServingUnit]
    let defaultQuantity: Double

    /// 当前语言下的名字
    var displayName: String { AppLanguage.current == .en ? nameEn : name }

    /// 每 100 克（毫升）的营养
    var values100: NutrientValues {
        NutrientValues(caloriesKcal: per100.kcal, proteinG: per100.protein, carbsG: per100.carbs, fatG: per100.fat)
    }

    /// 按常见做法估算的家常菜：数字更粗略，界面上加「约」
    var isEstimate: Bool { source == "estimate" }

    /// 搜索时参与比较的所有名字（中英文名和别名）
    var allNames: [String] { [name] + aliases + [nameEn] + aliasesEn }

    /// 存进记录、以后找回这种食物用的标记
    var ref: String { FoodRef.catalog(id) }
}

/// 记录里「来自哪种食物」的写法：catalog:rice、custom:<UUID>。只是一段文字，以后加新的来源也不用改数据库
nonisolated enum FoodRef {
    static func catalog(_ id: String) -> String { "catalog:\(id)" }
    static func custom(_ id: UUID) -> String { "custom:\(id.uuidString)" }

    static func catalogID(_ ref: String?) -> String? {
        guard let ref, ref.hasPrefix("catalog:") else { return nil }
        return String(ref.dropFirst("catalog:".count))
    }

    static func customID(_ ref: String?) -> UUID? {
        guard let ref, ref.hasPrefix("custom:") else { return nil }
        return UUID(uuidString: String(ref.dropFirst("custom:".count)))
    }
}

/// 名字规范化 + 同义词：「西红柿炒鸡蛋」「番茄炒鸡蛋」比较时是同一个样子
nonisolated struct FoodNameNormalizer: Sendable {
    /// （规范化后的同义词，标准写法），长的排前面：从左往右扫描时先试长的词
    private let replacements: [(word: [Character], standard: String)]

    init(synonyms: [[String]]) {
        var pairs: [(word: [Character], standard: String)] = []
        for group in synonyms {
            guard let first = group.first else { continue }
            let standard = FoodNameKey.normalize(first)
            for word in group.dropFirst() {
                let key = FoodNameKey.normalize(word)
                if !key.isEmpty { pairs.append((Array(key), standard)) }
            }
        }
        replacements = pairs.sorted { $0.word.count > $1.word.count }
    }

    /// 比较用的样子：规范化以后，把同义词换成标准写法
    func key(_ text: String) -> String {
        let chars = Array(FoodNameKey.normalize(text))
        guard !replacements.isEmpty else { return String(chars) }
        var result = ""
        var index = 0
        while index < chars.count {
            if let hit = replacements.first(where: { matches($0.word, in: chars, at: index) }) {
                result += hit.standard
                index += hit.word.count
            } else {
                result.append(chars[index])
                index += 1
            }
        }
        return result
    }

    private func matches(_ word: [Character], in chars: [Character], at index: Int) -> Bool {
        guard index + word.count <= chars.count else { return false }
        for offset in word.indices where chars[index + offset] != word[offset] { return false }
        return true
    }
}

/// 整个食物库：第一次用到时从 App 里读出来，之后一直放在内存里（一百多种食物，很小）
nonisolated final class FoodCatalog: Sendable {
    struct FileFormat: Codable {
        let version: Int
        let synonyms: [[String]]
        let foods: [CatalogFood]
    }

    static let shared = FoodCatalog.loadBundled()

    let foods: [CatalogFood]
    let normalizer: FoodNameNormalizer
    private let byID: [String: CatalogFood]
    /// 每个名字规范化后的样子 → 第几种食物（搜索用）
    let index: [(key: String, foodIndex: Int)]
    private let exactKeys: [String: Int]

    init(file: FileFormat) {
        foods = file.foods
        normalizer = FoodNameNormalizer(synonyms: file.synonyms)
        byID = Dictionary(file.foods.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var entries: [(key: String, foodIndex: Int)] = []
        var exact: [String: Int] = [:]
        for (i, food) in file.foods.enumerated() {
            for name in food.allNames {
                let key = normalizer.key(name)
                guard !key.isEmpty else { continue }
                entries.append((key, i))
                if exact[key] == nil { exact[key] = i }
            }
        }
        index = entries
        exactKeys = exact
    }

    /// 读 App 里的 FoodDatabase.json；读不到（不应该发生）就是空的食物库，搜索直接走 AI 估算 / 自定义食物
    static func loadBundled(bundle: Bundle = .main) -> FoodCatalog {
        guard let url = bundle.url(forResource: "FoodDatabase", withExtension: "json"),
            let data = try? Data(contentsOf: url),
            let file = try? JSONDecoder().decode(FileFormat.self, from: data)
        else {
            assertionFailure("读不到内置食物库 FoodDatabase.json")
            return FoodCatalog(file: FileFormat(version: 0, synonyms: [], foods: []))
        }
        return FoodCatalog(file: file)
    }

    func food(id: String) -> CatalogFood? { byID[id] }

    /// 名字（或别名）规范化后完全一样的那种食物
    func exactMatch(_ name: String) -> CatalogFood? {
        exactKeys[normalizer.key(name)].map { foods[$0] }
    }

    /// 记录里写的来源是食物库：找回那种食物
    func food(ref: String?) -> CatalogFood? {
        FoodRef.catalogID(ref).flatMap(food(id:))
    }
}
