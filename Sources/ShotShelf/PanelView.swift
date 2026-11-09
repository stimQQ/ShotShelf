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
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            topBar
            if store.isSearching {
                searchField
            }
            if !store.permissionGranted {
                permissionCard
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
            }
            if !store.busyHotKeys.isEmpty {
                noticeCard(L("快捷键 \(store.busyHotKeys.joined(separator: "、")) 被其他应用占用，可先用下方按钮",
                             "\(store.busyHotKeys.joined(separator: ", ")) is taken by another app. Use the buttons below."))
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
            }
            Group {
                if store.shots.isEmpty {
                    emptyState
                } else if store.isSearching && !searchTokens.isEmpty && store.searchResults.isEmpty {
                    noResults
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

    private var searchTokens: [String] {
        store.isSearching ? ShotStore.searchTokens(store.searchQuery) : []
    }

    private var rows: [Row] {
        var rows: [Row] = []
        var currentDay: Date?
        for shot in store.isSearching ? store.searchResults : store.shots {
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
                        ShotItem(shot: shot, store: store, tokens: searchTokens)
                    }
                }
                if store.isSearching && store.unindexedCount > 0 {
                    indexingNote
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 4)
            .padding(.bottom, 8)
        }
        .scrollIndicators(.never)
    }

    // MARK: - Chrome

    /// Folder and search at the left, settings at the right, an iOS-style drag handle centered.
    private var topBar: some View {
        ZStack {
            Capsule()
                .fill(Color.ink.opacity(0.2))
                .frame(width: 36, height: 5)
                .frame(width: 80, height: 28)
                .overlay(WindowDragArea())
                .help(L("拖动可以移动面板", "Drag to move"))
            HStack(spacing: 6) {
                Button(action: actions.openFolder) {
                    roundIcon("folder")
                }
                .buttonStyle(.plain)
                .help(L("打开截图文件夹", "Open screenshots folder"))
                Button(action: toggleSearch) {
                    roundIcon(store.isSearching ? "xmark" : "magnifyingglass")
                }
                .buttonStyle(.plain)
                .keyboardShortcut("f", modifiers: .command)
                .help(store.isSearching ? L("关闭搜索", "Close search")
                                        : L("搜索截图里的文字 ⌘F", "Search text in screenshots (⌘F)"))
                Spacer(minLength: 0)
                Button(action: actions.showSettings) {
                    roundIcon("gearshape")
                }
                .buttonStyle(.plain)
                .help(L("设置", "Settings"))
            }
        }
        .frame(height: 28)
        .padding(.horizontal, 10)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }

    private func toggleSearch() {
        if store.isSearching {
            store.endSearch()
        } else {
            store.isSearching = true
        }
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.inkSoft)
            TextField(L("搜索截图里的文字", "Search text in screenshots"), text: Bindable(store).searchQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($searchFocused)
                .onExitCommand {
                    if store.searchQuery.isEmpty { store.endSearch() } else { store.searchQuery = "" }
                }
            if !store.searchQuery.isEmpty {
                Button { store.searchQuery = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.inkSoft)
                }
                .buttonStyle(.plain)
                .help(L("清空", "Clear"))
            }
        }
        .padding(.horizontal, 11)
        .frame(height: 30)
        .background(Color.bubble, in: Capsule())
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .onAppear { DispatchQueue.main.async { searchFocused = true } }
    }

    private var noResults: some View {
        VStack(spacing: 8) {
            Image(systemName: "text.magnifyingglass")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(Color.inkSoft)
            Text(L("没有截图包含「\(store.searchQuery.trimmingCharacters(in: .whitespaces))」",
                   "No screenshots contain “\(store.searchQuery.trimmingCharacters(in: .whitespaces))”"))
                .font(.system(size: 13, weight: .semibold))
                .multilineTextAlignment(.center)
            if store.unindexedCount > 0 {
                indexingNote
            }
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity)
    }

    private var indexingNote: some View {
        Text(L("还有 \(store.unindexedCount) 张截图正在识别文字", "Still reading text in \(store.unindexedCount) screenshots"))
            .font(.system(size: 11))
            .foregroundStyle(Color.inkSoft)
            .frame(maxWidth: .infinity)
    }

    /// Shows the shortcut keys when they fit (Chinese), drops them when they don't (English).
    private var footer: some View {
        ViewThatFits(in: .horizontal) {
            footerRow(showKeys: true)
            footerRow(showKeys: false)
        }
    }

    /// The main button takes the spare width; the second one hugs its label.
    private func footerRow(showKeys: Bool) -> some View {
        HStack(spacing: 8) {
            Button {
                actions.capture(.image)
            } label: {
                pill(L("截图", "Capture"), icon: "camera.viewfinder", keys: showKeys ? "⌥⇧A" : nil, prominent: true)
            }
            .buttonStyle(.plain)
            Button {
                actions.capture(.text)
            } label: {
                pill(L("识字", "OCR"), icon: "text.viewfinder", keys: showKeys ? "⌥⇧O" : nil, prominent: false)
            }
            .buttonStyle(.plain)
            .fixedSize()
        }
    }

    private func pill(_ title: String, icon: String, keys: String?, prominent: Bool) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
            Text(title)
                .font(.system(size: 12, weight: .semibold))
            if let keys {
                Text(keys)
                    .font(.system(size: 10, weight: .semibold))
                    .opacity(0.65)
            }
        }
        .lineLimit(1)
        .foregroundStyle(prominent ? Color.white : Color.ink)
        .padding(.horizontal, 12)
        .frame(maxWidth: prominent ? .infinity : nil)
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
                Text(L("需要开启录屏权限", "Screen recording permission needed"))
                    .font(.system(size: 13, weight: .bold))
            }
            Text(L("系统设置 › 隐私与安全性 › 录屏与系统录音，打开 ShotShelf 后点「重新启动」。", "System Settings › Privacy & Security › Screen & System Audio Recording: turn on ShotShelf, then click Relaunch."))
                .font(.system(size: 12))
                .foregroundStyle(Color.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                smallButton(L("打开系统设置", "Open Settings"), prominent: true, action: actions.openPermissionSettings)
                smallButton(L("重新启动", "Relaunch"), prominent: false, action: actions.relaunch)
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
            Text(L("还没有截图", "No screenshots yet"))
                .font(.system(size: 15, weight: .bold))
            VStack(alignment: .leading, spacing: 12) {
                hintLine("⌥⇧A", L("截图，可以打码、识字", "Capture, redact, OCR"))
                hintLine("⌥⇧O", L("截图后直接识字并复制", "Capture and copy text"))
                hintLine("⌥⇧S", L("随时打开这个截图记录", "Open this history"))
            }
            .padding(14)
            .background(Color.bubble, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            Text(L("文件保存在「图片 › ShotShelf」", "Saved in Pictures › ShotShelf"))
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
        if calendar.isDateInToday(day) { return L("今天", "Today") }
        if calendar.isDateInYesterday(day) { return L("昨天", "Yesterday") }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: L("zh_CN", "en_US"))
        formatter.dateFormat = calendar.isDate(day, equalTo: Date(), toGranularity: .year)
            ? L("M月d日 EEEE", "EEEE, MMM d") : L("yyyy年M月d日", "MMM d, yyyy")
        return formatter.string(from: day)
    }
}

// MARK: - One screenshot: image bubble, text bubble, meta row (chat-like)

struct ShotItem: View {
    let shot: Shot
    let store: ShotStore
    /// Search words: show the matching lines instead of the full text.
    var tokens: [String] = []
    @State private var thumbnail: NSImage?
    @State private var flash: String?

    private var url: URL { store.url(for: shot) }

    /// Up to two lines that contain a search word, with every match highlighted. Long lines are
    /// cut to start shortly before the first match so it stays visible.
    static func snippet(_ text: String, tokens: [String]) -> AttributedString? {
        let options = ShotStore.searchOptions
        let lines = text.split(separator: "\n").map(String.init)
            .filter { line in tokens.contains { line.range(of: $0, options: options) != nil } }
        guard !lines.isEmpty else { return nil }
        let shown = lines.prefix(2).map { line -> String in
            guard line.count > 60,
                  let first = tokens.compactMap({ line.range(of: $0, options: options) }).min(by: { $0.lowerBound < $1.lowerBound }),
                  line.distance(from: line.startIndex, to: first.lowerBound) > 24
            else { return line }
            let start = line.index(first.lowerBound, offsetBy: -16)
            return "…" + line[start...]
        }
        var result = AttributedString(shown.joined(separator: "\n"))
        for token in tokens {
            var from = result.startIndex
            while from < result.endIndex, let range = result[from...].range(of: token, options: options) {
                result[range].backgroundColor = Color.yellow.opacity(0.6)
                result[range].foregroundColor = Color.black
                result[range].font = .system(size: 12, weight: .semibold)
                from = range.upperBound
            }
        }
        return result
    }

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
            if !tokens.isEmpty, let snippet = Self.snippet(shot.text ?? "", tokens: tokens) {
                Text(snippet)
                    .font(.system(size: 12))
                    .lineSpacing(2)
                    .lineLimit(3)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.bubble, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            } else if shot.showsText, let text = shot.text, !text.isEmpty {
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
                           tooltip: L("点击复制图片，也可以直接拖到微信、桌面等地方", "Click to copy, or drag into any app"),
                           menuItems: menuActions) { copyImage() }
        }
    }

    /// Right-click menu for the image (the AppKit drag view sits on top of SwiftUI's .contextMenu).
    private var menuActions: [(String, () -> Void)] {
        [
            (L("复制图片", "Copy Image"), { copyImage() }),
            (L("复制文字", "Copy Text"), { copyText() }),
            (L("打开", "Open"), { NSWorkspace.shared.open(url) }),
            (L("在 Finder 中显示", "Show in Finder"), { NSWorkspace.shared.activateFileViewerSelecting([url]) }),
            (L("移到废纸篓", "Move to Trash"), { store.delete(shot) }),
        ]
    }

    private var metaRow: some View {
        HStack(spacing: 2) {
            Text(Self.timeFormatter.string(from: shot.createdAt))
                .font(.system(size: 12, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(Color.inkSoft)
            if store.recognizing.contains(shot.id) {
                Text(L("· 识别中", "· Recognizing"))
                    .font(.system(size: 12))
                    .foregroundStyle(Color.inkSoft)
            }
            Spacer(minLength: 0)
            action("doc.on.doc", L("复制图片", "Copy image")) { copyImage() }
            action("text.viewfinder", shot.text == nil ? L("识别并复制文字", "Recognize and copy text") : L("复制文字", "Copy text")) { copyText() }
            action("folder", L("在 Finder 中显示", "Show in Finder")) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            action("trash", L("移到废纸篓", "Move to Trash")) { store.delete(shot) }
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
        if Clipboard.copyImage(at: url) { showFlash(L("已复制图片", "Image copied")) }
    }

    private func copyText() {
        Task {
            let text = await store.text(for: shot)
            if text.isEmpty {
                showFlash(L("没有识别到文字", "No text found"))
            } else {
                Clipboard.copyText(text)
                showFlash(L("已复制文字", "Text copied"))
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
