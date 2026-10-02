//
//  HintCopyTests.swift
//  FoodTrackerTests
//
//  热量提示文案的测试：每一条都不能用会制造负罪感的词（超标、警告、少吃、补偿、运动消耗……），也不用感叹号。
//  改了 HintCopy.swift 里的文案，跑一下这里就知道有没有踩线。
//

import Foundation
import Testing

@testable import FoodTracker

@Suite("热量提示文案")
struct HintCopyTests {
    /// 不能出现的词：责备、补偿、节食、运动抵消，以及感叹号
    static let banned = [
        "超标", "超出", "超过", "警告", "失控", "放纵", "惩罚", "少吃", "节食", "补偿", "补回", "抵消", "跳过", "不吃", "运动", "锻炼",
        "消耗", "燃烧", "失败", "!", "！",
    ]

    @Test("每条文案都不用会制造负罪感的词，也不用感叹号")
    func noBannedWords() {
        #expect(HintCopy.allSamples.count > 40)
        for sample in HintCopy.allSamples {
            #expect(!sample.isEmpty)
            for word in Self.banned {
                #expect(!sample.contains(word), "「\(word)」出现在：\(sample)")
            }
        }
    }

    @Test("数字和餐名出现在句子里；数字太小时不写数字")
    func numbers() {
        let near210 = HintCopy.nearLimit(remainingKcal: 210, mealName: "晚餐")
        #expect(near210.contains("210") && near210.contains("晚餐"))
        let near90 = HintCopy.nearLimit(remainingKcal: 90, mealName: "晚餐")
        #expect(near90.contains("接近目标") && !near90.contains("90"))
        let over40 = HintCopy.over(byKcal: 40, nextMealName: nil)
        #expect(over40.contains("目标线上") && !over40.contains("40") && !over40.contains("约 0"))
        #expect(HintCopy.over(byKcal: 0, nextMealName: "晚餐").contains("晚餐"))
        let over190 = HintCopy.over(byKcal: 190, nextMealName: "晚餐")
        #expect(over190.contains("190") && over190.contains("晚餐"))
        let above = HintCopy.weeklyAbove(differenceKcal: 367)
        #expect(above.contains("平均每天") && above.contains("367"))
        let numbers = HintCopy.weeklyNumbers(averageKcal: 1510, targetKcal: 1463, daysCounted: 5)
        #expect(numbers.contains(1510.formatted()) && numbers.contains(1463.formatted()) && numbers.contains("5 天"))
        let floor60 = HintCopy.nextMealRaisedToFloor(remainingKcal: 60, floorKcal: 320, mealName: "晚餐")
        #expect(floor60.contains("接近目标") && !floor60.contains("约 60"))
        let floor150 = HintCopy.nextMealRaisedToFloor(remainingKcal: 150, floorKcal: 320, mealName: "晚餐")
        #expect(floor150.contains("150") && floor150.contains("320"))
    }

    @Test("比目标多：说清楚多了多少，一句平静的话，不提补偿")
    func overCopy() {
        let over150 = HintCopy.over(byKcal: 150, nextMealName: nil)
        #expect(over150.contains("今天比目标多") && over150.contains("150"))
        #expect(over150.contains("很正常"))
        let withMeal = HintCopy.over(byKcal: 150, nextMealName: "晚餐")
        #expect(withMeal.contains("晚餐照常吃"))
    }

    @Test("吃得少：不表扬，告诉用户饿了可以正常吃")
    func belowPlanCopy() {
        let text = HintCopy.belowPlan
        #expect(text.contains("如果还饿") && text.contains("正常吃"))
        for word in ["很棒", "真棒", "厉害", "做得好", "太好了", "继续保持", "恭喜", "优秀"] {
            #expect(!text.contains(word), "「\(word)」")
        }
    }

    @Test("设置项的三个选项")
    func settings() {
        #expect(HintLevel.allCases.map(HintCopy.levelTitle) == ["全部开启", "只看每周小结", "关闭"])
        #expect(Set(HintLevel.allCases.map(HintCopy.levelExplanation)).count == 3)
    }
}
