//
//  HomeView.swift
//  FoodTracker
//
//  「今日」页：顶部是周横条（左右滑动翻周、点一天看那一天），中间是那一天的饮食记录
//  （和目标比较的卡片 + 各餐的记录），底部是记录用的按钮：拍照、从相册选择、手动添加。
//  新记录（拍照识别或手动添加）都记到正在看的那一天，所以忘了记的往日也能补。
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
    @State private var today: Date  // 今天的 0 点；过了午夜会更新
    @State private var selectedDay: Date  // 正在看的那一天（0 点）
    @State private var followsToday = true  // 用户最后一次选的是不是「今天」；过了午夜也不会被改掉
    @State private var visibleWeekOffset: Int? = 0  // 周横条现在显示哪一页：0 = 本周，-1 = 上周 …
    @State private var photo: UIImage?  // 当前选中的照片
    @State private var pickerItem: PhotosPickerItem?  // 相册里选中的项目
    @State private var showCamera = false  // 是否打开相机
    @State private var isAnalyzing = false  // 是否正在识别
    @State private var resultRoute: ResultRoute?  // 识别结果 + 记到哪一天，有值时自动跳到结果页
    @State private var showError = false  // 是否显示出错提示
    @State private var errorMessage = ""  // 出错提示的内容
    @State private var showNoCamera = false  // 是否提示「没有相机」
    @State private var showManualEntry = false  // 是否打开「手动添加」
    @State private var showMonthPicker = false  // 是否打开月历
    @State private var hintSheet: HintSheet?  // 热量提示里的按钮要打开的页面（弹窗挂在一直都在的列表上，提示消失了也不影响）

    init(profile: UserProfile) {
        self.profile = profile
        // 只读一次时钟：「今天」和「正在看的那天」一定是同一天（分开读的话，恰好跨午夜时会差一天）
        let now = DayMath.startOfDay(.now)
        _today = State(initialValue: now)
        _selectedDay = State(initialValue: now)
    }

    /// 正在看的是不是今天
    private var isToday: Bool { selectedDay == today }

    var body: some View {
        NavigationStack {
            DayLogView(day: selectedDay, today: today, bodyInfo: profile.bodyInfo) {
                // 热量提示只在看今天时出现，紧跟在进度卡片下面
                if isToday {
                    TodayHints(profile: profile, sheet: $hintSheet)
                }
            }
                // 换了一天就整个重新创建，保证列表查的是新的一天
                .id(selectedDay)
                .navigationTitle("今日")  // 只用在结果页的「返回」按钮上；顶栏中间显示的是月份
                .navigationBarTitleDisplayMode(.inline)
                // 顶部固定的周横条
                .safeAreaInset(edge: .top) {
                    WeekStripView(
                        selectedDay: $selectedDay, visibleWeekOffset: $visibleWeekOffset, today: today,
                        kcalTarget: profile.targets.calories
                    )
                    .id(DayMath.weekStart(containing: today))  // 新的一周开始（或换了时区）时整条重建
                    .disabled(isAnalyzing)  // 识别中不能切换日期
                    .scrollDisabled(isAnalyzing)
                    .background(.bar)
                }
                // 底部固定的按钮区域
                .safeAreaInset(edge: .bottom) {
                    actionBar
                }
                // resultRoute 有值时跳到结果页；用户按「返回」时它会自动变回 nil
                .navigationDestination(item: $resultRoute) { route in
                    ResultView(result: route.result, photo: photo, day: route.day, today: today) {
                        // 保存成功：关掉结果页、清掉照片，同一餐不会不小心识别两次
                        resultRoute = nil
                        photo = nil
                    }
                }
                .toolbar {
                    // 顶栏中间：正在看的那天所在的月份，点一下打开月历；识别中只显示文字，不能点
                    ToolbarItem(placement: .principal) {
                        if isAnalyzing {
                            Text(DayMath.monthTitle(for: selectedDay))
                                .font(.headline)
                        } else {
                            Button {
                                showMonthPicker = true
                            } label: {
                                HStack(spacing: 4) {
                                    Text(DayMath.monthTitle(for: selectedDay))
                                        .font(.headline)
                                    Image(systemName: "chevron.down")
                                        .font(.caption.weight(.semibold))
                                }
                                .foregroundStyle(.primary)
                            }
                            .accessibilityHint("打开月历，选择日期")
                        }
                    }
                    // 条件写在 ToolbarItem 外面：看今天或识别中时，整个按钮都不出现
                    if !isToday && !isAnalyzing {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("回到今天") { goToToday() }
                        }
                    }
                    #if DEBUG && targetEnvironment(simulator)
                    // 只在模拟器里出现的调试菜单：不用拍照、不花识别次数就能测试记录功能。
                    // 装到手机上的版本里没有这个菜单，不会弄乱真实数据
                    ToolbarItem(placement: .topBarLeading) {
                        Menu("调试") {
                            Button("在这一天插入两条示例记录") {
                                SampleData.insertSampleEntries(into: modelContext, day: selectedDay)
                                try? modelContext.save()
                            }
                            Button("最近两周每天插入示例记录") {
                                SampleData.insertRecentDays(into: modelContext, today: today)
                                try? modelContext.save()
                            }
                            Button("用示例结果") { showSampleResult(SampleData.analyzeResult) }
                            Button("用示例结果（不是食物）") { showSampleResult(SampleData.notFoodResult) }
                        }
                    }
                    #endif
                }
                // 从相册选了照片之后，把它读出来
                .onChange(of: pickerItem) { _, newItem in
                    Task { await loadPhoto(from: newItem) }
                }
                // 真的换了一天才会运行：记住用户最后选的是不是「今天」
                .onChange(of: selectedDay) { _, day in
                    followsToday = (day == today)
                }
                // 回到 App 时，以及系统通知「时间有大变化」（过了午夜、夏令时切换）时，检查今天是不是已经换了一天
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { refreshToday(appBecameActive: true) }
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
                    refreshToday(appBecameActive: false)
                }
                // 热量提示里的按钮：推荐下一餐、编辑资料
                .sheet(item: $hintSheet) { sheet in
                    switch sheet {
                    case .nextMeal(let budget):
                        NextMealSheet(profile: profile, budget: budget)
                    case .editProfile:
                        ProfileEditView(profile: profile)
                    }
                }
                // 月历：选了一天就跳过去
                .sheet(isPresented: $showMonthPicker) {
                    MonthPickerSheet(selectedDay: selectedDay, today: today) { day in
                        jump(to: day)
                    }
                }
                // 手动添加：填好后存成一条记录，记到正在看的那一天
                .sheet(isPresented: $showManualEntry) {
                    EntryEditView(
                        draft: EntryDraft(meal: suggestedMeal, day: selectedDay), title: "手动添加", showsMealPicker: true,
                        showsDate: true
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
                    // 没网、识别次数用完了：不用等，直接手动记
                    Button("改为手动添加") { openManualEntry() }
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

    /// 底部的按钮区域：选了照片时，上面多一行（照片缩略图 + 开始识别）；看往日时先写明记到哪一天
    private var actionBar: some View {
        VStack(spacing: 12) {
            if let caption = DayMath.recordCaption(day: selectedDay, today: today) {
                Label(caption, systemImage: "calendar")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
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
                        // 右上角的小叉：选错了照片，或看完结果不想再识别，点它收起这一行（识别中不显示）
                        .overlay(alignment: .topTrailing) {
                            if !isAnalyzing {
                                // 这里要写 self.photo：外面的 if let photo 里，photo 指的是照片本身，不能改
                                Button("移除照片", systemImage: "xmark.circle.fill") { self.photo = nil }
                                    .labelStyle(.iconOnly)
                                    .font(.title3)
                                    // 白色的叉 + 半透明黑底，放在什么颜色的照片上都看得清
                                    .symbolRenderingMode(.palette)
                                    .foregroundStyle(.white, .black.opacity(0.5))
                                    .padding(4)
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
        // 字号最多放大到「特特大」：再大这一栏会占掉小半个屏幕（和系统的标签栏一样；长按按钮可以看放大的文字）
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
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
                openManualEntry()
            } label: {
                Label("手动添加", systemImage: "square.and.pencil")
            }
        }
        .labelStyle(IconAboveTitleLabelStyle())
        .buttonStyle(.bordered)
        // 用特大字号的人长按按钮，会弹出放大的图标和文字（这一栏的字号有上限，见 actionBar）
        .accessibilityShowsLargeContentViewer()
        // 这一行的高度 = 最高的那个按钮：字号变大、「从相册选择」换行时，三个按钮还是一样高
        .fixedSize(horizontal: false, vertical: true)
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

    /// 打开「手动添加」表单
    private func openManualEntry() {
        refreshToday(appBecameActive: false)  // 打开前确认一下今天是哪天（可能刚过午夜）
        showManualEntry = true
    }

    /// 检查今天是不是换了一天（过了午夜、换了时区、时钟被调过），需要的话更新「今天」和正在看的那天。
    /// appBecameActive：是不是「回到 App」触发的。规则见 DayMath.dayToShow
    private func refreshToday(appBecameActive: Bool) {
        let newToday = DayMath.startOfDay(.now)
        let newDay = DayMath.dayToShow(
            newToday: newToday, selectedDay: selectedDay, followsToday: followsToday, appBecameActive: appBecameActive)
        guard newToday != today || newDay != selectedDay else { return }
        today = newToday
        selectedDay = newDay  // 值没变就不会触发 onChange，所以在前台过午夜时 followsToday 不会被改掉
        visibleWeekOffset = DayMath.weekOffset(of: newDay, relativeTo: newToday)
    }

    /// 「回到今天」：选中今天，周横条滚回本周
    private func goToToday() {
        selectedDay = today
        visibleWeekOffset = 0
    }

    /// 月历里选了一天：选中它，周横条滚到那一周
    private func jump(to day: Date) {
        selectedDay = DayMath.startOfDay(day)
        visibleWeekOffset = DayMath.weekOffset(of: selectedDay, relativeTo: today)
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

        // 识别要好几秒，先把「记到哪一天」定下来：记到正在看的那天；就算等待时刚好过了午夜，也还是按下按钮时的那天
        refreshToday(appBecameActive: false)
        let day = selectedDay
        do {
            // 界面目前只有中文，所以固定要中文结果；以后做英文版时再跟随手机语言
            let result = try await APIClient.analyze(jpegData: jpegData, lang: "zh")
            refreshToday(appBecameActive: false)
            resultRoute = ResultRoute(result: result, day: day)
        } catch {
            showError(message: error.localizedDescription)
        }
    }

    private func showError(message: String) {
        errorMessage = message
        showError = true
    }

    #if DEBUG && targetEnvironment(simulator)
    /// 调试菜单：不识别，直接用示例结果打开结果页（记到正在看的那天）
    private func showSampleResult(_ result: AnalyzeResult) {
        refreshToday(appBecameActive: false)
        resultRoute = ResultRoute(result: result, day: selectedDay)
    }
    #endif
}

/// 跳到结果页需要的两样东西：识别结果，以及这餐要记到哪一天
private struct ResultRoute: Hashable {
    let result: AnalyzeResult
    let day: Date
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)  // 撑满这一行的宽和高（高度由上面的 fixedSize 定）
        .padding(.vertical, 4)
    }
}

#Preview {
    HomeView(profile: SampleData.profile)
        .modelContainer(SampleData.previewContainer)
}
