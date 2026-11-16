import XCTest
import AppKit
import SwiftUI
import AVFoundation
import os
@testable import SimulTrans

final class CaptionTests: XCTestCase {
    @MainActor func testOverlayLayoutAndNativeControls() throws {
        _ = NSApplication.shared
        let state = AppState()
        state.translationConfig = nil
        state.currentOriginalText = String(repeating: "A long sentence remains available while speaking. ", count: 5)
        state.currentTranslatedText = String(repeating: "这是一段很长的译文，用来确认窗口能够换行显示完整内容，并允许滚动查看后面的文字。", count: 8)
        let panel = OverlayPanel(contentRect: .zero)
        let host = NSHostingView(rootView: OverlayContentView().environment(state))
        panel.contentView = host
        panel.setContentSize(NSSize(width: 480, height: 230))
        host.layoutSubtreeIfNeeded()
        XCTAssertTrue(panel.styleMask.contains(.fullSizeContentView))
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            XCTAssertEqual(panel.standardWindowButton(button)?.isHidden, false)
        }
        XCTAssertTrue(panel.titlebarAppearsTransparent)
        XCTAssertFalse(panel.isOpaque)
        XCTAssertEqual(panel.backgroundColor, .clear)
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        try data.write(to: URL(fileURLWithPath: "/private/tmp/simultrans-overlay-qa.png"))
        panel.orderOut(nil)
    }

    @MainActor func testHistoryCanStayScrolledUpWhileNewCaptionsArrive() async throws {
        _ = NSApplication.shared
        for mode in AppState.OverlayLayoutMode.allCases {
            let state = AppState()
            state.translationConfig = nil
            state.overlayLayoutMode = mode
            for index in 0..<12 {
                state.appendEntry(original: "原文第\(index)条，完整保留在历史里。", translated: "这是第\(index)条译文，供用户向上翻阅。")
            }
            let panel = OverlayPanel(contentRect: .zero)
            let host = NSHostingView(rootView: OverlayContentView().environment(state))
            panel.contentView = host
            panel.setContentSize(NSSize(width: 480, height: 250))
            panel.orderFront(nil)
            try await Task.sleep(for: .milliseconds(180))
            host.layoutSubtreeIfNeeded()
            let scroll = try XCTUnwrap(findScrollView(host))
            XCTAssertGreaterThan(scroll.documentView?.frame.height ?? 0, 500, "Every layout must contain history")
            let wheel = try XCTUnwrap(CGEvent(scrollWheelEvent2Source: nil, units: .pixel,
                wheelCount: 1, wheel1: 140, wheel2: 0, wheel3: 0))
            scroll.scrollWheel(with: try XCTUnwrap(NSEvent(cgEvent: wheel)))
            try await Task.sleep(for: .milliseconds(100))
            XCTAssertFalse(state.captionScroll.followsLatest, "An actual wheel event must pause following")
            scroll.contentView.scroll(to: .zero)
            scroll.reflectScrolledClipView(scroll.contentView)
            let position = scroll.contentView.bounds.origin.y
            state.appendEntry(original: "最新一句", translated: "最新一句译文")
            state.currentOriginalText = "又来了一句"
            state.currentTranslatedText = "译文晚到也不能抢走滚动位置"
            try await Task.sleep(for: .milliseconds(180))
            XCTAssertEqual(scroll.contentView.bounds.origin.y, position, accuracy: 2, "New captions must not pull the reader down")
            XCTAssertFalse(state.captionScroll.followsLatest)
            state.captionScroll.resume()
            try await Task.sleep(for: .milliseconds(180))
            XCTAssertGreaterThan(scroll.contentView.bounds.origin.y, position + 100)
            panel.orderOut(nil)
        }
    }

    @MainActor private func findScrollView(_ view: NSView) -> NSScrollView? {
        if let scroll = view as? NSScrollView { return scroll }
        for child in view.subviews { if let found = findScrollView(child) { return found } }
        return nil
    }

    @MainActor func testRemoteQwenLongSentenceFixture() async throws {
        guard let path = ProcessInfo.processInfo.environment["SIMULTRANS_ASR_FIXTURE"] else {
            throw XCTSkip("Set SIMULTRANS_ASR_FIXTURE to run against the configured Qwen server")
        }
        let file = try AVAudioFile(forReading: URL(fileURLWithPath: path))
        let completed = expectation(description: "Long sentence completes through the actual Qwen service")
        completed.assertForOverFulfill = true
        let recognizer = LocalSpeechRecognizer(engine: .qwen3ASR1_7B, locale: Locale(identifier: "ja"))
        var results: [String] = []
        recognizer.onError = { message in XCTFail(message); completed.fulfill() }
        recognizer.onResult = { update in
            results.append((update.isFinal ? "FINAL: " : "PARTIAL: ") + update.text)
            if update.isFinal {
                XCTAssertTrue(update.text.contains("研究"))
                XCTAssertTrue(update.text.contains("考え"), "The end of the long sentence must remain present")
                XCTAssertFalse(update.text.lowercased().contains("hai"))
                XCTAssertGreaterThan(update.text.count, 90)
                completed.fulfill()
            }
        }
        while file.framePosition < file.length {
            let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 2000))
            try file.read(into: buffer, frameCount: 2000)
            recognizer.append(buffer)
        }
        for _ in 0..<18 { recognizer.append(try audioBuffer(level: 0)) }
        await fulfillment(of: [completed], timeout: 90)
        try results.joined(separator: "\n").write(toFile: "/private/tmp/simultrans-qwen-e2e.txt", atomically: true, encoding: .utf8)
        recognizer.stop()
    }

    func testCumulativeHypothesesReplaceInsteadOfDuplicating() {
        var accumulator = UtteranceAccumulator()
        XCTAssertFalse(accumulator.update("今日は").isFinal)
        XCTAssertEqual(accumulator.update("今日は研究について").text, "今日は研究について")
        XCTAssertEqual(accumulator.update("今日は研究について説明します。", endsUtterance: true).text,
                       "今日は研究について説明します。")
        XCTAssertEqual(accumulator.update("次の文").text, "次の文")
    }

    func testJapaneseParticleAtTransportBoundary() {
        var accumulator = UtteranceAccumulator()
        _ = accumulator.update("何を変えるべきかを。", commitsWindow: true)
        XCTAssertEqual(accumulator.update("皆さんと考えたいと思います。", endsUtterance: true).text,
                       "何を変えるべきかを皆さんと考えたいと思います。")
        XCTAssertEqual(UtteranceAccumulator.join("最初の文です。", "次の文です。"), "最初の文です。次の文です。")
    }

    func testTransportWindowsNeverFinalizeLongSentence() {
        var accumulator = UtteranceAccumulator()
        let first = accumulator.update("I want to", commitsWindow: true)
        XCTAssertFalse(first.isFinal)
        let second = accumulator.update("finish my sentence", commitsWindow: true)
        XCTAssertEqual(second.text, "I want to finish my sentence")
        XCTAssertFalse(second.isFinal)
        let third = accumulator.update("even after a minute", commitsWindow: true)
        XCTAssertFalse(third.isFinal)
        let final = accumulator.update("", endsUtterance: true)
        XCTAssertEqual(final.text, "I want to finish my sentence even after a minute")
        XCTAssertTrue(final.isFinal)
    }

    @MainActor func testSilenceOnlyTailDoesNotCallASR() async throws {
        let calls = OSAllocatedUnfairLock(initialState: 0)
        let final = expectation(description: "Final from silence without decoding silence")
        let recognizer = LocalSpeechRecognizer(engine: .qwen3ASR1_7B, locale: Locale(identifier: "ja")) { url in
            let audio = try AVAudioFile(forReading: url)
            XCTAssertGreaterThan(Double(audio.length) / audio.processingFormat.sampleRate, 2.9,
                                 "A short overlap-only tail must never be sent to ASR")
            calls.withLock { $0 += 1 }
            return "まだ一つの長い文です。"
        }
        recognizer.onResult = { update in
            if update.isFinal {
                XCTAssertEqual(update.text, "まだ一つの長い文です。")
                final.fulfill()
            }
        }
        // Exactly one full 24-second transport window, then only silence.
        for _ in 0..<192 { recognizer.append(try audioBuffer(level: 0.1)) }
        for _ in 0..<17 { recognizer.append(try audioBuffer(level: 0)) }
        await fulfillment(of: [final], timeout: 10)
        // Previews can be coalesced; the tail must never add a second final ASR call.
        XCTAssertGreaterThan(calls.withLock { $0 }, 0)
        recognizer.stop()
    }

    @MainActor func testOnlySilenceProducesNoRecognition() async throws {
        let called = expectation(description: "No ASR call for silence")
        called.isInverted = true
        let recognizer = LocalSpeechRecognizer(engine: .qwen3ASR1_7B, locale: Locale(identifier: "ja")) { _ in
            called.fulfill()
            return "hai"
        }
        for _ in 0..<80 { recognizer.append(try audioBuffer(level: 0)) }
        recognizer.stop()
        await fulfillment(of: [called], timeout: 0.25)
    }

    @MainActor func testSpeechAcrossWindowsHasOneFinal() async throws {
        let final = expectation(description: "One final across 30 seconds")
        final.assertForOverFulfill = true
        let recognizer = LocalSpeechRecognizer(engine: .qwen3ASR1_7B, locale: Locale(identifier: "ja")) { _ in
            return "はい、続きを説明します。"
        }
        recognizer.onResult = { update in
            if update.isFinal {
                XCTAssertTrue(update.text.contains("はい"), "Real hai must not be blacklisted")
                final.fulfill()
            }
        }
        for _ in 0..<240 { recognizer.append(try audioBuffer(level: 0.1)) }
        for _ in 0..<17 { recognizer.append(try audioBuffer(level: 0)) }
        await fulfillment(of: [final], timeout: 10)
        recognizer.stop()
    }

    private func audioBuffer(level: Float) throws -> AVAudioPCMBuffer {
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 2_000))
        buffer.frameLength = 2_000
        for index in 0..<2_000 { buffer.floatChannelData![0][index] = level }
        return buffer
    }

    @MainActor func testPartialRevisionDoesNotCreateOrRewriteHistory() {
        let app = AppDelegate()
        app.appState.translationMode = .appleOnly
        let first = RecognitionUpdate(text: "我想", isFinal: false, segments: [])
        let second = RecognitionUpdate(text: "我想把这句话说完", isFinal: false, segments: [])
        app.handlePartialRecognitionUpdate(first, previousUpdate: nil)
        app.handlePartialRecognitionUpdate(second, previousUpdate: first)
        XCTAssertTrue(app.appState.transcriptEntries.isEmpty)
        app.appState.currentTranslatedText = "An obsolete draft"
        app.handleFinalRecognitionUpdate(.init(text: "我想把这句话说完整。", isFinal: true, segments: []), previousUpdate: second)
        XCTAssertEqual(app.appState.transcriptEntries.count, 1)
        XCTAssertNil(app.appState.transcriptEntries[0].translatedText)
        app.handlePartialRecognitionUpdate(.init(text: "下一句", isFinal: false, segments: []), previousUpdate: nil)
        XCTAssertEqual(app.appState.transcriptEntries[0].originalText, "我想把这句话说完整。")
        XCTAssertEqual(app.appState.currentOriginalText, "下一句")
    }

    @MainActor func testRetainedHistoryAndStaleTranslation() {
        let state = AppState()
        state.transcriptEntries = []
        let index = state.appendEntry(original: "Original", translated: nil)
        let id = state.transcriptEntries[index].id
        let old = state.beginEntryTranslation(entryID: id)!
        let current = state.beginEntryTranslation(entryID: id)!
        XCTAssertFalse(state.applyEntryTranslation("Old", entryID: id, requestID: old.requestID, expectedSource: "Original", stage: .appleDraft))
        XCTAssertTrue(state.applyEntryTranslation("New", entryID: id, requestID: current.requestID, expectedSource: "Original", stage: .appleDraft))
        for number in 0..<201 { state.appendEntry(original: "\(number)", translated: nil) }
        XCTAssertEqual(state.transcriptEntries.count, 202)
        XCTAssertEqual(state.transcriptEntries.first?.originalText, "Original")
        XCTAssertEqual(state.transcriptEntries.last?.originalText, "200")
        state.transcriptEntries.removeAll()
        XCTAssertFalse(state.applyEntryTranslation("Late", entryID: id, requestID: current.requestID, expectedSource: "Original", stage: .appleDraft))
    }

    @MainActor func testLateRefinementDoesNotRewriteTextBeingRead() {
        let state = AppState()
        state.appendEntry(original: "最初の文", translated: "第一句")
        let id = state.transcriptEntries[0].id
        let request = state.beginEntryTranslation(entryID: id)!
        state.captionScroll.userDidScroll()
        XCTAssertFalse(state.applyEntryTranslation("改写的第一句", entryID: id, requestID: request.requestID,
                       expectedSource: "最初の文", stage: .contextualAI))
        XCTAssertEqual(state.transcriptEntries[0].translatedText, "第一句")
    }

    @MainActor func testSameLanguageConfigurationDoesNotReplaceSession() {
        let state = AppState()
        let revision = state.translationConfigurationRevision
        state.updateTranslationConfig()
        XCTAssertEqual(state.translationConfigurationRevision, revision)
    }
}
