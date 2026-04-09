//
//  Clip.swift
//  vidajary
//

import Foundation
import SwiftData

@Model
final class Clip {
    var id: UUID
    var filename: String
    var recordedAt: Date
    var duration: TimeInterval
    var project: Project?

    init(filename: String, duration: TimeInterval) {
        self.id = UUID()
        self.filename = filename
        self.recordedAt = Date()
        self.duration = duration
    }
}
