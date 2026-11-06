import SwiftUI

// MARK: - Palette: high contrast on frosted glass, adapts to light / dark

extension Color {
    static func adaptive(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        })
    }

    /// Wash over the blur so the glass reads bright (light) or deep (dark), never muddy grey.
    /// Light: a pale grey (like iOS grouped backgrounds) so white cards and screenshots keep their edges.
    static let glassTint = adaptive(light: NSColor(white: 0.9, alpha: 0.15),
                                    dark: NSColor.black.withAlphaComponent(0.2))
    /// Bubbles, inputs and secondary buttons.
    static let bubble = adaptive(light: NSColor.white.withAlphaComponent(0.92),
                                 dark: NSColor.white.withAlphaComponent(0.13))
    static let ink = adaptive(light: .black, dark: .white)
    static let inkSoft = adaptive(light: NSColor.black.withAlphaComponent(0.55),
                                  dark: NSColor.white.withAlphaComponent(0.62))
}

struct PanelActions {
    var capture: (CaptureMode) -> Void
    var openFolder: () -> Void
    var showSettings: () -> Void
    var openPermissionSettings: () -> Void
    var relaunch: () -> Void

    static var noop: PanelActions {
        PanelActions(capture: { _ in }, openFolder: {}, showSettings: {}, openPermissionSettings: {}, relaunch: {})
    }
}

struct PanelView: View {
    static let size = NSSize(width: 240, height: 300)
    /// Width inside the 12pt side margins.
    static let contentWidth = size.width - 24

    let store: ShotStore
    let actions: PanelActions

    var body: some View {
        VStack(spacing: 0) {
            topBar
            if !store.permissionGranted {
                permissionCard
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
            }
            if let warning = store.hotKeyWarning {
                noticeCard(warning)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
            }
            Group {
                if store.shots.isEmpty {
                    emptyState
                } else {
                    list
                }
            }
            .frame(maxHeight: .infinity)
            footer
                .padding(12)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .background(WindowDragArea()) // empty spots move the panel too
        .background(Color.glassTint)
        .clipShape(RoundedRectangle(cornerRadius: GlassPanel.cornerRadius, style: .continuous))
        .foregroundStyle(Color.ink)
    }

    // MARK: - Rows

    private enum Row: Identifiable {
        case header(Date)
        case shot(Shot)

        var id: String {
            switch self {
            case .header(let day): "h-\(day.timeIntervalSince1970)"
            case .shot(let shot): shot.id.uuidString
            }
        }
    }

    private var rows: [Row] {
        var rows: [Row] = []
        var currentDay: Date?
        for shot in store.shots {
            let day = Calendar.current.startOfDay(for: shot.createdAt)
            if day != currentDay {
                rows.append(.header(day))
                currentDay = day
            }
            rows.append(.shot(shot))
        }
        return rows
    }

    private var list: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                ForEach(rows) { row in
                    switch row {
                    case .header(let day):
                        Text(Self.dayTitle(day))
                            .font(.system(size: 13, weight: .bold))
                            .padding(.leading, 4)
                            .padding(.bottom, -8)
                    case .shot(let shot):
                        ShotItem(shot: shot, store: store)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 4)
            .padding(.bottom, 8)
        }
        .scrollIndicators(.never)
    }

    // MARK: - Chrome

    /// Folder at the left, settings at the right, an iOS-style drag handle in between.
    private var topBar: some View {
        HStack(spacing: 0) {
            Button(action: actions.openFolder) {
                roundIcon("folder")
            }
            .buttonStyle(.plain)
            .help("打开截图文件夹")
            Capsule()
                .fill(Color.ink.opacity(0.2))
                .frame(width: 36, height: 5)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(WindowDragArea())
                .help("拖动可以移动面板")
            Button(action: actions.showSettings) {
                roundIcon("gearshape")
            }
            .buttonStyle(.plain)
            .help("设置")
        }
        .frame(height: 28)
        .padding(.horizontal, 10)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button {
                actions.capture(.image)
            } label: {
                pill("截图", icon: "camera.viewfinder", keys: "⌥⇧A", prominent: true)
            }
            .buttonStyle(.plain)
            Button {
                actions.capture(.text)
            } label: {
                pill("识字", icon: "text.viewfinder", keys: "⌥⇧O", prominent: false)
            }
            .buttonStyle(.plain)
        }
    }

    private func pill(_ title: String, icon: String, keys: String, prominent: Bool) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
            Text(title)
                .font(.system(size: 12, weight: .semibold))
            Text(keys)
                .font(.system(size: 10, weight: .semibold))
                .opacity(0.65)
        }
        .foregroundStyle(prominent ? Color.white : Color.ink)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity)
        .frame(height: 32)
        .background(prominent ? Color.accentColor : Color.bubble,
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .contentShape(Rectangle())
    }

    private func roundIcon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 12, weight: .semibold))
            .frame(width: 28, height: 28)
            .background(Color.bubble, in: Circle())
            .contentShape(Circle())
    }

    private var permissionCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "lock.shield.fill")
                    .foregroundStyle(Color.orange)
                Text("需要开启录屏权限")
                    .font(.system(size: 13, weight: .bold))
            }
            Text("系统设置 › 隐私与安全性 › 录屏与系统录音，打开 ShotShelf 后点「重新启动」。")
                .font(.system(size: 12))
                .foregroundStyle(Color.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                smallButton("打开系统设置", prominent: true, action: actions.openPermissionSettings)
                smallButton("重新启动", prominent: false, action: actions.relaunch)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.bubble, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func noticeCard(_ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "keyboard")
                .foregroundStyle(Color.orange)
            Text(text)
                .font(.system(size: 12))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.bubble, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func smallButton(_ title: String, prominent: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(prominent ? Color.white : Color.ink)
                .padding(.horizontal, 12)
                .frame(height: 30)
                .background(prominent ? Color.accentColor : Color.ink.opacity(0.08), in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    /// Drops the icon when the panel is too short for it.
    private var emptyState: some View {
        ViewThatFits(in: .vertical) {
            emptyContent(showIcon: true)
            emptyContent(showIcon: false)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func emptyContent(showIcon: Bool) -> some View {
        VStack(spacing: 12) {
            if showIcon {
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 52, height: 52)
                    .background(Color.bubble, in: Circle())
            }
            Text("还没有截图")
                .font(.system(size: 15, weight: .bold))
            VStack(alignment: .leading, spacing: 12) {
                hintLine("⌥⇧A", "截图，可以打码、识字")
                hintLine("⌥⇧O", "截图后直接识字并复制")
                hintLine("⌥⇧S", "随时打开这个截图记录")
            }
            .padding(14)
            .background(Color.bubble, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            Text("文件保存在「图片 › ShotShelf」")
                .font(.system(size: 12))
                .foregroundStyle(Color.inkSoft)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func hintLine(_ keys: String, _ text: String) -> some View {
        HStack(spacing: 12) {
            Text(keys)
                .font(.system(size: 12, weight: .bold))
                .frame(width: 42, height: 22)
                .background(Color.ink.opacity(0.07), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            Text(text)
                .font(.system(size: 12))
        }
    }

    private static func dayTitle(_ day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "今天" }
        if calendar.isDateInYesterday(day) { return "昨天" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = calendar.isDate(day, equalTo: Date(), toGranularity: .year)
            ? "M月d日 EEEE" : "yyyy年M月d日"
        return formatter.string(from: day)
    }
}

// MARK: - One screenshot: image bubble, text bubble, meta row (chat-like)

struct ShotItem: View {
    let shot: Shot
    let store: ShotStore
    @State private var thumbnail: NSImage?
    @State private var flash: String?

    private var url: URL { store.url(for: shot) }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    /// Fit into the list width, never upscale past the screenshot's real point size.
    private var displaySize: CGSize {
        let maxWidth = PanelView.contentWidth, maxHeight: CGFloat = 170
        let pw = CGFloat(max(shot.pixelWidth, 1)), ph = CGFloat(max(shot.pixelHeight, 1))
        let scale = CGFloat(max(shot.scale, 1))
        var width = min(pw / scale, maxWidth)
        var height = width * ph / pw
        if height > maxHeight {
            height = maxHeight
            width = height * pw / ph
        }
        return CGSize(width: max(width, 32), height: max(height, 24))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            imageBubble
            if let text = shot.text, !text.isEmpty {
                Text(text)
                    .font(.system(size: 13))
                    .lineSpacing(2)
                    .lineLimit(4)
                    .textSelection(.enabled)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(Color.bubble, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            metaRow
        }
        .contextMenu { menuItems }
        .task(id: shot.fileName) {
            thumbnail = await Thumbnails.shared.load(url)
        }
    }

    private var imageBubble: some View {
        Group {
            if let image = thumbnail ?? Thumbnails.shared.cached(url) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
            } else {
                Color.bubble
            }
        }
        .frame(width: displaySize.width, height: displaySize.height)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            if let flash {
                Text(flash)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.black.opacity(0.72)))
            }
        }
        .overlay {
            FileDragSource(url: url, image: thumbnail ?? Thumbnails.shared.cached(url),
                           tooltip: "点击复制图片，也可以直接拖到微信、桌面等地方",
                           menuItems: menuActions) { copyImage() }
        }
    }

    /// Right-click menu for the image (the AppKit drag view sits on top of SwiftUI's .contextMenu).
    private var menuActions: [(String, () -> Void)] {
        [
            ("复制图片", { copyImage() }),
            ("复制文字", { copyText() }),
            ("打开", { NSWorkspace.shared.open(url) }),
            ("在 Finder 中显示", { NSWorkspace.shared.activateFileViewerSelecting([url]) }),
            ("移到废纸篓", { store.delete(shot) }),
        ]
    }

    private var metaRow: some View {
        HStack(spacing: 2) {
            Text(Self.timeFormatter.string(from: shot.createdAt))
                .font(.system(size: 12, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(Color.inkSoft)
            if store.recognizing.contains(shot.id) {
                Text("· 识别中")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.inkSoft)
            }
            Spacer(minLength: 0)
            action("doc.on.doc", "复制图片") { copyImage() }
            action("text.viewfinder", shot.text == nil ? "识别并复制文字" : "复制文字") { copyText() }
            action("folder", "在 Finder 中显示") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            action("trash", "移到废纸篓") { store.delete(shot) }
        }
        .padding(.leading, 4)
    }

    private func action(_ icon: String, _ title: String, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.ink.opacity(0.7))
                .frame(width: 28, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(title)
    }

    @ViewBuilder
    private var menuItems: some View {
        ForEach(Array(menuActions.enumerated()), id: \.offset) { _, item in
            Button(item.0, action: item.1)
        }
    }

    private func copyImage() {
        if Clipboard.copyImage(at: url) { showFlash("已复制图片") }
    }

    private func copyText() {
        Task {
            let text = await store.text(for: shot)
            if text.isEmpty {
                showFlash("没有识别到文字")
            } else {
                Clipboard.copyText(text)
                showFlash("已复制文字")
            }
        }
    }

    private func showFlash(_ message: String) {
        flash = message
        Task {
            try? await Task.sleep(for: .seconds(1))
            if flash == message { flash = nil }
        }
    }
}
