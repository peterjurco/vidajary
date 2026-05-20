import Foundation
import SwiftData
import zlib

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
    private static let chunkSize = 4 * 1024 * 1024 // 4 MB

    // MARK: - Export

    /// Writes a standard ZIP archive to outputURL.
    /// Layout: metadata.json | clips/<filename> … | music/<filename>
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
        encoder.outputFormatting = .prettyPrinted
        let metaJSON = try encoder.encode(metadata)

        // Collect file entries: (zip path, source URL or nil for in-memory data)
        struct FileEntry {
            let zipPath: String
            let url: URL?
            let data: Data?
        }
        var entries: [FileEntry] = [FileEntry(zipPath: "metadata.json", url: nil, data: metaJSON)]
        for clip in sortedClips {
            let u = dir.appendingPathComponent(clip.filename)
            if FileManager.default.fileExists(atPath: u.path) {
                entries.append(FileEntry(zipPath: "clips/\(clip.filename)", url: u, data: nil))
            }
        }
        if let music = project.musicFilename {
            let u = dir.appendingPathComponent(music)
            if FileManager.default.fileExists(atPath: u.path) {
                entries.append(FileEntry(zipPath: "music/\(music)", url: u, data: nil))
            }
        }

        try? FileManager.default.removeItem(at: outputURL)
        guard FileManager.default.createFile(atPath: outputURL.path, contents: nil) else {
            throw ArchiveError.writeFailed
        }
        let out = try FileHandle(forWritingTo: outputURL)
        defer { try? out.close() }

        // Central directory info collected while writing local entries
        struct CDEntry {
            let zipPath: String
            let crc: UInt32
            let size: UInt64
            let localOffset: UInt64
            let dosTime: UInt16
            let dosDate: UInt16
        }
        var cdEntries: [CDEntry] = []

        let (dosDate, dosTime) = currentDosDateTime()

        for entry in entries {
            let localOffset = (try? out.offset()) ?? 0
            let nameData = Data(entry.zipPath.utf8)

            // Local file header — sizes/CRC are zero; data descriptor carries real values (bit 3)
            try out.write(contentsOf: sig(0x04034b50))
            try out.write(contentsOf: le16(20))          // version needed
            try out.write(contentsOf: le16(0x0008))      // general purpose: data descriptor present
            try out.write(contentsOf: le16(0))           // compression: STORE
            try out.write(contentsOf: le16(dosTime))
            try out.write(contentsOf: le16(dosDate))
            try out.write(contentsOf: le32(0))           // CRC placeholder
            try out.write(contentsOf: le32(0))           // compressed size placeholder
            try out.write(contentsOf: le32(0))           // uncompressed size placeholder
            try out.write(contentsOf: le16(UInt16(nameData.count)))
            try out.write(contentsOf: le16(0))           // extra field length
            try out.write(contentsOf: nameData)

            // File data — stream and accumulate CRC
            var crc: uLong = zlib.crc32(0, nil, 0)
            var written: UInt64 = 0

            if let data = entry.data {
                data.withUnsafeBytes { ptr in
                    crc = zlib.crc32(crc, ptr.baseAddress?.assumingMemoryBound(to: Bytef.self), uInt(data.count))
                }
                try out.write(contentsOf: data)
                written = UInt64(data.count)
            } else if let url = entry.url {
                let inp = try FileHandle(forReadingFrom: url)
                defer { try? inp.close() }
                while true {
                    let chunk = inp.readData(ofLength: chunkSize)
                    if chunk.isEmpty { break }
                    chunk.withUnsafeBytes { ptr in
                        crc = zlib.crc32(crc, ptr.baseAddress?.assumingMemoryBound(to: Bytef.self), uInt(chunk.count))
                    }
                    try out.write(contentsOf: chunk)
                    written += UInt64(chunk.count)
                }
            }

            let finalCRC = UInt32(crc & 0xFFFFFFFF)

            // Data descriptor (signature + CRC + sizes)
            try out.write(contentsOf: sig(0x08074b50))
            try out.write(contentsOf: le32(finalCRC))
            try out.write(contentsOf: le32(UInt32(written & 0xFFFFFFFF)))
            try out.write(contentsOf: le32(UInt32(written & 0xFFFFFFFF)))

            cdEntries.append(CDEntry(zipPath: entry.zipPath, crc: finalCRC, size: written,
                                     localOffset: localOffset, dosTime: dosTime, dosDate: dosDate))
        }

        // Central directory
        let cdOffset = (try? out.offset()) ?? 0
        for cd in cdEntries {
            let nameData = Data(cd.zipPath.utf8)
            try out.write(contentsOf: sig(0x02014b50))
            try out.write(contentsOf: le16(0x0314))      // version made by: Unix 3.0
            try out.write(contentsOf: le16(20))          // version needed
            try out.write(contentsOf: le16(0x0008))      // data descriptor flag
            try out.write(contentsOf: le16(0))           // STORE
            try out.write(contentsOf: le16(cd.dosTime))
            try out.write(contentsOf: le16(cd.dosDate))
            try out.write(contentsOf: le32(cd.crc))
            try out.write(contentsOf: le32(UInt32(cd.size & 0xFFFFFFFF)))
            try out.write(contentsOf: le32(UInt32(cd.size & 0xFFFFFFFF)))
            try out.write(contentsOf: le16(UInt16(nameData.count)))
            try out.write(contentsOf: le16(0))           // extra
            try out.write(contentsOf: le16(0))           // comment
            try out.write(contentsOf: le16(0))           // disk start
            try out.write(contentsOf: le16(0))           // internal attrs
            try out.write(contentsOf: le32(0))           // external attrs
            try out.write(contentsOf: le32(UInt32(cd.localOffset & 0xFFFFFFFF)))
            try out.write(contentsOf: nameData)
        }
        let cdEnd = (try? out.offset()) ?? 0
        let cdSize = cdEnd - cdOffset

        // End of central directory
        try out.write(contentsOf: sig(0x06054b50))
        try out.write(contentsOf: le16(0))               // disk number
        try out.write(contentsOf: le16(0))               // disk with CD
        try out.write(contentsOf: le16(UInt16(cdEntries.count)))
        try out.write(contentsOf: le16(UInt16(cdEntries.count)))
        try out.write(contentsOf: le32(UInt32(cdSize & 0xFFFFFFFF)))
        try out.write(contentsOf: le32(UInt32(cdOffset & 0xFFFFFFFF)))
        try out.write(contentsOf: le16(0))               // comment length
    }

    // MARK: - Import

    static func importArchive(from inputURL: URL, context: ModelContext) throws {
        let dir = clipsDirectory()
        let handle = try FileHandle(forReadingFrom: inputURL)
        defer { try? handle.close() }

        // Locate end-of-central-directory by scanning backwards for its signature
        let fileSize = try handle.seekToEnd()
        guard fileSize >= 22 else { throw ArchiveError.invalidFormat }

        var eocdOffset: UInt64? = nil
        let scanBack = min(fileSize, UInt64(65536 + 22))
        try handle.seek(toOffset: fileSize - scanBack)
        let tail = handle.readData(ofLength: Int(scanBack))
        for i in stride(from: tail.count - 22, through: 0, by: -1) {
            if tail[i] == 0x50, tail[i+1] == 0x4B, tail[i+2] == 0x05, tail[i+3] == 0x06 {
                eocdOffset = fileSize - scanBack + UInt64(i)
                break
            }
        }
        guard let eocdOffset else { throw ArchiveError.invalidFormat }

        try handle.seek(toOffset: eocdOffset)
        let eocdData = handle.readData(ofLength: 22)
        guard eocdData.count == 22 else { throw ArchiveError.truncated }

        let cdCount  = eocdData.le16(at: 10)
        let cdSize   = eocdData.le32(at: 12)
        let cdOffset = eocdData.le32(at: 16)

        // Read central directory
        try handle.seek(toOffset: UInt64(cdOffset))
        let cdData = handle.readData(ofLength: Int(cdSize))

        struct CDRecord {
            let zipPath: String
            let size: UInt64
            let localOffset: UInt64
        }
        var records: [CDRecord] = []
        var pos = 0
        for _ in 0..<cdCount {
            guard pos + 46 <= cdData.count else { break }
            guard cdData[pos] == 0x50, cdData[pos+1] == 0x4B,
                  cdData[pos+2] == 0x01, cdData[pos+3] == 0x02 else { break }
            let compSize   = cdData.le32(at: pos + 20)
            let nameLen    = cdData.le16(at: pos + 28)
            let extraLen   = cdData.le16(at: pos + 30)
            let commentLen = cdData.le16(at: pos + 32)
            let localOff   = cdData.le32(at: pos + 42)
            let nameStart  = pos + 46
            guard nameStart + Int(nameLen) <= cdData.count else { break }
            let nameData   = cdData.subdata(in: nameStart ..< nameStart + Int(nameLen))
            let zipPath    = String(data: nameData, encoding: .utf8) ?? ""
            records.append(CDRecord(zipPath: zipPath, size: UInt64(compSize), localOffset: UInt64(localOff)))
            pos += 46 + Int(nameLen) + Int(extraLen) + Int(commentLen)
        }

        guard !records.isEmpty else { throw ArchiveError.invalidFormat }

        print("[Archive] Parsed \(records.count) CD records:")
        for r in records { print("  path='\(r.zipPath)' size=\(r.size) offset=\(r.localOffset)") }

        // Helper: read a file entry from the zip into destURL (nil = return Data)
        func extractEntry(_ record: CDRecord, to destURL: URL? = nil) throws -> Data? {
            try handle.seek(toOffset: record.localOffset)
            let lhPrefix = handle.readData(ofLength: 30)
            guard lhPrefix.count == 30,
                  lhPrefix[0] == 0x50, lhPrefix[1] == 0x4B,
                  lhPrefix[2] == 0x03, lhPrefix[3] == 0x04 else { throw ArchiveError.invalidFormat }
            let nameLen  = lhPrefix.le16(at: 26)
            let extraLen = lhPrefix.le16(at: 28)
            handle.readData(ofLength: Int(nameLen) + Int(extraLen)) // skip name + extra

            if let dest = destURL {
                try? FileManager.default.removeItem(at: dest)
                guard FileManager.default.createFile(atPath: dest.path, contents: nil) else {
                    throw ArchiveError.writeFailed
                }
                let out = try FileHandle(forWritingTo: dest)
                defer { try? out.close() }
                var remaining = Int(record.size)
                while remaining > 0 {
                    let chunk = handle.readData(ofLength: min(remaining, chunkSize))
                    guard !chunk.isEmpty else { throw ArchiveError.truncated }
                    try out.write(contentsOf: chunk)
                    remaining -= chunk.count
                }
                let written = (try? FileManager.default.attributesOfItem(atPath: dest.path)[.size] as? Int) ?? -1
                print("[Archive] Extracted '\(record.zipPath)' → size on disk: \(written)")
                return nil
            } else {
                return handle.readData(ofLength: Int(record.size))
            }
        }

        // Find and decode metadata.json
        guard let metaRecord = records.first(where: { $0.zipPath == "metadata.json" }),
              let metaData = try extractEntry(metaRecord) else {
            throw ArchiveError.invalidFormat
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let metadata = try decoder.decode(ProjectArchiveMetadata.self, from: metaData)

        print("[Archive] metadata clips: \(metadata.clips.map(\.filename))")

        // Extract clip files
        for clipMeta in metadata.clips {
            let lookupKey = "clips/\(clipMeta.filename)"
            if let record = records.first(where: { $0.zipPath == lookupKey }) {
                let dest = dir.appendingPathComponent(clipMeta.filename)
                let exists = FileManager.default.fileExists(atPath: dest.path)
                print("[Archive] clip '\(clipMeta.filename)': record found (size=\(record.size)), fileExists=\(exists)")
                if !exists {
                    try extractEntry(record, to: dest)
                }
            } else {
                print("[Archive] clip '\(clipMeta.filename)': NO RECORD FOUND for key '\(lookupKey)'")
            }
        }

        // Extract music file
        if let music = metadata.musicFilename,
           let record = records.first(where: { $0.zipPath == "music/\(music)" }) {
            let dest = dir.appendingPathComponent(music)
            if !FileManager.default.fileExists(atPath: dest.path) {
                try extractEntry(record, to: dest)
            }
        }

        // Reconstruct SwiftData model
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

    // MARK: - Zip helpers

    private static func sig(_ v: UInt32) -> Data { le32(v) }
    private static func le16(_ v: UInt16) -> Data { var x = v.littleEndian; return Data(bytes: &x, count: 2) }
    private static func le32(_ v: UInt32) -> Data { var x = v.littleEndian; return Data(bytes: &x, count: 4) }

    private static func currentDosDateTime() -> (date: UInt16, time: UInt16) {
        let c = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: Date())
        let year = max(0, (c.year ?? 1980) - 1980)
        let date = UInt16((year << 9) | ((c.month ?? 1) << 5) | (c.day ?? 1))
        let time = UInt16(((c.hour ?? 0) << 11) | ((c.minute ?? 0) << 5) | ((c.second ?? 0) >> 1))
        return (date, time)
    }

    // MARK: - Errors

    enum ArchiveError: LocalizedError {
        case invalidFormat, truncated, writeFailed
        var errorDescription: String? {
            switch self {
            case .invalidFormat: return "Not a valid Vidajary archive."
            case .truncated: return "The archive appears to be incomplete."
            case .writeFailed: return "Not enough storage space to complete the operation."
            }
        }
    }
}

// MARK: - Data parsing helpers

private extension Data {
    func le16(at offset: Int) -> UInt16 {
        guard offset + 2 <= count else { return 0 }
        return subdata(in: offset..<offset+2).withUnsafeBytes { $0.load(as: UInt16.self).littleEndian }
    }
    func le32(at offset: Int) -> UInt32 {
        guard offset + 4 <= count else { return 0 }
        return subdata(in: offset..<offset+4).withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }
    }
}
