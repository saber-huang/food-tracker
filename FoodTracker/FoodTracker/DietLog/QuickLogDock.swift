//
//  QuickLogDock.swift
//  FoodTracker
//
//  「今日」页的快速记录：一个完整的卡片，里面并排三个动作——拍照（主要动作，橄榄绿的圆）、
//  相册、手动（次要动作，燕麦色的圆）。三个动作共用一个容器，不各自是一个大按钮。
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
            HStack(alignment: .top, spacing: 0) {
                Button(action: onCamera) {
                    QuickLogActionLabel(title: "拍照", systemImage: "camera", isPrimary: photo == nil)
                }
                .buttonStyle(QuickLogPressStyle())

                // PhotosPicker 是系统自带的相册选择器，不需要申请相册权限
                PhotosPicker(selection: $pickerItem, matching: .images) {
                    QuickLogActionLabel(title: "相册", systemImage: "photo.on.rectangle", isPrimary: false)
                }
                .buttonStyle(QuickLogPressStyle())

                Button(action: onManual) {
                    QuickLogActionLabel(title: "手动", systemImage: "square.and.pencil", isPrimary: false)
                }
                .buttonStyle(QuickLogPressStyle())
            }
            .disabled(isAnalyzing)
            // 用特大字号的人长按按钮，会弹出放大的图标和文字（这一块的字号有上限，见下面）
            .accessibilityShowsLargeContentViewer()
        }
        .padding(.horizontal, AppSpacing.sm)
        .padding(.vertical, AppSpacing.md - 2)
        .frame(maxWidth: .infinity)
        .appCard(radius: AppRadius.dock)
        // 字号最多放大到「特特大」：圆形按钮大小固定，字再大就挤不下了（长按按钮可以看放大的文字）
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }
}

/// 一个动作：圆形图标在上，文字在下。主要动作是橄榄绿实心圆 + 暖白图标；次要动作是燕麦色圆 + 棕灰图标
private struct QuickLogActionLabel: View {
    let title: LocalizedStringKey
    let systemImage: String
    let isPrimary: Bool

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        VStack(spacing: 6) {
            Circle()
                .fill(isPrimary ? AppColors.brand : AppColors.surfaceSecondary)
                .frame(width: 50, height: 50)
                .overlay {
                    Image(systemName: systemImage)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(isPrimary ? AppColors.onBrand : AppColors.iconSecondary)
                }
            Text(title)
                .font(AppTypography.actionLabel)
                .foregroundStyle(AppColors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, minHeight: 72)  // 每个动作占三分之一宽，整块都能点（远大于 44 × 44）
        .contentShape(Rectangle())
        .opacity(isEnabled ? 1 : 0.45)
        .animation(.easeOut(duration: 0.2), value: isPrimary)
    }
}

/// 按下去的反馈：轻轻缩小到 0.97、稍微变淡；系统设置了「减弱动态效果」时只变淡不缩放
struct QuickLogPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
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
                .buttonStyle(QuickLogPressStyle())
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
        .padding(.horizontal, AppSpacing.xs)
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
