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
    var sortOrder: Int
    var rotationOverride: Int   // 0, 90, 180, or 270
    var trimStart: TimeInterval // seconds from clip start; 0 = no trim
    var trimEnd: TimeInterval   // seconds from clip start; 0 = use full duration

    init(filename: String, duration: TimeInterval, sortOrder: Int = 0) {
        self.id = UUID()
        self.filename = filename
        self.recordedAt = Date()
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
