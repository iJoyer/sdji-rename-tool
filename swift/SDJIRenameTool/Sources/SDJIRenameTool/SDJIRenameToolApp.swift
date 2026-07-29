import SwiftUI
import AppKit

@main
struct SDJIRenameToolApp: App {
    init() {
        AppCommandLine.runIfRequested()
    }

    var body: some Scene {
        WindowGroup("SDJI Rename Tool") {
            ContentView()
                .frame(minWidth: 760, minHeight: 540)
        }
        .defaultSize(width: 920, height: 680)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}

struct ContentView: View {
    @StateObject private var model = AppModel()
    @State private var showConfirmation = false
    @State private var showRules = false
    @State private var showLightroom = false
    @State private var isDropTarget = false

    var body: some View {
        ZStack {
            WindowGlassBackground()
                .ignoresSafeArea()

            VStack(spacing: 0) {
                AppHeader(
                    chooseFolder: chooseFolder,
                    rulesPresented: showRules,
                    showRules: { showRules.toggle() },
                    showLightroom: { showLightroom = true }
                )

                MainStage(
                    model: model,
                    isDropTarget: isDropTarget
                )
                .contentShape(Rectangle())
                .onDrop(of: [.fileURL], isTargeted: $isDropTarget) { providers in
                    handleDrop(providers)
                }

                AppFooter(
                    model: model,
                    requestRename: { showConfirmation = true }
                )
            }
        }
        .ignoresSafeArea(.container, edges: .top)
        .background(WindowConfigurator())
        .inspector(isPresented: $showRules) {
            RulesSidebar(model: model, isPresented: $showRules)
                .inspectorColumnWidth(min: 300, ideal: 330, max: 390)
        }
        .sheet(isPresented: $showLightroom) {
            LightroomActionSheet(model: model)
        }
        .confirmationDialog(
            "应用 \(model.plan.count) 项改名？",
            isPresented: $showConfirmation,
            titleVisibility: .visible
        ) {
            Button("应用改名", role: .destructive) {
                model.applyRename()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("文件会直接在所选文件夹中改名，完成后可使用“撤销上次改名”。")
        }
        .onChange(of: model.rules) {
            model.preview()
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "选择"
        panel.message = "选择包含待改名图片的文件夹"
        if panel.runModal() == .OK, let url = panel.url {
            model.setFolder(url)
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
            guard let data = item as? Data,
                  let string = String(data: data, encoding: .utf8),
                  let url = URL(string: string) else {
                return
            }
            Task { @MainActor in
                model.setFolder(url)
            }
        }
        return true
    }
}

struct AppHeader: View {
    let chooseFolder: () -> Void
    let rulesPresented: Bool
    let showRules: () -> Void
    let showLightroom: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 12) {
            AdaptiveAppIcon(colorScheme: colorScheme)

            VStack(alignment: .leading, spacing: 1) {
                Text("SDJI Rename Tool")
                    .font(.title3.weight(.semibold))
                Text(AppVersion.display)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .tracking(0.5)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 8) {
                HeaderIconButton(
                    title: "选择文件夹",
                    systemImage: "folder.badge.plus",
                    action: chooseFolder
                )
                .keyboardShortcut("o", modifiers: .command)

                HeaderIconButton(
                    title: "Lightroom Export Action",
                    systemImage: "camera.aperture",
                    action: showLightroom
                )

                SidebarToggleButton(
                    isPresented: rulesPresented,
                    action: showRules
                )
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 44)
        .padding(.bottom, 18)
    }
}

struct MainStage: View {
    @ObservedObject var model: AppModel
    let isDropTarget: Bool

    var body: some View {
        Group {
            if isDropTarget {
                DropPrompt(
                    systemImage: "arrow.down.folder.fill",
                    title: "松开以选择这个文件夹",
                    subtitle: "随后会自动生成改名预览"
                )
            } else if model.folder == nil {
                DropPrompt(
                    systemImage: "photo.stack",
                    title: "拖入图片文件夹",
                    subtitle: "支持批量改名与子文件夹扫描"
                )
            } else if model.plan.isEmpty {
                DropPrompt(
                    systemImage: "checkmark.circle",
                    title: "没有需要改名的文件",
                    subtitle: "文件名已符合规则，或没有匹配的图片格式"
                )
            } else {
                RenamePreviewList(model: model)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct DropPrompt: View {
    let systemImage: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 13) {
            Image(systemName: systemImage)
                .font(.system(size: 42, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            Text(title)
                .font(.title2.weight(.semibold))

            Text(subtitle)
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
        .accessibilityElement(children: .combine)
    }
}

struct RenamePreviewList: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.folder?.lastPathComponent ?? "改名预览")
                        .font(.headline)
                    Text(model.folder?.path ?? "")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer()

                Text("\(model.plan.count) 个文件")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 12)

            HStack(spacing: 10) {
                Text("原文件名")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "arrow.right")
                    .frame(width: 24)
                    .accessibilityHidden(true)
                Text("改名后")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 28)
            .padding(.vertical, 8)

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(model.plan.enumerated()), id: \.element.id) { index, item in
                        RenamePreviewRow(
                            source: item.sourceName(relativeTo: baseURL(for: item)),
                            target: item.targetName(relativeTo: baseURL(for: item)),
                            sourcePath: item.source.path,
                            targetPath: item.target.path
                        )
                        .background(
                            index.isMultiple(of: 2)
                                ? Color.primary.opacity(0.03)
                                : Color.clear
                        )
                    }
                }
            }
        }
    }

    private func baseURL(for item: RenameItem) -> URL {
        model.folder ?? item.source.deletingLastPathComponent()
    }
}

struct RenamePreviewRow: View {
    let source: String
    let target: String
    let sourcePath: String
    let targetPath: String

    var body: some View {
        HStack(spacing: 10) {
            filename(source, help: sourcePath)
                .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "arrow.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(width: 24)
                .accessibilityHidden(true)

            filename(target, help: targetPath)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("原文件名 \(source)，改名后 \(target)")
    }

    private func filename(_ text: String, help: String) -> some View {
        Text(text)
            .font(.system(size: 12.5, design: .monospaced))
            .lineLimit(1)
            .truncationMode(.middle)
            .help(help)
            .textSelection(.enabled)
    }
}

struct AppFooter: View {
    @ObservedObject var model: AppModel
    let requestRename: () -> Void

    var body: some View {
        HStack(alignment: .bottom, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Label(model.status.message, systemImage: model.status.symbolName)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(model.status.tint)

                if let folder = model.folder {
                    Label(folder.path, systemImage: "folder")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(folder.path)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 10) {
                GlassActionButton(
                    title: "撤销上次",
                    systemImage: "arrow.uturn.backward",
                    action: model.undo
                )

                ApplyRenameButton(
                    count: model.plan.count,
                    disabled: model.plan.isEmpty,
                    action: requestRename
                )
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 14)
        .padding(.bottom, 24)
    }
}

struct RulesSidebar: View {
    @ObservedObject var model: AppModel
    @Binding var isPresented: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("改名规则")
                        .font(.title3.weight(.semibold))
                    Text("修改后自动刷新预览")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    isPresented = false
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .help("关闭")
                .accessibilityLabel("关闭改名规则")
            }
            .padding(16)

            Form {
                Section("扫描范围") {
                    TextField("文件格式", text: extensionsBinding)
                        .help("使用逗号分隔扩展名")
                    Toggle("包含子文件夹", isOn: $model.rules.recursive)
                }

                Section("DJI 文件名") {
                    Toggle("启用 DJI 规则", isOn: $model.rules.djiEnabled)
                    TextField("识别前缀", text: $model.rules.prefix)
                        .disabled(!model.rules.djiEnabled)
                    Toggle("删除前缀后的时间戳", isOn: $model.rules.removeMiddleTimestamp)
                        .disabled(!model.rules.djiEnabled)
                    Toggle("只删除紧跟前缀的时间戳", isOn: $model.rules.timestampMustFollowPrefix)
                        .disabled(!model.rules.djiEnabled || !model.rules.removeMiddleTimestamp)
                    Toggle("清理后删除末尾 -数字", isOn: $model.rules.removeExistingTrailingDashNumber)
                        .disabled(!model.rules.djiEnabled)
                }

                Section("名称冲突") {
                    Picker("命名策略", selection: $model.rules.conflictStrategy) {
                        ForEach(ConflictStrategy.allCases) { strategy in
                            Text(strategy.label).tag(strategy.rawValue)
                        }
                    }

                    Stepper(
                        "起始编号：\(model.rules.conflictStartIndex)",
                        value: $model.rules.conflictStartIndex,
                        in: 2...9999
                    )
                    .disabled(model.rules.conflictStrategy == ConflictStrategy.skip.rawValue)
                }

                Section("标记处理") {
                    LabeledContent("保留") {
                        TextField("-T, -L", text: keepMarkersBinding)
                            .multilineTextAlignment(.trailing)
                    }

                    LabeledContent("删除") {
                        TextField("-D, -HDR", text: removeMarkersBinding)
                            .multilineTextAlignment(.trailing)
                    }

                    Text("多个标记请用逗号分隔。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .disabled(!model.rules.djiEnabled)
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button {
                    model.saveConfig()
                } label: {
                    Text("保存配置")
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut("s", modifiers: .command)
            }
            .padding(14)
        }
    }

    private var extensionsBinding: Binding<String> {
        Binding(
            get: { model.rules.extensions.joined(separator: ", ") },
            set: { model.rules.extensions = parseList($0, lowercase: true, stripDot: true) }
        )
    }

    private var keepMarkersBinding: Binding<String> {
        Binding(
            get: { model.rules.keepMarkers.joined(separator: ", ") },
            set: { model.rules.keepMarkers = parseList($0, lowercase: false, stripDot: false) }
        )
    }

    private var removeMarkersBinding: Binding<String> {
        Binding(
            get: { model.rules.removeMarkers.joined(separator: ", ") },
            set: { model.rules.removeMarkers = parseList($0, lowercase: false, stripDot: false) }
        )
    }
}

struct LightroomActionSheet: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SheetHeader(
                title: "Lightroom Export Action",
                subtitle: "导出完成后自动应用当前改名规则",
                dismiss: dismiss
            )

            Label(model.exportActionStatus, systemImage: exportActionSymbol)
                .font(.headline)
                .foregroundStyle(exportActionTint)

            VStack(alignment: .leading, spacing: 6) {
                Text("安装位置")
                    .font(.headline)
                Text(model.exportActionTarget.label)
                    .font(.callout)
                Text(model.exportActionTarget.exportActionsFolder.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(3)
                    .truncationMode(.middle)
            }

            HStack(spacing: 10) {
                Button {
                    model.installExportAction()
                } label: {
                    Text(model.exportActionStatus == "已安装" ? "重新安装" : "安装")
                }
                .buttonStyle(.borderedProminent)

                Button("选择 App 或目录…") {
                    chooseExportActionTarget()
                }

                Button("恢复默认位置") {
                    model.resetExportActionTarget()
                }
            }

            Spacer()

            HStack {
                Spacer()
                Button("完成") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 540, height: 330)
        .onAppear {
            model.refreshExportActionStatus()
        }
    }

    private var exportActionSymbol: String {
        switch model.exportActionStatus {
        case "已安装":
            "checkmark.circle.fill"
        case "需要更新":
            "arrow.triangle.2.circlepath.circle.fill"
        default:
            "circle.dashed"
        }
    }

    private var exportActionTint: Color {
        switch model.exportActionStatus {
        case "已安装":
            .green
        case "需要更新":
            .orange
        default:
            .secondary
        }
    }

    private func chooseExportActionTarget() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.treatsFilePackagesAsDirectories = false
        panel.prompt = "选择"
        panel.message = "选择 Lightroom CC.app，或选择 Export Actions 文件夹"
        if panel.runModal() == .OK, let url = panel.url {
            model.setExportActionTarget(url)
        }
    }
}

struct SheetHeader: View {
    let title: String
    let subtitle: String
    let dismiss: DismissAction

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.title2.weight(.semibold))
                Text(subtitle)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .help("关闭")
            .accessibilityLabel("关闭")
        }
        .padding(20)
    }
}

struct GlassActionButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    @ViewBuilder
    var body: some View {
        if #available(macOS 26.0, *) {
            button
                .buttonStyle(.glass)
        } else {
            button
                .buttonStyle(.bordered)
        }
    }

    private var button: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
        }
    }
}

struct HeaderIconButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help(title)
        .accessibilityLabel(title)
    }
}

struct SidebarToggleButton: View {
    let isPresented: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "sidebar.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isPresented ? Color.accentColor : Color.primary)
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help(isPresented ? "隐藏改名规则" : "显示改名规则")
        .accessibilityLabel(isPresented ? "隐藏改名规则侧栏" : "显示改名规则侧栏")
    }
}

struct ApplyRenameButton: View {
    let count: Int
    let disabled: Bool
    let action: () -> Void

    @ViewBuilder
    var body: some View {
        if #available(macOS 26.0, *) {
            button
                .buttonStyle(.glassProminent)
        } else {
            button
                .buttonStyle(.borderedProminent)
        }
    }

    private var button: some View {
        Button(action: action) {
            Label(
                count > 0 ? "应用改名（\(count)）" : "应用改名",
                systemImage: "checkmark"
            )
        }
        .disabled(disabled)
        .keyboardShortcut(.return, modifiers: .command)
    }
}

struct AdaptiveAppIcon: View {
    let colorScheme: ColorScheme

    var body: some View {
        Group {
            if let image = AppIconManager.image(for: colorScheme) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
            } else {
                Image(systemName: "photo.stack")
                    .resizable()
                    .scaledToFit()
                    .padding(10)
                    .foregroundStyle(Color.accentColor)
            }
        }
        .frame(width: 44, height: 44)
        .accessibilityHidden(true)
    }
}

private struct WindowGlassBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        if #available(macOS 26.0, *) {
            let view = NSGlassEffectView()
            view.style = .regular
            view.cornerRadius = 0
            view.tintColor = NSColor.windowBackgroundColor.withAlphaComponent(0.06)
            return view
        }

        let view = NSVisualEffectView()
        view.material = .underWindowBackground
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

private struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        configure(view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        configure(nsView)
    }

    private func configure(_ view: NSView) {
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.isOpaque = false
            window.backgroundColor = .clear
            window.titlebarAppearsTransparent = true
            window.titlebarSeparatorStyle = .none
            window.titleVisibility = .hidden
            window.styleMask.insert(.fullSizeContentView)
            window.isMovableByWindowBackground = true
        }
    }
}

private extension AppStatus {
    var symbolName: String {
        switch self {
        case .idle:
            "folder"
        case .ready(let count):
            count == 0 ? "checkmark.circle" : "arrow.right.circle.fill"
        case .notice:
            "info.circle.fill"
        case .success:
            "checkmark.circle.fill"
        case .failure:
            "exclamationmark.triangle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .idle, .notice:
            .secondary
        case .ready(let count):
            count == 0 ? .secondary : .primary
        case .success:
            .green
        case .failure:
            .red
        }
    }
}

private enum AppIconManager {
    static func image(for colorScheme: ColorScheme) -> NSImage? {
        let resourceName = colorScheme == .dark ? "AppIconDark" : "AppIconLight"
        let bundles = [Bundle.main, Bundle.module]

        guard let url = bundles.lazy.compactMap({
            $0.url(forResource: resourceName, withExtension: "icns")
        }).first else {
            return nil
        }
        return NSImage(contentsOf: url)
    }
}

private enum AppVersion {
    static var display: String {
        let version = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String
        return "v\(version ?? "1.0")"
    }
}

private func parseList(_ value: String, lowercase: Bool, stripDot: Bool) -> [String] {
    value
        .replacingOccurrences(of: "，", with: ",")
        .replacingOccurrences(of: ",", with: "\n")
        .split(separator: "\n")
        .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
        .map { stripDot ? $0.trimmingCharacters(in: CharacterSet(charactersIn: ".")) : $0 }
        .map { lowercase ? $0.lowercased() : $0 }
        .filter { !$0.isEmpty }
        .reduce(into: []) { result, item in
            if !result.contains(item) {
                result.append(item)
            }
        }
}
