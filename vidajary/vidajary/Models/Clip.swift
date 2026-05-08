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
    var sortOrder: Int = 0
    var rotationOverride: Int = 0   // 0, 90, 180, or 270
    var trimStart: TimeInterval = 0 // seconds from clip start; 0 = no trim
    var trimEnd: TimeInterval = 0   // seconds from clip start; 0 = use full duration
    var clipVolume: Float = 1.0     // this clip's audio volume (0–1)
    var musicVolume: Float = 1.0    // background music level during this clip (0–1)

    init(filename: String, duration: TimeInterval, sortOrder: Int = 0, recordedAt: Date = Date()) {
        self.id = UUID()
        self.filename = filename
        self.recordedAt = recordedAt
        self.duration = duration
        self.sortOrder = sortOrder
        self.rotationOverride = 0
        self.trimStart = 0
        self.trimEnd = 0
    }

    var effectiveDuration: TimeInterval {
        let end = trimEnd > 0 ? trimEnd : duration
        return max(0, end - trimStart)
    }
}
