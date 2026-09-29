//
//  RootView.swift
//  FoodTracker
//
//  App 的最外层：还没有个人资料时显示引导流程，有了就显示主界面。
//

import SwiftData
import SwiftUI

struct RootView: View {
    /// 从手机本地读取个人资料。@Query 会自动刷新：资料一保存，界面马上切换
    @Query(sort: \UserProfile.updatedAt, order: .reverse) private var profiles: [UserProfile]

    var body: some View {
        if let profile = profiles.first {
            MainTabView(profile: profile)
        } else {
            OnboardingView()
        }
    }
}

/// 主界面：底部的标签栏
struct MainTabView: View {
    let profile: UserProfile

    var body: some View {
        TabView {
            HomeView(profile: profile)
                .tabItem { Label("今日", systemImage: "fork.knife") }

            ProfileView(profile: profile)
                .tabItem { Label("我的", systemImage: "person.crop.circle") }
        }
    }
}
