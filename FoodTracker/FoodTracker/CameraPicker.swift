//
//  CameraPicker.swift
//  FoodTracker
//
//  SwiftUI 在 iOS 17 上没有现成的拍照组件，这里把系统相机（UIImagePickerController）
//  包装成 SwiftUI 可以直接用的样子。
//

import SwiftUI
import UIKit

struct CameraPicker: UIViewControllerRepresentable {
    /// 拍好照片后调用，把照片交给首页
    let onPhotoTaken: (UIImage) -> Void

    @Environment(\.dismiss) private var dismiss

    // 创建系统相机界面
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    // Coordinator 负责接收相机的回调：拍好了，或者取消了
    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker

        init(parent: CameraPicker) { self.parent = parent }

        // 用户拍好照片并点了「使用照片」
        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let photo = info[.originalImage] as? UIImage {
                parent.onPhotoTaken(photo)
            }
            parent.dismiss()
        }

        // 用户点了「取消」
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
