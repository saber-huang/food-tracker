//
//  NumberRow.swift
//  FoodTracker
//
//  一行数字输入：标题、输入框、单位；填错时在下面显示红色提示。资料页和饮食记录的表单共用。
//
//  - 正在输入时不显示错误（比如年龄刚输入「1」时还不算错），离开这个输入框后才提示
//  - 点这一行的任何地方（包括标题）都能开始输入
//
//  用法：页面里有一个 @FocusState 记住「现在在输入哪个框」，把它和这一行对应的值传进来：
//      NumberRow(title: "年龄", unit: "岁", text: $draft.ageText, keyboard: .numberPad,
//                error: draft.ageError, focus: $focusedField, field: .age)
//

import SwiftUI

struct NumberRow<Field: Hashable>: View {
    let title: String
    let unit: String
    @Binding var text: String
    let keyboard: UIKeyboardType
    let error: String?
    /// 页面的「现在在输入哪个框」
    let focus: FocusState<Field?>.Binding
    /// 这一行对应的是哪个框
    let field: Field

    private var isEditing: Bool { focus.wrappedValue == field }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                TextField(title, text: $text, prompt: Text("请输入"))
                    .keyboardType(keyboard)
                    .multilineTextAlignment(.trailing)
                    .focused(focus, equals: field)
                Text(unit)
                    .foregroundStyle(.secondary)
            }
            // 整行都能点：点标题或单位也会开始输入
            .contentShape(Rectangle())
            .simultaneousGesture(TapGesture().onEnded { focus.wrappedValue = field })

            // 还没输入、或者正在输入时不显示错误，免得一边打字一边看到红字
            if let error, !text.isEmpty, !isEditing {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }
}
