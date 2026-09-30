//
//  HomeView.swift
//  FoodTracker
//
//  「今日」页：上面是今天的饮食记录（和目标比较的卡片 + 各餐的记录），
//  底部是记录用的按钮：拍照、从相册选择、手动添加。
//  选了照片后点「开始识别」，识别成功后自动跳到结果页；手动添加不需要联网，识别次数用完了也能记。
//

import PhotosUI
import SwiftData
import SwiftUI

struct HomeView: View {
    /// 用户的个人资料，用来算每日目标
    let profile: UserProfile

    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    // @State 是这个页面自己记住的数据，数据一变，界面会自动刷新
    @State private var today = DayMath.startOfDay(.now)  // 今天的 0 点；过了午夜会更新
    @State private var photo: UIImage?  // 当前选中的照片
    @State private var pickerItem: PhotosPickerItem?  // 相册里选中的项目
    @State private var showCamera = false  // 是否打开相机
    @State private var isAnalyzing = false  // 是否正在识别
    @State private var result: AnalyzeResult?  // 识别结果，有值时自动跳到结果页
    @State private var showError = false  // 是否显示出错提示
    @State private var errorMessage = ""  // 出错提示的内容
    @State private var showNoCamera = false  // 是否提示「没有相机」
    @State private var showManualEntry = false  // 是否打开「手动添加」

    var body: some View {
        NavigationStack {
            DayLogView(day: today, today: today, bodyInfo: profile.bodyInfo)
                // 换了一天就整个重新创建，保证列表查的是新的一天
                .id(today)
                .navigationTitle("今日")
                // 底部固定的按钮区域
                .safeAreaInset(edge: .bottom) {
                    actionBar
                }
                // result 有值时跳到结果页；从结果页返回时 result 会自动变回 nil
                .navigationDestination(item: $result) { result in
                    ResultView(result: result, photo: photo)
                }
                .toolbar {
                    #if DEBUG && targetEnvironment(simulator)
                    // 只在模拟器里出现的调试菜单：不用拍照、不花识别次数就能测试记录功能。
                    // 装到手机上的版本里没有这个菜单，不会弄乱真实数据
                    ToolbarItem(placement: .topBarLeading) {
                        Menu("调试") {
                            Button("插入两条示例记录") {
                                SampleData.insertSampleEntries(into: modelContext, day: today)
                                try? modelContext.save()
                            }
                        }
                    }
                    #endif
                }
                // 从相册选了照片之后，把它读出来
                .onChange(of: pickerItem) { _, newItem in
                    Task { await loadPhoto(from: newItem) }
                }
                // 回到 App 时，以及系统通知「日期变了」（比如过了午夜）时，检查今天是不是已经换了一天
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { refreshToday() }
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
                    refreshToday()
                }
                // 手动添加：填好后存成一条记录
                .sheet(isPresented: $showManualEntry) {
                    EntryEditView(
                        draft: EntryDraft(meal: suggestedMeal, day: today), title: "手动添加", showsMealPicker: true, showsDate: true
                    ) { item in
                        modelContext.insert(
                            FoodEntry(
                                day: item.day, meal: item.meal, name: item.name, weightG: item.weightG, values: item.values,
                                source: .manual))
                        try? modelContext.save()
                    }
                }
                // 全屏打开相机
                .fullScreenCover(isPresented: $showCamera) {
                    CameraPicker { newPhoto in
                        photo = newPhoto
                    }
                    .ignoresSafeArea()
                }
                .alert("识别失败", isPresented: $showError) {
                    Button("重试") { Task { await analyze() } }
                    Button("好", role: .cancel) {}
                } message: {
                    Text(errorMessage)
                }
                .alert("没有可用的相机", isPresented: $showNoCamera) {
                    Button("好", role: .cancel) {}
                } message: {
                    Text("这台设备现在不能拍照，请点「从相册选择」。")
                }
        }
    }

    // MARK: - 界面的各个部分

    /// 底部的按钮区域：选了照片时，上面多一行（照片缩略图 + 开始识别）
    private var actionBar: some View {
        VStack(spacing: 12) {
            if let photo {
                HStack(spacing: 12) {
                    Image(uiImage: photo)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 72, height: 72)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay {
                            if isAnalyzing {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(.black.opacity(0.4))
                                    ProgressView()
                                        .tint(.white)
                                }
                            }
                        }
                    VStack(alignment: .leading, spacing: 6) {
                        analyzeButton
                        if isAnalyzing {
                            Text("正在识别，通常需要 5～10 秒…")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            pickButtons
        }
        .padding()
        .background(.bar)
    }

    /// 拍照 / 从相册选择 / 手动添加 三个按钮（图标在上、文字在下，小屏幕的手机也放得下）
    private var pickButtons: some View {
        HStack(spacing: 12) {
            Button {
                // 有些设备（比如旧版模拟器）没有相机，先检查一下
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    showCamera = true
                } else {
                    showNoCamera = true
                }
            } label: {
                Label("拍照", systemImage: "camera")
            }

            // PhotosPicker 是系统自带的相册选择器，不需要申请相册权限
            PhotosPicker(selection: $pickerItem, matching: .images) {
                Label("从相册选择", systemImage: "photo.on.rectangle")
            }

            Button {
                refreshToday()  // 打开前确认一下今天是哪天（可能刚过午夜）
                showManualEntry = true
            } label: {
                Label("手动添加", systemImage: "square.and.pencil")
            }
        }
        .labelStyle(IconAboveTitleLabelStyle())
        .buttonStyle(.bordered)
        .disabled(isAnalyzing)
    }

    /// 开始识别按钮：识别中不能重复点
    private var analyzeButton: some View {
        Button {
            Task { await analyze() }
        } label: {
            Label("开始识别", systemImage: "sparkles")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(isAnalyzing)
    }

    // MARK: - 功能

    /// 按现在几点，默认选中这一餐（用户可以改）
    private var suggestedMeal: MealType {
        DietLogMath.suggestedMeal(hour: DayMath.calendar.component(.hour, from: .now))
    }

    /// 如果已经过了午夜，把「今天」换成新的一天
    private func refreshToday() {
        let newToday = DayMath.startOfDay(.now)
        if newToday != today { today = newToday }
    }

    /// 从相册选中的项目里读出照片
    private func loadPhoto(from item: PhotosPickerItem?) async {
        guard let item else { return }
        if let data = try? await item.loadTransferable(type: Data.self),
            let image = UIImage(data: data)
        {
            photo = image
        } else {
            showError(message: "读取照片失败，请换一张试试。")
        }
        pickerItem = nil  // 清空选择，下次选同一张照片也能生效
    }

    /// 压缩照片 → 发给后端 → 拿到结果
    private func analyze() async {
        guard let photo else { return }
        guard let jpegData = photo.compressedForUpload() else {
            showError(message: "照片处理失败，请换一张试试。")
            return
        }

        isAnalyzing = true
        defer { isAnalyzing = false }  // 不管成功还是失败，最后都关掉加载动画

        do {
            // 界面目前只有中文，所以固定要中文结果；以后做英文版时再跟随手机语言
            result = try await APIClient.analyze(jpegData: jpegData, lang: "zh")
        } catch {
            showError(message: error.localizedDescription)
        }
    }

    private func showError(message: String) {
        errorMessage = message
        showError = true
    }
}

/// 按钮上图标在上、文字在下（系统没有现成的这种样式，自己定义一个）
private struct IconAboveTitleLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(spacing: 4) {
            configuration.icon
                .font(.title3)
            configuration.title
                .font(.caption)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }
}

#Preview {
    HomeView(profile: SampleData.profile)
        .modelContainer(SampleData.previewContainer)
}
