//
//  RootView.swift
//  FoodTracker
//
//  App 的最外层：还没有个人资料时显示引导流程，有了就显示主界面。
//  「删除所有数据」也在这里做：先离开主界面，再删（见 eraseAllData）。
//

import SwiftData
import SwiftUI

struct RootView: View {
    /// 从手机本地读取个人资料。@Query 会自动刷新：资料一保存，界面马上切换
    @Query(sort: \UserProfile.updatedAt, order: .reverse) private var profiles: [UserProfile]
    @Environment(\.modelContext) private var modelContext
    /// 正在「删除所有数据」：先换成等待画面，主界面的各个页面都关掉了再动手删
    @State private var isErasing = false
    @State private var eraseFailed = false

    var body: some View {
        Group {
            if isErasing {
                // 这个画面出现时，主界面已经不在了：不会有页面再去读马上要删掉的资料
                ProgressView("正在删除…")
                    .task { eraseAllData() }
            } else if let profile = profiles.first {
                MainTabView(profile: profile) { isErasing = true }
            } else {
                OnboardingView()
            }
        }
        // 以前只能用公制：已经有资料的人继续用公制（只在第一次运行这个版本时判断一次）
        .onAppear { UnitSystem.keepMetricForExistingUser(hasProfile: !profiles.isEmpty) }
        .alert("没有删除成功", isPresented: $eraseFailed) {
            Button("好", role: .cancel) {}
        } message: {
            Text("请稍后再试一次。")
        }
    }

    /// 删掉手机上的所有资料和设置；删完 @Query 读不到资料，自动回到引导页
    private func eraseAllData() {
        do {
            try DataEraser.eraseAll(context: modelContext)
        } catch {
            // 没删成功：把这次删了一半的改动撤销，资料保持原样，用户可以再试一次
            modelContext.rollback()
            eraseFailed = true
        }
        isErasing = false
    }
}

/// 主界面：三个标签页，底部是悬浮的标签栏（FloatingTabBar）。
/// 系统自带的标签栏藏起来；每个标签页的内容和翻页记录都由 TabView 保留，切换回来还在原来的位置。
/// 标签栏放在页面下面（不是盖在页面上）：任何页面的最后一行、底部按钮都停在它上面，不会被挡住；
/// 它周围露出的是和页面一样的暖色背景，所以看起来仍然是浮在页面上的一个圆角条。
/// 进到二级页面（食谱详情、识别结果、设置的下一页……）时标签栏藏起来，回到一级页面再出现（见 TabBarVisibility）
struct MainTabView: View {
    let profile: UserProfile
    let onEraseAll: () -> Void  // 「我的」页确认「删除所有数据」后调用

    @State private var selection: AppTab = {
        #if DEBUG && targetEnvironment(simulator)
        // 只在模拟器里：用启动参数 -startTab recipes 直接打开某个标签（截图检查用）
        if let raw = UserDefaults.standard.string(forKey: "startTab"), let tab = AppTab(rawValue: raw) {
            return tab
        }
        #endif
        return .today
    }()
    @State private var tabBar = TabBarVisibility()
    @State private var toasts = ToastCenter()  // 轻提示（「已记录到午餐」「已删除 撤销」），所有页面共用一个

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $selection) {
                HomeView(profile: profile)
                    .tag(AppTab.today)
                    .toolbar(.hidden, for: .tabBar)

                RecipesView(profile: profile)
                    .tag(AppTab.recipes)
                    .toolbar(.hidden, for: .tabBar)

                ProfileView(profile: profile, onEraseAll: onEraseAll)
                    .tag(AppTab.profile)
                    .toolbar(.hidden, for: .tabBar)
            }
            .environment(tabBar)
            // 轻提示显示在页面内容的最下面：标签栏在时就在它上面一点，不会被挡住
            .toastHost(toasts)
            if !tabBar.isHidden {
                FloatingTabBar(selection: $selection)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.2), value: tabBar.isHidden)
        .environment(toasts)
        .background { AppBackground(glow: false) }
        // 一进主界面就悄悄叫醒云端服务器（免费服务器闲置会休眠），用户点识别时就不用等
        .task { await APIClient.warmUp() }
    }
}
