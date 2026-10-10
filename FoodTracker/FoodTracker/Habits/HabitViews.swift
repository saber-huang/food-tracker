//
//  HabitViews.swift
//  FoodTracker
//
//  记录习惯的界面：
//  - HabitStatsRow、HabitBadgesRow：「我的」页「记录习惯」卡片的两行（本周几天、累计几天、最长连续几天 + 一句平静的话；徽章）
//  - AchievementsView：徽章页（从卡片、或新徽章卡片上的「查看全部徽章」进来）
//  - BadgeMedal：一枚徽章。获得了是一枚花边奖章（外圈一圈圆齿，中间是图标），三档颜色越来越深：
//    燕麦色（起步）→ 鼠尾草绿（稳定）→ 橄榄绿（长久，多一道内圈）。
//    还没获得的是虚线圈 + 浅色图标（不只靠颜色区分），旁白读「尚未解锁」
//  说的话只描述记录了几天，不催、不比较、不提「断了」：漏记一天什么都不会变
//

import SwiftData
import SwiftUI

// MARK: - 文案

enum HabitCopy {
    /// 卡片里那一句话：只说这周记了几天
    static func weekLine(daysThisWeek days: Int) -> String {
        switch days {
        case 0: String(localized: "这周还没有记录。想记的时候随时开始就好。")
        case 1...3: String(localized: "这周记录了 \(days) 天。按自己的节奏来就好。")
        case 4...6: String(localized: "这周记录了 \(days) 天，节奏很稳。")
        default: String(localized: "这周每天都有记录。")
        }
    }

    /// 「3 天」「12 天」
    static func days(_ count: Int) -> String {
        String(localized: "\(count) 天")
    }

    /// 本周：「3/7 天」
    static func daysThisWeek(_ count: Int) -> String {
        String(localized: "\(count)/7 天")
    }
}

// MARK: - 「我的」页的两行

/// 第一行：三个数字并排（字号特别大时上下排）+ 一句话
struct HabitStatsRow: View {
    let stats: HabitStats

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            let tiles = Group {
                HabitStatTile(label: String(localized: "本周"), value: HabitCopy.daysThisWeek(stats.daysThisWeek))
                HabitStatTile(label: String(localized: "累计记录"), value: HabitCopy.days(stats.loggedDays))
                HabitStatTile(label: String(localized: "最长连续"), value: HabitCopy.days(stats.longestStreak))
            }
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: AppSpacing.sm) { tiles }
            } else {
                HStack(alignment: .top, spacing: AppSpacing.md) { tiles }
            }
            Text(HabitCopy.weekLine(daysThisWeek: stats.daysThisWeek))
                .font(AppTypography.detail)
                .foregroundStyle(AppColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, AppSpacing.xs)
    }
}

/// 一个数字：上面是名称（小字、灰色），下面是数字（数字大一号，单位小一号、浅一点）
struct HabitStatTile: View {
    let label: String
    let value: String  // 「3/7 天」「12 days」

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xxs) {
            Text(label)
                .font(AppTypography.detail)
                .foregroundStyle(AppColors.textSecondary)
            Text(Self.styled(value))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label + " " + value)  // 「本周 3/7 天」（两段都已经翻译好，直接拼起来）
    }

    /// 数字和「/」用圆体大字，其余（单位）用小一号的灰字。按字符分，中文、英文都适用
    static func styled(_ text: String) -> AttributedString {
        var result = AttributedString()
        for character in text {
            var piece = AttributedString(String(character))
            if character.isNumber || character == "/" {
                piece.font = .system(.title3, design: .rounded, weight: .semibold).monospacedDigit()
                piece.foregroundColor = AppColors.textPrimary
            } else {
                piece.font = .footnote
                piece.foregroundColor = AppColors.textSecondary
            }
            result += piece
        }
        return result
    }
}

/// 第二行：「徽章」+ 获得的几个徽章 +「3/8」+ 小箭头，点了打开徽章页
struct HabitBadgesRow: View {
    let ledger: AchievementLedger
    let action: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// 一行里最多放几个小徽章
    private static let maxShown = 4

    var body: some View {
        let unlocked = Achievement.allCases.filter(ledger.isUnlocked)
        Button(action: action) {
            HStack(spacing: AppSpacing.sm) {
                Text("徽章")
                    .foregroundStyle(AppColors.textPrimary)
                    .fixedSize()  // 不换行（字号很大时被挤成竖排的「徽 / 章」）
                Spacer(minLength: AppSpacing.xs)
                // 字号特别大时放不下，小徽章不显示（数字和箭头还在，点进去能看到全部）
                if !dynamicTypeSize.isAccessibilitySize {
                    HStack(spacing: AppSpacing.xxs) {
                        ForEach(unlocked.suffix(Self.maxShown), id: \.self) { achievement in
                            BadgeMedal(achievement: achievement, isUnlocked: true, size: 30)
                        }
                    }
                }
                Text(verbatim: "\(unlocked.count)/\(Achievement.allCases.count)")
                    .font(AppTypography.number)
                    .foregroundStyle(AppColors.textSecondary)
                AppChevron()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "徽章，已获得 \(unlocked.count) 个，共 \(Achievement.allCases.count) 个"))
        .accessibilityHint(String(localized: "打开徽章页"))
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - 徽章图标

/// 一档徽章的颜色：外圈（圆齿，飘带也用它）、中间的底色、图标。存数值，测试可以直接算对比度
nonisolated struct BadgePalette {
    let ring: ColorPair
    let fill: ColorPair
    let icon: ColorPair

    static func of(_ tier: AchievementTier) -> BadgePalette {
        switch tier {
        case .starter: BadgePalette(ring: AppColors.Pair.oatRim, fill: AppColors.Pair.oatEmpty, icon: AppColors.Pair.iconSecondary)
        case .steady: BadgePalette(ring: AppColors.Pair.protein, fill: AppColors.Pair.brandSoft, icon: AppColors.Pair.brand)
        case .devoted: BadgePalette(ring: AppColors.Pair.brand, fill: AppColors.Pair.brandSoft, icon: AppColors.Pair.brandDeep)
        }
    }
}

/// 一枚徽章：获得了是花边奖章（外圈圆齿 + 中间的图标，中间一圈卡片色的细线把两部分隔开）；
/// 还没获得是虚线圈 + 浅色图标。showsRibbon：下面两条飘带（只在新徽章卡片上的大徽章用）
struct BadgeMedal: View {
    let achievement: Achievement
    let isUnlocked: Bool
    var size: CGFloat = 44
    var showsRibbon = false

    var body: some View {
        let palette = BadgePalette.of(achievement.tier)
        ZStack {
            if isUnlocked {
                if showsRibbon {
                    ribbons(color: Color(palette.ring))
                }
                RosetteShape(scallops: 14, depth: 0.08)
                    .fill(Color(palette.ring))
                Circle()
                    .fill(Color(palette.fill))
                    .padding(size * 0.15)
                Circle()
                    .strokeBorder(AppColors.surfacePrimary, lineWidth: max(1, size * 0.03))
                    .padding(size * 0.15)
                // 最难得到的一档：多一道细细的内圈
                if achievement.tier == .devoted {
                    Circle()
                        .strokeBorder(Color(palette.ring).opacity(0.45), lineWidth: max(0.75, size * 0.014))
                        .padding(size * 0.22)
                }
            } else {
                Circle()
                    .strokeBorder(AppColors.textTertiary, style: StrokeStyle(lineWidth: 1.2, dash: [3, 3]))
                    .padding(size * 0.08)
            }
            Image(systemName: achievement.systemImage)
                .font(.system(size: size * (isUnlocked ? 0.3 : 0.36), weight: .semibold))
                .foregroundStyle(isUnlocked ? Color(palette.icon) : AppColors.textTertiary)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    /// 两条飘带：从奖章后面往左下、右下垂下去，末端剪成燕尾
    private func ribbons(color: Color) -> some View {
        HStack(spacing: size * 0.04) {
            RibbonTail()
                .fill(color.opacity(0.7))
                .frame(width: size * 0.2, height: size * 0.46)
                .rotationEffect(.degrees(16), anchor: .top)
            RibbonTail()
                .fill(color.opacity(0.7))
                .frame(width: size * 0.2, height: size * 0.46)
                .rotationEffect(.degrees(-16), anchor: .top)
        }
        .offset(y: size * 0.5)
    }
}

/// 花边奖章的外圈：一圈圆圆的齿（齿尖是圆的，齿缝是尖的）
struct RosetteShape: Shape {
    var scallops = 14  // 几个齿
    var depth = 0.08  // 齿有多深（占半径的比例）

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        let steps = scallops * 24
        var path = Path()
        for step in 0...steps {
            let angle = Double(step) / Double(steps) * 2 * .pi
            // |cos| 在齿缝处是一个尖角，在齿尖处是圆的
            let r = radius * (1 - depth * (1 - abs(cos(Double(scallops) * angle / 2))))
            let point = CGPoint(x: center.x + r * sin(angle), y: center.y - r * cos(angle))
            if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }
}

/// 一条飘带：长方形，末端剪成燕尾（中间凹进去）
struct RibbonTail: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY - rect.width * 0.55))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

// MARK: - 徽章页

struct AchievementsView: View {
    @Environment(HabitCenter.self) private var habits: HabitCenter?
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let ledger = habits?.ledger ?? AchievementLedger()
        let stats = habits?.stats ?? .empty
        AppForm {
            // 这一页的标题已经是「记录习惯」，第一块不再写标题
            AppFormSection(nil) {
                VStack(alignment: .leading, spacing: AppSpacing.md) {
                    // 两个一行；字号特别大时一个一行
                    let columns = Array(
                        repeating: GridItem(.flexible(), spacing: AppSpacing.md, alignment: .topLeading),
                        count: dynamicTypeSize.isAccessibilitySize ? 1 : 2)
                    LazyVGrid(columns: columns, alignment: .leading, spacing: AppSpacing.md) {
                        HabitStatTile(label: String(localized: "本周"), value: HabitCopy.daysThisWeek(stats.daysThisWeek))
                        HabitStatTile(label: String(localized: "最好的一周"), value: HabitCopy.days(stats.bestWeekDays))
                        HabitStatTile(label: String(localized: "累计记录"), value: HabitCopy.days(stats.loggedDays))
                        HabitStatTile(label: String(localized: "最长连续"), value: HabitCopy.days(stats.longestStreak))
                    }
                    Text(HabitCopy.weekLine(daysThisWeek: stats.daysThisWeek))
                        .font(AppTypography.detail)
                        .foregroundStyle(AppColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(AppSpacing.cardPadding)
            }

            AppFormSection(
                String(localized: "徽章"),
                footer: String(localized: "徽章只和记录有关，和吃多吃少无关。获得以后会一直保留。")
            ) {
                ForEach(Array(Achievement.allCases.enumerated()), id: \.element) { index, achievement in
                    if index > 0 { AppFormDivider() }
                    AchievementRow(achievement: achievement, unlockedDate: ledger.unlockedDate(achievement))
                }
            }
        }
        .navigationTitle(String(localized: "记录习惯"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .hidesFloatingTabBar()  // 二级页面：底部标签栏收起来
        .onAppear { habits?.refresh(context: modelContext) }
    }
}

/// 徽章页的一行：图标、名称、一句话（获得了写做到了什么，没获得写怎么得到）、右边获得的日期
private struct AchievementRow: View {
    let achievement: Achievement
    let unlockedDate: Date?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let isUnlocked = unlockedDate != nil
        HStack(alignment: dynamicTypeSize.isAccessibilitySize ? .top : .center, spacing: AppSpacing.sm) {
            BadgeMedal(achievement: achievement, isUnlocked: isUnlocked, size: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text(achievement.title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(isUnlocked ? AppColors.textPrimary : AppColors.textSecondary)
                Text(isUnlocked ? achievement.detail : achievement.requirement)
                    .font(AppTypography.detail)
                    .foregroundStyle(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                // 字号特别大时，日期放在说明下面（放右边会把说明挤成很窄的一条）
                if dynamicTypeSize.isAccessibilitySize {
                    statusLabel
                }
            }
            Spacer(minLength: AppSpacing.xs)
            if !dynamicTypeSize.isAccessibilitySize {
                statusLabel
                    .multilineTextAlignment(.trailing)
            }
        }
        .padding(.horizontal, AppSpacing.cardPadding)
        .padding(.vertical, AppSpacing.sm)
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var statusLabel: some View {
        Text(statusText)
            .font(AppTypography.caption)
            .foregroundStyle(AppColors.textSecondary)
    }

    /// 右边的小字：获得的日期（「10月2日」），没获得是「未获得」
    private var statusText: String {
        guard let unlockedDate else { return String(localized: "未获得") }
        return DayMath.shortDate(unlockedDate, today: .now)
    }

    /// 旁白：「第一餐，已获得，10月2日。记下了第一餐。」/「尚未解锁：十餐。累计记录 10 餐」
    private var accessibilityText: String {
        guard let unlockedDate else {
            return String(localized: "尚未解锁：\(achievement.title)。\(achievement.requirement)")
        }
        let date = DayMath.shortDate(unlockedDate, today: .now)
        return String(localized: "\(achievement.title)，已获得，\(date)。\(achievement.detail)")
    }
}

#Preview("徽章页") {
    NavigationStack {
        AchievementsView()
    }
    .environment(HabitCenter())
    .modelContainer(for: AppModels.all, inMemory: true)
}
