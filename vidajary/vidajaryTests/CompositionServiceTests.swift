import XCTest
import AVFoundation
@testable import vidajary

final class CompositionServiceTests: XCTestCase {

    func testBuildCompositionFromTwoClips() throws {
        let dir = FileManager.default.temporaryDirectory
        let url1 = dir.appendingPathComponent("comp_clip1.mov")
        let url2 = dir.appendingPathComponent("comp_clip2.mov")
        try makeTestVideo(at: url1, duration: 1.0, testCase: self)
        try makeTestVideo(at: url2, duration: 2.0, testCase: self)

        let composition = try CompositionService.buildComposition(from: [url1, url2])

        XCTAssertEqual(composition.duration.seconds, 3.0, accuracy: 0.2)
        XCTAssertFalse(composition.tracks(withMediaType: .video).isEmpty)
    }

    func testEmptyClipsReturnsEmptyComposition() throws {
        let composition = try CompositionService.buildComposition(from: [])
        XCTAssertEqual(composition.duration.seconds, 0.0, accuracy: 0.01)
    }
}
