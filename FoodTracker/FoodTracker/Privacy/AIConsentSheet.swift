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

    var body: some View {
        NavigationStack {
            List {
                Group {
                    AIDataDisclosure()
                    Section {
                        NavigationLink("查看完整的隐私政策") {
                            PrivacyPolicyView()
                        }
                    }
                }
                .appCardRow()  // 卡片用暖白，和 App 其他页面一样
            }
            .appListBackground()
            .navigationTitle("使用 AI 功能前")
            .navigationBarTitleDisplayMode(.inline)
            // 两个按钮固定在底部，说明再长也不会被挤出屏幕
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 8) {
                    Button {
                        onDecision(true)
                    } label: {
                        Text("同意并继续")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    Button {
                        onDecision(false)
                    } label: {
                        Text("暂不使用")
                            .frame(maxWidth: .infinity)
                    }
                    .controlSize(.large)
                }
                .padding()
                .appBottomBar()  // 和页面同样的暖色，上边缘淡出
            }
        }
    }
}

/// 「我的」>「AI 功能」>「关于 AI 数据处理」打开的同一份说明（只看，不带按钮）
struct AIDataInfoView: View {
    var body: some View {
        List {
            Group {
                AIDataDisclosure()
                Section {
                    NavigationLink("查看完整的隐私政策") {
                        PrivacyPolicyView()
                    }
                }
            }
            .appCardRow()  // 卡片用暖白，和 App 其他页面一样
        }
        .appListBackground()
        .navigationTitle("关于 AI 数据处理")
        .navigationBarTitleDisplayMode(.inline)
        .hidesFloatingTabBar()  // 二级页面：底部标签栏收起来
    }
}

/// 说明的正文，两个页面共用
struct AIDataDisclosure: View {
    var body: some View {
        Section {
            Text("拍照识别、生成食谱和推荐下一餐，是由 Anthropic 公司的 Claude AI 完成的。第一次使用前，请先看看会发送哪些内容。")
        }

        Section("会发送什么") {
            item("photo", "拍照识别：你选的餐食照片（同一餐最多 4 张）。上传前会缩小并重新压缩，不带拍摄地点等信息。")
            item("fork.knife", "生成食谱和推荐下一餐：你的目标（减脂、维持或增肌），热量和三大营养素目标，以及你填写的口味偏好、过敏、不吃的食物和做饭时间。")
        }

        Section("不会发送什么") {
            item("hand.raised", "年龄、身高、体重和饮食记录本身；也没有姓名、电话、位置这类身份信息。")
        }

        Section("发给谁、怎么处理") {
            item("arrow.up.arrow.down", "先发到本 App 的服务器，再由服务器转交给 Anthropic。结果只发回你的手机。")
            item("externaldrive.badge.xmark", "本 App 的服务器不保存照片和你填写的内容。")
            item("building.2", "Anthropic 按商业服务条款处理：默认不用来训练模型，一般在 30 天内删除。")
            item("number", "为了防止滥用，服务器会按随机的设备编号和网络地址统计每天的使用次数，大约一天后自动清除。")
        }

        Section("随时可以改变主意") {
            item("arrow.uturn.backward", "在「我的」>「AI 功能」里可以随时关掉。不同意也能照常手动记录饮食。")
        }
    }

    /// 一条说明：左边一个图标，右边一段话（text 是可翻译的文字，写在调用处的中文会自动进入翻译）
    private func item(_ systemImage: String, _ text: LocalizedStringKey) -> some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(.tint)
        }
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
