//
//  AIConsentSheet.swift
//  FoodTracker
//
//  「使用 AI 功能前」的说明：会发送什么、不会发送什么、发给谁、怎么处理、怎么撤回。
//  第一次用 AI 功能时弹出（带「同意并继续」「暂不使用」两个按钮）；「我的」>「AI 功能」里也能随时打开看（不带按钮）。
//  这里的说法要和 PrivacyPolicy.md 保持一致；发送的内容有变化时，两边一起改，并把 AIConsent.currentVersion 加 1。
//

import SwiftUI

/// 第一次用 AI 功能时弹出。onDecision(true) = 同意并继续，false = 暂不使用
struct AIConsentSheet: View {
    let onDecision: (Bool) -> Void
    /// 以前同意过旧版说明：顶部先说一句改了什么
    private let isUpdate = AIConsent.isUpdate(version: UserDefaults.standard.integer(forKey: AIConsent.key))

    var body: some View {
        NavigationStack {
            AppForm {
                if isUpdate { updateNote }
                AIDataDisclosure()
                PrivacyPolicyLinkSection()
            }
            .toolbar(.hidden, for: .navigationBar)
            .appSheetHeader(AppSheetHeader(title: String(localized: "使用 AI 功能前")))
            // 两个按钮固定在底部，说明再长也不会被挤出屏幕
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: AppSpacing.xxs) {
                    Button("同意并继续") { onDecision(true) }
                        .buttonStyle(.appPrimary)
                    Button("暂不使用") { onDecision(false) }
                        .buttonStyle(.appTertiary)
                }
                .padding(.horizontal, AppSpacing.pageMargin)
                .padding(.top, AppSpacing.xs)
                .appBottomBar()
            }
        }
        .appSheet()
    }

    /// 「说明有更新」：这一版多了什么（第 2 版：AI 估算食物）
    private var updateNote: some View {
        HStack(alignment: .firstTextBaseline, spacing: AppSpacing.sm) {
            Image(systemName: "sparkles")
                .foregroundStyle(AppColors.brand)
                .accessibilityHidden(true)
            Text("说明有更新：新增了「AI 估算食物」，只会发送你输入的食物名称。其他内容和之前一样，确认后就能继续使用。")
                .foregroundStyle(AppColors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(AppSpacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.brandSoft, in: RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
    }
}

/// 「我的」>「AI 功能」>「关于 AI 数据处理」打开的同一份说明（只看，不带按钮）
struct AIDataInfoView: View {
    var body: some View {
        AppForm {
            AIDataDisclosure()
            PrivacyPolicyLinkSection()
        }
        .navigationTitle("关于 AI 数据处理")
        .navigationBarTitleDisplayMode(.inline)
        .hidesFloatingTabBar()  // 二级页面：底部标签栏收起来
    }
}

/// 「查看完整的隐私政策」一行
private struct PrivacyPolicyLinkSection: View {
    var body: some View {
        AppFormSection(nil) {
            NavigationLink {
                PrivacyPolicyView()
            } label: {
                AppFormLinkLabel(title: String(localized: "查看完整的隐私政策"))
            }
            .buttonStyle(AppPressStyle(scales: false))
        }
    }
}

/// 说明的正文，两个页面共用（放在 AppForm 里：一段开头的话，后面几块）
struct AIDataDisclosure: View {
    var body: some View {
        Text("拍照识别、AI 估算食物、生成食谱和推荐下一餐，是由 Anthropic 公司的 Claude AI 完成的。使用前，请先看看会发送哪些内容。")
            .font(.callout)
            .foregroundStyle(AppColors.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, AppSpacing.xxs)

        AppFormSection(String(localized: "会发送什么")) {
            item("photo", "拍照识别：你选的餐食照片（同一餐最多 4 张）。上传前会缩小并重新压缩，不带拍摄地点等信息。")
            AppFormDivider()
            item("fork.knife", "生成食谱和推荐下一餐：你的目标（减脂、维持或增肌），热量和三大营养素目标，以及你填写的口味偏好、过敏、不吃的食物和做饭时间。")
            AppFormDivider()
            item("text.magnifyingglass", "AI 估算食物：你输入、但食物库里没有的那个食物名称（比如「山西过油肉」），只发这个名称。")
        }

        AppFormSection(String(localized: "不会发送什么")) {
            item("hand.raised", "年龄、身高、体重和饮食记录本身；也没有姓名、电话、位置这类身份信息。")
        }

        AppFormSection(String(localized: "发给谁、怎么处理")) {
            item("arrow.up.arrow.down", "先发到本 App 的服务器，再由服务器转交给 Anthropic。结果只发回你的手机。")
            AppFormDivider()
            item("externaldrive.badge.xmark", "本 App 的服务器不保存照片和你填写的内容。为了更快返回，同样的食谱和食物估算结果会在服务器内存里暂存一段时间，不和你的设备关联。")
            AppFormDivider()
            item("building.2", "Anthropic 按商业服务条款处理：默认不用来训练模型，一般在 30 天内删除。")
            AppFormDivider()
            item("number", "为了防止滥用，服务器会按随机的设备编号和网络地址统计每天的使用次数，大约一天后自动清除。")
        }

        AppFormSection(String(localized: "随时可以改变主意")) {
            item("arrow.uturn.backward", "在「我的」>「AI 功能」里可以随时关掉。不同意也能照常手动记录饮食。")
        }
    }

    /// 一条说明：左边一个描边小图标，右边一段话（text 是可翻译的文字，写在调用处的中文会自动进入翻译）
    private func item(_ systemImage: String, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: AppSpacing.sm) {
            Image(systemName: systemImage)
                .foregroundStyle(AppColors.brand)
                .frame(width: 22)
                .accessibilityHidden(true)
            Text(text)
                .foregroundStyle(AppColors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, AppSpacing.cardPadding)
        .padding(.vertical, AppSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview("第一次使用时") {
    AIConsentSheet { _ in }
}

#Preview("我的页里") {
    NavigationStack {
        AIDataInfoView()
    }
}
