import Foundation

enum AppStatus: Equatable {
    case idle
    case ready(Int)
    case notice(String)
    case success(String)
    case failure(String)

    var message: String {
        switch self {
        case .idle:
            "未选择文件夹"
        case .ready(let count):
            count == 0 ? "没有需要改名的文件" : "待处理 \(count) 个文件"
        case .notice(let message), .success(let message), .failure(let message):
            message
        }
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var folder: URL?
    @Published var rules = RenameRules()
    @Published var plan: [RenameItem] = []
    @Published var status = AppStatus.idle
    @Published var exportActionTarget = ExportActionInstaller.selectedTarget
    @Published var exportActionStatus = "未安装"

    init() {
        loadConfig()
        refreshExportActionStatus()
    }

    func setFolder(_ url: URL) {
        folder = url.hasDirectoryPath ? url : url.deletingLastPathComponent()
        preview()
    }

    func preview() {
        guard let folder else {
            plan = []
            status = .idle
            return
        }
        do {
            plan = try RenameEngine.buildPlan(base: folder, rules: rules)
            status = .ready(plan.count)
        } catch {
            plan = []
            status = .failure("预览失败：\(error.localizedDescription)")
        }
    }

    func applyRename() {
        guard let folder else {
            status = .idle
            return
        }
        guard !plan.isEmpty else {
            status = .notice("没有需要改名的文件")
            return
        }
        do {
            let current = plan
            _ = try RenameEngine.writeLog(base: folder, plan: current)
            try RenameEngine.apply(current)
            preview()
            status = .success("已完成 \(current.count) 个文件的改名")
        } catch {
            status = .failure("改名失败：\(error.localizedDescription)")
        }
    }

    func undo() {
        do {
            let count = try RenameEngine.undoLast()
            preview()
            status = count == 0
                ? .notice("没有可撤销的改名")
                : .success("已撤销 \(count) 个文件的改名")
        } catch {
            status = .failure("撤销失败：\(error.localizedDescription)")
        }
    }

    func saveConfig() {
        do {
            try ConfigStore.saveRules(rules)
            status = .success("改名规则已保存")
        } catch {
            status = .failure("保存失败：\(error.localizedDescription)")
        }
    }

    func installExportAction() {
        do {
            try ExportActionInstaller.install(to: exportActionTarget)
            refreshExportActionStatus()
            status = .success("Lightroom Export Action 已安装")
        } catch {
            refreshExportActionStatus()
            status = .failure("安装失败：\(error.localizedDescription)")
        }
    }

    func setExportActionTarget(_ url: URL) {
        exportActionTarget = ExportActionInstaller.target(for: url)
        ExportActionInstaller.setCustomTarget(url)
        refreshExportActionStatus()
    }

    func resetExportActionTarget() {
        ExportActionInstaller.resetTarget()
        exportActionTarget = ExportActionInstaller.selectedTarget
        refreshExportActionStatus()
    }

    func refreshExportActionStatus() {
        exportActionStatus = ExportActionInstaller.statusText(for: exportActionTarget)
    }

    private func loadConfig() {
        rules = ConfigStore.loadRules()
    }
}
