import Foundation

func clipsDirectory() -> URL {
    let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    let dir = docs.appendingPathComponent("clips")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

func newClipURL() -> URL {
    clipsDirectory().appendingPathComponent(UUID().uuidString + ".mov")
}
