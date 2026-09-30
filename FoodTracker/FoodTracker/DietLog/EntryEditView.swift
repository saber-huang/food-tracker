//
//  EntryEditView.swift
//  FoodTracker
//
//  填写或修改一项食物的表单：名称、重量、热量、三大营养素。
//  它只负责填写；点「保存」后把结果交给打开它的页面，由那个页面决定怎么存（和「编辑资料」页一样的做法）。
//  手动添加、修改识别结果里的一项、修改已保存的记录，都用这个表单。
//

import SwiftUI

struct EntryEditView: View {
    let title: String
    let showsMealPicker: Bool  // 是否显示「记到哪一餐」
    let showsDate: Bool  // 是否显示「记录日期」（只显示，不能改：新记录固定记到正在看的那天）
    let showsDayPicker: Bool  // 是否显示可以改的「日期」（修改已保存的记录时用）
    let note: String?  // 分量下面的一行灰字（比如从食谱记的一餐：「重量按食材生重合计。」）
    let onSave: (EditableItem) -> Void
    let onDelete: (() -> Void)?  // 有值时多一个「删除这一项」按钮

    @Environment(\.dismiss) private var dismiss
    @State private var draft: EntryDraft
    @State private var didSave = false  // 防止快速连点两次「保存」存成两条
    @FocusState private var focusedField: Field?
    private enum Field { case name, weight, calories, protein, carbs, fat }

    init(
        draft: EntryDraft, title: String, showsMealPicker: Bool = false, showsDate: Bool = false,
        showsDayPicker: Bool = false, note: String? = nil, onSave: @escaping (EditableItem) -> Void,
        onDelete: (() -> Void)? = nil
    ) {
        _draft = State(initialValue: draft)
        self.title = title
        self.showsMealPicker = showsMealPicker
        self.showsDate = showsDate
        self.showsDayPicker = showsDayPicker
        self.note = note
        self.onSave = onSave
        self.onDelete = onDelete
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("名称", text: $draft.name, prompt: Text("必填，例如：米饭"))
                        .focused($focusedField, equals: .name)
                        .accessibilityLabel("名称")
                        // 数字键盘没有「完成」键，在键盘上方加一个。只挂在这一行上，挂多了会出现好几个「完成」
                        .toolbar {
                            ToolbarItemGroup(placement: .keyboard) {
                                Spacer()
                                Button("完成") { focusedField = nil }
                            }
                        }
                    if let error = draft.nameError, !draft.name.isEmpty, focusedField != .name {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    if showsDate {
                        LabeledContent("记录日期", value: DayMath.dayTitle(for: draft.day, today: .now))
                    }
                    if showsDayPicker {
                        // 只能选到今天为止，不能记到未来。日期按中文显示（2026年9月29日），弹出的月历从周一开始
                        DatePicker("日期", selection: $draft.day, in: ...Date.now, displayedComponents: .date)
                            .environment(\.locale, DayMath.locale)
                    }
                } header: {
                    Text("食物")
                } footer: {
                    if showsDate {
                        Text("新记录会保存到「今日」页正在看的这一天；要记到别的日期，先在「今日」页切换日期。")
                    }
                }

                if showsMealPicker {
                    // 分段样式不显示 Picker 自己的标题，所以用这一组的标题（和识别结果页一样）
                    Section {
                        Picker("记到哪一餐", selection: $draft.meal) {
                            ForEach(MealType.allCases) { meal in
                                Text(meal.title).tag(meal)
                            }
                        }
                        .pickerStyle(.segmented)
                    } header: {
                        Text("记到哪一餐")
                    } footer: {
                        // 只有新记录的餐次是按时间猜的；修改已保存的记录时选中的是原来的餐次，不加这句
                        if showsDate {
                            Text("按现在的时间默认推荐，可以改。")
                        }
                    }
                }

                Section {
                    // 名称和热量必须填，其他可以不填：输入框里的灰字直接写明
                    NumberRow(
                        title: "重量", unit: "克", text: $draft.weightText, keyboard: .decimalPad,
                        error: draft.weightError, focus: $focusedField, field: .weight, prompt: "选填")
                    NumberRow(
                        title: "热量", unit: "千卡", text: $draft.caloriesText, keyboard: .decimalPad,
                        error: draft.caloriesError, focus: $focusedField, field: .calories, prompt: "必填")
                    NumberRow(
                        title: "蛋白质", unit: "克", text: $draft.proteinText, keyboard: .decimalPad,
                        error: draft.proteinError, focus: $focusedField, field: .protein, prompt: "选填")
                    NumberRow(
                        title: "碳水", unit: "克", text: $draft.carbsText, keyboard: .decimalPad,
                        error: draft.carbsError, focus: $focusedField, field: .carbs, prompt: "选填")
                    NumberRow(
                        title: "脂肪", unit: "克", text: $draft.fatText, keyboard: .decimalPad,
                        error: draft.fatError, focus: $focusedField, field: .fat, prompt: "选填")

                    // 灰色提醒：可能填错了，但不阻止保存
                    if let warning = draft.kcalMismatchWarning {
                        Label(warning, systemImage: "info.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let warning = draft.macrosExceedWeightWarning {
                        Label(warning, systemImage: "info.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let note {
                        Text(note)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("分量与营养")
                } footer: {
                    // 第一句一直显示；第二句看现在能不能按比例换算；
                    // 最后一句：国内包装上的「能量」按规定用千焦标示，照着抄很容易把千焦当成千卡
                    Text(
                        "名称和热量必须填，其他可以不填。"
                            + (draft.per100 == nil
                                ? "先填重量、再填热量，之后改重量才会按比例换算。"
                                : "改了重量，热量和三大营养素会按比例一起变；直接改某一项，就只改那一项。")
                            + "包装上的「能量」一般是千焦（kJ），除以 4.2 大约就是千卡。")
                }

                if let onDelete {
                    Section {
                        // 先关掉表单再删：表单还开着的时候删掉它正在显示的记录，会出错
                        Button("删除这一项", role: .destructive) {
                            dismiss()
                            onDelete()
                        }
                    }
                }
            }
            // 任何一个数字框变了，交给草稿判断要不要按比例换算
            .onChange(of: draft.allTexts) { draft.textsChanged() }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(draft.output == nil || didSave)
                }
            }
        }
    }

    private func save() {
        // 按钮变灰要等下一次刷新界面，所以这里再检查一次，连点两下也只存一条
        guard !didSave, let item = draft.output else { return }
        didSave = true
        onSave(item)
        dismiss()
    }
}

#Preview("手动添加") {
    EntryEditView(draft: EntryDraft(meal: .lunch, day: .now), title: "手动添加", showsMealPicker: true, showsDate: true) { _ in }
}

#Preview("修改识别结果") {
    EntryEditView(
        draft: EntryDraft(item: EditableItem(SampleData.analyzeResult.items[0], meal: .lunch, day: .now)),
        title: "修改食物"
    ) { _ in }
}

#Preview("修改已保存的记录") {
    EntryEditView(
        draft: EntryDraft(item: EditableItem(SampleData.analyzeResult.items[0], meal: .lunch, day: .now)),
        title: "修改记录", showsMealPicker: true, showsDayPicker: true, onSave: { _ in }, onDelete: {}
    )
}
