//
//  ImageCompressor.swift
//  FoodTracker
//
//  上传前压缩照片。iPhone 原图通常有几 MB，压缩后只有一两百 KB，
//  上传更快、更省流量，AI 识别也更快。
//

import UIKit

extension UIImage {
    /// 把照片的长边缩小到 maxSide 像素以内，再压缩成 JPEG。
    /// - Parameters:
    ///   - maxSide: 长边最多多少像素，1024 已经足够 AI 看清食物
    ///   - quality: JPEG 质量，0～1，越小文件越小
    func compressedForUpload(maxSide: CGFloat = 1024, quality: CGFloat = 0.7) -> Data? {
        // 1. 算出缩小后的尺寸（等比例缩小；本来就小的图不放大）
        let longSide = max(size.width, size.height)
        let ratio = min(1, maxSide / longSide)
        let newSize = CGSize(
            width: (size.width * ratio).rounded(),
            height: (size.height * ratio).rounded()
        )

        // 2. 按新尺寸重新画一遍
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1  // 按实际像素画，不乘屏幕倍数，否则在 Retina 屏上会变成 2～3 倍大
        let resized = UIGraphicsImageRenderer(size: newSize, format: format).image { _ in
            // draw 会自动处理手机照片的旋转方向，画出来一定是正的
            draw(in: CGRect(origin: .zero, size: newSize))
        }

        // 3. 转成 JPEG 数据
        return resized.jpegData(compressionQuality: quality)
    }
}
