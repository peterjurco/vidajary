//
//  Project.swift
//  vidajary
//

import Foundation
import SwiftData

@Model
final class Project {
    var id: UUID
    var name: String
    var createdAt: Date
    var lastRecordedAt: Date?
    var saveClipsToLibrary: Bool
    @Relationship(deleteRule: .cascade, inverse: \Clip.project) var clips: [Clip]

    init(name: String) {
        self.id = UUID()
        self.name = name
        self.createdAt = Date()
        self.saveClipsToLibrary = false
        self.clips = []
    }

    var totalDuration: TimeInterval {
        clips.reduce(0) { $0 + $1.duration }
    }
}
