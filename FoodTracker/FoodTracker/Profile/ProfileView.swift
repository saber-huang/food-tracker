//
//  ProfileView.swift
//  FoodTracker
//
//  「我的」页面，从上到下：
//  0. 页面标题「我的」和一句说明（左对齐，和「食谱」一样）
//  1. 每日目标（主卡片，见 GoalHeroCard），下面一个小链接「这些目标是如何计算的？」
//  2. 个人资料（性别、年龄、身高、体重），标题右边是「编辑」
//  3. 目标与活动（活动量、目标）
//  4. 设置（单位、热量提示）、隐私与 AI（隐私政策、AI 功能、删除所有数据）、关于（意见反馈、健康提示、版本号）
//  每一组是一张卡片，不是一整页的设置列表。这一页只显示当前的值，不放说明文字：
//  需要解释的设置点进二级页面再说（见 SettingsPages.swift），健康提示点开是一张说明卡片。
//

import SwiftData
import SwiftUI

struct ProfileView: View {
    let profile: UserProfile
    /// 用户确认「删除所有数据」后调用：由最外层的 RootView 先离开主界面再删（见 RootView.swift）
    let onEraseAll: () -> Void

    @State private var isEditing = false
    @State private var showsExplanation = false  // 是否打开「这些目标是如何计算的？」
    @State private var confirmErase = false  // 是否弹出「确定删除所有数据？」的确认
    @State private var showsHealthInfo = false  // 是否打开「健康提示」说明卡片
    // 同意过第几版 AI 数据说明（0 = 没同意或撤回了）；在别的页面点了同意，这里也会马上变
    @AppStorage(AIConsent.key) private var aiConsentVersion = 0
    // 热量提示的设置，存在手机本地（UserDefaults）；默认全部开启
    @AppStorage(HintKeys.level) private var hintLevel: HintLevel = .all
    // 身高、体重用哪种单位显示和填写；没选过时按手机的地区（美国用英制）
    @AppStorage(UnitSystem.key) private var units: UnitSystem = UnitSystem.regionDefault()

    var body: some View {
        let bodyInfo = profile.bodyInfo
        let targets = profile.targets

        NavigationStack {
            List {
                // 页面标题：左对齐的「我的」+ 一句说明（和「食谱」页一样）
                Section {
                    PageHeader(title: String(localized: "我的"), subtitle: String(localized: "管理你的目标与个人信息"))
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }

                // 1. 每日目标：这一页的主卡片；紧贴在下面的是一个小链接，不是一行列表
                Section {
                    VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                        GoalHeroCard(targets: targets, bodyInfo: bodyInfo)
                        Button {
                            showsExplanation = true
                        } label: {
                            Label("这些目标是如何计算的？", systemImage: "info.circle")
                                .font(AppTypography.detail.weight(.medium))
                                .foregroundStyle(AppColors.brand)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)  // 字号很大时换行，不截断
                                .frame(minHeight: 44)
                                .padding(.horizontal, AppSpacing.xxs)
                                .contentShape(Rectangle())
                        }
                        // 只有点到这个链接才打开（不是整行都能点）
                        .buttonStyle(.borderless)
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }

                Group {
                    // 2. 个人资料
                    Section {
                        ProfileInfoRow(label: "性别", value: bodyInfo.sex.title)
                        ProfileInfoRow(label: "年龄", value: String(localized: "\(bodyInfo.age) 岁"))
                        ProfileInfoRow(label: "身高", value: BodyUnits.heightDisplay(cm: bodyInfo.heightCm, units: units))
                        ProfileInfoRow(label: "体重", value: BodyUnits.weightDisplay(kg: bodyInfo.weightKg, units: units))
                    } header: {
                        AppSectionHeaderWithAction(title: String(localized: "个人资料"), actionTitle: String(localized: "编辑")) {
                            isEditing = true
                        }
                    }

                    // 3. 目标与活动：两块并排，名称在上、值在下（不是一行一行的设置）
                    Section {
                        HStack(alignment: .top, spacing: AppSpacing.md) {
                            ProfileValueTile(label: "活动量", value: bodyInfo.activity.title)
                            ProfileValueTile(label: "目标", value: bodyInfo.goal.title)
                        }
                        .padding(.vertical, AppSpacing.xs)
                    } header: {
                        AppSectionHeader(title: String(localized: "目标与活动"))
                    }

                    // 4. 设置：单位；热量提示（点进去再选，说明文字都在那一页里）
                    Section {
                        Picker("单位", selection: $units) {
                            ForEach(UnitSystem.allCases, id: \.self) { system in
                                Text(system.title).tag(system)
                            }
                        }
                        NavigationLink {
                            HintSettingsView()
                        } label: {
                            LabeledContent(HintCopy.settingsHeader, value: HintCopy.levelTitle(hintLevel))
                        }
                    } header: {
                        AppSectionHeader(title: String(localized: "设置"))
                    }

                    // 5. 隐私与 AI：隐私政策、AI 功能（开关和撤回都在下一页）、删除所有数据
                    Section {
                        NavigationLink("隐私政策") {
                            PrivacyPolicyView()
                        }
                        NavigationLink {
                            AISettingsView()
                        } label: {
                            LabeledContent(
                                "AI 功能",
                                value: AIConsent.isGranted(version: aiConsentVersion)
                                    ? String(localized: "已开启") : String(localized: "未开启"))
                        }
                        Button(role: .destructive) {
                            confirmErase = true
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("删除所有数据")
                                Text("删除后无法恢复")
                                    .font(AppTypography.detail)
                                    .foregroundStyle(AppColors.textSecondary)
                            }
                            .padding(.vertical, AppSpacing.xxs)
                        }
                        .foregroundStyle(AppColors.destructive)
                    } header: {
                        AppSectionHeader(title: String(localized: "隐私与 AI"))
                    }

                    // 6. 关于：意见反馈、健康提示（点开是一张说明卡片）、版本号
                    Section {
                        // 联系邮箱还没定时不显示（见 SupportInfo.swift）
                        if let feedbackURL = SupportInfo.feedbackURL {
                            Link("意见反馈", destination: feedbackURL)
                        }
                        Button {
                            showsHealthInfo = true
                        } label: {
                            LabeledContent("健康提示") {
                                Image(systemName: "info.circle")
                                    .foregroundStyle(AppColors.textSecondary)
                            }
                            .foregroundStyle(AppColors.textPrimary)
                        }
                        LabeledContent("版本", value: SupportInfo.versionText)
                    } header: {
                        AppSectionHeader(title: String(localized: "关于"))
                    }

                    #if DEBUG && targetEnvironment(simulator)
                    // 只在模拟器里出现的开发者工具：一键造出各种热量提示
                    DebugHintSection(profile: profile)
                    #endif
                }
                .appCardRow()  // 卡片用暖白，分隔线很淡
            }
            .listStyle(.insetGrouped)
            .listSectionSpacing(AppSpacing.cardGap)
            .contentMargins(.horizontal, AppSpacing.pageMargin, for: .scrollContent)
            .contentMargins(.top, 0, for: .scrollContent)
            .environment(\.defaultMinListRowHeight, 56)  // 每一行至少 56pt 高，不像密密的设置列表
            .appListBackground()  // 页面用 App 的暖色背景（和「今日」页一样）
            .appStatusBarCover()  // 没有导航栏：状态栏那一条盖上背景色
            .navigationTitle("我的")  // 只用在下一页的「返回」上
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(isPresented: $showsExplanation) {
                ExplanationView(bodyInfo: profile.bodyInfo)
            }
            .sheet(isPresented: $isEditing) {
                ProfileEditView(profile: profile)
            }
            .sheet(isPresented: $showsHealthInfo) {
                InfoSheet(topic: .health)
            }
            // 删除前再确认一次：删掉就找不回来了。用居中的提示框，「取消」「删除」两个按钮都看得见
            .alert("确定删除所有数据？", isPresented: $confirmErase) {
                Button("取消", role: .cancel) {}
                Button("删除", role: .destructive) { onEraseAll() }
            } message: {
                Text("会删除这台手机上的个人资料、全部饮食记录、我的食物和设置。此操作无法撤销。")
            }
        }
    }
}

/// 编辑资料：改完点「保存」，每日目标会自动重新计算
struct ProfileEditView: View {
    let profile: UserProfile

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var draft: ProfileDraft
    @State private var savedTick = 0  // 保存时加 1：轻轻震一下

    init(profile: UserProfile) {
        self.profile = profile
        // 用原来的资料生成一份草稿；不点保存的话，原来的资料不会变
        _draft = State(initialValue: ProfileDraft(from: profile.bodyInfo, units: UnitSystem.current()))
    }

    var body: some View {
        AppForm {
            BasicInfoSection(draft: draft)
            ActivitySection(draft: draft)
            GoalSection(draft: draft)

            // 边改边预览新的目标
            if let bodyInfo = draft.bodyInfo {
                let targets = NutritionCalculator.targets(for: bodyInfo)
                AppFormSection(String(localized: "保存后的每日目标")) {
                    VStack(alignment: .leading, spacing: AppSpacing.sm) {
                        TargetsSummaryView(targets: targets)
                        FloorNotice(targets: targets)
                    }
                    .padding(AppSpacing.cardPadding)
                }
            }
        }
        .appSheetHeader(
            AppSheetHeader(
                title: String(localized: "编辑资料"), onCancel: { dismiss() }, confirmTitle: String(localized: "保存"),
                confirmEnabled: draft.bodyInfo != nil,  // 有填错的地方就不能保存
                onConfirm: save))
        .sensoryFeedback(.success, trigger: savedTick)
        .appSheet()
    }

    private func save() {
        guard let bodyInfo = draft.bodyInfo else { return }
        profile.update(with: bodyInfo)
        try? modelContext.save()
        savedTick += 1
        dismiss()
    }
}
