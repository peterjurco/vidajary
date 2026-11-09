import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    static var orientationMask: UIInterfaceOrientationMask = .portrait

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        cleanTmpZips()
        #if DEBUG
        printStorageTree()
        #endif
        return true
    }

    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        AppDelegate.orientationMask
    }
}

private func cleanTmpZips() {
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
    let fm = FileManager.default
    guard let items = try? fm.contentsOfDirectory(at: tmp, includingPropertiesForKeys: nil) else { return }
    for item in items where item.pathExtension.lowercased() == "zip" {
        try? fm.removeItem(at: item)
    }
}

#if DEBUG
private func printStorageTree() {
    let fm = FileManager.default
    let docs = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
    print("=== STORAGE TREE ===")
    print("Documents: \(docs.path)")
    printDir(docs, fm: fm, indent: "")
    print("Tmp: \(tmp.path)  \(formatBytes(directorySize(tmp, fm: fm)))")
    printDir(tmp, fm: fm, indent: "")
    print("====================")
}

private func printDir(_ url: URL, fm: FileManager, indent: String) {
    guard let items = try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey, .totalFileSizeKey], options: []) else { return }
    let sorted = items.sorted { $0.lastPathComponent < $1.lastPathComponent }
    for item in sorted {
        let vals = try? item.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey])
        let isDir = vals?.isDirectory ?? false
        if isDir {
            let total = directorySize(item, fm: fm)
            print("\(indent)[\(item.lastPathComponent)/]  \(formatBytes(total))")
            printDir(item, fm: fm, indent: indent + "  ")
        } else {
            let size = vals?.fileSize ?? 0
            print("\(indent)\(item.lastPathComponent)  \(formatBytes(size))")
        }
    }
}

private func directorySize(_ url: URL, fm: FileManager) -> Int {
    guard let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles]) else { return 0 }
    return enumerator.compactMap { ($0 as? URL).flatMap { try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize } }.reduce(0, +)
}

private func formatBytes(_ bytes: Int) -> String {
    let mb = Double(bytes) / 1_048_576
    return mb >= 1 ? String(format: "%.1f MB", mb) : "\(bytes / 1024) KB"
}
#endif
