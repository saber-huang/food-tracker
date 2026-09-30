//
//  SupportInfo.swift
//  FoodTracker
//
//  联系方式和版本号：「我的」页的「关于」和隐私政策里的「联系我们」都从这里读。
//

import Foundation

nonisolated enum SupportInfo {
    /// 意见反馈和隐私问题的联系邮箱，会公开显示在 App 和隐私政策里。
    /// 还没定：空着时「我的」页不显示「意见反馈」，隐私政策里写「联系邮箱稍后公布」
    static let contactEmail = ""

    /// 隐私政策「联系我们」后面的那句
    static var contactLine: String {
        contactEmail.isEmpty ? "联系邮箱稍后公布。" : contactEmail
    }

    /// 点「意见反馈」时打开的邮件：收件人和标题已经填好。没有邮箱时是 nil
    static var feedbackURL: URL? {
        guard !contactEmail.isEmpty else { return nil }
        // 标题里有中文，要先转成网址能用的格式
        let subject = "饮食记录 App 反馈（\(versionText)）"
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return URL(string: "mailto:\(contactEmail)?subject=\(subject)")
    }

    /// 版本号，例如「1.0（1）」：前面是给用户看的版本，括号里是第几次构建
    static var versionText: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version)（\(build)）"
    }
}
