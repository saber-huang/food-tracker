//
//  PrivacyTests.swift
//  FoodTrackerTests
//
//  隐私相关的测试：隐私政策能读出来、拆块正确；AI 功能的同意状态；没同意时不会直接发送。
//  用到 UserDefaults 的测试都用单独的一份（suiteName），不会改到模拟器里 App 的真实设置。
//

import Foundation
import SwiftUI
import Testing

@testable import FoodTracker

@Suite("Markdown 拆块")
struct MarkdownBlocksTests {
    @Test("标题、小标题、段落、列表项")
    func parse() {
        let text = """
            # 隐私政策

            第一段的第一行
            第一段的第二行

            ## 简单来说
            - 第一项
            - 第二项 **加粗**
            最后一段
            """
        #expect(
            MarkdownBlocks.parse(text) == [
                .title("隐私政策"),
                .paragraph("第一段的第一行 第一段的第二行"),
                .heading("简单来说"),
                .bullet("第一项"),
                .bullet("第二项 **加粗**"),
                .paragraph("最后一段"),
            ])
    }

    @Test("空文字没有任何块；行首行尾的空格不影响")
    func edgeCases() {
        #expect(MarkdownBlocks.parse("").isEmpty)
        #expect(MarkdownBlocks.parse("\n\n  \n").isEmpty)
        #expect(MarkdownBlocks.parse("  ## 标题  \n  - 一项 ") == [.heading("标题"), .bullet("一项")])
    }
}

@Suite("隐私政策")
struct PrivacyPolicyTests {
    @Test("打包进 App 的隐私政策能读出来，而且写到了关键的几点")
    func bundledPolicy() throws {
        // 测试跑在 App 里面，Bundle.main 就是 App 本身
        let text = try #require(PrivacyPolicy.markdown())
        for fact in ["Anthropic", "30 天", "不会用来训练模型", "删除所有数据", "撤回", "18 岁", "设备编号"] {
            #expect(text.contains(fact), "隐私政策里应该写到「\(fact)」")
        }
        // 第一块是大标题
        let blocks = PrivacyPolicy.blocks(contact: "test@example.com")
        #expect(blocks.first == .title("隐私政策"))
    }

    @Test("英文版隐私政策也在，而且和中文版写到同样的关键几点")
    func englishPolicy() throws {
        let text = try #require(PrivacyPolicy.markdown(language: .en))
        for fact in ["Anthropic", "30 days", "not used to train", "Delete All Data", "Withdraw", "18", "device ID"] {
            #expect(text.contains(fact), "英文隐私政策里应该写到「\(fact)」")
        }
        #expect(text.range(of: "\\p{Han}", options: .regularExpression) == nil, "英文隐私政策里不应该有中文")
        // 两种语言的小标题一样多，说明内容是对应的
        let zhHeadings = PrivacyPolicy.blocks(language: .zh, contact: "x").filter { if case .heading = $0 { true } else { false } }
        let enHeadings = PrivacyPolicy.blocks(language: .en, contact: "x").filter { if case .heading = $0 { true } else { false } }
        #expect(zhHeadings.count == enHeadings.count)
        #expect(PrivacyPolicy.blocks(language: .en, contact: "x").first == .title("Privacy Policy"))
    }

    @Test("联系方式的占位符会被换掉")
    func contactPlaceholder() {
        let blocks = PrivacyPolicy.blocks(contact: "test@example.com")
        let allText = blocks.map { "\($0)" }.joined()
        #expect(allText.contains("test@example.com"))
        #expect(!allText.contains("{{"))
        // 默认用 SupportInfo 里的联系邮箱
        let defaultText = PrivacyPolicy.blocks().map { "\($0)" }.joined()
        #expect(defaultText.contains(SupportInfo.contactLine))
    }

    @Test("意见反馈：打开写好收件人和标题的邮件")
    func feedbackMail() throws {
        // 没填邮箱时不显示「意见反馈」；填了就是一个 mailto 链接
        #expect(SupportInfo.contactEmail.isEmpty == (SupportInfo.feedbackURL == nil))
        guard !SupportInfo.contactEmail.isEmpty else { return }
        let url = try #require(SupportInfo.feedbackURL)
        #expect(url.scheme == "mailto")
        #expect(url.absoluteString.hasPrefix("mailto:\(SupportInfo.contactEmail)?subject="))
        // 标题里的中文和括号要先转码，链接才打得开；转回来就是原来的标题
        let subject = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first?.value)
        #expect(subject.hasPrefix("一拍即食 反馈"))
        #expect(subject.contains(SupportInfo.versionText))
    }
}

// PendingAIAction 和 Binding 只能在主线程使用
@MainActor
@Suite("AI 功能的同意")
struct AIConsentTests {
    let defaults: UserDefaults

    init() {
        // 每个测试一份全新的、单独的设置
        let name = "AIConsentTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
    }

    @Test("没同意过 → 同意 → 撤回")
    func grantAndRevoke() {
        #expect(!AIConsent.isGranted(in: defaults))
        AIConsent.grant(in: defaults)
        #expect(AIConsent.isGranted(in: defaults))
        AIConsent.revoke(in: defaults)
        #expect(!AIConsent.isGranted(in: defaults))
    }

    @Test("同意的是旧版说明时要重新问；新版或更新的都算同意")
    func versions() {
        #expect(!AIConsent.isGranted(version: 0))
        #expect(!AIConsent.isGranted(version: AIConsent.currentVersion - 1))
        #expect(AIConsent.isGranted(version: AIConsent.currentVersion))
        #expect(AIConsent.isGranted(version: AIConsent.currentVersion + 1))
    }

    @Test("没同意时先不做，记下来等说明弹出；同意过就马上做")
    func perform() throws {
        var pending: PendingAIAction?
        let binding = Binding(get: { pending }, set: { pending = $0 })
        var runs = 0

        // 没同意：不发送，等着弹出说明
        AIConsent.perform(pending: binding, defaults: defaults) { runs += 1 }
        #expect(runs == 0)
        let waiting = try #require(pending)

        // 用户点了「同意并继续」：记下的那件事才真正去做（aiConsentSheet 里就是这样做的）
        AIConsent.grant(in: defaults)
        waiting.run()
        #expect(runs == 1)

        // 以后再点：直接做，不再弹出说明
        pending = nil
        AIConsent.perform(pending: binding, defaults: defaults) { runs += 1 }
        #expect(runs == 2)
        #expect(pending == nil)
    }
}
