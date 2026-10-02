//
//  NutritionLabelScanner.swift
//  FoodTracker
//
//  拍营养成分表，自动填写：用 iPhone 自带的文字识别（Vision），在手机上认出照片里的字，不联网、不花钱、照片不上传。
//  认出来的字先按行拼好（同一行左右几段连起来），再从里面找：
//  - 表上按什么写：每 100 克 / 每 100 毫升 / 每份（30 克）；美国的包装是 Serving size
//  - 能量（千焦 / 千卡；美国的 Calories）、蛋白质、脂肪、碳水化合物（跳过饱和脂肪、反式脂肪这些子项）
//  - 净含量（照片里拍到的话）
//  找的是「名称后面紧跟着的数字」：不会把 NRV% 那一列的「11%」、钠的「300 毫克」当成克数。
//  认出来的只是帮用户填好，界面上请用户和包装核对，不会自动保存
//

import Foundation
import ImageIO
import UIKit
import Vision

/// 认出来的一段文字和它在照片里的位置（像素，原点在左下角，和 Vision 一样；已经摆正）
nonisolated struct RecognizedText: Sendable {
    let text: String
    let minX: Double
    let midY: Double
    let height: Double
}

/// Vision 认出来的一段文字和它的四个角（像素，原点在左下角）。照片拍斜了，四个角也是斜的
nonisolated struct RawTextBox: Sendable {
    let text: String
    let topLeft: CGPoint
    let topRight: CGPoint
    let bottomLeft: CGPoint
    let bottomRight: CGPoint
}

/// 从照片里认出来的营养成分表（没认出来的是 nil）
nonisolated struct LabelScanResult: Equatable, Sendable {
    var column: LabelColumn?
    var servingSize: Double?
    var servingUnit: AmountUnit?
    var energy: Double?
    var energyUnit: EnergyUnit?
    var protein: Double?
    var fat: Double?
    var carbs: Double?
    var packageAmount: Double?

    /// 认出了几项营养数字（能量、蛋白质、脂肪、碳水化合物）
    var nutrientCount: Int { [energy, protein, fat, carbs].compactMap { $0 }.count }
    var isEmpty: Bool { nutrientCount == 0 }
}

// MARK: - 把认出来的字整理成营养成分表

nonisolated enum NutritionLabelParser {
    /// 数字：「6.5」「2010」
    private static let number = #"(\d+(?:\.\d+)?)"#

    /// 照片拍斜了：试 -10°～10° 的几个角度，选「拼出来的行最少、每行最齐」的那个把位置转正。
    /// 不用每段文字自己的角度：Vision 给短文字的框常常是正的，看不出照片斜了，
    /// 结果左边的「能量」和右边（更高）的「2010千焦」「24%」会被拆成两行
    static func straightened(_ boxes: [RawTextBox]) -> [RecognizedText] {
        guard !boxes.isEmpty else { return [] }
        // 角度从 0 往两边试：一样好时选转得少的
        let angles = (0...40).flatMap { step -> [Double] in
            let degrees = Double(step) * 0.25
            return step == 0 ? [0] : [degrees, -degrees]
        }
        var best: (rows: Int, spread: Double, items: [RecognizedText])?
        for degrees in angles {
            let items = boxes.map { place($0, turnedBy: degrees * .pi / 180) }
            let rows = groupRows(items)
            let spread = rows.reduce(0) { total, row in
                let mean = row.map(\.midY).reduce(0, +) / Double(row.count)
                return total + row.reduce(0) { $0 + abs($1.midY - mean) }
            }
            if let current = best, rows.count > current.rows || (rows.count == current.rows && spread >= current.spread) {
                continue
            }
            best = (rows.count, spread, items)
        }
        return best?.items ?? []
    }

    /// 把一段文字的四个角转一个角度，算出它转正以后的位置
    private static func place(_ box: RawTextBox, turnedBy turn: Double) -> RecognizedText {
        func rotate(_ point: CGPoint) -> CGPoint {
            CGPoint(x: point.x * cos(turn) - point.y * sin(turn), y: point.x * sin(turn) + point.y * cos(turn))
        }
        let corners = [box.topLeft, box.topRight, box.bottomLeft, box.bottomRight].map(rotate)
        let top = (corners[0].y + corners[1].y) / 2
        let bottom = (corners[2].y + corners[3].y) / 2
        return RecognizedText(
            text: box.text, minX: Double(corners.map(\.x).min() ?? 0), midY: Double((top + bottom) / 2),
            height: Double(max(top - bottom, 1)))
    }

    /// 一段一段的文字分成行：从上往下，和这一行的平均高度差不到大半个字高的算同一行
    static func groupRows(_ items: [RecognizedText]) -> [[RecognizedText]] {
        guard !items.isEmpty else { return [] }
        let heights = items.map(\.height).sorted()
        let tolerance = heights[heights.count / 2] * 0.6
        var rows: [[RecognizedText]] = []
        var means: [Double] = []
        for item in items.sorted(by: { $0.midY > $1.midY }) {
            if let mean = means.last, abs(mean - item.midY) <= tolerance {
                rows[rows.count - 1].append(item)
                means[means.count - 1] = rows[rows.count - 1].map(\.midY).reduce(0, +) / Double(rows[rows.count - 1].count)
            } else {
                rows.append([item])
                means.append(item.midY)
            }
        }
        return rows
    }

    /// 拼成一行一行的文字：同一行从左到右连起来，行从上到下排
    static func rows(_ items: [RecognizedText]) -> [String] {
        groupRows(items).map { $0.sorted { $0.minX < $1.minX }.map(\.text).joined(separator: " ") }
    }

    /// 从上往下找，每一项用最先找到的（子项「饱和脂肪」「糖」在主项下面，不会抢先）
    static func parse(rows: [String]) -> LabelScanResult {
        var result = LabelScanResult()
        for line in rows.map(normalize) {
            if result.column == nil { readColumn(line, into: &result) }
            if result.energy == nil, let (value, unit) = energy(in: line) {
                result.energy = value
                result.energyUnit = unit
            }
            if result.protein == nil { result.protein = grams(after: ["蛋白质", "protein"], in: line) }
            if result.fat == nil {
                // 跳过「饱和脂肪」「反式脂肪」，和美国旧包装上的「Calories from Fat 70」
                result.fat = grams(after: ["脂肪", "fat"], in: line, skippingAfter: ["饱和", "反式", "saturated", "trans", "from"])
            }
            if result.carbs == nil {
                result.carbs = grams(after: ["碳水化合物", "碳水", "carbohydrate", "carbs"], in: line)
            }
            if result.packageAmount == nil { result.packageAmount = netContents(in: line) }
        }
        return result
    }

    // MARK: - 整理文字

    /// 全角换半角（「１００ｇ」→「100g」）、小写；「2,010」去掉千位的逗号，「6,5 g」的逗号当小数点
    static func normalize(_ line: String) -> String {
        var text = line.precomposedStringWithCompatibilityMapping.lowercased()
        text = replacing(#"(\d),(\d{3})(?!\d)"#, in: text, with: "$1$2")
        text = replacing(#"(\d),(\d{1,2})\s*(g|克)"#, in: text, with: "$1.$2$3")
        return text
    }

    private static func replacing(_ pattern: String, in text: String, with template: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        return regex.stringByReplacingMatches(
            in: text, range: NSRange(text.startIndex..., in: text), withTemplate: template)
    }

    /// 正则的所有匹配：每个匹配是（整段的开始位置，各个括号里的内容）
    private static func matches(_ pattern: String, in text: String) -> [(start: String.Index, groups: [String?])] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
            guard let whole = Range(match.range, in: text) else { return nil }
            let groups = (1..<match.numberOfRanges).map { index -> String? in
                Range(match.range(at: index), in: text).map { String(text[$0]) }
            }
            return (whole.lowerBound, groups)
        }
    }

    // MARK: - 找各项

    /// 表上按什么写：同一行里先出现的那一列（两列的表，第一个数字属于先出现的那一列）
    private static func readColumn(_ line: String, into result: inout LabelScanResult) {
        let per100g = matches(#"每\s*100\s*(?:克|g(?![a-z]))|per\s*100\s*g(?![a-z])"#, in: line).first?.start
        let per100ml = matches(#"每\s*100\s*(?:毫升|ml)|per\s*100\s*ml"#, in: line).first?.start
        let perServing = matches(#"每\s*份|serving\s*size|per\s*serving"#, in: line).first?.start
        let found = [(LabelColumn.per100g, per100g), (.per100ml, per100ml), (.perServing, perServing)]
            .compactMap { column, start in start.map { (column, $0) } }
            .min { $0.1 < $1.1 }
        guard let column = found?.0 else { return }
        result.column = column
        guard column == .perServing else { return }
        // 每份多少：「每份(30克)」；美国的「Serving size 1 cup (240mL)」取最后一个克 / 毫升数
        let sizes = matches(number + #"\s*(克|g(?![a-z])|毫升|ml)"#, in: line)
        if let size = (line.contains("每") ? sizes.first : sizes.last), let value = size.groups[0].flatMap(Double.init) {
            result.servingSize = value
            let unit = size.groups[1] ?? ""
            result.servingUnit = unit == "毫升" || unit == "ml" ? .milliliter : .gram
        }
    }

    /// 能量：「能量 2010千焦」「能量 2010 kJ」「Calories 230」；没写单位的「能量」按千焦（中国的营养成分表），Calories 按千卡
    private static func energy(in line: String) -> (Double, EnergyUnit)? {
        let pattern = #"(能量|热量|energy|卡路里|calories)[^\d%]{0,12}?"# + number + #"\s*(千焦|kj|千卡|kcal|大卡)?"#
        guard let match = matches(pattern, in: line).first,
            let keyword = match.groups[0], let value = match.groups[1].flatMap(Double.init)
        else { return nil }
        switch match.groups[2] {
        case "千焦", "kj": return (value, .kilojoule)
        case "千卡", "kcal", "大卡": return (value, .kilocalorie)
        default: return (value, keyword == "calories" || keyword == "热量" ? .kilocalorie : .kilojoule)
        }
    }

    /// 名称后面紧跟的克数：「蛋白质 6.5克」「Protein 3g」「脂肪(g) 20.0」。
    /// skippingAfter：名称前面紧挨着这些字的不算（「饱和脂肪」「Saturated Fat」）
    private static func grams(after keywords: [String], in line: String, skippingAfter skipped: [String] = []) -> Double? {
        let pattern = "(?:" + keywords.joined(separator: "|") + #")[^\d%]{0,12}?"# + number + #"\s*(毫克|mg|克|g(?![a-z]))?"#
        for match in matches(pattern, in: line) {
            let before = line[..<match.start].suffix(10)
            if skipped.contains(where: { before.contains($0) }) { continue }
            if let unit = match.groups[1], unit == "毫克" || unit == "mg" { continue }  // 毫克是钠、胆固醇这类，不是这一项
            return match.groups[0].flatMap(Double.init)
        }
        return nil
    }

    /// 净含量：「净含量：100克」「Net Wt 1.5 kg」「净含量 1L」，换算成克（毫升）
    private static func netContents(in line: String) -> Double? {
        let pattern = #"(?:净含量|净重|net\s*wt|net\s*weight|net\s*contents?)[^\d]{0,8}"# + number
            + #"\s*(千克|kg|克|g(?![a-z])|毫升|ml|升|l(?![a-z]))"#
        guard let match = matches(pattern, in: line).first, let value = match.groups[0].flatMap(Double.init) else {
            return nil
        }
        let unit = match.groups[1] ?? ""
        return ["千克", "kg", "升", "l"].contains(unit) ? value * 1000 : value
    }
}

// MARK: - 文字识别（Vision，在手机上跑）

nonisolated enum LabelTextRecognizer {
    /// 认出照片里的字（中文和英文），按行拼好。在后台跑，不卡界面
    static func recognizeRows(_ image: UIImage) async throws -> [String] {
        guard let cgImage = image.cgImage else { return [] }
        let orientation = CGImagePropertyOrientation(image.imageOrientation)
        // Vision 给的位置是 0～1，按转正以后的照片算：横着拍的照片宽高要对调，换回像素才能算对角度
        let sideways = [.left, .right, .leftMirrored, .rightMirrored].contains(orientation)
        let width = Double(sideways ? cgImage.height : cgImage.width)
        let height = Double(sideways ? cgImage.width : cgImage.height)
        return try await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["zh-Hans", "en-US"]
            request.usesLanguageCorrection = true
            try VNImageRequestHandler(cgImage: cgImage, orientation: orientation).perform([request])
            let boxes = (request.results ?? []).compactMap { observation -> RawTextBox? in
                guard let text = observation.topCandidates(1).first?.string else { return nil }
                func pixels(_ point: CGPoint) -> CGPoint { CGPoint(x: point.x * width, y: point.y * height) }
                return RawTextBox(
                    text: text, topLeft: pixels(observation.topLeft), topRight: pixels(observation.topRight),
                    bottomLeft: pixels(observation.bottomLeft), bottomRight: pixels(observation.bottomRight))
            }
            return NutritionLabelParser.rows(NutritionLabelParser.straightened(boxes))
        }.value
    }
}

nonisolated extension CGImagePropertyOrientation {
    /// 照片的方向（拍照时手机横着拿也能认）
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up: self = .up
        case .upMirrored: self = .upMirrored
        case .down: self = .down
        case .downMirrored: self = .downMirrored
        case .left: self = .left
        case .leftMirrored: self = .leftMirrored
        case .right: self = .right
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}
