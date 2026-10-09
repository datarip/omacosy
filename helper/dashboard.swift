// omacosy-dashboard — the settings modal (Super+,).
//
// A Super+K-style card with three tabs: Options, Workspaces, Themes. It
// reads current state from the same files and commands the rest of omacosy
// uses, and applies changes by running those commands — it holds no policy
// of its own, so the GUI can never disagree with the CLI.
//
// Self-contained on purpose: install.sh builds one source file per binary,
// and a fault here must never be able to take the menu bar down, so the
// palette/font/measure helpers the cheatsheet uses are copied in rather
// than shared with bar.swift.
//
// Palette comes from ~/.config/omarchy/current/theme/sketchybar.sh, the
// same file the bar and cheatsheet read, and it is re-read when that
// symlink is swapped — so stock, custom and auto-theme-derived palettes
// all follow automatically.

import Cocoa
import ImageIO
import UniformTypeIdentifiers

let HOME = NSHomeDirectory()

// --- palette ---------------------------------------------------------------

struct Palette {
    var itemBG = NSColor.black
    var accent = NSColor.systemBlue
    var label = NSColor.white
    var muted = NSColor.gray
    var barBG = NSColor.black
}

func color(fromARGB v: UInt64) -> NSColor {
    NSColor(srgbRed: CGFloat((v >> 16) & 0xff) / 255,
            green: CGFloat((v >> 8) & 0xff) / 255,
            blue: CGFloat(v & 0xff) / 255,
            alpha: CGFloat((v >> 24) & 0xff) / 255)
}

func loadPalette() -> Palette {
    var p = Palette()
    let file = HOME + "/.config/omarchy/current/theme/sketchybar.sh"
    guard let text = try? String(contentsOfFile: file, encoding: .utf8) else { return p }
    for line in text.split(separator: "\n") {
        let parts = line.replacingOccurrences(of: "export ", with: "").split(separator: "=")
        guard parts.count == 2, parts[1].hasPrefix("0x"),
              let v = UInt64(parts[1].dropFirst(2), radix: 16) else { continue }
        switch parts[0] {
        case "ITEM_BG": p.itemBG = color(fromARGB: v)
        case "ACCENT": p.accent = color(fromARGB: v)
        case "LABEL_COLOR": p.label = color(fromARGB: v)
        case "MUTED": p.muted = color(fromARGB: v)
        case "BAR_BG_SOLID": p.barBG = color(fromARGB: v)
        default: break
        }
    }
    return p
}

var palette = loadPalette()

func nerdFont(_ face: String, _ size: CGFloat) -> NSFont {
    let desc = NSFontDescriptor(fontAttributes: [
        .family: "JetBrainsMono Nerd Font", .face: face,
    ])
    if let f = NSFont(descriptor: desc, size: size), f.familyName == "JetBrainsMono Nerd Font" {
        return f
    }
    return .monospacedSystemFont(ofSize: size, weight: face == "Bold" ? .bold : .semibold)
}

// --- text ------------------------------------------------------------------

func textLine(_ s: String, _ font: NSFont, _ color: NSColor) -> CTLine {
    CTLineCreateWithAttributedString(NSAttributedString(
        string: s, attributes: [.font: font, .foregroundColor: color]))
}

func advance(_ s: String, _ font: NSFont) -> CGFloat {
    CGFloat(CTLineGetTypographicBounds(textLine(s, font, .black), nil, nil, nil))
}

func drawBaseline(_ s: String, _ font: NSFont, _ color: NSColor, x: CGFloat, baseline: CGFloat) {
    guard !s.isEmpty, let ctx = NSGraphicsContext.current?.cgContext else { return }
    ctx.textPosition = CGPoint(x: x, y: baseline)
    CTLineDraw(textLine(s, font, color), ctx)
}

// top-based helpers: `top`/`midTop` measure down from the view's top edge
func drawTopLeft(_ s: String, _ font: NSFont, _ color: NSColor,
                 x: CGFloat, top: CGFloat, height: CGFloat) {
    drawBaseline(s, font, color, x: x, baseline: height - top - font.capHeight)
}

func drawMidLeft(_ s: String, _ font: NSFont, _ color: NSColor,
                 x: CGFloat, midTop: CGFloat, height: CGFloat) {
    drawBaseline(s, font, color, x: x, baseline: height - midTop - font.capHeight / 2)
}

func drawMidCenter(_ s: String, _ font: NSFont, _ color: NSColor,
                   centerX: CGFloat, midTop: CGFloat, height: CGFloat) {
    drawBaseline(s, font, color, x: centerX - advance(s, font) / 2,
                 baseline: height - midTop - font.capHeight / 2)
}

// --- shell / config --------------------------------------------------------

@discardableResult
func shell(_ command: String) -> (Int32, String) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/bin/bash")
    p.arguments = ["-c", command]
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = pipe
    do { try p.run() } catch { return (127, "") }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return (p.terminationStatus, String(data: data, encoding: .utf8) ?? "")
}

func readConfKey(_ file: String, _ key: String) -> String? {
    guard let text = try? String(contentsOfFile: file, encoding: .utf8) else { return nil }
    for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
        let line = raw.trimmingCharacters(in: .whitespaces)
        guard !line.hasPrefix("#"), let eq = line.firstIndex(of: "=") else { continue }
        let k = line[line.startIndex..<eq].trimmingCharacters(in: .whitespaces)
        if k == key {
            var v = String(line[line.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
            v = v.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            return v
        }
    }
    return nil
}

@discardableResult
func setConfKey(_ file: String, _ key: String, _ value: String) -> Bool {
    var text = (try? String(contentsOfFile: file, encoding: .utf8)) ?? ""
    var lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    if let last = lines.last, last.isEmpty { lines.removeLast() }
    var found = false
    for i in 0..<lines.count {
        let trimmed = lines[i].trimmingCharacters(in: .whitespaces)
        guard !trimmed.hasPrefix("#"), let eq = trimmed.firstIndex(of: "=") else { continue }
        let k = trimmed[trimmed.startIndex..<eq].trimmingCharacters(in: .whitespaces)
        if k == key { lines[i] = "\(key)=\"\(value)\""; found = true; break }
    }
    if !found { lines.append("\(key)=\"\(value)\"") }
    text = lines.joined(separator: "\n") + "\n"
    do { try text.write(toFile: file, atomically: true, encoding: .utf8); return true }
    catch { return false }
}

// --- secrets ---------------------------------------------------------------

let SECRETS = HOME + "/.config/omacosy/secrets.conf"

func readSecret(_ key: String) -> String {
    guard let text = try? String(contentsOfFile: SECRETS, encoding: .utf8) else { return "" }
    for raw in text.split(separator: "\n") {
        let t = raw.trimmingCharacters(in: .whitespaces)
        guard !t.hasPrefix("#"), let eq = t.firstIndex(of: "=") else { continue }
        if t[..<eq].trimmingCharacters(in: .whitespaces) == key {
            return String(t[t.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
        }
    }
    return ""
}

// secrets.conf holds credentials, so it is the one config file that must
// not be world-readable and must not be half-written. The temp file is
// created with mode 600 BEFORE any value is written, flushed to disk, then
// renamed over the old file. Nothing here shells out, so the value cannot
// reach a log or a transcript. An empty value removes the key, which is
// what clearing the field in the API Keys tab does.
@discardableResult
func writeSecret(_ key: String, _ value: String) -> Bool {
    let dir = HOME + "/.config/omacosy"
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    var lines: [String] = []
    if let text = try? String(contentsOfFile: SECRETS, encoding: .utf8) {
        lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if let last = lines.last, last.isEmpty { lines.removeLast() }
    }
    let clean = value.replacingOccurrences(of: "\n", with: "")
    var out: [String] = []
    var found = false
    for line in lines {
        let t = line.trimmingCharacters(in: .whitespaces)
        let eq = t.firstIndex(of: "=")
        let k = eq.map { t[..<$0].trimmingCharacters(in: .whitespaces) } ?? ""
        if !t.hasPrefix("#"), k == key {
            found = true
            if !clean.isEmpty { out.append("\(key)=\(clean)") }
        } else {
            out.append(line)
        }
    }
    if !found && !clean.isEmpty { out.append("\(key)=\(clean)") }
    if out.allSatisfy({ $0.trimmingCharacters(in: .whitespaces).isEmpty }) {
        _ = unlink(SECRETS)
        return true
    }
    let text = out.joined(separator: "\n") + "\n"

    let tmp = SECRETS + ".tmp"
    _ = unlink(tmp)
    let fd = open(tmp, O_WRONLY | O_CREAT | O_EXCL, 0o600)
    guard fd >= 0 else { return false }
    let data = Array(text.utf8)
    let written = data.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
    _ = fsync(fd)
    _ = close(fd)
    guard written == data.count else { _ = unlink(tmp); return false }
    guard rename(tmp, SECRETS) == 0 else { _ = unlink(tmp); return false }
    _ = chmod(SECRETS, 0o600)
    return true
}

// --- logo ------------------------------------------------------------------

func repoDir() -> String? {
    if let env = ProcessInfo.processInfo.environment["OMACOSY_REPO"], !env.isEmpty { return env }
    let link = HOME + "/.local/bin/theme-set"
    guard FileManager.default.fileExists(atPath: link) else { return nil }
    let resolved = URL(fileURLWithPath: link).resolvingSymlinksInPath().path
    var url = URL(fileURLWithPath: resolved)
    url.deleteLastPathComponent()
    url.deleteLastPathComponent()
    let path = url.path
    return FileManager.default.fileExists(atPath: path + "/install.sh") ? path : nil
}

func logoFiles() -> [String] {
    var bases: [String] = []
    if let r = repoDir() { bases.append(r + "/helper/assets") }
    bases.append(HOME + "/.local/state/omacosy/assets")
    bases.append(HOME + "/.local/share/omacosy/assets")
    var out: [String] = []
    for b in bases {
        // SVG first: it is the source of the wordmark and the only file that
        // carries the shaded strips. The PNG is a legacy pre-render that a
        // stale copy in the state dir would otherwise shadow.
        for name in ["omacosy-logo.svg", "omacosy-logo.png"] {
            let p = b + "/" + name
            if FileManager.default.fileExists(atPath: p) { out.append(p) }
        }
    }
    return out
}

func mixColor(_ a: NSColor, _ b: NSColor, _ t: CGFloat) -> NSColor {
    let x = a.usingColorSpace(.sRGB) ?? a, y = b.usingColorSpace(.sRGB) ?? b
    return NSColor(srgbRed: x.redComponent + (y.redComponent - x.redComponent) * t,
                   green: x.greenComponent + (y.greenComponent - x.greenComponent) * t,
                   blue: x.blueComponent + (y.blueComponent - x.blueComponent) * t,
                   alpha: 1)
}

// Omarchy's luminance ladder: one accent colour becomes five shades, "lit" being
// the accent itself, crest and hover mixed toward white, mid and dim toward
// black. The ratios are pulled in from Omarchy's own, which make the top band
// glow and the bottom sink; and they are walked back smoothly as the card
// brightens, so a mid-tone card gets neither a grey top nor a black bottom. A
// light card lands on the gentlest ladder, where neither end reaches the card.
func accentShades(_ accent: NSColor, cardL: CGFloat) -> [NSColor] {
    let strong: [CGFloat] = [0.40, 0.19, 0, -0.21, -0.42]
    let gentle: [CGFloat] = [0.12, 0.06, 0, -0.18, -0.36]
    let t = min(1, max(0, (cardL - 0.10) / 0.35))
    let step = zip(strong, gentle).map { $0 + ($1 - $0) * t }
    return step.map { $0 >= 0 ? mixColor(accent, .white, $0) : mixColor(accent, .black, -$0) }
}

// crest, hover, lit, mid, dim sit at these brightnesses of the wordmark mask
func shade(level: CGFloat, in shades: [NSColor]) -> NSColor {
    let stop: [CGFloat] = [1, 0.75, 0.5, 0.25, 0]
    if level >= 1 { return shades[0] }
    if level <= 0 { return shades[4] }
    for i in 0..<4 where level <= stop[i] && level >= stop[i + 1] {
        return mixColor(shades[i], shades[i + 1], (stop[i] - level) / (stop[i] - stop[i + 1]))
    }
    return shades[2]
}

// the wordmark SVG is a neutral white-to-black ramp. Every pixel is mapped onto
// the accent's shade ladder by its brightness, so each strip becomes a shade of
// the theme colour and the top bands can be lighter than the accent. A flat fill
// cannot do that, and neither can a multiply, which only ever darkens.
func shadedImage(_ image: NSImage, _ color: NSColor, cardL: CGFloat) -> NSImage? {
    let aspect = image.size.width / max(image.size.height, 1)
    let h = 220
    let w = max(1, Int((CGFloat(h) * aspect).rounded()))
    let count = w * h * 4
    let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: count)
    buf.initialize(repeating: 0, count: count)
    defer { buf.deallocate() }
    let cs = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(data: buf, width: w, height: h, bitsPerComponent: 8,
                              bytesPerRow: w * 4, space: cs,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
    image.draw(in: NSRect(x: 0, y: 0, width: w, height: h))
    NSGraphicsContext.restoreGraphicsState()
    let shades = accentShades(color, cardL: cardL)
    for i in stride(from: 0, to: count, by: 4) {
        let a = CGFloat(buf[i + 3]) / 255
        if a == 0 { continue }
        let level = (0.299 * CGFloat(buf[i]) + 0.587 * CGFloat(buf[i + 1])
                     + 0.114 * CGFloat(buf[i + 2])) / 255 / a
        let c = shade(level: min(1, level), in: shades)
        buf[i] = UInt8((c.redComponent * a * 255).rounded())
        buf[i + 1] = UInt8((c.greenComponent * a * 255).rounded())
        buf[i + 2] = UInt8((c.blueComponent * a * 255).rounded())
    }
    guard let provider = CGDataProvider(data: Data(bytes: buf, count: count) as CFData),
          let cg = CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32,
                           bytesPerRow: w * 4, space: cs,
                           bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                           provider: provider, decode: nil, shouldInterpolate: true,
                           intent: .defaultIntent) else { return nil }
    let out = NSImage(size: NSSize(width: w, height: h))
    out.addRepresentation(NSBitmapImageRep(cgImage: cg))
    return out
}

func logoImage() -> NSImage? {
    let card = palette.barBG.usingColorSpace(.sRGB) ?? .black
    let cardL = 0.299 * card.redComponent + 0.587 * card.greenComponent + 0.114 * card.blueComponent
    for path in logoFiles() {
        guard let img = NSImage(contentsOfFile: path), img.size.width > 0 else { continue }
        // no alpha check: an SVG loads as a vector rep that reports no alpha
        // even though it renders transparent, which rejected the shipped asset.
        return shadedImage(img, palette.accent, cardL: cardL)
    }
    return nil
}

// --- state -----------------------------------------------------------------

enum WindowManager: Int { case aerospace = 0, omniwm = 1 }
enum CornerMode: Int { case rounded = 0, square = 1 }
enum BarMode: Int { case visible = 0, hidden = 1, auto = 2 }
enum TerminalThemeMode: Int { case own = 0, follow = 1 }

struct DashboardState {
    var wm: WindowManager = .aerospace
    var corners: CornerMode = .rounded
    var bar: BarMode = .visible
    var fullscreen: Bool = false
    var termTheme: TerminalThemeMode = .own
}

let SETTINGS = HOME + "/.config/omacosy/settings.conf"
let BARCONF = HOME + "/.config/omacosy/bar.conf"
let TERMCONF = HOME + "/.config/omacosy/term-auto-theme.conf"
// the setting's earlier home; read only until omacosy-term-auto-theme has
// migrated it, so the row is truthful on the first open after an upgrade
let OLD_AUTOCONF = HOME + "/.config/omacosy/auto-theme.conf"

func readState() -> DashboardState {
    var s = DashboardState()
    if shell("\(HOME)/.local/bin/omacosy-omni active >/dev/null 2>&1").0 == 0 { s.wm = .omniwm }

    let (cc, cout) = shell("/usr/bin/defaults read -g NSConvolutionOverride1 2>/dev/null")
    if cc == 0, let d = Double(cout.trimmingCharacters(in: .whitespacesAndNewlines)), d < 5 {
        s.corners = .square
    }

    var bv = readConfKey(SETTINGS, "AUTOHIDE") ?? ""
    if bv.isEmpty { bv = readConfKey(BARCONF, "autohide") ?? "off" }
    switch bv { case "on": s.bar = .hidden; case "auto": s.bar = .auto; default: s.bar = .visible }

    s.fullscreen = FileManager.default.fileExists(atPath: HOME + "/.config/omacosy/solo-fullscreen")

    // The terminal-following setting. Before the rename it lived in
    // auto-theme.conf as `apps`, with the `auto-theme` master switch as the
    // fallback when apps was never written; an unmigrated install reads
    // exactly the same truth either way.
    if let terminal = readConfKey(TERMCONF, "terminal") {
        s.termTheme = terminal == "on" ? .follow : .own
    } else if let apps = readConfKey(OLD_AUTOCONF, "apps") {
        s.termTheme = apps == "off" ? .own : .follow
    } else {
        s.termTheme = (readConfKey(OLD_AUTOCONF, "auto-theme") ?? "off") == "on" ? .follow : .own
    }
    return s
}

// The radius macOS draws window corners with, when the user has set one.
// omacosy-window-corners writes NSConvolutionOverride1, and this modal's
// borderless card gets no rounding from macOS, so it reads the value back
// to stay consistent with every other window. Absent means macOS's own
// radius, and the card keeps its rounded default.
func windowCornerRadius(_ fallback: CGFloat) -> CGFloat {
    guard let n = UserDefaults.standard.object(forKey: "NSConvolutionOverride1") as? NSNumber
    else { return fallback }
    return CGFloat(n.doubleValue)
}

// --- controls --------------------------------------------------------------

final class SegmentedView: NSView {
    var items: [String] = []
    var index: Int = 0
    var onChange: ((Int) -> Void)?
    private var segFrames: [NSRect] = []

    func sizeThatFits() -> NSSize {
        let f = nerdFont("Regular", 12)
        var w: CGFloat = 4
        for it in items { w += max(advance(it, f) + 22, 46) }
        return NSSize(width: w, height: 28)
    }

    private func layoutSegments() {
        segFrames.removeAll()
        let f = nerdFont("Regular", 12)
        var x: CGFloat = 2
        for it in items {
            let w = max(advance(it, f) + 22, 46)
            segFrames.append(NSRect(x: x, y: 2, width: w, height: bounds.height - 4))
            x += w
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        layoutSegments()
        let track = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6)
        palette.itemBG.withAlphaComponent(0.55).setFill()
        track.fill()
        let f = nerdFont("Regular", 12)
        let bf = nerdFont("Bold", 12)
        for (i, r) in segFrames.enumerated() {
            let path = NSBezierPath(roundedRect: r, xRadius: 5, yRadius: 5)
            if i == index {
                palette.accent.withAlphaComponent(0.9).setFill()
                path.fill()
            } else {
                // a faint accent outline so an unselected choice is legible
                // on a dark card instead of blending into it
                palette.accent.withAlphaComponent(0.30).setStroke()
                path.lineWidth = 1
                path.stroke()
            }
            drawMidCenter(items[i], i == index ? bf : f,
                          i == index ? palette.barBG : palette.label,
                          centerX: r.midX, midTop: bounds.height / 2, height: bounds.height)
        }
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        for (i, r) in segFrames.enumerated() where r.contains(p) {
            if i != index { index = i; needsDisplay = true; onChange?(i) }
            return
        }
    }

    override var acceptsFirstResponder: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class ButtonView: NSView {
    var title = "Save" { didSet { needsDisplay = true } }
    var fontSize: CGFloat = 12
    // icon buttons centre on the glyph's own box; text buttons centre on cap
    // height, which reads better for words
    var centeredByBounds = false
    // a quieter fill for the second action in a dialog or footer row
    var secondary = false { didSet { needsDisplay = true } }
    var busy = false { didSet { needsDisplay = true } }
    var onClick: (() -> Void)?

    override func draw(_ dirtyRect: NSRect) {
        let r = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6)
        if secondary && !busy {
            palette.itemBG.withAlphaComponent(0.35).setFill()
            r.fill()
            palette.muted.withAlphaComponent(0.35).setStroke()
            r.lineWidth = 1
            r.stroke()
        } else {
            (busy ? palette.muted : palette.accent).setFill()
            r.fill()
        }
        let text = busy ? "Saving…" : title
        let font = nerdFont("Bold", fontSize)
        let ink = (secondary && !busy) ? palette.label : palette.barBG
        if centeredByBounds {
            // centre on the glyph's ink, not its line box: nerd-font icons
            // carry odd metrics and drift high/left in a line-box centre
            guard let ctx = NSGraphicsContext.current?.cgContext else { return }
            let line = textLine(text, font, ink)
            let inkBounds = CTLineGetImageBounds(line, ctx)
            ctx.textPosition = CGPoint(x: bounds.midX - inkBounds.midX,
                                       y: bounds.midY - inkBounds.midY)
            CTLineDraw(line, ctx)
        } else {
            drawMidCenter(text, font, ink,
                          centerX: bounds.midX, midTop: bounds.height / 2, height: bounds.height)
        }
    }

    override func mouseDown(with event: NSEvent) { if !busy { onClick?() } }
    override var acceptsFirstResponder: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

// --- custom scrollbar ------------------------------------------------------
// System scrollers are overlay-styled on macOS and float over the content,
// which put one on top of the "Add App" button. This draws a squared,
// accent-coloured thumb in a reserved strip instead, and takes its place.

final class CustomScroller: NSView {
    weak var scrollView: NSScrollView?
    private var dragging = false
    private var dragStartY: CGFloat = 0
    private var dragStartOrigin: CGFloat = 0
    private let minThumb: CGFloat = 30

    override var isFlipped: Bool { true }

    private var docH: CGFloat { scrollView?.documentView?.frame.height ?? 0 }
    private var clipH: CGFloat { scrollView?.contentSize.height ?? 0 }
    private var maxScroll: CGFloat { max(0, docH - clipH) }
    private var thumbH: CGFloat {
        guard docH > clipH, docH > 0 else { return 0 }
        return max(minThumb, bounds.height * clipH / docH)
    }
    private func originY() -> CGFloat { scrollView?.contentView.bounds.origin.y ?? 0 }
    private var frac: CGFloat { maxScroll > 0 ? originY() / maxScroll : 1 }
    private var thumbTop: CGFloat { (1 - frac) * (bounds.height - thumbH) }

    func refresh() { needsDisplay = true }

    override func draw(_ dirtyRect: NSRect) {
        let h = thumbH
        guard h > 0, h < bounds.height - 1 else { return }
        palette.itemBG.withAlphaComponent(0.35).setFill()
        NSBezierPath(rect: bounds).fill()
        let r = NSRect(x: 0, y: thumbTop, width: bounds.width, height: h)
        palette.accent.withAlphaComponent(0.85).setFill()
        NSBezierPath(rect: r).fill()
    }

    override func mouseDown(with event: NSEvent) {
        guard thumbH > 0 else { return }
        let p = convert(event.locationInWindow, from: nil)
        if NSRect(x: 0, y: thumbTop, width: bounds.width, height: thumbH).contains(p) {
            dragging = true
            dragStartY = p.y
            dragStartOrigin = originY()
        } else {
            let t = (p.y - thumbH / 2) / max(1, bounds.height - thumbH)
            setOrigin(max(0, min(1, 1 - t)) * maxScroll)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard dragging, maxScroll > 0 else { return }
        let p = convert(event.locationInWindow, from: nil)
        let delta = (p.y - dragStartY) / max(1, bounds.height - thumbH)
        let f = max(0, min(1, dragStartOrigin / maxScroll - delta))
        setOrigin(f * maxScroll)
    }

    override func mouseUp(with event: NSEvent) { dragging = false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private func setOrigin(_ o: CGFloat) {
        guard let sv = scrollView else { return }
        sv.contentView.scroll(to: NSPoint(x: 0, y: o))
        sv.reflectScrolledClipView(sv.contentView)
        needsDisplay = true
    }
}

// --- arrow-key scrolling ---------------------------------------------------
// A positive dy scrolls towards later content ("down"). Every document view
// here is non-flipped, so later content sits at a *smaller* y origin: subtract
// dy. Used by the arrow keys in the app picker and the dashboard's own tabs.

func scrollBy(_ sv: NSScrollView, _ dy: CGFloat) {
    guard let doc = sv.documentView else { return }
    let clip = sv.contentView
    let maxY = max(0, doc.frame.height - clip.bounds.height)
    let y = max(0, min(maxY, clip.bounds.origin.y - dy))
    clip.scroll(to: NSPoint(x: clip.bounds.origin.x, y: y))
    sv.reflectScrolledClipView(clip)
}

// A tab with one vertical list the arrow keys can move.
protocol ScrollStepTab: AnyObject {
    func scrollStep(_ dy: CGFloat)
}

// --- options tab -----------------------------------------------------------

struct OptionRow {
    let category: String
    let title: String
    let desc: String
    let seg: SegmentedView
}

final class OptionsDocView: NSView {
    var rows: [OptionRow] = []
    private let rowH: CGFloat = 58
    private let catH: CGFloat = 30
    private let sectionGap: CGFloat = 6
    private let topPad: CGFloat = 6

    func contentHeight() -> CGFloat {
        topPad + CGFloat(rows.count) * (catH + rowH + sectionGap) + 10
    }

    override func layout() {
        super.layout()
        var top = topPad
        for row in rows {
            top += catH
            let sz = row.seg.sizeThatFits()
            let segTop = top + (rowH - sz.height) / 2
            row.seg.frame = NSRect(x: bounds.width - sz.width,
                                   y: bounds.height - segTop - sz.height,
                                   width: sz.width, height: sz.height)
            top += rowH + sectionGap
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        var top = topPad
        for row in rows {
            drawTopLeft(row.category, nerdFont("Bold", 13), palette.accent,
                        x: 0, top: top, height: bounds.height)
            top += catH
            let rowMid = top + 20
            drawMidLeft(row.title, nerdFont("Bold", 13), palette.label,
                        x: 0, midTop: rowMid, height: bounds.height)
            drawMidLeft(row.desc, nerdFont("Regular", 11), palette.muted,
                        x: 0, midTop: rowMid + 18, height: bounds.height)
            top += rowH
            palette.muted.withAlphaComponent(0.25).setFill()
            NSRect(x: 0, y: bounds.height - top - 0.5, width: bounds.width, height: 1).fill()
            top += sectionGap
        }
    }
}

final class OptionsTabView: NSView, ScrollStepTab {
    private(set) var rows: [OptionRow] = []
    func scrollStep(_ dy: CGFloat) { scrollBy(scroll, dy) }
    func refreshColors() {
        needsDisplay = true
        doc.needsDisplay = true
        for r in rows { r.seg.needsDisplay = true }
        scroller.refresh()
    }
    private var original = DashboardState()
    private var status = ""
    private let scroll = NSScrollView()
    private let doc = OptionsDocView()
    private let scroller = CustomScroller()
    private let scrollerW: CGFloat = 8
    let saveButton = ButtonView()
    // the root draws the card, which follows the window-corner setting; a
    // saved change must redraw it at once, not wait for a tab switch
    var onApplied: (() -> Void)?
    private let bottomBarH: CGFloat = 54
    private var lastDocH: CGFloat = -1

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        scroll.hasVerticalScroller = false
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        addSubview(scroll)
        scroll.documentView = doc
        addSubview(scroller)
        scroller.scrollView = scroll
        scroll.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(scrolled),
            name: NSView.boundsDidChangeNotification, object: scroll.contentView)
        build()
        saveButton.title = "Save"
        saveButton.onClick = { [weak self] in self?.save() }
        addSubview(saveButton)
    }
    @objc private func scrolled() { scroller.refresh() }
    required init?(coder: NSCoder) { fatalError("not used") }

    private func makeSeg(_ items: [String], _ idx: Int) -> SegmentedView {
        let s = SegmentedView()
        s.items = items
        s.index = idx
        return s
    }

    private func build() {
        original = readState()

        let wmSeg = makeSeg(["AeroSpace", "OmniWM"], original.wm.rawValue)
        let cornerSeg = makeSeg(["Rounded", "Square"], original.corners.rawValue)
        let barSeg = makeSeg(["Visible", "Hidden", "Auto"], original.bar.rawValue)
        let fsSeg = makeSeg(["Off", "On"], original.fullscreen ? 1 : 0)
        let atSeg = makeSeg(["Own Colours", "Follow Theme"], original.termTheme.rawValue)

        rows = [
            OptionRow(category: "Window Manager", title: "Window Manager",
                      desc: "Which tiling manager Omacosy switches to. Switching reloads Omacosy for a moment.",
                      seg: wmSeg),
            OptionRow(category: "Windows", title: "Window Corners",
                      desc: "Radius macOS draws window corners with; the ring follows.", seg: cornerSeg),
            OptionRow(category: "Bar", title: "Menu Bar Mode",
                      desc: "Keep the bar visible, let it hide at rest, or follow the display.", seg: barSeg),
            OptionRow(category: "Fullscreen", title: "Full Screen Mode",
                      desc: "A workspace holding one window fills the display.", seg: fsSeg),
            OptionRow(category: "Themes", title: "Terminal Auto-Theme",
                      desc: "Let the terminal and its apps follow the wallpaper theme, or keep their own colours.", seg: atSeg),
        ]
        doc.rows = rows
        for r in rows { doc.addSubview(r.seg) }
    }

    override func layout() {
        super.layout()
        let saveW: CGFloat = 96, saveH: CGFloat = 24
        saveButton.frame = NSRect(x: (bounds.width - saveW) / 2,
                                  y: (bottomBarH - saveH) / 2, width: saveW, height: saveH)
        let scrollH = max(0, bounds.height - bottomBarH)
        scroll.frame = NSRect(x: 0, y: bottomBarH, width: max(0, bounds.width - scrollerW - 14), height: scrollH)
        scroller.frame = NSRect(x: bounds.width - scrollerW, y: bottomBarH, width: scrollerW, height: scrollH)
        scroller.refresh()
        let w = scroll.contentSize.width
        if w > 0, abs(doc.frame.width - w) > 0.5 {
            doc.frame.size.width = w
            let h = doc.contentHeight()
            doc.frame.size.height = h
            doc.needsLayout = true
            if h != lastDocH {
                lastDocH = h
                scroll.contentView.scroll(to: NSPoint(x: 0, y: max(0, h - scroll.contentSize.height)))
                scroll.reflectScrolledClipView(scroll.contentView)
            }
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        palette.muted.withAlphaComponent(0.25).setFill()
        NSRect(x: 0, y: bottomBarH - 0.5, width: bounds.width, height: 1).fill()
        if !status.isEmpty {
            drawMidLeft(status, nerdFont("Regular", 11), palette.muted,
                        x: 0, midTop: bounds.height - bottomBarH / 2, height: bounds.height)
        }
    }

    private func save() {
        let wm = WindowManager(rawValue: rows[0].seg.index) ?? original.wm
        let corners = CornerMode(rawValue: rows[1].seg.index) ?? original.corners
        let bar = BarMode(rawValue: rows[2].seg.index) ?? original.bar
        let fullscreen = rows[3].seg.index == 1
        let termTheme = TerminalThemeMode(rawValue: rows[4].seg.index) ?? original.termTheme

        var steps: [String] = []
        if wm != original.wm {
            steps.append("\(HOME)/.local/bin/omacosy-wm-switch \(wm == .omniwm ? "omniwm" : "aerospace")")
        }
        if corners != original.corners {
            setConfKey(SETTINGS, "WINDOW_CORNER", corners == .square ? "0.1" : "")
            steps.append("\(HOME)/.local/bin/omacosy-window-corners \(corners == .square ? "square" : "round")")
        }
        if bar != original.bar {
            let v = ["off", "on", "auto"][bar.rawValue]
            steps.append("\(HOME)/.local/bin/omacosy-bar-autohide \(v)")
        }
        if fullscreen != original.fullscreen {
            steps.append("\(HOME)/.local/bin/omacosy-solo-fullscreen \(fullscreen ? "on" : "off")")
        }
        if termTheme != original.termTheme {
            steps.append("\(HOME)/.local/bin/omacosy-term-auto-theme \(termTheme == .follow ? "on" : "off")")
        }

        guard !steps.isEmpty else {
            status = "No changes"
            needsDisplay = true
            return
        }

        saveButton.busy = true
        status = "Applying…"
        needsDisplay = true

        DispatchQueue.global().async { [weak self] in
            var last = ""
            for step in steps {
                let (code, out) = shell(step)
                last = out.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "\n").last.map(String.init) ?? ""
                if code != 0 {
                    DispatchQueue.main.async {
                        self?.status = "Error: \(step.split(separator: " ").last ?? "") — \(last)"
                        self?.saveButton.busy = false
                        self?.needsDisplay = true
                    }
                    return
                }
            }
            DispatchQueue.main.async {
                self?.original = readState()
                self?.status = "Saved"
                self?.saveButton.busy = false
                self?.needsDisplay = true
                self?.onApplied?()
            }
        }
    }
}

// --- workspaces tab --------------------------------------------------------

struct AppInfo {
    let bundleID: String
    let name: String
    let path: String
}

struct ScreenInfo {
    let name: String
    let workspaces: [String]
}

var appIconCache: [String: NSImage] = [:]

func iconForBundle(_ id: String) -> NSImage? {
    if let c = appIconCache[id] { return c }
    guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return nil }
    let img = NSWorkspace.shared.icon(forFile: url.path)
    appIconCache[id] = img
    return img
}

func installedApps() -> [AppInfo] {
    let dirs = ["/Applications", "/System/Applications", HOME + "/Applications"]
    var seen = Set<String>()
    var out: [AppInfo] = []
    for dir in dirs {
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: dir) else { continue }
        for e in entries where e.hasSuffix(".app") {
            let path = dir + "/" + e
            let plist = path + "/Contents/Info.plist"
            guard let d = NSDictionary(contentsOfFile: plist),
                  let bid = d["CFBundleIdentifier"] as? String, !bid.isEmpty,
                  !seen.contains(bid) else { continue }
            seen.insert(bid)
            let name = (d["CFBundleDisplayName"] as? String)
                ?? (d["CFBundleName"] as? String)
                ?? String(e.dropLast(4))
            out.append(AppInfo(bundleID: bid, name: name, path: path))
        }
    }
    return out.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
}

func numericAsc(_ a: String, _ b: String) -> Bool {
    a.compare(b, options: .numeric) == .orderedAscending
}

func screensInfo() -> [ScreenInfo] {
    if shell("\(HOME)/.local/bin/omacosy-omni active >/dev/null 2>&1").0 == 0 {
        let (c1, out1) = shell("\(HOME)/.local/bin/omacosy-omni query displays 2>/dev/null")
        let (c2, out2) = shell("\(HOME)/.local/bin/omacosy-omni query workspaces 2>/dev/null")
        if c1 == 0, c2 == 0,
           let d1 = out1.data(using: .utf8), let d2 = out2.data(using: .utf8),
           let r1 = (try? JSONSerialization.jsonObject(with: d1)) as? [String: Any],
           let r2 = (try? JSONSerialization.jsonObject(with: d2)) as? [String: Any],
           let p1 = (r1["result"] as? [String: Any])?["payload"] as? [String: Any],
           let p2 = (r2["result"] as? [String: Any])?["payload"] as? [String: Any],
           let displays = p1["displays"] as? [[String: Any]],
           let workspaces = p2["workspaces"] as? [[String: Any]] {
            var byDisp: [String: [String]] = [:]
            for w in workspaces {
                guard let did = (w["display"] as? [String: Any])?["id"] as? String,
                      let dn = w["displayName"] as? String else { continue }
                byDisp[did, default: []].append(dn)
            }
            let ordered = displays.sorted {
                (($0["isMain"] as? Bool) ?? false) && !(($1["isMain"] as? Bool) ?? false)
            }
            return ordered.compactMap { d in
                guard let id = d["id"] as? String, let name = d["name"] as? String else { return nil }
                return ScreenInfo(name: name, workspaces: (byDisp[id] ?? []).sorted(by: numericAsc))
            }
        }
    }
    let (_, out) = shell("/opt/homebrew/bin/aerospace list-monitors --format '%{monitor-name}' 2>/dev/null")
    let names = out.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    var res: [ScreenInfo] = []
    for (i, n) in names.enumerated() {
        if i == 0 { res.append(ScreenInfo(name: n, workspaces: (1...9).map(String.init))) }
        else { res.append(ScreenInfo(name: n, workspaces: (11...19).map(String.init))) }
    }
    return res
}

// APP_WORKSPACE_RULES is a multi-line shell string; read the block between
// the quotes rather than a single line
func readWorkspaceRules() -> [(String, String)] {
    guard let text = try? String(contentsOfFile: SETTINGS, encoding: .utf8) else { return [] }
    var out: [(String, String)] = []
    var inBlock = false
    for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
        let line = String(raw)
        if !inBlock {
            guard line.hasPrefix("APP_WORKSPACE_RULES=") else { continue }
            let after = line.dropFirst("APP_WORKSPACE_RULES=".count)
            if after.hasPrefix("\"") {
                let rest = after.dropFirst()
                if let close = rest.firstIndex(of: "\"") {
                    let one = rest[rest.startIndex..<close]
                    for t in one.split(separator: "\n") {
                        let parts = t.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
                        if parts.count >= 2 { out.append((parts[0], parts[1])) }
                    }
                } else {
                    inBlock = true
                }
            }
            continue
        }
        if line.contains("\"") { inBlock = false; continue }
        let t = line.trimmingCharacters(in: .whitespaces)
        let parts = t.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
        if parts.count >= 2 { out.append((parts[0], parts[1])) }
    }
    return out
}

@discardableResult
func writeWorkspaceRules(_ pairs: [(String, String)]) -> Bool {
    guard let text = try? String(contentsOfFile: SETTINGS, encoding: .utf8) else { return false }
    let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    var out: [String] = []
    var i = 0
    var replaced = false
    while i < lines.count {
        let line = lines[i]
        if line.hasPrefix("APP_WORKSPACE_RULES=") && !replaced {
            out.append("APP_WORKSPACE_RULES=\"")
            for (app, ws) in pairs { out.append("\(app)    \(ws)") }
            out.append("\"")
            replaced = true
            let after = line.dropFirst("APP_WORKSPACE_RULES=".count)
            if after.hasPrefix("\"") && after.dropFirst().contains("\"") {
                i += 1
            } else {
                i += 1
                while i < lines.count {
                    if lines[i].contains("\"") { break }
                    i += 1
                }
                i += 1
            }
            continue
        }
        out.append(line)
        i += 1
    }
    if !replaced {
        out.append("APP_WORKSPACE_RULES=\"")
        for (app, ws) in pairs { out.append("\(app)    \(ws)") }
        out.append("\"")
    }
    var result = out.joined(separator: "\n")
    if !result.hasSuffix("\n") { result += "\n" }
    do { try result.write(toFile: SETTINGS, atomically: true, encoding: .utf8); return true }
    catch { return false }
}

final class AppListView: NSView {
    var apps: [AppInfo] = []
    var onPick: ((String) -> Void)?
    var selected: Int = 0
    let rowH: CGFloat = 30

    private func rowRect(_ i: Int) -> NSRect {
        let top = CGFloat(i) * rowH
        return NSRect(x: 0, y: bounds.height - top - rowH, width: bounds.width, height: rowH)
    }

    override func draw(_ dirtyRect: NSRect) {
        for (i, a) in apps.enumerated() {
            let r = rowRect(i)
            if i == selected, apps.indices.contains(selected) {
                // the same accent the custom scrollers use, so a chosen row
                // reads as "the one the arrows are on"
                palette.accent.withAlphaComponent(0.85).setFill()
                r.fill()
            } else if i % 2 == 1 {
                palette.itemBG.withAlphaComponent(0.25).setFill()
                r.fill()
            }
            if let ic = iconForBundle(a.bundleID) {
                ic.draw(in: NSRect(x: 6, y: r.midY - 8, width: 16, height: 16))
            }
            drawMidLeft(a.name, nerdFont("Regular", 12),
                        i == selected ? palette.barBG : palette.label,
                        x: 30, midTop: CGFloat(i) * rowH + rowH / 2, height: bounds.height)
        }
    }

    func moveSelection(_ delta: Int) {
        guard !apps.isEmpty else { return }
        let next = max(0, min(apps.count - 1, selected + delta))
        guard next != selected else { return }
        selected = next
        needsDisplay = true
        ensureVisible()
    }

    // keep the highlighted row inside the viewport as the arrows walk it
    private func ensureVisible() {
        guard let sv = enclosingScrollView, apps.indices.contains(selected) else { return }
        let r = rowRect(selected)
        let visible = sv.documentVisibleRect
        var origin = sv.contentView.bounds.origin
        if r.maxY > visible.maxY { origin.y = r.maxY - visible.height }
        else if r.minY < visible.minY { origin.y = r.minY }
        else { return }
        let maxY = max(0, bounds.height - sv.contentSize.height)
        origin.y = max(0, min(maxY, origin.y))
        sv.contentView.scroll(to: origin)
        sv.reflectScrolledClipView(sv.contentView)
    }

    private var trackingArea: NSTrackingArea?

    // the highlighting follows the mouse as well as the arrows, so the row
    // under the pointer is always the one Enter would apply
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = trackingArea { removeTrackingArea(t) }
        let t = NSTrackingArea(rect: .zero,
                               options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect],
                               owner: self, userInfo: nil)
        addTrackingArea(t)
        trackingArea = t
    }

    override func mouseMoved(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let i = Int((bounds.height - p.y) / rowH)
        guard apps.indices.contains(i), i != selected else { return }
        selected = i
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let i = Int((bounds.height - p.y) / rowH)
        if apps.indices.contains(i) {
            selected = i
            needsDisplay = true
            onPick?(apps[i].bundleID)
        }
    }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class PickerRoot: NSView {
    let search = NSSearchField()
    let scroll = NSScrollView()
    let list = AppListView()
    var titleText: String?
    var showsSearch = true

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(search)
        addSubview(scroll)
        scroll.documentView = list
    }
    required init?(coder: NSCoder) { fatalError("not used") }

    override func draw(_ dirtyRect: NSRect) {
        let r = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 10, yRadius: 10)
        palette.barBG.setFill()
        r.fill()
        palette.accent.setStroke()
        r.lineWidth = 1
        r.stroke()
        if !showsSearch, let t = titleText {
            drawTopLeft(t, nerdFont("Bold", 12), palette.accent, x: 12, top: 9, height: bounds.height)
        }
    }

    override func layout() {
        super.layout()
        relayout()
    }

    func relayout() {
        let pad: CGFloat = 10
        let headerH: CGFloat = showsSearch ? 26 + 8 : 32
        if showsSearch {
            search.isHidden = false
            search.frame = NSRect(x: pad, y: bounds.height - pad - 26,
                                  width: max(0, bounds.width - pad * 2), height: 26)
        } else {
            search.isHidden = true
        }
        scroll.frame = NSRect(x: pad, y: pad, width: max(0, bounds.width - pad * 2),
                              height: max(0, bounds.height - pad * 2 - headerH))
        if scroll.documentView !== list { scroll.documentView = list }
        let w = max(scroll.contentSize.width, 10)
        list.frame = NSRect(x: 0, y: 0, width: w,
                            height: max(scroll.contentSize.height, CGFloat(list.apps.count) * list.rowH))
        showTop()
    }

    // the list is drawn top-down inside a non-flipped document view, so
    // "the top of the list" is the document's maximum scroll offset
    func showTop() {
        let maxY = max(0, list.frame.height - scroll.contentSize.height)
        scroll.contentView.scroll(to: NSPoint(x: 0, y: maxY))
        scroll.reflectScrolledClipView(scroll.contentView)
    }
}

final class PickerWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

final class AppPicker: NSObject, NSWindowDelegate {
    private static var current: AppPicker?
    private let window: NSWindow
    private let root = PickerRoot(frame: .zero)
    private var apps: [AppInfo] = []
    private var completion: ((String) -> Void)?
    private var monitors: [Any] = []
    private var searchable = true
    private let W: CGFloat = 340
    private let H: CGFloat = 430

    init(apps: [AppInfo], title: String?, searchable: Bool, completion: @escaping (String) -> Void) {
        self.apps = apps
        self.completion = completion
        self.searchable = searchable
        window = PickerWindow(contentRect: NSRect(x: 0, y: 0, width: W, height: H),
                              styleMask: .borderless, backing: .buffered, defer: false)
        super.init()
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.level = .popUpMenu
        window.appearance = NSAppearance(named: .darkAqua)
        window.acceptsMouseMovedEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.contentView = root
        root.titleText = title
        root.showsSearch = searchable
        root.scroll.hasVerticalScroller = true
        root.scroll.drawsBackground = false
        root.scroll.borderType = .noBorder
        root.list.apps = apps
        root.list.onPick = { [weak self] bundle in self?.pick(bundle) }
        root.search.placeholderString = "Search apps"
        root.search.sendsWholeSearchString = false
        root.search.sendsSearchStringImmediately = true
        root.search.target = self
        root.search.action = #selector(searchChanged)
    }

    static func present(apps: [AppInfo], near view: NSView, in parent: NSView,
                        title: String? = nil, searchable: Bool = true,
                        completion: @escaping (String) -> Void) {
        current?.close()
        let p = AppPicker(apps: apps, title: title, searchable: searchable, completion: completion)
        guard let host = view.window else { return }
        let btn = host.convertToScreen(view.convert(view.bounds, to: nil))
        var x = btn.minX
        var y = btn.minY - p.H - 6
        if y < 40 { y = btn.maxY + 6 }
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(btn.origin) }) ?? NSScreen.main {
            x = min(max(screen.frame.minX + 8, x), screen.frame.maxX - p.W - 8)
        }
        p.window.setFrame(NSRect(x: x, y: y, width: p.W, height: p.H), display: true)
        current = p
        // a child window: it stays above the modal and is ordered out with it
        host.addChildWindow(p.window, ordered: .above)
        p.show()
    }

    static func dismiss() { current?.close() }

    private func show() {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        root.needsLayout = true
        root.layoutSubtreeIfNeeded()
        root.relayout()
        if searchable {
            root.search.stringValue = ""
            searchChanged()
            window.makeFirstResponder(root.search)
        }
        // Esc, or any click outside the picker's own window. The LOCAL
        // monitor is the important one: a click on the dashboard is our own
        // app, so a global monitor never sees it and the picker used to stay
        // up behind the modal.
        let km = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] e in
            guard let self else { return e }
            if e.keyCode == 53 { self.close(); return nil }
            // the search field holds focus, so consume the arrows before it
            // sees them: they scroll the list, one row a press
            if e.window === self.window {
                if e.keyCode == 126 { self.root.list.moveSelection(-1); return nil } // up
                if e.keyCode == 125 { self.root.list.moveSelection(1); return nil }  // down
                if e.keyCode == 36 || e.keyCode == 76 { self.pickSelected(); return nil } // return
            }
            return e
        }
        let lm = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] e in
            if e.window !== self?.window { self?.close() }
            return e
        }
        let gm = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.close()
        }
        monitors = [km, lm, gm].compactMap { $0 }
    }

    @objc private func searchChanged() {
        let q = root.search.stringValue.lowercased()
        root.list.apps = q.isEmpty ? apps : apps.filter { $0.name.lowercased().contains(q) }
        // a new result set starts with the top app highlighted
        root.list.selected = 0
        root.list.needsDisplay = true
        root.relayout()
    }

    private func pickSelected() {
        guard root.list.apps.indices.contains(root.list.selected) else { return }
        pick(root.list.apps[root.list.selected].bundleID)
    }

    private func pick(_ bundle: String) {
        completion?(bundle)
        close()
    }

    private func close() {
        for m in monitors { NSEvent.removeMonitor(m) }
        monitors.removeAll()
        window.parent?.removeChildWindow(window)
        window.orderOut(nil)
        if AppPicker.current === self { AppPicker.current = nil }
    }
}

// the chip strip inside the horizontal scroll view a row shows when it is
// expanded: all assigned apps, icons and all, scrollable sideways
final class ChipStrip: NSView {
    var assigned: [String] = []
    let allApps: [AppInfo]
    var onRemove: ((String) -> Void)?
    var onAdd: (() -> Void)?
    var onTap: (() -> Void)?
    private var chipFrames: [(NSRect, String)] = []
    private var addFrame: NSRect = .zero
    private let gap: CGFloat = 8
    // only the "✕" removes: clicking the rest of a chip must not delete an
    // app by accident (the whole chip used to be a delete target)
    private let removeZone: CGFloat = 22

    init(allApps: [AppInfo]) {
        self.allApps = allApps
        super.init(frame: .zero)
    }
    required init?(coder: NSCoder) { fatalError("not used") }

    private func label(_ id: String) -> String {
        let name = allApps.first { $0.bundleID == id }?.name ?? id
        return truncate(name, nerdFont("Regular", 11), 150)
    }
    private func chipWidth(_ id: String) -> CGFloat {
        return 16 + 6 + advance(label(id), nerdFont("Regular", 11)) + 22
    }

    private let addChipW: CGFloat = 78

    func stripWidth() -> CGFloat {
        var w: CGFloat = 0
        for id in assigned { w += chipWidth(id) + gap }
        return max(0, w - gap) + gap + addChipW + 4
    }

    private func layoutChips() {
        chipFrames.removeAll()
        var x: CGFloat = 2
        for id in assigned {
            let cw = chipWidth(id)
            chipFrames.append((NSRect(x: x, y: (bounds.height - 24) / 2, width: cw, height: 24), id))
            x += cw + gap
        }
        addFrame = NSRect(x: x, y: (bounds.height - 24) / 2, width: addChipW, height: 24)
    }

    override func draw(_ dirtyRect: NSRect) {
        layoutChips()
        for (f, id) in chipFrames {
            let chip = NSBezierPath(roundedRect: f, xRadius: 5, yRadius: 5)
            palette.itemBG.withAlphaComponent(0.6).setFill()
            chip.fill()
            if let ic = iconForBundle(id) {
                ic.draw(in: NSRect(x: f.minX + 5, y: f.midY - 7, width: 14, height: 14))
            }
            drawMidLeft(label(id), nerdFont("Regular", 11), palette.label,
                        x: f.minX + 24, midTop: bounds.height / 2, height: bounds.height)
            drawMidLeft("✕", nerdFont("Regular", 10), palette.muted,
                        x: f.maxX - 14, midTop: bounds.height / 2, height: bounds.height)
        }
        // a trailing "＋ Add" so an app can be added from the expanded strip
        let add = NSBezierPath(roundedRect: addFrame, xRadius: 5, yRadius: 5)
        palette.accent.withAlphaComponent(0.30).setStroke()
        add.lineWidth = 1
        add.stroke()
        drawMidCenter("＋ Add", nerdFont("Bold", 11), palette.accent,
                      centerX: addFrame.midX, midTop: bounds.height / 2, height: bounds.height)
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if addFrame.contains(p) { onAdd?(); return }
        for (f, id) in chipFrames where f.contains(p) {
            if p.x >= f.maxX - removeZone { onRemove?(id) } else { onTap?() }
            return
        }
        onTap?()
    }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class WorkspaceRowView: NSView {
    let ws: String
    var assigned: [String]
    let allApps: [AppInfo]
    var onAssign: ((String) -> Void)?
    var onRemove: ((String) -> Void)?
    private var chipFrames: [(NSRect, String)] = []
    private var overflowApps: [String] = []
    private var moreFrame: NSRect = .zero
    private var expanded = false
    private let addButton = ButtonView()
    private let chipScroll = NSScrollView()
    private let chipStrip: ChipStrip
    private let labelW: CGFloat = 120
    private let addW: CGFloat = 96

    init(ws: String, assigned: [String], allApps: [AppInfo]) {
        self.ws = ws
        self.assigned = assigned
        self.allApps = allApps
        self.chipStrip = ChipStrip(allApps: allApps)
        super.init(frame: .zero)
        addButton.title = "＋ Add App"
        addButton.onClick = { [weak self] in self?.showMenu() }
        addSubview(addButton)
        chipScroll.hasHorizontalScroller = true
        chipScroll.drawsBackground = false
        chipScroll.borderType = .noBorder
        chipScroll.autohidesScrollers = true
        chipScroll.documentView = chipStrip
        chipScroll.isHidden = true
        addSubview(chipScroll)
        chipStrip.onRemove = { [weak self] bundle in self?.onRemove?(bundle) }
        chipStrip.onAdd = { [weak self] in self?.showMenu() }
        chipStrip.onTap = { [weak self] in self?.setExpanded(false) }
    }
    required init?(coder: NSCoder) { fatalError("not used") }

    private func chipLabel(_ id: String) -> String {
        let name = allApps.first(where: { $0.bundleID == id })?.name ?? id
        return truncate(name, nerdFont("Regular", 11), 150)
    }

    private func chipWidth(_ id: String) -> CGFloat {
        return 16 + 6 + advance(chipLabel(id), nerdFont("Regular", 11)) + 22
    }

    // computed on every draw as well as on layout: a rebuild after a
    // removal does not always trigger layout(), and a stale overflow list is
    // exactly the "+N more" that would not come back
    private func computeChips() {
        chipFrames.removeAll()
        overflowApps.removeAll()
        moreFrame = .zero
        var x: CGFloat = labelW + 8
        let limit = bounds.width - addW - 8
        var placed = 0
        for (idx, id) in assigned.enumerated() {
            let cw = chipWidth(id)
            let remaining = assigned.count - idx - 1
            // if chips will not fit, keep room for the "+N more" label
            let reserve: CGFloat = remaining > 0 ? 74 : 0
            if x + cw > limit - reserve { break }
            chipFrames.append((NSRect(x: x, y: (bounds.height - 24) / 2, width: cw, height: 24), id))
            x += cw + 8
            placed = idx + 1
        }
        overflowApps = Array(assigned.dropFirst(placed))
        if !overflowApps.isEmpty {
            let mx = chipFrames.last.map { $0.0.maxX + 8 } ?? (labelW + 8)
            moreFrame = NSRect(x: mx, y: (bounds.height - 24) / 2, width: 80, height: 24)
        }
    }

    override func layout() {
        super.layout()
        let w: CGFloat = addW, h: CGFloat = 24
        addButton.frame = NSRect(x: bounds.width - w, y: (bounds.height - h) / 2, width: w, height: h)
        computeChips()
        let stripX = labelW + 8
        let stripW = max(0, bounds.width - stripX - addW - 8)
        chipScroll.frame = NSRect(x: stripX, y: 0, width: stripW, height: bounds.height)
        if expanded {
            chipScroll.isHidden = false
            chipStrip.assigned = assigned
            // fill the clip view at least: the empty space past the chips is
            // still part of the strip, so a click there reaches ChipStrip and
            // folds the row instead of being swallowed by the scroll view
            let stripW = max(chipStrip.stripWidth(), chipScroll.contentSize.width)
            chipStrip.frame = NSRect(x: 0, y: 0, width: stripW, height: bounds.height)
            chipStrip.needsDisplay = true
        } else {
            chipScroll.isHidden = true
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        computeChips()
        drawMidLeft("Workspace \(ws)", nerdFont("Bold", 12), palette.label,
                    x: 0, midTop: bounds.height / 2, height: bounds.height)
        if !assigned.isEmpty, expanded || !overflowApps.isEmpty {
            drawMidLeft(expanded ? "‹" : "›", nerdFont("Bold", 12), palette.accent,
                        x: labelW - 16, midTop: bounds.height / 2, height: bounds.height)
        }
        if expanded { return }   // the horizontally scrollable strip draws them

        for (frame, id) in chipFrames {
            let name = chipLabel(id)
            let chip = NSBezierPath(roundedRect: frame, xRadius: 5, yRadius: 5)
            palette.itemBG.withAlphaComponent(0.6).setFill()
            chip.fill()
            if let ic = iconForBundle(id) {
                ic.draw(in: NSRect(x: frame.minX + 5, y: frame.midY - 7, width: 14, height: 14))
            }
            drawMidLeft(name, nerdFont("Regular", 11), palette.label,
                        x: frame.minX + 24, midTop: bounds.height / 2, height: bounds.height)
            drawMidLeft("✕", nerdFont("Regular", 10), palette.muted,
                        x: frame.maxX - 14, midTop: bounds.height / 2, height: bounds.height)
        }
        if assigned.isEmpty {
            drawMidLeft("No app assigned", nerdFont("Regular", 11), palette.muted,
                        x: labelW + 8, midTop: bounds.height / 2, height: bounds.height)
        } else if !overflowApps.isEmpty {
            // accent, and clickable: reveals the hidden apps in a sideways
            // scroll on this same row
            drawMidLeft("+\(overflowApps.count) more", nerdFont("Bold", 11), palette.accent,
                        x: moreFrame.minX, midTop: bounds.height / 2, height: bounds.height)
        }
    }

    override func mouseDown(with event: NSEvent) {
        // let the tab fold any OTHER open row before this click is handled
        onWillHandleClick?(self)
        let p = convert(event.locationInWindow, from: nil)
        if expanded {
            // the chips live in the strip subview, which folds the row itself
            // on a non-✕ tap; a click on the row body folds it too
            setExpanded(false)
            return
        }
        // the chevron/"+N more": expand into the scrollable strip
        if !overflowApps.isEmpty, (moreFrame.contains(p) || p.x < labelW) {
            setExpanded(true)
            return
        }
        // a chip only loses its app on the "✕"; its body opens the row so the
        // hidden apps can be seen (no overflow means there is nothing to open)
        for (frame, id) in chipFrames where frame.contains(p) {
            if p.x >= frame.maxX - 22 { onRemove?(id) }
            else if !overflowApps.isEmpty { setExpanded(true) }
            return
        }
    }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // The tab owns one always-on click monitor and tracks which row is open.
    // A per-row monitor was tried first and was unreliable: the row is a
    // short-lived view (rebuilt on every add or remove), so its monitor
    // could be gone before a click arrived.
    var onWillHandleClick: ((WorkspaceRowView) -> Void)?
    var onExpandedChanged: ((WorkspaceRowView, Bool) -> Void)?

    func setExpanded(_ v: Bool) {
        guard expanded != v else { return }
        expanded = v
        // toggle the strip directly, not via layout(): a missing layout pass
        // would leave the strip on top of the "+N more" it should reveal.
        // On collapse the strip leaves the hierarchy entirely, so it can never
        // paint over the folded row (a hidden view still could).
        if v {
            let stripX = labelW + 8
            chipScroll.frame = NSRect(x: stripX, y: 0,
                                      width: max(0, bounds.width - stripX - addW - 8),
                                      height: bounds.height)
            chipStrip.assigned = assigned
            chipStrip.frame = NSRect(x: 0, y: 0,
                                     width: max(chipStrip.stripWidth(), chipScroll.contentSize.width),
                                     height: bounds.height)
            chipStrip.needsDisplay = true
            if chipScroll.superview == nil { addSubview(chipScroll) }
            chipScroll.isHidden = false
        } else {
            chipScroll.isHidden = true
            chipScroll.removeFromSuperview()
        }
        computeChips()
        needsLayout = true
        needsDisplay = true
        displayIfNeeded()
        onExpandedChanged?(self, v)
    }

    private func showMenu() {
        AppPicker.present(apps: allApps, near: addButton, in: self) { [weak self] bundle in
            self?.onAssign?(bundle)
        }
    }
}

final class WorkspacesTabView: NSView, ScrollStepTab {
    private var screens: [ScreenInfo] = []
    func scrollStep(_ dy: CGFloat) { scrollBy(scroll, dy) }
    func refreshColors() {
        needsDisplay = true
        screenSeg.needsDisplay = true
        for r in rows { r.needsDisplay = true; r.subviews.forEach { $0.needsDisplay = true } }
        scroller.refresh()
    }
    private var allApps: [AppInfo] = []
    private var rules: [(String, String)] = []
    private var savedRules: [(String, String)] = []
    private var screenIndex = 0
    private var rows: [WorkspaceRowView] = []
    private let screenSeg = SegmentedView()
    private let scroll = NSScrollView()
    private let doc = NSView()
    private let scroller = CustomScroller()
    private let scrollerW: CGFloat = 8
    let saveButton = ButtonView()
    private var status = ""
    private var expandedRow: WorkspaceRowView?
    private var clickMonitor: Any?

    private let headerH: CGFloat = 40
    private let bottomBarH: CGFloat = 54
    private let rowH: CGFloat = 48
    private var lastDocH: CGFloat = -1

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        screens = screensInfo()
        allApps = installedApps()
        rules = readWorkspaceRules()
        savedRules = rules
        if screens.isEmpty { screens = [ScreenInfo(name: "This display", workspaces: (1...9).map(String.init))] }
        screenSeg.items = screens.map { $0.name }
        screenSeg.index = 0
        screenSeg.onChange = { [weak self] i in self?.screenIndex = i; self?.rebuildRows() }
        addSubview(screenSeg)
        scroll.hasVerticalScroller = false
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        addSubview(scroll)
        scroll.documentView = doc
        addSubview(scroller)
        scroller.scrollView = scroll
        scroll.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(scrolled),
            name: NSView.boundsDidChangeNotification, object: scroll.contentView)
        saveButton.title = "Save"
        saveButton.onClick = { [weak self] in self?.save() }
        addSubview(saveButton)
        // one always-on monitor for the whole tab: a click anywhere outside
        // the open row folds it back. Row lifetime does not matter here.
        clickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] e in
            self?.collapseIfClickOutside(e)
            return e
        }
        rebuildRows()
    }
    required init?(coder: NSCoder) { fatalError("not used") }
    deinit { if let m = clickMonitor { NSEvent.removeMonitor(m) } }
    @objc private func scrolled() { scroller.refresh() }

    private func collapseExpanded(except keep: WorkspaceRowView?) {
        if let r = expandedRow, r !== keep { r.setExpanded(false); expandedRow = nil }
    }

    func collapseIfClickOutside(_ e: NSEvent) {
        guard let r = expandedRow else { return }
        let inside = (e.window === r.window) && r.bounds.contains(r.convert(e.locationInWindow, from: nil))
        let hit = r.window?.contentView?.hitTest(e.locationInWindow)
        if !inside { r.setExpanded(false); expandedRow = nil; return }
        // a click inside the open row folds it too, so there is no dead zone
        // that only a reopen can clear. The one exception is the Add button,
        // which must open the picker. Deferred one tick so the click is
        // handled against the current layout first (a chip "✕" rebuilds the
        // rows and clears expandedRow before this runs).
        if hit is ButtonView { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.expandedRow === r else { return }
            r.setExpanded(false)
            self.expandedRow = nil
        }
    }

    // a click on the tab's own empty space also folds the open row, and is
    // consumed so it does not fall through to the modal's close-on-click
    override func mouseDown(with event: NSEvent) {
        collapseExpanded(except: nil)
    }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // the workspace rules are sensitive: only the SAVE button persists them.
    // Re-entering the tab drops anything unsaved and shows the file's state
    // again, so an edit is never mistaken for an applied one.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil { reloadFromDisk() }
    }

    private func reloadFromDisk() {
        rules = readWorkspaceRules()
        savedRules = rules
        status = ""
        rebuildRows()
    }

    // called when the modal is shown again: unsaved edits are dropped
    func resetToSaved() { reloadFromDisk() }

    private var dirty: Bool {
        rules.map { "\($0.0) \($0.1)" }.sorted() != savedRules.map { "\($0.0) \($0.1)" }.sorted()
    }

    private func assigned(for ws: String) -> [String] {
        rules.filter { $0.1 == ws }.map { $0.0 }
    }

    private func rebuildRows() {
        for r in rows { r.removeFromSuperview() }
        rows.removeAll()
        expandedRow = nil
        guard screens.indices.contains(screenIndex) else { return }
        for ws in screens[screenIndex].workspaces {
            let row = WorkspaceRowView(ws: ws, assigned: assigned(for: ws), allApps: allApps)
            row.onAssign = { [weak self] bundle in self?.assign(bundle, to: ws) }
            row.onRemove = { [weak self] bundle in self?.unassign(bundle) }
            row.onWillHandleClick = { [weak self] r in self?.collapseExpanded(except: r) }
            row.onExpandedChanged = { [weak self] r, exp in
                if exp {
                    self?.collapseExpanded(except: r)
                    self?.expandedRow = r
                } else if self?.expandedRow === r {
                    self?.expandedRow = nil
                }
            }
            doc.addSubview(row)
            rows.append(row)
        }
        for row in rows { row.needsLayout = true; row.needsDisplay = true }
        needsLayout = true
        needsDisplay = true
    }

    private func assign(_ bundle: String, to ws: String) {
        rules.removeAll { $0.0 == bundle }
        rules.append((bundle, ws))
        rebuildRows()
    }

    private func unassign(_ bundle: String) {
        rules.removeAll { $0.0 == bundle }
        rebuildRows()
    }

    override func layout() {
        super.layout()
        let showSeg = screens.count > 1
        screenSeg.isHidden = !showSeg
        let segSize = screenSeg.sizeThatFits()
        screenSeg.frame = NSRect(x: 0, y: bounds.height - 2 - segSize.height,
                                 width: min(segSize.width, bounds.width), height: segSize.height)
        let saveW: CGFloat = 96, saveH: CGFloat = 24
        saveButton.frame = NSRect(x: (bounds.width - saveW) / 2,
                                  y: (bottomBarH - saveH) / 2, width: saveW, height: saveH)
        // a whole number of rows: on first open the list sits at the top, so
        // an unrounded viewport would show a half-cut row at its bottom edge.
        // The leftover goes as a small gap above the Save bar instead.
        let rawH = max(0, bounds.height - bottomBarH - headerH)
        let shownRows = floor(rawH / rowH)
        let scrollH = shownRows > 0 ? shownRows * rowH : rawH
        let gap = rawH - scrollH
        scroll.frame = NSRect(x: 0, y: bottomBarH + gap, width: max(0, bounds.width - scrollerW - 14), height: scrollH)
        scroller.frame = NSRect(x: bounds.width - scrollerW, y: bottomBarH + gap, width: scrollerW, height: scrollH)
        scroller.refresh()
        let w = scroll.contentSize.width
        guard w > 0 else { return }
        if abs(doc.frame.width - w) > 0.5 { doc.frame.size.width = w }
        let h = CGFloat(rows.count) * rowH
        if abs(doc.frame.height - h) > 0.5 { doc.frame.size.height = h }
        for (i, row) in rows.enumerated() {
            let f = NSRect(x: 0, y: h - CGFloat(i + 1) * rowH, width: w, height: rowH)
            if row.frame != f { row.frame = f }
        }
        if h != lastDocH {
            lastDocH = h
            scroll.contentView.scroll(to: NSPoint(x: 0, y: max(0, h - scroll.contentSize.height)))
            scroll.reflectScrolledClipView(scroll.contentView)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        if screens.count <= 1, let s = screens.first {
            drawMidLeft("Screen: \(s.name)", nerdFont("Bold", 12), palette.accent,
                        x: 0, midTop: headerH / 2, height: bounds.height)
        }
        palette.muted.withAlphaComponent(0.25).setFill()
        NSRect(x: 0, y: bottomBarH - 0.5, width: bounds.width, height: 1).fill()
        if !status.isEmpty {
            drawMidLeft(status, nerdFont("Regular", 11), palette.muted,
                        x: 0, midTop: bounds.height - bottomBarH / 2, height: bounds.height)
        } else if dirty {
            drawMidLeft("Unsaved changes", nerdFont("Regular", 11), palette.accent,
                        x: 0, midTop: bounds.height - bottomBarH / 2, height: bounds.height)
        }
    }

    private func save() {
        saveButton.busy = true
        status = "Applying…"
        needsDisplay = true
        let rules = self.rules
        // bundles taken out since the last save: omacosy-settings only adds
        // and corrects OmniWM rules, so these have to be pruned explicitly
        let removed = savedRules.map { $0.0 }.filter { b in !rules.contains { $0.0 == b } }
        DispatchQueue.global().async { [weak self] in
            let wrote = writeWorkspaceRules(rules)
            var err = ""
            if wrote {
                let (code, out) = shell("\(HOME)/.local/bin/omacosy-settings 2>&1")
                if code != 0 {
                    err = out.split(separator: "\n").last.map(String.init) ?? ""
                } else if !removed.isEmpty {
                    let args = removed.map(shellQuote).joined(separator: " ")
                    _ = shell("\(HOME)/.local/bin/omacosy-ws-prune \(args) 2>&1")
                }
            } else { err = "could not write settings.conf" }
            DispatchQueue.main.async {
                self?.savedRules = rules
                self?.status = err.isEmpty ? "Saved" : "Error: \(err)"
                self?.saveButton.busy = false
                self?.needsDisplay = true
            }
        }
    }
}

// --- themes tab ------------------------------------------------------------

struct ThemeCell: Equatable {
    let logical: String
    let wallpaper: String
    let title: String
    let isCustom: Bool
    let paletteFile: String
    // a named edition: its immutable record id; nil on stock and raw cells
    var editionID: String?
    // a raw wallpaper with editions: how many variations hang off its source
    var variations: Int
    var storedColors: [NSColor]

    init(logical: String, wallpaper: String, title: String, isCustom: Bool,
         paletteFile: String, editionID: String? = nil, variations: Int = 0,
         storedColors: [NSColor] = []) {
        self.logical = logical
        self.wallpaper = wallpaper
        self.title = title
        self.isCustom = isCustom
        self.paletteFile = paletteFile
        self.editionID = editionID
        self.variations = variations
        self.storedColors = storedColors
    }
}

func stableHash(_ s: String) -> String {
    var h: UInt64 = 0xcbf29ce484222325
    for b in s.utf8 { h ^= UInt64(b); h = h &* 0x100000001b3 }
    return String(h, radix: 16)
}

func isImageFile(_ name: String) -> Bool {
    let ext = (name as NSString).pathExtension.lowercased()
    return ["jpg", "jpeg", "png", "webp", "heic", "gif"].contains(ext)
}

func prettyThemeName(_ t: String) -> String {
    t.split(separator: "-").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
}

func prettyWallName(_ file: String) -> String {
    var s = (file as NSString).deletingPathExtension
    if let r = s.range(of: "^[0-9]+[-_]", options: .regularExpression) { s.removeSubrange(r) }
    s = s.replacingOccurrences(of: "-", with: " ").replacingOccurrences(of: "_", with: " ")
    return s.split(separator: " ").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
}

func stockVariants() -> [ThemeCell] {
    guard let repo = repoDir() else { return [] }
    let themesDir = repo + "/themes"
    let themes = ((try? FileManager.default.contentsOfDirectory(atPath: themesDir)) ?? [])
        .filter { !$0.hasPrefix(".") }.sorted()
    var out: [ThemeCell] = []
    for t in themes {
        let colors = themesDir + "/" + t + "/colors.toml"
        guard FileManager.default.fileExists(atPath: colors) else { continue }
        let bg = themesDir + "/" + t + "/backgrounds"
        let files = ((try? FileManager.default.contentsOfDirectory(atPath: bg)) ?? [])
            .filter { isImageFile($0) }.sorted()
        for f in files {
            out.append(ThemeCell(logical: t, wallpaper: bg + "/" + f,
                                 title: "\(prettyThemeName(t)) — \(prettyWallName(f))",
                                 isCustom: false, paletteFile: colors))
        }
    }
    return out
}

// symlink-canonical spelling, so a raw entry and an edition's recorded
// provenance match even when one is /tmp and the other /private/tmp
func canonicalPath(_ path: String) -> String {
    URL(fileURLWithPath: path).resolvingSymlinksInPath().path
}

// --- theme editions ---------------------------------------------------------

struct ThemeEdition {
    let id: String
    let name: String
    let primary: Bool
    let sourcePath: String?
    let media: String?
    let colors: [NSColor]
}

// What the editor and the grid need from the record store: id, name,
// provenance and the stored palette. `theme list --json` is the library's
// own answer, so the tab and the CLI can never disagree.
func allEditions() -> [ThemeEdition] {
    let (code, out) = shell("\(HOME)/.local/bin/omacosy-themecore theme list --json 2>/dev/null")
    guard code == 0, let data = out.data(using: .utf8),
          let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
    return rows.compactMap { row in
        guard let id = row["id"] as? String, let name = row["name"] as? String else { return nil }
        let wall = row["wallpaper"] as? [String: Any] ?? [:]
        let palette = row["palette"] as? [String: Any] ?? [:]
        let hexes = palette["colors"] as? [String] ?? []
        return ThemeEdition(id: id, name: name,
                            primary: (row["primary"] as? Bool) ?? false,
                            sourcePath: wall["path"] as? String,
                            media: wall["media"] as? String,
                            colors: hexes.compactMap(hexColor))
    }
}

// The edition's own snapshot wins; the recorded source is the fallback. A
// record with neither left in place cannot be applied, so it gets no cell.
func editionImage(_ e: ThemeEdition) -> String? {
    if let m = e.media, !m.isEmpty, !m.contains("/") {
        let p = HOME + "/.local/share/omacosy/theme-media/" + m
        if FileManager.default.fileExists(atPath: p) { return p }
    }
    if let s = e.sourcePath, FileManager.default.fileExists(atPath: s) { return s }
    return nil
}

// Every wallpaper in the configured folder is an auto-theme
// (`Wallpaper #N`); named editions always sit on top.
func customVariants() -> [ThemeCell] {
    let dir = wallpapersDir()
    let files = ((try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? [])
        .filter { isImageFile($0) }.sorted()
    let editions = allEditions()

    var bySource: [String: Int] = [:]
    for e in editions {
        guard let src = e.sourcePath else { continue }
        bySource[canonicalPath(src), default: 0] += 1
    }

    var out: [ThemeCell] = []
    // named editions A→Z on top; the raw entries stay below in today's
    // lexicographic order and are numbered over the full sorted list
    let sorted = editions.sorted {
        let cmp = $0.name.localizedCaseInsensitiveCompare($1.name)
        return cmp == .orderedSame ? $0.id < $1.id : cmp == .orderedAscending
    }
    for e in sorted {
        guard let img = editionImage(e) else { continue }
        out.append(ThemeCell(logical: "custom", wallpaper: img, title: e.name,
                             isCustom: true, paletteFile: "",
                             editionID: e.id, storedColors: e.colors))
    }
    for (i, f) in files.enumerated() {
        let p = dir + "/" + f
        out.append(ThemeCell(logical: "custom", wallpaper: p,
                             title: "Wallpaper #\(i + 1)", isCustom: true, paletteFile: "",
                             variations: bySource[canonicalPath(p), default: 0]))
    }
    return out
}

// --- wallpapers tab data ---------------------------------------------------

// The configured folder, read from the CLI so the dashboard and
// `omacosy-custom-theme status` can never disagree. status answers even
// when terminal following is off, so this tab never depends on a switch.
func wallpapersDir() -> String {
    let (_, out) = shell("\(HOME)/.local/bin/omacosy-custom-theme status 2>/dev/null")
    for line in out.split(separator: "\n") {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard t.hasPrefix("wallpaper directory"), let r = t.range(of: ":") else { continue }
        let d = t[r.upperBound...].trimmingCharacters(in: .whitespaces)
        if !d.isEmpty { return d }
    }
    return HOME + "/Pictures/wallpapers"
}

enum WallpaperImport { case added, skipped, failed }

// Copy, never move: the user's file stays where it was, and picking an
// image already in the folder is skipped — compared by content against
// every file in the folder, not just against a same-named file, so the
// same picture under a new name does not pile up. A name already taken by
// genuinely different content gets a -2/-3 suffix; nothing is ever
// overwritten.
func importWallpaper(_ src: String, into dir: String) -> WallpaperImport {
    let fm = FileManager.default
    let name = (src as NSString).lastPathComponent
    guard isImageFile(name) else { return .failed }
    do { try fm.createDirectory(atPath: dir, withIntermediateDirectories: true) }
    catch { return .failed }
    let entries = (try? fm.contentsOfDirectory(atPath: dir)) ?? []
    for e in entries where isImageFile(e) {
        let p = dir + "/" + e
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: p, isDirectory: &isDir), !isDir.boolValue else { continue }
        if fm.contentsEqual(atPath: src, andPath: p) { return .skipped }
    }
    var dest = dir + "/" + name
    var n = 2
    while fm.fileExists(atPath: dest) {
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        dest = dir + "/\(base)-\(n)" + (ext.isEmpty ? "" : ".\(ext)")
        n += 1
    }
    do { try fm.copyItem(atPath: src, toPath: dest); return .added }
    catch { return .failed }
}

func hexColor(_ s: String) -> NSColor? {
    var h = s
    if h.hasPrefix("#") { h.removeFirst() }
    guard h.count == 6, let v = UInt64(h, radix: 16) else { return nil }
    return color(fromARGB: 0xff000000 | v)
}

// WCAG relative luminance, so the Edit pill can pick a label colour that
// stays readable on the accent fill. 0.179 is the sRGB pivot where black
// and white trade places.
func relativeLuminance(_ c: NSColor) -> CGFloat {
    let s = c.usingColorSpace(.sRGB) ?? c
    func lin(_ v: CGFloat) -> CGFloat {
        v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
    }
    return 0.2126 * lin(s.redComponent) + 0.7152 * lin(s.greenComponent) + 0.0722 * lin(s.blueComponent)
}

func parseColorsToml(_ path: String) -> [NSColor] {
    guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return [] }
    var map: [String: String] = [:]
    for line in text.split(separator: "\n") {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard let eq = t.firstIndex(of: "=") else { continue }
        let k = t[..<eq].trimmingCharacters(in: .whitespaces)
        var v = t[t.index(after: eq)...].trimmingCharacters(in: .whitespaces)
        v = v.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        map[String(k)] = v
    }
    let ansi = (0...15).map { "color\($0)" }
    if ansi.allSatisfy({ map[$0] != nil }) {
        return ansi.compactMap { map[$0].flatMap(hexColor) }
    }
    let order = ["background", "accent", "color1", "color2", "color3", "color4", "color5", "color6"]
    return order.compactMap { map[$0].flatMap(hexColor) }
}

// a derived custom theme has no colors.toml; its palette lives in the
// generated sketchybar.sh the bar itself reads. Eight keys, same order the
// stock strip uses: background, accent, then the named hues.
func parseSketchybar(_ path: String) -> [NSColor] {
    guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return [] }
    var map: [String: NSColor] = [:]
    for line in text.split(separator: "\n") {
        let t = line.replacingOccurrences(of: "export ", with: "")
        let parts = t.split(separator: "=")
        guard parts.count == 2, parts[1].hasPrefix("0x"),
              let v = UInt64(parts[1].dropFirst(2), radix: 16) else { continue }
        map[String(parts[0])] = color(fromARGB: v)
    }
    let order = ["BAR_BG_SOLID", "ACCENT", "RED", "GREEN", "YELLOW", "ITEM_BG", "LABEL_COLOR", "MUTED"]
    return order.compactMap { map[$0] }
}

// derive-on-first-use for a custom wallpaper; cached by its derived dir
func customPalette(_ wallpaper: String) -> [NSColor] {
    let (code, out) = shell("\(HOME)/.local/bin/omacosy-custom-theme theme --raw \(shellQuote(wallpaper)) 2>/dev/null")
    guard code == 0 else { return [] }
    let dir = out.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "\n").last.map(String.init) ?? ""
    guard !dir.isEmpty else { return [] }
    // the full 16 ANSI colours the editor seeds from (same helper, same
    // milliseconds); the bar's 8-role summary is the fallback
    let envFile = NSTemporaryDirectory()
        + "omacosy-cell-palette-\(ProcessInfo.processInfo.processIdentifier)-\(UUID().uuidString).env"
    let (tc, _) = shell("\(HOME)/.local/bin/omacosy-term-palette \(shellQuote(dir)) \(shellQuote(envFile)) >/dev/null 2>&1")
    var byIndex: [Int: NSColor] = [:]
    if tc == 0, let text = try? String(contentsOfFile: envFile, encoding: .utf8) {
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2, parts[0].hasPrefix("OMACOSY_P"),
                  let i = Int(parts[0].dropFirst(9)) else { continue }
            let value = parts[1].trimmingCharacters(in: CharacterSet(charactersIn: "'\""))
            if let col = hexColor(value) { byIndex[i] = col }
        }
    }
    try? FileManager.default.removeItem(atPath: envFile)
    if byIndex.count == 16 { return (0..<16).compactMap { byIndex[$0] } }
    return parseSketchybar(dir + "/sketchybar.sh")
}

func shellQuote(_ s: String) -> String {
    "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
}

func thumbnail(_ path: String, maxPixel: Int = 360) -> NSImage? {
    let dir = HOME + "/.local/state/omacosy/dashboard/thumbs"
    let cache = dir + "/" + stableHash(path + ":\(maxPixel)") + ".png"
    if let img = NSImage(contentsOfFile: cache) { return img }
    guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil) else { return nil }
    let opts: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceThumbnailMaxPixelSize: maxPixel,
    ]
    guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    if let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: cache) as CFURL, "public.png" as CFString, 1, nil) {
        CGImageDestinationAddImage(dest, cg, nil)
        CGImageDestinationFinalize(dest)
    }
    return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
}

func applyTheme(_ c: ThemeCell, done: @escaping () -> Void) {
    // a named edition applies through its record, a raw wallpaper through
    // the derived dir, a stock theme through its logical name
    let cmd: String
    if let id = c.editionID {
        let json = HOME + "/.config/omacosy/themes/" + id + ".json"
        cmd = "\(HOME)/.local/bin/omacosy-theme-switch set-theme \(shellQuote(json))"
    } else if c.isCustom {
        cmd = "\(HOME)/.local/bin/omacosy-theme-switch set-raw \(shellQuote(c.wallpaper))"
    } else {
        cmd = "\(HOME)/.local/bin/omacosy-theme-switch set \(c.logical) \(shellQuote(c.wallpaper))"
    }
    DispatchQueue.global().async {
        _ = shell(cmd)
        DispatchQueue.main.async { done() }
    }
}

final class ThemeGridView: NSView {
    var cells: [ThemeCell] = []
    var customDir: String?
    var thumbs: [Int: NSImage] = [:]
    var palettes: [Int: [NSColor]] = [:]
    var pending: Set<Int> = []
    var cellFrames: [Int: NSRect] = [:]
    var headers: [(NSRect, String)] = []
    var onApplied: ((String) -> Void)?
    // the Edit pill's click: opens the Theme Editor on this cell
    var onEdit: ((ThemeCell) -> Void)?
    private var hoveredIndex: Int?
    private var hoverTracking: NSTrackingArea?

    private var customHeaderRect = NSRect.zero
    private var separatorRect = NSRect.zero
    private let headerH: CGFloat = 34
    private let cellH: CGFloat = 180
    private let gapX: CGFloat = 14
    private let gapY: CGFloat = 16
    private let cellPaletteH: CGFloat = 12
    private let cellLabelH: CGFloat = 18
    private let cellThumbGap: CGFloat = 12
    private let pillH: CGFloat = 22
    private let pillInset: CGFloat = 8

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
    }
    required init?(coder: NSCoder) { fatalError("not used") }

    func rebuild() {
        cellFrames.removeAll(); headers.removeAll()
        hoveredIndex = nil
        let W = max(bounds.width, 120)
        // keep a margin at both edges so the hover ring is never clipped by
        // the scroll view's clip rect
        let padX: CGFloat = 4
        let usable = W - padX * 2
        var cols = max(2, Int((usable + gapX) / (216 + gapX)))
        if cols < 2 { cols = 2 }
        let cellW = (usable - gapX * CGFloat(cols - 1)) / CGFloat(cols)

        var top: CGFloat = 0
        var x: CGFloat = padX
        var idx = 0

        func placeCell(_ cellIndex: Int) {
            if x + cellW > padX + usable + 0.5 { x = padX; top += cellH + gapY }
            let f = NSRect(x: x, y: top, width: cellW, height: cellH)
            cellFrames[cellIndex] = f
            x += cellW + gapX
        }
        func endRow() { if x > padX { top += cellH + gapY; x = padX } }

        let stockCount = cells.filter { !$0.isCustom }.count
        if stockCount > 0 {
            headers.append((NSRect(x: 0, y: top, width: W, height: headerH), "Omarchy Themes"))
            top += headerH + 8
            for (i, c) in cells.enumerated() where !c.isCustom { placeCell(i); idx += 1 }
            endRow()
            top += 6
        }

        // custom section: every wallpaper is an auto-theme, so the section
        // shows whenever there is anything to show — no switch state gates it
        let customIdx = cells.enumerated().filter { $0.element.isCustom }.map { $0.offset }
        if !customIdx.isEmpty {
            // a rule between the Omarchy grid and the custom grid, so the two
            // galleries read as separate sections
            top += 22
            separatorRect = NSRect(x: 0, y: top, width: W, height: 1)
            top += 1 + 22
            customHeaderRect = NSRect(x: 0, y: top, width: W, height: headerH)
            headers.append((customHeaderRect, "Custom Themes"))
            top += headerH + 8
            for i in customIdx { placeCell(i) }
            endRow()
        }

        // convert top-coords to non-flipped bottom coords
        let contentH = max(top + 8, 200)
        func flip(_ r: NSRect) -> NSRect {
            NSRect(x: r.origin.x, y: contentH - r.origin.y - r.height, width: r.width, height: r.height)
        }
        for (k, v) in cellFrames { cellFrames[k] = flip(v) }
        headers = headers.map { (flip($0.0), $0.1) }
        customHeaderRect = flip(customHeaderRect)
        separatorRect = flip(separatorRect)

        frame.size = NSSize(width: W, height: contentH)
        needsDisplay = true
    }

    func loadVisible(_ rect: NSRect) {
        for (i, f) in cellFrames where f.intersects(rect) {
            guard thumbs[i] == nil, !pending.contains(i) else { continue }
            pending.insert(i)
            loadCell(i)
        }
    }

    private func loadCell(_ i: Int) {
        guard cells.indices.contains(i) else { pending.remove(i); return }
        let c = cells[i]
        DispatchQueue.global().async { [weak self] in
            let img = thumbnail(c.wallpaper)
            let pal: [NSColor]
            if !c.storedColors.isEmpty { pal = c.storedColors }
            else if c.isCustom { pal = customPalette(c.wallpaper) }
            else { pal = parseColorsToml(c.paletteFile) }
            DispatchQueue.main.async {
                // a reload may have reshuffled the cells while this was in
                // flight; only land on the cell it was decoded for
                guard let self, self.cells.indices.contains(i),
                      self.cells[i].wallpaper == c.wallpaper else { return }
                self.thumbs[i] = img
                self.palettes[i] = pal
                self.pending.remove(i)
                self.needsDisplay = true
            }
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        // section labels only: the folder buttons live in the Wallpapers tab,
        // which owns the directory
        for (r, title) in headers {
            drawMidLeft(title, nerdFont("Bold", 13), palette.accent,
                        x: 0, midTop: bounds.height - r.midY, height: bounds.height)
        }
        if cells.contains(where: { $0.isCustom }) {
            palette.muted.withAlphaComponent(0.25).setFill()
            separatorRect.fill()
        }
        for (i, f) in cellFrames {
            drawCell(i, f)
        }
    }

    private func drawCell(_ i: Int, _ f: NSRect) {
        // leave room under the thumbnail for the hover ring (2 px) plus air
        // before the theme name
        let thumbRect = NSRect(x: f.minX, y: f.minY + cellPaletteH + cellLabelH + cellThumbGap,
                               width: f.width, height: f.height - cellPaletteH - cellLabelH - cellThumbGap)
        let thumbCorner = min(windowCornerRadius(7), min(thumbRect.width, thumbRect.height) / 2)
        let thumb = NSBezierPath(roundedRect: thumbRect, xRadius: thumbCorner, yRadius: thumbCorner)
        NSGraphicsContext.current?.saveGraphicsState()
        thumb.setClip()
        if let img = thumbs[i] {
            drawAspectFill(img, in: thumbRect)
        } else {
            palette.itemBG.withAlphaComponent(0.5).setFill()
            thumbRect.fill()
            drawMidCenter("loading…", nerdFont("Regular", 10), palette.muted,
                          centerX: thumbRect.midX, midTop: bounds.height - thumbRect.midY, height: bounds.height)
        }
        NSGraphicsContext.current?.restoreGraphicsState()
        thumb.lineWidth = 1
        palette.muted.withAlphaComponent(0.3).setStroke()
        thumb.stroke()

        // the focus-ring accent, drawn on the thumbnail's own outline: no gap
        // to the picture, and it inherits the radius from windowCornerRadius()
        if i == hoveredIndex {
            thumb.lineWidth = 2
            palette.accent.setStroke()
            thumb.stroke()
        }

        let titleFont = nerdFont("Regular", 11)
        let badgeFont = nerdFont("Regular", 10)
        let n = cells[i].variations
        let badge = n > 0 ? "· \(n) variation\(n == 1 ? "" : "s")" : ""
        let badgeW = badge.isEmpty ? 0 : advance(badge, badgeFont) + 8
        let title = truncate(cells[i].title, titleFont, f.width - badgeW)
        let titleTop = bounds.height - (f.minY + cellPaletteH + cellLabelH)
        drawTopLeft(title, titleFont, palette.label,
                    x: f.minX, top: titleTop, height: bounds.height)
        if !badge.isEmpty {
            drawTopLeft(badge, badgeFont, palette.muted,
                        x: f.minX + advance(title, titleFont) + 8,
                        top: titleTop, height: bounds.height)
        }

        // palette strip along the bottom
        let colors = palettes[i] ?? []
        if !colors.isEmpty {
            let sw = f.width / CGFloat(colors.count)
            for (j, col) in colors.enumerated() {
                col.setFill()
                NSRect(x: f.minX + CGFloat(j) * sw, y: f.minY, width: sw + 0.5, height: cellPaletteH).fill()
            }
        } else {
            palette.itemBG.withAlphaComponent(0.5).setFill()
            NSRect(x: f.minX, y: f.minY, width: f.width, height: cellPaletteH).fill()
        }

        // the Edit pill, drawn only on the hovered custom cell: the door into
        // the Theme Editor. No scrim — the picture stays fully visible.
        if i == hoveredIndex, cells[i].isCustom {
            let label = pillLabel(cells[i])
            let pill = editPillRect(f, label: label)
            let shape = NSBezierPath(roundedRect: pill, xRadius: 6, yRadius: 6)
            palette.accent.setFill()
            shape.fill()
            let ink = relativeLuminance(palette.accent) > 0.179 ? palette.barBG : palette.label
            drawMidCenter(label, nerdFont("Bold", 11), ink,
                          centerX: pill.midX, midTop: bounds.height - pill.midY, height: bounds.height)
        }
    }

    // A named variation resumes a saved record; a raw wallpaper seeds a new
    // one. The label says which, and the pill's width follows it.
    private func pillLabel(_ c: ThemeCell) -> String {
        c.editionID != nil ? "Edit" : "Customize"
    }

    // The pill sits over the picture's bottom-right corner. drawCell and
    // mouseDown share this rect, so the hit test can never disagree with the
    // pill that is on screen.
    private func editPillRect(_ f: NSRect, label: String) -> NSRect {
        let thumbRect = NSRect(x: f.minX, y: f.minY + cellPaletteH + cellLabelH + cellThumbGap,
                               width: f.width, height: f.height - cellPaletteH - cellLabelH - cellThumbGap)
        let w = advance(label, nerdFont("Bold", 11)) + 20
        return NSRect(x: thumbRect.maxX - pillInset - w,
                      y: thumbRect.minY + pillInset,
                      width: w, height: pillH)
    }

    private func drawAspectFill(_ img: NSImage, in rect: NSRect) {
        let imgA = img.size.width / max(img.size.height, 1)
        let rectA = rect.width / max(rect.height, 1)
        var src = NSRect(origin: .zero, size: img.size)
        if imgA > rectA {
            let w = img.size.height * rectA
            src = NSRect(x: (img.size.width - w) / 2, y: 0, width: w, height: img.size.height)
        } else {
            let h = img.size.width / rectA
            src = NSRect(x: 0, y: (img.size.height - h) / 2, width: img.size.width, height: h)
        }
        img.draw(in: rect, from: src, operation: .sourceOver, fraction: 1)
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        for (i, f) in cellFrames where f.contains(p) {
            let c = cells[i]
            // a visible Edit/Customize pill takes the click; anywhere else
            // applies the theme as before
            if i == hoveredIndex, c.isCustom, editPillRect(f, label: pillLabel(c)).contains(p) {
                onEdit?(c)
                return
            }
            applyTheme(c) { [weak self] in self?.onApplied?(c.title) }
            return
        }
    }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = hoverTracking { removeTrackingArea(t) }
        let t = NSTrackingArea(rect: .zero,
                               options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                               owner: self, userInfo: nil)
        addTrackingArea(t)
        hoverTracking = t
    }

    override func mouseMoved(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let hit = cellFrames.first { $0.value.contains(p) }?.key
        guard hit != hoveredIndex else { return }
        hoveredIndex = hit
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        guard hoveredIndex != nil else { return }
        hoveredIndex = nil
        needsDisplay = true
    }
}

func truncate(_ s: String, _ font: NSFont, _ maxW: CGFloat) -> String {
    if advance(s, font) <= maxW { return s }
    var out = s
    while !out.isEmpty, advance(out + "…", font) > maxW { out.removeLast() }
    return out + "…"
}

final class ThemesTabView: NSView, ScrollStepTab {
    private let scroll = NSScrollView()
    private let grid = ThemeGridView()
    func scrollStep(_ dy: CGFloat) { scrollBy(scroll, dy) }
    func refreshColors() {
        needsDisplay = true
        grid.needsDisplay = true
        scroller.refresh()
    }
    private let scroller = CustomScroller()
    private let scrollerW: CGFloat = 8
    private var status = ""
    private var needsGridRebuild = true
    var onApplied: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        scroll.hasVerticalScroller = false
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        addSubview(scroll)
        scroll.documentView = grid
        addSubview(scroller)
        scroller.scrollView = scroll
        grid.onApplied = { [weak self] title in
            self?.status = "Applied \(title)"
            self?.needsDisplay = true
            self?.onApplied?()
        }
        grid.onEdit = { [weak self] cell in
            guard let self, let w = self.window else { return }
            ThemeEditor.present(cell: cell, from: w) { [weak self] message in
                self?.status = message
                self?.needsDisplay = true
                self?.onApplied?()
            }
        }
        scroll.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(visibleChanged),
            name: NSView.boundsDidChangeNotification, object: scroll.contentView)
        reload()
        watchSources()
    }
    required init?(coder: NSCoder) { fatalError("not used") }
    deinit { NotificationCenter.default.removeObserver(self) }

    // re-read when the tab is shown, so a wallpaper added or removed while
    // the modal is closed is picked up
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil { reload() }
    }

    private var watchedPaths: [String] = []
    private func watchSources() {
        var paths: [String] = []
        if let r = repoDir() { paths.append(r + "/themes") }
        if let d = grid.customDir { paths.append(d) }
        paths.append(HOME + "/.config/omacosy/themes")
        paths.append(HOME + "/.config/omacosy/themes.conf")
        for p in paths where !watchedPaths.contains(p) {
            watchedPaths.append(p)
            watch(p) { [weak self] in self?.reload() }
        }
    }

    @objc private func visibleChanged() { grid.loadVisible(scroll.documentVisibleRect); scroller.refresh() }

    func reload() {
        let cells = stockVariants() + customVariants()
        let dir = wallpapersDir()

        // Re-entering the tab re-reads the shelves. When nothing changed,
        // leave the decoded thumbnails and palettes exactly as they are:
        // clearing them repaints a grid of "loading…" placeholders for a
        // frame, which reads as a flicker when the gallery is already at
        // the top and no scroll motion hides it.
        if cells == grid.cells, dir == grid.customDir {
            needsGridRebuild = true
            needsLayout = true
            return
        }

        // The set changed: keep what is still valid, keyed by wallpaper,
        // because an added or removed picture shifts every index.
        var decodedThumbs: [String: NSImage] = [:]
        var decodedPalettes: [String: [NSColor]] = [:]
        for (i, c) in grid.cells.enumerated() {
            if let t = grid.thumbs[i] { decodedThumbs[c.wallpaper] = t }
            if let p = grid.palettes[i] { decodedPalettes[c.wallpaper] = p }
        }

        grid.cells = cells
        grid.customDir = dir

        var thumbs: [Int: NSImage] = [:]
        var palettes: [Int: [NSColor]] = [:]
        for (i, c) in cells.enumerated() {
            if let t = decodedThumbs[c.wallpaper] { thumbs[i] = t }
            if let p = decodedPalettes[c.wallpaper] { palettes[i] = p }
        }
        grid.thumbs = thumbs
        grid.palettes = palettes
        grid.pending.removeAll()
        needsGridRebuild = true
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let scrollH = max(0, bounds.height - 18)
        scroll.frame = NSRect(x: 0, y: 18, width: max(0, bounds.width - scrollerW - 14), height: scrollH)
        scroller.frame = NSRect(x: bounds.width - scrollerW, y: 18, width: scrollerW, height: scrollH)
        scroller.refresh()
        let w = scroll.contentSize.width
        if w > 0 {
            if abs(grid.frame.width - w) > 0.5 {
                grid.frame.size.width = w
                needsGridRebuild = true
            }
            if needsGridRebuild {
                grid.rebuild()
                needsGridRebuild = false
                // open at the top (the non-flipped document's origin is the
                // bottom, which otherwise shows the custom section first)
                let top = max(0, grid.frame.height - scroll.contentSize.height)
                scroll.contentView.scroll(to: NSPoint(x: 0, y: top))
                scroll.reflectScrolledClipView(scroll.contentView)
                scroller.refresh()
            }
        }
        grid.loadVisible(scroll.documentVisibleRect)
    }

    override func draw(_ dirtyRect: NSRect) {
        if !status.isEmpty {
            drawTopLeft(status, nerdFont("Regular", 11), palette.muted,
                        x: 0, top: bounds.height - 14, height: bounds.height)
        }
    }
}

// --- theme editor ----------------------------------------------------------

// The editor opens on one of two things: a stored edition (its record is
// loaded from the library) or a new draft seeded from a raw wallpaper's
// Magic palette. 5a-2 builds the shell and the door; the Palette Builder,
// the previews and the Wallpaper Editor arrive in later sessions.
enum EditorSubject {
    case edition(ThemeEdition)
    case draft(wallpaper: String)

    var displayName: String {
        switch self {
        case .edition(let e): return e.name
        case .draft(let w): return prettyWallName((w as NSString).lastPathComponent)
        }
    }
}

final class EditorWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

// One column of the editor card. The shell draws the header and leaves the
// body to the panel that will own it.
final class EditorColumnView: NSView {
    var title = "" { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        drawMidLeft(title, nerdFont("Bold", 13), palette.accent,
                    x: 16, midTop: 18, height: bounds.height)
    }
}

// --- palette builder --------------------------------------------------------

// The engine's binary. OMACOSY_THEMECORE_BIN is the test seam: a /tmp build
// drives the editor without touching ~/.local/bin.
func themecoreBin() -> String {
    if let env = ProcessInfo.processInfo.environment["OMACOSY_THEMECORE_BIN"], !env.isEmpty {
        return env
    }
    return HOME + "/.local/bin/omacosy-themecore"
}

func nsColor(fromHex hex: String) -> NSColor {
    let clean = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
    guard clean.count == 6, let v = UInt64(clean, radix: 16) else { return .black }
    return color(fromARGB: 0xff000000 | v)
}

func hexString(from color: NSColor) -> String? {
    guard let c = color.usingColorSpace(.sRGB) else { return nil }
    let r = max(0, min(255, Int((c.redComponent * 255).rounded())))
    let g = max(0, min(255, Int((c.greenComponent * 255).rounded())))
    let b = max(0, min(255, Int((c.blueComponent * 255).rounded())))
    return String(format: "#%02x%02x%02x", r, g, b)
}

// A user-typed colour, normalised to "#rrggbb"; nil when it is not one.
func cleanHex(_ raw: String) -> String? {
    var s = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if !s.hasPrefix("#") { s = "#" + s }
    guard s.count == 7, s.dropFirst().allSatisfy({ $0.isHexDigit }) else { return nil }
    return s
}

// The tone curve's 256-entry LUT, for drawing the curve graph instantly.
// This is a copy of themecore's ToneCurve.lut (Aether's buildCurveLUT); the
// harness extracts this marked block and diffs it against the engine's
// `curve lut` output, so the two cannot drift. Keep the markers intact.
// MARK: tone-curve-lut-begin
func dashboardToneCurveLUT(_ points: [[Double]]) -> [UInt8]? {
    guard !points.isEmpty else { return nil }

    var tagged: [(i: Int, x: Double, y: Double)] = [(0, 0, 0)]
    for (i, p) in points.enumerated() where p.count == 2 {
        tagged.append((i + 1, p[0], p[1]))
    }
    tagged.append((points.count + 1, 1, 1))
    tagged.sort { $0.x == $1.x ? $0.i < $1.i : $0.x < $1.x }
    let pts = tagged.map { (x: $0.x, y: $0.y) }
    let n = pts.count

    var m: [Double] = []
    for i in 0..<(n - 1) {
        let dx = pts[i + 1].x - pts[i].x
        let dy = pts[i + 1].y - pts[i].y
        m.append(dx == 0 ? 0 : dy / dx)
    }

    var tangents = [Double](repeating: 0, count: n)
    tangents[0] = m[0]
    tangents[n - 1] = m[n - 2]
    for i in 1..<(n - 1) {
        if m[i - 1] * m[i] <= 0 {
            tangents[i] = 0
        } else {
            tangents[i] = (m[i - 1] + m[i]) / 2
        }
    }
    for i in 0..<(n - 1) {
        if m[i] == 0 {
            tangents[i] = 0
            tangents[i + 1] = 0
        } else {
            let a = tangents[i] / m[i]
            let b = tangents[i + 1] / m[i]
            let s = a * a + b * b
            if s > 9 {
                let t = 3 / s.squareRoot()
                tangents[i] = t * a * m[i]
                tangents[i + 1] = t * b * m[i]
            }
        }
    }

    var lut = [UInt8](repeating: 0, count: 256)
    var seg = 0
    for i in 0..<256 {
        let x = Double(i) / 255
        while seg < n - 2 && x > pts[seg + 1].x { seg += 1 }
        let p0 = pts[seg], p1 = pts[seg + 1]
        let h = p1.x - p0.x
        if h == 0 {
            lut[i] = UInt8(max(0, min(255, (p0.y * 255).rounded())))
            continue
        }
        let t = (x - p0.x) / h
        let t2 = t * t, t3 = t2 * t
        let h00 = 2 * t3 - 3 * t2 + 1
        let h10 = t3 - 2 * t2 + t
        let h01 = -2 * t3 + 3 * t2
        let h11 = t3 - t2
        let val = h00 * p0.y + h10 * h * tangents[seg]
            + h01 * p1.y + h11 * h * tangents[seg + 1]
        lut[i] = UInt8(max(0, min(255, (val * 255).rounded())))
    }
    return lut
}
// MARK: tone-curve-lut-end

// The 12 adjustments and their UI ranges, mirroring themecore's
// Adjustments.limits (Aether's ADJUSTMENT_LIMITS). The editor keeps the
// values so it can drive its controls; the engine applies them.
struct EditorAdjustments {
    var vibrance = 0.0
    var saturation = 0.0
    var contrast = 0.0
    var brightness = 0.0
    var shadows = 0.0
    var highlights = 0.0
    var hueShift = 0.0
    var temperature = 0.0
    var tint = 0.0
    var blackPoint = 0.0
    var whitePoint = 0.0
    var gamma = 1.0

    struct Field {
        let key: String       // the record's spelling
        let cli: String       // themecore's flag
        let label: String
        var min = 0.0, max = 0.0, step = 0.0, def = 0.0
    }

    static let fields: [Field] = [
        Field(key: "vibrance", cli: "--vibrance", label: "Vibrance", min: -50, max: 50, step: 5, def: 0),
        Field(key: "saturation", cli: "--saturation", label: "Saturation", min: -100, max: 100, step: 5, def: 0),
        Field(key: "contrast", cli: "--contrast", label: "Contrast", min: -30, max: 30, step: 5, def: 0),
        Field(key: "brightness", cli: "--brightness", label: "Brightness", min: -30, max: 30, step: 5, def: 0),
        Field(key: "shadows", cli: "--shadows", label: "Shadows", min: -50, max: 50, step: 5, def: 0),
        Field(key: "highlights", cli: "--highlights", label: "Highlights", min: -50, max: 50, step: 5, def: 0),
        Field(key: "hueShift", cli: "--hue-shift", label: "Hue Shift", min: -180, max: 180, step: 10, def: 0),
        Field(key: "temperature", cli: "--temperature", label: "Temperature", min: -50, max: 50, step: 5, def: 0),
        Field(key: "tint", cli: "--tint", label: "Tint", min: -50, max: 50, step: 5, def: 0),
        Field(key: "blackPoint", cli: "--black-point", label: "Black Point", min: -30, max: 30, step: 5, def: 0),
        Field(key: "whitePoint", cli: "--white-point", label: "White Point", min: -30, max: 30, step: 5, def: 0),
        Field(key: "gamma", cli: "--gamma", label: "Gamma", min: 0.5, max: 2.0, step: 0.1, def: 1.0),
    ]

    subscript(key: String) -> Double {
        get {
            switch key {
            case "vibrance": return vibrance
            case "saturation": return saturation
            case "contrast": return contrast
            case "brightness": return brightness
            case "shadows": return shadows
            case "highlights": return highlights
            case "hueShift": return hueShift
            case "temperature": return temperature
            case "tint": return tint
            case "blackPoint": return blackPoint
            case "whitePoint": return whitePoint
            case "gamma": return gamma
            default: return 0
            }
        }
        set {
            switch key {
            case "vibrance": vibrance = newValue
            case "saturation": saturation = newValue
            case "contrast": contrast = newValue
            case "brightness": brightness = newValue
            case "shadows": shadows = newValue
            case "highlights": highlights = newValue
            case "hueShift": hueShift = newValue
            case "temperature": temperature = newValue
            case "tint": tint = newValue
            case "blackPoint": blackPoint = newValue
            case "whitePoint": whitePoint = newValue
            case "gamma": gamma = newValue
            default: break
            }
        }
    }

    var isIdentity: Bool {
        EditorAdjustments.fields.allSatisfy { abs(self[$0.key] - $0.def) < 1e-9 }
    }

    // The flags `palette render` takes.
    var cliFlags: String {
        EditorAdjustments.fields.map { f in
            let v = self[f.key]
            let text = f.step < 1 ? String(format: "%.1f", v) : String(format: "%.0f", v)
            return "\(f.cli) \(text)"
        }.joined(separator: " ")
    }

    // the record's spelling of every value
    var values: [String: Double] {
        var out: [String: Double] = [:]
        for f in Self.fields { out[f.key] = self[f.key] }
        return out
    }

    static func format(_ v: Double, _ step: Double) -> String {
        step < 1 ? String(format: "%.1f", v) : String(format: "%.0f", v)
    }
}

// The editor's shared state. Both columns read it; its setters run the
// engine calls. It mirrors Aether's theme store — a base palette, the four
// extended colours, the 12 adjustments, the tone curve, locks and the
// multi-selection — and owns every themecore invocation. Nothing here
// touches the desktop.
final class PaletteModel {
    var onUpdate: (() -> Void)?
    var onUserEdit: (() -> Void)?

    private(set) var baseColors: [String] = []
    private(set) var extendedHex: [String: String] = [:]
    private(set) var adjustments = EditorAdjustments()
    private(set) var curve: [[Double]] = []
    private(set) var locked = Set<Int>()
    private(set) var selected = Set<Int>()
    private(set) var finalColors: [String] = []
    private(set) var finalExtended: [String: String] = [:]
    private(set) var method = "magic"
    private(set) var mode = "auto"
    private(set) var resolvedMode = "dark"
    private(set) var strips: [String: [String]] = [:]
    private(set) var histogram: [Int] = []
    private(set) var shades: [String: String] = [:]
    private(set) var recentColors: [String] = []
    private(set) var imagePath = ""

    enum EditTarget: Equatable {
        case color(Int)
        case extended(String)
    }
    private(set) var editTarget: EditTarget?

    static let extendedKeys: [(key: String, label: String)] = [
        ("accent", "Accent"),
        ("cursor", "Cursor"),
        ("selection_foreground", "Selection Text"),
        ("selection_background", "Selection"),
    ]
    static let ansiLabels = ["BG", "RD", "GR", "YL", "BL", "MG", "CY", "FG",
                             "DIM", "RD+", "GR+", "YL+", "BL+", "MG+", "CY+", "FG+"]

    private(set) var modeGroups: [(label: String, modes: [(value: String, label: String)])] = []
    private var paletteGeneration = 0
    private var renderGeneration = 0
    private var renderWork: DispatchWorkItem?
    private var recentWork: DispatchWorkItem?
    private var stripGeneration = 0

    init() {
        loadModes()
    }

    // --- seeding ------------------------------------------------------------

    func seedDraft(image: String, colors: [String], accent: String?, resolved: String) {
        imagePath = image
        method = "magic"
        mode = "auto"
        resolvedMode = resolved == "light" ? "light" : "dark"
        baseColors = colors
        extendedHex = defaultExtended(colors, accent: accent)
        adjustments = EditorAdjustments()
        curve = []
        locked.removeAll()
        selected.removeAll()
        editTarget = nil
        finalColors = colors
        finalExtended = extendedHex
        strips.removeAll()
        strips["magic"] = colors
        histogram = []
        update()
        refreshRender()
        loadHistogram()
        loadStrips()
    }

    func seedEdition(record: [String: Any], image: String) {
        imagePath = image
        let pal = record["palette"] as? [String: Any] ?? [:]
        baseColors = (pal["colors"] as? [String]) ?? []
        extendedHex = defaultExtended(baseColors, accent: nil)
        if let ext = pal["extended"] as? [String: Any] {
            for slot in Self.extendedKeys {
                if let v = ext[slot.key] as? String { extendedHex[slot.key] = v }
            }
        }
        method = (pal["method"] as? String) ?? "magic"
        mode = (pal["mode"] as? String) ?? "auto"
        resolvedMode = (pal["resolvedMode"] as? String) ?? "dark"
        adjustments = EditorAdjustments()
        if let adj = pal["adjustments"] as? [String: Any] {
            for f in EditorAdjustments.fields {
                if let n = adj[f.key] as? NSNumber { adjustments[f.key] = n.doubleValue }
            }
        }
        locked = Set((pal["locked"] as? [Int]) ?? [])
        curve = parseCurve(pal["curve"])
        selected.removeAll()
        editTarget = nil
        finalColors = baseColors
        finalExtended = extendedHex
        strips.removeAll()
        histogram = []
        update()
        refreshRender()
        loadHistogram()
        loadStrips()
    }

    // --- user actions -------------------------------------------------------

    func setBaseColor(_ index: Int, _ hex: String) {
        guard baseColors.indices.contains(index), baseColors[index] != hex else { return }
        baseColors[index] = hex
        edited()
        update()
        refreshRender()
    }

    func setExtended(_ key: String, _ hex: String) {
        guard extendedHex[key] != hex else { return }
        extendedHex[key] = hex
        edited()
        update()
        refreshRender()
    }

    func setAdjustment(_ key: String, _ value: Double) {
        guard abs(adjustments[key] - value) > 1e-9 else { return }
        adjustments[key] = value
        edited()
        update()
        refreshRender()
    }

    func resetAdjustments() {
        guard !adjustments.isIdentity || !curve.isEmpty else { return }
        adjustments = EditorAdjustments()
        curve = []
        edited()
        update()
        refreshRender()
    }

    func setCurve(_ points: [[Double]]) {
        guard points != curve else { return }
        curve = points
        edited()
        update()
        refreshRender()
    }

    func resetCurve() {
        guard !curve.isEmpty else { return }
        curve = []
        edited()
        update()
        refreshRender()
    }

    func chooseMethod(_ value: String) {
        guard value != method else { return }
        method = value
        edited()
        update()
        regenerate(reset: value == "magic")
    }

    func setMode(_ index: Int) {
        let names = ["auto", "dark", "light"]
        let newMode = names[max(0, min(2, index))]
        guard newMode != mode else { return }
        mode = newMode
        edited()
        update()
        if newMode == "auto" {
            paletteGeneration += 1
            let gen = paletteGeneration
            let q = shellQuote(imagePath)
            DispatchQueue.global().async { [weak self] in
                guard let self else { return }
                let (code, out) = self.themecore("palette suggest-mode \(q)")
                let resolved = (code == 0
                    && out.trimmingCharacters(in: .whitespacesAndNewlines) == "light") ? "light" : "dark"
                DispatchQueue.main.async {
                    guard self.paletteGeneration == gen else { return }
                    self.resolvedMode = resolved
                    self.update()
                    if self.method != "magic" { self.regenerate(reset: false) }
                    else { self.refreshRender() }
                    self.loadStrips()
                }
            }
        } else {
            resolvedMode = newMode
            if method != "magic" { regenerate(reset: false) } else { refreshRender() }
            loadStrips()
        }
    }

    func toggleLock(_ index: Int) {
        let targets = selected.contains(index) ? selected : [index]
        let lockAll = !locked.contains(index)
        for t in targets {
            if lockAll { locked.insert(t) } else { locked.remove(t) }
        }
        edited()
        update()
    }

    func toggleSelect(_ index: Int) {
        if selected.contains(index) { selected.remove(index) } else { selected.insert(index) }
        update()
    }

    @discardableResult
    func clearSelection() -> Bool {
        guard !selected.isEmpty else { return false }
        selected.removeAll()
        update()
        return true
    }

    @discardableResult
    func clearEditTarget() -> Bool {
        guard editTarget != nil else { return false }
        editTarget = nil
        update()
        return true
    }

    func selectForEdit(_ target: EditTarget) {
        if case .color(let i) = target, locked.contains(i) { return }
        editTarget = target
        update()
    }

    func editTargetHex() -> String? {
        switch editTarget {
        case .color(let i): return baseColors.indices.contains(i) ? baseColors[i] : nil
        case .extended(let key): return extendedHex[key]
        case nil: return nil
        }
    }

    func editTargetTitle() -> String {
        switch editTarget {
        case .color(let i):
            guard Self.ansiLabels.indices.contains(i) else { return "Colour \(i)" }
            return "\(Self.ansiLabels[i]) (ANSI \(i))"
        case .extended(let key):
            return Self.extendedKeys.first { $0.key == key }?.label ?? key
        case nil:
            return "No colour selected"
        }
    }

    func writeEditTarget(_ hex: String) {
        switch editTarget {
        case .color(let i): setBaseColor(i, hex)
        case .extended(let key): setExtended(key, hex)
        case nil: break
        }
        scheduleRecent(hex)
    }

    // Recently touched colours, debounced so a drag records only the value
    // the user settles on.
    private func scheduleRecent(_ hex: String) {
        recentWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.recentColors.removeAll { $0 == hex }
            self.recentColors.insert(hex, at: 0)
            if self.recentColors.count > 6 { self.recentColors.removeLast(self.recentColors.count - 6) }
            self.update()
        }
        recentWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
    }

    func methodLabel(_ value: String) -> String {
        if value == "magic" { return "Magic" }
        for group in modeGroups {
            if let m = group.modes.first(where: { $0.value == value }) { return m.label }
        }
        return value
    }

    func teardown() {
        renderWork?.cancel()
        renderWork = nil
        stripGeneration += 1
        MethodPicker.dismiss()
    }

    // --- engine -------------------------------------------------------------

    private func update() { onUpdate?() }
    private func edited() { onUserEdit?() }

    private func defaultExtended(_ colors: [String], accent: String?) -> [String: String] {
        let c = colors.count == 16 ? colors : Array(repeating: "#000000", count: 16)
        return ["accent": accent ?? c[4], "cursor": c[7],
                "selection_foreground": c[0], "selection_background": c[7]]
    }

    private func parseCurve(_ raw: Any?) -> [[Double]] {
        guard let list = raw as? [Any] else { return [] }
        return list.compactMap { pair in
            guard let p = pair as? [Any], p.count == 2,
                  let x = (p[0] as? NSNumber)?.doubleValue,
                  let y = (p[1] as? NSNumber)?.doubleValue else { return nil }
            return [x, y]
        }
    }

    private func loadModes() {
        let (code, out) = themecore("modes --json")
        guard code == 0, let data = out.data(using: .utf8),
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let groups = obj["groups"] as? [[String: Any]] else { return }
        modeGroups = groups.map { g in
            let modes = (g["modes"] as? [[String: Any]] ?? []).compactMap {
                m -> (value: String, label: String)? in
                guard let v = m["value"] as? String else { return nil }
                return (v, (m["label"] as? String) ?? v)
            }
            return ((g["label"] as? String) ?? "", modes)
        }
    }

    @discardableResult
    private func themecore(_ args: String) -> (Int32, String) {
        shell("\(shellQuote(themecoreBin())) \(args) 2>/dev/null")
    }

    // Re-derives the base palette from the image. Locked colours keep their
    // old value; choosing Magic resets the adjustments too (the plan's
    // reset action).
    private func regenerate(reset: Bool) {
        guard !imagePath.isEmpty, baseColors.count == 16 else { return }
        paletteGeneration += 1
        let gen = paletteGeneration
        let q = shellQuote(imagePath)
        let m = method
        let light = resolvedMode == "light"
        let lockedNow = locked
        let previous = baseColors
        DispatchQueue.global().async { [weak self] in
            guard let self else { return }
            let cmd = m == "magic"
                ? "palette magic \(q) --json"
                : "palette extract \(q) --mode \(m)\(light ? " --light" : "") --json"
            let (code, out) = self.themecore(cmd)
            var colors: [String] = []
            if code == 0, let data = out.data(using: .utf8),
               let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
                colors = obj["colors"] as? [String] ?? []
            }
            guard colors.count == 16 else { return }
            DispatchQueue.main.async {
                guard self.paletteGeneration == gen else { return }
                var next = colors
                for i in lockedNow where i < 16 { next[i] = previous[i] }
                self.baseColors = next
                if reset { self.adjustments = EditorAdjustments() }
                self.update()
                self.refreshRender()
            }
        }
    }

    // One render per 75 ms while the user drags: the first change schedules
    // the call, later changes ride along instead of restarting it.
    private func refreshRender() {
        guard baseColors.count == 16 else { return }
        guard renderWork == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            self?.renderWork = nil
            self?.performRender()
        }
        renderWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.075, execute: work)
    }

    private func performRender() {
        guard baseColors.count == 16 else { return }
        renderGeneration += 1
        let gen = renderGeneration
        var args = "palette render --colors \(shellQuote(baseColors.joined(separator: ",")))"
        for slot in Self.extendedKeys {
            let flag = slot.key.replacingOccurrences(of: "_", with: "-")
            args += " --\(flag) \(shellQuote(extendedHex[slot.key] ?? "#000000"))"
        }
        args += " \(adjustments.cliFlags)"
        if !curve.isEmpty {
            let text = curve.map { "\($0[0]),\($0[1])" }.joined(separator: ";")
            args += " --curve \(shellQuote(text))"
        }
        args += " --json"
        DispatchQueue.global().async { [weak self] in
            guard let self else { return }
            let (code, out) = self.themecore(args)
            guard code == 0, let data = out.data(using: .utf8),
                  let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let colors = obj["colors"] as? [String], colors.count == 16 else { return }
            let ext = obj["extended"] as? [String: String] ?? [:]
            DispatchQueue.main.async {
                guard self.renderGeneration == gen else { return }
                self.finalColors = colors
                if !ext.isEmpty { self.finalExtended = ext }
                self.update()
                self.loadShades(colors)
            }
        }
    }

    // Aether's derived shade ramps, for the semantic colour groups. Follows
    // the rendered palette, so the shades move with the adjustments.
    private func loadShades(_ colors: [String]) {
        let csv = colors.joined(separator: ",")
        DispatchQueue.global().async { [weak self] in
            guard let self else { return }
            let (code, out) = self.themecore("palette shades --colors \(shellQuote(csv)) --json")
            guard code == 0, let data = out.data(using: .utf8),
                  let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: String]
            else { return }
            DispatchQueue.main.async {
                self.shades = obj
                self.update()
            }
        }
    }

    private func loadHistogram() {
        guard !imagePath.isEmpty else { return }
        let q = shellQuote(imagePath)
        DispatchQueue.global().async { [weak self] in
            guard let self else { return }
            let (code, out) = self.themecore("image histogram \(q) --json")
            guard code == 0, let data = out.data(using: .utf8),
                  let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let bins = obj["bins"] as? [Int], bins.count == 256 else { return }
            DispatchQueue.main.async {
                self.histogram = bins
                self.update()
            }
        }
    }

    // The mini palette strips the Method picker shows. The Magic strip is
    // the seed itself and appears at once; the 24 mode strips run in small
    // parallel batches shortly after the first paint, so the picker is
    // populated by the time it is opened.
    private func loadStrips() {
        guard !imagePath.isEmpty else { return }
        stripGeneration += 1
        let gen = stripGeneration
        let values = modeGroups.flatMap { $0.modes.map { $0.value } }
        let q = shellQuote(imagePath)
        let light = resolvedMode == "light"
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self else { return }
            let batchSize = 6
            var start = 0
            while start < values.count {
                guard self.stripGeneration == gen else { return }
                let batch = Array(values[start..<min(start + batchSize, values.count)])
                let group = DispatchGroup()
                let lock = NSLock()
                var done: [(String, [String])] = []
                for value in batch {
                    group.enter()
                    DispatchQueue.global().async {
                        defer { group.leave() }
                        let cmd = "palette extract \(q) --mode \(value)\(light ? " --light" : "") --json"
                        let (code, out) = self.themecore(cmd)
                        guard code == 0, let data = out.data(using: .utf8),
                              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                              let colors = obj["colors"] as? [String], colors.count == 16
                        else { return }
                        lock.lock()
                        done.append((value, colors))
                        lock.unlock()
                    }
                }
                group.wait()
                guard self.stripGeneration == gen else { return }
                DispatchQueue.main.async {
                    guard self.stripGeneration == gen else { return }
                    for (value, colors) in done { self.strips[value] = colors }
                    if !done.isEmpty { self.update() }
                }
                start += batchSize
            }
        }
    }
}

// A flat "popup button": the current choice and a chevron; the menu itself
// is the MethodPicker card window.
final class PopupButtonView: NSView {
    var title = "" { didSet { needsDisplay = true } }
    var onClick: (() -> Void)?

    override func draw(_ dirtyRect: NSRect) {
        let r = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6)
        palette.itemBG.withAlphaComponent(0.35).setFill()
        r.fill()
        palette.muted.withAlphaComponent(0.35).setStroke()
        r.lineWidth = 1
        r.stroke()
        drawMidLeft(truncate(title, nerdFont("Regular", 12), bounds.width - 40),
                    nerdFont("Regular", 12), palette.label,
                    x: 10, midTop: bounds.height / 2, height: bounds.height)
        drawMidCenter("\u{f078}", nerdFont("Regular", 9), palette.muted,
                      centerX: bounds.width - 15, midTop: bounds.height / 2, height: bounds.height)
    }

    override func mouseDown(with event: NSEvent) { onClick?() }
    override var acceptsFirstResponder: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

// --- method picker ----------------------------------------------------------

// The dark Method dropdown, in the same visual language as the Workspaces
// "Add App" picker: a borderless card child window with a scrollable list,
// Esc/outside-click to close, and a compact 16-square strip on each mode row
// showing that mode's palette for the current image.
final class MethodPicker: NSObject {
    private static var active: MethodPicker?

    struct Row {
        let header: String?   // a group label row when set
        let value: String?    // a selectable mode when set
        let label: String
    }

    private let window: PickerWindow
    private let root = MethodPickerRoot()
    private var rows: [Row]
    private var selected = 0
    private var completion: ((String) -> Void)?
    private var monitors: [Any] = []
    private let W: CGFloat = 340
    private let H: CGFloat = 430

    private init(rows: [Row], strips: [String: [String]], currentMethod: String,
                 completion: @escaping (String) -> Void) {
        self.rows = rows
        self.completion = completion
        window = PickerWindow(contentRect: NSRect(x: 0, y: 0, width: W, height: H),
                              styleMask: .borderless, backing: .buffered, defer: false)
        super.init()
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.level = .popUpMenu
        window.appearance = NSAppearance(named: .darkAqua)
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.contentView = root
        root.rows = rows
        root.strips = strips
        root.onPick = { [weak self] value in self?.pick(value) }
        selected = rows.firstIndex { $0.value == currentMethod }
            ?? rows.firstIndex { $0.value != nil } ?? 0
        root.selected = selected
    }

    static func present(from view: NSView, rows: [Row], strips: [String: [String]],
                        currentMethod: String, completion: @escaping (String) -> Void) {
        active?.close()
        let p = MethodPicker(rows: rows, strips: strips, currentMethod: currentMethod,
                             completion: completion)
        guard let host = view.window else { return }
        let btn = host.convertToScreen(view.convert(view.bounds, to: nil))
        var x = btn.minX
        var y = btn.minY - p.H - 6
        if y < 40 { y = btn.maxY + 6 }
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(btn.origin) }) ?? NSScreen.main {
            x = min(max(screen.frame.minX + 8, x), screen.frame.maxX - p.W - 8)
        }
        p.window.setFrame(NSRect(x: x, y: y, width: p.W, height: p.H), display: true)
        active = p
        // a child window: it stays above the modal and is ordered out with it
        host.addChildWindow(p.window, ordered: .above)
        p.show()
    }

    static func dismiss() { active?.close() }

    private func show() {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        root.needsLayout = true
        root.layoutSubtreeIfNeeded()
        root.relayout()
        root.scrollToSelected()
        let km = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] e in
            guard let self else { return e }
            if e.keyCode == 53 { self.close(); return nil }
            if e.window === self.window {
                if e.keyCode == 126 { self.move(-1); return nil }  // up
                if e.keyCode == 125 { self.move(1); return nil }   // down
                if e.keyCode == 36 || e.keyCode == 76 { self.pickSelected(); return nil }
            }
            return e
        }
        let lm = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] e in
            if e.window !== self?.window { self?.close() }
            return e
        }
        let gm = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.close()
        }
        monitors = [km, lm, gm].compactMap { $0 }
    }

    private func move(_ delta: Int) {
        var i = selected
        repeat { i += delta } while rows.indices.contains(i) && rows[i].value == nil
        guard rows.indices.contains(i), rows[i].value != nil else { return }
        selected = i
        root.selected = i
        root.needsDisplay = true
        root.scrollToSelected()
    }

    private func pickSelected() {
        guard rows.indices.contains(selected), let v = rows[selected].value else { return }
        pick(v)
    }

    private func pick(_ value: String) {
        completion?(value)
        close()
    }

    private func close() {
        for m in monitors { NSEvent.removeMonitor(m) }
        monitors.removeAll()
        window.parent?.removeChildWindow(window)
        window.orderOut(nil)
        if MethodPicker.active === self { MethodPicker.active = nil }
    }
}

final class MethodPickerRoot: NSView {
    let scroll = NSScrollView()
    let list = MethodPickerList()
    var rows: [MethodPicker.Row] = []
    var strips: [String: [String]] = [:]
    var selected = 0
    var onPick: ((String) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(scroll)
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.documentView = list
    }
    required init?(coder: NSCoder) { fatalError("not used") }

    override func draw(_ dirtyRect: NSRect) {
        let r = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 10, yRadius: 10)
        palette.barBG.setFill()
        r.fill()
        palette.accent.setStroke()
        r.lineWidth = 1
        r.stroke()
        drawTopLeft("Method", nerdFont("Bold", 12), palette.accent,
                    x: 12, top: 9, height: bounds.height)
    }

    override func layout() {
        super.layout()
        relayout()
    }

    func relayout() {
        let pad: CGFloat = 10
        let headerH: CGFloat = 32
        scroll.frame = NSRect(x: pad, y: pad, width: max(0, bounds.width - pad * 2),
                              height: max(0, bounds.height - pad * 2 - headerH))
        list.rows = rows
        list.strips = strips
        list.selected = selected
        list.onPick = onPick
        let w = max(scroll.contentSize.width, 10)
        list.frame = NSRect(x: 0, y: 0, width: w,
                            height: max(scroll.contentSize.height, MethodPickerList.height(for: rows)))
    }

    func scrollToSelected() { list.scrollRowIntoView(selected, in: scroll) }
}

final class MethodPickerList: NSView {
    var rows: [MethodPicker.Row] = [] { didSet { needsDisplay = true } }
    var strips: [String: [String]] = [:] { didSet { needsDisplay = true } }
    var selected = 0 { didSet { needsDisplay = true } }
    var onPick: ((String) -> Void)?
    private static let rowH: CGFloat = 30
    private static let headerH: CGFloat = 26

    static func height(for rows: [MethodPicker.Row]) -> CGFloat {
        rows.reduce(0) { $0 + ($1.value == nil ? headerH : rowH) }
    }

    private func rowTops() -> [CGFloat] {
        var tops: [CGFloat] = []
        var y: CGFloat = 0
        for row in rows {
            tops.append(y)
            y += row.value == nil ? Self.headerH : Self.rowH
        }
        return tops
    }

    private func rowRect(_ i: Int, tops: [CGFloat]) -> NSRect {
        let h = rows[i].value == nil ? Self.headerH : Self.rowH
        return NSRect(x: 0, y: bounds.height - tops[i] - h, width: bounds.width, height: h)
    }

    override func draw(_ dirtyRect: NSRect) {
        let tops = rowTops()
        for (i, row) in rows.enumerated() {
            let r = rowRect(i, tops: tops)
            if row.value == nil {
                drawMidLeft(row.header ?? "", nerdFont("Bold", 10), palette.muted,
                            x: 10, midTop: tops[i] + Self.headerH / 2, height: bounds.height)
                continue
            }
            if i == selected {
                palette.accent.withAlphaComponent(0.85).setFill()
                r.fill()
            }
            let ink = i == selected ? palette.barBG : palette.label
            drawMidLeft(truncate(row.label, nerdFont("Regular", 12), bounds.width - 170),
                        nerdFont("Regular", 12), ink,
                        x: 10, midTop: tops[i] + Self.rowH / 2, height: bounds.height)
            if let strip = strips[row.value ?? ""] {
                drawStrip(strip, in: r, selected: i == selected)
            } else {
                drawStripPlaceholder(in: r, selected: i == selected)
            }
            if i == selected {
                drawMidLeft("\u{f00c}", nerdFont("Regular", 10), palette.barBG,
                            x: bounds.width - 16, midTop: tops[i] + Self.rowH / 2, height: bounds.height)
            }
        }
    }

    // 16 tiny bars, the mode's palette left to right; slim, line-like.
    private func drawStrip(_ colors: [String], in row: NSRect, selected: Bool) {
        let sqW: CGFloat = 7, sqH: CGFloat = 5, gap: CGFloat = 1
        let total = CGFloat(colors.count) * sqW + CGFloat(max(0, colors.count - 1)) * gap
        var x = row.maxX - 30 - total
        let y = row.midY - sqH / 2
        for hex in colors {
            let cell = NSRect(x: x, y: y, width: sqW, height: sqH)
            let path = NSBezierPath(roundedRect: cell, xRadius: 1, yRadius: 1)
            nsColor(fromHex: hex).setFill()
            path.fill()
            palette.barBG.withAlphaComponent(selected ? 0.25 : 0.4).setStroke()
            path.lineWidth = 0.5
            path.stroke()
            x += sqW + gap
        }
    }

    private func drawStripPlaceholder(in row: NSRect, selected: Bool) {
        let sqW: CGFloat = 7, sqH: CGFloat = 5, gap: CGFloat = 1
        var x = row.maxX - 30 - (16 * sqW + 15 * gap)
        let y = row.midY - sqH / 2
        for _ in 0..<16 {
            palette.muted.withAlphaComponent(selected ? 0.35 : 0.18).setFill()
            NSBezierPath(roundedRect: NSRect(x: x, y: y, width: sqW, height: sqH),
                         xRadius: 1, yRadius: 1).fill()
            x += sqW + gap
        }
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let tops = rowTops()
        for i in rows.indices where rowRect(i, tops: tops).contains(p) {
            guard let value = rows[i].value else { return }
            selected = i
            needsDisplay = true
            onPick?(value)
            return
        }
    }

    func scrollRowIntoView(_ index: Int, in scroll: NSScrollView) {
        guard rows.indices.contains(index) else { return }
        let tops = rowTops()
        let r = rowRect(index, tops: tops)
        let clip = scroll.contentView.bounds
        var origin = clip.origin
        if r.minY < clip.minY { origin.y = r.minY }
        else if r.maxY > clip.maxY { origin.y = r.maxY - clip.height }
        let maxY = max(0, bounds.height - scroll.contentSize.height)
        origin.y = max(0, min(maxY, origin.y))
        scroll.contentView.scroll(to: origin)
        scroll.reflectScrolledClipView(scroll.contentView)
    }

    override var acceptsFirstResponder: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

// --- compact slider ---------------------------------------------------------

// One adjustment, Aether-style: label on the left, a thin track with a small
// square thumb in the middle, the value on the right. Drag sets the value
// (snapped to the range's step), double-click resets it, and the value can be
// typed.
final class AdjustmentSliderView: NSView, NSTextFieldDelegate {
    let field: EditorAdjustments.Field
    var value: Double = 0 { didSet { needsDisplay = true } }
    var onChange: ((Double) -> Void)?
    private let valueField = NSTextField()
    private var dragging = false

    static let rowHeight: CGFloat = 26

    init(field: EditorAdjustments.Field) {
        self.field = field
        super.init(frame: .zero)
        value = field.def
        valueField.isBezeled = false
        valueField.drawsBackground = false
        valueField.textColor = palette.label
        valueField.font = nerdFont("Regular", 11)
        valueField.alignment = .right
        valueField.focusRingType = .none
        valueField.delegate = self
        valueField.target = self
        valueField.action = #selector(fieldReturn)
        addSubview(valueField)
        syncField()
    }
    required init?(coder: NSCoder) { fatalError("not used") }

    func setValue(_ v: Double, notify: Bool) {
        value = v
        syncField()
        if notify { onChange?(v) }
    }

    func refreshColors() {
        valueField.textColor = palette.label
        needsDisplay = true
    }

    private func syncField() {
        guard valueField.currentEditor() == nil else { return }
        valueField.stringValue = EditorAdjustments.format(value, field.step)
    }

    private func snap(_ v: Double) -> Double {
        let steps = ((v - field.min) / field.step).rounded()
        return min(field.max, max(field.min, field.min + steps * field.step))
    }

    @objc private func fieldReturn() { commitField() }

    private func commitField() {
        guard let raw = Double(valueField.stringValue) else { syncField(); return }
        let v = snap(raw)
        if abs(v - value) > 1e-9 { setValue(v, notify: true) }
        syncField()
        needsDisplay = true
    }

    func controlTextDidEndEditing(_ obj: Notification) { commitField() }

    private var labelW: CGFloat { 88 }
    private var valueW: CGFloat { 34 }
    private var track: (CGFloat, CGFloat) { (labelW, max(labelW + 24, bounds.width - valueW - 4)) }

    override func layout() {
        super.layout()
        valueField.frame = NSRect(x: bounds.width - valueW,
                                  y: bounds.height / 2 - 8, width: valueW, height: 16)
    }

    private func updateValue(from p: NSPoint) {
        let (x0, x1) = track
        let t = min(1, max(0, (p.x - x0) / max(1, x1 - x0)))
        setValue(snap(field.min + Double(t) * (field.max - field.min)), notify: true)
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        guard p.x >= labelW - 4, p.x <= bounds.width, p.y >= 4, p.y <= bounds.height - 4 else { return }
        if event.clickCount == 2 {
            setValue(field.def, notify: true)
            return
        }
        dragging = true
        updateValue(from: p)
    }

    override func mouseDragged(with event: NSEvent) {
        guard dragging else { return }
        updateValue(from: convert(event.locationInWindow, from: nil))
    }

    override func mouseUp(with event: NSEvent) { dragging = false }

    override func draw(_ dirtyRect: NSRect) {
        let mid = bounds.height / 2
        drawMidLeft(field.label, nerdFont("Regular", 11), palette.label,
                    x: 0, midTop: mid, height: bounds.height)
        let (x0, x1) = track
        palette.muted.withAlphaComponent(0.35).setFill()
        NSRect(x: x0, y: mid - 1, width: x1 - x0, height: 2).fill()
        let t = (value - field.min) / max(1e-9, field.max - field.min)
        let cx = x0 + CGFloat(t) * (x1 - x0)
        let atDefault = abs(value - field.def) < 1e-9
        let thumb = NSBezierPath(roundedRect: NSRect(x: cx - 4.5, y: mid - 4.5, width: 9, height: 9),
                                 xRadius: 2, yRadius: 2)
        (atDefault ? palette.muted : palette.accent).setFill()
        thumb.fill()
    }

    override var acceptsFirstResponder: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

// --- tone curve editor ------------------------------------------------------

// The curve box, Aether-style: the image's luminance histogram as a backdrop,
// the curve sampled from the LUT, and draggable control points. The endpoints
// (0,0) and (1,1) are fixed; click empty space to add, drag to move,
// double-click a point to remove, Reset returns to identity.
final class CurveEditorView: NSView {
    var points: [[Double]] = [] { didSet { needsDisplay = true } }
    var histogram: [Int] = [] { didSet { needsDisplay = true } }
    var onChange: (([[Double]]) -> Void)?

    static let viewHeight: CGFloat = 116
    private var dragIndex: Int?
    private let inset: CGFloat = 10
    private let topPad: CGFloat = 12

    private var graph: NSRect {
        NSRect(x: inset, y: inset, width: max(1, bounds.width - inset * 2),
               height: max(1, bounds.height - topPad - inset))
    }

    private func pointXY(_ p: NSPoint) -> (Double, Double) {
        let g = graph
        let x = Double((p.x - g.minX) / max(1, g.width))
        let y = Double((p.y - g.minY) / max(1, g.height))
        return (min(1, max(0, x)), min(1, max(0, y)))
    }

    private func screenXY(_ x: Double, _ y: Double) -> NSPoint {
        let g = graph
        return NSPoint(x: g.minX + CGFloat(x) * g.width, y: g.minY + CGFloat(y) * g.height)
    }

    private func hitIndex(_ p: NSPoint) -> Int? {
        for (i, pt) in points.enumerated() {
            let s = screenXY(pt[0], pt[1])
            if hypot(s.x - p.x, s.y - p.y) <= 9 { return i }
        }
        return nil
    }

    override func draw(_ dirtyRect: NSRect) {
        let box = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6)
        palette.itemBG.withAlphaComponent(0.35).setFill()
        box.fill()
        palette.muted.withAlphaComponent(0.35).setStroke()
        box.lineWidth = 1
        box.stroke()

        let g = graph
        palette.muted.withAlphaComponent(0.12).setStroke()
        for i in 1..<4 {
            let x = g.minX + g.width * CGFloat(i) / 4
            let y = g.minY + g.height * CGFloat(i) / 4
            NSBezierPath.strokeLine(from: NSPoint(x: x, y: g.minY), to: NSPoint(x: x, y: g.maxY))
            NSBezierPath.strokeLine(from: NSPoint(x: g.minX, y: y), to: NSPoint(x: g.maxX, y: y))
        }

        if histogram.count == 256, let maxBins = histogram.max(), maxBins > 0 {
            let barW = g.width / 256
            palette.muted.withAlphaComponent(0.20).setFill()
            for (i, n) in histogram.enumerated() {
                let h = CGFloat(Double(n) / Double(maxBins)) * g.height
                NSRect(x: g.minX + CGFloat(i) * barW, y: g.minY, width: max(0.5, barW), height: h).fill()
            }
        }

        let lut = dashboardToneCurveLUT(points) ?? (0...255).map { UInt8($0) }
        let path = NSBezierPath()
        for i in 0..<256 {
            let p = screenXY(Double(i) / 255, Double(lut[i]) / 255)
            if i == 0 { path.move(to: p) } else { path.line(to: p) }
        }
        palette.accent.setStroke()
        path.lineWidth = 2
        path.stroke()

        // fixed endpoints, faint; interior points solid
        for (x, y) in [(0.0, 0.0), (1.0, 1.0)] {
            let s = screenXY(x, y)
            palette.label.withAlphaComponent(0.45).setFill()
            NSBezierPath(ovalIn: NSRect(x: s.x - 2, y: s.y - 2, width: 4, height: 4)).fill()
        }
        for pt in points {
            let s = screenXY(pt[0], pt[1])
            let dot = NSBezierPath(ovalIn: NSRect(x: s.x - 4, y: s.y - 4, width: 8, height: 8))
            palette.accent.setFill()
            dot.fill()
            palette.barBG.setStroke()
            dot.lineWidth = 1.5
            dot.stroke()
        }
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        guard graph.contains(p) else { return }
        if let i = hitIndex(p) {
            if event.clickCount == 2 {
                var next = points
                next.remove(at: i)
                onChange?(next)
                dragIndex = nil
            } else {
                dragIndex = i
            }
            return
        }
        let (x, y) = pointXY(p)
        let clampedX = min(0.99, max(0.01, x))
        var next = points
        let newIndex = next.firstIndex { $0[0] > clampedX } ?? next.count
        next.insert([clampedX, y], at: newIndex)
        dragIndex = newIndex
        onChange?(next)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let i = dragIndex, points.indices.contains(i) else { return }
        let p = convert(event.locationInWindow, from: nil)
        let (rawX, y) = pointXY(p)
        let lower = i > 0 ? points[i - 1][0] + 0.005 : 0.005
        let upper = i < points.count - 1 ? points[i + 1][0] - 0.005 : 0.995
        guard lower < upper else { return }
        var next = points
        next[i] = [min(upper, max(lower, rawX)), y]
        onChange?(next)
    }

    override func mouseUp(with event: NSEvent) { dragIndex = nil }

    override var acceptsFirstResponder: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

// --- palette cards ----------------------------------------------------------

// Aether's palette cards: role label and a contrast badge on top, the hex at
// the bottom, the colour filling the card. Used for the 16 ANSI colours and
// for the four extended colours.
final class PaletteCardsView: NSView {
    struct Card {
        let label: String
        let hex: String
        let index: Int          // 0...15 for an ANSI slot, -1 for extended
        let extendedKey: String?
    }

    var cards: [Card] = [] { didSet { needsDisplay = true } }
    var locked = Set<Int>() { didSet { needsDisplay = true } }
    var selected = Set<Int>() { didSet { needsDisplay = true } }
    var editTarget: PaletteModel.EditTarget? { didSet { needsDisplay = true } }
    var bgHex = "#000000"
    var showsLocks = true
    var onEdit: ((PaletteModel.EditTarget) -> Void)?
    var onToggleLock: ((Int) -> Void)?
    var onToggleSelect: ((Int) -> Void)?
    var onHover: (() -> Void)?

    static let columns = 8
    static let cardH: CGFloat = 50
    static let cardGap: CGFloat = 5

    static func height(for count: Int) -> CGFloat {
        let rows = max(1, (count + columns - 1) / columns)
        return CGFloat(rows) * cardH + CGFloat(rows - 1) * cardGap
    }

    private func rects() -> [NSRect] {
        guard bounds.width > 0 else { return [] }
        let w = ((bounds.width - CGFloat(Self.columns - 1) * Self.cardGap) / CGFloat(Self.columns))
        var out: [NSRect] = []
        let rowCount = (cards.count + Self.columns - 1) / Self.columns
        for row in 0..<max(1, rowCount) {
            for col in 0..<Self.columns {
                let i = row * Self.columns + col
                if i >= cards.count { break }
                let x = CGFloat(col) * (w + Self.cardGap)
                let top = CGFloat(row) * (Self.cardH + Self.cardGap)
                out.append(NSRect(x: x, y: bounds.height - top - Self.cardH, width: w, height: Self.cardH))
            }
        }
        return out
    }

    override func draw(_ dirtyRect: NSRect) {
        for (i, card) in cards.enumerated() {
            let all = rects()
            guard all.indices.contains(i) else { break }
            let r = all[i]
            let path = NSBezierPath(roundedRect: r.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6)
            nsColor(fromHex: card.hex).setFill()
            path.fill()

            let light = relativeLuminance(nsColor(fromHex: card.hex)) > 0.5
            let ink: NSColor = light ? .black : .white
            let inkMain = ink.withAlphaComponent(light ? 0.78 : 0.92)
            let inkFaint = ink.withAlphaComponent(light ? 0.55 : 0.68)

            drawMidLeft(card.label, nerdFont("Bold", 9), inkMain,
                        x: r.minX + 6, midTop: bounds.height - r.maxY + 10, height: bounds.height)
            drawMidLeft(card.hex, nerdFont("Regular", 8), inkFaint,
                        x: r.minX + 6, midTop: bounds.height - r.maxY + Self.cardH - 10,
                        height: bounds.height)

            if showsLocks, card.index >= 0 {
                let lockedNow = locked.contains(card.index)
                drawMidCenter("\u{f023}", nerdFont("Regular", 8),
                              lockedNow ? inkMain : ink.withAlphaComponent(0.22),
                              centerX: r.maxX - 11, midTop: bounds.height - r.maxY + 10,
                              height: bounds.height)
            }

            // contrast badge against the palette background, bottom-right
            // (the BG card compares with itself, so it carries none)
            if card.index > 0, r.width >= 60 {
                let ratio = contrastRatioHex(card.hex, bgHex)
                let level = ratio >= 7 ? "AAA" : (ratio >= 4.5 ? "AA" : (ratio >= 3 ? "AA-L" : "!"))
                drawMidCenter(level, nerdFont("Bold", 8), level == "!" ? ink : inkFaint,
                              centerX: r.maxX - 16, midTop: bounds.height - r.maxY + Self.cardH - 10,
                              height: bounds.height)
            }

            let isEditing: Bool
            switch editTarget {
            case .color(let idx): isEditing = card.index >= 0 && idx == card.index
            case .extended(let key): isEditing = card.extendedKey == key
            case nil: isEditing = false
            }
            if isEditing {
                palette.accent.setStroke()
                path.lineWidth = 2.5
                path.stroke()
            } else if card.index >= 0 && selected.contains(card.index) {
                palette.accent.withAlphaComponent(0.9).setStroke()
                path.lineWidth = 1.5
                path.stroke()
            }
        }
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let all = rects()
        for (i, card) in cards.enumerated() {
            guard all.indices.contains(i), all[i].contains(p) else { continue }
            let r = all[i]
            let lockZone = NSRect(x: r.maxX - 22, y: r.maxY - 18, width: 20, height: 18)
            if showsLocks, card.index >= 0, lockZone.contains(p) {
                onToggleLock?(card.index)
            } else if card.index >= 0, event.modifierFlags.contains(.shift) {
                onToggleSelect?(card.index)
            } else if let key = card.extendedKey {
                onEdit?(.extended(key))
            } else {
                onEdit?(.color(card.index))
            }
            return
        }
    }

    func flashHover() { onHover?() }

    override var acceptsFirstResponder: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

// WCAG contrast between two hex colours, for the card badges.
func contrastRatioHex(_ a: String, _ b: String) -> Double {
    let la = Double(relativeLuminance(nsColor(fromHex: a)))
    let lb = Double(relativeLuminance(nsColor(fromHex: b)))
    return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
}

// --- semantic colours -------------------------------------------------------

// Aether's semantic groups: the Background and Foreground shade ramps and the
// accent pair, all derived from the palette, plus the UI group — the four
// extended colours, which are editable.
final class SemanticSectionView: NSView {
    struct Card {
        let label: String
        let hex: String
        let key: String?   // non-nil: an editable extended colour
    }
    struct Group {
        let title: String
        let cards: [Card]
    }

    var groups: [Group] = [] { didSet { needsDisplay = true } }
    var editTarget: PaletteModel.EditTarget? { didSet { needsDisplay = true } }
    var onEdit: ((PaletteModel.EditTarget) -> Void)?

    static let groupH: CGFloat = 86
    static let rowGap: CGFloat = 8

    static func height() -> CGFloat { groupH * 2 + rowGap }

    private func boxes() -> [(group: Group, box: NSRect, cards: [NSRect])] {
        guard groups.count == 4, bounds.width > 0 else { return [] }
        let colGap: CGFloat = 8
        let colW = (bounds.width - colGap) / 2
        var out: [(Group, NSRect, [NSRect])] = []
        for (i, group) in groups.enumerated() {
            let col = i % 2, row = i / 2
            let x = CGFloat(col) * (colW + colGap)
            let top = CGFloat(row) * (Self.groupH + Self.rowGap)
            let box = NSRect(x: x, y: bounds.height - top - Self.groupH,
                             width: colW, height: Self.groupH)
            let padX: CGFloat = 10
            let n = max(1, group.cards.count)
            let gap: CGFloat = 5
            let cardW = (box.width - padX * 2 - CGFloat(n - 1) * gap) / CGFloat(n)
            var rects: [NSRect] = []
            for j in 0..<group.cards.count {
                let cx = box.minX + padX + CGFloat(j) * (cardW + gap)
                rects.append(NSRect(x: cx, y: box.minY + 22, width: cardW, height: 34))
            }
            out.append((group, box, rects))
        }
        return out
    }

    override func draw(_ dirtyRect: NSRect) {
        for (group, box, rects) in boxes() {
            let boxPath = NSBezierPath(roundedRect: box.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6)
            palette.itemBG.withAlphaComponent(0.22).setFill()
            boxPath.fill()
            palette.muted.withAlphaComponent(0.15).setStroke()
            boxPath.lineWidth = 1
            boxPath.stroke()
            drawTopLeft(group.title.uppercased(), nerdFont("Bold", 9), palette.muted,
                        x: box.minX + 10, top: bounds.height - box.maxY + 8, height: bounds.height)
            for (j, card) in group.cards.enumerated() {
                let r = rects[j]
                let path = NSBezierPath(roundedRect: r, xRadius: 4, yRadius: 4)
                nsColor(fromHex: card.hex).setFill()
                path.fill()
                let light = relativeLuminance(nsColor(fromHex: card.hex)) > 0.5
                let main: NSColor = light ? .black : .white
                drawMidLeft(card.hex, nerdFont("Regular", 8), main.withAlphaComponent(0.62),
                            x: r.minX + 5, midTop: bounds.height - r.maxY + r.height - 9,
                            height: bounds.height)
                drawMidCenter(card.label, nerdFont("Regular", 9), palette.label.withAlphaComponent(0.72),
                              centerX: r.midX, midTop: bounds.height - r.minY + 7,
                              height: bounds.height)
                if let key = card.key {
                    var isEditing = false
                    if case .extended(let k) = editTarget, k == key { isEditing = true }
                    if isEditing {
                        palette.accent.setStroke()
                        path.lineWidth = 2
                        path.stroke()
                    }
                }
            }
        }
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        for (group, _, rects) in boxes() {
            for (j, card) in group.cards.enumerated() where card.key != nil {
                if rects[j].contains(p) {
                    onEdit?(.extended(card.key!))
                    return
                }
            }
        }
    }

    override var acceptsFirstResponder: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

// --- colour inspector -------------------------------------------------------

// HSL helpers for the inspector's channels, harmony and tones. Same formulas
// as Aether's color.ts: h in degrees, s and l in percent.
func hslComponents(_ hex: String) -> (h: Double, s: Double, l: Double) {
    let clean = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
    guard clean.count == 6, let v = UInt64(clean, radix: 16) else { return (0, 0, 0) }
    let r = Double((v >> 16) & 0xff) / 255
    let g = Double((v >> 8) & 0xff) / 255
    let b = Double(v & 0xff) / 255
    let maxV = max(r, max(g, b)), minV = min(r, min(g, b))
    let l = (maxV + minV) / 2
    var h = 0.0, s = 0.0
    if maxV != minV {
        let d = maxV - minV
        s = l > 0.5 ? d / (2 - maxV - minV) : d / (maxV + minV)
        if maxV == r { h = ((g - b) / d + (g < b ? 6 : 0)) / 6 }
        else if maxV == g { h = ((b - r) / d + 2) / 6 }
        else { h = ((r - g) / d + 4) / 6 }
    }
    return (h * 360, s * 100, l * 100)
}

func hslHex(_ h: Double, _ s: Double, _ l: Double) -> String {
    let hn = ((h.truncatingRemainder(dividingBy: 360)) + 360).truncatingRemainder(dividingBy: 360) / 360
    let sn = min(100, max(0, s)) / 100
    let ln = min(100, max(0, l)) / 100
    if sn == 0 {
        let v = Int((ln * 255).rounded())
        return String(format: "#%02x%02x%02x", v, v, v)
    }
    let q = ln < 0.5 ? ln * (1 + sn) : ln + sn - ln * sn
    let p = 2 * ln - q
    func hue(_ t0: Double) -> Double {
        var t = t0
        if t < 0 { t += 1 }
        if t > 1 { t -= 1 }
        if t < 1.0 / 6.0 { return p + (q - p) * 6 * t }
        if t < 1.0 / 2.0 { return q }
        if t < 2.0 / 3.0 { return p + (q - p) * (2.0 / 3.0 - t) * 6 }
        return p
    }
    let r = Int((hue(hn + 1.0 / 3.0) * 255).rounded())
    let g = Int((hue(hn) * 255).rounded())
    let b = Int((hue(hn - 1.0 / 3.0) * 255).rounded())
    return String(format: "#%02x%02x%02x", min(255, max(0, r)), min(255, max(0, g)), min(255, max(0, b)))
}

// One channel row, Aether's channel style: a gradient track with a white
// handle and a typed value on the right.
final class ChannelSliderView: NSView, NSTextFieldDelegate {
    var label = ""
    var suffix = ""
    var minValue = 0.0
    var maxValue = 255.0
    var value = 0.0 { didSet { needsDisplay = true; syncField() } }
    var gradient: [NSColor]?
    var onChange: ((Double) -> Void)?
    private let valueField = NSTextField()
    private var dragging = false

    static let rowHeight: CGFloat = 24

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        valueField.isBezeled = false
        valueField.drawsBackground = false
        valueField.textColor = palette.label
        valueField.font = nerdFont("Regular", 11)
        valueField.alignment = .right
        valueField.focusRingType = .none
        valueField.delegate = self
        valueField.target = self
        valueField.action = #selector(fieldReturn)
        addSubview(valueField)
    }
    required init?(coder: NSCoder) { fatalError("not used") }

    func setValue(_ v: Double, notify: Bool) {
        value = v
        syncField()
        if notify { onChange?(v) }
    }

    func refreshColors() {
        valueField.textColor = palette.label
        needsDisplay = true
    }

    private func syncField() {
        guard valueField.currentEditor() == nil else { return }
        valueField.stringValue = "\(Int(value.rounded()))\(suffix)"
    }

    @objc private func fieldReturn() { commitField() }
    func controlTextDidEndEditing(_ obj: Notification) { commitField() }

    private func commitField() {
        let raw = valueField.stringValue
            .replacingOccurrences(of: "°", with: "")
            .replacingOccurrences(of: "%", with: "")
            .trimmingCharacters(in: .whitespaces)
        guard let n = Double(raw) else { syncField(); return }
        let v = min(maxValue, max(minValue, n))
        if abs(v - value) > 1e-9 { setValue(v, notify: true) }
        syncField()
    }

    private var trackRect: NSRect {
        NSRect(x: 18, y: bounds.height / 2 - 4, width: max(10, bounds.width - 18 - 48), height: 8)
    }

    private func update(from p: NSPoint) {
        let t = min(1, max(0, (p.x - trackRect.minX) / max(1, trackRect.width)))
        setValue(minValue + Double(t) * (maxValue - minValue), notify: true)
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        guard p.x >= 10, p.x <= bounds.width - 40 else { return }
        dragging = true
        update(from: p)
    }
    override func mouseDragged(with event: NSEvent) {
        guard dragging else { return }
        update(from: convert(event.locationInWindow, from: nil))
    }
    override func mouseUp(with event: NSEvent) { dragging = false }

    override func draw(_ dirtyRect: NSRect) {
        let mid = bounds.height / 2
        drawMidLeft(label, nerdFont("Regular", 10), palette.muted,
                    x: 0, midTop: mid, height: bounds.height)
        let track = NSBezierPath(roundedRect: trackRect, xRadius: 2, yRadius: 2)
        if let colors = gradient, colors.count >= 2 {
            NSGradient(colors: colors)?.draw(in: track, angle: 0)
        } else {
            palette.itemBG.withAlphaComponent(0.6).setFill()
            track.fill()
        }
        palette.muted.withAlphaComponent(0.3).setStroke()
        track.lineWidth = 0.5
        track.stroke()
        let t = (value - minValue) / max(1e-9, maxValue - minValue)
        let cx = trackRect.minX + CGFloat(t) * trackRect.width
        let handle = NSBezierPath(roundedRect: NSRect(x: cx - 2, y: mid - 7, width: 4, height: 14),
                                  xRadius: 1.5, yRadius: 1.5)
        NSColor.white.setFill()
        handle.fill()
        NSColor.black.withAlphaComponent(0.6).setStroke()
        handle.lineWidth = 1
        handle.stroke()
    }

    override func layout() {
        super.layout()
        valueField.frame = NSRect(x: bounds.width - 44, y: bounds.height / 2 - 8, width: 44, height: 16)
    }
    override var acceptsFirstResponder: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

// The full colour inspector for the selected swatch: name and hex, contrast
// against the palette's background and foreground, the RGB/HSL channels with
// gradient tracks, harmony swatches, the 11-step tone row and the session's
// recent colours. Harmony, tones and recents apply the colour they show.
final class ColorInspectorView: NSView, NSTextFieldDelegate {
    var onColor: ((String) -> Void)?

    private let hexField = NSTextField()
    private let tabs = SegmentedView()
    private var rgbSliders: [ChannelSliderView] = []
    private var hslSliders: [ChannelSliderView] = []

    private(set) var hex = "#000000"
    private var title = "No colour selected"
    private var bgHex = "#000000"
    private var fgHex = "#ffffff"
    private var recents: [String] = []
    private var active = false
    private var syncing = false
    private var tab = 0   // 0 RGB, 1 HSL

    private var harmony: [(label: String, hex: String)] = []
    private var tones: [String] = []
    private var currentTone = -1

    static let viewHeight: CGFloat = 292
    static let harmonySpec: [(label: String, delta: Double)] = [
        ("An−", -30), ("Tri+", 120), ("Comp", 180), ("Tri−", 240), ("An+", 30),
    ]

    // vertical plan, top down
    private let headerTop: CGFloat = 0
    private let contrastTop: CGFloat = 28
    private let channelsTop: CGFloat = 48
    private let channelRowsTop: CGFloat = 78
    private let harmonyTop: CGFloat = 168
    private let tonesTop: CGFloat = 226
    private let recentTop: CGFloat = 266

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        hexField.isBezeled = false
        hexField.drawsBackground = true
        hexField.backgroundColor = palette.itemBG.withAlphaComponent(0.25)
        hexField.textColor = palette.label
        hexField.font = nerdFont("Regular", 11)
        hexField.alignment = .center
        hexField.focusRingType = .none
        hexField.delegate = self
        hexField.target = self
        hexField.action = #selector(hexReturn)
        addSubview(hexField)

        tabs.items = ["RGB", "HSL"]
        tabs.index = 0
        tabs.onChange = { [weak self] i in
            guard let self else { return }
            self.tab = i
            self.needsLayout = true
            self.layoutSubtreeIfNeeded()
            self.needsDisplay = true
        }
        addSubview(tabs)

        for (i, label) in ["R", "G", "B"].enumerated() {
            let s = ChannelSliderView()
            s.label = label
            s.minValue = 0
            s.maxValue = 255
            s.onChange = { [weak self] v in self?.rgbChanged(i, v) }
            rgbSliders.append(s)
            addSubview(s)
        }
        for (i, spec) in [("H", "°", 360.0), ("S", "%", 100.0), ("L", "%", 100.0)].enumerated() {
            let s = ChannelSliderView()
            s.label = spec.0
            s.suffix = spec.1
            s.minValue = 0
            s.maxValue = spec.2
            s.onChange = { [weak self] v in self?.hslChanged(i, v) }
            hslSliders.append(s)
            addSubview(s)
        }
    }
    required init?(coder: NSCoder) { fatalError("not used") }

    func update(hex: String?, title: String, active: Bool,
                bgHex: String, fgHex: String, recent: [String]) {
        syncing = true
        self.title = title
        self.active = active
        self.bgHex = bgHex
        self.fgHex = fgHex
        self.recents = recent
        self.hex = hex ?? "#000000"
        if hexField.currentEditor() == nil { hexField.stringValue = hex ?? "" }
        syncChannels()
        syncing = false
        recomputeDerivedSwatches()
        needsDisplay = true
        layoutSubtreeIfNeeded()
    }

    private func syncChannels() {
        guard hex.count == 7, let v = UInt64(hex.dropFirst(), radix: 16) else { return }
        let r = Double((v >> 16) & 0xff), g = Double((v >> 8) & 0xff), b = Double(v & 0xff)
        rgbSliders[0].setValue(r, notify: false)
        rgbSliders[1].setValue(g, notify: false)
        rgbSliders[2].setValue(b, notify: false)
        let hsl = hslComponents(hex)
        hslSliders[0].setValue(hsl.h, notify: false)
        hslSliders[1].setValue(hsl.s, notify: false)
        hslSliders[2].setValue(hsl.l, notify: false)
        hslSliders[0].gradient = stride(from: 0.0, through: 360.0, by: 30.0).map {
            nsColor(fromHex: hslHex($0, max(40, hsl.s), min(70, max(30, hsl.l))))
        }
        hslSliders[1].gradient = [
            nsColor(fromHex: hslHex(hsl.h, 0, hsl.l)),
            nsColor(fromHex: hslHex(hsl.h, 50, hsl.l)),
            nsColor(fromHex: hslHex(hsl.h, 100, hsl.l)),
        ]
        hslSliders[2].gradient = [
            nsColor(fromHex: hslHex(hsl.h, hsl.s, 4)),
            nsColor(fromHex: hslHex(hsl.h, hsl.s, 50)),
            nsColor(fromHex: hslHex(hsl.h, hsl.s, 96)),
        ]
    }

    private func recomputeDerivedSwatches() {
        let hsl = hslComponents(hex)
        harmony = Self.harmonySpec.map { ($0.label, hslHex(hsl.h + $0.delta, hsl.s, hsl.l)) }
        tones = (0..<11).map { i in hslHex(hsl.h, hsl.s, 8 + Double(i) * 8.4) }
        currentTone = (0..<11).first { abs((8 + Double($0) * 8.4) - hsl.l) < 4.2 } ?? -1
    }

    @objc private func hexReturn() { commitHex() }
    func controlTextDidEndEditing(_ obj: Notification) { commitHex() }

    private func commitHex() {
        guard !syncing else { return }
        guard let clean = cleanHex(hexField.stringValue) else {
            hexField.stringValue = hex
            return
        }
        if clean != hex { onColor?(clean) }
    }

    private func rgbChanged(_ index: Int, _ value: Double) {
        guard !syncing, hex.count == 7, let v = UInt64(hex.dropFirst(), radix: 16) else { return }
        var c = [Double((v >> 16) & 0xff), Double((v >> 8) & 0xff), Double(v & 0xff)]
        c[index] = max(0, min(255, value.rounded()))
        apply(String(format: "#%02x%02x%02x", Int(c[0]), Int(c[1]), Int(c[2])))
    }

    private func hslChanged(_ index: Int, _ value: Double) {
        guard !syncing else { return }
        var hsl = hslComponents(hex)
        switch index {
        case 0: hsl.h = value
        case 1: hsl.s = value
        default: hsl.l = value
        }
        apply(hslHex(hsl.h, hsl.s, hsl.l))
    }

    private func apply(_ out: String) {
        hex = out
        hexField.stringValue = out
        syncChannels()
        recomputeDerivedSwatches()
        needsDisplay = true
        onColor?(out)
    }

    // --- geometry ----------------------------------------------------------

    private func swatchRow(count: Int, top: CGFloat, height: CGFloat) -> [NSRect] {
        guard count > 0 else { return [] }
        let gap: CGFloat = 4
        let w = (bounds.width - CGFloat(count - 1) * gap) / CGFloat(count)
        return (0..<count).map {
            NSRect(x: CGFloat($0) * (w + gap), y: bounds.height - top - height, width: w, height: height)
        }
    }

    private func harmonyRects() -> [NSRect] { swatchRow(count: harmony.count, top: harmonyTop, height: 28) }
    private func toneRects() -> [NSRect] { swatchRow(count: tones.count, top: tonesTop, height: 22) }
    private func recentRects() -> [NSRect] { swatchRow(count: recents.count, top: recentTop, height: 16) }

    override func layout() {
        super.layout()
        hexField.frame = NSRect(x: bounds.width - 96, y: bounds.height - headerTop - 24,
                                width: 96, height: 18)
        let tabsSize = tabs.sizeThatFits()
        tabs.frame = NSRect(x: bounds.width - tabsSize.width,
                            y: bounds.height - channelsTop - tabsSize.height + 4,
                            width: tabsSize.width, height: tabsSize.height)
        let active = tab == 0 ? rgbSliders : hslSliders
        for s in rgbSliders { s.isHidden = tab != 0 }
        for s in hslSliders { s.isHidden = tab != 1 }
        for (i, s) in active.enumerated() {
            s.frame = NSRect(x: 0, y: bounds.height - channelRowsTop - CGFloat(i + 1) * ChannelSliderView.rowHeight,
                             width: bounds.width, height: ChannelSliderView.rowHeight)
        }
    }

    private func eyebrow(_ text: String, _ top: CGFloat) {
        drawTopLeft(text, nerdFont("Bold", 9), palette.muted,
                    x: 0, top: top, height: bounds.height)
    }

    override func draw(_ dirtyRect: NSRect) {
        if !active {
            drawMidLeft("Click a colour card to edit it.", nerdFont("Regular", 11), palette.muted,
                        x: 0, midTop: 12, height: bounds.height)
            return
        }
        // header: preview + name + hex field
        let preview = NSRect(x: 0, y: bounds.height - headerTop - 22, width: 22, height: 22)
        let path = NSBezierPath(roundedRect: preview.insetBy(dx: 0.5, dy: 0.5), xRadius: 5, yRadius: 5)
        nsColor(fromHex: hex).setFill()
        path.fill()
        palette.muted.withAlphaComponent(0.35).setStroke()
        path.lineWidth = 1
        path.stroke()
        drawMidLeft(truncate(title, nerdFont("Bold", 11), bounds.width - 130),
                    nerdFont("Bold", 11), palette.label,
                    x: 30, midTop: headerTop + 11, height: bounds.height)

        // contrast against the palette background and foreground
        let bgRatio = contrastRatioHex(hex, bgHex)
        let fgRatio = contrastRatioHex(hex, fgHex)
        func level(_ r: Double) -> String {
            r >= 7 ? "AAA" : (r >= 4.5 ? "AA" : (r >= 3 ? "AA-L" : "fail"))
        }
        let bgText = String(format: "%.1f \(level(bgRatio)) vs bg", bgRatio)
        let fgText = String(format: "%.1f \(level(fgRatio)) vs fg", fgRatio)
        let startX = drawColored(bgText, nerdFont("Regular", 9),
                                 ink: bgRatio >= 4.5 ? .systemGreen : .systemRed,
                                 x: 0, top: contrastTop, height: bounds.height)
        _ = drawColored(fgText, nerdFont("Regular", 9),
                        ink: fgRatio >= 4.5 ? .systemGreen : .systemRed,
                        x: startX + 10, top: contrastTop, height: bounds.height)

        eyebrow("Channels", channelsTop + 2)
        eyebrow("Harmony", harmonyTop - 12)
        eyebrow("Tones", tonesTop - 12)
        if !recents.isEmpty { eyebrow("Recent", recentTop - 12) }

        for (i, h) in harmony.enumerated() {
            let r = harmonyRects()[i]
            nsColor(fromHex: h.hex).setFill()
            NSBezierPath(roundedRect: r, xRadius: 3, yRadius: 3).fill()
            drawMidCenter(h.label, nerdFont("Regular", 9), palette.muted,
                          centerX: r.midX, midTop: bounds.height - r.minY + 8, height: bounds.height)
        }
        for (i, t) in tones.enumerated() {
            let r = toneRects()[i]
            nsColor(fromHex: t).setFill()
            NSBezierPath(roundedRect: r, xRadius: 2, yRadius: 2).fill()
            if i == currentTone {
                NSColor.white.setStroke()
                let ring = NSBezierPath(roundedRect: r.insetBy(dx: 1, dy: 1), xRadius: 2, yRadius: 2)
                ring.lineWidth = 2
                ring.stroke()
            }
        }
        for (i, c) in recents.enumerated() {
            let r = recentRects()[i]
            nsColor(fromHex: c).setFill()
            NSBezierPath(roundedRect: r, xRadius: 3, yRadius: 3).fill()
        }
    }

    // draws one text run and returns the x it ended at, so two runs can sit
    // on one line with different inks
    @discardableResult
    private func drawColored(_ s: String, _ font: NSFont, ink: NSColor,
                             x: CGFloat, top: CGFloat, height: CGFloat) -> CGFloat {
        drawTopLeft(s, font, ink, x: x, top: top, height: height)
        return x + advance(s, font)
    }

    override func mouseDown(with event: NSEvent) {
        guard active else { return }
        let p = convert(event.locationInWindow, from: nil)
        for (i, h) in harmony.enumerated() where harmonyRects()[i].contains(p) {
            onColor?(h.hex)
            return
        }
        for (i, t) in tones.enumerated() where toneRects()[i].contains(p) {
            onColor?(t)
            return
        }
        for (i, c) in recents.enumerated() where recentRects()[i].contains(p) {
            onColor?(c)
            return
        }
    }

    func refreshColors() {
        hexField.textColor = palette.label
        hexField.backgroundColor = palette.itemBG.withAlphaComponent(0.25)
        for s in rgbSliders + hslSliders { s.refreshColors() }
        needsDisplay = true
    }

    override var acceptsFirstResponder: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

// --- editor columns ---------------------------------------------------------

// The left column: Method, Mode, the curve box, the 12 sliders and Reset.
// A thin view over the shared PaletteModel.
final class PaletteBuilderView: NSView {
    var model: PaletteModel? { didSet { wire() } }

    private let scroll = NSScrollView()
    private let scroller = CustomScroller()
    private let doc = PaletteBuilderDoc()
    private let scrollerW: CGFloat = 8
    private var shownEditKey: String?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        scroll.hasVerticalScroller = false
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        addSubview(scroll)
        scroll.documentView = doc
        addSubview(scroller)
        scroller.scrollView = scroll
        scroll.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(scrolled),
            name: NSView.boundsDidChangeNotification, object: scroll.contentView)
    }
    required init?(coder: NSCoder) { fatalError("not used") }
    deinit { NotificationCenter.default.removeObserver(self) }

    @objc private func scrolled() { scroller.refresh() }

    private func wire() {
        doc.methodButton.onClick = { [weak self] in
            guard let self, let model = self.model else { return }
            var rows: [MethodPicker.Row] = [
                MethodPicker.Row(header: nil, value: "magic", label: "Magic"),
            ]
            for group in model.modeGroups {
                rows.append(MethodPicker.Row(header: group.label.uppercased(),
                                             value: nil, label: group.label))
                for m in group.modes {
                    rows.append(MethodPicker.Row(header: nil, value: m.value, label: m.label))
                }
            }
            MethodPicker.present(from: self.doc.methodButton, rows: rows, strips: model.strips,
                                 currentMethod: model.method) { [weak model] value in
                model?.chooseMethod(value)
            }
        }
        doc.modeSeg.onChange = { [weak self] i in self?.model?.setMode(i) }
        doc.curveView.onChange = { [weak self] points in self?.model?.setCurve(points) }
        for slider in doc.sliders {
            let key = slider.field.key
            slider.onChange = { [weak self] v in self?.model?.setAdjustment(key, v) }
        }
        doc.resetButton.onClick = { [weak self] in self?.model?.resetAdjustments() }
    }

    func sync() {
        guard let model else { return }
        doc.methodButton.title = model.methodLabel(model.method)
        doc.modeSeg.index = model.mode == "light" ? 2 : (model.mode == "dark" ? 1 : 0)
        doc.modeSeg.needsDisplay = true
        doc.curveView.points = model.curve
        doc.curveView.histogram = model.histogram
        for slider in doc.sliders {
            slider.setValue(model.adjustments[slider.field.key], notify: false)
        }
        let editing = model.editTarget != nil
        if doc.editorVisible != editing {
            doc.editorVisible = editing
            doc.inspector.isHidden = !editing
            needsLayout = true
            layoutSubtreeIfNeeded()
        }
        let finals = model.finalColors.count == 16 ? model.finalColors : model.baseColors
        doc.inspector.update(hex: model.editTargetHex(), title: model.editTargetTitle(),
                             active: editing,
                             bgHex: finals.first ?? "#000000",
                             fgHex: finals.indices.contains(7) ? finals[7] : "#ffffff",
                             recent: model.recentColors)
        let editKey = editing ? (model.editTargetHex() ?? "") + "·" + model.editTargetTitle() : nil
        if editKey != shownEditKey {
            shownEditKey = editKey
            if editKey != nil {
                DispatchQueue.main.async { [weak self] in self?.doc.scrollInspectorIntoView() }
            }
        }
        doc.needsDisplay = true
        needsDisplay = true
    }

    func refreshColors() {
        needsDisplay = true
        markTree(doc)
        for slider in doc.sliders { slider.refreshColors() }
        doc.inspector.refreshColors()
    }

    private func markTree(_ view: NSView) {
        view.needsDisplay = true
        for sub in view.subviews { markTree(sub) }
    }

    override func layout() {
        super.layout()
        let headerH: CGFloat = 40
        let h = max(0, bounds.height - headerH)
        scroll.frame = NSRect(x: 0, y: 0, width: max(0, bounds.width - scrollerW - 14), height: h)
        scroller.frame = NSRect(x: bounds.width - scrollerW, y: 0, width: scrollerW, height: h)
        scroller.refresh()
        let w = scroll.contentSize.width
        let clipH = scroll.contentSize.height
        let targetH = max(doc.contentHeight(), clipH)
        if w > 0, (abs(doc.frame.width - w) > 0.5 || abs(doc.frame.height - targetH) > 0.5) {
            let first = doc.frame.width == 0
            doc.frame = NSRect(origin: .zero, size: NSSize(width: w, height: targetH))
            doc.needsLayout = true
            doc.layoutSubtreeIfNeeded()
            if first {
                scroll.contentView.scroll(to: NSPoint(x: 0, y: max(0, targetH - clipH)))
                scroll.reflectScrolledClipView(scroll.contentView)
            }
            scroller.refresh()
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        drawMidLeft("Palette Builder", nerdFont("Bold", 13), palette.accent,
                    x: 16, midTop: 18, height: bounds.height)
    }
}

final class PaletteBuilderDoc: NSView {
    let methodButton = PopupButtonView()
    let modeSeg = SegmentedView()
    let inspector = ColorInspectorView()
    let curveView = CurveEditorView()
    var sliders: [AdjustmentSliderView] = []
    let resetButton = ButtonView()

    // the inspector appears only while a card is selected
    var editorVisible = false

    private let insetL: CGFloat = 16
    private let insetR: CGFloat = 12
    private var methodTop: CGFloat = 0
    private var modeTop: CGFloat = 0
    private var editorTop: CGFloat = 0
    private var adjTop: CGFloat = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        modeSeg.items = ["Auto", "Dark", "Light"]
        addSubview(methodButton)
        addSubview(modeSeg)
        inspector.isHidden = true
        addSubview(inspector)
        addSubview(curveView)
        for f in EditorAdjustments.fields {
            let s = AdjustmentSliderView(field: f)
            sliders.append(s)
            addSubview(s)
        }
        resetButton.title = "Reset"
        addSubview(resetButton)
    }
    required init?(coder: NSCoder) { fatalError("not used") }

    private var contentW: CGFloat { max(0, bounds.width - insetL - insetR) }

    // Brings the colour panel to the top of the left pane when a card is
    // picked, so the controls the click opened are in view.
    func scrollInspectorIntoView() {
        guard editorVisible, let scroll = enclosingScrollView else { return }
        layoutSubtreeIfNeeded()
        let clip = scroll.contentView
        let docH = bounds.height
        let top = max(0, editorTop - 12)
        let origin = min(max(0, docH - clip.bounds.height), max(0, docH - top - clip.bounds.height))
        clip.scroll(to: NSPoint(x: 0, y: origin))
        scroll.reflectScrolledClipView(clip)
    }

    func contentHeight() -> CGFloat {
        var h: CGFloat = 10
        h += 34 + 34                                        // Method + Mode
        if editorVisible { h += ColorInspectorView.viewHeight + 20 }
        h += 24                                             // Adjustments
        h += CurveEditorView.viewHeight + 8
        h += CGFloat(sliders.count) * AdjustmentSliderView.rowHeight
        h += 38                                             // Reset Adjustments
        h += 10
        return h
    }

    private func rect(top: CGFloat, h: CGFloat, x: CGFloat, w: CGFloat) -> NSRect {
        NSRect(x: x, y: bounds.height - top - h, width: w, height: h)
    }

    override func layout() {
        super.layout()
        var top: CGFloat = 10
        methodTop = top
        methodButton.frame = rect(top: top + 3, h: 26, x: insetL + max(0, contentW - 170), w: 170)
        top += 34
        modeTop = top
        let segSize = modeSeg.sizeThatFits()
        modeSeg.frame = rect(top: top + 3, h: segSize.height,
                             x: insetL + max(0, contentW - segSize.width), w: segSize.width)
        top += 34
        if editorVisible {
            editorTop = top + 10
            inspector.frame = rect(top: editorTop, h: ColorInspectorView.viewHeight,
                                   x: insetL, w: contentW)
            top += ColorInspectorView.viewHeight + 20
        }
        adjTop = top
        top += 24
        curveView.frame = rect(top: top, h: CurveEditorView.viewHeight, x: insetL, w: contentW)
        top += CurveEditorView.viewHeight + 8
        for s in sliders {
            s.frame = rect(top: top, h: AdjustmentSliderView.rowHeight, x: insetL, w: contentW)
            top += AdjustmentSliderView.rowHeight
        }
        top += 8
        resetButton.frame = rect(top: top, h: 24, x: insetL, w: 96)
    }

    override func draw(_ dirtyRect: NSRect) {
        drawMidLeft("Method", nerdFont("Bold", 12), palette.label,
                    x: insetL, midTop: methodTop + 16, height: bounds.height)
        drawMidLeft("Mode", nerdFont("Bold", 12), palette.label,
                    x: insetL, midTop: modeTop + 16, height: bounds.height)
        if editorVisible {
            palette.muted.withAlphaComponent(0.25).setFill()
            NSRect(x: insetL, y: bounds.height - (editorTop - 6), width: contentW, height: 1).fill()
            NSRect(x: insetL, y: bounds.height - (adjTop - 10), width: contentW, height: 1).fill()
        }
        drawTopLeft("Adjustments", nerdFont("Bold", 12), palette.accent,
                    x: insetL, top: adjTop, height: bounds.height)
    }
}

// The centre column: the palette cards, the extended four and the inline
// colour editor. The wallpaper and preview panes arrive in Phase 6 above
// this document.
final class PaletteCanvasView: NSView {
    var model: PaletteModel? { didSet { wire(); sync() } }

    private let scroll = NSScrollView()
    private let scroller = CustomScroller()
    private let doc = PaletteCanvasDoc()
    private let scrollerW: CGFloat = 8

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        scroll.hasVerticalScroller = false
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        addSubview(scroll)
        scroll.documentView = doc
        addSubview(scroller)
        scroller.scrollView = scroll
        scroll.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(scrolled),
            name: NSView.boundsDidChangeNotification, object: scroll.contentView)
    }
    required init?(coder: NSCoder) { fatalError("not used") }
    deinit { NotificationCenter.default.removeObserver(self) }

    @objc private func scrolled() { scroller.refresh() }

    private func wire() {
        doc.colorCards.onEdit = { [weak self] target in self?.model?.selectForEdit(target) }
        doc.colorCards.onToggleLock = { [weak self] i in self?.model?.toggleLock(i) }
        doc.colorCards.onToggleSelect = { [weak self] i in self?.model?.toggleSelect(i) }
        doc.semantic.onEdit = { [weak self] target in self?.model?.selectForEdit(target) }
    }

    func sync() {
        guard let model else { return }
        let finals = model.finalColors.count == 16 ? model.finalColors : model.baseColors
        doc.colorCards.cards = model.baseColors.enumerated().map { i, base in
            let label = PaletteModel.ansiLabels.indices.contains(i) ? PaletteModel.ansiLabels[i] : "\(i)"
            return PaletteCardsView.Card(label: label,
                                         hex: finals.indices.contains(i) ? finals[i] : base,
                                         index: i, extendedKey: nil)
        }
        doc.colorCards.locked = model.locked
        doc.colorCards.selected = model.selected
        doc.colorCards.editTarget = model.editTarget
        doc.colorCards.bgHex = finals.first ?? "#000000"
        doc.methodText = "· \(model.methodLabel(model.method))"

        func base(_ i: Int) -> String { finals.indices.contains(i) ? finals[i] : "#000000" }
        func shade(_ key: String, _ fallback: Int) -> String {
            model.shades[key] ?? base(fallback)
        }
        func ext(_ key: String) -> String {
            model.finalExtended[key] ?? model.extendedHex[key] ?? "#000000"
        }
        doc.semantic.groups = [
            SemanticSectionView.Group(title: "Background", cards: [
                .init(label: "Darker", hex: shade("darker_bg", 0), key: nil),
                .init(label: "Dark", hex: shade("dark_bg", 0), key: nil),
                .init(label: "Base", hex: base(0), key: nil),
                .init(label: "Lighter", hex: shade("lighter_bg", 0), key: nil),
            ]),
            SemanticSectionView.Group(title: "Foreground", cards: [
                .init(label: "Muted", hex: base(8), key: nil),
                .init(label: "Dark", hex: shade("dark_fg", 7), key: nil),
                .init(label: "Base", hex: base(7), key: nil),
                .init(label: "Light", hex: shade("light_fg", 7), key: nil),
                .init(label: "Bright", hex: shade("bright_fg", 7), key: nil),
            ]),
            SemanticSectionView.Group(title: "Accent", cards: [
                .init(label: "Orange", hex: shade("orange", 1), key: nil),
                .init(label: "Brown", hex: shade("brown", 1), key: nil),
            ]),
            SemanticSectionView.Group(title: "UI", cards: [
                .init(label: "Accent", hex: ext("accent"), key: "accent"),
                .init(label: "Cursor", hex: ext("cursor"), key: "cursor"),
                .init(label: "Sel FG", hex: ext("selection_foreground"), key: "selection_foreground"),
                .init(label: "Sel BG", hex: ext("selection_background"), key: "selection_background"),
            ]),
        ]
        doc.semantic.editTarget = model.editTarget
        doc.needsDisplay = true
        needsDisplay = true
    }

    func refreshColors() {
        needsDisplay = true
        markTree(doc)
    }

    private func markTree(_ view: NSView) {
        view.needsDisplay = true
        for sub in view.subviews { markTree(sub) }
    }

    override func layout() {
        super.layout()
        scroll.frame = NSRect(x: 0, y: 0, width: max(0, bounds.width - scrollerW - 14), height: bounds.height)
        scroller.frame = NSRect(x: bounds.width - scrollerW, y: 0, width: scrollerW, height: bounds.height)
        scroller.refresh()
        let w = scroll.contentSize.width
        let clipH = scroll.contentSize.height
        let targetH = max(doc.contentHeight(), clipH)
        if w > 0, (abs(doc.frame.width - w) > 0.5 || abs(doc.frame.height - targetH) > 0.5) {
            let first = doc.frame.width == 0
            doc.frame = NSRect(origin: .zero, size: NSSize(width: w, height: targetH))
            doc.needsLayout = true
            doc.layoutSubtreeIfNeeded()
            if first {
                scroll.contentView.scroll(to: NSPoint(x: 0, y: max(0, targetH - clipH)))
                scroll.reflectScrolledClipView(scroll.contentView)
            }
            scroller.refresh()
        }
    }
}

final class PaletteCanvasDoc: NSView {
    let colorCards = PaletteCardsView()
    let semantic = SemanticSectionView()
    var methodText = ""

    private let insetL: CGFloat = 16
    private let insetR: CGFloat = 14
    private var paletteTop: CGFloat = 0
    private var hintTop: CGFloat = 0
    private var semanticTop: CGFloat = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        colorCards.showsLocks = true
        addSubview(colorCards)
        addSubview(semantic)
    }
    required init?(coder: NSCoder) { fatalError("not used") }

    private var contentW: CGFloat { max(0, bounds.width - insetL - insetR) }

    func contentHeight() -> CGFloat {
        var h: CGFloat = 12
        h += 26                                             // "Palette 16 colors · …"
        h += PaletteCardsView.height(for: 16)
        h += 36                                             // spaced hint line
        h += 26                                             // "Semantic Colors"
        h += SemanticSectionView.height()
        h += 12
        return h
    }

    private func rect(top: CGFloat, h: CGFloat, x: CGFloat, w: CGFloat) -> NSRect {
        NSRect(x: x, y: bounds.height - top - h, width: w, height: h)
    }

    override func layout() {
        super.layout()
        var top: CGFloat = 12
        paletteTop = top
        top += 26
        colorCards.frame = rect(top: top, h: PaletteCardsView.height(for: 16), x: insetL, w: contentW)
        top += PaletteCardsView.height(for: 16)
        hintTop = top + 12
        top += 36
        semanticTop = top
        top += 26
        semantic.frame = rect(top: top, h: SemanticSectionView.height(), x: insetL, w: contentW)
    }

    override func draw(_ dirtyRect: NSRect) {
        let h = bounds.height
        drawTopLeft("Palette", nerdFont("Bold", 13), palette.label,
                    x: insetL, top: paletteTop, height: h)
        drawTopLeft(methodText, nerdFont("Regular", 11), palette.muted,
                    x: insetL + 62, top: paletteTop + 2, height: h)
        drawTopLeft("Click to edit · Shift-click to select; the padlock survives a Method change.",
                    nerdFont("Regular", 10), palette.muted,
                    x: insetL, top: hintTop, height: h)
        drawTopLeft("Semantic Colors", nerdFont("Bold", 12), palette.accent,
                    x: insetL, top: semanticTop, height: h)
        drawTopLeft("Derived automatically.",
                    nerdFont("Regular", 10), palette.muted,
                    x: insetL + 118, top: semanticTop + 1, height: h)
    }
}

// --- editor footer ----------------------------------------------------------

// Save / Save As / Apply, and the one place unsaved changes are announced.
final class EditorFooterView: NSView {
    let saveButton = ButtonView()
    let saveAsButton = ButtonView()
    let applyButton = ButtonView()
    var dirty = false { didSet { needsDisplay = true } }
    var message: (text: String, red: Bool)? { didSet { needsDisplay = true } }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        saveAsButton.title = "Save As…"
        saveAsButton.secondary = true
        saveButton.title = "Save"
        applyButton.title = "Apply Theme"
        addSubview(saveAsButton)
        addSubview(saveButton)
        addSubview(applyButton)
    }
    required init?(coder: NSCoder) { fatalError("not used") }

    override func layout() {
        super.layout()
        let margin: CGFloat = 16
        let w: CGFloat = 96, h: CGFloat = 24
        let y = (bounds.height - h) / 2
        applyButton.frame = NSRect(x: bounds.width - margin - w, y: y, width: w, height: h)
        saveButton.frame = NSRect(x: applyButton.frame.minX - 8 - w, y: y, width: w, height: h)
        saveAsButton.frame = NSRect(x: saveButton.frame.minX - 8 - w, y: y, width: w, height: h)
    }

    override func draw(_ dirtyRect: NSRect) {
        palette.muted.withAlphaComponent(0.25).setFill()
        NSRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1).fill()
        if let message {
            drawMidLeft(message.text, nerdFont("Regular", 11),
                        message.red ? .systemRed : palette.muted,
                        x: 20, midTop: bounds.height / 2, height: bounds.height)
        } else if dirty {
            let dot = NSRect(x: 20, y: bounds.midY - 3, width: 6, height: 6)
            palette.accent.setFill()
            NSBezierPath(ovalIn: dot).fill()
            drawMidLeft("Unsaved changes", nerdFont("Regular", 11), palette.muted,
                        x: 32, midTop: bounds.height / 2, height: bounds.height)
        }
    }
}

final class ThemeEditorView: NSView, NSTextFieldDelegate {
    var onClose: (() -> Void)?
    var onNameEdit: (() -> Void)?
    var displayName = "" { didSet { needsDisplay = true } }
    var dirty = false { didSet { footer.dirty = dirty } }
    let nameField = NSTextField()
    let paletteBuilder = PaletteBuilderView()
    let paletteCanvas = PaletteCanvasView()
    let wallpaperEditor = EditorColumnView()
    let footer = EditorFooterView()

    private let headerH: CGFloat = 56
    private let footerH: CGFloat = 54
    private let leftW: CGFloat = 320
    private let rightW: CGFloat = 340
    private let closeSize: CGFloat = 24

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wallpaperEditor.title = "Wallpaper Editor"
        nameField.isBezeled = false
        nameField.drawsBackground = true
        nameField.backgroundColor = palette.itemBG.withAlphaComponent(0.25)
        nameField.textColor = palette.label
        nameField.font = nerdFont("Bold", 14)
        nameField.focusRingType = .none
        nameField.usesSingleLineMode = true
        nameField.lineBreakMode = .byTruncatingTail
        nameField.delegate = self
        nameField.target = self
        nameField.action = #selector(nameReturn)
        addSubview(nameField)
        addSubview(paletteBuilder)
        addSubview(paletteCanvas)
        addSubview(wallpaperEditor)
        addSubview(footer)
    }
    required init?(coder: NSCoder) { fatalError("not used") }

    var nameValue: String {
        nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    func setName(_ name: String) { nameField.stringValue = name }

    @objc private func nameReturn() { window?.makeFirstResponder(self) }
    func controlTextDidChange(_ obj: Notification) { onNameEdit?() }

    // a theme name is not prose: the field editor's red dotted spell
    // underline reads as a rendering bug in the header
    func controlTextDidBeginEditing(_ obj: Notification) {
        guard let editor = obj.userInfo?["NSFieldEditor"] as? NSTextView else { return }
        editor.isContinuousSpellCheckingEnabled = false
        editor.isAutomaticSpellingCorrectionEnabled = false
        editor.isAutomaticTextReplacementEnabled = false
        editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.isAutomaticDashSubstitutionEnabled = false
        editor.isGrammarCheckingEnabled = false
    }

    private var closeRect: NSRect {
        NSRect(x: bounds.width - closeSize - 16,
               y: bounds.height - headerH / 2 - closeSize / 2,
               width: closeSize, height: closeSize)
    }

    override func layout() {
        super.layout()
        let h = max(0, bounds.height - headerH - footerH)
        paletteBuilder.frame = NSRect(x: 0, y: footerH, width: leftW, height: h)
        paletteCanvas.frame = NSRect(x: leftW, y: footerH,
                                     width: max(0, bounds.width - leftW - rightW), height: h)
        wallpaperEditor.frame = NSRect(x: bounds.width - rightW, y: footerH, width: rightW, height: h)
        footer.frame = NSRect(x: 0, y: 0, width: bounds.width, height: footerH)
        // the name field is the whole title — no static prefix (the editor
        // is obvious from its contents); -14 centres the cell-drawn text on
        // the header's mid line — NSTextField lays text out from the frame
        // top, not on cap height
        nameField.frame = NSRect(x: 20, y: bounds.height - headerH / 2 - 14,
                                 width: max(120, closeRect.minX - 16 - 20), height: 22)
    }

    override func draw(_ dirtyRect: NSRect) {
        // the same card chrome as the dashboard: bar background, accent rim
        let corner = min(windowCornerRadius(10), min(bounds.width, bounds.height) / 2)
        let body = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
                                xRadius: corner, yRadius: corner)
        palette.barBG.setFill()
        body.fill()
        palette.accent.setStroke()
        body.lineWidth = 1
        body.stroke()

        drawMidCenter("✕", nerdFont("Regular", 12), palette.muted,
                      centerX: closeRect.midX, midTop: headerH / 2, height: bounds.height)

        // column rules, drawn last so they sit on every surface
        palette.muted.withAlphaComponent(0.25).setFill()
        NSRect(x: 0, y: bounds.height - headerH, width: bounds.width, height: 1).fill()
        let columnH = max(0, bounds.height - headerH - footerH)
        NSRect(x: leftW, y: footerH, width: 1, height: columnH).fill()
        NSRect(x: bounds.width - rightW, y: footerH, width: 1, height: columnH).fill()
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if closeRect.contains(p) { onClose?() }
    }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onClose?() }
    }
}

final class ThemeEditor {
    private static var current: ThemeEditor?

    let window: EditorWindow
    private let root: ThemeEditorView
    private let subject: EditorSubject
    private let model = PaletteModel()
    private let status: ((String) -> Void)?
    private var keyMonitor: Any?
    private var messageWork: DispatchWorkItem?
    // what the later panels read: the edition's stored record, or the
    // draft's Magic seed
    private(set) var record: [String: Any]?
    // set on any user change; Save/Apply clear it
    private(set) var dirty = false

    private init(subject: EditorSubject, size: NSSize, status: ((String) -> Void)?) {
        self.subject = subject
        self.status = status
        root = ThemeEditorView(frame: NSRect(origin: .zero, size: size))
        window = EditorWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: .borderless, backing: .buffered, defer: false)
        root.displayName = subject.displayName
        root.setName(subject.displayName)
        root.onClose = { [weak self] in self?.close() }
        root.onNameEdit = { [weak self] in
            guard let self else { return }
            self.dirty = true
            self.root.dirty = true
        }
        root.paletteBuilder.model = model
        root.paletteCanvas.model = model
        model.onUpdate = { [weak self] in
            guard let self else { return }
            self.root.paletteBuilder.sync()
            self.root.paletteCanvas.sync()
        }
        model.onUserEdit = { [weak self] in
            guard let self else { return }
            self.dirty = true
            self.root.dirty = true
        }
        root.footer.saveButton.onClick = { [weak self] in self?.startSave(newID: false, action: .none) }
        root.footer.saveAsButton.onClick = { [weak self] in self?.startSave(newID: true, action: .none) }
        root.footer.applyButton.onClick = { [weak self] in self?.startSave(newID: false, action: .apply) }
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.level = .popUpMenu
        window.acceptsMouseMovedEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.contentView = root
    }

    // The Edit pill's front door. A named variation opens its saved record;
    // a raw Wallpaper #N always starts a fresh draft seeded from its Magic
    // palette — Customize never replaces an existing variation.
    static func present(cell: ThemeCell, from host: NSWindow, status: ((String) -> Void)? = nil) {
        guard let dash = host as? DashboardWindow else { return }
        if let id = cell.editionID, let e = allEditions().first(where: { $0.id == id }) {
            openEditor(.edition(e), from: dash, status: status)
            return
        }
        openEditor(.draft(wallpaper: cell.wallpaper), from: dash, status: status)
    }

    private static func openEditor(_ subject: EditorSubject, from dash: DashboardWindow,
                                   status: ((String) -> Void)?) {
        current?.close()
        let screen = dash.screen ?? NSScreen.main
        let frame = screen?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let w = min(1280, frame.width - 80)
        let h = min(800, frame.height - 80)
        let editor = ThemeEditor(subject: subject, size: NSSize(width: w, height: h), status: status)
        current = editor
        editor.window.setFrameOrigin(NSPoint(x: frame.midX - w / 2, y: frame.midY - h / 2))
        // the editor owns the session: outside clicks and the toggle key
        // must not dismiss the dashboard until the editor is closed
        dash.hideSuppressed = true
        dash.addChildWindow(editor.window, ordered: .above)
        editor.show()
    }

    // a theme switch repaints the card; the editor draws with the same
    // global palette, so it must be marked dirty too
    static func refreshColors() {
        guard let e = current else { return }
        e.root.needsDisplay = true
        for v in e.root.subviews { v.needsDisplay = true }
        e.root.paletteBuilder.refreshColors()
        e.root.paletteCanvas.refreshColors()
    }

    // Esc on the dashboard while the editor is up means "close the editor,
    // not the dashboard": a click on the card around the editor hands the
    // keyboard back to the dashboard, and Esc must still return to Themes
    @discardableResult
    static func closeIfOpen() -> Bool {
        guard let e = current else { return false }
        e.close()
        return true
    }

    // --- save / apply -------------------------------------------------------

    private enum SaveAction { case none, apply }

    private func startSave(newID: Bool, action: SaveAction) {
        let name = root.nameValue
        guard !name.isEmpty else {
            showMessage("Give the theme a name.", red: true)
            return
        }
        let base = saveBase(newID: newID)
        root.footer.saveButton.busy = true
        root.footer.saveAsButton.busy = true
        root.footer.message = nil
        DispatchQueue.global().async { [weak self] in
            guard let self else { return }
            let (error, fresh) = self.runSave(base: base, name: name, newID: newID)
            DispatchQueue.main.async {
                self.root.footer.saveButton.busy = false
                self.root.footer.saveAsButton.busy = false
                if let error {
                    self.showMessage(error, red: true)
                } else if let fresh {
                    self.didSave(fresh, action: action)
                }
            }
        }
    }

    // The record skeleton, built on the main thread so a save in flight
    // never reads the model while an edit is running.
    private func saveBase(newID: Bool) -> [String: Any] {
        var top: [String: Any]
        if let rec = record {
            top = rec
            if newID {
                top["schema"] = rec["schema"] ?? 1
                top["primary"] = rec["primary"] ?? true
                top.removeValue(forKey: "id")
                top.removeValue(forKey: "created")
                top.removeValue(forKey: "updated")
            }
        } else {
            top = ["schema": 1, "primary": true, "favorite": false,
                   "wallpaper": ["path": model.imagePath, "source": "local",
                                 "blur": false, "edited": false]]
        }
        top["palette"] = palettePayload()
        return top
    }

    private func palettePayload() -> [String: Any] {
        var extended: [String: String] = [:]
        for slot in PaletteModel.extendedKeys {
            extended[slot.key] = model.extendedHex[slot.key] ?? "#000000"
        }
        return ["method": model.method, "mode": model.mode, "resolvedMode": model.resolvedMode,
                "colors": model.baseColors, "extended": extended,
                "locked": model.locked.sorted(),
                "adjustments": model.adjustments.values, "curve": model.curve]
    }

    private func runSave(base: [String: Any], name: String, newID: Bool)
        -> (error: String?, record: [String: Any]?) {
        var top = base
        top["name"] = name
        let tmp = NSTemporaryDirectory()
            + "omacosy-editor-save-\(ProcessInfo.processInfo.processIdentifier).json"
        guard let data = try? JSONSerialization.data(withJSONObject: top, options: [.sortedKeys]),
              (try? data.write(to: URL(fileURLWithPath: tmp))) != nil else {
            return ("Couldn't prepare the theme file.", nil)
        }
        let (code, out) = shell("\(themecoreBin()) theme save \(shellQuote(tmp)) --json 2>&1")
        try? FileManager.default.removeItem(atPath: tmp)
        guard code == 0, let od = out.data(using: .utf8),
              let obj = (try? JSONSerialization.jsonObject(with: od)) as? [String: Any],
              let id = obj["id"] as? String else {
            if out.lowercased().contains("already exists") {
                return ("A theme named “\(name)” already exists. Choose another name.", nil)
            }
            return ("Couldn't save the theme. Try again.", nil)
        }
        let (sc, so) = shell("\(themecoreBin()) theme show \(shellQuote(id)) 2>/dev/null")
        if sc == 0, let fresh = (try? JSONSerialization.jsonObject(with: Data(so.utf8))) as? [String: Any] {
            return (nil, fresh)
        }
        var fallback = top
        fallback["id"] = id
        return (nil, fallback)
    }

    private func didSave(_ fresh: [String: Any], action: SaveAction) {
        record = fresh
        dirty = false
        root.dirty = false
        let name = fresh["name"] as? String ?? root.nameValue
        if action == .apply, let id = fresh["id"] as? String {
            performApply(id: id, name: name)
        } else {
            finish(with: "Saved \(name)")
        }
    }

    // a finished write hands the dashboard a line of status and steps out
    private func finish(with message: String) {
        let report = status
        close()
        report?(message)
    }

    private func showMessage(_ text: String, red: Bool, seconds: Double = 4) {
        messageWork?.cancel()
        root.footer.message = (text, red)
        let work = DispatchWorkItem { [weak self] in self?.root.footer.message = nil }
        messageWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    private func performApply(id: String, name: String) {
        root.footer.applyButton.busy = true
        DispatchQueue.global().async { [weak self] in
            let json = HOME + "/.config/omacosy/themes/" + id + ".json"
            _ = shell("\(HOME)/.local/bin/omacosy-theme-switch set-theme \(shellQuote(json))")
            DispatchQueue.main.async {
                guard let self else { return }
                self.root.footer.applyButton.busy = false
                self.finish(with: "Applied \(name)")
            }
        }
    }

    private func show() {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(root)
        // Esc, wherever focus sits in the editor; the dashboard's own
        // monitors ignore an Esc aimed at another window
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] e in
            guard let self, e.window === self.window else { return e }
            if e.keyCode == 53 {
                // Esc while the name is being edited ends that first
                if self.root.nameField.currentEditor() != nil {
                    self.root.window?.makeFirstResponder(self.root)
                    return nil
                }
                // Esc peels one layer at a time: selection, then the edited
                // colour, then the editor itself
                if self.model.clearSelection() { return nil }
                if self.model.clearEditTarget() { return nil }
                self.close()
                return nil
            }
            return e
        }
        loadSubject()
    }

    private func loadSubject() {
        switch subject {
        case .edition(let e):
            let q = shellQuote(e.id)
            DispatchQueue.global().async { [weak self] in
                let (code, out) = shell("\(themecoreBin()) theme show " + q + " 2>/dev/null")
                guard code == 0, let data = out.data(using: .utf8),
                      let rec = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
                else { return }
                let (wc, wo) = shell("\(themecoreBin()) theme wallpaper " + q + " --json 2>/dev/null")
                var image = ""
                if wc == 0, let wd = wo.data(using: .utf8),
                   let wobj = (try? JSONSerialization.jsonObject(with: wd)) as? [String: Any] {
                    image = wobj["path"] as? String ?? ""
                }
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.record = rec
                    if let name = rec["name"] as? String, !name.isEmpty { self.root.setName(name) }
                    guard !image.isEmpty else { return }
                    self.model.seedEdition(record: rec, image: image)
                }
            }
        case .draft(let wallpaper):
            let q = shellQuote(wallpaper)
            DispatchQueue.global().async { [weak self] in
                guard let self else { return }
                // Fast path: the derived theme the Themes grid already shows.
                // Its 16 colours ARE the Magic palette (the Phase 2
                // cross-check pins them), and term-palette reads them in
                // milliseconds instead of a fresh extraction (~0.6 s on 4K).
                let (rc, rout) = shell("\(HOME)/.local/bin/omacosy-custom-theme theme --raw \(q) 2>/dev/null")
                let dir = rout.split(separator: "\n").last.map(String.init)?
                    .trimmingCharacters(in: .whitespaces) ?? ""
                if rc == 0, !dir.isEmpty {
                    let envFile = NSTemporaryDirectory()
                        + "omacosy-editor-seed-\(ProcessInfo.processInfo.processIdentifier).env"
                    let (tc, _) = shell("\(HOME)/.local/bin/omacosy-term-palette \(shellQuote(dir)) \(shellQuote(envFile)) >/dev/null 2>&1")
                    var byIndex: [Int: String] = [:]
                    var accent: String?
                    var resolved = "dark"
                    if tc == 0, let text = try? String(contentsOfFile: envFile, encoding: .utf8) {
                        for line in text.split(separator: "\n") {
                            let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
                            guard parts.count == 2 else { continue }
                            let value = parts[1].trimmingCharacters(in: CharacterSet(charactersIn: "'\""))
                            if parts[0].hasPrefix("OMACOSY_P"), let i = Int(parts[0].dropFirst(9)) {
                                byIndex[i] = value
                            } else if parts[0] == "OMACOSY_ACCENT" {
                                accent = value
                            } else if parts[0] == "OMACOSY_IS_DARK" {
                                resolved = value == "1" ? "dark" : "light"
                            }
                        }
                    }
                    try? FileManager.default.removeItem(atPath: envFile)
                    let colors = (0..<16).compactMap { byIndex[$0] }
                    if colors.count == 16 {
                        DispatchQueue.main.async {
                            self.model.seedDraft(image: wallpaper, colors: colors,
                                                 accent: accent, resolved: resolved)
                        }
                        return
                    }
                }
                // Fallback: a fresh extraction; the two calls run in parallel.
                let lock = NSLock()
                var colors: [String] = []
                var roles: [String: Any] = [:]
                let group = DispatchGroup()
                group.enter()
                DispatchQueue.global().async {
                    let (c, o) = shell("\(themecoreBin()) palette magic \(q) --json 2>/dev/null")
                    if c == 0, let d = o.data(using: .utf8),
                       let obj = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] {
                        lock.lock(); colors = obj["colors"] as? [String] ?? []; lock.unlock()
                    }
                    group.leave()
                }
                group.enter()
                DispatchQueue.global().async {
                    let (c, o) = shell("\(themecoreBin()) palette magic \(q) --roles --json 2>/dev/null")
                    if c == 0, let d = o.data(using: .utf8),
                       let obj = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] {
                        lock.lock(); roles = obj; lock.unlock()
                    }
                    group.leave()
                }
                group.wait()
                lock.lock()
                let finalColors = colors
                let accent = roles["accent"] as? String
                let resolved = (roles["ladder"] as? String) == "light" ? "light" : "dark"
                lock.unlock()
                DispatchQueue.main.async {
                    guard finalColors.count == 16 else { return }
                    self.model.seedDraft(image: wallpaper, colors: finalColors,
                                         accent: accent, resolved: resolved)
                }
            }
        }
    }

    private func close() {
        guard ThemeEditor.current === self else { return }
        ThemeEditor.current = nil
        if let k = keyMonitor { NSEvent.removeMonitor(k); keyMonitor = nil }
        model.teardown()
        if let dash = window.parent as? DashboardWindow {
            dash.hideSuppressed = false
            dash.removeChildWindow(window)
            NSApp.activate(ignoringOtherApps: true)
            dash.makeKeyAndOrderFront(nil)
            if let root = dash.contentView { dash.makeFirstResponder(root) }
        }
        window.orderOut(nil)
    }
}

// --- storage tab -----------------------------------------------------------

// where the local wallpapers folder is set and fed
final class StorageTabView: NSView {
    private let browseButton = ButtonView()
    private let addButton = ButtonView()
    private let chooseButton = ButtonView()
    private var dir = ""
    private var status = ""
    // three buttons right-aligned as one group; every text button in the
    // dashboard shares one compact size (96×24, font 12 — the chips and
    // segmented controls' scale), the folder glyph keeps its icon width
    private let chooseW: CGFloat = 96
    private let addW: CGFloat = 96
    private let folderW: CGFloat = 26
    private let gap: CGFloat = 6

    func refreshColors() {
        browseButton.needsDisplay = true
        addButton.needsDisplay = true
        chooseButton.needsDisplay = true
        needsDisplay = true
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        browseButton.title = "\u{f07b}"
        // an icon glyph, not text: centre it on its own box, not cap height
        browseButton.centeredByBounds = true
        browseButton.fontSize = 12
        browseButton.toolTip = "Open the Wallpaper Folder"
        browseButton.onClick = { [weak self] in
            guard let d = self?.dir, !d.isEmpty else { return }
            NSWorkspace.shared.open(URL(fileURLWithPath: d))
        }
        addButton.title = "Add Images"
        addButton.onClick = { [weak self] in self?.addFiles() }
        chooseButton.title = "Set Folder"
        chooseButton.toolTip = "Change the Wallpaper Folder"
        chooseButton.onClick = { [weak self] in self?.chooseDirectory() }
        addSubview(browseButton)
        addSubview(addButton)
        addSubview(chooseButton)
        reload()
    }
    required init?(coder: NSCoder) { fatalError("not used") }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil { reload() }
    }

    // the folder is the CLI's answer, so the path shown and the path
    // omacosy-custom-theme writes to can never disagree
    func reload() {
        dir = wallpapersDir()
        needsDisplay = true
    }

    override func layout() {
        super.layout()
        let y = bounds.height - 28
        chooseButton.frame = NSRect(x: bounds.width - chooseW, y: y, width: chooseW, height: 24)
        addButton.frame = NSRect(x: chooseButton.frame.minX - gap - addW, y: y, width: addW, height: 24)
        browseButton.frame = NSRect(x: addButton.frame.minX - gap - folderW, y: y, width: folderW, height: 24)
    }

    override func draw(_ dirtyRect: NSRect) {
        // the Themes tab's Custom Themes header, verbatim: label, path and
        // the buttons centre on one line
        let mid = browseButton.frame.midY
        drawMidLeft("Local Wallpapers", nerdFont("Bold", 13), palette.accent,
                    x: 0, midTop: bounds.height - mid, height: bounds.height)
        let tw = advance("Local Wallpapers", nerdFont("Bold", 13)) + 14
        // the folder we ship with is marked, so it is clear the path was
        // set for the user and can be changed with Set Folder
        let marker = dir == HOME + "/Pictures/wallpapers" ? " (default)" : ""
        let markerW = marker.isEmpty ? 0 : advance(marker, nerdFont("Regular", 11))
        let pathW = max(80, browseButton.frame.minX - tw - 16 - markerW)
        drawMidLeft(truncate(dir, nerdFont("Regular", 11), pathW) + marker,
                    nerdFont("Regular", 11), palette.muted,
                    x: tw, midTop: bounds.height - mid, height: bounds.height)
        if !status.isEmpty {
            drawTopLeft(truncate(status, nerdFont("Regular", 11), bounds.width),
                        nerdFont("Regular", 11), palette.muted,
                        x: 0, top: 44, height: bounds.height)
        }
    }

    // Images picked from anywhere — a USB key, a NAS, another folder — are
    // copied into the configured folder (never moved), so they become the
    // next Wallpaper #N in Themes without extra steps.
    private func addFiles() {
        guard let dash = window as? DashboardWindow else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Add"
        panel.allowedContentTypes = [.image]
        // as a sheet the panel can never fall behind the popUpMenu-level
        // dashboard card, which a runModal panel does
        dash.hideSuppressed = true
        panel.beginSheetModal(for: dash) { [weak self] resp in
            dash.hideSuppressed = false
            guard let self, resp == .OK else { return }
            let sources = panel.urls.map { $0.path }
            guard !sources.isEmpty else { return }
            self.status = "Adding…"
            self.needsDisplay = true
            let dest = self.dir
            DispatchQueue.global().async {
                var added = 0, skipped = 0, failed = 0
                for s in sources {
                    switch importWallpaper(s, into: dest) {
                    case .added: added += 1
                    case .skipped: skipped += 1
                    case .failed: failed += 1
                    }
                }
                DispatchQueue.main.async {
                    var parts: [String] = []
                    if added > 0 { parts.append("\(added) added") }
                    if skipped > 0 { parts.append("\(skipped) already in the folder") }
                    if failed > 0 { parts.append("\(failed) could not be copied") }
                    self.status = parts.joined(separator: ", ")
                    self.needsDisplay = true
                }
            }
        }
    }

    private func chooseDirectory() {
        guard let dash = window as? DashboardWindow else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Use This Folder"
        // as a sheet the panel can never fall behind the popUpMenu-level
        // dashboard card, which a runModal panel does
        dash.hideSuppressed = true
        panel.beginSheetModal(for: dash) { [weak self] resp in
            dash.hideSuppressed = false
            guard resp == .OK, let url = panel.url else { return }
            _ = shell("\(HOME)/.local/bin/omacosy-custom-theme path \(shellQuote(url.path))")
            self?.reload()
        }
    }
}

// --- api keys tab ----------------------------------------------------------

final class APIKeysTabView: NSView, NSTextFieldDelegate {
    private let field = NSSecureTextField()
    private let plainField = NSTextField()
    private let eyeButton = ButtonView()
    private var revealed = false
    private var pendingSave: DispatchWorkItem?
    // matches the compact buttons, so the box and the eye line up
    private let boxH: CGFloat = 24
    // the field itself is only as tall as its text: AppKit draws the value
    // near the top of a taller field, which read as uncentred. The visible
    // box is drawn around it, the text can't drift.
    private let fieldH: CGFloat = 16
    private var status = ""

    func refreshColors() {
        field.textColor = palette.label
        field.backgroundColor = palette.itemBG.withAlphaComponent(0.35)
        plainField.textColor = palette.label
        plainField.backgroundColor = palette.itemBG.withAlphaComponent(0.35)
        eyeButton.needsDisplay = true
        needsDisplay = true
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        for f in [field, plainField] {
            f.isBezeled = false
            f.drawsBackground = true
            f.backgroundColor = palette.itemBG.withAlphaComponent(0.35)
            f.textColor = palette.label
            f.font = nerdFont("Regular", 12)
            f.focusRingType = .none
            f.delegate = self
            f.target = self
            f.action = #selector(persistNow)
            addSubview(f)
        }
        plainField.isHidden = true
        eyeButton.title = "\u{f070}"
        eyeButton.centeredByBounds = true
        eyeButton.fontSize = 12
        eyeButton.toolTip = "Show the Key"
        eyeButton.onClick = { [weak self] in self?.toggleReveal() }
        addSubview(eyeButton)
        let key = readSecret("wallhaven")
        field.stringValue = key
        plainField.stringValue = key
    }
    required init?(coder: NSCoder) { fatalError("not used") }

    // the native placeholder sat high in the taller field; this draws it on
    // the same mid line as the value so an empty field reads centred
    func controlTextDidChange(_ obj: Notification) {
        if let src = obj.object as? NSTextField {
            let other: NSTextField = src === field ? plainField : field
            if other.stringValue != src.stringValue { other.stringValue = src.stringValue }
        }
        scheduleSave()
        needsDisplay = true
    }

    private var activeField: NSTextField { revealed ? plainField : field }

    // one field is always hidden; the eye swaps which, keeping the text
    private func toggleReveal() {
        revealed.toggle()
        let value = activeField.stringValue
        field.stringValue = value
        plainField.stringValue = value
        field.isHidden = revealed
        plainField.isHidden = !revealed
        eyeButton.title = revealed ? "\u{f06e}" : "\u{f070}"
        eyeButton.toolTip = revealed ? "Hide the Key" : "Show the Key"
        window?.makeFirstResponder(activeField)
        if let editor = activeField.currentEditor() {
            editor.selectedRange = NSRange(location: (value as NSString).length, length: 0)
        }
        needsDisplay = true
    }

    override func layout() {
        super.layout()
        let w = min(420, max(160, bounds.width - 60))
        let boxY = bounds.height - 52 - boxH
        field.frame = NSRect(x: 0, y: boxY + (boxH - fieldH) / 2, width: w, height: fieldH)
        plainField.frame = field.frame
        eyeButton.frame = NSRect(x: w + 12, y: boxY, width: 26, height: 24)
    }

    override func draw(_ dirtyRect: NSRect) {
        drawTopLeft("Wallhaven.cc API Key", nerdFont("Bold", 13), palette.accent,
                    x: 0, top: 0, height: bounds.height)
        drawTopLeft(truncate("Optional: Create an account and go to https://wallhaven.cc/settings/account to get your API Key. Needed for NSFW content.",
                             nerdFont("Regular", 11), bounds.width),
                    nerdFont("Regular", 11), palette.muted, x: 0, top: 22, height: bounds.height)
        let box = NSRect(x: field.frame.minX - 0.5,
                         y: field.frame.minY - (boxH - fieldH) / 2 - 0.5,
                         width: field.frame.width + 1, height: boxH + 1)
        let border = NSBezierPath(roundedRect: box, xRadius: 6, yRadius: 6)
        palette.muted.withAlphaComponent(0.35).setStroke()
        border.lineWidth = 1
        border.stroke()
        if field.stringValue.isEmpty {
            drawMidLeft("Paste your key", nerdFont("Regular", 12), palette.muted,
                        x: field.frame.minX + 6,
                        midTop: bounds.height - field.frame.midY, height: bounds.height)
        }
        if !status.isEmpty {
            drawTopLeft(status, nerdFont("Regular", 11), palette.muted,
                        x: 0, top: 90, height: bounds.height)
        }
    }

    // the key saves itself; a failed write is the only thing worth saying
    private func scheduleSave() {
        pendingSave?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.persistKey() }
        pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    @objc private func persistNow() { pendingSave?.cancel(); persistKey() }

    private func persistKey() {
        let value = field.stringValue.replacingOccurrences(of: "\n", with: "")
        if writeSecret("wallhaven", value) {
            field.stringValue = value
            plainField.stringValue = value
            status = ""
        } else {
            status = "Could not save the key"
        }
        needsDisplay = true
    }
}

// --- update tab ------------------------------------------------------------

final class UpdateTabView: NSView {
    private var stateText = "Checking for updates…"
    private var detail = ""
    private var warning = "Installing an update reloads Omacosy for a short moment."
    private let lineH: CGFloat = 24
    private var hasUpdate = false
    private var busy = false
    private var upToDate = false
    private let installButton = ButtonView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        installButton.title = "Install Update"
        installButton.onClick = { [weak self] in self?.install() }
        installButton.isHidden = true
        addSubview(installButton)
    }
    required init?(coder: NSCoder) { fatalError("not used") }
    func refreshColors() { needsDisplay = true; installButton.needsDisplay = true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // check whenever the tab is shown, unless one is already running
        if window != nil, !busy { check() }
    }

    // the update script prints ANSI-coloured "==> ..." messages and an
    // indented list of commits. Keep the one line a reader can use: strip the
    // colour, strip a leading "==> ", drop the chatter, and take what is left
    // (the newest commit subject on an update, the reason on a failure).
    private func infoLine(_ s: String) -> String {
        let noANSI = s.replacingOccurrences(of: "\u{1B}\\[[0-9;]*[A-Za-z]",
                                            with: "", options: .regularExpression)
        return noANSI.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .map { $0.hasPrefix("==>") ? String($0.dropFirst(3)).trimmingCharacters(in: .whitespaces) : $0 }
            .filter { !$0.isEmpty }
            .filter { !$0.hasPrefix("checking for updates") && !$0.hasPrefix("already up to date")
                      && !$0.hasPrefix("run without --check") && !$0.hasPrefix("pulling") }
            .last ?? ""
    }

    private func check() {
        stateText = "Checking for updates…"
        detail = ""
        hasUpdate = false
        upToDate = false
        installButton.isHidden = true
        needsDisplay = true
        DispatchQueue.global().async { [weak self] in
            let (code, out) = shell("\(HOME)/.local/bin/omacosy-update --check 2>&1")
            DispatchQueue.main.async {
                guard let self else { return }
                if code != 0 {
                    self.stateText = "Could not check for updates"
                    self.detail = self.infoLine(out)
                    self.hasUpdate = false
                } else if out.contains("new commit") {
                    self.stateText = "Update available"
                    self.detail = self.infoLine(out)
                    self.hasUpdate = true
                } else {
                    self.stateText = "Omacosy is up to date"
                    self.detail = self.infoLine(out)
                    self.upToDate = true
                }
                self.installButton.isHidden = !self.hasUpdate
                self.needsLayout = true
                self.needsDisplay = true
            }
        }
    }

    private func install() {
        busy = true
        hasUpdate = false
        upToDate = false
        installButton.isHidden = true
        stateText = "Updating…"
        detail = "Omacosy will reload in a moment; the window may flicker."
        needsDisplay = true
        DispatchQueue.global().async { [weak self] in
            let (code, out) = shell("\(HOME)/.local/bin/omacosy-update 2>&1")
            DispatchQueue.main.async {
                guard let self else { return }
                self.busy = false
                if code != 0 {
                    self.stateText = "Update failed"
                    self.detail = self.infoLine(out)
                } else {
                    self.stateText = "Updated"
                    self.detail = ""
                }
                self.installButton.isHidden = true
                self.needsLayout = true
                self.needsDisplay = true
            }
        }
    }

    // the visible lines, top to bottom; the button (when shown) sits above
    // them. Kept in one place so layout and draw agree on the block height.
    private func stackLines() -> [(String, NSFont, NSColor)] {
        var lines: [(String, NSFont, NSColor)] = [
            (stateText, nerdFont("Bold", 15), palette.accent)
        ]
        if !detail.isEmpty {
            lines.append((truncate(detail, nerdFont("Regular", 11), bounds.width - 40),
                          nerdFont("Regular", 11), palette.muted))
        }
        if hasUpdate {
            lines.append((warning, nerdFont("Regular", 11), palette.muted))
        } else if upToDate {
            lines.append(("Checked against the origin of this clone.",
                          nerdFont("Regular", 11), palette.muted))
        }
        return lines
    }

    private func blockHeight() -> CGFloat {
        CGFloat(stackLines().count) * lineH + (installButton.isHidden ? 0 : 24 + 14)
    }

    override func layout() {
        super.layout()
        var top = (bounds.height - blockHeight()) / 2
        if !installButton.isHidden {
            installButton.frame = NSRect(x: (bounds.width - 160) / 2,
                                         y: bounds.height - top - 24, width: 96, height: 24)
            top += 24 + 14
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        var top = (bounds.height - blockHeight()) / 2
        if !installButton.isHidden { top += 24 + 14 }
        for (text, font, color) in stackLines() {
            drawMidCenter(text, font, color, centerX: bounds.midX,
                          midTop: top + lineH / 2, height: bounds.height)
            top += lineH
        }
    }
}

// --- window / root ---------------------------------------------------------

final class DashboardWindow: NSWindow {
    // fires for every left click the window receives, before dispatch. Used
    // to fold an expanded workspace row back on a click anywhere else.
    var onMouseDown: ((NSEvent) -> Void)?
    // set while a system open panel is attached as a sheet: clicks in that
    // window must not be mistaken for a click outside the dashboard
    var hideSuppressed = false
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
    override var canBecomeKey: Bool { true }
    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown { onMouseDown?(event) }
        super.sendEvent(event)
    }
}

protocol RefreshableTab: AnyObject {
    func refreshColors()
}

extension OptionsTabView: RefreshableTab {}
extension WorkspacesTabView: RefreshableTab {}
extension ThemesTabView: RefreshableTab {}
// --- wallpapers tab --------------------------------------------------------

// wallhaven.cc browsing lands here (Phase 7): search row, chips and the
// results grid. Local files are never previewed in this tab — they are
// sourced from the Storage tab and appear as Wallpaper #N in Themes.
final class WallpapersTabView: NSView {}

extension StorageTabView: RefreshableTab {}
extension APIKeysTabView: RefreshableTab {}
extension UpdateTabView: RefreshableTab {}

final class RootView: NSView {
    let tabs = ["Options", "Workspaces", "Themes", "Wallpapers", "Storage", "API Keys", "Update"]
    var selected = 0
    private var logo: NSImage?
    private let logoView = NSImageView()
    private let options = OptionsTabView(frame: .zero)
    private let workspaces = WorkspacesTabView(frame: .zero)
    private let themes = ThemesTabView(frame: .zero)
    private let wallpapers = WallpapersTabView(frame: .zero)
    private let storage = StorageTabView(frame: .zero)
    private let keys = APIKeysTabView(frame: .zero)
    private let update = UpdateTabView(frame: .zero)
    private lazy var tabViews: [NSView] = [options, workspaces, themes, wallpapers, storage, keys, update]
    var onHide: (() -> Void)?

    private let logoH: CGFloat = 34
    private let topPad: CGFloat = 16
    private let tabH: CGFloat = 40
    private let pad: CGFloat = 20

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        logoView.imageScaling = .scaleProportionallyUpOrDown
        addSubview(logoView)
        addSubview(options)
        options.onApplied = { [weak self] in self?.needsDisplay = true }
        themes.onApplied = { [weak self] in self?.paletteChanged() }
        reloadLogo()
    }

    // A theme switch swaps the palette under the whole modal. Every surface
    // draws its own colour, so each has to be told to repaint: the tab view,
    // its document/list subviews and the custom scroller. Left alone they keep
    // the old theme until the next scroll or hover.
    func paletteChanged() {
        palette = loadPalette()
        reloadLogo()
        for v in tabViews { (v as? RefreshableTab)?.refreshColors() }
        ThemeEditor.refreshColors()
        needsDisplay = true
    }
    required init?(coder: NSCoder) { fatalError("not used") }

    func reloadLogo() {
        logo = logoImage()
        logoView.image = logo
        needsDisplay = true
        for v in tabViews { v.needsDisplay = true }
    }

    private var tabTop: CGFloat { topPad + logoH + 24 }
    private var contentTop: CGFloat { tabTop + tabH + 10 }
    private var contentFrame: NSRect {
        NSRect(x: pad, y: pad, width: bounds.width - pad * 2,
               height: bounds.height - contentTop - pad)
    }

    // every open starts from the saved state, not from edits left over from
    // a previous visit
    func resetTabsOnShow() {
        workspaces.resetToSaved()
    }

    // the window forwards every left click here before dispatch
    func mouseDownAnywhere(_ e: NSEvent) {
        workspaces.collapseIfClickOutside(e)
    }

    func showTab(_ i: Int) {
        selected = i
        for v in tabViews { v.removeFromSuperview() }
        let v = tabViews[i]
        v.frame = contentFrame
        addSubview(v)
        // a tab holding a text field may have made it first responder; the
        // arrows and Esc have to keep reaching this view after a switch
        window?.makeFirstResponder(self)
        needsDisplay = true
    }

    override func layout() {
        super.layout()
        if let logo {
            let aspect = logo.size.width / max(logo.size.height, 1)
            let w = logoH * aspect
            // centred between the card's top edge and the tabs' top edge
            logoView.frame = NSRect(x: bounds.midX - w / 2,
                                    y: bounds.height - (tabTop + logoH) / 2,
                                    width: w, height: logoH)
        }
        for v in tabViews { v.frame = contentFrame }
    }

    private func tabFrame(_ i: Int) -> NSRect {
        let f = nerdFont("Bold", 13)
        var widths: [CGFloat] = []
        for t in tabs { widths.append(advance(t, f) + 34) }
        let total = widths.reduce(0, +)
        var x = (bounds.width - total) / 2
        for (j, w) in widths.enumerated() {
            if j == i {
                return NSRect(x: x, y: bounds.height - tabTop - tabH + 6, width: w, height: tabH)
            }
            x += w
        }
        return .zero
    }

    override func draw(_ dirtyRect: NSRect) {
        let corner = min(windowCornerRadius(10), min(bounds.width, bounds.height) / 2)
        let body = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: corner, yRadius: corner)
        palette.barBG.setFill()
        body.fill()
        palette.accent.setStroke()
        body.lineWidth = 1
        body.stroke()

        // tab strip
        var x = (bounds.width - tabsWidth()) / 2
        let f = nerdFont("Bold", 13)
        for (i, t) in tabs.enumerated() {
            let w = advance(t, f) + 34
            let mid = bounds.height - (tabTop + tabH / 2)
            drawMidCenter(t, f, i == selected ? palette.accent : palette.label,
                          centerX: x + w / 2, midTop: tabTop + tabH / 2, height: bounds.height)
            if i == selected {
                palette.accent.setFill()
                NSRect(x: x + 10, y: mid - 15, width: w - 20, height: 2).fill()
            }
            x += w
        }
    }

    private func tabsWidth() -> CGFloat {
        let f = nerdFont("Bold", 13)
        return tabs.reduce(0) { $0 + advance($1, f) + 34 }
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let f = nerdFont("Bold", 13)
        var x = (bounds.width - tabsWidth()) / 2
        for (i, t) in tabs.enumerated() {
            let w = advance(t, f) + 34
            let rect = NSRect(x: x, y: bounds.height - tabTop - tabH, width: w, height: tabH)
            if rect.contains(p) { showTab(i); return }
            x += w
        }
        onHide?()
    }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    private var activeTab: NSView { tabViews[selected] }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: onHide?()
        case 43 where event.modifierFlags.contains([.command, .control, .option]): onHide?()
        case 126: (activeTab as? ScrollStepTab)?.scrollStep(-48)   // up
        case 125: (activeTab as? ScrollStepTab)?.scrollStep(48)    // down
        case 123: showTab((selected + tabs.count - 1) % tabs.count) // left
        case 124: showTab((selected + 1) % tabs.count)              // right
        default: break
        }
    }
}

// --- app -------------------------------------------------------------------

final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: DashboardWindow?
    var root: RootView?
    var globalMonitor: Any?
    var localKeyMonitor: Any?
    let width: CGFloat = 860
    let height: CGFloat = 720

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        // An accessory app has no visible menu bar, but key equivalents are
        // dispatched through the main menu: without an Edit menu, Cmd+V/C/X/A
        // do nothing and only the field's context menu offers paste.
        let main = NSMenu()
        let editItem = NSMenuItem()
        main.addItem(editItem)
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "Z"))
        edit.addItem(NSMenuItem.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        NSApplication.shared.mainMenu = main

        let root = RootView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        root.onHide = { [weak self] in self?.hide() }
        self.root = root

        let w = DashboardWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: height),
                                styleMask: .borderless, backing: .buffered, defer: false)
        w.isOpaque = false
        w.backgroundColor = .clear
        w.hasShadow = true
        w.level = .popUpMenu
        w.acceptsMouseMovedEvents = true
        w.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        w.contentView = root
        w.onMouseDown = { [weak self] e in self?.root?.mouseDownAnywhere(e) }
        window = w

        let pid = HOME + "/.local/state/omacosy/dashboard.pid"
        try? "\(ProcessInfo.processInfo.processIdentifier)\n"
            .write(toFile: pid, atomically: true, encoding: .utf8)

        watch("/tmp/omacosy-dashboard", create: true) { [weak self] in self?.toggle() }
        watch(HOME + "/.config/omarchy/current") { [weak self] in
            self?.root?.paletteChanged()
        }
        show()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func show() {
        guard let w = window else { return }
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main!
        w.setFrame(NSRect(x: screen.frame.midX - width / 2,
                          y: screen.frame.midY - height / 2,
                          width: width, height: height), display: true)
        NSApp.activate(ignoringOtherApps: true)
        if let root { root.resetTabsOnShow() }
        w.makeKeyAndOrderFront(nil)
        if let root { w.makeFirstResponder(root) }
        // AeroSpace hands the window to the screen without making it key, so
        // the first keystroke — Escape — has nowhere to go until a click. Ask
        // for focus again one tick later, once the window server has settled.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            guard let w = self?.window, w.isVisible else { return }
            NSApp.activate(ignoringOtherApps: true)
            w.makeKeyAndOrderFront(nil)
            if let root = self?.root { w.makeFirstResponder(root) }
        }
        if globalMonitor == nil {
            globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                // an NSOpenPanel is a window from a system helper process, so
                // its clicks reach this monitor as "another app"; while such a
                // sheet is up, its clicks must not hide the dashboard
                guard let self, self.window?.hideSuppressed != true else { return }
                self.hide()
            }
        }
        if localKeyMonitor == nil {
            // Esc closes the dashboard even while a text field is editing,
            // where the field editor swallows it before the responder chain.
            // A local monitor sees the event first, like the picker's does.
            localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] e in
                guard let self else { return e }
                // a live Theme Editor owns the session: Esc closes it and
                // returns to Themes, never the dashboard under it
                if e.keyCode == 53, e.window === self.window, ThemeEditor.closeIfOpen() { return nil }
                guard self.window?.hideSuppressed != true else { return e }
                // only Esc aimed at the dashboard: while the app picker is
                // up it is the key window and handles its own Esc
                if e.keyCode == 53, e.window === self.window { self.hide(); return nil }
                return e
            }
        }
    }

    func hide() {
        // a live Theme Editor owns the session: outside clicks and the
        // toggle key must not dismiss the dashboard until it is closed
        guard window?.hideSuppressed != true else { return }
        AppPicker.dismiss()
        window?.hideSuppressed = false
        window?.orderOut(nil)
        if let g = globalMonitor { NSEvent.removeMonitor(g); globalMonitor = nil }
        if let k = localKeyMonitor { NSEvent.removeMonitor(k); localKeyMonitor = nil }
    }

    func toggle() {
        if window?.isVisible == true { hide() } else { show() }
    }
}

// create makes the trigger if it is missing. Without it the retry below runs
// every 2 s for as long as the file is absent, and /tmp is emptied on reboot —
// so a fresh session would tick every two seconds until the shortcut was
// pressed again. The bar's own watcher creates its trigger for the same reason.
func watch(_ path: String, create: Bool = false, _ handler: @escaping () -> Void) {
    if create, !FileManager.default.fileExists(atPath: path) {
        FileManager.default.createFile(atPath: path, contents: nil)
    }
    let fd = open(path, O_EVTONLY)
    guard fd >= 0 else {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { watch(path, create: create, handler) }
        return
    }
    let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd,
        eventMask: [.write, .attrib, .delete, .rename], queue: .main)
    src.setEventHandler {
        let ev = src.data
        handler()
        if ev.contains(.delete) || ev.contains(.rename) { src.cancel() }
    }
    src.setCancelHandler {
        close(fd)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { watch(path, create: create, handler) }
    }
    src.resume()
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
