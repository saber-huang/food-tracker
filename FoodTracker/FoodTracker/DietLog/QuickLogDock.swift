//
//  QuickLogDock.swift
//  FoodTracker
//
//  「今日」页的快速记录：一张卡片，三个动作并排，图标在同一条线上、文字在同一条基线上。
//  「拍照」是主要动作：56pt 的橄榄绿圆、实心相机、半粗的字，下面一行很小的「AI 估算热量」；
//  「相册」「手动」是次要动作：44pt 的燕麦色圆、描边图标、灰色的字。一眼就能看出拍照是主功能。
//  相册一次可以选 1～4 张同一餐的照片。拍好或选好之后去「确认照片」页（PhotoReviewView），在那里可以再加几张、再识别。
//  这里只负责样子：拍照、选照片、手动添加都由「今日」页（HomeView）来做。
//

import PhotosUI
import SwiftUI

struct QuickLogDock: View {
    @Binding var pickerItems: [PhotosPickerItem]  // 相册里选中的照片（由 HomeView 读出来）
    let onCamera: () -> Void
    let onManual: () -> Void

    var body: some View {
        // 三个动作平分一行；每个图标都放在 56pt 高的格子里，圆心在同一条线上，文字在同一条基线上
        HStack(alignment: .top, spacing: 0) {
            Button(action: onCamera) {
                QuickLogAction(title: "拍照", systemImage: "camera.fill", isPrimary: true, caption: "AI 估算热量")
            }
            .buttonStyle(AppPressStyle())

            // PhotosPicker 是系统自带的相册选择器，不需要申请相册权限；一次最多选 4 张同一餐的照片
            PhotosPicker(
                selection: $pickerItems, maxSelectionCount: APIClient.maxPhotos, selectionBehavior: .ordered,
                matching: .images
            ) {
                QuickLogAction(title: "相册", systemImage: "photo.on.rectangle", isPrimary: false)
            }
            .buttonStyle(AppPressStyle())

            Button(action: onManual) {
                QuickLogAction(title: "手动", systemImage: "square.and.pencil", isPrimary: false)
            }
            .buttonStyle(AppPressStyle())
        }
        // 用特大字号的人长按按钮，会弹出放大的图标和文字（这一块的字号有上限，见下面）
        .accessibilityShowsLargeContentViewer()
        .padding(.horizontal, AppSpacing.xs)
        .padding(.vertical, AppSpacing.md + 2)
        .frame(maxWidth: .infinity)
        .appCard()
        // 字号最多放大到「特特大」：圆形按钮大小固定，字再大就挤不下了（长按按钮可以看放大的文字）
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }
}

/// 快速记录里的一个动作：图标在上（放在 56pt 高的格子里，三个动作的圆心对齐），文字在下（三个动作基线对齐）。
/// 主要动作是 56pt 的橄榄绿圆 + 暖白实心图标 + 半粗的正文色文字，下面可以有一行很小的说明；
/// 次要动作是 44pt 的燕麦色圆 + 棕灰色描边图标 + 灰色文字
private struct QuickLogAction: View {
    let title: LocalizedStringKey
    let systemImage: String
    let isPrimary: Bool
    var caption: LocalizedStringKey?

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        VStack(spacing: AppSpacing.xs) {
            ZStack {
                Circle()
                    .fill(isPrimary ? AppColors.brand : AppColors.surfaceSecondary)
                    .frame(width: isPrimary ? 56 : 44, height: isPrimary ? 56 : 44)
                Image(systemName: systemImage)
                    .font(.system(size: isPrimary ? 22 : 18, weight: .medium))
                    .foregroundStyle(isPrimary ? AppColors.onBrand : AppColors.iconSecondary)
            }
            .frame(height: 56)  // 三个动作的图标格子一样高：圆心对齐，下面的文字也就在同一条基线上
            .accessibilityHidden(true)

            VStack(spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(isPrimary ? .semibold : .medium))
                    .foregroundStyle(isPrimary ? AppColors.textPrimary : AppColors.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if let caption {
                    Text(caption)
                        .font(.caption2)
                        .foregroundStyle(AppColors.textTertiary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
        }
        .frame(maxWidth: .infinity)  // 三个动作平分一行，整块都能点（远大于 44 × 44）
        .contentShape(Rectangle())
        .opacity(isEnabled ? 1 : 0.45)
        .animation(.easeOut(duration: 0.2), value: isPrimary)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    @Previewable @State var items: [PhotosPickerItem] = []
    ZStack {
        AppBackground()
        QuickLogDock(pickerItems: $items, onCamera: {}, onManual: {})
            .padding(AppSpacing.pageMargin)
    }
}
