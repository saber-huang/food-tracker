//
//  PhotoReviewView.swift
//  FoodTracker
//
//  拍照识别的确认页和分析页（同一页，分几步）：
//  1. 确认照片：上面是选中那张照片的大图，下面一行是所有照片的缩略图（点一张换着看），最后一格「+」再加一张；
//     选中的那张可以「重拍」或「删除」，删得一张不剩就回到「今日」页。一餐最多 4 张。
//     底部：「开始识别」（几张时是「识别 3 张照片」）、「再拍一张」、今天还能识别几次
//  2. 正在分析：整页换成分析的样子，不再显示「确认照片」和返回按钮。没有大白卡片：
//     页面中上部一只冒热气的碗，下面「正在分析这顿饭」（几张时「正在分析 3 张照片」）和一句正在做什么
//     （等得久了自然换一句，不显示假的百分比、也不说「通常要几秒」），再下面一排小缩略图，最底下一个很轻的「取消分析」
//  3. 分析完了：热气停下、碗轻轻放大一点、震一下，约 0.24 秒后打开识别结果页（叠在这一页上面）。
//     在结果页点返回就回到第 1 步，照片都还在；结果页保存成功时，由「今日」页把这两页一起关掉
//  4. 没有完成（网络、服务器）：同一个位置换成没有热气的碗 +「没有完成识别」+ 能照着做的一句话，
//     按钮是「重试」「手动添加」「返回照片」。不弹警告框
//  5. 照片里没认出食物：不给出任何热量，「没有识别到足够清晰的食物」+ 几条拍照建议，「重新拍摄」「手动添加」
//  几张照片一起发给 AI，合并成这一餐的一份结果（同一份食物在几张照片里出现只算一次，见后端 food_ai.py）
//

import PhotosUI
import SwiftUI

struct PhotoReviewView: View {
    @Binding var photos: [UIImage]
    /// 识别时记到哪一天：按下「开始识别」时「今日」页正在看的那天（20260929 这样的数字）
    let dayKey: () -> Int
    /// 结果页保存成功：由「今日」页关掉结果页和这一页、清掉照片
    let onSaved: () -> Void

    /// 这一页现在在哪一步
    enum Phase: Equatable {
        case reviewing  // 确认照片
        case analyzing  // 正在分析
        case finishing  // 分析完了，马上打开结果页
        case failed(String)  // 没有完成（网络、服务器出错），带着一句能照着做的话
        case notFood  // 照片里没认出食物
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize  // 字号特别大时换一种排法
    /// 「可以补拍不同角度……」的提示只出现一次（第一次来到这一页时）
    @AppStorage("multiPhotoTipShown") private var tipAlreadyShown = false
    @State private var showsTip = false
    @State private var selected = 0  // 大图显示的是第几张
    @State private var camera: CameraTarget?  // 有值时打开相机：再拍一张，或者重拍某一张
    @State private var showsLibrary = false
    @State private var libraryItems: [PhotosPickerItem] = []
    @State private var phase: Phase = .reviewing
    @State private var analysisTask: Task<Void, Never>?  // 正在进行的分析：点「取消分析」时停掉它
    @State private var analysisStart = Date.now  // 开始分析的时间：用来决定显示哪一句
    @State private var remaining: Int?  // 今天还能识别几次；问不到就不显示
    @State private var pendingAIAction: PendingAIAction?  // 还没同意使用 AI 时，先记下要做的识别，同意后再做
    @State private var captureTick = 0  // 拍到一张就加 1：轻轻震一下
    @State private var successTick = 0  // 分析完就加 1：震一下表示完成
    @State private var loadFailed = false  // 从相册读照片失败
    @State private var manualEntry: ManualEntryRequest?
    @State private var resultRoute: ResultRoute?  // 分析成功后有值：打开结果页（叠在这一页上面）

    private var canAddMore: Bool { photos.count < APIClient.maxPhotos }
    private var hasCamera: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    var body: some View {
        Group {
            if phase == .reviewing {
                reviewContent
            } else {
                analysisContent
            }
        }
        .background { AppBackground(glow: false) }
        // 开始分析以后已经不是「确认照片」了：标题和返回按钮都收起来（往右滑返回也一起关掉），用页面里的按钮
        .navigationTitle(phase == .reviewing ? String(localized: "确认照片") : "")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(phase != .reviewing)
        .safeAreaInset(edge: .bottom) {
            if phase == .reviewing {
                bottomBar
            } else if phase == .analyzing {
                cancelBar
            }
        }
        .animation(.easeOut(duration: 0.25), value: phase)
        .hidesFloatingTabBar()
        .sensoryFeedback(.impact(weight: .light), trigger: captureTick)
        .sensoryFeedback(.success, trigger: successTick)
        .fullScreenCover(item: $camera) { target in
            CameraPicker { photo in
                apply(photo, to: target)
            }
            .ignoresSafeArea()
        }
        .photosPicker(
            isPresented: $showsLibrary, selection: $libraryItems, maxSelectionCount: max(1, APIClient.maxPhotos - photos.count),
            selectionBehavior: .ordered, matching: .images
        )
        .onChange(of: libraryItems) {
            Task { await addLibraryItems() }
        }
        // 删得一张不剩：回到「今日」页；删掉的是最后一张时，选中的往前挪
        .onChange(of: photos.count) { _, count in
            if count == 0 {
                dismiss()
            } else if selected >= count {
                selected = count - 1
            }
            if count > 1 { showsTip = false }
        }
        // 从结果页返回：回到确认照片这一步
        .onChange(of: resultRoute == nil) { _, isGone in
            if isGone && phase == .finishing { phase = .reviewing }
        }
        .onAppear {
            // 第一次只带着一张照片来到这一页时，告诉用户可以补拍；以后不再出现
            // （从相册一次选了好几张的人已经知道可以多张，不用再提示）
            if !tipAlreadyShown && photos.count == 1 {
                showsTip = true
                tipAlreadyShown = true
            }
        }
        .onDisappear {
            // 这一页被关掉（保存成功、删光照片）时，还在进行的分析也停掉
            if resultRoute == nil { analysisTask?.cancel() }
        }
        .task { await refreshRemaining() }
        // 第一次识别前：说明照片会发给谁、怎么处理，同意后才上传（见 AIConsent.swift）
        .aiConsentSheet(pending: $pendingAIAction)
        // 「手动添加」：和首页的「手动」一样，打开「选择食物」
        .sheet(item: $manualEntry) { request in
            FoodSearchSheet(request: request)
        }
        // 识别结果页：从这一页打开，点返回就回到这一页（照片还在，可以重拍、补拍、再识别）
        .navigationDestination(item: $resultRoute) { route in
            ResultView(result: route.result, photos: route.photos, dayKey: route.dayKey, today: route.today, onSaved: onSaved)
        }
        .alert("读取照片失败", isPresented: $loadFailed) {
            Button("好", role: .cancel) {}
        } message: {
            Text("有照片读不出来，请换一张试试。")
        }
    }

    // MARK: - 第 1 步：确认照片

    private var reviewContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                preview
                selectedPhotoActions
                thumbnailStrip
                if showsTip {
                    tip
                }
            }
            .padding(.horizontal, AppSpacing.pageMargin)
            .padding(.top, AppSpacing.xs)
            .padding(.bottom, AppSpacing.lg)
        }
        .transition(.opacity)
    }

    // MARK: - 第 2～5 步：分析中、完成、没有完成、没认出食物

    /// 分析的样子：内容直接放在页面背景上（不放在卡片里），碗在屏幕大约三分之一高的地方。
    /// 出错时碗留在原处（只是热气没了），页面不跳
    private var analysisContent: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    Color.clear.frame(height: max(AppSpacing.lg, proxy.size.height * 0.21))
                    analysisState
                        .padding(.horizontal, AppSpacing.pageMargin)
                    Color.clear.frame(height: AppSpacing.xxl)
                }
                .frame(maxWidth: .infinity, minHeight: proxy.size.height, alignment: .top)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .transition(.opacity)
    }

    @ViewBuilder
    private var analysisState: some View {
        switch phase {
        case .reviewing, .analyzing, .finishing:
            // 每秒看一次等了多久，决定显示哪一句
            TimelineView(.periodic(from: analysisStart, by: 1)) { context in
                BrandedStateView(
                    kind: .loading, title: Self.analyzingTitle(photoCount: photos.count),
                    message: Self.loadingMessages(photoCount: photos.count).line(after: context.date.timeIntervalSince(analysisStart)),
                    isFinishing: phase == .finishing
                ) {
                    analysisThumbnails
                } actions: {
                    EmptyView()
                }
            }
        case .failed(let message):
            BrandedStateView(kind: .error, title: String(localized: "没有完成识别"), message: message) {
                analysisThumbnails
            } actions: {
                Button("重试", action: startAnalyzing)
                    .buttonStyle(.appPrimary)
                Button("手动添加", action: openManualEntry)
                    .buttonStyle(.appSecondary)
                Button("返回照片") { phase = .reviewing }
                    .buttonStyle(.appTertiary)
            }
        case .notFood:
            BrandedStateView(
                kind: .error, title: String(localized: "没有识别到足够清晰的食物"),
                message: photos.count > 1
                    ? String(localized: "这几张照片里的食物不够清晰，可以换个角度再试一次。")
                    : String(localized: "这张照片里的食物不够清晰，可以换个角度再试一次。")
            ) {
                photoTips
            } actions: {
                Button("重新拍摄") { phase = .reviewing }
                    .buttonStyle(.appPrimary)
                Button("手动添加", action: openManualEntry)
                    .buttonStyle(.appSecondary)
            }
        }
    }

    /// 分析时的标题：一张「正在分析这顿饭」，几张「正在分析 3 张照片」
    static func analyzingTitle(photoCount: Int) -> String {
        photoCount > 1 ? String(localized: "正在分析 \(photoCount) 张照片") : String(localized: "正在分析这顿饭")
    }

    /// 分析时的几句话：一开始说在识别；等得久一点（几张照片时）说在结合不同角度；再久一点说在整理营养
    static func loadingMessages(photoCount: Int) -> LoadingMessages {
        photoCount > 1
            ? LoadingMessages(
                lines: [
                    String(localized: "正在识别食物和估算份量…"), String(localized: "正在结合不同角度判断份量…"),
                    String(localized: "正在整理这顿饭的营养信息…"),
                ], switchAt: [0, 5, 11])
            : LoadingMessages(
                lines: [String(localized: "正在识别食物和估算份量…"), String(localized: "正在整理这顿饭的营养信息…")],
                switchAt: [0, 6])
    }

    /// 分析时的一排小缩略图：每张 56pt、小圆角，居中
    private var analysisThumbnails: some View {
        HStack(spacing: AppSpacing.xs) {
            ForEach(photos.indices, id: \.self) { index in
                Image(uiImage: photos[index])
                    .resizable()
                    .scaledToFill()
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous))
            }
        }
        .padding(.top, AppSpacing.xs)
        .accessibilityHidden(true)
    }

    /// 没认出食物时的几条拍照建议
    private var photoTips: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            ForEach(
                [String(localized: "换个角度再拍一张"), String(localized: "靠近食物一些"), String(localized: "确保主要食物没有被遮挡")],
                id: \.self
            ) { tip in
                HStack(alignment: .firstTextBaseline, spacing: AppSpacing.xs) {
                    Circle()
                        .fill(AppColors.oatRim)
                        .frame(width: 5, height: 5)
                        .alignmentGuide(.firstTextBaseline) { d in d[.bottom] + 4 }
                        .accessibilityHidden(true)
                    Text(tip)
                        .font(AppTypography.detail)
                        .foregroundStyle(AppColors.textSecondary)
                }
            }
        }
        .padding(.bottom, AppSpacing.xs)
    }

    /// 分析中最底下的「取消分析」：很轻的第三级按钮
    private var cancelBar: some View {
        Button("取消分析", action: cancelAnalysis)
            .buttonStyle(.appTertiary)
            .padding(.horizontal, AppSpacing.pageMargin)
            .padding(.bottom, AppSpacing.xs)
            .frame(maxWidth: .infinity)
    }

    /// 大图：选中的那张照片，完整显示（不裁剪）
    private var preview: some View {
        RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous)
            .fill(AppColors.surfaceSecondary)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if photos.indices.contains(selected) {
                    Image(uiImage: photos[selected])
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous))
                        .padding(AppSpacing.xs)
                }
            }
            .accessibilityElement()
            .accessibilityLabel("第 \(selected + 1) 张照片")
    }

    /// 大图下面：第几张，和对这一张的操作（重拍、删除）
    private var selectedPhotoActions: some View {
        // 字号特别大时，「第几张」放在上面一行，两个按钮放在下面一行，按钮上的字不会被挤成竖排
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: AppSpacing.xs))
            : AnyLayout(HStackLayout(spacing: AppSpacing.xs))
        return layout {
            Text("第 \(selected + 1) 张，共 \(photos.count) 张")
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textSecondary)
                .monospacedDigit()
            if !dynamicTypeSize.isAccessibilitySize {
                Spacer(minLength: AppSpacing.xs)
            }
            HStack(spacing: AppSpacing.xs) {
                if hasCamera {
                    Button {
                        camera = .retake(selected)
                    } label: {
                        Label("重拍", systemImage: "arrow.counterclockwise")
                            .actionChip(color: AppColors.iconSecondary)
                    }
                    .buttonStyle(AppPressStyle())
                }
                Button {
                    photos.remove(at: selected)
                } label: {
                    Label("删除", systemImage: "trash")
                        .actionChip(color: AppColors.destructive)
                }
                .buttonStyle(AppPressStyle())
            }
        }
    }

    /// 缩略图一行：点一张换着看；最后一格「+」再加一张（拍照或从相册选）
    private var thumbnailStrip: some View {
        ScrollView(.horizontal) {
            HStack(spacing: AppSpacing.xs) {
                ForEach(photos.indices, id: \.self) { index in
                    Button {
                        selected = index
                    } label: {
                        Image(uiImage: photos[index])
                            .resizable()
                            .scaledToFill()
                            .frame(width: 64, height: 64)
                            .clipShape(RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous)
                                    .strokeBorder(index == selected ? AppColors.brand : .clear, lineWidth: 2.5)
                            }
                    }
                    .buttonStyle(AppPressStyle())
                    .accessibilityLabel("第 \(index + 1) 张照片")
                    .accessibilityAddTraits(index == selected ? .isSelected : [])
                }
                if canAddMore {
                    addTile
                }
            }
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
    }

    /// 「+」：有相机时可以选拍照或从相册选，没有相机时直接打开相册
    @ViewBuilder
    private var addTile: some View {
        let tile = RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous)
            .fill(AppColors.surfaceSecondary)
            .frame(width: 64, height: 64)
            .overlay {
                Image(systemName: "plus")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(AppColors.iconSecondary)
            }
            .accessibilityLabel("再加一张照片")
        if hasCamera {
            Menu {
                Button("拍照", systemImage: "camera") { camera = .add }
                Button("从相册选择", systemImage: "photo.on.rectangle") { showsLibrary = true }
            } label: {
                tile
            }
        } else {
            Button {
                showsLibrary = true
            } label: {
                tile
            }
            .buttonStyle(AppPressStyle())
        }
    }

    /// 只出现一次的提示
    private var tip: some View {
        HStack(alignment: .top, spacing: AppSpacing.sm) {
            Image(systemName: "camera.on.rectangle")
                .font(.subheadline)
                .foregroundStyle(AppColors.iconSecondary)
                .accessibilityHidden(true)
            Text("可以补拍不同角度，或同一餐中的其他食物。")
                .font(AppTypography.detail)
                .foregroundStyle(AppColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button {
                withAnimation(.easeOut(duration: 0.15)) { showsTip = false }
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppColors.textTertiary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .padding(-AppSpacing.sm)
            .accessibilityLabel("关闭提示")
        }
        .padding(AppSpacing.md)
        .appCard(.muted)
        .transition(.opacity)
    }

    /// 底部：「开始识别 / 识别 3 张照片」（主要按钮）、「再拍一张」（第三级，橄榄绿字）、还能识别几次
    private var bottomBar: some View {
        VStack(spacing: 2) {
            Button(action: startAnalyzing) {
                Label(Self.analyzeTitle(photoCount: photos.count), systemImage: "sparkles")
            }
            .buttonStyle(.appPrimary)
            .disabled(photos.isEmpty)

            if canAddMore && hasCamera {
                Button {
                    camera = .add
                } label: {
                    Label("再拍一张", systemImage: "camera")
                }
                .buttonStyle(AppButtonStyle(kind: .tertiary, tint: AppColors.brand))
            }

            Group {
                if let remaining {
                    // 按下「开始识别」前告诉用户还剩几次；用完了也不挡着按钮，后端会给出明确的说明
                    Text(remaining > 0 ? "今天还可以识别 \(remaining) 次" : "今天的识别次数用完了，可以先手动添加")
                }
            }
            .font(.caption2)
            .foregroundStyle(AppColors.textTertiary)
            .padding(.top, AppSpacing.xxs)
        }
        .padding(.horizontal, AppSpacing.pageMargin)
        .padding(.top, AppSpacing.xs)
        .padding(.bottom, AppSpacing.xxs)
        .appBottomBar()
    }

    /// 按钮上的字：1 张是「开始识别」，几张是「识别 3 张照片」
    static func analyzeTitle(photoCount: Int) -> String {
        photoCount > 1 ? String(localized: "识别 \(photoCount) 张照片") : String(localized: "开始识别")
    }

    // MARK: - 功能

    /// 相机要拍的是：再加一张，还是重拍第几张
    enum CameraTarget: Identifiable {
        case add
        case retake(Int)

        var id: String {
            switch self {
            case .add: "add"
            case .retake(let index): "retake-\(index)"
            }
        }
    }

    private func apply(_ photo: UIImage, to target: CameraTarget) {
        switch target {
        case .add:
            guard canAddMore else { return }
            photos.append(photo)
            selected = photos.count - 1
        case .retake(let index):
            guard photos.indices.contains(index) else { return }
            photos[index] = photo
            selected = index
        }
        captureTick += 1
    }

    /// 从相册选的照片加在后面（最多加到 4 张）
    private func addLibraryItems() async {
        let items = libraryItems
        guard !items.isEmpty else { return }
        libraryItems = []  // 清空选择，下次选同一张照片也能生效
        var loaded: [UIImage] = []
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                loaded.append(image)
            }
        }
        if loaded.count < items.count { loadFailed = true }
        let room = APIClient.maxPhotos - photos.count
        guard room > 0, !loaded.isEmpty else { return }
        photos.append(contentsOf: loaded.prefix(room))
        selected = photos.count - 1
    }

    /// 没同意过使用 AI 时，先弹出说明；同意后才真正上传照片
    private func startAnalyzing() {
        AIConsent.perform(pending: $pendingAIAction) {
            analysisTask = Task { await analyze() }
        }
    }

    /// 「取消分析」：停掉请求，回到确认照片（已经发出去的那一次可能已经算了次数）
    private func cancelAnalysis() {
        analysisTask?.cancel()
        analysisTask = nil
        phase = .reviewing
    }

    /// 没认出食物、或者没有完成时，改成手动记
    private func openManualEntry() {
        manualEntry = ManualEntryRequest(meal: DietLogMath.suggestedMeal(at: .now), dayKey: dayKey())
    }

    /// 压缩每一张照片 → 一起发给后端 → 拿到合并好的一份结果
    private func analyze() async {
        guard phase != .analyzing, !photos.isEmpty else { return }
        let jpegs = photos.compactMap { $0.compressedForUpload() }
        guard jpegs.count == photos.count else {
            phase = .failed(String(localized: "有照片处理不了，请换一张试试。"))
            return
        }
        analysisStart = .now
        phase = .analyzing
        // 识别要好几秒，先把「记到哪一天」和这几张照片定下来：
        // 就算等待时刚好过了午夜，也还是按下按钮时的那天；结果页显示的就是发给 AI 的这几张
        let day = dayKey()
        let analyzedPhotos = photos
        do {
            // 识别结果（食物名称和那句总结）用 App 现在显示的语言
            let result = try await APIClient.analyze(jpegs: jpegs, lang: AppLanguage.current.apiCode)
            guard !Task.isCancelled else { return }
            if !result.isFood || result.items.isEmpty {
                // 没认出食物：留在这一页说明怎么拍，不打开一个空的结果页、也不给出任何热量
                phase = .notFood
            } else {
                // 完成：热气停下、碗轻轻放大，震一下，稍等一下再打开结果页（不是一下子切走）
                phase = .finishing
                successTick += 1
                try? await Task.sleep(for: .milliseconds(240))
                resultRoute = ResultRoute(result: result, dayKey: day, photos: analyzedPhotos, today: DayMath.startOfDay(.now))
            }
        } catch {
            // 用户点了「取消分析」：已经回到确认照片了，什么都不用说
            guard !Task.isCancelled else { return }
            // 给用户看的是能照着做的一句话（见 APIError）；技术细节 APIClient 已经写进日志
            phase = .failed(error.localizedDescription)
        }
        // 识别用掉了一次（失败时后端可能还回去了），重新问一下还剩几次
        Task { await refreshRemaining() }
    }

    /// 问后端今天还能识别几次（不花钱、不占次数）；问不到就不显示，不打扰用户
    private func refreshRemaining() async {
        if let quota = try? await APIClient.quota() {
            remaining = quota.analyzeRemaining
        }
    }

}

/// 打开识别结果页需要的东西：识别结果、这餐要记到哪一天（20260929 这样的数字）、识别的是哪几张照片、今天是哪天
struct ResultRoute: Hashable {
    let result: AnalyzeResult
    let dayKey: Int
    let photos: [UIImage]
    let today: Date
}

extension View {
    /// 小的操作按钮（重拍、删除）：浅燕麦色的胶囊，至少 44pt 高的点击范围
    fileprivate func actionChip(color: Color) -> some View {
        font(AppTypography.caption.weight(.medium))
            .lineLimit(1)
            .fixedSize()  // 按钮上的字永远一行，不被挤窄
            .foregroundStyle(color)
            .padding(.horizontal, AppSpacing.sm)
            .frame(minHeight: 32)
            .background(AppColors.surfaceSecondary, in: Capsule())
            .frame(minHeight: 44)
            .contentShape(Rectangle())
    }
}
