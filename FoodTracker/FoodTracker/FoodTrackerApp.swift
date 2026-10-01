//
//  FoodTrackerApp.swift
//  FoodTracker
//
//  Created by huang shengkai on 9/28/26.
//

import SwiftData
import SwiftUI
import UIKit

@main
struct FoodTrackerApp: App {
    init() {
        // 顶栏标题：「食谱」「我的」的大标题 30pt（比系统的 34pt 小一点，三个标签页的标题一样大），
        // 颜色用 App 的正文颜色（暖黑），不用纯黑
        let bar = UINavigationBar.appearance()
        let titleColor = UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? AppColors.Pair.textPrimary.dark : AppColors.Pair.textPrimary.light)
        }
        let large = UIFont.systemFont(ofSize: AppTypography.pageTitleSize, weight: .bold)
        bar.largeTitleTextAttributes = [
            .font: UIFontMetrics(forTextStyle: .largeTitle).scaledFont(for: large), .foregroundColor: titleColor,
        ]
        let inline = UIFont.systemFont(ofSize: 17, weight: .semibold)
        bar.titleTextAttributes = [
            .font: UIFontMetrics(forTextStyle: .headline).scaledFont(for: inline), .foregroundColor: titleColor,
        ]
    }

    var body: some Scene {
        WindowGroup {
            RootView()  // 没有资料时显示引导流程，有资料时显示主界面
                // 品牌主色（按钮、开关、可以点的文字、选中的日期）：橄榄绿，见 DesignSystem.swift。
                // Assets 里的 AccentColor 也是这个颜色，但在 iOS 26 以后的系统上只靠它不够，按钮还是系统蓝，
                // 所以这里明确地设一次
                .tint(AppColors.brand)
        }
        // 告诉 SwiftData 要保存哪些数据；数据存在手机本地
        .modelContainer(for: AppModels.all) { result in
            // 数据库打不开时（多半是模型改法不对，见 FoodEntry.swift 开头的规则），SwiftUI 不会闪退，
            // 而是悄悄换成一个空的临时数据库：引导页会重新出现，而且什么都存不进去（原来的数据还在，只是没读出来）。
            // 开发版在这里直接停下，Xcode 里能看到原因；装到手机上的正式版不受影响
            if case .failure(let error) = result {
                assertionFailure("数据库打不开：\(error)")
            }
        }
    }
}

/// App 在手机上保存的所有数据类型。
/// 新加一种类型时加在这里：已有的数据不受影响（SwiftData 会自动升级数据库）
enum AppModels {
    static let all: [any PersistentModel.Type] = [UserProfile.self, FoodEntry.self]
}
