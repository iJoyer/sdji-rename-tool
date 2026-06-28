import Foundation

@MainActor
final class AppModel: ObservableObject {
    @Published var folder: URL?
    @Published var rules = RenameRules()
    @Published var plan: [RenameItem] = []
    @Published var status = "未选择文件夹"

    private let configURL: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("SDJI Rename Tool").appendingPathComponent("config.json")
    }()

    init() {
        loadConfig()
    }

    func setFolder(_ url: URL) {
        folder = url.hasDirectoryPath ? url : url.deletingLastPathComponent()
        preview()
    }

    func preview() {
        guard let folder else {
            plan = []
            status = "未选择文件夹"
            return
        }
        do {
            plan = try RenameEngine.buildPlan(base: folder, rules: rules)
            status = "待处理 \(plan.count) 个文件"
        } catch {
            plan = []
            status = "预览失败: \(error.localizedDescription)"
        }
    }

    func applyRename() {
        guard let folder else {
            status = "未选择文件夹"
            return
        }
        guard !plan.isEmpty else {
            status = "没有需要改名的文件"
            return
        }
        do {
            let current = plan
            _ = try RenameEngine.writeLog(base: folder, plan: current)
            try RenameEngine.apply(current)
            preview()
            status = "改名完成: \(current.count) 个文件"
        } catch {
            status = "改名失败: \(error.localizedDescription)"
        }
    }

    func undo() {
        do {
            let count = try RenameEngine.undoLast()
            preview()
            status = "撤销完成: \(count) 个文件"
        } catch {
            status = "撤销失败: \(error.localizedDescription)"
        }
    }

    func saveConfig() {
        do {
            try FileManager.default.createDirectory(
                at: configURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try JSONEncoder().encode(rules).write(to: configURL)
            status = "配置已保存"
        } catch {
            status = "保存失败: \(error.localizedDescription)"
        }
    }

    private func loadConfig() {
        guard let data = try? Data(contentsOf: configURL),
              let saved = try? JSONDecoder().decode(RenameRules.self, from: data) else {
            return
        }
        rules = saved
    }
}
