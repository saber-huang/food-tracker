//
//  OnboardingView.swift
//  FoodTracker
//
//  第一次打开 App 时的引导，一共 6 步：
//  欢迎 → 你的目标 → 基本信息 → 活动量 → 饮食偏好（可以跳过）→ 你的每日参考目标。
//  - 每一步只做一件事；顶部是返回箭头和一条细细的进度条，底部是同一个主按钮（「开始」「继续」「记录第一餐」）
//  - 填到一半退出 App，下次打开从那一步接着填，填过的都还在（见 OnboardingProgress.swift）
//  - 最后一步按填的资料算出每日热量和三大营养素（和「我的」页同一个公式）。
//    点「记录第一餐」保存资料、进主界面后直接打开「选择食物」；点「稍后再说」只保存资料
//  - 健康说明是最后一步的小字（不用勾选）；年龄只能填 18～80 岁（基本信息那一步检查）
//  - 先选了「减脂」、填完资料发现不适合减脂（体重偏轻，或 65 岁以上且 BMI 低于 30）：自动换成「维持」，结果页说明原因
//  - 换一步时 0.25 秒淡入、轻轻滑进来；系统开了「减弱动态效果」时只淡入淡出
//

import SwiftData
import SwiftUI
import UIKit

struct OnboardingView: View {
    /// 资料保存好以后调用。logFirstMeal：点的是「记录第一餐」（主界面出来后直接打开「选择食物」）
    let onFinish: (_ logFirstMeal: Bool) -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var draft: ProfileDraft
    @State private var step: OnboardingStep
    @State private var preferences: PreferenceChoices
    @State private var goalWasAdjusted: Bool
    /// 往后走还是往回走：决定新的一页从哪边滑进来
    @State private var movesForward = true
    /// 已经保存了资料：之后不再存进度
    @State private var isFinished = false
    /// 键盘出来时收起底部按钮：iOS 26 起数字键盘上方的「完成」浮在页面上，会挡住按钮的下半截
    @State private var isKeyboardVisible = false
    @State private var selectionTick = 0  // 选了一项：轻轻震一下

    init(onFinish: @escaping (_ logFirstMeal: Bool) -> Void = { _ in }) {
        self.onFinish = onFinish
        // 上次没填完的话，接着填
        let saved = OnboardingProgress.load()
        let units = UnitSystem.current()
        let draft = saved.map { ProfileDraft(snapshot: $0.profile, units: units) } ?? ProfileDraft(units: units)
        var goalWasAdjusted = saved?.goalWasAdjusted ?? false
        var step = OnboardingStep.welcome
        if let saved {
            step = OnboardingProgress.resumeStep(
                saved: saved.step, goalChosen: draft.goal != nil, basicInfoValid: draft.isBasicInfoValid,
                activityChosen: draft.activity != nil)
            if step.rawValue > OnboardingStep.basicInfo.rawValue && Self.adjustGoalIfNeeded(draft) {
                goalWasAdjusted = true
            }
        }
        _draft = State(initialValue: draft)
        _step = State(initialValue: step)
        _preferences = State(initialValue: saved?.preferences ?? PreferenceChoices())
        _goalWasAdjusted = State(initialValue: goalWasAdjusted)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if step != .welcome {
                    topBar
                }
                // 新的一步淡入、轻轻滑进来，旧的一步淡出（两步叠在一起换，不会上下挤）
                ZStack {
                    stepContent
                        .id(step)
                        .transition(stepTransition)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background { AppBackground(glow: step == .welcome) }
            .navigationTitle(String(localized: "每日参考目标"))  // 只用在「怎么算的」页的返回按钮上
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if !isKeyboardVisible {
                    bottomBar
                }
            }
            .sensoryFeedback(.selection, trigger: selectionTick)
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
                isKeyboardVisible = true
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                isKeyboardVisible = false
            }
            // 每改一点就存一次进度：随时退出都能接着填
            .onChange(of: progress) { _, newProgress in
                guard !isFinished else { return }
                newProgress.save()
            }
        }
    }

    // MARK: - 顶部、底部

    /// 顶部：返回箭头、进度条；偏好这一步右边有「跳过」（其他步骤那里留一个同样宽的空位，进度条不跳）
    private var topBar: some View {
        HStack(spacing: AppSpacing.xs) {
            Button(action: goBack) {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(AppColors.textPrimary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "上一步"))

            SlimProgressBar(fraction: Double(step.rawValue) / Double(OnboardingStep.countedSteps), color: AppColors.brand)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(String(localized: "第 \(step.rawValue) 步，共 \(OnboardingStep.countedSteps) 步"))

            if step == .preferences {
                Button("跳过", action: skipPreferences)
                    .font(.body)
                    .foregroundStyle(AppColors.textSecondary)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
                    .accessibilityHint(String(localized: "不填饮食偏好，直接看每日目标"))
            } else {
                // 固定大小的空位（Color.clear 不写大小会把整行、整页的空间都占掉）
                Color.clear
                    .frame(width: 44, height: 44)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, AppSpacing.xs)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    /// 底部的按钮：每一步同一个位置、同一个样子
    private var bottomBar: some View {
        VStack(spacing: AppSpacing.xxs) {
            switch step {
            case .welcome:
                Button("开始") { go(to: .goal) }
                    .buttonStyle(.appPrimary)
            case .result:
                Button("记录第一餐") { finish(logFirstMeal: true) }
                    .buttonStyle(.appPrimary)
                    .disabled(draft.bodyInfo == nil)
                Button("稍后再说") { finish(logFirstMeal: false) }
                    .buttonStyle(.appTertiary)
                    .disabled(draft.bodyInfo == nil)
            default:
                Button("继续", action: goForward)
                    .buttonStyle(.appPrimary)
                    .disabled(!canContinue)
            }
        }
        .padding(.horizontal, AppSpacing.pageMargin)
        .padding(.vertical, AppSpacing.xs)
        .appBottomBar()
    }

    // MARK: - 每一步的内容

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .welcome:
            WelcomeStep()
        case .goal:
            GoalStep(draft: draft) { goal in
                draft.goal = goal
                goalWasAdjusted = false  // 自己选的，不用再说明
                selectionTick += 1
            }
        case .basicInfo:
            AppForm {
                OnboardingStepHeader(
                    title: String(localized: "你的基本信息"), subtitle: String(localized: "用来估算你每天大约需要多少热量。"))
                BasicInfoSection(draft: draft, showsTitle: false)
            }
        case .activity:
            ActivityStep(draft: draft) { level in
                draft.activity = level
                selectionTick += 1
            }
        case .preferences:
            PreferencesStep(choices: $preferences) { selectionTick += 1 }
        case .result:
            ResultStep(draft: draft, goalWasAdjusted: goalWasAdjusted)
        }
    }

    // MARK: - 规则

    /// 现在的进度（存档用）
    private var progress: OnboardingProgress {
        OnboardingProgress(step: step, profile: draft.snapshot, preferences: preferences, goalWasAdjusted: goalWasAdjusted)
    }

    /// 这一步填好了没有，能不能「继续」
    private var canContinue: Bool {
        switch step {
        case .welcome, .preferences: true
        case .goal: draft.goal != nil
        case .basicInfo: draft.isBasicInfoValid
        case .activity: draft.activity != nil
        case .result: draft.bodyInfo != nil
        }
    }

    /// 新的一步从哪边进来：往后走从右边，往回走从左边；减弱动态效果时只淡入淡出
    private var stepTransition: AnyTransition {
        if reduceMotion { return .opacity }
        return .asymmetric(
            insertion: .opacity.combined(with: .offset(x: movesForward ? 24 : -24)),
            removal: .opacity)
    }

    private func go(to next: OnboardingStep) {
        movesForward = next.rawValue > step.rawValue
        withAnimation(.easeOut(duration: 0.25)) { step = next }
        // 换了一页：旁白从新一页的开头读
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            UIAccessibility.post(notification: .screenChanged, argument: nil)
        }
    }

    private func goForward() {
        guard canContinue, let next = OnboardingStep(rawValue: step.rawValue + 1) else { return }
        if step == .basicInfo && Self.adjustGoalIfNeeded(draft) {
            goalWasAdjusted = true
        }
        go(to: next)
    }

    private func goBack() {
        guard let previous = OnboardingStep(rawValue: step.rawValue - 1) else { return }
        go(to: previous)
    }

    /// 跳过偏好：这一步选的都不算，直接看结果
    private func skipPreferences() {
        preferences = PreferenceChoices()
        go(to: .result)
    }

    /// 选了「减脂」但填的资料不适合减脂：换成「维持」。返回有没有换
    private static func adjustGoalIfNeeded(_ draft: ProfileDraft) -> Bool {
        guard draft.goal == .loseFat, draft.fatLossRestriction != nil else { return false }
        draft.goal = .maintain
        return true
    }

    /// 保存资料、写入偏好，删掉进度存档。保存后 App 自动切到主界面（见 RootView）
    private func finish(logFirstMeal: Bool) {
        guard !isFinished, let bodyInfo = draft.bodyInfo else { return }
        isFinished = true
        preferences.save()
        OnboardingProgress.clear()
        onFinish(logFirstMeal)  // 先告诉外面要不要打开「选择食物」，主界面一出现就知道
        modelContext.insert(UserProfile(body: bodyInfo))
        try? modelContext.save()
    }
}

// MARK: - 每一步共用的标题

/// 每一步最上面的大标题和一句说明
private struct OnboardingStepHeader: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text(title)
                .font(.title2.weight(.bold))
                .foregroundStyle(AppColors.textPrimary)
                .accessibilityAddTraits(.isHeader)
            if let subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(AppColors.textSecondary)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, AppSpacing.xxs)
        .padding(.top, AppSpacing.xs)
    }
}

/// 可以选的一张卡片：左边一个小图标（可选），标题 + 一句说明，右边一个圆圈（选中时是打勾的实心圆）。
/// 选中时底色换成品牌浅绿、加一圈橄榄绿的边，还有对勾：不只靠颜色区分
private struct OnboardingOptionCard: View {
    let title: String
    var detail: String?
    var systemImage: String?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous)
        Button(action: action) {
            HStack(spacing: AppSpacing.sm) {
                if let systemImage {
                    AppIconTile(
                        systemImage: systemImage, size: 40,
                        tint: isSelected ? AppColors.surfacePrimary : AppColors.surfaceSecondary,
                        iconColor: isSelected ? AppColors.brand : AppColors.iconSecondary)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(AppColors.textPrimary)
                    if let detail {
                        Text(detail)
                            .font(AppTypography.detail)
                            .foregroundStyle(AppColors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? AppColors.brand : AppColors.textTertiary)
                    .accessibilityHidden(true)
            }
            .multilineTextAlignment(.leading)
            .padding(AppSpacing.cardPadding)
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            .background(shape.fill(isSelected ? AppColors.brandSoft : AppColors.surfacePrimary))
            .overlay(shape.strokeBorder(isSelected ? AppColors.brand : .clear, lineWidth: 1.5))
            .contentShape(shape)
        }
        .buttonStyle(AppPressStyle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - 第 1 步：欢迎

private struct WelcomeStep: View {
    @ScaledMetric(relativeTo: .largeTitle) private var markWidth: CGFloat = 112

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    Spacer(minLength: AppSpacing.xxl)
                    // App 图标里的那只碗（代码画的，深色模式自动换颜色）
                    KindbiteMark()
                        .frame(width: min(markWidth, 168))
                        .padding(.bottom, AppSpacing.xxl)
                    VStack(spacing: AppSpacing.sm) {
                        Text("吃饭不需要每次都称重")
                            .font(.title.weight(.bold))
                            .foregroundStyle(AppColors.textPrimary)
                            .accessibilityAddTraits(.isHeader)
                        Text("拍一拍、选一选，就能更轻松地了解每天吃了多少。")
                            .font(.body)
                            .foregroundStyle(AppColors.textSecondary)
                    }
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: AppSpacing.xxl)
                    Label("你的资料和饮食记录只保存在这台手机上", systemImage: "lock")
                        .font(AppTypography.detail)
                        .foregroundStyle(AppColors.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.bottom, AppSpacing.md)
                }
                .padding(.horizontal, AppSpacing.pageMargin)
                .frame(maxWidth: .infinity, minHeight: proxy.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }
}

// MARK: - 第 2 步：目标

private struct GoalStep: View {
    let draft: ProfileDraft
    let onSelect: (Goal) -> Void

    var body: some View {
        AppForm {
            OnboardingStepHeader(title: String(localized: "你现在的目标是？"), subtitle: String(localized: "之后随时可以在「我的」里修改。"))
            VStack(spacing: AppSpacing.sm) {
                ForEach(Goal.allCases, id: \.self) { goal in
                    // 回到这一步时资料已经填过：不适合减脂的人，「减脂」不能选（下面有说明）
                    let disabled = goal == .loseFat && draft.fatLossRestriction != nil
                    OnboardingOptionCard(
                        title: goal.title, detail: Self.detail(goal), systemImage: Self.icon(goal), isSelected: draft.goal == goal
                    ) {
                        onSelect(goal)
                    }
                    .disabled(disabled)
                    .opacity(disabled ? 0.45 : 1)
                }
            }
            if let restriction = draft.fatLossRestriction {
                Label(restriction, systemImage: "info.circle")
                    .font(.callout)
                    .foregroundStyle(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, AppSpacing.xxs)
            }
        }
    }

    /// 引导里的说明比「编辑资料」里的更短：先让人选得出来
    private static func detail(_ goal: Goal) -> String {
        switch goal {
        case .loseFat: String(localized: "逐步降低体脂和体重")
        case .maintain: String(localized: "保持现在的状态")
        case .gainMuscle: String(localized: "增加体重和肌肉")
        }
    }

    private static func icon(_ goal: Goal) -> String {
        switch goal {
        case .loseFat: "arrow.down.right"
        case .maintain: "equal"
        case .gainMuscle: "arrow.up.right"
        }
    }
}

// MARK: - 第 4 步：活动量

private struct ActivityStep: View {
    let draft: ProfileDraft
    let onSelect: (ActivityLevel) -> Void

    var body: some View {
        AppForm {
            OnboardingStepHeader(title: String(localized: "平时的活动量"), subtitle: String(localized: "按大多数星期的实际情况选就好。"))
            VStack(spacing: AppSpacing.sm) {
                ForEach(ActivityLevel.allCases, id: \.self) { level in
                    OnboardingOptionCard(title: level.title, detail: level.detail, isSelected: draft.activity == level) {
                        onSelect(level)
                    }
                }
            }
            Text("不确定的话选低一档。用 2～3 周后，可以按体重的变化再调整。")
                .font(AppTypography.detail)
                .foregroundStyle(AppColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, AppSpacing.xxs)
        }
    }
}

// MARK: - 第 5 步：饮食偏好（可以跳过）

private struct PreferencesStep: View {
    @Binding var choices: PreferenceChoices
    let onToggle: () -> Void

    var body: some View {
        AppForm {
            OnboardingStepHeader(
                title: String(localized: "饮食偏好"), subtitle: String(localized: "推荐食谱时会参考。可以多选，也可以跳过。"))

            FlowLayout(spacing: AppSpacing.xs) {
                ForEach(FoodPreferenceTag.allCases, id: \.self) { tag in
                    PreferenceChip(title: tag.title, isSelected: choices.tags.contains(tag)) {
                        choices.toggle(tag)
                        onToggle()
                    }
                }
            }

            if choices.showsAllergies {
                AppFormSection(title: String(localized: "过敏食材"), accessory: { InfoButton(topic: .allergies) }) {
                    AppFormTextField(
                        title: String(localized: "过敏食材"), placeholder: String(localized: "例如：花生、虾"), text: $choices.allergies)
                }
                .transition(.opacity)
            } else {
                Button {
                    withAnimation(.easeOut(duration: 0.2)) { choices.showsAllergies = true }
                } label: {
                    Label("添加过敏食材", systemImage: "plus")
                }
                .buttonStyle(AppButtonStyle(kind: .tertiary, tint: AppColors.brand, fullWidth: false))
            }

            Text("忌口可以稍后在「我的」→「偏好和忌口」里填写。")
                .font(AppTypography.detail)
                .foregroundStyle(AppColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, AppSpacing.xxs)
        }
    }
}

/// 一个偏好标签：胶囊形；选中时品牌浅绿底、深橄榄字、前面一个对勾（不只靠颜色区分）
private struct PreferenceChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: AppSpacing.xxs) {
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.footnote.weight(.semibold))
                        .accessibilityHidden(true)
                }
                Text(title)
            }
            .font(.subheadline.weight(isSelected ? .semibold : .medium))
            .foregroundStyle(isSelected ? AppColors.brandDeep : AppColors.textPrimary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, AppSpacing.md)
            .padding(.vertical, AppSpacing.xs)
            .frame(minHeight: 44)
            .background(Capsule().fill(isSelected ? AppColors.brandSoft : AppColors.surfacePrimary))
            .overlay(Capsule().strokeBorder(isSelected ? AppColors.brand : AppColors.divider, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(AppPressStyle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - 第 6 步：每日参考目标

private struct ResultStep: View {
    let draft: ProfileDraft
    let goalWasAdjusted: Bool

    var body: some View {
        AppForm {
            OnboardingStepHeader(title: String(localized: "你的每日参考目标"))
            if let bodyInfo = draft.bodyInfo {
                // 和「我的」页最上面同一张卡片：大号的千卡、三大营养素，有需要时下面一段温和的说明
                GoalHeroCard(targets: NutritionCalculator.targets(for: bodyInfo), bodyInfo: bodyInfo)

                // 先选了「减脂」、但填的资料不适合减脂：说明为什么按「维持」算
                if goalWasAdjusted, let restriction = draft.fatLossRestriction {
                    Label(String(localized: "根据你填写的资料，这里先按「维持」计算。") + restriction, systemImage: "info.circle")
                        .font(.callout)
                        .foregroundStyle(AppColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, AppSpacing.xxs)
                }

                Text("这是一个参考起点，不需要每天都精确做到。记录几天以后，你会更了解自己的饮食。")
                    .font(.callout)
                    .foregroundStyle(AppColors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, AppSpacing.xxs)

                NavigationLink {
                    ExplanationView(bodyInfo: bodyInfo)
                } label: {
                    Label("这些数字是怎么算的？", systemImage: "info.circle")
                        .font(AppTypography.detail.weight(.medium))
                        .foregroundStyle(AppColors.brand)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(minHeight: 44)
                        .padding(.horizontal, AppSpacing.xxs)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                // 健康说明：小字，不用勾选
                Text("每日目标是根据公式估算的参考值，不是医疗建议。本 App 适用于 18 岁以上的成年人。如有疾病（尤其是肾病、糖尿病）、处于孕期或哺乳期，或有饮食失调史，请先咨询医生或注册营养师。")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, AppSpacing.xxs)
            }
        }
    }
}

#Preview {
    OnboardingView()
        .modelContainer(for: AppModels.all, inMemory: true)
}
