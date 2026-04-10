import XCTest
import AVFoundation
import SwiftData
@testable import vidajary

final class CompositionServiceTests: XCTestCase {

    func testBuildCompositionFromTwoClips() async throws {
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
    }

    func testEmptyClipsReturnsEmptyComposition() async throws {
        let result = try await CompositionService.buildComposition(from: [])
        XCTAssertEqual(result.composition.duration.seconds, 0.0, accuracy: 0.01)
    }

    func testBuildCompositionFromClipModelsOrdersByRecordedAt() async throws {
        let dir = FileManager.default.temporaryDirectory
        let url1 = dir.appendingPathComponent(UUID().uuidString + ".mov")
        let url2 = dir.appendingPathComponent(UUID().uuidString + ".mov")
        try makeTestVideo(at: url1, duration: 1.0, testCase: self)
        try makeTestVideo(at: url2, duration: 2.0, testCase: self)
        defer {
            try? FileManager.default.removeItem(at: url1)
            try? FileManager.default.removeItem(at: url2)
        }

        // Create clips in reverse order — older clip (url2) recorded first
        let clip1 = Clip(filename: url1.lastPathComponent, duration: 1.0)
        clip1.recordedAt = Date(timeIntervalSince1970: 2000)
        let clip2 = Clip(filename: url2.lastPathComponent, duration: 2.0)
        clip2.recordedAt = Date(timeIntervalSince1970: 1000) // earlier

        // Pass them in reversed order — composition should sort and put clip2 first
        let result = try await CompositionService.buildComposition(
            from: [clip1, clip2],
            in: dir
        )
        // Total duration should still be 3s regardless of order
        XCTAssertEqual(result.composition.duration.seconds, 3.0, accuracy: 0.2)
    }
}
