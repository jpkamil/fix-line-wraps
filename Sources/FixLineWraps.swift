// FixLineWraps.swift — the whole "Fix Line Wraps" app.
//
// A window with a drop zone. Drop .md files (or folders of them) on the window or on the Dock
// icon, or press "Choose Files…". Each file is rewritten in place so every paragraph is one
// line, and the report appears in the window. The work is done by reflow_md.py, carried inside
// the app bundle; it refuses any file whose text would change by more than whitespace.
//
// HOW A FILE REACHES THE TOOL. The app copies each dropped file into a private temporary folder,
// runs reflow_md.py on the copies, and writes back only the copies that changed. The app process
// is the one that holds whatever access the drop or the Open panel granted, so the Python child
// never has to read a protected folder (Desktop, Documents, Downloads) itself. This is the
// difference from the AppleScript droplet this replaced, whose shell child was refused those
// files with "Operation not permitted".
//
// Build: ./build-app.sh --install   (see README.md)

import AppKit
import UniformTypeIdentifiers

let appName = "Fix Line Wraps"

// MARK: - Python

/// The first python3 on this Mac that actually runs. Order: an explicit override, the
/// python.org framework, Homebrew, /usr/local, then Apple's own interpreter — but that one only
/// when the Command Line Tools are installed, because without them /usr/bin/python3 is a stub
/// that pops an installer dialog and blocks.
func findPython() -> String? {
    let fm = FileManager.default
    var candidates: [String] = []
    if let env = ProcessInfo.processInfo.environment["COMPASS_PYTHON"], !env.isEmpty { candidates.append(env) }
    candidates += ["/Library/Frameworks/Python.framework/Versions/Current/bin/python3",
                   "/opt/homebrew/bin/python3",
                   "/usr/local/bin/python3"]
    if fm.fileExists(atPath: "/Library/Developer/CommandLineTools/usr/bin/python3")
        || fm.fileExists(atPath: "/Applications/Xcode.app") {
        candidates.append("/usr/bin/python3")
    }
    for c in candidates where fm.isExecutableFile(atPath: c) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: c)
        p.arguments = ["-I", "-c", "import sys; print(sys.version_info[0])"]
        let out = Pipe(); p.standardOutput = out; p.standardError = Pipe()
        do { try p.run() } catch { continue }
        p.waitUntilExit()
        let s = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        if p.terminationStatus == 0, s.trimmingCharacters(in: .whitespacesAndNewlines) == "3" { return c }
    }
    return nil
}

// MARK: - The work

struct Outcome {
    var report = ""
    var permissionTrouble = false
}

/// Expand folders to the .md files inside them; keep plain files as they are.
func expand(_ urls: [URL]) -> [URL] {
    let fm = FileManager.default
    var files: [URL] = []
    for u in urls {
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: u.path, isDirectory: &isDir) else { continue }
        if isDir.boolValue {
            if let e = fm.enumerator(at: u, includingPropertiesForKeys: [.isRegularFileKey],
                                     options: [.skipsHiddenFiles, .skipsPackageDescendants]) {
                for case let f as URL in e where f.pathExtension.lowercased() == "md" { files.append(f) }
            }
        } else {
            files.append(u)
        }
    }
    return files
}

func fix(_ dropped: [URL]) -> Outcome {
    var o = Outcome()
    let files = expand(dropped)
    if files.isEmpty {
        o.report = "  Nothing to do: no files, and no .md files inside the folders dropped.\n"
        return o
    }
    guard let py = findPython() else {
        o.report = """
          ⛔ No python3 on this Mac that will run.
             Install Apple's command line tools:   xcode-select --install
             or a current Python from https://www.python.org/downloads/macos/

        """
        return o
    }
    guard let script = Bundle.main.url(forResource: "reflow_md", withExtension: "py") else {
        o.report = "  ⛔ The app bundle is missing reflow_md.py. Rebuild it with build-app.sh.\n"
        return o
    }

    let fm = FileManager.default
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("fix-line-wraps-" + UUID().uuidString, isDirectory: true)
    defer { try? fm.removeItem(at: tmp) }

    func isPermission(_ error: Error) -> Bool {
        let e = error as NSError
        return e.code == NSFileReadNoPermissionError || e.code == NSFileWriteNoPermissionError
            || e.localizedDescription.localizedCaseInsensitiveContains("permitted")
            || e.localizedDescription.localizedCaseInsensitiveContains("permission")
    }

    // 1. Copy each file in, remembering what it held.
    var pairs: [(orig: URL, copy: URL, before: Data)] = []
    for (i, f) in files.enumerated() {
        do {
            let data = try Data(contentsOf: f)
            let dir = tmp.appendingPathComponent(String(i), isDirectory: true)
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            let copy = dir.appendingPathComponent(f.lastPathComponent)
            try data.write(to: copy)
            pairs.append((f, copy, data))
        } catch {
            o.report += "  ⛔ could not read  \(f.lastPathComponent): \(error.localizedDescription)\n"
            if isPermission(error) { o.permissionTrouble = true }
        }
    }
    guard !pairs.isEmpty else { return o }

    // 2. Run the tool on the copies.
    let p = Process()
    p.executableURL = URL(fileURLWithPath: py)
    p.arguments = ["-I", script.path] + pairs.map { $0.copy.path }
    let out = Pipe(); p.standardOutput = out; p.standardError = out
    do {
        try p.run()
    } catch {
        o.report += "  ⛔ could not start python: \(error.localizedDescription)\n"
        return o
    }
    let data = out.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    o.report += String(data: data, encoding: .utf8) ?? "  (the tool printed something that is not UTF-8)\n"
    if p.terminationStatus != 0 {
        o.report += "  ⛔ the tool exited with status \(p.terminationStatus)\n"
    }

    // 3. Write back only what changed, in place (same file, not a replacement).
    var written = 0
    for pr in pairs {
        guard let after = try? Data(contentsOf: pr.copy), after != pr.before else { continue }
        do {
            try after.write(to: pr.orig, options: [])
            written += 1
        } catch {
            o.report += "  ⛔ fixed, but could not write back  \(pr.orig.lastPathComponent): \(error.localizedDescription)\n"
            if isPermission(error) { o.permissionTrouble = true }
        }
    }
    if written > 0 {
        o.report += "  \(written) file\(written == 1 ? "" : "s") written in place.\n"
    }
    return o
}

// MARK: - Drop zone

final class DropZone: NSView {
    var onDrop: (([URL]) -> Void)?
    let title = NSTextField(labelWithString: "Drop .md files here")
    let subtitle = NSTextField(wrappingLabelWithString: "Files or whole folders. Each paragraph becomes one line; nothing but whitespace ever changes.")
    private var active = false { didSet { needsDisplay = true } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
        wantsLayer = true
        title.font = .systemFont(ofSize: 20, weight: .semibold)
        title.alignment = .center
        subtitle.font = .systemFont(ofSize: 12)
        subtitle.textColor = .secondaryLabelColor
        subtitle.alignment = .center
        let stack = NSStackView(views: [title, subtitle])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -24),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        let r = bounds.insetBy(dx: 2, dy: 2)
        let path = NSBezierPath(roundedRect: r, xRadius: 14, yRadius: 14)
        (active ? NSColor.controlAccentColor.withAlphaComponent(0.14) : NSColor.quaternaryLabelColor.withAlphaComponent(0.25)).setFill()
        path.fill()
        path.lineWidth = 2
        path.setLineDash([8, 6], count: 2, phase: 0)
        (active ? NSColor.controlAccentColor : NSColor.tertiaryLabelColor).setStroke()
        path.stroke()
    }

    private func urls(_ sender: NSDraggingInfo) -> [URL] {
        (sender.draggingPasteboard.readObjects(forClasses: [NSURL.self],
                                                options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
    }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard !urls(sender).isEmpty else { return [] }
        active = true
        return .copy
    }
    override func draggingExited(_ sender: NSDraggingInfo?) { active = false }
    override func draggingEnded(_ sender: NSDraggingInfo) { active = false }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        active = false
        let u = urls(sender)
        guard !u.isEmpty else { return false }
        onDrop?(u)
        return true
    }
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var window: NSWindow!
    var dropZone: DropZone!
    var log: NSTextView!
    var busy = false

    func applicationWillFinishLaunching(_ n: Notification) {
        buildMenu()
        buildWindow()
    }
    func applicationDidFinishLaunching(_ n: Notification) {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    /// Files dropped on the Dock icon, opened with the app, or passed to `open -a`.
    func application(_ application: NSApplication, open urls: [URL]) {
        if window == nil { buildWindow() }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        run(urls)
    }

    func buildMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem(); main.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About \(appName)", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Choose Files…", action: #selector(chooseFiles(_:)), keyEquivalent: "o")
        appMenu.addItem(withTitle: "Clear Report", action: #selector(clearLog(_:)), keyEquivalent: "k")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide \(appName)", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "Quit \(appName)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        let editItem = NSMenuItem(); main.addItem(editItem)
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        let windowItem = NSMenuItem(); main.addItem(windowItem)
        let win = NSMenu(title: "Window")
        win.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        win.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowItem.submenu = win
        NSApp.mainMenu = main
    }

    func buildWindow() {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 480),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable],
                          backing: .buffered, defer: false)
        window.title = appName
        window.minSize = NSSize(width: 420, height: 360)
        window.center()
        window.setFrameAutosaveName("FixLineWrapsMain")
        window.delegate = self

        dropZone = DropZone(frame: .zero)
        dropZone.translatesAutoresizingMaskIntoConstraints = false
        dropZone.onDrop = { [weak self] urls in self?.run(urls) }

        let choose = NSButton(title: "Choose Files…", target: self, action: #selector(chooseFiles(_:)))
        choose.keyEquivalent = "\r"
        let hint = NSTextField(labelWithString: "or drop files on the Dock icon")
        hint.textColor = .secondaryLabelColor
        hint.font = .systemFont(ofSize: 11)
        let row = NSStackView(views: [choose, hint])
        row.orientation = .horizontal
        row.spacing = 10
        row.translatesAutoresizingMaskIntoConstraints = false

        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        log = NSTextView()
        log.isEditable = false
        log.isRichText = false
        log.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        log.textContainerInset = NSSize(width: 8, height: 8)
        log.autoresizingMask = [.width]
        log.isVerticallyResizable = true
        log.isHorizontallyResizable = false
        log.textContainer?.widthTracksTextView = true
        log.minSize = NSSize(width: 0, height: 0)
        log.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        scroll.documentView = log

        let content = NSView()
        content.addSubview(dropZone)
        content.addSubview(row)
        content.addSubview(scroll)
        window.contentView = content
        NSLayoutConstraint.activate([
            dropZone.topAnchor.constraint(equalTo: content.topAnchor, constant: 16),
            dropZone.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            dropZone.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            dropZone.heightAnchor.constraint(equalToConstant: 150),
            row.topAnchor.constraint(equalTo: dropZone.bottomAnchor, constant: 12),
            row.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            scroll.topAnchor.constraint(equalTo: row.bottomAnchor, constant: 12),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            scroll.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -16),
        ])
        append("Waiting for files.\n")
    }

    @objc func chooseFiles(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.message = "Pick the markdown files (or folders of them) to fix:"
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        var types: [UTType] = [.plainText]
        if let md = UTType("net.daringfireball.markdown") { types.append(md) }
        panel.allowedContentTypes = types
        panel.beginSheetModal(for: window) { [weak self] resp in
            guard resp == .OK else { return }
            self?.run(panel.urls)
        }
    }

    @objc func clearLog(_ sender: Any?) {
        log.string = ""
    }

    func append(_ s: String) {
        log.textStorage?.append(NSAttributedString(string: s, attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
            .foregroundColor: NSColor.labelColor,
        ]))
        log.scrollToEndOfDocument(nil)
    }

    func run(_ urls: [URL]) {
        guard !busy else { append("  (busy with the previous drop; try again in a moment)\n"); return }
        busy = true
        dropZone.title.stringValue = "Working…"
        let stamp = DateFormatter()
        stamp.dateFormat = "HH:mm:ss"
        append("\n— \(stamp.string(from: Date())) —\n")
        DispatchQueue.global(qos: .userInitiated).async {
            let outcome = fix(urls)
            DispatchQueue.main.async {
                self.append(outcome.report)
                if outcome.permissionTrouble {
                    self.append("""

                      macOS refused a file in a protected folder (Desktop, Documents or Downloads).
                      Either press "Choose Files…" and pick it there, or allow \(appName) under
                      System Settings > Privacy & Security > Files and Folders.

                    """)
                }
                let summary = outcome.report.split(separator: "\n").last(where: { $0.contains("already fine") })
                self.dropZone.title.stringValue = summary.map { "Done: " + $0.trimmingCharacters(in: .whitespaces) } ?? "Drop .md files here"
                self.busy = false
            }
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
