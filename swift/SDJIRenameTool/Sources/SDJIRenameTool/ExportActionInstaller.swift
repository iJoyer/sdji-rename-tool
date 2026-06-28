import Foundation

enum ExportActionInstaller {
    static let actionName = "SDJI Rename Tool Export Action"

    private static let customTargetKey = "lightroomExportActionTarget"
    private static let markerFileName = "sdji-export-action-target.txt"

    struct InstallTarget {
        let selectedURL: URL
        let exportActionsFolder: URL
        let label: String
    }

    static var defaultExportActionsFolder: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Adobe/Lightroom/Export Actions", isDirectory: true)
    }

    static var selectedTarget: InstallTarget {
        if let value = UserDefaults.standard.string(forKey: customTargetKey), !value.isEmpty {
            return target(for: URL(fileURLWithPath: value))
        }
        return target(for: defaultExportActionsFolder)
    }

    static func setCustomTarget(_ url: URL) {
        UserDefaults.standard.set(url.path, forKey: customTargetKey)
    }

    static func resetTarget() {
        UserDefaults.standard.removeObject(forKey: customTargetKey)
    }

    static func target(for url: URL) -> InstallTarget {
        let standardized = url.standardizedFileURL
        if standardized.pathExtension.lowercased() == "app" {
            return InstallTarget(
                selectedURL: standardized,
                exportActionsFolder: standardized
                    .appendingPathComponent("Contents", isDirectory: true)
                    .appendingPathComponent("Resources", isDirectory: true)
                    .appendingPathComponent("Export Actions", isDirectory: true),
                label: "App: \(standardized.lastPathComponent)"
            )
        }

        return InstallTarget(
            selectedURL: standardized,
            exportActionsFolder: standardized,
            label: standardized.path
        )
    }

    static func statusText(for target: InstallTarget = selectedTarget) -> String {
        let actionURL = actionURL(in: target.exportActionsFolder)
        guard FileManager.default.fileExists(atPath: actionURL.path) else {
            return "未安装"
        }

        guard let executablePath = Bundle.main.executableURL?.path else {
            return "已安装"
        }

        let markerURL = markerURL(in: actionURL)
        guard let marker = try? String(contentsOf: markerURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines) else {
            return "需要更新"
        }

        return marker == executablePath ? "已安装" : "需要更新"
    }

    static func install(to target: InstallTarget = selectedTarget) throws {
        guard let executablePath = Bundle.main.executableURL?.path else {
            throw NSError(domain: "ExportActionInstaller", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "无法定位当前 App"
            ])
        }

        let folder = target.exportActionsFolder
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let actionURL = actionURL(in: folder)
        if FileManager.default.fileExists(atPath: actionURL.path) {
            try FileManager.default.removeItem(at: actionURL)
        }

        let scriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("applescript")
        try appleScript(executablePath: executablePath).write(to: scriptURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: scriptURL) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osacompile")
        process.arguments = ["-o", actionURL.path, scriptURL.path]

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw NSError(domain: "ExportActionInstaller", code: Int(process.terminationStatus), userInfo: [
                NSLocalizedDescriptionKey: "Export Action 编译失败"
            ])
        }

        let markerURL = markerURL(in: actionURL)
        try FileManager.default.createDirectory(at: markerURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try executablePath.write(to: markerURL, atomically: true, encoding: .utf8)
    }

    private static func actionURL(in folder: URL) -> URL {
        folder.appendingPathComponent("\(actionName).app", isDirectory: true)
    }

    private static func markerURL(in actionURL: URL) -> URL {
        actionURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Resources", isDirectory: true)
            .appendingPathComponent(markerFileName)
    }

    private static func appleScript(executablePath: String) -> String {
        let escapedPath = executablePath
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        return """
        on open exportedFiles
            set fileArgs to ""
            set exportFolders to {}
            repeat with exportedFile in exportedFiles
                set exportedPath to POSIX path of exportedFile
                set fileArgs to fileArgs & " " & quoted form of exportedPath
                set exportFolder to do shell script "/usr/bin/dirname " & quoted form of exportedPath
                if exportFolders does not contain exportFolder then
                    set end of exportFolders to exportFolder
                end if
            end repeat

            do shell script quoted form of "\(escapedPath)" & " --lightroom-export" & fileArgs
            delay 0.3

            repeat with exportFolder in exportFolders
                do shell script "/usr/bin/open " & quoted form of (exportFolder as text)
            end repeat
        end open

        on run
            do shell script quoted form of "\(escapedPath)" & " --help"
        end run
        """
    }
}
