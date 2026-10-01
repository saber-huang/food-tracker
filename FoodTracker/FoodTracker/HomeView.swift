//
//  HomeView.swift
//  FoodTracker
//
//  「今日」页：顶部是日期栏（月份 + 一周的日期，左右滑动翻周、点一天看那一天），
//  下面依次是主卡片（还可以吃多少）、快速记录（拍照、相册、手动）、热量提示、今日饮食。
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
    @State private var analyzeRemaining: Int?  // 今天还能拍照识别几次；问不到（没网、服务器在唤醒）就不显示
    @State private var pendingAIAction: PendingAIAction?  // 还没同意使用 AI 时，先记下要做的识别，同意后再做
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
                quickLogDock
            } hints: {
                // 热量提示只在看今天时出现，放在快速记录下面
                if isToday {
                    TodayHints(profile: profile, sheet: $hintSheet)
                }
            }
                // 换了一天就整个重新创建，保证列表查的是新的一天
                .id(selectedDay)
                .navigationTitle("今日")  // 只用在结果页的「返回」按钮上；这一页自己的顶部是日期栏
                .toolbar(.hidden, for: .navigationBar)
                // 顶部固定的日期栏：月份 + 一周的日期，和页面背景连在一起，不像系统的日期选择器
                .safeAreaInset(edge: .top, spacing: 0) {
                    dateHeader
                }
                // resultRoute 有值时跳到结果页；用户按「返回」时它会自动变回 nil
                .navigationDestination(item: $resultRoute) { route in
                    ResultView(result: route.result, photo: photo, dayKey: route.dayKey, today: today) {
                        // 保存成功：关掉结果页、清掉照片，同一餐不会不小心识别两次
                        resultRoute = nil
                        photo = nil
                    }
                }
                // 从相册选了照片之后，把它读出来
                .onChange(of: pickerItem) { _, newItem in
                    Task { await loadPhoto(from: newItem) }
                }
                // 选好照片（拍照或从相册）时，顺便问一下今天还能识别几次
                .onChange(of: photo) { _, newPhoto in
                    if newPhoto != nil {
                        Task { await refreshAnalyzeRemaining() }
                    }
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
                // 手机换了时区（比如坐飞机落地）：马上按新的时区重新算「今天」，列表查的也是新的一天。
                // 系统没说这个通知在哪个线程发出，所以回到主线程再改界面的数据
                .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in
                    Task { @MainActor in refreshToday(appBecameActive: false) }
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
                    // 打开表单时就把「哪一天」换成数字定下来，填表中途手机换了时区也不会记到别的一天
                    EntryEditView(
                        draft: EntryDraft(meal: suggestedMeal, dayKey: DayMath.dayKey(for: selectedDay)), title: String(localized: "手动添加"),
                        showsMealPicker: true, showsDate: true
                    ) { item in
                        modelContext.insert(
                            FoodEntry(
                                dayKey: item.dayKey, meal: item.meal, name: item.name, weightG: item.weightG,
                                values: item.values, source: .manual))
                        try? modelContext.save()
                    }
                }
                // 第一次识别前：说明照片会发给谁、怎么处理，同意后才上传（见 AIConsent.swift）
                .aiConsentSheet(pending: $pendingAIAction)
                // 全屏打开相机
                .fullScreenCover(isPresented: $showCamera) {
                    CameraPicker { newPhoto in
                        photo = newPhoto
                    }
                    .ignoresSafeArea()
                }
                .alert("识别失败", isPresented: $showError) {
                    Button("重试") { startAnalyzing() }
                    // 没网、识别次数用完了：不用等，直接手动记
                    Button("改为手动添加") { openManualEntry() }
                    Button("好", role: .cancel) {}
                } message: {
                    Text(errorMessage)
                }
                .alert("没有可用的相机", isPresented: $showNoCamera) {
                    Button("好", role: .cancel) {}
                } message: {
                    Text("这台设备现在不能拍照，请点「相册」。")
                }
        }
    }

    // MARK: - 界面的各个部分

    /// 顶部的日期栏：第一行是月份（点一下打开月历）和「回到今天」，下面是一周的日期。
    /// 背景和页面顶部同一个颜色，底边淡出，内容滑到它下面时被柔和地盖住
    private var dateHeader: some View {
        VStack(spacing: AppSpacing.xs) {
            HStack(spacing: AppSpacing.sm) {
                Button {
                    showMonthPicker = true
                } label: {
                    HStack(spacing: AppSpacing.xxs) {
                        Text(DayMath.monthTitle(for: selectedDay))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppColors.textPrimary)
                        Image(systemName: "chevron.down")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(AppColors.textSecondary)
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(isAnalyzing)  // 识别中不能切换日期
                .accessibilityHint("打开月历，选择日期")

                Spacer(minLength: 0)

                // 看往日时才出现；识别中不能切换日期
                if !isToday && !isAnalyzing {
                    Button("回到今天") { goToToday() }
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(AppColors.brand)
                        .frame(minHeight: 44)
                }

                #if DEBUG && targetEnvironment(simulator)
                // 只在模拟器里出现的调试菜单：不用拍照、不花识别次数就能测试记录功能。
                // 装到手机上的版本里没有这个菜单，不会弄乱真实数据
                Menu {
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
                } label: {
                    Text("调试")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(AppColors.textSecondary)
                        .frame(minWidth: 44, minHeight: 44)
                }
                #endif
            }
            .padding(.horizontal, AppSpacing.pageMargin)

            DateStrip(
                selectedDay: $selectedDay, visibleWeekOffset: $visibleWeekOffset, today: today,
                kcalTarget: profile.targets.calories
            )
            .id(DayMath.weekStart(containing: today))  // 新的一周开始（或换了时区）时整条重建
            .padding(.horizontal, AppSpacing.xs)
            .disabled(isAnalyzing)  // 识别中不能切换日期
            .scrollDisabled(isAnalyzing)
        }
        .padding(.bottom, AppSpacing.sm)
        .background {
            AppColors.backgroundTop
                .ignoresSafeArea(edges: .top)
        }
        // 底边往下淡出一小段：内容滑上来时慢慢消失，不是被一条硬边切掉
        .overlay(alignment: .bottom) {
            LinearGradient(
                colors: [AppColors.backgroundTop, AppColors.backgroundTop.opacity(0)], startPoint: .top, endPoint: .bottom
            )
            .frame(height: AppSpacing.md)
            .offset(y: AppSpacing.md)
            .allowsHitTesting(false)
        }
    }

    /// 快速记录：拍照、相册、手动；选了照片时多出缩略图和「开始识别」
    private var quickLogDock: some View {
        QuickLogDock(
            photo: photo, isAnalyzing: isAnalyzing, analyzeRemaining: analyzeRemaining, pickerItem: $pickerItem,
            onCamera: openCamera, onManual: openManualEntry, onAnalyze: startAnalyzing,
            onRemovePhoto: { photo = nil })
    }

    // MARK: - 功能

    /// 按现在几点，默认选中这一餐（用户可以改）
    private var suggestedMeal: MealType {
        DietLogMath.suggestedMeal(at: .now)
    }

    /// 打开相机。有些设备（比如旧版模拟器）没有相机，先检查一下
    private func openCamera() {
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            showCamera = true
        } else {
            showNoCamera = true
        }
    }

    /// 开始识别。没同意过使用 AI 时，先弹出说明；同意后才真正上传照片
    private func startAnalyzing() {
        AIConsent.perform(pending: $pendingAIAction) { Task { await analyze() } }
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
            showError(message: String(localized: "读取照片失败，请换一张试试。"))
        }
        pickerItem = nil  // 清空选择，下次选同一张照片也能生效
    }

    /// 压缩照片 → 发给后端 → 拿到结果
    private func analyze() async {
        guard let photo else { return }
        guard let jpegData = photo.compressedForUpload() else {
            showError(message: String(localized: "照片处理失败，请换一张试试。"))
            return
        }

        isAnalyzing = true
        defer { isAnalyzing = false }  // 不管成功还是失败，最后都关掉加载动画

        // 识别要好几秒，先把「记到哪一天」定下来（换成数字）：记到正在看的那天；
        // 就算等待时刚好过了午夜、或者手机换了时区，也还是按下按钮时的那天
        refreshToday(appBecameActive: false)
        let dayKey = DayMath.dayKey(for: selectedDay)
        do {
            // 识别结果（食物名称和那句总结）用 App 现在显示的语言
            let result = try await APIClient.analyze(jpegData: jpegData, lang: AppLanguage.current.apiCode)
            refreshToday(appBecameActive: false)
            resultRoute = ResultRoute(result: result, dayKey: dayKey)
        } catch {
            showError(message: error.localizedDescription)
        }
        // 识别用掉了一次（失败时后端可能还回去了），重新问一下还剩几次。
        // 另起一个任务去问：不然上面的 defer 要等它问完才关掉加载状态，按钮会一直是灰的
        Task { await refreshAnalyzeRemaining() }
    }

    /// 问后端今天还能识别几次（不花钱、不占次数）；问不到就不显示，不打扰用户
    private func refreshAnalyzeRemaining() async {
        if let quota = try? await APIClient.quota() {
            analyzeRemaining = quota.analyzeRemaining
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
        resultRoute = ResultRoute(result: result, dayKey: DayMath.dayKey(for: selectedDay))
    }
    #endif
}

/// 跳到结果页需要的两样东西：识别结果，以及这餐要记到哪一天（20260929 这样的数字）
private struct ResultRoute: Hashable {
    let result: AnalyzeResult
    let dayKey: Int
}

/// 次要按钮：灰底黑字（深色模式白字）。主色只留给一个主按钮；
/// 主色的浅底上放主色的小字对比度不够（量出来不到 4.5:1），灰底黑字看得最清楚
#Preview {
    HomeView(profile: SampleData.profile)
        .modelContainer(SampleData.previewContainer)
}
