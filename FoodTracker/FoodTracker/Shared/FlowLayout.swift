//
//  FlowLayout.swift
//  FoodTracker
//
//  从左到右排、一行放不下就换到下一行的排法（引导页的偏好标签用）。
//  字号变大时标签变宽，自然换成更多行；一个标签比一整行还宽时，文字在标签里换行。
//

import SwiftUI

struct FlowLayout: Layout {
    var spacing: CGFloat = AppSpacing.xs

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(maxWidth: proposal.width ?? .infinity, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let frames = arrange(maxWidth: bounds.width, subviews: subviews).frames
        for (subview, frame) in zip(subviews, frames) {
            subview.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY), proposal: ProposedViewSize(frame.size))
        }
    }

    /// 算出每个标签放在哪：放不下就换行，每行的高度按这一行最高的那个
    private func arrange(maxWidth: CGFloat, subviews: Subviews) -> (frames: [CGRect], size: CGSize) {
        var frames: [CGRect] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(ProposedViewSize(width: maxWidth, height: nil))
            let width = min(size.width, maxWidth)
            if x > 0 && x + width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            frames.append(CGRect(x: x, y: y, width: width, height: size.height))
            widest = max(widest, x + width)
            x += width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return (frames, CGSize(width: widest, height: y + rowHeight))
    }
}
