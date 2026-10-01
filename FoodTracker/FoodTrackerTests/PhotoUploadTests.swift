//
//  PhotoUploadTests.swift
//  FoodTrackerTests
//
//  第四轮新加的几处小逻辑：
//  - 多张照片一起识别：上传时每张照片放在哪个字段（第一张 photo，其余 more_photos），最多 4 张
//  - 「确认照片」页底部按钮上的字：一张写「开始识别」，多张写「识别 N 张照片」
//  - 手动添加 / 修改一项食物时，「更多营养信息」一开始是展开还是收起
//

import Foundation
import Testing

@testable import FoodTracker

@MainActor
@Suite("多张照片识别和手动添加")
struct PhotoUploadTests {
    private let boundary = "TestBoundary"

    /// 上传内容里的每个文件：(字段名, 文件名)，按出现的顺序
    private func fileParts(_ body: Data) -> [(field: String, fileName: String)] {
        let text = String(decoding: body, as: UTF8.self)
        let pattern = #/name="([a-z_]+)"; filename="([^"]+)"/#
        return text.matches(of: pattern).map { (String($0.output.1), String($0.output.2)) }
    }

    @Test("只有一张照片：和以前完全一样，只有 photo 一个文件字段")
    func singlePhoto() {
        let body = APIClient.multipartBody(jpegs: [Data("A".utf8)], lang: "zh", boundary: boundary)
        let parts = fileParts(body)
        #expect(parts.map(\.field) == ["photo"])
        #expect(parts.map(\.fileName) == ["meal.jpg"])
    }

    @Test("三张照片：第一张是 photo，另外两张是 more_photos，顺序不变")
    func threePhotos() {
        let jpegs = ["第一张", "第二张", "第三张"].map { Data($0.utf8) }
        let body = APIClient.multipartBody(jpegs: jpegs, lang: "en", boundary: boundary)
        let parts = fileParts(body)
        #expect(parts.map(\.field) == ["photo", "more_photos", "more_photos"])
        #expect(parts.map(\.fileName) == ["meal.jpg", "meal-2.jpg", "meal-3.jpg"])

        // 每张照片的内容原样放进去，并且按顺序；语言字段和结束标记都在
        let text = String(decoding: body, as: UTF8.self)
        let positions = ["第一张", "第二张", "第三张"].compactMap { text.range(of: $0)?.lowerBound }
        #expect(positions.count == 3)
        #expect(positions == positions.sorted())
        #expect(text.contains("name=\"lang\"\r\n\r\nen\r\n"))
        #expect(text.hasSuffix("--\(boundary)--\r\n"))
    }

    @Test("同一餐最多 4 张照片（和后端的上限一样）")
    func maxPhotos() {
        #expect(APIClient.maxPhotos == 4)
    }

    @Test("按钮上的字：一张写「开始识别」，多张写「识别 N 张照片」")
    func analyzeTitle() {
        #expect(PhotoReviewView.analyzeTitle(photoCount: 1) == "开始识别")
        #expect(PhotoReviewView.analyzeTitle(photoCount: 2) == "识别 2 张照片")
        #expect(PhotoReviewView.analyzeTitle(photoCount: 4) == "识别 4 张照片")
    }

    @Test("新的一项：「更多营养信息」先收起来；已经有蛋白质、碳水或脂肪的：直接展开")
    func nutritionSectionStartsShownOnlyWithValues() {
        let empty = EntryDraft(meal: .lunch, dayKey: 20261001)
        #expect(!EntryEditView.startsWithNutritionShown(empty))

        // 只填了其中一项也要展开，不然用户看不到自己填过的数
        let fatOnly = EntryDraft(meal: .lunch, dayKey: 20261001)
        fatOnly.fatText = "5"
        #expect(EntryEditView.startsWithNutritionShown(fatOnly))

        // 只有空格不算填了
        let spaces = EntryDraft(meal: .lunch, dayKey: 20261001)
        spaces.proteinText = "  "
        #expect(!EntryEditView.startsWithNutritionShown(spaces))

        // 识别结果里的米饭：三大营养素都有
        let rice = EditableItem(
            FoodItem(name: "米饭", weightG: 150, caloriesKcal: 174, proteinG: 3.9, carbsG: 38.1, fatG: 0.5, confidence: .high),
            meal: .lunch, dayKey: 20261001)
        #expect(EntryEditView.startsWithNutritionShown(EntryDraft(item: rice)))
    }
}
