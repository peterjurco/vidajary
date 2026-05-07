import XCTest
import SwiftData
@testable import vidajary

final class ModelTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!

    override func tearDown() async throws {
        context = nil
        container = nil
    }

    override func setUp() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: Project.self, Clip.self, configurations: config)
        context = ModelContext(container)
    }

    func testCreateProject() throws {
        let project = Project(name: "Vacation 2024")
        context.insert(project)
        try context.save()

        let projects = try context.fetch(FetchDescriptor<Project>())
        XCTAssertEqual(projects.count, 1)
        XCTAssertEqual(projects.first?.name, "Vacation 2024")
        XCTAssertFalse(projects.first!.saveClipsToLibrary)
        XCTAssertTrue(projects.first!.clips.isEmpty)
    }

    func testAddClipToProject() throws {
        let project = Project(name: "Test")
        context.insert(project)
        let clip = Clip(filename: "abc.mov", duration: 5.0)
        project.clips.append(clip)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Project>()).first!
        XCTAssertEqual(fetched.clips.count, 1)
        XCTAssertEqual(fetched.clips.first?.filename, "abc.mov")
        XCTAssertEqual(fetched.clips.first?.duration, 5.0)
        XCTAssertNotNil(fetched.clips.first?.recordedAt)
    }

    func testDeleteProjectCascadesClips() throws {
        let project = Project(name: "Test")
        context.insert(project)
        project.clips.append(Clip(filename: "a.mov", duration: 2.0))
        project.clips.append(Clip(filename: "b.mov", duration: 3.0))
        try context.save()

        context.delete(project)
        try context.save()

        let clips = try context.fetch(FetchDescriptor<Clip>())
        XCTAssertTrue(clips.isEmpty)
    }

    func testTotalDuration() throws {
        let project = Project(name: "Test")
        context.insert(project)
        project.clips.append(Clip(filename: "a.mov", duration: 10.0))
        project.clips.append(Clip(filename: "b.mov", duration: 5.0))
        try context.save()

        XCTAssertEqual(project.totalDuration, 15.0, accuracy: 0.01)
    }

    func testClipDefaultFields() throws {
        let clip = Clip(filename: "test.mov", duration: 10.0, sortOrder: 3)
        XCTAssertEqual(clip.sortOrder, 3)
        XCTAssertEqual(clip.rotationOverride, 0)
        XCTAssertEqual(clip.trimStart, 0.0, accuracy: 0.001)
        XCTAssertEqual(clip.trimEnd, 0.0, accuracy: 0.001)
    }

    func testClipEffectiveDuration() throws {
        let clip = Clip(filename: "test.mov", duration: 10.0, sortOrder: 0)
        XCTAssertEqual(clip.effectiveDuration, 10.0, accuracy: 0.01)

        clip.trimStart = 2.0
        clip.trimEnd = 7.0
        XCTAssertEqual(clip.effectiveDuration, 5.0, accuracy: 0.01)

        clip.trimStart = 1.0
        clip.trimEnd = 0.0  // 0 means "no trim from end"
        XCTAssertEqual(clip.effectiveDuration, 9.0, accuracy: 0.01)
    }

    func testClipVolumeDefaults() throws {
        let clip = Clip(filename: "test.mov", duration: 10.0)
        XCTAssertEqual(clip.clipVolume, 1.0, accuracy: 0.001)
        XCTAssertEqual(clip.musicVolume, 1.0, accuracy: 0.001)
    }

    func testClipVolumesPersist() throws {
        let project = Project(name: "Test")
        context.insert(project)
        let clip = Clip(filename: "a.mov", duration: 5.0)
        clip.clipVolume = 0.5
        clip.musicVolume = 0.3
        project.clips.append(clip)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Clip>()).first!
        XCTAssertEqual(fetched.clipVolume, 0.5, accuracy: 0.001)
        XCTAssertEqual(fetched.musicVolume, 0.3, accuracy: 0.001)
    }

    func testTotalDurationUsesEffectiveDuration() throws {
        let project = Project(name: "Test")
        context.insert(project)
        let clip = Clip(filename: "a.mov", duration: 10.0, sortOrder: 0)
        clip.trimStart = 2.0
        clip.trimEnd = 7.0  // effective = 5s
        project.clips.append(clip)
        project.clips.append(Clip(filename: "b.mov", duration: 5.0, sortOrder: 1))
        try context.save()
        XCTAssertEqual(project.totalDuration, 10.0, accuracy: 0.01)
    }

    func testProjectAudioDefaults() throws {
        let project = Project(name: "Test")
        context.insert(project)
        try context.save()
        XCTAssertNil(project.musicFilename)
        XCTAssertEqual(project.musicVolume, 1.0, accuracy: 0.001)
        XCTAssertEqual(project.videoVolume, 1.0, accuracy: 0.001)
    }
}
