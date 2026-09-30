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

/// 主界面：底部的标签栏
struct MainTabView: View {
    let profile: UserProfile
    let onEraseAll: () -> Void  // 「我的」页确认「删除所有数据」后调用

    var body: some View {
        TabView {
            HomeView(profile: profile)
                .tabItem { Label("今日", systemImage: "fork.knife") }

            RecipesView(profile: profile)
                .tabItem { Label("食谱", systemImage: "book") }

            ProfileView(profile: profile, onEraseAll: onEraseAll)
                .tabItem { Label("我的", systemImage: "person.crop.circle") }
        }
        // 一进主界面就悄悄叫醒云端服务器（免费服务器闲置会休眠），用户点识别时就不用等
        .task { await APIClient.warmUp() }
    }
}
