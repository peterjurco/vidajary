import Foundation
import SwiftData

// MARK: - Metadata

struct ProjectArchiveMetadata: Codable {
    var version: Int = 1
    var projectName: String
    var musicFilename: String?
    var saveClipsToLibrary: Bool
    var clips: [ClipMetadata]

    struct ClipMetadata: Codable {
        var filename: String
        var duration: TimeInterval
        var recordedAt: Date
        var sortOrder: Int
        var rotationOverride: Int
        var trimStart: TimeInterval
        var trimEnd: TimeInterval
        var clipVolume: Float
        var musicVolume: Float
    }
}

// MARK: - Service

enum ArchiveService {
    // File format: magic(4) | metaLen(u32le) | metaJSON | [nameLen(u32le) | name | dataLen(u64le) | data]*
    private static let magic = Data([0x56, 0x49, 0x44, 0x41]) // "VIDA"
    private static let chunkSize = 4 * 1024 * 1024 // 4 MB

    // MARK: Export

    /// Writes a .vidajary archive to outputURL. Call from a background context for large projects.
    static func export(project: Project, to outputURL: URL) throws {
        let dir = clipsDirectory()
        let sortedClips = project.clips.sorted { $0.sortOrder < $1.sortOrder }

        let metadata = ProjectArchiveMetadata(
            projectName: project.name,
            musicFilename: project.musicFilename,
            saveClipsToLibrary: project.saveClipsToLibrary,
            clips: sortedClips.map {
                .init(filename: $0.filename, duration: $0.duration,
                      recordedAt: $0.recordedAt, sortOrder: $0.sortOrder,
                      rotationOverride: $0.rotationOverride, trimStart: $0.trimStart,
                      trimEnd: $0.trimEnd, clipVolume: $0.clipVolume, musicVolume: $0.musicVolume)
            }
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let metaJSON = try encoder.encode(metadata)

        var entries: [(name: String, url: URL)] = sortedClips.compactMap {
            let u = dir.appendingPathComponent($0.filename)
            return FileManager.default.fileExists(atPath: u.path) ? ($0.filename, u) : nil
        }
        if let music = project.musicFilename {
            let u = dir.appendingPathComponent(music)
            if FileManager.default.fileExists(atPath: u.path) { entries.append((music, u)) }
        }

        try? FileManager.default.removeItem(at: outputURL)
        FileManager.default.createFile(atPath: outputURL.path, contents: nil)
        let out = try FileHandle(forWritingTo: outputURL)
        defer { try? out.close() }

        out.write(magic)
        out.write(le32(UInt32(metaJSON.count)))
        out.write(metaJSON)

        for (name, fileURL) in entries {
            let nameData = Data(name.utf8)
            out.write(le32(UInt32(nameData.count)))
            out.write(nameData)
            out.write(le64(try byteSize(of: fileURL)))
            let inp = try FileHandle(forReadingFrom: fileURL)
            defer { try? inp.close() }
            while true {
                let chunk = inp.readData(ofLength: chunkSize)
                if chunk.isEmpty { break }
                out.write(chunk)
            }
        }
    }

    // MARK: Import

    static func importArchive(from inputURL: URL, context: ModelContext) throws {
        let dir = clipsDirectory()
        let inp = try FileHandle(forReadingFrom: inputURL)
        defer { try? inp.close() }

        guard inp.readData(ofLength: 4) == magic else { throw ArchiveError.invalidFormat }

        let metaLenData = inp.readData(ofLength: 4)
        guard metaLenData.count == 4 else { throw ArchiveError.truncated }
        let metaLen = Int(metaLenData.withUnsafeBytes { $0.load(as: UInt32.self).littleEndian })
        let metaData = inp.readData(ofLength: metaLen)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let metadata = try decoder.decode(ProjectArchiveMetadata.self, from: metaData)

        var filenames = metadata.clips.map { $0.filename }
        if let m = metadata.musicFilename { filenames.append(m) }

        for filename in filenames {
            let nameLenData = inp.readData(ofLength: 4)
            guard nameLenData.count == 4 else { throw ArchiveError.truncated }
            let nameLen = Int(nameLenData.withUnsafeBytes { $0.load(as: UInt32.self).littleEndian })
            let nameData = inp.readData(ofLength: nameLen)
            guard String(data: nameData, encoding: .utf8) == filename else { throw ArchiveError.invalidFormat }

            let sizeData = inp.readData(ofLength: 8)
            guard sizeData.count == 8 else { throw ArchiveError.truncated }
            let size = Int(sizeData.withUnsafeBytes { $0.load(as: UInt64.self).littleEndian })

            let dest = dir.appendingPathComponent(filename)

            // Skip if this file is already present (e.g. re-importing same archive)
            if FileManager.default.fileExists(atPath: dest.path),
               let existingSize = try? byteSize(of: dest),
               existingSize == UInt64(size) {
                let currentOffset = (try? inp.offset()) ?? 0
                try? inp.seek(toOffset: currentOffset + UInt64(size))
                continue
            }

            try? FileManager.default.removeItem(at: dest)
            FileManager.default.createFile(atPath: dest.path, contents: nil)
            let out = try FileHandle(forWritingTo: dest)
            defer { try? out.close() }

            var remaining = size
            while remaining > 0 {
                let chunk = inp.readData(ofLength: min(remaining, chunkSize))
                guard !chunk.isEmpty else { throw ArchiveError.truncated }
                out.write(chunk)
                remaining -= chunk.count
            }
        }

        let project = Project(name: metadata.projectName)
        project.musicFilename = metadata.musicFilename
        project.saveClipsToLibrary = metadata.saveClipsToLibrary

        for m in metadata.clips {
            let clip = Clip(filename: m.filename, duration: m.duration,
                            sortOrder: m.sortOrder, recordedAt: m.recordedAt)
            clip.rotationOverride = m.rotationOverride
            clip.trimStart = m.trimStart
            clip.trimEnd = m.trimEnd
            clip.clipVolume = m.clipVolume
            clip.musicVolume = m.musicVolume
            project.clips.append(clip)
        }

        context.insert(project)
        try context.save()
    }

    // MARK: Helpers

    private static func le32(_ v: UInt32) -> Data { var x = v.littleEndian; return Data(bytes: &x, count: 4) }
    private static func le64(_ v: UInt64) -> Data { var x = v.littleEndian; return Data(bytes: &x, count: 8) }

    private static func byteSize(of url: URL) throws -> UInt64 {
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        if let v = attrs[.size] as? UInt64 { return v }
        if let v = attrs[.size] as? Int { return UInt64(max(0, v)) }
        return 0
    }

    enum ArchiveError: LocalizedError {
        case invalidFormat, truncated
        var errorDescription: String? {
            switch self {
            case .invalidFormat: return "Not a valid Vidajary archive."
            case .truncated: return "The archive appears to be incomplete."
            }
        }
    }
}
