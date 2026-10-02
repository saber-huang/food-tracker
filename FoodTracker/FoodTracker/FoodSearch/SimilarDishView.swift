//
//  SimilarDishView.swift
//  FoodTracker
//
//  搜不到的菜（「山西过油肉」）又不想用 AI（没同意、次数用完、没网、AI 出错）时：
//  从食物库里挑一道差不多的菜（「青椒肉丝」），名字照样记成「山西过油肉」，营养按挑的那道菜估算。
//  不用联网、不花钱。菜品本来就只能估算：比起让人凭空填一个脂肪克数，挑一道做法相近的菜更靠谱
//

import SwiftUI

struct SimilarDishView: View {
    /// 用户搜的名字（记录时用这个名字）
    let query: String
    let onPick: (CatalogFood) -> Void

    @State private var filter = ""
    private let catalog = FoodCatalog.shared

    /// 家常菜、快餐和小吃、主食和面点三组（零食、饮料这些有包装，不在这里挑）。家常菜最常用，放最前面
    private var groups: [(title: String, foods: [CatalogFood])] {
        let key = catalog.normalizer.key(filter)
        func matches(_ food: CatalogFood) -> Bool {
            key.isEmpty || food.allNames.contains { catalog.normalizer.key($0).contains(key) }
        }
        let dishes = catalog.foods.filter { $0.category == "dish" && matches($0) }
        return [
            (String(localized: "家常菜"), dishes.filter(\.adjustsOil)),
            (String(localized: "快餐和小吃"), dishes.filter { !$0.adjustsOil }),
            (String(localized: "主食和面点"), catalog.foods.filter { $0.category == "staple" && matches($0) }),
        ].filter { !$0.foods.isEmpty }
    }

    var body: some View {
        AppForm {
            Text("挑一道做法差不多的菜，营养按它估算，名字照样记成「\(query)」。")
                .font(.callout)
                .foregroundStyle(AppColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, AppSpacing.xxs)

            filterField

            ForEach(groups, id: \.title) { group in
                AppFormSection(group.title) {
                    ForEach(Array(group.foods.enumerated()), id: \.element.id) { index, food in
                        if index > 0 { AppFormDivider() }
                        let choice = FoodChoice.catalog(food)
                        FoodChoiceRow(choice: choice, subtitle: FoodRowText.typical(choice)) { onPick(food) }
                    }
                }
            }
            if groups.isEmpty {
                Text("没有找到，换个字试试")
                    .font(AppTypography.detail)
                    .foregroundStyle(AppColors.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, AppSpacing.md)
            }
        }
        .toolbar(.visible, for: .navigationBar)
        .navigationTitle(String(localized: "选一道差不多的菜"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var filterField: some View {
        HStack(spacing: AppSpacing.xs) {
            Image(systemName: "line.3.horizontal.decrease")
                .foregroundStyle(AppColors.textSecondary)
                .accessibilityHidden(true)
            TextField("筛选", text: $filter, prompt: Text("筛选，比如「肉丝」").foregroundStyle(AppColors.textTertiary))
                .foregroundStyle(AppColors.textPrimary)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.done)
        }
        .padding(.horizontal, AppSpacing.md)
        .frame(minHeight: 48)
        .background(AppColors.surfacePrimary, in: RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
    }
}
