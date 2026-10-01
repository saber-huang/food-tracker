//
//  QuickLogDock.swift
//  FoodTracker
//
//  「今日」页的快速记录：一张卡片，三个动作并排，图标在同一条线上、文字在同一条基线上。
//  「拍照」是主要动作：56pt 的橄榄绿圆、实心相机、半粗的字，下面一行很小的「AI 估算热量」；
//  「相册」「手动」是次要动作：44pt 的燕麦色圆、描边图标、灰色的字。一眼就能看出拍照是主功能。
//  选了照片以后，卡片上方多出一行：照片缩略图 + 「开始识别」；这时「开始识别」是唯一的主要动作，拍照变回次要样式。
//  这里只负责样子：拍照、选照片、识别、手动添加都由「今日」页（HomeView）来做。
//

import PhotosUI
import SwiftUI

struct QuickLogDock: View {
    let photo: UIImage?  // 选好的照片；没选时是 nil
    let isAnalyzing: Bool  // 正在识别：按钮都不能点
    let analyzeRemaining: Int?  // 今天还能识别几次；问不到就不显示
    @Binding var pickerItem: PhotosPickerItem?  // 相册里选中的项目（由 HomeView 读出照片）
    let onCamera: () -> Void
    let onManual: () -> Void
    let onAnalyze: () -> Void
    let onRemovePhoto: () -> Void

    var body: some View {
        VStack(spacing: AppSpacing.lg) {
            if let photo {
                SelectedPhotoRow(
                    photo: photo, isAnalyzing: isAnalyzing, analyzeRemaining: analyzeRemaining, onAnalyze: onAnalyze,
                    onRemove: onRemovePhoto)
            }
            // 三个动作平分一行；每个图标都放在 56pt 高的格子里，圆心在同一条线上，文字在同一条基线上
            HStack(alignment: .top, spacing: 0) {
                Button(action: onCamera) {
                    QuickLogAction(
                        title: "拍照", systemImage: photo == nil ? "camera.fill" : "camera", isPrimary: photo == nil,
                        caption: photo == nil ? "AI 估算热量" : nil)
                }
                .buttonStyle(AppPressStyle())

                // PhotosPicker 是系统自带的相册选择器，不需要申请相册权限
                PhotosPicker(selection: $pickerItem, matching: .images) {
                    QuickLogAction(title: "相册", systemImage: "photo.on.rectangle", isPrimary: false)
                }
                .buttonStyle(AppPressStyle())

                Button(action: onManual) {
                    QuickLogAction(title: "手动", systemImage: "square.and.pencil", isPrimary: false)
                }
                .buttonStyle(AppPressStyle())
            }
            .disabled(isAnalyzing)
            // 用特大字号的人长按按钮，会弹出放大的图标和文字（这一块的字号有上限，见下面）
            .accessibilityShowsLargeContentViewer()
        }
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

/// 选了照片以后的一行：缩略图（右上角的小叉可以移除）+ 「开始识别」+ 还能识别几次
private struct SelectedPhotoRow: View {
    let photo: UIImage
    let isAnalyzing: Bool
    let analyzeRemaining: Int?
    let onAnalyze: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: AppSpacing.md) {
            Image(uiImage: photo)
                .resizable()
                .scaledToFill()
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.thumbnail, style: .continuous))
                .overlay {
                    if isAnalyzing {
                        ZStack {
                            RoundedRectangle(cornerRadius: AppRadius.thumbnail, style: .continuous)
                                .fill(.black.opacity(0.35))
                            ProgressView()
                                .tint(.white)
                        }
                    }
                }
                // 右上角的小叉：选错了照片，或看完结果不想再识别，点它收起这一行（识别中不显示）
                .overlay(alignment: .topTrailing) {
                    if !isAnalyzing {
                        Button("移除照片", systemImage: "xmark.circle.fill", action: onRemove)
                            .labelStyle(.iconOnly)
                            .font(.title3)
                            // 白色的叉 + 半透明黑底，放在什么颜色的照片上都看得清
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, .black.opacity(0.5))
                            .padding(AppSpacing.xxs)
                            .frame(width: 44, height: 44, alignment: .topTrailing)  // 能点的范围够大
                            .offset(x: 14, y: -14)
                            .buttonStyle(.borderless)
                    }
                }
                .accessibilityHidden(true)  // 就是刚选的那张照片

            VStack(alignment: .leading, spacing: 6) {
                Button(action: onAnalyze) {
                    Label("开始识别", systemImage: "sparkles")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(AppColors.onBrand)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(AppColors.brand, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(AppPressStyle())
                .disabled(isAnalyzing)
                .opacity(isAnalyzing ? 0.6 : 1)

                Group {
                    if isAnalyzing {
                        Text("正在识别，通常需要 5～10 秒…")
                    } else if let remaining = analyzeRemaining {
                        // 按下「开始识别」前告诉用户还剩几次；用完了也不挡着按钮，后端会给出明确的说明
                        Text(remaining > 0 ? "今天还可以识别 \(remaining) 次" : "今天的识别次数用完了，可以先用「手动」")
                    }
                }
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

#Preview {
    @Previewable @State var item: PhotosPickerItem?
    ZStack {
        AppBackground()
        QuickLogDock(
            photo: nil, isAnalyzing: false, analyzeRemaining: nil, pickerItem: $item, onCamera: {}, onManual: {},
            onAnalyze: {}, onRemovePhoto: {}
        )
        .padding(AppSpacing.pageMargin)
    }
}
