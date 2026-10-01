//
//  LoadingStateTests.swift
//  FoodTrackerTests
//
//  第六轮：识别照片时的加载页
//  - 标题：一张「正在分析这顿饭」，几张「正在分析 3 张照片」
//  - 标题下面那句话按等待的时间换说法，不出现秒数和百分比（不知道真正的进度，就不假装知道）
//  - 冒热气的碗：三缕热气错开、先变清楚再变淡；「减弱动态效果」时停住
//

import Foundation
import Testing

@testable import FoodTracker

@MainActor
@Suite("识别照片的加载页")
struct LoadingStateTests {
    @Test("标题：一张写「正在分析这顿饭」，几张写「正在分析 N 张照片」")
    func analyzingTitle() {
        #expect(PhotoReviewView.analyzingTitle(photoCount: 1) == "正在分析这顿饭")
        #expect(PhotoReviewView.analyzingTitle(photoCount: 3) == "正在分析 3 张照片")
    }

    @Test("一张照片：先说在识别，6 秒后说在整理营养，之后不再换")
    func singlePhotoMessages() {
        let messages = PhotoReviewView.loadingMessages(photoCount: 1)
        #expect(messages.line(after: 0) == "正在识别食物和估算份量…")
        #expect(messages.line(after: 5.9) == "正在识别食物和估算份量…")
        #expect(messages.line(after: 6) == "正在整理这顿饭的营养信息…")
        #expect(messages.line(after: 600) == "正在整理这顿饭的营养信息…")
    }

    @Test("几张照片：中间多一句「正在结合不同角度判断份量…」")
    func multiPhotoMessages() {
        let messages = PhotoReviewView.loadingMessages(photoCount: 3)
        #expect(messages.line(after: 0) == "正在识别食物和估算份量…")
        #expect(messages.line(after: 5) == "正在结合不同角度判断份量…")
        #expect(messages.line(after: 11) == "正在整理这顿饭的营养信息…")
        #expect(messages.line(after: 600) == "正在整理这顿饭的营养信息…")
    }

    @Test("不显示假的进度：每一句都没有秒数、没有百分比")
    func noFakeProgress() {
        for count in 1...APIClient.maxPhotos {
            let messages = PhotoReviewView.loadingMessages(photoCount: count)
            #expect(messages.lines.count == messages.switchAt.count)
            for line in messages.lines + [PhotoReviewView.analyzingTitle(photoCount: count)] {
                #expect(!line.contains("秒"))
                #expect(!line.contains("%"))
                #expect(!line.contains("％"))
            }
        }
    }

    @Test("没有句子时不出错（返回空字符串）")
    func emptyMessages() {
        #expect(LoadingMessages(lines: [], switchAt: []).line(after: 3) == "")
    }

    @Test("热气：三缕错开三分之一轮，2 秒一轮")
    func steamPhases() {
        for time in stride(from: 0.0, to: 4, by: 0.25) {
            let phases = (0..<3).map { SteamLayer.phase(time: time, index: $0) }
            for phase in phases {
                #expect(phase >= 0 && phase < 1)
            }
            // 后一缕比前一缕晚三分之一轮
            let gap = (phases[1] - phases[0] + 1).truncatingRemainder(dividingBy: 1)
            #expect(abs(gap - 1.0 / 3) < 1e-9)
            // 2 秒后回到同一个位置
            #expect(abs(SteamLayer.phase(time: time + 2, index: 0) - phases[0]) < 1e-9)
        }
    }

    @Test("热气的透明度：刚冒出来和飘到顶时几乎看不见，中间最清楚也只有 0.55；减弱动态效果时停在很淡的 0.35")
    func steamOpacity() {
        #expect(SteamLayer.opacity(phase: 0, still: false) < 0.001)
        #expect(SteamLayer.opacity(phase: 0.999, still: false) < 0.01)
        #expect(abs(SteamLayer.opacity(phase: 0.5, still: false) - 0.55) < 1e-9)
        for phase in stride(from: 0.0, to: 1, by: 0.05) {
            #expect(SteamLayer.opacity(phase: phase, still: false) <= 0.55)
            #expect(SteamLayer.opacity(phase: phase, still: true) == 0.35)
        }
        // 减弱动态效果：三缕停在固定的高度，彼此错开
        let still = (0..<3).map { SteamLayer.phase(time: nil, index: $0) }
        #expect(Set(still).count == 3)
        #expect(still.allSatisfy { $0 > 0 && $0 < 1 })
    }
}
