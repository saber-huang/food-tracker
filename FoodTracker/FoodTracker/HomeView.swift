//
//  HomeView.swift
//  FoodTracker
//
//  「今日」页：顶部显示每日目标；下面可以拍照或从相册选一张餐食照片，
//  点「开始识别」后交给 AI 识别，识别成功后自动跳到结果页。
//

import PhotosUI
import SwiftData
import SwiftUI

struct HomeView: View {
    /// 用户的个人资料，用来显示每日目标
    let profile: UserProfile

    // @State 是这个页面自己记住的数据，数据一变，界面会自动刷新
    @State private var photo: UIImage?  // 当前选中的照片
    @State private var pickerItem: PhotosPickerItem?  // 相册里选中的项目
    @State private var showCamera = false  // 是否打开相机
    @State private var isAnalyzing = false  // 是否正在识别
    @State private var result: AnalyzeResult?  // 识别结果，有值时自动跳到结果页
    @State private var showError = false  // 是否显示出错提示
    @State private var errorMessage = ""  // 出错提示的内容
    @State private var showNoCamera = false  // 是否提示「没有相机」

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                TargetsCard(bodyInfo: profile.bodyInfo)
                photoArea
                pickButtons
                analyzeButton
            }
            .padding()
            .navigationTitle("今日")
            // result 有值时跳到结果页；从结果页返回时 result 会自动变回 nil
            .navigationDestination(item: $result) { result in
                ResultView(result: result, photo: photo)
            }
            // 从相册选了照片之后，把它读出来
            .onChange(of: pickerItem) { _, newItem in
                Task { await loadPhoto(from: newItem) }
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

    /// 照片区域：没选照片时显示提示，选了就显示照片；识别中盖一层加载动画
    private var photoArea: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(.secondarySystemBackground))

            if let photo {
                Image(uiImage: photo)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 20))
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "fork.knife.circle")
                        .font(.system(size: 60))
                        .foregroundStyle(.tint)
                    Text("拍一张餐食照片\nAI 帮你估算热量和营养")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
            }

            if isAnalyzing {
                RoundedRectangle(cornerRadius: 20)
                    .fill(.black.opacity(0.4))
                VStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.large)
                        .tint(.white)
                    Text("正在识别，通常需要 5～10 秒…")
                        .foregroundStyle(.white)
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    /// 拍照 / 从相册选择 两个按钮
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
                    .frame(maxWidth: .infinity)
            }

            // PhotosPicker 是系统自带的相册选择器，不需要申请相册权限
            PhotosPicker(selection: $pickerItem, matching: .images) {
                Label("从相册选择", systemImage: "photo.on.rectangle")
                    .frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .disabled(isAnalyzing)
    }

    /// 开始识别按钮：选了照片才能点，识别中不能重复点
    private var analyzeButton: some View {
        Button {
            Task { await analyze() }
        } label: {
            Label("开始识别", systemImage: "sparkles")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(photo == nil || isAnalyzing)
    }

    // MARK: - 功能

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

#Preview {
    HomeView(
        profile: UserProfile(
            body: BodyInfo(sex: .male, age: 30, heightCm: 178, weightKg: 75, activity: .moderate, goal: .maintain))
    )
    .modelContainer(for: UserProfile.self, inMemory: true)
}
