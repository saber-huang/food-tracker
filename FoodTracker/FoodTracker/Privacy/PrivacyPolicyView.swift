//
//  PrivacyPolicyView.swift
//  FoodTracker
//
//  隐私政策页面。正文写在同一个文件夹里（打包进 App，不联网也能看）：
//  中文 PrivacyPolicy.md，英文 PrivacyPolicy.en.md，按 App 的语言显示其中一份。
//  网页版也用同样的两份文件生成（site/build_site.py），两边的内容保证一样。
//  改正文时两份一起改，改完记得更新里面的「最后更新」日期。
//

import SwiftUI

nonisolated enum PrivacyPolicy {
    /// 正文里的占位符，显示时换成 SupportInfo 里的联系方式
    static let contactPlaceholder = "{{contact}}"

    /// 某种语言的正文文件名（不含 .md）
    static func fileName(for language: AppLanguage) -> String {
        language == .zh ? "PrivacyPolicy" : "PrivacyPolicy.en"
    }

    /// 读出打包在 App 里的正文；读不到时是 nil
    static func markdown(bundle: Bundle = .main, language: AppLanguage = .current) -> String? {
        guard let url = bundle.url(forResource: fileName(for: language), withExtension: "md") else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    /// 拆好块、填好联系方式的正文
    static func blocks(
        bundle: Bundle = .main, language: AppLanguage = .current, contact: String = SupportInfo.contactLine
    ) -> [MarkdownBlock] {
        let text = markdown(bundle: bundle, language: language) ?? String(localized: "隐私政策暂时读不出来，请更新 App 后再试。")
        return MarkdownBlocks.parse(text.replacingOccurrences(of: contactPlaceholder, with: contact))
    }
}

struct PrivacyPolicyView: View {
    /// 正文的第一块是大标题「隐私政策」，和顶栏重复，App 里不显示（网页版仍然有）
    private let blocks = PrivacyPolicy.blocks().filter {
        if case .title = $0 { false } else { true }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                    blockView(block)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("隐私政策")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func blockView(_ block: MarkdownBlock) -> some View {
        switch block {
        case .title(let text):
            Text(Self.inline(text))
                .font(.title2.bold())
                .accessibilityAddTraits(.isHeader)
        case .heading(let text):
            Text(Self.inline(text))
                .font(.headline)
                .padding(.top, 8)
                .accessibilityAddTraits(.isHeader)
        case .paragraph(let text):
            Text(Self.inline(text))
        case .bullet(let text):
            // 圆点和文字按第一行对齐；文字换行时不会绕到圆点下面
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("•")
                    .accessibilityHidden(true)
                Text(Self.inline(text))
            }
        }
    }

    /// 处理一块里面的加粗和链接；链接可以点，会在浏览器里打开
    private static func inline(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }
}

#Preview {
    NavigationStack {
        PrivacyPolicyView()
    }
}
