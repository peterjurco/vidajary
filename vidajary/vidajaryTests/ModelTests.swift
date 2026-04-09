import XCTest
import SwiftData
@testable import vidajary

final class ModelTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!

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
}
