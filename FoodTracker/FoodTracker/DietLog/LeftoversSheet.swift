//
//  LeftoversSheet.swift
//  FoodTracker
//
//  「这餐吃了多少」：饭前记的一餐没吃完时，从「今日」一餐卡片底部的「没吃完？」打开。从上到下：
//  1. 拍一张剩下的：选好照片后点「开始估算」，AI 对照这餐原来的食物（只发名字和大约多少克），
//     估算每样吃了几成，填进下面（换成最接近的一档，用户可以再改）。用掉 1 次识别，和拍照识别共用次数
//  2. 整餐：全部 / ¾ / 一半 / ¼，点一下每一样都改成这一档（每一样不一样时哪一格都不选中）
//  3. 每一样：全部吃完 / 吃了¾ / 吃了一半 / 吃了¼ / 没吃（「没吃」保存时从这餐里删掉）
//  4. 这餐合计：按吃了的算多少千卡，下面一行「原来 620 千卡」
//  点「保存」才改记录；下方出现「午餐已更新为 430 千卡  撤销」，几秒内点「撤销」就原样换回去。
//  每次都按原来盛的份量算（见 FoodEntry.setEaten），改几次都不会越乘越小
//

import PhotosUI
import SwiftData
import SwiftUI

struct LeftoversSheet: View {
    let meal: MealType
    let entries: [FoodEntry]  // 这一餐的记录（按添加的先后）

    /// AI 估算的几种状态
    enum Estimate: Equatable {
        case idle  // 还没开始（选好照片就显示「开始估算」）
        case loading  // 正在估算
        case done(String)  // 估算完了，带着 AI 的一句话
        case notLeftovers(String)  // 照片里不是吃剩的饭菜
        case failed(String)  // 没有完成（网络、次数用完…），带着一句能照着做的话
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(ToastCenter.self) private var toasts: ToastCenter?
    /// 每一样吃了几成（记录的编号 → 0～1）；打开时是记录现在的样子
    @State private var fractions: [PersistentIdentifier: Double]
    @State private var photo: UIImage?  // 剩下的照片
    @State private var estimate: Estimate = .idle
    @State private var estimateTask: Task<Void, Never>?
    @State private var remaining: Int?  // 今天还能识别几次；问不到就不显示
    @State private var pendingAIAction: PendingAIAction?  // 还没同意使用 AI 时，先记下来，同意后再估算
    @State private var showsCamera = false
    @State private var showsLibrary = false
    @State private var libraryItem: PhotosPickerItem?
    @State private var loadFailed = false
    @State private var estimatedTick = 0  // 估算完就加 1：震一下
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize  // 字号特别大时，每一样的选择按钮放到名称下面
    @ScaledMetric(relativeTo: .caption) private var pieSize: CGFloat = 12  // 小饼图跟着字号变大

    init(meal: MealType, entries: [FoodEntry]) {
        self.meal = meal
        self.entries = entries
        _fractions = State(initialValue: Dictionary(entries.map { ($0.persistentModelID, $0.eaten) }) { first, _ in first })
    }

    private var hasCamera: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    private func fraction(for entry: FoodEntry) -> Double {
        fractions[entry.persistentModelID] ?? entry.eaten
    }

    /// 和打开时比有没有改动（没改动时「保存」不能点）
    private var hasChanges: Bool {
        entries.contains { fraction(for: $0) != $0.eaten }
    }

    var body: some View {
        AppForm {
            photoSection
            AppFormSection(String(localized: "整餐")) {
                AppSegmentedControl(
                    title: String(localized: "整餐吃了多少"), selection: mealSelection,
                    options: EatenPortion.mealOptions.map(Optional.some),
                    label: { $0.map(EatenPortion.mealLabel) ?? "" },
                    accessibilityLabel: { $0.map(EatenPortion.spokenMealLabel) ?? "" }
                )
                .padding(AppSpacing.sm)
            }
            AppFormSection(
                String(localized: "每一样"),
                footer: entries.contains { fraction(for: $0) == 0 }
                    ? String(localized: "选了「没吃」的，保存时会从这一餐里删掉。") : nil
            ) {
                ForEach(Array(entries.enumerated()), id: \.element.persistentModelID) { index, entry in
                    if index > 0 { AppFormDivider() }
                    itemRow(entry)
                }
            }
            totalSection
        }
        .appSheetHeader(
            AppSheetHeader(
                title: String(localized: "这餐吃了多少"), onCancel: cancel, confirmTitle: String(localized: "保存"),
                confirmEnabled: hasChanges && estimate != .loading, onConfirm: save))
        // 改了一半、或者正在估算时，往下滑不会把这一页关掉（用「取消」）
        .interactiveDismissDisabled(hasChanges || estimate == .loading)
        .sensoryFeedback(.success, trigger: estimatedTick)
        .fullScreenCover(isPresented: $showsCamera) {
            CameraPicker { picked in use(picked) }
                .ignoresSafeArea()
        }
        .photosPicker(isPresented: $showsLibrary, selection: $libraryItem, matching: .images)
        .onChange(of: libraryItem) {
            Task { await loadLibraryItem() }
        }
        .task { await refreshRemaining() }
        .onDisappear { estimateTask?.cancel() }
        .aiConsentSheet(pending: $pendingAIAction)
        .alert("读取照片失败", isPresented: $loadFailed) {
            Button("好", role: .cancel) {}
        } message: {
            Text("这张照片读不出来，请换一张试试。")
        }
        .appSheet()
    }

    // MARK: - 拍一张剩下的

    @ViewBuilder
    private var photoSection: some View {
        AppFormSection(nil, footer: remainingText) {
            if let photo {
                photoCard(photo)
            } else {
                sourceMenu {
                    HStack(spacing: AppSpacing.sm) {
                        AppIconTile(systemImage: "camera.viewfinder", tint: AppColors.brandSoft, iconColor: AppColors.brand)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("拍一张剩下的")
                                .font(.body.weight(.medium))
                                .foregroundStyle(AppColors.textPrimary)
                            Text("AI 对照这餐原来的食物，估算每样吃了多少。")
                                .font(AppTypography.detail)
                                .foregroundStyle(AppColors.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .multilineTextAlignment(.leading)  // 按钮里的文字默认居中，换行后第二行会跑到中间
                        Spacer(minLength: AppSpacing.xs)
                        AppChevron()
                    }
                    .padding(.horizontal, AppSpacing.cardPadding)
                    .padding(.vertical, AppSpacing.sm)
                    .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .accessibilityHint(String(localized: "会用掉 1 次识别"))
            }
        }
    }

    /// 选好照片以后：左边小图，右边按现在的状态写一句话和能做的事
    private func photoCard(_ photo: UIImage) -> some View {
        HStack(alignment: .top, spacing: AppSpacing.sm) {
            Image(uiImage: photo)
                .resizable()
                .scaledToFill()
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                switch estimate {
                case .idle:
                    Text("照片准备好了。估算会用掉 1 次识别。")
                        .font(AppTypography.detail)
                        .foregroundStyle(AppColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button(action: startEstimate) {
                        Label("开始估算", systemImage: "sparkles")
                    }
                    .buttonStyle(AppButtonStyle(kind: .primary, fullWidth: false))
                    changePhotoButton
                case .loading:
                    HStack(spacing: AppSpacing.xs) {
                        AppLoadingIndicator()  // 冒热气的小碗（全 App 的加载都用它，不用转圈）
                        Text("正在估算吃了多少…")
                            .font(AppTypography.detail)
                            .foregroundStyle(AppColors.textSecondary)
                    }
                    .frame(minHeight: 32)
                    Button("取消", action: cancelEstimate)
                        .buttonStyle(AppButtonStyle(kind: .tertiary, fullWidth: false))
                case .done(let message):
                    Text(message)
                        .foregroundStyle(AppColors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("已经按估算填好，可以再调整。")
                        .font(AppTypography.detail)
                        .foregroundStyle(AppColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    changePhotoButton
                case .notLeftovers(let message):
                    Text(message)
                        .foregroundStyle(AppColors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    changePhotoButton
                case .failed(let message):
                    Text(message)
                        .foregroundStyle(AppColors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: AppSpacing.xs) {
                        Button("重试", action: startEstimate)
                            .buttonStyle(AppButtonStyle(kind: .secondary, fullWidth: false))
                        changePhotoButton
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(AppSpacing.cardPadding)
        .animation(.easeOut(duration: 0.2), value: estimate)
    }

    /// 「换一张」：很轻的第三级按钮（有相机时可以选拍照或从相册选）
    private var changePhotoButton: some View {
        sourceMenu {
            Text("换一张")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(AppColors.brand)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
    }

    /// 有相机时：点了先选「拍照」还是「从相册选择」；没有相机（模拟器）时直接打开相册
    @ViewBuilder
    private func sourceMenu<Label: View>(@ViewBuilder label: () -> Label) -> some View {
        if hasCamera {
            Menu {
                Button("拍照", systemImage: "camera") { showsCamera = true }
                Button("从相册选择", systemImage: "photo.on.rectangle") { showsLibrary = true }
            } label: {
                label()
            }
        } else {
            Button {
                showsLibrary = true
            } label: {
                label()
            }
            .buttonStyle(AppPressStyle(scales: false))
        }
    }

    /// 照片下面一行小字：今天还能识别几次（问不到就不写）
    private var remainingText: String? {
        guard let remaining else { return nil }
        return remaining > 0
            ? String(localized: "和拍照识别共用次数，今天还可以识别 \(remaining) 次。")
            : String(localized: "今天的识别次数用完了，可以直接在下面选。")
    }

    // MARK: - 整餐、每一样、合计

    /// 整餐的分段按钮：每一样都是同一档时选中那一格；不一样时哪一格都不选中。点了就把每一样都改成这一档
    private var mealSelection: Binding<Double?> {
        Binding(
            get: {
                let all = Set(entries.map { fraction(for: $0) })
                guard all.count == 1, let only = all.first, EatenPortion.mealOptions.contains(only) else { return nil }
                return only
            },
            set: { newValue in
                guard let newValue else { return }
                for entry in entries { fractions[entry.persistentModelID] = newValue }
            })
    }

    /// 一样食物：名称、原来的份量和热量（改了的写「380 → 190 千卡」），右边是选吃了多少的小按钮。
    /// 字号特别大时按钮放到下面一行（并排的话名称会被挤成很窄的一条）
    private func itemRow(_ entry: FoodEntry) -> some View {
        let current = fraction(for: entry)
        let layout =
            dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: AppSpacing.xxs))
            : AnyLayout(HStackLayout(alignment: .center, spacing: AppSpacing.sm))
        return layout {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name)
                    .font(AppTypography.itemName)
                    .foregroundStyle(current == 0 ? AppColors.textSecondary : AppColors.textPrimary)
                    .strikethrough(current == 0, color: AppColors.textTertiary)
                    .lineLimit(2)
                Text(itemDetail(entry, fraction: current))
                    .font(AppTypography.detail)
                    .foregroundStyle(AppColors.textSecondary)
                    .monospacedDigit()
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !dynamicTypeSize.isAccessibilitySize {
                Spacer(minLength: AppSpacing.xs)
            }
            Menu {
                Picker(String(localized: "吃了多少"), selection: binding(for: entry)) {
                    ForEach(EatenPortion.itemOptions, id: \.self) { option in
                        Text(EatenPortion.itemLabel(option)).tag(option)
                    }
                }
            } label: {
                HStack(spacing: AppSpacing.xxs) {
                    EatenPie(fraction: current)
                        .frame(width: pieSize, height: pieSize)
                    Text(EatenPortion.itemLabel(current))
                        .lineLimit(1)
                        .fixedSize()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(AppColors.textTertiary)
                }
                .font(AppTypography.caption.weight(.semibold))
                .foregroundStyle(current == 0 ? AppColors.destructive : AppColors.brandDeep)
                .padding(.horizontal, 10)
                .frame(minHeight: 30)
                .background(AppColors.surfaceSecondary, in: Capsule())
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .accessibilityLabel(String(localized: "\(entry.name)吃了多少"))
            .accessibilityValue(EatenPortion.spokenItemLabel(current))
        }
        .padding(.horizontal, AppSpacing.cardPadding)
        .padding(.vertical, AppSpacing.xs)
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        .animation(.easeOut(duration: 0.15), value: current)
    }

    /// 「1 碗 · 约 150 克 · 240 千卡」；没吃完「… · 240 → 120 千卡」；没吃「保存时删掉」
    private func itemDetail(_ entry: FoodEntry, fraction: Double) -> String {
        let served = entry.servedValues.caloriesKcal
        let kcal: String
        switch fraction {
        case 1: kcal = String(localized: "\(served.noDecimal) 千卡")
        case 0: kcal = String(localized: "保存时删掉")
        default:
            let eaten = EatenPortion.eatenValues(served: entry.servedValues, fraction: fraction).caloriesKcal
            kcal = String(localized: "\(served.noDecimal) → \(eaten.noDecimal) 千卡")
        }
        guard let portion = entry.portionText else { return kcal }
        return "\(portion) · \(kcal)"
    }

    private func binding(for entry: FoodEntry) -> Binding<Double> {
        Binding(
            get: { fraction(for: entry) },
            set: { fractions[entry.persistentModelID] = $0 })
    }

    /// 这餐合计：按吃了的算多少千卡；和原来不一样时下面写「原来 620 千卡」
    private var totalSection: some View {
        let served = DietLogMath.total(of: entries.map(\.servedValues)).caloriesKcal
        let eaten = DietLogMath.total(
            of: entries.map { EatenPortion.eatenValues(served: $0.servedValues, fraction: fraction(for: $0)) }
        ).caloriesKcal
        // 字号特别大时上下排（并排的话「这餐合计」会被挤成两行）
        let layout =
            dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: AppSpacing.xxs))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: AppSpacing.sm))
        return AppFormSection(nil) {
            layout {
                Text("这餐合计")
                    .foregroundStyle(AppColors.textPrimary)
                if !dynamicTypeSize.isAccessibilitySize {
                    Spacer(minLength: AppSpacing.xs)
                }
                VStack(alignment: dynamicTypeSize.isAccessibilitySize ? .leading : .trailing, spacing: 2) {
                    Text("\(eaten.noDecimal) 千卡")
                        .font(.system(.title3, design: .rounded, weight: .semibold).monospacedDigit())
                        .foregroundStyle(AppColors.textPrimary)
                        .contentTransition(.numericText())
                    if eaten != served {
                        Text("原来 \(served.noDecimal) 千卡")
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.textSecondary)
                            .monospacedDigit()
                    }
                }
            }
            .padding(AppSpacing.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(.easeOut(duration: 0.15), value: eaten)
            .accessibilityElement(children: .combine)
        }
    }

    // MARK: - 功能

    /// 拍好或选好一张照片：换掉原来的，回到「开始估算」（换照片不会自动花次数）
    private func use(_ picked: UIImage) {
        estimateTask?.cancel()
        photo = picked
        estimate = .idle
    }

    private func loadLibraryItem() async {
        guard let item = libraryItem else { return }
        libraryItem = nil  // 清空选择，下次选同一张照片也能生效
        if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
            use(image)
        } else {
            loadFailed = true
        }
    }

    /// 没同意过使用 AI 时，先弹出说明；同意后才上传照片
    private func startEstimate() {
        AIConsent.perform(pending: $pendingAIAction) {
            estimateTask = Task { await runEstimate() }
        }
    }

    private func cancelEstimate() {
        estimateTask?.cancel()
        estimateTask = nil
        estimate = .idle
    }

    /// 压缩照片 → 连同原来的清单发给后端 → 把每样吃了几成换成最接近的一档，填进下面
    private func runEstimate() async {
        guard estimate != .loading, let photo else { return }
        guard let jpeg = photo.compressedForUpload() else {
            estimate = .failed(String(localized: "这张照片处理不了，请换一张试试。"))
            return
        }
        estimate = .loading
        // 只发名字和原来大约多少克（不发热量和别的记录）；名字太长的截一下（后端最多收 60 个字）
        let sent = Array(entries.prefix(APIClient.maxLeftoverItems))
        let items = sent.map { entry in
            let weight = entry.eatenFraction == nil ? entry.weightG : entry.servedWeightG
            return LeftoverServedItem(name: String(entry.name.prefix(60)), weightG: weight.map { min($0, 5000) })
        }
        do {
            let result = try await APIClient.leftovers(jpeg: jpeg, items: items, lang: AppLanguage.current.apiCode)
            guard !Task.isCancelled else { return }
            if let left = result.remainingToday { remaining = left }
            guard result.isLeftoverPhoto, result.eaten.count == sent.count else {
                estimate = .notLeftovers(
                    result.message.isEmpty ? String(localized: "这张照片里没看到这一餐剩下的饭菜，换一张试试。") : result.message)
                return
            }
            for (entry, eaten) in zip(sent, result.eaten) {
                fractions[entry.persistentModelID] = EatenPortion.snapped(eaten)
            }
            estimate = .done(result.message)
            estimatedTick += 1
        } catch {
            // 点了「取消」：已经回到「开始估算」了，什么都不用说
            guard !Task.isCancelled else { return }
            estimate = .failed(error.localizedDescription)
            // 失败时后端可能把次数还回去了，重新问一下
            Task { await refreshRemaining() }
        }
    }

    /// 问后端今天还能识别几次（不花钱、不占次数）；问不到就不显示
    private func refreshRemaining() async {
        if let quota = try? await APIClient.quota() {
            remaining = quota.analyzeRemaining
        }
    }

    private func cancel() {
        estimateTask?.cancel()
        dismiss()
    }

    /// 保存：改了的每一样按新的比例算（「没吃」的删掉），下方提示「午餐已更新为 430 千卡  撤销」
    private func save() {
        var changed: [(entry: FoodEntry, previous: Double)] = []
        var removed: [FoodEntrySnapshot] = []
        var kept: [FoodEntry] = []
        for entry in entries {
            let new = fraction(for: entry)
            let previous = entry.eaten
            if new <= 0 {
                removed.append(FoodEntrySnapshot(entry))
                modelContext.delete(entry)
                continue
            }
            kept.append(entry)
            if new != previous {
                changed.append((entry, previous))
                entry.setEaten(new)
            }
        }
        try? modelContext.save()
        let message =
            kept.isEmpty
            ? String(localized: "已删除\(meal.title)的 \(removed.count) 项")
            : String(localized: "\(meal.title)已更新为 \(DietLogMath.total(of: kept.map(\.values)).caloriesKcal.noDecimal) 千卡")
        // 撤销：改过的换回原来的比例（从原来盛的份量算，数字和改之前一模一样），删掉的原样放回去
        toasts?.changed(message) { [modelContext] in
            for (entry, previous) in changed where entry.modelContext != nil && !entry.isDeleted {
                entry.setEaten(previous)
            }
            for snapshot in removed {
                snapshot.restore(into: modelContext)
            }
            try? modelContext.save()
        }
        dismiss()
    }
}

#Preview {
    let container = SampleData.previewContainer
    let entries = (try? container.mainContext.fetch(FetchDescriptor<FoodEntry>())) ?? []
    LeftoversSheet(meal: .lunch, entries: entries)
        .modelContainer(container)
}
