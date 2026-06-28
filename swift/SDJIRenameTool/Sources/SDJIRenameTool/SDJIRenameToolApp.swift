import SwiftUI
import AppKit

@main
struct SDJIRenameToolApp: App {
    init() {
        AppCommandLine.runIfRequested()
        FontLoader.load()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 1040, minHeight: 680)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}

enum FontLoader {
    static func load() {
        ["Oxanium-Regular", "Oxanium-SemiBold", "Oxanium-Bold"].forEach { name in
            let url: URL?
            if let bundled = Bundle.main.url(forResource: name, withExtension: "ttf", subdirectory: "Fonts") {
                url = bundled
            } else {
                url = Bundle.module.url(forResource: name, withExtension: "ttf", subdirectory: "Fonts")
            }
            guard let url else { return }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}

struct ContentView: View {
    @StateObject private var model = AppModel()
    @State private var showConfirm = false

    var body: some View {
        VStack(spacing: 0) {
            Toolbar(model: model, showConfirm: $showConfirm)
            Divider()
            HStack(spacing: 0) {
                Sidebar(model: model)
                    .frame(width: 338)
                Divider()
                PreviewPane(model: model, showConfirm: $showConfirm)
            }
        }
        .background(AppColor.canvas)
        .onChange(of: model.rules.recursive) { model.preview() }
        .onChange(of: model.rules.extensions) { model.preview() }
        .onChange(of: model.rules.djiEnabled) { model.preview() }
        .onChange(of: model.rules.prefix) { model.preview() }
        .onChange(of: model.rules.removeMiddleTimestamp) { model.preview() }
        .onChange(of: model.rules.timestampMustFollowPrefix) { model.preview() }
        .onChange(of: model.rules.keepMarkers) { model.preview() }
        .onChange(of: model.rules.removeMarkers) { model.preview() }
        .onChange(of: model.rules.removeExistingTrailingDashNumber) { model.preview() }
        .onChange(of: model.rules.conflictStrategy) { model.preview() }
        .onChange(of: model.rules.conflictStartIndex) { model.preview() }
        .confirmationDialog("确认执行改名 \(model.plan.count) 个文件吗？", isPresented: $showConfirm) {
            Button("应用改名", role: .destructive) { model.applyRename() }
            Button("取消", role: .cancel) {}
        }
    }
}

struct Toolbar: View {
    @ObservedObject var model: AppModel
    @Binding var showConfirm: Bool

    var body: some View {
        HStack(spacing: 12) {
            Text("SDJI Rename Tool")
                .font(.custom("Oxanium", size: 21).weight(.bold))
                .foregroundStyle(AppColor.text)

            StatusPill(text: model.status, count: model.plan.count)
            Spacer()

            Button("预览") { model.preview() }
                .buttonStyle(SecondaryButtonStyle())
            Button("撤销上次") { model.undo() }
                .buttonStyle(SecondaryButtonStyle())
            Button("应用改名") { showConfirm = true }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(model.plan.isEmpty)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 13)
        .background(.regularMaterial)
    }
}

struct Sidebar: View {
    @ObservedObject var model: AppModel
    @State private var isDropTarget = false

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                SectionBox("Source") {
                    VStack(alignment: .leading, spacing: 10) {
                        DropTarget(model: model, isDropTarget: $isDropTarget)
                        Button("选择文件夹") { chooseFolder() }
                            .buttonStyle(SecondaryButtonStyle())
                    }
                }

                LightroomActionSection(model: model)

                SectionBox("Scan") {
                    VStack(alignment: .leading, spacing: 10) {
                        FieldLabel("文件格式")
                        TextField("jpg, jpeg, png", text: Binding(
                            get: { model.rules.extensions.joined(separator: ", ") },
                            set: { model.rules.extensions = parseList($0, lowercase: true, stripDot: true) }
                        ))
                        .textFieldStyle(.plain)
                        .controlChrome()
                        Toggle("包含子文件夹", isOn: $model.rules.recursive)
                    }
                }

                SectionBox("Rules") {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle("启用 DJI 规则", isOn: $model.rules.djiEnabled)
                        FieldLabel("识别前缀")
                        TextField("DJI", text: $model.rules.prefix)
                            .textFieldStyle(.plain)
                            .controlChrome()
                        Toggle("删除前缀后的时间戳", isOn: $model.rules.removeMiddleTimestamp)
                        Toggle("只删除紧跟前缀的时间戳", isOn: $model.rules.timestampMustFollowPrefix)
                        Toggle("清理后删除末尾 -数字", isOn: $model.rules.removeExistingTrailingDashNumber)
                    }
                }

                SectionBox("Conflict") {
                    VStack(alignment: .leading, spacing: 10) {
                        FieldLabel("命名策略")
                        Picker("", selection: $model.rules.conflictStrategy) {
                            ForEach(ConflictStrategy.allCases) { strategy in
                                Text(strategy.label).tag(strategy.rawValue)
                            }
                        }
                        .labelsHidden()
                        .controlSize(.small)
                        .frame(maxWidth: .infinity, alignment: .leading)

                        HStack(spacing: 10) {
                            FieldLabel("起始编号")
                            Spacer()
                            NumberStepper(value: $model.rules.conflictStartIndex)
                                .disabled(model.rules.conflictStrategy == ConflictStrategy.skip.rawValue)
                                .opacity(model.rules.conflictStrategy == ConflictStrategy.skip.rawValue ? 0.45 : 1)
                        }
                    }
                }

                MarkerEditor(title: "Keep", hint: "保留标记，每行一个", markers: $model.rules.keepMarkers)
                MarkerEditor(title: "Remove", hint: "删除标记，每行一个", markers: $model.rules.removeMarkers)

                Button("保存配置") { model.saveConfig() }
                    .buttonStyle(PrimaryButtonStyle())
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(14)
        }
        .background(AppColor.sidebar)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            model.setFolder(url)
        }
    }
}

struct LightroomActionSection: View {
    @ObservedObject var model: AppModel

    var body: some View {
        SectionBox("Lightroom CC Export Action") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(model.exportActionStatus)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(statusColor)
                    Spacer()
                    Circle()
                        .fill(statusColor)
                        .frame(width: 8, height: 8)
                }

                Text(model.exportActionTarget.label)
                    .font(.system(size: 12))
                    .foregroundStyle(AppColor.muted)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 8) {
                    Button(model.exportActionStatus == "已安装" ? "更新" : "安装") {
                        model.installExportAction()
                    }
                    .buttonStyle(PrimaryButtonStyle())

                    Button("选择 App/目录") {
                        chooseExportActionTarget()
                    }
                    .buttonStyle(SecondaryButtonStyle())

                    Button("默认") {
                        model.resetExportActionTarget()
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
            }
        }
    }

    private var statusColor: Color {
        model.exportActionStatus == "已安装" ? AppColor.success : AppColor.muted
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

struct DropTarget: View {
    @ObservedObject var model: AppModel
    @Binding var isDropTarget: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("图片文件夹")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Circle()
                    .fill(model.folder == nil ? AppColor.border : AppColor.success)
                    .frame(width: 8, height: 8)
            }
            Text(model.folder?.path ?? "拖入文件夹或手动选择")
                .font(.system(size: 12))
                .foregroundStyle(AppColor.muted)
                .lineLimit(2)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(AppColor.control)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isDropTarget ? AppColor.accent : AppColor.border, lineWidth: 1)
        )
        .onDrop(of: [.fileURL], isTargeted: $isDropTarget) { providers in
            handleDrop(providers)
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
            Task { @MainActor in model.setFolder(url) }
        }
        return true
    }
}

struct PreviewPane: View {
    @ObservedObject var model: AppModel
    @Binding var showConfirm: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Preview")
                        .font(.custom("Oxanium", size: 16).weight(.semibold))
                    Text(model.folder?.lastPathComponent ?? "No folder selected")
                        .font(.system(size: 12))
                        .foregroundStyle(AppColor.muted)
                }
                Spacer()
                Text("\(model.plan.count)")
                    .font(.custom("Oxanium", size: 24).weight(.bold))
                    .foregroundStyle(AppColor.text)
                Text("items")
                    .font(.system(size: 12))
                    .foregroundStyle(AppColor.muted)
            }
            .padding(16)

            Divider()

            Table(model.plan) {
                TableColumn("原文件名") { item in
                    Text(item.sourceName(relativeTo: model.folder ?? item.source.deletingLastPathComponent()))
                        .font(.system(size: 13, design: .monospaced))
                }
                TableColumn("新文件名") { item in
                    Text(item.targetName(relativeTo: model.folder ?? item.target.deletingLastPathComponent()))
                        .font(.system(size: 13, design: .monospaced))
                }
            }
            .background(Color.white)
        }
        .background(Color.white)
    }
}

struct MarkerEditor: View {
    let title: String
    let hint: String
    @Binding var markers: [String]

    var body: some View {
        SectionBox(title) {
            VStack(alignment: .leading, spacing: 8) {
                Text(hint)
                    .font(.system(size: 12))
                    .foregroundStyle(AppColor.muted)
                TextEditor(text: Binding(
                    get: { markers.joined(separator: "\n") },
                    set: { markers = parseList($0, lowercase: false, stripDot: false) }
                ))
                .font(.system(size: 12, design: .monospaced))
                .scrollContentBackground(.hidden)
                .frame(height: 92)
                .padding(8)
                .background(AppColor.control)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppColor.border))
            }
        }
    }
}

struct NumberStepper: View {
    @Binding var value: Int

    var body: some View {
        HStack(spacing: 0) {
            Button {
                value = max(2, value - 1)
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: 10, weight: .bold))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)

            Text("\(value)")
                .font(.custom("Oxanium", size: 13).weight(.semibold))
                .frame(width: 42, height: 28)
                .background(Color.white)
                .overlay(
                    Rectangle()
                        .fill(AppColor.border)
                        .frame(width: 1),
                    alignment: .leading
                )
                .overlay(
                    Rectangle()
                        .fill(AppColor.border)
                        .frame(width: 1),
                    alignment: .trailing
                )

            Button {
                value = min(9999, value + 1)
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .bold))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(AppColor.text)
        .background(AppColor.control)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(AppColor.border))
    }
}

struct SectionBox<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.custom("Oxanium", size: 12).weight(.semibold))
                .foregroundStyle(AppColor.muted)
                .textCase(.uppercase)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
            content
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(AppColor.border))
    }
}

struct FieldLabel: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(AppColor.muted)
    }
}

struct StatusPill: View {
    let text: String
    let count: Int

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(count > 0 ? AppColor.accent : AppColor.muted)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(count > 0 ? AppColor.accent.opacity(0.08) : AppColor.control)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(count > 0 ? AppColor.accent.opacity(0.18) : AppColor.border))
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.custom("Oxanium", size: 12).weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(configuration.isPressed ? AppColor.accentPressed : AppColor.accent)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.custom("Oxanium", size: 12).weight(.semibold))
            .foregroundStyle(AppColor.text)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(configuration.isPressed ? AppColor.controlPressed : Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(AppColor.border))
    }
}

extension View {
    func controlChrome() -> some View {
        self
            .font(.system(size: 13))
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .background(AppColor.control)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppColor.border))
    }
}

enum AppColor {
    static let canvas = Color(red: 0.965, green: 0.969, blue: 0.976)
    static let sidebar = Color(red: 0.984, green: 0.984, blue: 0.988)
    static let control = Color(red: 0.973, green: 0.973, blue: 0.976)
    static let controlPressed = Color(red: 0.925, green: 0.929, blue: 0.937)
    static let border = Color(red: 0.878, green: 0.886, blue: 0.902)
    static let text = Color(red: 0.067, green: 0.067, blue: 0.067)
    static let muted = Color(red: 0.392, green: 0.408, blue: 0.447)
    static let accent = Color(red: 0.0, green: 0.439, blue: 0.933)
    static let accentPressed = Color(red: 0.0, green: 0.337, blue: 0.733)
    static let success = Color(red: 0.063, green: 0.686, blue: 0.361)
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
