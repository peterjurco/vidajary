import XCTest
import AVFoundation
import SwiftData
@testable import vidajary

final class CompositionServiceTests: XCTestCase {

    func testBuildCompositionFromTwoURLs() async throws {
        let dir = FileManager.default.temporaryDirectory
        let url1 = dir.appendingPathComponent(UUID().uuidString + ".mov")
        let url2 = dir.appendingPathComponent(UUID().uuidString + ".mov")
        try makeTestVideo(at: url1, duration: 1.0, testCase: self)
        try makeTestVideo(at: url2, duration: 2.0, testCase: self)
        defer {
            try? FileManager.default.removeItem(at: url1)
            try? FileManager.default.removeItem(at: url2)
        }
        let result = try await CompositionService.buildComposition(from: [url1, url2])
        XCTAssertEqual(result.composition.duration.seconds, 3.0, accuracy: 0.2)
        XCTAssertFalse(result.composition.tracks(withMediaType: .video).isEmpty)
        XCTAssertNil(result.audioMix) // no volumes set, no music
    }

    func testEmptyClipsReturnsEmptyComposition() async throws {
        let result = try await CompositionService.buildComposition(from: [])
        XCTAssertEqual(result.composition.duration.seconds, 0.0, accuracy: 0.01)
    }

    func testBuildCompositionSortsBySortOrder() async throws {
        let dir = FileManager.default.temporaryDirectory
        let url1 = dir.appendingPathComponent(UUID().uuidString + ".mov")
        let url2 = dir.appendingPathComponent(UUID().uuidString + ".mov")
        try makeTestVideo(at: url1, duration: 1.0, testCase: self)
        try makeTestVideo(at: url2, duration: 2.0, testCase: self)
        defer {
            try? FileManager.default.removeItem(at: url1)
            try? FileManager.default.removeItem(at: url2)
        }
        // clip2 (2s) sortOrder=0 should be first; clip1 (1s) sortOrder=1 should be second
        let clip1 = Clip(filename: url1.lastPathComponent, duration: 1.0, sortOrder: 1)
        let clip2 = Clip(filename: url2.lastPathComponent, duration: 2.0, sortOrder: 0)
        let result = try await CompositionService.buildComposition(from: [clip1, clip2], in: dir)
        XCTAssertEqual(result.composition.duration.seconds, 3.0, accuracy: 0.2)
        let videoTrack = result.composition.tracks(withMediaType: .video).first
        XCTAssertNotNil(videoTrack)
        // First segment should be 2s (clip2 with sortOrder=0)
        if let first = videoTrack?.segments.first(where: { !$0.isEmpty }) {
            XCTAssertEqual(first.timeMapping.target.duration.seconds, 2.0, accuracy: 0.3)
        }
    }

    func testBuildCompositionAppliesTrim() async throws {
        let dir = FileManager.default.temporaryDirectory
        let url = dir.appendingPathComponent(UUID().uuidString + ".mov")
        try makeTestVideo(at: url, duration: 3.0, testCase: self)
        defer { try? FileManager.default.removeItem(at: url) }

        let clip = Clip(filename: url.lastPathComponent, duration: 3.0, sortOrder: 0)
        clip.trimStart = 0.5
        clip.trimEnd = 2.5  // 2 seconds of content

        let result = try await CompositionService.buildComposition(from: [clip], in: dir)
        XCTAssertEqual(result.composition.duration.seconds, 2.0, accuracy: 0.3)
    }

    func testBuildCompositionWithClipAudioReturnsAudioMix() async throws {
        let dir = FileManager.default.temporaryDirectory
        let url = dir.appendingPathComponent(UUID().uuidString + ".mov")
        try makeTestVideo(at: url, duration: 1.0, testCase: self)
        defer { try? FileManager.default.removeItem(at: url) }

        let clip = Clip(filename: url.lastPathComponent, duration: 1.0, sortOrder: 0)
        let result = try await CompositionService.buildComposition(from: [clip], in: dir)
        // audioMix is created whenever any clip has audio
        XCTAssertNotNil(result.audioMix)
    }
}
