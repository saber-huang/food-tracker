//
//  ServingPicker.swift
//  FoodTracker
//
//  选份量：上面选单位（碗 / 克），下面是 − 1.5 碗 + 和「约 225 克」；切到「克」就直接填克数。
//  份量页（FoodServingView）和手动填写表单（EntryEditView）都用它，它自己不存状态：
//  选了什么、填的克数都由用的地方管，这里只负责显示和把点击告诉它们。
//  放在 AppFormSection 的卡片里用（每一行左右 16 的留白已经算好）
//

import SwiftUI

struct ServingPicker<AmountInput: View>: View {
    /// 这种食物的自然单位（碗、个……）
    let units: [ServingUnit]
    /// 克还是毫升；nil = 只能按份数（不知道重量的食物，没有「克」可选）
    let amountUnit: AmountUnit?
    /// 选中的自然单位；nil = 正在直接填克数
    let selectedUnitID: String?
    let quantity: Double
    /// 选单位：传自然单位的 id，nil = 切到「克」
    let onSelectUnit: (String?) -> Void
    /// 加一步（+1）/ 减一步（-1）
    let onStep: (Int) -> Void
    /// 直接填克数的那一行（由用的地方提供：份量页和手动表单的输入框不一样）
    @ViewBuilder var amountInput: AmountInput

    private static var amountOptionID: String { "__amount" }

    private var options: [String] {
        units.map(\.id) + (amountUnit == nil ? [] : [Self.amountOptionID])
    }

    private var selectedUnit: ServingUnit? {
        selectedUnitID.flatMap { id in units.first { $0.id == id } }
    }

    var body: some View {
        VStack(spacing: 0) {
            // 只有一个选项（比如只能按份数的食物）时不显示单位选择
            if options.count > 1 {
                AppSegmentedControl(
                    title: String(localized: "份量单位"),
                    selection: Binding(
                        get: { selectedUnitID ?? Self.amountOptionID },
                        set: { onSelectUnit($0 == Self.amountOptionID ? nil : $0) }),
                    options: options,
                    label: { id in
                        // 英文的单位名在句子里是小写（1.5 bowls），放在分段按钮上首字母大写（Bowl）；克、毫升的符号不变
                        id == Self.amountOptionID
                            ? (amountUnit ?? .gram).symbol
                            : (units.first { $0.id == id }?.displayName(quantity: 1) ?? id).localizedCapitalized
                    }
                )
                .padding(AppSpacing.sm)
                AppFormDivider()
            }
            if let unit = selectedUnit {
                stepper(unit)
            } else {
                amountInput
            }
        }
    }

    /// − 1.5 碗 +，下面一行「约 225 克」
    private func stepper(_ unit: ServingUnit) -> some View {
        HStack(spacing: AppSpacing.sm) {
            stepButton(systemImage: "minus", direction: -1, disabled: quantity <= unit.step)
            VStack(spacing: 2) {
                Text(PortionText.serving(quantity, unit: unit))
                    .font(.system(.title3, design: .rounded, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(AppColors.textPrimary)
                    .contentTransition(.numericText())
                if let amountUnit, unit.amount > 0 {
                    Text(PortionText.amount(quantity * unit.amount, unit: amountUnit, approximate: true))
                        .font(AppTypography.detail)
                        .monospacedDigit()
                        .foregroundStyle(AppColors.textSecondary)
                }
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(String(localized: "份量"))
            .accessibilityValue(spokenValue(unit))
            // 旁白：上下滑动加减份量
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: onStep(1)
                case .decrement: if quantity > unit.step { onStep(-1) }
                @unknown default: break
                }
            }
            stepButton(systemImage: "plus", direction: 1, disabled: quantity >= 99)
        }
        .padding(.horizontal, AppSpacing.cardPadding)
        .padding(.vertical, AppSpacing.sm)
        .frame(minHeight: 72)
        .animation(.easeOut(duration: 0.15), value: quantity)
        .sensoryFeedback(.selection, trigger: quantity)  // 加减一次轻轻震一下
    }

    private func spokenValue(_ unit: ServingUnit) -> String {
        let serving = PortionText.serving(quantity, unit: unit)
        guard let amountUnit, unit.amount > 0 else { return serving }
        return "\(serving)，\(PortionText.amount(quantity * unit.amount, unit: amountUnit, approximate: true))"
    }

    private func stepButton(systemImage: String, direction: Int, disabled: Bool) -> some View {
        Button {
            onStep(direction)
        } label: {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(AppColors.brandDeep)
                .frame(width: 44, height: 44)
                .background(AppColors.surfaceSecondary, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(AppPressStyle())
        .disabled(disabled)
        .opacity(disabled ? 0.4 : 1)
        .accessibilityLabel(direction > 0 ? String(localized: "多一点") : String(localized: "少一点"))
    }
}
