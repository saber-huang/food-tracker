//
//  MealCard.swift
//  FoodTracker
//
//  「今日饮食」里的每一餐（早餐、午餐、晚餐、加餐）：
//  - 记过的一餐是一张完整的卡片（底色比「快速记录」轻一档）：
//    MealCardHeader（餐次图标，图标底色是这一餐很淡的分类色；早餐 / 午餐…；这一餐的千卡）
//    MealRow（一条记录一行：名称，右边是千卡和小箭头；点一下修改，左滑删除。没吃完的名称下面写「◔ 吃了一半」）
//    AggregatedFoodRow（同一种食物记了几次时合并成一行「米饭 ×2」，点一下展开）+ MealMemberRow（展开后的每一条）
//    MealCardFooter（最下面一行：这一餐的蛋白质、碳水、脂肪，右边一个小按钮「没吃完？」，打开 LeftoversSheet）
//  - 还没记的一餐最轻：没有底色、只有一圈很淡的边，EmptyMealRow「早餐 还没有记录」，右边一个 +，点了直接给这一餐手动添加
//  不读字也能一眼看出哪一餐吃了、哪一餐还没吃。层级靠底色、字号、颜色和缩进，不靠阴影和分隔线。
//  字号特别大（辅助功能字号）时，千卡放到名称下面一行：并排放的话名称会被挤成一个字一行。
//

import SwiftUI

/// 名称和千卡：平时并排（千卡靠右），字号特别大时上下两行（千卡在名称下面）
private struct NameAndKcalLayout<Name: View, Kcal: View>: View {
    @ViewBuilder let name: Name
    @ViewBuilder let kcal: Kcal

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 2) {
                name
                kcal
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack(alignment: .firstTextBaseline, spacing: AppSpacing.xs) {
                name
                Spacer(minLength: AppSpacing.xs)
                kcal
            }
        }
    }
}

/// 记过的一餐的第一行：图标、早餐 / 午餐…，右边是这一餐合计的千卡
struct MealCardHeader: View {
    let meal: MealType
    let kcal: Double

    var body: some View {
        HStack(alignment: .center, spacing: AppSpacing.sm) {
            AppIconTile(systemImage: meal.systemImage, tint: meal.tint)
            NameAndKcalLayout {
                Text(meal.title)
                    .font(AppTypography.mealTitle)
                    .foregroundStyle(AppColors.textPrimary)
            } kcal: {
                Text("\(kcal.noDecimal) 千卡")
                    .font(AppTypography.number)
                    .foregroundStyle(AppColors.textPrimary)
                    .fixedSize()
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// 一条记录：名称，右边是千卡和小箭头（点了可以修改）。没吃完的名称下面多一行「◔ 吃了一半」，千卡是吃下去的
struct MealRow: View {
    let entry: FoodEntry

    var body: some View {
        HStack(alignment: .center, spacing: AppSpacing.xs) {
            NameAndKcalLayout {
                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.name)
                        .font(AppTypography.itemName)
                        .foregroundStyle(AppColors.textPrimary)
                        .lineLimit(2)  // 名字很长时最多两行
                    if let fraction = entry.eatenFraction {
                        EatenTag(fraction: fraction)
                    }
                }
            } kcal: {
                Text("\(entry.caloriesKcal.noDecimal) 千卡")
                    .font(AppTypography.numberSmall)
                    .foregroundStyle(AppColors.textSecondary)
                    .fixedSize()  // 千卡数永远完整显示，名字太长时让名字换行
            }
            AppChevron()
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())  // 整行都能点
        // 旁白多读一点：重量、是不是来自食谱（屏幕上为了干净只写名称和千卡）
        .accessibilityElement(children: .combine)
        .accessibilityValue(detail)
    }

    /// 「来自食谱 · 1 碗 · 约 150 克」：只给旁白读（「吃了一半」屏幕上写着，旁白跟着名称读出来）
    private var detail: String {
        var parts: [String] = []
        if entry.source == .recipe { parts.append(String(localized: "来自食谱")) }
        if let portion = entry.portionText { parts.append(portion) }
        return parts.joined(separator: " · ")
    }
}

/// 没吃完的小标签：一个小饼图（吃掉的那一块是燕麦色）+「吃了一半」
struct EatenTag: View {
    let fraction: Double

    @ScaledMetric(relativeTo: .caption) private var pieSize: CGFloat = 11  // 小饼图跟着字号变大

    var body: some View {
        HStack(spacing: AppSpacing.xxs) {
            EatenPie(fraction: fraction)
                .frame(width: pieSize, height: pieSize)
            Text(EatenPortion.itemLabel(fraction))
        }
        .font(AppTypography.caption.weight(.medium))
        .foregroundStyle(AppColors.textSecondary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(EatenPortion.spokenItemLabel(fraction))
    }
}

/// 小饼图：一圈碗沿色的细边，吃掉的那一块从 12 点钟方向顺时针填上
struct EatenPie: View {
    let fraction: Double

    var body: some View {
        ZStack {
            Circle().fill(AppColors.oatEmpty)
            PieSlice(fraction: fraction).fill(AppColors.oatMark)
            Circle().strokeBorder(AppColors.oatRim, lineWidth: 1)
        }
        .accessibilityHidden(true)
    }
}

/// 从 12 点钟方向顺时针画的扇形（fraction = 0.25 是右上的四分之一）
struct PieSlice: Shape {
    var fraction: Double

    var animatableData: Double {
        get { fraction }
        set { fraction = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let clamped = min(max(fraction, 0), 1)
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        var path = Path()
        guard clamped > 0 else { return path }
        guard clamped < 1 else {
            path.addEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
            return path
        }
        path.move(to: center)
        path.addArc(
            center: center, radius: radius, startAngle: .degrees(-90), endAngle: .degrees(-90 + 360 * clamped), clockwise: false)
        path.closeSubpath()
        return path
    }
}

/// 同一种食物记了几次（名字一样、份量和热量差不多）：合并成一行「米饭 ×2」，右边是合计的千卡。
/// 点一下展开，下面列出每一条（可以分别修改、删除）；再点一下收起
struct AggregatedFoodRow: View {
    let name: String
    let count: Int
    let totalKcal: Double
    let isExpanded: Bool

    var body: some View {
        HStack(alignment: .center, spacing: AppSpacing.xs) {
            NameAndKcalLayout {
                // 「×2」紧跟在名字后面、跟着一起换行，不会被挤到单独一行
                (Text(name).foregroundStyle(AppColors.textPrimary)
                    + Text(verbatim: " ×\(count)").font(AppTypography.numberSmall).foregroundStyle(AppColors.textSecondary))
                    .font(AppTypography.itemName)
                    .lineLimit(2)
            } kcal: {
                Text("\(totalKcal.noDecimal) 千卡")
                    .font(AppTypography.numberSmall)
                    .foregroundStyle(AppColors.textSecondary)
                    .fixedSize()
            }
            Image(systemName: "chevron.down")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(AppColors.textTertiary)
                .rotationEffect(.degrees(isExpanded ? 180 : 0))
                .accessibilityHidden(true)
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "\(name)，\(count) 份，共 \(totalKcal.noDecimal) 千卡"))
        .accessibilityHint(isExpanded ? String(localized: "收起") : String(localized: "展开查看每一条"))
    }
}

/// 合并的那一行展开后的每一条：份量和千卡（名字和上面一样，不重复写），点一下修改
struct MealMemberRow: View {
    let entry: FoodEntry

    var body: some View {
        HStack(alignment: .center, spacing: AppSpacing.xs) {
            NameAndKcalLayout {
                Text(detail)
                    .font(AppTypography.detail)
                    .foregroundStyle(AppColors.textSecondary)
            } kcal: {
                Text("\(entry.caloriesKcal.noDecimal) 千卡")
                    .font(AppTypography.numberSmall)
                    .foregroundStyle(AppColors.textSecondary)
                    .fixedSize()
            }
            AppChevron()
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(String(localized: "\(entry.name)，\(detail)"))
        .accessibilityHint("修改这一条")
    }

    /// 「1 碗 · 约 150 克 · 吃了一半 · 来自食谱」；什么都没有时写「1 份」
    private var detail: String {
        var parts: [String] = []
        if let portion = entry.portionText { parts.append(portion) }
        if let eaten = entry.eatenLabel { parts.append(eaten) }
        if entry.source == .recipe { parts.append(String(localized: "来自食谱")) }
        return parts.isEmpty ? String(localized: "1 份") : parts.joined(separator: " · ")
    }
}

/// 记过的一餐的最后一行：左边是这一餐的三大营养素（三种都是 0，也就是只填了热量时不写），
/// 右边一个小按钮「没吃完？」（这一餐已经调过吃了多少时写「吃了多少」），点了打开 LeftoversSheet。
/// 一行放不下时（英文、字号很大）营养素在上、按钮在下一行，营养素不会被挤成两行
struct MealCardFooter: View {
    let total: NutrientValues?  // nil = 不写营养素
    let isAdjusted: Bool  // 这一餐有没吃完的
    let onLeftovers: () -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: AppSpacing.xs) {
                if let total {
                    MealMacroFooter(total: total)
                } else {
                    Spacer(minLength: 0)
                }
                leftoversButton
            }
            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                if let total {
                    MealMacroFooter(total: total)
                }
                leftoversButton
            }
        }
    }

    private var leftoversButton: some View {
        Button(action: onLeftovers) {
            // 图标和字自己排：在列表的一行里，系统的 Label 会只画图标、不画字（iOS 27 模拟器上看到的）
            HStack(spacing: AppSpacing.xxs) {
                Image(systemName: "circle.lefthalf.filled")
                Text(isAdjusted ? String(localized: "吃了多少") : String(localized: "没吃完？"))
            }
            .font(AppTypography.caption.weight(.semibold))
            .foregroundStyle(AppColors.brandDeep)  // 深色模式下主色在浅绿底上不够清楚，用深橄榄
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, AppSpacing.sm)
            .frame(minHeight: 28)
            .background(AppColors.brandSoft, in: Capsule())
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(AppPressStyle())
        .accessibilityLabel(isAdjusted ? String(localized: "这餐吃了多少") : String(localized: "没吃完？记录吃了多少"))
    }
}

/// 这一餐的三大营养素（MealCardFooter 的左边）
struct MealMacroFooter: View {
    let total: NutrientValues

    var body: some View {
        Text("蛋白质 \(total.proteinG.noDecimal) · 碳水 \(total.carbsG.noDecimal) · 脂肪 \(total.fatG.noDecimal) 克")
            .font(AppTypography.caption)
            .foregroundStyle(AppColors.textSecondary)
            .monospacedDigit()
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 还没记的一餐：最轻的一条（没有底色，只有一圈很淡的边，见 DayLogView），「早餐  还没有记录」，右边一个 +（点整条都可以）
struct EmptyMealRow: View {
    let meal: MealType

    var body: some View {
        HStack(alignment: .center, spacing: AppSpacing.sm) {
            Image(systemName: meal.systemImage)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(AppColors.textTertiary)
                .frame(width: 28, height: 28)
                .accessibilityHidden(true)
            HStack(alignment: .firstTextBaseline, spacing: AppSpacing.xs) {
                Text(meal.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(AppColors.textSecondary)
                Text("还没有记录")
                    .font(AppTypography.detail)
                    .foregroundStyle(AppColors.textTertiary)
            }
            Spacer(minLength: AppSpacing.xs)
            Image(systemName: "plus")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppColors.brand)
                .frame(width: 30, height: 30)
                .overlay(Circle().strokeBorder(AppColors.brand.opacity(0.35), lineWidth: 1))
                .accessibilityHidden(true)
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(meal.title)，还没有记录")
        .accessibilityHint("手动添加\(meal.title)")
    }
}
