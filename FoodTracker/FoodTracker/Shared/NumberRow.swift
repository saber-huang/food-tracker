//
//  NumberRow.swift
//  FoodTracker
//
//  一行数字输入：标题、输入框、单位；填错时在下面显示红色提示。资料页和饮食记录的表单共用。
//
//  - 正在输入时不显示错误（比如年龄刚输入「1」时还不算错），离开这个输入框后才提示
//  - 点这一行的任何地方（包括标题）都能开始输入
//  - 旁白（VoiceOver）把标题和单位一起读成「热量（千卡）」，出现红色提示时会念出来
//
//  用法：页面里有一个 @FocusState 记住「现在在输入哪个框」，把它和这一行对应的值传进来：
//      NumberRow(title: "年龄", unit: "岁", text: $draft.ageText, keyboard: .numberPad,
//                error: draft.ageError, focus: $focusedField, field: .age)
//  输入框里的灰字默认是「请输入」，可以改：比如可以不填的框写 prompt: "选填"
//

import Accessibility
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
    /// 输入框里的灰字（必须写成 var 才能有默认值）
    var prompt = String(localized: "请输入")

    private var isEditing: Bool { focus.wrappedValue == field }

    /// 现在要显示的错误：还没输入、或者正在输入时不显示，免得一边打字一边看到红字
    private var shownError: String? { !text.isEmpty && !isEditing ? error : nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .accessibilityHidden(true)  // 旁白读输入框自己的名字（下面），这里不重复读
                TextField(title, text: $text, prompt: Text(prompt))
                    .keyboardType(keyboard)
                    .multilineTextAlignment(.trailing)
                    .focused(focus, equals: field)
                    .accessibilityLabel("\(title)（\(unit)）")
                Text(unit)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            // 整行都能点：点标题或单位也会开始输入
            .contentShape(Rectangle())
            .simultaneousGesture(TapGesture().onEnded { focus.wrappedValue = field })

            if let shownError {
                Text(shownError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        // 红色提示出现时，让旁白念出来（看不见屏幕的用户也知道哪里填错了）
        .onChange(of: shownError) { _, newError in
            if let newError {
                AccessibilityNotification.Announcement(newError).post()
            }
        }
    }
}
