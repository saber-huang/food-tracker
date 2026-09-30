//
//  PrivacyPolicyView.swift
//  FoodTracker
//
//  隐私政策页面。正文写在同一个文件夹的 PrivacyPolicy.md 里（打包进 App，不联网也能看）；
//  以后放到网上时，直接用同一份文件，两边的内容保证一样。
//  改正文只改 PrivacyPolicy.md，改完记得更新里面的「最后更新」日期。
//

import SwiftUI

nonisolated enum PrivacyPolicy {
    /// 正文里的占位符，显示时换成 SupportInfo 里的联系方式
    static let contactPlaceholder = "{{contact}}"

    /// 读出打包在 App 里的 PrivacyPolicy.md；读不到时是 nil
    static func markdown(bundle: Bundle = .main) -> String? {
        guard let url = bundle.url(forResource: "PrivacyPolicy", withExtension: "md") else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    /// 拆好块、填好联系方式的正文
    static func blocks(bundle: Bundle = .main, contact: String = SupportInfo.contactLine) -> [MarkdownBlock] {
        let text = markdown(bundle: bundle) ?? "隐私政策暂时读不出来，请更新 App 后再试。"
        return MarkdownBlocks.parse(text.replacingOccurrences(of: contactPlaceholder, with: contact))
    }
}

struct PrivacyPolicyView: View {
    private let blocks = PrivacyPolicy.blocks()

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
