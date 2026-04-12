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
    var musicFilename: String?
    var musicVolume: Float
    var videoVolume: Float
    @Relationship(deleteRule: .cascade, inverse: \Clip.project) var clips: [Clip]

    init(name: String) {
        self.id = UUID()
        self.name = name
        self.createdAt = Date()
        self.saveClipsToLibrary = false
        self.musicFilename = nil
        self.musicVolume = 1.0
        self.videoVolume = 1.0
        self.clips = []
    }

    var totalDuration: TimeInterval {
        clips.reduce(0) { $0 + $1.effectiveDuration }
    }
}
