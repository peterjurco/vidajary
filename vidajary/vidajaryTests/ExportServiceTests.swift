import XCTest
import AVFoundation
@testable import vidajary

final class ExportServiceTests: XCTestCase {

    func testExportWritesFileToOutputURL() async throws {
        let dir = FileManager.default.temporaryDirectory
        let inputURL = dir.appendingPathComponent(UUID().uuidString + ".mov")
        try makeTestVideo(at: inputURL, duration: 1.0, testCase: self)
        defer { try? FileManager.default.removeItem(at: inputURL) }

        let result = try await CompositionService.buildComposition(from: [inputURL])

        let outputURL = dir.appendingPathComponent(UUID().uuidString + ".mov")
        defer { try? FileManager.default.removeItem(at: outputURL) }

        try await ExportService.export(
            composition: result.composition,
            videoComposition: result.videoComposition,
            audioMix: result.audioMix,
            to: outputURL
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))
        let asset = AVURLAsset(url: outputURL)
        let duration = try await asset.load(.duration)
        XCTAssertEqual(duration.seconds, 1.0, accuracy: 0.2)
    }
}
