//
//  NutritionLabelTests.swift
//  FoodTrackerTests
//
//  第七轮第二版：菜和包装食品分开处理。
//  - 包装食品照营养成分表填：每 100 克 / 每份、能量可以填千焦、一包多少克
//  - 菜不让人填营养：AI 估算或「差不多的菜」，再选「少油 / 正常 / 多油」
//  - AI 说是包装食品时，提示照营养成分表填
//

import Foundation
import Testing

@testable import FoodTracker

// MARK: - 照营养成分表填写

@Suite("照营养成分表填写")
struct NutritionLabelInputTests {
    private func label(
        _ column: LabelColumn = .per100g, energy: Double? = 2010, unit: EnergyUnit = .kilojoule, size: Double? = nil,
        protein: Double? = 6.5, fat: Double? = 20, carbs: Double? = 68, package: Double? = nil
    ) -> NutritionLabelInput {
        NutritionLabelInput(
            name: " 某某牌饼干 ", column: column, servingSize: size, energy: energy, energyUnit: unit, protein: protein,
            fat: fat, carbs: carbs, packageID: "pack", packageAmount: package)
    }

    @Test("千焦换算成千卡：2010 千焦 ≈ 480 千卡；千卡照抄")
    func energyUnits() throws {
        #expect(abs(EnergyUnit.kilojoule.kcal(2010) - 480.4) < 0.1)
        #expect(EnergyUnit.kilocalorie.kcal(480) == 480)
        #expect(abs(EnergyUnit.kilojoule.value(fromKcal: 100) - 418.4) < 0.001)
        let fields = try #require(label().fields)
        #expect(fields.servingValues.caloriesKcal == 480)  // 整数千卡
        #expect(fields.servingValues.fatG == 20 && fields.servingValues.carbsG == 68 && fields.servingValues.proteinG == 6.5)
        #expect(fields.name == "某某牌饼干")  // 去掉多余的空格
    }

    @Test("每 100 克的表：1 份 = 100 克；填了一包多重才有「包」")
    func per100() throws {
        let plain = try #require(label().fields)
        #expect(plain.basis == .per100 && plain.amountUnit == .gram && plain.servingAmount == 100)
        #expect(plain.packageName == nil && plain.packageAmount == nil)
        let withPackage = try #require(label(package: 30).fields)
        #expect(withPackage.packageName == "pack" && withPackage.packageAmount == 30)
        let drink = try #require(label(.per100ml, energy: 180, protein: 0, fat: 0, carbs: 10.6).fields)
        #expect(drink.amountUnit == .milliliter && drink.servingValues.caloriesKcal == 43)
    }

    @Test("每份的表：每份多少克可以不知道；不知道时不能按一包记")
    func perServing() throws {
        let known = try #require(
            label(.perServing, energy: 150, unit: .kilocalorie, size: 30, protein: 2, fat: 7, carbs: 20, package: 90).fields)
        #expect(known.basis == .perServing && known.servingAmount == 30 && known.packageAmount == 90)
        let unknownInput = label(.perServing, energy: 150, unit: .kilocalorie, size: nil, package: 90)
        #expect(!unknownInput.canUsePackage)
        let unknown = try #require(unknownInput.fields)
        #expect(unknown.servingAmount == nil && unknown.packageAmount == nil)
    }

    @Test("检查：名称、能量必填；每 100 克不会超过约 900 千卡；营养素加起来不能比一份还重")
    func validation() {
        #expect(label(energy: nil).fields == nil)
        #expect(NutritionLabelInput(name: "  ", energy: 100).fields == nil)
        #expect(label(energy: 4000).energyError != nil)  // 4000 千焦 ≈ 956 千卡 / 100 克
        #expect(label(energy: 3700).energyError == nil)  // ≈ 884，像纯油
        #expect(label(energy: 0).energyError != nil)
        #expect(label(protein: 50, fat: 40, carbs: 30).macrosError != nil)  // 120 克 > 100 克
        #expect(label(.perServing, energy: 150, unit: .kilocalorie, size: 30, protein: 10, fat: 10, carbs: 15).macrosError != nil)
        #expect(label(.perServing, energy: 150, unit: .kilocalorie, size: nil, protein: 10, fat: 10, carbs: 15).macrosError == nil)
        #expect(label(protein: nil, fat: nil, carbs: nil).fields != nil)  // 营养素可以都不填
    }

    @Test("打开修改：存下来的样子放回表单（能量按千卡显示）")
    func roundTrip() throws {
        let fields = try #require(label(package: 30).fields)
        let snapshot = CustomFoodSnapshot(
            id: UUID(), name: fields.name, amountUnit: fields.amountUnit, servingName: "", servingAmount: fields.servingAmount,
            servingValues: fields.servingValues, labelBasis: fields.basis, packageName: fields.packageName,
            packageAmount: fields.packageAmount, foodType: .packaged)
        let input = NutritionLabelInput(food: snapshot)
        #expect(input.column == .per100g && input.energyUnit == .kilocalorie && input.energy == 480)
        #expect(input.packageID == "pack" && input.packageAmount == 30)
        #expect(input.fields?.servingValues == fields.servingValues)
    }

    @Test("一包的单位从固定的几个里选，英文有单复数")
    func packageUnits() throws {
        #expect(PackageUnit.all.count >= 8)
        #expect(Set(PackageUnit.all.map(\.id)).count == PackageUnit.all.count)
        let bottle = try #require(PackageUnit.named("bottle"))
        #expect(bottle.name == "瓶" && bottle.nameEnPlural == "bottles")
        #expect(PackageUnit.named("1") == nil)  // 第一版能打字，打了「1」：现在认不出来就不显示
    }
}

// MARK: - 我的食物的份量

@Suite("我的食物：包装食品的份量")
struct LabelFoodUnitsTests {
    private func food(
        basis: NutritionLabelBasis?, size: Double?, package: Double?, values: NutrientValues = NutrientValues(caloriesKcal: 480)
    ) -> CustomFoodSnapshot {
        CustomFoodSnapshot(
            id: UUID(), name: "某某牌饼干", amountUnit: .gram, servingName: "", servingAmount: size, servingValues: values,
            labelBasis: basis, packageName: package == nil ? nil : "pack", packageAmount: package, foodType: .packaged)
    }

    @Test("每 100 克、没填一包多重：只能按克，从 100 克开始")
    func per100Plain() {
        let choice = FoodChoice.custom(food(basis: .per100, size: 100, package: nil))
        #expect(choice.units.isEmpty)
        #expect(choice.initialSelection == .amount(100))
        #expect(ServingMath.values(of: .amount(30), in: choice).caloriesKcal == 144)
        #expect(!choice.isEstimate && !choice.adjustsOil)  // 照包装填的：数字准确，不用选油量
    }

    @Test("每 100 克、填了一包 30 克：可以选「1 包」")
    func per100Package() throws {
        let choice = FoodChoice.custom(food(basis: .per100, size: 100, package: 30))
        let pack = try #require(choice.units.first)
        #expect(choice.units.count == 1 && pack.id == "package" && pack.name == "包" && pack.amount == 30)
        #expect(choice.initialSelection == .natural(unitID: "package", quantity: 1))
        #expect(ServingMath.values(of: choice.initialSelection, in: choice).caloriesKcal == 144)
    }

    @Test("每份的表：先是「份」，知道每份多重时还有「包」")
    func perServing() {
        let known = FoodChoice.custom(food(basis: .perServing, size: 25, package: 100, values: NutrientValues(caloriesKcal: 120)))
        #expect(known.units.map(\.id) == ["custom", "package"])
        #expect(ServingMath.values(of: .natural(unitID: "package", quantity: 1), in: known).caloriesKcal == 480)
        let unknown = FoodChoice.custom(food(basis: .perServing, size: nil, package: 100, values: NutrientValues(caloriesKcal: 120)))
        #expect(unknown.units.map(\.id) == ["custom"])  // 不知道每份多重：没法换算一包
        #expect(unknown.basis == .perServing(NutrientValues(caloriesKcal: 120)))
    }
}

// MARK: - 油量

@Suite("少油 / 正常 / 多油")
struct OilLevelTests {
    let dish = NutrientValues(caloriesKcal: 300, proteinG: 22, carbsG: 18, fatG: 16)

    @Test("只改脂肪：多油 ×1.4、少油 ×0.7，热量按每克脂肪 9 千卡跟着变")
    func adjust() {
        let heavy = ServingMath.oilAdjusted(dish, .heavy)
        #expect(abs(heavy.fatG - 22.4) < 0.001 && abs(heavy.caloriesKcal - 357.6) < 0.001)
        #expect(heavy.proteinG == 22 && heavy.carbsG == 18)
        let light = ServingMath.oilAdjusted(dish, .light)
        #expect(abs(light.fatG - 11.2) < 0.001 && abs(light.caloriesKcal - 256.8) < 0.001)
        #expect(ServingMath.oilAdjusted(dish, .normal) == dish)
    }

    @Test("记录里存的是多油的数字：换回正常的再按选的算，不会叠加两次")
    func normalize() {
        for level in OilLevel.allCases {
            let back = ServingMath.oilNormalized(ServingMath.oilAdjusted(dish, level), from: level)
            #expect(abs(back.fatG - dish.fatG) < 0.001 && abs(back.caloriesKcal - dish.caloriesKcal) < 0.001)
        }
    }

    @Test("哪些能选油量：按做法估算的家常菜、AI 说是菜的；米饭、包装食品不能")
    func whichFoods() throws {
        let catalog = FoodCatalog.shared
        let tomatoEgg = try #require(catalog.food(id: "tomato_egg"))
        let rice = try #require(catalog.food(id: "rice"))
        let burger = try #require(catalog.foods.first { $0.name == "汉堡" })
        #expect(tomatoEgg.adjustsOil && !rice.adjustsOil && !burger.adjustsOil)
        func estimate(_ type: EstimatedFoodType?, _ unit: AmountUnit = .gram) -> FoodChoice {
            .aiEstimate(
                FoodEstimate(
                    name: "x", per100: NutrientValues(caloriesKcal: 100), amountUnit: unit, servingName: "份", servingAmount: 100,
                    foodType: type))
        }
        #expect(estimate(.dish).adjustsOil && !estimate(.dish).suggestsLabel)
        #expect(!estimate(.packaged).adjustsOil && estimate(.packaged).suggestsLabel)
        #expect(!estimate(.other).adjustsOil)
        #expect(!estimate(nil, .milliliter).adjustsOil)  // 旧版后端、按毫升：多半是饮品
    }

    @Test("上次选了「多油」：再打开还是多油，数字是正常做法的（打开后按多油算出来和上次一样）")
    func recentKeepsOil() throws {
        let food = try #require(FoodCatalog.shared.food(id: "tomato_egg"))
        let normal = FoodChoice.catalog(food)
        let normalValues = ServingMath.values(of: normal.initialSelection, in: normal)
        let logged = ServingMath.oilAdjusted(normalValues, .heavy)
        let recent = RecentFood(
            name: "番茄炒蛋", weightG: 200, values: DietLogMath.rounded(logged), servingQuantity: 1, servingUnitID: "serving",
            foodRef: "catalog:tomato_egg", loggedAt: .now, oilLevel: .heavy)
        let choice = FoodChoice.catalog(food, recent: recent)
        #expect(choice.adjustsOil && choice.initialOil == .heavy)
        let reopened = ServingMath.oilAdjusted(ServingMath.values(of: choice.initialSelection, in: choice), choice.initialOil)
        #expect(abs(reopened.caloriesKcal - DietLogMath.rounded(logged).caloriesKcal) < 1)
    }
}

// MARK: - 差不多的菜

@Suite("选一道差不多的菜")
struct SimilarDishTests {
    @Test("名字照用户写的，营养、单位按挑的那道菜；是估算，能选油量，还没有来源标记")
    func similar() throws {
        let base = try #require(FoodCatalog.shared.food(id: "pork_pepper"))
        let choice = FoodChoice.similar(name: "山西过油肉", basedOn: base)
        #expect(choice.name == "山西过油肉" && choice.isSimilar && choice.isEstimate && choice.foodRef == nil)
        #expect(choice.basedOnName == base.displayName)
        #expect(choice.adjustsOil == base.adjustsOil)
        #expect(choice.units == base.units)
        #expect(ServingMath.values(of: choice.initialSelection, in: choice) == ServingMath.values(of: FoodChoice.catalog(base).initialSelection, in: .catalog(base)))
    }

    @Test("保存到我的食物以后：标「估算」、按哪道菜估算的、能选油量")
    func savedSimilar() {
        let snapshot = CustomFoodSnapshot(
            id: UUID(), name: "山西过油肉", amountUnit: .gram, servingName: "份", servingAmount: 200,
            servingValues: NutrientValues(caloriesKcal: 308, proteinG: 22, carbsG: 18, fatG: 16), source: .similar,
            foodType: .dish, basedOnRef: "catalog:pork_pepper")
        #expect(snapshot.isEstimate && !snapshot.isAIEstimate && snapshot.adjustsOil)
        let choice = FoodChoice.custom(snapshot)
        #expect(choice.isMine && choice.isEstimate && choice.adjustsOil)
        #expect(choice.basedOnName == FoodCatalog.shared.food(id: "pork_pepper")?.displayName)
    }

    @Test("后端返回的类型不认识时当作没说（不会读不出来）")
    func unknownFoodType() throws {
        let json = """
            {"is_food": true, "food_type": "drink", "name": "奶茶", "base_unit": "ml",
             "per_100": {"calories_kcal": 60, "protein_g": 1, "carbs_g": 10, "fat_g": 2},
             "serving_name": "杯", "serving_amount": 500, "message": "", "model": "claude", "remaining_today": 3}
            """
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let response = try decoder.decode(EstimateResponse.self, from: Data(json.utf8))
        let estimate = FoodEstimate(response, query: "奶茶")
        #expect(estimate.foodType == nil && !estimate.isDish)  // 按毫升：不当作菜
    }
}

// MARK: - 拍营养成分表

@Suite("拍营养成分表：从认出来的字里找数字")
struct NutritionLabelParserTests {
    private func parse(_ rows: [String]) -> LabelScanResult { NutritionLabelParser.parse(rows: rows) }

    @Test("中国常见的营养成分表（每 100 克）：跳过 NRV%、饱和脂肪、糖、钠")
    func chinesePer100() {
        let result = parse([
            "营养成分表", "项目 每100克 营养素参考值%", "能量 2010千焦 24%", "蛋白质 6.5克 11%", "脂肪 20.0克 33%",
            "—饱和脂肪 9.0克 45%", "碳水化合物 68.0克 23%", "—糖 22.0克", "钠 300毫克 15%",
        ])
        #expect(result.column == .per100g)
        #expect(result.energy == 2010 && result.energyUnit == .kilojoule)
        #expect(result.protein == 6.5 && result.fat == 20 && result.carbs == 68)
        #expect(result.nutrientCount == 4 && result.packageAmount == nil)
    }

    @Test("两列的表（每 100 克、每份）：数字按先出现的那一列")
    func twoColumns() {
        let result = parse(["项目 每100克 每份(30克) NRV%", "能量 2010千焦 603千焦 24%", "蛋白质 6.5克 2.0克 11%"])
        #expect(result.column == .per100g && result.energy == 2010 && result.protein == 6.5)
    }

    @Test("每份的表：每份多少克也认出来")
    func perServing() {
        let result = parse(["项目 每份(25克) NRV%", "能量 502kJ 6%", "蛋白质 1.6g 3%", "脂肪 5.0g 8%", "碳水化合物 17.0g 6%"])
        #expect(result.column == .perServing && result.servingSize == 25 && result.servingUnit == .gram)
        #expect(result.energy == 502 && result.energyUnit == .kilojoule && result.carbs == 17)
    }

    @Test("饮料（每 100 毫升）：0 克也算认出来；拍到净含量就填上")
    func drink() {
        let result = parse([
            "项目 每100毫升 NRV%", "能量 180千焦 2%", "蛋白质 0克 0%", "脂肪 0克 0%", "碳水化合物 10.6克 4%", "钠 12毫克 1%",
            "净含量：330毫升",
        ])
        #expect(result.column == .per100ml && result.energy == 180)
        #expect(result.protein == 0 && result.fat == 0 && result.carbs == 10.6)
        #expect(result.packageAmount == 330)
    }

    @Test("美国的 Nutrition Facts：每份（Serving size 的克数）、Calories 是千卡、跳过 Saturated / Trans Fat")
    func usLabel() {
        let result = parse([
            "Nutrition Facts", "8 servings per container", "Serving size 2/3 cup (55g)", "Amount per serving", "Calories 230",
            "Total Fat 8g 10%", "Saturated Fat 1g 5%", "Trans Fat 0g", "Cholesterol 0mg 0%", "Sodium 160mg 7%",
            "Total Carbohydrate 37g 13%", "Dietary Fiber 4g 14%", "Total Sugars 12g", "Protein 3g",
        ])
        #expect(result.column == .perServing && result.servingSize == 55 && result.servingUnit == .gram)
        #expect(result.energy == 230 && result.energyUnit == .kilocalorie)
        #expect(result.fat == 8 && result.carbs == 37 && result.protein == 3)
    }

    @Test("美国旧包装的「Calories from Fat 70」不当成脂肪")
    func caloriesFromFat() {
        let result = parse(["Calories 230 Calories from Fat 70", "Total Fat 8g"])
        #expect(result.energy == 230 && result.fat == 8)
    }

    @Test("全角数字、冒号、一行写完的营养成分表、千位逗号、没写单位的能量")
    func variants() {
        let fullWidth = parse(["能量：２０１０ｋＪ", "蛋白质：６．５ｇ"])
        #expect(fullWidth.energy == 2010 && fullWidth.energyUnit == .kilojoule && fullWidth.protein == 6.5)
        let inline = parse(["每100g含：能量2010kJ，蛋白质6.5g，脂肪20.0g，碳水化合物68.0g"])
        #expect(inline.column == .per100g && inline.energy == 2010 && inline.protein == 6.5)
        #expect(inline.fat == 20 && inline.carbs == 68)
        #expect(parse(["Calories 1,230"]).energy == 1230)
        let noUnit = parse(["能量(kJ) 2010"])
        #expect(noUnit.energy == 2010 && noUnit.energyUnit == .kilojoule)
        let heat = parse(["热量 480千卡"])
        #expect(heat.energy == 480 && heat.energyUnit == .kilocalorie)
        #expect(parse(["净含量：1.5千克"]).packageAmount == 1500)
    }

    @Test("不是营养成分表：什么都不填")
    func notALabel() {
        #expect(parse(["今天天气不错", "12345", "钠 300毫克"]).isEmpty)
        #expect(parse([]).isEmpty)
    }

    @Test("认出来的一段一段文字按行拼好：同一行从左到右，行从上到下")
    func rows() {
        let items = [
            RecognizedText(text: "6.5克", minX: 0.5, midY: 0.748, height: 0.03),
            RecognizedText(text: "能量", minX: 0.1, midY: 0.80, height: 0.03),
            RecognizedText(text: "蛋白质", minX: 0.1, midY: 0.75, height: 0.03),
            RecognizedText(text: "2010千焦", minX: 0.5, midY: 0.805, height: 0.03),
        ]
        #expect(NutritionLabelParser.rows(items) == ["能量 2010千焦", "蛋白质 6.5克"])
        #expect(NutritionLabelParser.rows([]).isEmpty)
    }

    @Test("照片拍斜了（转了 5°）：先摆正，同一行的名称和数字还能拼在一起")
    func tilted() {
        let angle = 5.0 * .pi / 180
        func box(_ text: String, x: Double, y: Double, width: Double) -> RawTextBox {
            func turn(_ px: Double, _ py: Double) -> CGPoint {
                CGPoint(x: px * cos(angle) - py * sin(angle), y: px * sin(angle) + py * cos(angle))
            }
            return RawTextBox(
                text: text, topLeft: turn(x, y + 15), topRight: turn(x + width, y + 15), bottomLeft: turn(x, y - 15),
                bottomRight: turn(x + width, y - 15))
        }
        let boxes = [
            box("能量", x: 100, y: 800, width: 100), box("2010千焦", x: 500, y: 800, width: 200),
            box("蛋白质", x: 100, y: 720, width: 150), box("6.5克", x: 500, y: 720, width: 120),
        ]
        let naive = boxes.map { box in
            RecognizedText(
                text: box.text, minX: box.topLeft.x,
                midY: (box.topLeft.y + box.topRight.y + box.bottomLeft.y + box.bottomRight.y) / 4, height: 30)
        }
        #expect(NutritionLabelParser.rows(naive) != ["能量 2010千焦", "蛋白质 6.5克"])  // 不摆正会拼错
        #expect(NutritionLabelParser.rows(NutritionLabelParser.straightened(boxes)) == ["能量 2010千焦", "蛋白质 6.5克"])
    }
}
