//
//  FoodEntry.swift
//  FoodTracker
//
//  一条饮食记录 = 一种食物，存在手机本地（SwiftData）。
//  拍照识别出 3 种食物就是 3 条记录；同一天同一餐的记录（dayKey + mealRaw 相同）显示在一起。
//
//  ⚠️ 以后改这个类只能「加」，不能「改」，否则手机上已有的数据会读不出来：
//  - 新属性只用 String / Int / Double / Bool / Date 这类简单类型，并且要有默认值，或者是可选的（类型后面带 ?）
//  - 选项（枚举）照 mealRaw 的样子存英文文字；不要直接存枚举或自己定义的结构体：
//    旧记录读这个新属性会闪退（枚举），或者整个数据库打不开（结构体）
//  - 想改属性名，要用 @Attribute(originalName: "旧名字")
//  - 不要改已有属性的类型
//
//  「哪一天」一律用 dayKey 这个数字传来传去，只在显示时才换成日期（见 DayMath.date(fromDayKey:)）：
//  先换成日期、过一会儿再换回数字的话，中途手机换了时区，记录就会跑到前一天或后一天
//

import Foundation
import SwiftData

@Model
final class FoodEntry {
    /// 记在哪一天：20260929 这样的数字（见 DayMath.dayKey）。
    /// 按年月日存，手机换了时区，记录也还在原来那天
    var dayKey: Int
    var mealRaw: String  // MealType 的英文名，存文字最稳妥（和 UserProfile.sexRaw 一样）
    var name: String
    var weightG: Double?  // nil = 不知道重量
    var caloriesKcal: Double  // 存进来之前已经取整
    var proteinG: Double  // 存进来之前已经保留 1 位小数
    var carbsG: Double
    var fatG: Double
    var sourceRaw: String  // EntrySource 的英文名：photo / manual / recipe
    var createdAt: Date  // 同一餐里按添加的先后排

    // 第七轮加的（都是可选的：以前的记录读出来是 nil，照常显示成「约 150 克」）
    var amountUnitRaw: String? = nil  // weightG 的单位：nil 或 "g" = 克，"ml" = 毫升
    var servingQuantity: Double? = nil  // 选了自然份量时：几份（1.5）
    var servingUnitID: String? = nil  // 哪个单位（bowl）
    var servingUnitName: String? = nil  // 单位当时显示的名字（「碗」）
    var foodRef: String? = nil  // 来自哪种食物：catalog:rice、custom:<UUID>
    var oilLevelRaw: String? = nil  // 家常菜选的油量：light / heavy；nil = 正常（或不是家常菜）

    // 第九轮加的：没吃完（都是可选的：以前的记录读出来是 nil，就是全部吃完）。
    // 上面的重量、热量、营养素存的一直是「吃下去的」；下面几个记住「原来盛了多少」，改回全部吃完时原样换回去。
    // 没吃完时 servingQuantity 是 nil（吃下去的部分只按克记：「0.75 碗」不好读），单位的编号和名字还留着，换回去时用
    var eatenFraction: Double? = nil  // 吃了几成：0.75、0.5、0.25；nil = 全部吃完
    var servedWeightG: Double? = nil
    var servedCaloriesKcal: Double? = nil
    var servedProteinG: Double? = nil
    var servedCarbsG: Double? = nil
    var servedFatG: Double? = nil
    var servedServingQuantity: Double? = nil

    /// dayKey：记到哪一天，20260929 这样的数字。要记到「今天」就写 DayMath.dayKey(for: .now)
    init(
        dayKey: Int, meal: MealType, name: String, weightG: Double?, values: NutrientValues, source: EntrySource,
        createdAt: Date = .now, amountUnit: AmountUnit = .gram, serving: ServingChoice? = nil, foodRef: String? = nil,
        oilLevel: OilLevel? = nil
    ) {
        self.dayKey = dayKey
        self.mealRaw = meal.rawValue
        self.name = name
        self.weightG = weightG
        self.caloriesKcal = values.caloriesKcal
        self.proteinG = values.proteinG
        self.carbsG = values.carbsG
        self.fatG = values.fatG
        self.sourceRaw = source.rawValue
        self.createdAt = createdAt
        self.amountUnitRaw = amountUnit == .gram ? nil : amountUnit.rawValue
        self.servingQuantity = serving?.quantity
        self.servingUnitID = serving?.unitID
        self.servingUnitName = serving?.unitName
        self.foodRef = foodRef
        self.oilLevelRaw = oilLevel == .normal ? nil : oilLevel?.rawValue
    }

    /// 克还是毫升
    var amountUnit: AmountUnit { AmountUnit(storedValue: amountUnitRaw) }

    /// 家常菜选的油量（没选过、不是家常菜是 nil）
    var oilLevel: OilLevel? { oilLevelRaw.flatMap(OilLevel.init(rawValue:)) }

    /// 选了自然份量时：哪个单位、几份
    var serving: ServingChoice? {
        guard let quantity = servingQuantity, let id = servingUnitID, let name = servingUnitName else { return nil }
        return ServingChoice(unitID: id, unitName: name, quantity: quantity)
    }

    /// 记在哪一天（那天的 0 点，按手机当前的时区）。
    /// 故意写成「方法」而不是「属性」：查询条件里用了算出来的属性，能编译但运行时会闪退；
    /// 写成方法的话，误用时编译器会直接报错
    func day(calendar: Calendar = DayMath.calendar) -> Date {
        DayMath.date(fromDayKey: dayKey, calendar: calendar)
    }

    // ⚠️ 下面的 meal、source、values 是「算出来的属性」，数据库里没有这几列，只能在查出来以后用。
    //    #Predicate 和排序里要写存下来的 mealRaw、sourceRaw、caloriesKcal 等：写 $0.meal 能编译，但运行时会闪退
    var meal: MealType {
        get { MealType(rawValue: mealRaw) ?? .snack }
        set { mealRaw = newValue.rawValue }
    }

    var source: EntrySource { EntrySource(rawValue: sourceRaw) ?? .manual }

    var values: NutrientValues {
        NutrientValues(caloriesKcal: caloriesKcal, proteinG: proteinG, carbsG: carbsG, fatG: fatG)
    }

    /// 修改后保存：把表单里的内容写回这条记录（日期也是数字，直接写回，不经过时区换算）。
    /// 没吃完的记录：重量和数字都没改（只改了名字、餐次、日期）就还按「吃了几成」记；
    /// 改了数字就按新填的算，不再是「原来的几成」了（和油量的规则一样）
    func apply(_ item: EditableItem) {
        let keepsEaten = eatenFraction != nil && item.weightG == weightG && item.values == values
        name = item.name
        meal = item.meal
        if item.dayKey != dayKey { dayKey = item.dayKey }
        foodRef = item.foodRef
        oilLevelRaw = item.oilLevel == .normal ? nil : item.oilLevel?.rawValue
        // 数字没改：份量也不动（表单可能把 75 克认成「半碗」，换个写法而已，原来的份量还要留着换回去）
        guard !keepsEaten else { return }
        weightG = item.weightG
        caloriesKcal = item.values.caloriesKcal
        proteinG = item.values.proteinG
        carbsG = item.values.carbsG
        fatG = item.values.fatG
        amountUnitRaw = item.amountUnit == .gram ? nil : item.amountUnit.rawValue
        servingQuantity = item.serving?.quantity
        servingUnitID = item.serving?.unitID
        servingUnitName = item.serving?.unitName
        eatenFraction = nil
        servedPortion = nil
    }

    // MARK: - 没吃完

    /// 原来盛了多少：只有没吃完的记录才有（全部吃完时是 nil：原来的就是现在的）
    var servedPortion: ServedPortion? {
        get {
            guard eatenFraction != nil, let kcal = servedCaloriesKcal else { return nil }
            return ServedPortion(
                weightG: servedWeightG,
                values: NutrientValues(
                    caloriesKcal: kcal, proteinG: servedProteinG ?? 0, carbsG: servedCarbsG ?? 0, fatG: servedFatG ?? 0),
                servingQuantity: servedServingQuantity)
        }
        set {
            servedWeightG = newValue?.weightG
            servedCaloriesKcal = newValue?.values.caloriesKcal
            servedProteinG = newValue?.values.proteinG
            servedCarbsG = newValue?.values.carbsG
            servedFatG = newValue?.values.fatG
            servedServingQuantity = newValue?.servingQuantity
        }
    }

    /// 原来盛的营养（没吃完时是记下的原来的，吃完了就是现在的）
    var servedValues: NutrientValues { servedPortion?.values ?? values }

    /// 原来盛的自然份量（「1 碗」）：没吃完时用记下的份数，单位还是原来的
    var servedServing: ServingChoice? {
        guard eatenFraction != nil else { return serving }
        guard let quantity = servedServingQuantity, let id = servingUnitID, let name = servingUnitName else { return nil }
        return ServingChoice(unitID: id, unitName: name, quantity: quantity)
    }

    /// 吃了几成（全部吃完是 1）
    var eaten: Double { eatenFraction ?? 1 }

    /// 改成吃了几成（1 = 全部吃完）。每次都从「原来盛了多少」算，改几次都不会越乘越小；
    /// 改回 1 时原样换回原来的数字（不经过四舍五入）。0（没吃）一般由页面直接删掉这条，这里也能存成 0 千卡
    func setEaten(_ fraction: Double) {
        let fraction = fraction.isFinite ? min(max(fraction, 0), 1) : 1
        let served =
            servedPortion
            ?? ServedPortion(weightG: weightG, values: values, servingQuantity: servingQuantity)
        if fraction >= 1 {
            weightG = served.weightG
            caloriesKcal = served.values.caloriesKcal
            proteinG = served.values.proteinG
            carbsG = served.values.carbsG
            fatG = served.values.fatG
            servingQuantity = served.servingQuantity
            eatenFraction = nil
            servedPortion = nil
        } else {
            let eatenValues = EatenPortion.eatenValues(served: served.values, fraction: fraction)
            eatenFraction = fraction
            servedPortion = served
            weightG = EatenPortion.eatenWeight(served: served.weightG, fraction: fraction)
            caloriesKcal = eatenValues.caloriesKcal
            proteinG = eatenValues.proteinG
            carbsG = eatenValues.carbsG
            fatG = eatenValues.fatG
            servingQuantity = nil
        }
    }

    /// 把一餐里的几项食物一起存进数据库（识别结果页的「保存到今日」、调试菜单的示例记录都用它）。
    /// 每一项自己记的餐次和日期在这里用不上：整餐记到同一餐、同一天，由调用的地方决定。
    /// eatenFraction：识别结果页选了「这餐吃了多少」（全部是 1）。
    /// 同一次保存的几条记录 createdAt 相差 1 毫秒，保证显示顺序和保存前的列表一样。
    /// 这里不调用 save()，什么时候真正写进数据库由调用的地方决定
    @discardableResult
    static func insert(
        _ items: [EditableItem], meal: MealType, dayKey: Int, source: EntrySource, into context: ModelContext,
        now: Date = .now, eatenFraction: Double = 1
    ) -> [FoodEntry] {
        items.enumerated().map { index, item in
            let entry = FoodEntry(
                dayKey: dayKey, meal: meal, name: item.name, weightG: item.weightG,
                values: DietLogMath.rounded(item.values), source: source,
                createdAt: now.addingTimeInterval(Double(index) * 0.001), amountUnit: item.amountUnit,
                serving: item.serving, foodRef: item.foodRef, oilLevel: item.oilLevel)
            if eatenFraction < 1 { entry.setEaten(eatenFraction) }
            context.insert(entry)
            return entry
        }
    }

    // MARK: - 查询条件
    // 所有按日期查记录的地方都用这两个函数。数字在 #Predicate 外面先算好：查询条件里不能调用日历

    /// 某一天的记录
    static func predicate(day: Date, calendar: Calendar = DayMath.calendar) -> Predicate<FoodEntry> {
        let key = DayMath.dayKey(for: day, calendar: calendar)
        return #Predicate<FoodEntry> { $0.dayKey == key }
    }

    /// 从 start 那天到 end 那天之前的记录（包括 start，不包括 end）
    static func predicate(from start: Date, to end: Date, calendar: Calendar = DayMath.calendar) -> Predicate<FoodEntry> {
        let first = DayMath.dayKey(for: start, calendar: calendar)
        let last = DayMath.dayKey(for: end, calendar: calendar)
        return #Predicate<FoodEntry> { $0.dayKey >= first && $0.dayKey < last }
    }
}

extension EditableItem {
    /// 已保存的记录 → 编辑表单用的一项（要读 @Model，所以写在这里）
    init(entry: FoodEntry) {
        self.init(
            id: UUID(),
            name: entry.name,
            weightG: entry.weightG,
            values: entry.values,
            confidence: nil,
            meal: entry.meal,
            dayKey: entry.dayKey,
            amountUnit: entry.amountUnit,
            serving: entry.serving,
            foodRef: entry.foodRef,
            oilLevel: entry.oilLevel
        )
    }
}

/// 删除一条记录前先拍一张「快照」：点「撤销」时按它原样放回去（包括添加的时间，所以顺序也不变）
struct FoodEntrySnapshot {
    let dayKey: Int
    let meal: MealType
    let name: String
    let weightG: Double?
    let values: NutrientValues
    let source: EntrySource
    let createdAt: Date
    let amountUnit: AmountUnit
    // 份量的三样分开记：没吃完的记录 servingQuantity 是空的，但单位还要留着（改回吃完时用）
    let servingQuantity: Double?
    let servingUnitID: String?
    let servingUnitName: String?
    let foodRef: String?
    let oilLevel: OilLevel?
    let eatenFraction: Double?
    let servedPortion: ServedPortion?

    init(_ entry: FoodEntry) {
        dayKey = entry.dayKey
        meal = entry.meal
        name = entry.name
        weightG = entry.weightG
        values = entry.values
        source = entry.source
        createdAt = entry.createdAt
        amountUnit = entry.amountUnit
        servingQuantity = entry.servingQuantity
        servingUnitID = entry.servingUnitID
        servingUnitName = entry.servingUnitName
        foodRef = entry.foodRef
        oilLevel = entry.oilLevel
        eatenFraction = entry.eatenFraction
        servedPortion = entry.servedPortion
    }

    /// 放回数据库（调用的地方再 save）
    @discardableResult
    func restore(into context: ModelContext) -> FoodEntry {
        let entry = FoodEntry(
            dayKey: dayKey, meal: meal, name: name, weightG: weightG, values: values, source: source, createdAt: createdAt,
            amountUnit: amountUnit, foodRef: foodRef, oilLevel: oilLevel)
        entry.servingQuantity = servingQuantity
        entry.servingUnitID = servingUnitID
        entry.servingUnitName = servingUnitName
        entry.eatenFraction = eatenFraction
        entry.servedPortion = servedPortion
        context.insert(entry)
        return entry
    }
}

extension FoodEntry {
    /// 份量写给人看：「1.5 碗 · 约 225 克」「约 150 克」「约 250 毫升」；什么都不知道时是 nil。
    /// 没吃完的记录写原来盛的份量（「1 碗 · 约 150 克」），吃了几成另外写（见 MealRow）。
    /// 单位名优先用食物库里当前语言的写法（记录时存的是当时语言的名字）
    var portionText: String? {
        let unit = amountUnit
        let weight = eatenFraction == nil ? weightG : servedWeightG
        if let serving = servedServing {
            let catalogUnit = FoodCatalog.shared.food(ref: foodRef)?.units.first { $0.id == serving.unitID }
            let name = catalogUnit?.displayName(quantity: serving.quantity) ?? serving.unitName
            let servingText = PortionText.serving(serving.quantity, unitName: name)
            guard let weight else { return servingText }
            return "\(servingText) · \(PortionText.amount(weight, unit: unit, approximate: true))"
        }
        return weight.map { PortionText.amount($0, unit: unit, approximate: true) }
    }

    /// 没吃完时的小标签：「吃了一半」；全部吃完是 nil
    var eatenLabel: String? {
        eatenFraction.map(EatenPortion.itemLabel)
    }

    /// 合并显示时比较用的样子：名字、份量、热量
    var groupingItem: GroupingItem {
        GroupingItem(name: name, weightG: weightG, caloriesKcal: caloriesKcal)
    }

    /// 「最近使用」里的样子：名字和这一次的份量、营养（还有选的是哪个自然份量、来自哪种食物，下次打开按上次的份量）。
    /// 没吃完的记录按原来盛的份量：下次一般还是盛这么多，没吃完再调
    var recentFood: RecentFood {
        let served = servedPortion
        return RecentFood(
            name: name, weightG: served == nil ? weightG : served?.weightG, values: served?.values ?? values,
            amountUnit: amountUnit, servingQuantity: served == nil ? servingQuantity : served?.servingQuantity,
            servingUnitID: servingUnitID, foodRef: foodRef, loggedAt: createdAt, oilLevel: oilLevel)
    }

    /// 最近的记录（从新到旧），用来做「最近使用」。只取最近的几百条，够挑出常吃的食物，也不会慢
    static var recentDescriptor: FetchDescriptor<FoodEntry> {
        var descriptor = FetchDescriptor<FoodEntry>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        descriptor.fetchLimit = 300
        return descriptor
    }
}
