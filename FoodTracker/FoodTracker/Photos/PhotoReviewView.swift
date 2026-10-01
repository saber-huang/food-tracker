//
//  PhotoReviewView.swift
//  FoodTracker
//
//  拍照识别前的确认页。拍完第一张（或从相册选好）后来到这里，不会马上上传：
//  - 上面是选中那张照片的大图，下面一行是所有照片的缩略图（点一张换着看），最后一格「+」再加一张
//  - 选中的那张可以「重拍」或「删除」；删得一张不剩就回到「今日」页
//  - 一餐最多 4 张：可以补拍同一餐的其他角度、特写，或者同一餐里的别的食物
//  - 底部：「开始识别」（几张时是「识别 3 张照片」）和「再拍一张」。几张照片一起发给 AI，
//    合并成这一餐的一份结果（同一份食物在几张照片里出现只算一次，见后端 food_ai.py）
//  一张照片也可以直接点「开始识别」，和以前一样快。
//  识别的流程（先征得 AI 同意、上传、出错提示）在这里；识别成功后把结果交给「今日」页，由它打开识别结果页。
//

import PhotosUI
import SwiftUI

struct PhotoReviewView: View {
    @Binding var photos: [UIImage]
    /// 识别时记到哪一天：按下「开始识别」时「今日」页正在看的那天（20260929 这样的数字）
    let dayKey: () -> Int
    /// 识别成功：把结果、记到的那一天和识别的这几张照片交给「今日」页
    let onResult: (AnalyzeResult, Int, [UIImage]) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize  // 字号特别大时换一种排法
    /// 「可以补拍不同角度……」的提示只出现一次（第一次来到这一页时）
    @AppStorage("multiPhotoTipShown") private var tipAlreadyShown = false
    @State private var showsTip = false
    @State private var selected = 0  // 大图显示的是第几张
    @State private var camera: CameraTarget?  // 有值时打开相机：再拍一张，或者重拍某一张
    @State private var showsLibrary = false
    @State private var libraryItems: [PhotosPickerItem] = []
    @State private var isAnalyzing = false
    @State private var remaining: Int?  // 今天还能识别几次；问不到就不显示
    @State private var pendingAIAction: PendingAIAction?  // 还没同意使用 AI 时，先记下要做的识别，同意后再做
    @State private var errorMessage: String?  // 识别失败的说明
    @State private var loadFailed = false  // 从相册读照片失败
    @State private var manualEntry: ManualEntryRequest?

    private var canAddMore: Bool { photos.count < APIClient.maxPhotos }
    private var hasCamera: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    var body: some View {
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
        .background { AppBackground(glow: false) }
        .navigationTitle("确认照片")
        .navigationBarTitleDisplayMode(.inline)
        // 识别中不能返回：结果回来时这一页还要在
        .navigationBarBackButtonHidden(isAnalyzing)
        .safeAreaInset(edge: .bottom) { bottomBar }
        .hidesFloatingTabBar()
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
        .onAppear {
            // 第一次只带着一张照片来到这一页时，告诉用户可以补拍；以后不再出现
            // （从相册一次选了好几张的人已经知道可以多张，不用再提示）
            if !tipAlreadyShown && photos.count == 1 {
                showsTip = true
                tipAlreadyShown = true
            }
        }
        .task { await refreshRemaining() }
        // 第一次识别前：说明照片会发给谁、怎么处理，同意后才上传（见 AIConsent.swift）
        .aiConsentSheet(pending: $pendingAIAction)
        .sheet(item: $manualEntry) { request in
            ManualEntrySheet(request: request)
        }
        .alert("识别失败", isPresented: isShowingError) {
            Button("重试") { startAnalyzing() }
            // 没网、识别次数用完了：不用等，直接手动记
            Button("改为手动添加") {
                manualEntry = ManualEntryRequest(meal: DietLogMath.suggestedMeal(at: .now), dayKey: dayKey())
            }
            Button("好", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .alert("读取照片失败", isPresented: $loadFailed) {
            Button("好", role: .cancel) {}
        } message: {
            Text("有照片读不出来，请换一张试试。")
        }
    }

    // MARK: - 页面的几块

    /// 大图：选中的那张照片，完整显示（不裁剪）
    private var preview: some View {
        RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous)
            .fill(AppColors.surfaceSecondary)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if photos.indices.contains(selected) {
                    Image(uiImage: photos[selected])
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: AppRadius.thumbnail, style: .continuous))
                        .padding(AppSpacing.xs)
                }
            }
            .overlay {
                if isAnalyzing {
                    RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous)
                        .fill(.black.opacity(0.25))
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
        .disabled(isAnalyzing)
    }

    /// 缩略图一行：点一张换着看；最后一格「+」再加一张（拍照或从相册选）
    private var thumbnailStrip: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 10) {
                ForEach(photos.indices, id: \.self) { index in
                    Button {
                        selected = index
                    } label: {
                        Image(uiImage: photos[index])
                            .resizable()
                            .scaledToFill()
                            .frame(width: 64, height: 64)
                            .clipShape(RoundedRectangle(cornerRadius: AppRadius.thumbnail, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: AppRadius.thumbnail, style: .continuous)
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
        .disabled(isAnalyzing)
    }

    /// 「+」：有相机时可以选拍照或从相册选，没有相机时直接打开相册
    @ViewBuilder
    private var addTile: some View {
        let tile = RoundedRectangle(cornerRadius: AppRadius.thumbnail, style: .continuous)
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
        .background(AppColors.surfaceSecondary.opacity(0.7), in: RoundedRectangle(cornerRadius: AppRadius.compact, style: .continuous))
        .transition(.opacity)
    }

    /// 底部：「开始识别 / 识别 3 张照片」、「再拍一张」、还能识别几次
    private var bottomBar: some View {
        VStack(spacing: 2) {
            Button(action: startAnalyzing) {
                HStack(spacing: AppSpacing.xs) {
                    if isAnalyzing {
                        ProgressView()
                            .tint(AppColors.onBrand)
                        Text("正在识别…")
                    } else {
                        Image(systemName: "sparkles")
                        Text(Self.analyzeTitle(photoCount: photos.count))
                    }
                }
                .font(.body.weight(.semibold))
                .foregroundStyle(AppColors.onBrand)
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(AppColors.brand, in: RoundedRectangle(cornerRadius: AppRadius.button, style: .continuous))
            }
            .buttonStyle(AppPressStyle())
            .disabled(isAnalyzing || photos.isEmpty)

            if canAddMore && hasCamera && !isAnalyzing {
                Button {
                    camera = .add
                } label: {
                    Label("再拍一张", systemImage: "camera")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(AppColors.brand)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(AppPressStyle())
            }

            Group {
                if isAnalyzing {
                    Text(photos.count > 1 ? "通常需要 10～20 秒" : "通常需要 5～10 秒")
                } else if let remaining {
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
        AIConsent.perform(pending: $pendingAIAction) { Task { await analyze() } }
    }

    /// 压缩每一张照片 → 一起发给后端 → 拿到合并好的一份结果
    private func analyze() async {
        guard !isAnalyzing, !photos.isEmpty else { return }
        let jpegs = photos.compactMap { $0.compressedForUpload() }
        guard jpegs.count == photos.count else {
            errorMessage = String(localized: "照片处理失败，请换一张试试。")
            return
        }
        isAnalyzing = true
        defer { isAnalyzing = false }  // 不管成功还是失败，最后都关掉加载状态
        // 识别要好几秒，先把「记到哪一天」和这几张照片定下来：
        // 就算等待时刚好过了午夜，也还是按下按钮时的那天；结果页显示的就是发给 AI 的这几张
        let day = dayKey()
        let analyzedPhotos = photos
        do {
            // 识别结果（食物名称和那句总结）用 App 现在显示的语言
            let result = try await APIClient.analyze(jpegs: jpegs, lang: AppLanguage.current.apiCode)
            onResult(result, day, analyzedPhotos)
        } catch {
            errorMessage = error.localizedDescription
        }
        // 识别用掉了一次（失败时后端可能还回去了），重新问一下还剩几次。
        // 另起一个任务去问：不然上面的 defer 要等它问完才关掉加载状态
        Task { await refreshRemaining() }
    }

    /// 问后端今天还能识别几次（不花钱、不占次数）；问不到就不显示，不打扰用户
    private func refreshRemaining() async {
        if let quota = try? await APIClient.quota() {
            remaining = quota.analyzeRemaining
        }
    }

    private var isShowingError: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }
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
