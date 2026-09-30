//
//  HintCopy.swift
//  FoodTracker
//
//  热量提示的全部文案都在这个文件里：想改措辞只改这里，不用碰逻辑代码。
//  写文案的原则：提前提醒；看整体趋势；给下一步建议；不制造负罪感。
//  不能建议少吃来补偿、不能建议跳过某一餐、不能建议靠运动消耗掉；也不用「超标」「警告」「失败」这类词。
//  FoodTrackerTests/HintCopyTests.swift 会检查下面每一条文案都没有用到这些词。改完文案按 ⌘U 跑一下；
//  新加一条文案时，在文件最底部的 allSamples 里加一个样例。
//
//  数字的写法：热量都是估算值，所以「今天还剩多少」「多了多少」都四舍五入到 10 千卡并加「约」；
//  每周小结里平均值四舍五入到 10，目标取整（和首页一致），差值就是这两个数相减。
//  餐名（早餐 / 午餐 / 晚餐）由调用方传入。
//

import Foundation

nonisolated enum HintCopy {

    // MARK: - 数字格式（1463 → "1,463"，和首页一致）

    private static func n(_ value: Int) -> String { value.formatted() }

    // MARK: - 餐名

    /// 句子中间的餐名：英文里用小写（「save it for dinner」），中文不变。标题和按钮上的餐名照常大写
    private static func mealInSentence(_ name: String) -> String {
        AppLanguage.current == .en ? name.lowercased() : name
    }

    // MARK: - 今日 · 接近目标（摄入 ≥ 85%，且还有正餐没记录、还来得及吃）

    /// 例：「今天离目标还有约 210 千卡，可以留给晚餐。晚餐照常吃就好，稍微多一点也没关系。」
    /// 剩下不到 100 千卡时不写数字（「还有约 10 千卡，可以留给晚餐」读起来不像话）
    static func nearLimit(remainingKcal: Int, mealName: String) -> String {
        if remainingKcal < 100 {
            return String(localized: "今天的摄入已经接近目标。\(mealInSentence(mealName))照常吃就好，稍微多一点也没关系。", table: "HintCopy")
        }
        return String(localized: "今天离目标还有约 \(n(remainingKcal)) 千卡，可以留给\(mealInSentence(mealName))。\(mealInSentence(mealName))照常吃就好，稍微多一点也没关系。", table: "HintCopy")
    }
    /// 按钮：打开「推荐下一餐」页面
    static let recommendNextMeal = String(localized: "推荐下一餐", table: "HintCopy")
    /// 读屏软件（VoiceOver）念的按钮说明
    static let recommendNextMealA11y = String(localized: "打开一份按今天剩下的热量推荐的食谱", table: "HintCopy")

    // MARK: - 今日 · 到达或多于目标

    /// byKcal 是四舍五入到 10 的数；不到 50 千卡算「差不多就在目标线上」，不写数字。
    /// nextMealName 是还没记录、还来得及吃的那一餐；nil 表示今天的正餐都记过了（或都过了时间）。
    static func over(byKcal: Int, nextMealName: String?) -> String {
        if byKcal < 50 {
            if let meal = nextMealName {
                return String(localized: "今天的摄入差不多就在目标线上。\(mealInSentence(meal))照常吃、照常记录就好，稍微多一点也没关系。", table: "HintCopy")
            }
            return String(localized: "今天的摄入差不多就在目标线上。明天照常吃、照常记录就好。", table: "HintCopy")
        }
        if let meal = nextMealName {
            return String(localized: "今天比目标多了约 \(n(byKcal)) 千卡。偶尔一天这样很正常，对整体趋势没什么影响；\(mealInSentence(meal))照常吃、照常记录就好。", table: "HintCopy")
        }
        return String(localized: "今天比目标多了约 \(n(byKcal)) 千卡。一天的数字有起伏很正常，看的是几周的平均；明天照常吃、照常记录就好。", table: "HintCopy")
    }

    // MARK: - 每周小结（每周一次，回顾上一个完整的周一～周日）

    static let weeklyTitle = String(localized: "上周小结", table: "HintCopy")
    /// 数字行，例：「平均每天约 1,510 千卡（目标 1,463）· 按记录较完整的 5 天计算」
    static func weeklyNumbers(averageKcal: Int, targetKcal: Int, daysCounted: Int) -> String {
        String(localized: "平均每天约 \(n(averageKcal)) 千卡（目标 \(n(targetKcal))）· 按记录较完整的 \(daysCounted) 天计算", table: "HintCopy")
    }
    /// 平均和目标相差不超过 10%
    static let weeklyOnTarget = String(localized: "这一周走得很稳，平均和目标基本一致。保持现在的节奏就好，不需要做任何调整。", table: "HintCopy")
    /// 平均比目标高 10% 以上；differenceKcal 传正数
    static func weeklyAbove(differenceKcal: Int) -> String {
        String(localized: "平均每天比目标高约 \(n(differenceKcal)) 千卡。一周有起伏很正常，看整体趋势比盯着某一天更有用；这周照常吃、照常记录就好。", table: "HintCopy")
    }
    /// 平均比目标低 10% 以上；differenceKcal 传正数（低了多少）
    static func weeklyBelow(differenceKcal: Int) -> String {
        String(localized: "平均每天比目标低约 \(n(differenceKcal)) 千卡。吃够也很重要：目标本身就是为你算好的量，不用再往下压；如果只是有几餐没记录，那也很常见。", table: "HintCopy")
    }
    /// 上周记录较完整的只有 1～2 天，算不出有参考价值的平均
    static func weeklyFewDays(daysCounted: Int) -> String {
        String(localized: "上周有 \(daysCounted) 天的记录比较完整，还算不出有参考价值的平均。这完全没关系，记录多少都有用；这周想记的时候记就好。", table: "HintCopy")
    }
    /// 第一个完整天之后改过资料时追加的一句（改的时间可能在上周，也可能在这周）
    static let weeklyTargetChangedNote = String(localized: "上周以来修改过资料，上面的对比按现在的目标计算。", table: "HintCopy")
    /// 平均明显高于目标（≥ 120%）且目标是减脂时追加的一句，下面放「调整目标」按钮
    static let weeklyAdjustSuggestion = String(localized: "如果觉得现在的目标有点紧，可以把它调到更容易坚持的水平。", table: "HintCopy")
    /// 按钮
    static let weeklyDismiss = String(localized: "知道了", table: "HintCopy")

    // MARK: - 连续多天明显高于目标（连续 3 天 ≥ 120%）

    static func adjustTarget(consecutiveDays: Int) -> String {
        String(localized: "最近 \(consecutiveDays) 天的摄入都明显高于目标。这更可能说明目标定得有点紧，或者这几天的节奏和平时不一样。把目标调到更容易坚持的水平，长期看更有用。要不要看看目标设置？", table: "HintCopy")
    }
    /// 按钮
    static let adjustTargetAction = String(localized: "调整目标", table: "HintCopy")
    static let adjustTargetA11y = String(localized: "打开编辑资料页面", table: "HintCopy")
    static let adjustTargetLater = String(localized: "先不用", table: "HintCopy")

    // MARK: - 「推荐下一餐」页面

    /// 导航栏标题，例：「推荐晚餐」
    static func nextMealTitle(mealName: String) -> String { String(localized: "推荐\(mealName)", table: "HintCopy") }
    /// 剩下的够一顿正餐（≥ 320 千卡）时，例：「按今天剩下的热量，为你推荐一份约 400 千卡的晚餐，份量已经算好了。」
    static func nextMealIntro(mealKcal: Int, mealName: String) -> String {
        String(localized: "按今天剩下的热量，为你推荐一份约 \(n(mealKcal)) 千卡的\(mealInSentence(mealName))，份量已经算好了。", table: "HintCopy")
    }
    /// 剩下不到 320 千卡、按一顿正餐的最低量推荐时：如实说明，不让人「省着吃」
    static func nextMealRaisedToFloor(remainingKcal: Int, floorKcal: Int, mealName: String) -> String {
        let start = remainingKcal < 100 ? String(localized: "今天的摄入已经接近目标。", table: "HintCopy") : String(localized: "今天剩下约 \(n(remainingKcal)) 千卡。", table: "HintCopy")
        return start + String(localized: "为了让\(mealInSentence(mealName))仍然是一顿像样的正餐，这里按约 \(n(floorKcal)) 千卡来推荐；稍微多一点没关系，看一周的整体就好。", table: "HintCopy")
    }
    /// 这一餐的目标，例：「这一餐约 320 千卡 · 蛋白质 26 · 碳水 34 · 脂肪 9 克」
    static func nextMealBudgetLine(kcal: Int, proteinG: Int, carbsG: Int, fatG: Int) -> String {
        String(localized: "这一餐约 \(n(kcal)) 千卡 · 蛋白质 \(proteinG) · 碳水 \(carbsG) · 脂肪 \(fatG) 克", table: "HintCopy")
    }
    /// 按钮和状态
    static func generateNextMeal(mealName: String) -> String { String(localized: "生成\(mealName)推荐", table: "HintCopy") }
    static let generatingNextMeal = String(localized: "正在生成，通常需要 10～20 秒…", table: "HintCopy")
    /// 页面底部：和「食谱」页共用生成次数
    static func quotaRemaining(_ count: Int) -> String {
        String(localized: "今天还可以生成 \(count) 次（和「食谱」页共用次数）。条件不变时重新生成会直接用上次的结果，不占次数。", table: "HintCopy")
    }
    static let quotaUsedUp = String(localized: "食谱生成的次数暂时用完了，过一阵再来看看。", table: "HintCopy")
    /// 出错弹窗的标题（正文用后端返回的说明）和按钮
    static let generateFailedTitle = String(localized: "暂时没能生成", table: "HintCopy")
    static let ok = String(localized: "好", table: "HintCopy")
    static let done = String(localized: "完成", table: "HintCopy")

    // MARK: - 设置（「我的」页）

    static let settingsHeader = String(localized: "热量提示", table: "HintCopy")
    static let settingsPickerLabel = String(localized: "提示", table: "HintCopy")
    static func levelTitle(_ level: HintLevel) -> String {
        switch level {
        case .all: String(localized: "全部开启", table: "HintCopy")
        case .weeklyOnly: String(localized: "只看每周小结", table: "HintCopy")
        case .off: String(localized: "关闭", table: "HintCopy")
        }
    }
    /// 选中不同选项时，下面的灰色说明
    static func levelExplanation(_ level: HintLevel) -> String {
        switch level {
        case .all:
            String(localized: "接近目标时提前告诉你还剩多少，并按剩下的量推荐下一餐；每周一次小结；连续几天明显高于目标时，问一句要不要调整目标。所有提示只说明情况、给出下一步的选择。", table: "HintCopy")
        case .weeklyOnly:
            String(localized: "只在每周显示一次平均摄入和目标的对比，平时不打扰。", table: "HintCopy")
        case .off:
            String(localized: "不显示任何热量提示。每日目标和记录功能不受影响。", table: "HintCopy")
        }
    }
    static let settingsGoalNote = String(localized: "接近目标、到达目标和连续几天明显偏高的提示只在目标为「减脂」时显示；每周小结在「减脂」和「维持」时显示。", table: "HintCopy")

    // MARK: - 开发者工具（只在 Xcode 装的测试版里出现，用来在模拟器里触发各种提示）

    static let debugSectionTitle = String(localized: "开发者（仅测试版）", table: "HintCopy")
    static let debugSeedNearLimit = String(localized: "演示：今天吃到 90%", table: "HintCopy")
    static let debugSeedOver = String(localized: "演示：今天比目标多 150 千卡", table: "HintCopy")
    static let debugSeedStreak = String(localized: "演示：最近 3 天明显偏高", table: "HintCopy")
    static let debugSeedLastWeekOnTarget = String(localized: "演示：上周记录 5 天（和目标一致）", table: "HintCopy")
    static let debugSeedLastWeekAbove = String(localized: "演示：上周记录 7 天（明显偏高）", table: "HintCopy")
    static let debugSeedLastWeekFew = String(localized: "演示：上周只记了 2 天", table: "HintCopy")
    static let debugResetHintState = String(localized: "重置提示状态（知道了 / 先不用）", table: "HintCopy")
    static let debugClearLog = String(localized: "清除全部饮食记录", table: "HintCopy")
    static let debugClearLogConfirm = String(localized: "确定要清除全部饮食记录吗？", table: "HintCopy")
    static let debugClearLogAction = String(localized: "清除", table: "HintCopy")
    static let debugCancel = String(localized: "取消", table: "HintCopy")
    static let debugFakeNow = String(localized: "假装现在是", table: "HintCopy")
    static let debugUseRealNow = String(localized: "用真实时间", table: "HintCopy")
    /// 演示记录的名字，例：「演示早餐」
    static func debugEntryName(_ mealName: String) -> String { String(localized: "演示\(mealName)", table: "HintCopy") }
    /// 「假装现在是」生效时，今日页顶部的灰色小字
    static func debugFakeNowCaption(_ date: Date) -> String {
        String(localized: "测试时间：\(date.formatted(date: .abbreviated, time: .shortened))（在「我的」→「开发者」里可以改回真实时间）", table: "HintCopy")
    }
    static let debugFooter = String(localized: "这些按钮只在测试版里出现。「演示」按钮按「假装现在是」的时间写入示例记录，会替换那几天原有的记录（所以多按几次结果一样），并把资料修改时间改到 30 天前，让前几天的记录也能参与计算。", table: "HintCopy")

    // MARK: - 给单元测试用：每条文案各取一个样例（新加文案时在这里加一行）

    static var allSamples: [String] {
        [
            nearLimit(remainingKcal: 210, mealName: String(localized: "晚餐", table: "HintCopy")), nearLimit(remainingKcal: 90, mealName: String(localized: "晚餐", table: "HintCopy")),
            recommendNextMeal, recommendNextMealA11y,
            over(byKcal: 0, nextMealName: String(localized: "晚餐", table: "HintCopy")), over(byKcal: 40, nextMealName: nil),
            over(byKcal: 190, nextMealName: String(localized: "晚餐", table: "HintCopy")), over(byKcal: 190, nextMealName: nil),
            weeklyTitle, weeklyNumbers(averageKcal: 1510, targetKcal: 1463, daysCounted: 5),
            weeklyOnTarget, weeklyAbove(differenceKcal: 367), weeklyBelow(differenceKcal: 160),
            weeklyFewDays(daysCounted: 2), weeklyTargetChangedNote, weeklyAdjustSuggestion, weeklyDismiss,
            adjustTarget(consecutiveDays: 3), adjustTargetAction, adjustTargetA11y, adjustTargetLater,
            nextMealTitle(mealName: String(localized: "晚餐", table: "HintCopy")), nextMealIntro(mealKcal: 400, mealName: String(localized: "晚餐", table: "HintCopy")),
            nextMealRaisedToFloor(remainingKcal: 150, floorKcal: 320, mealName: String(localized: "晚餐", table: "HintCopy")),
            nextMealRaisedToFloor(remainingKcal: 60, floorKcal: 320, mealName: String(localized: "晚餐", table: "HintCopy")),
            nextMealBudgetLine(kcal: 320, proteinG: 26, carbsG: 34, fatG: 9),
            generateNextMeal(mealName: String(localized: "晚餐", table: "HintCopy")), generatingNextMeal, quotaRemaining(4), quotaUsedUp,
            generateFailedTitle, ok, done,
            settingsHeader, settingsPickerLabel, settingsGoalNote,
        ]
        + HintLevel.allCases.map(levelTitle) + HintLevel.allCases.map(levelExplanation)
        + [
            debugSectionTitle, debugSeedNearLimit, debugSeedOver, debugSeedStreak, debugSeedLastWeekOnTarget,
            debugSeedLastWeekAbove, debugSeedLastWeekFew, debugResetHintState, debugClearLog, debugClearLogConfirm,
            debugClearLogAction, debugCancel, debugFakeNow, debugUseRealNow, debugEntryName(String(localized: "早餐", table: "HintCopy")),
            debugFakeNowCaption(Date(timeIntervalSince1970: 1_790_740_800)), debugFooter,
        ]
    }
}
