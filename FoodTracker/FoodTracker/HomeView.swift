//
//  HomeView.swift
//  FoodTracker
//
//  「今日」页：顶部是日期栏（月份 + 一周的日期，左右滑动翻周、点一天看那一天），
//  下面依次是主卡片（还可以吃多少）、快速记录（拍照、相册、手动）、热量提示、今日饮食。
//  新记录（拍照识别或手动添加）都记到正在看的那一天，所以忘了记的往日也能补。
//  拍完照（或从相册选好照片）先到「确认照片」页：可以再拍几张同一餐的照片（最多 4 张），点「开始识别」后，
//  几张照片合并成一份结果，自动跳到结果页（从结果页返回会回到「确认照片」页）。手动添加不需要联网，识别次数用完了也能记。
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
    @State private var photos: [UIImage] = []  // 这一餐的照片（1～4 张），在「确认照片」页里增减
    @State private var pickerItems: [PhotosPickerItem] = []  // 相册里选中的项目（一次最多 4 张）
    @State private var showCamera = false  // 是否打开相机
    @State private var showsPhotoReview = false  // 是否打开「确认照片」页
    #if DEBUG && targetEnvironment(simulator)
    @State private var debugResultRoute: ResultRoute?  // 调试菜单的示例结果：有值时直接打开结果页
    #endif
    @State private var loadFailed = false  // 从相册读照片失败
    @State private var showNoCamera = false  // 是否提示「没有相机」
    @State private var manualEntry: ManualEntryRequest?  // 有值时打开「手动添加」：默认记到哪一餐、哪一天
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
            DayLogView(day: selectedDay, today: today, bodyInfo: profile.bodyInfo, onAddToMeal: { meal in
                openManualEntry(meal: meal)
            }) {
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
                // 拍完照或选好照片：先到「确认照片」页，可以再加几张，再一起识别；结果页由它打开（叠在它上面）
                .navigationDestination(isPresented: $showsPhotoReview) {
                    PhotoReviewView(photos: $photos, dayKey: currentDayKey) {
                        // 保存成功：关掉「确认照片」页（叠在上面的结果页一起关掉）、清掉照片，同一餐不会不小心识别两次
                        showsPhotoReview = false
                    }
                }
                #if DEBUG && targetEnvironment(simulator)
                // 调试菜单的示例结果：不经过「确认照片」页，直接打开结果页
                .navigationDestination(item: $debugResultRoute) { route in
                    ResultView(result: route.result, photos: route.photos, dayKey: route.dayKey, today: route.today) {
                        debugResultRoute = nil
                    }
                }
                #endif
                // 离开「确认照片」页（返回、或者保存完）：照片不再需要了
                .onChange(of: showsPhotoReview) { _, isShowing in
                    if !isShowing { photos = [] }
                }
                // 从相册选了照片之后，把它们读出来，打开「确认照片」页
                .onChange(of: pickerItems) {
                    Task { await loadPickedPhotos() }
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
                // 手动添加：填好后存成一条记录，默认记到正在看的那一天。
                // 用 sheet(item:)：打开时带着「哪一餐、哪一天」，表单第一次出现就是对的
                // （用 isPresented 加另一个状态的话，第一次弹出时可能读到旧的餐次）
                .sheet(item: $manualEntry) { request in
                    ManualEntrySheet(request: request)
                }
                // 全屏打开相机；拍好一张（关掉相机之后）打开「确认照片」页
                .fullScreenCover(isPresented: $showCamera, onDismiss: openPhotoReviewIfNeeded) {
                    CameraPicker { newPhoto in
                        photos = [newPhoto]
                    }
                    .ignoresSafeArea()
                }
                .alert("读取照片失败", isPresented: $loadFailed) {
                    Button("好", role: .cancel) {}
                } message: {
                    Text("读取照片失败，请换一张试试。")
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
                .accessibilityHint("打开月历，选择日期")

                Spacer(minLength: 0)

                // 看往日时才出现
                if !isToday {
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

    /// 快速记录：拍照、相册、手动
    private var quickLogDock: some View {
        QuickLogDock(pickerItems: $pickerItems, onCamera: openCamera, onManual: { openManualEntry() })
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

    /// 打开「手动添加」表单。meal：默认记到哪一餐（从某一餐的 + 打开时）；不传就按现在的时间推荐。
    /// 打开时就把「哪一天」换成数字定下来，填表中途手机换了时区也不会记到别的一天
    private func openManualEntry(meal: MealType? = nil) {
        refreshToday(appBecameActive: false)  // 打开前确认一下今天是哪天（可能刚过午夜）
        manualEntry = ManualEntryRequest(meal: meal ?? suggestedMeal, dayKey: DayMath.dayKey(for: selectedDay))
    }

    /// 识别时记到哪一天：先确认一下今天是哪天（可能刚过午夜），再取正在看的那天
    private func currentDayKey() -> Int {
        refreshToday(appBecameActive: false)
        return DayMath.dayKey(for: selectedDay)
    }

    /// 相机关掉以后：拍到了照片就打开「确认照片」页（取消了就什么都不做）
    private func openPhotoReviewIfNeeded() {
        if !photos.isEmpty && !showsPhotoReview {
            showsPhotoReview = true
        }
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

    /// 从相册选中的项目里读出照片（最多 4 张），打开「确认照片」页
    private func loadPickedPhotos() async {
        let items = pickerItems
        guard !items.isEmpty else { return }
        pickerItems = []  // 清空选择，下次选同一张照片也能生效
        var loaded: [UIImage] = []
        for item in items.prefix(APIClient.maxPhotos) {
            if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                loaded.append(image)
            }
        }
        if loaded.count < min(items.count, APIClient.maxPhotos) { loadFailed = true }
        guard !loaded.isEmpty else { return }
        photos = loaded
        showsPhotoReview = true
    }

    #if DEBUG && targetEnvironment(simulator)
    /// 调试菜单：不识别，直接用示例结果打开结果页（记到正在看的那天）
    private func showSampleResult(_ result: AnalyzeResult) {
        refreshToday(appBecameActive: false)
        debugResultRoute = ResultRoute(result: result, dayKey: DayMath.dayKey(for: selectedDay), photos: [], today: today)
    }
    #endif
}

#Preview {
    HomeView(profile: SampleData.profile)
        .modelContainer(SampleData.previewContainer)
}
