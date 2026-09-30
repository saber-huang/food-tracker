//
//  MarkdownBlocks.swift
//  FoodTracker
//
//  把一小段 Markdown 文字拆成一块一块（标题、段落、列表项），给隐私政策页面显示用。
//  只支持隐私政策里用到的几种写法：「# 」大标题、「## 」小标题、「- 」列表项、空行分段；
//  每一块里面的 **加粗** 和 [链接](网址) 交给系统的 AttributedString 处理。
//  只做文字处理，不涉及界面，可以单独写单元测试（FoodTrackerTests/PrivacyTests.swift）。
//

import Foundation

nonisolated enum MarkdownBlock: Equatable {
    case title(String)  // 「# 」开头：整页的大标题
    case heading(String)  // 「## 」开头：小标题
    case paragraph(String)  // 普通的一段话
    case bullet(String)  // 「- 」开头：列表里的一项
}

nonisolated enum MarkdownBlocks {
    static func parse(_ text: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var paragraphLines: [String] = []  // 还没结束的这一段（Markdown 里连续的几行算一段）

        func finishParagraph() {
            guard !paragraphLines.isEmpty else { return }
            blocks.append(.paragraph(paragraphLines.joined(separator: " ")))
            paragraphLines = []
        }

        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                finishParagraph()  // 空行 = 一段结束
            } else if line.hasPrefix("## ") {
                finishParagraph()
                blocks.append(.heading(String(line.dropFirst(3))))
            } else if line.hasPrefix("# ") {
                finishParagraph()
                blocks.append(.title(String(line.dropFirst(2))))
            } else if line.hasPrefix("- ") {
                finishParagraph()
                blocks.append(.bullet(String(line.dropFirst(2))))
            } else {
                paragraphLines.append(line)
            }
        }
        finishParagraph()
        return blocks
    }
}
