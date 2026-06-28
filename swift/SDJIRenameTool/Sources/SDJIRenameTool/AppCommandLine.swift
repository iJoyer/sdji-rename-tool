import Foundation

enum AppCommandLine {
    static func runIfRequested() {
        let args = Array(CommandLine.arguments.dropFirst())
        guard let first = args.first, first.hasPrefix("--") else { return }

        let code = run(args)
        fflush(stdout)
        fflush(stderr)
        exit(Int32(code))
    }

    private static func run(_ rawArgs: [String]) -> Int {
        let dryRun = rawArgs.contains("--dry-run")
        let args = rawArgs.filter { $0 != "--dry-run" }

        switch args.first {
        case "--rename-folder":
            guard args.count >= 2 else {
                fputs("缺少目录路径。\n", stderr)
                return 2
            }
            return renameFolder(args[1], dryRun: dryRun)

        case "--lightroom-export":
            let paths = Array(args.dropFirst())
            guard !paths.isEmpty else {
                fputs("缺少 Lightroom 导出文件。\n", stderr)
                return 2
            }
            return renameFiles(paths, dryRun: dryRun)

        case "--undo-last":
            do {
                let count = try RenameEngine.undoLast()
                print("撤销完成: \(count) 个文件")
                return 0
            } catch {
                fputs("撤销失败: \(error.localizedDescription)\n", stderr)
                return 1
            }

        case "--config-path":
            print(ConfigStore.configURL.path)
            return 0

        case "--version", "-V":
            print("SDJI Rename Tool 0.1.0")
            return 0

        case "--help", "-h":
            printHelp()
            return 0

        default:
            fputs("未知参数。使用 --help 查看可用命令。\n", stderr)
            return 2
        }
    }

    private static func renameFolder(_ path: String, dryRun: Bool) -> Int {
        let folder = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            fputs("目录不存在: \(folder.path)\n", stderr)
            return 1
        }

        do {
            let rules = ConfigStore.loadRules()
            let plan = try RenameEngine.buildPlan(base: folder, rules: rules)
            return try apply(plan: plan, base: folder, dryRun: dryRun, emptyMessage: "没有需要改名的文件。")
        } catch {
            fputs("改名失败: \(error.localizedDescription)\n", stderr)
            return 1
        }
    }

    private static func renameFiles(_ paths: [String], dryRun: Bool) -> Int {
        let files = paths.map { URL(fileURLWithPath: $0).standardizedFileURL }
        let existingFiles = files.filter { url in
            var isDirectory: ObjCBool = false
            return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && !isDirectory.boolValue
        }

        guard !existingFiles.isEmpty else {
            print("没有可处理的 Lightroom 导出文件。")
            return 0
        }

        do {
            let rules = ConfigStore.loadRules()
            let plan = try RenameEngine.buildPlan(files: existingFiles, rules: rules)
            let base = commonBaseDirectory(for: existingFiles)
            return try apply(plan: plan, base: base, dryRun: dryRun, emptyMessage: "没有需要改名的 Lightroom 导出文件。")
        } catch {
            fputs("Lightroom Export Action 改名失败: \(error.localizedDescription)\n", stderr)
            return 1
        }
    }

    private static func apply(plan: [RenameItem], base: URL, dryRun: Bool, emptyMessage: String) throws -> Int {
        guard !plan.isEmpty else {
            print(emptyMessage)
            return 0
        }

        if dryRun {
            print("待处理: \(plan.count)")
            for item in plan {
                print("\(item.source.path) -> \(item.target.path)")
            }
            print("dry-run=true，未执行实际改名。")
            return 0
        }

        _ = try RenameEngine.writeLog(base: base, plan: plan)
        try RenameEngine.apply(plan)
        print("改名完成: \(plan.count) 个文件")
        return 0
    }

    private static func commonBaseDirectory(for files: [URL]) -> URL {
        let directories = files.map { $0.deletingLastPathComponent().standardizedFileURL.pathComponents }
        guard var common = directories.first else {
            return URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        }

        for components in directories.dropFirst() {
            while !common.isEmpty && !components.starts(with: common) {
                common.removeLast()
            }
        }

        if common.isEmpty {
            return URL(fileURLWithPath: "/", isDirectory: true)
        }
        return URL(fileURLWithPath: NSString.path(withComponents: common), isDirectory: true)
    }

    private static func printHelp() {
        print("""
        SDJI Rename Tool

        --rename-folder <folder>       按 app 配置处理目录
        --lightroom-export <files...>  Lightroom Export Action 模式，只处理传入文件
        --undo-last                    撤销上次改名
        --dry-run                      只预览，不实际改名
        --config-path                  输出 app 配置路径
        """)
    }
}
