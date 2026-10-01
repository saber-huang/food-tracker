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
        // 顶栏的标题也用圆体，和 App 里其他文字一样（中文标题不变：系统的中文字体没有圆体）
        let bar = UINavigationBar.appearance()
        bar.largeTitleTextAttributes = [.font: Self.roundedFont(size: 34, weight: .bold, style: .largeTitle)]
        bar.titleTextAttributes = [.font: Self.roundedFont(size: 17, weight: .semibold, style: .headline)]
    }

    var body: some Scene {
        WindowGroup {
            RootView()  // 没有资料时显示引导流程，有资料时显示主界面
                // 品牌主色（按钮、开关、可以点的文字、选中的日期、顶栏按钮）和圆体字，配色见 Theme.swift。
                // Assets 里的 AccentColor 也是这个颜色，但在 iOS 26 以后的系统上只靠它不够，按钮还是系统蓝，
                // 所以这里明确地设一次
                .tint(Theme.accent)
                .fontDesign(.rounded)
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

extension FoodTrackerApp {
    /// 系统字体的圆体版本，跟着用户设置的字号一起放大缩小
    fileprivate static func roundedFont(size: CGFloat, weight: UIFont.Weight, style: UIFont.TextStyle) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: weight)
        let rounded = base.fontDescriptor.withDesign(.rounded).map { UIFont(descriptor: $0, size: size) } ?? base
        return UIFontMetrics(forTextStyle: style).scaledFont(for: rounded)
    }
}

/// App 在手机上保存的所有数据类型。
/// 新加一种类型时加在这里：已有的数据不受影响（SwiftData 会自动升级数据库）
enum AppModels {
    static let all: [any PersistentModel.Type] = [UserProfile.self, FoodEntry.self]
}
