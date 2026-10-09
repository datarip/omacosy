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
enum AutoThemeMode: Int { case off = 0, desktopOnly = 1, on = 2 }

struct DashboardState {
    var wm: WindowManager = .aerospace
    var corners: CornerMode = .rounded
    var bar: BarMode = .visible
    var fullscreen: Bool = false
    var autoTheme: AutoThemeMode = .off
}

let SETTINGS = HOME + "/.config/omacosy/settings.conf"
let BARCONF = HOME + "/.config/omacosy/bar.conf"
let AUTOCONF = HOME + "/.config/omacosy/auto-theme.conf"

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

    if (readConfKey(AUTOCONF, "auto-theme") ?? "off") == "on" {
        s.autoTheme = (readConfKey(AUTOCONF, "apps") ?? "on") == "off" ? .desktopOnly : .on
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
    var fontSize: CGFloat = 13
    // icon buttons centre on the glyph's own box; text buttons centre on cap
    // height, which reads better for words
    var centeredByBounds = false
    var busy = false { didSet { needsDisplay = true } }
    var onClick: (() -> Void)?

    override func draw(_ dirtyRect: NSRect) {
        let r = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6)
        (busy ? palette.muted : palette.accent).setFill()
        r.fill()
        let text = busy ? "Saving…" : title
        let font = nerdFont("Bold", fontSize)
        if centeredByBounds {
            // centre on the glyph's ink, not its line box: nerd-font icons
            // carry odd metrics and drift high/left in a line-box centre
            guard let ctx = NSGraphicsContext.current?.cgContext else { return }
            let line = textLine(text, font, palette.barBG)
            let ink = CTLineGetImageBounds(line, ctx)
            ctx.textPosition = CGPoint(x: bounds.midX - ink.midX,
                                       y: bounds.midY - ink.midY)
            CTLineDraw(line, ctx)
        } else {
            drawMidCenter(text, font, palette.barBG,
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
        let atSeg = makeSeg(["Off", "Desktop Only", "On"], original.autoTheme.rawValue)

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
            OptionRow(category: "Themes", title: "Auto-Theme Mode",
                      desc: "Derive colours from your own wallpapers, custom themes included.", seg: atSeg),
        ]
        doc.rows = rows
        for r in rows { doc.addSubview(r.seg) }
    }

    override func layout() {
        super.layout()
        let saveW: CGFloat = 110, saveH: CGFloat = 32
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
        let autoTheme = AutoThemeMode(rawValue: rows[4].seg.index) ?? original.autoTheme

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
        if autoTheme != original.autoTheme {
            let v = ["off", "on desktop-only", "on"][autoTheme.rawValue]
            steps.append("\(HOME)/.local/bin/omacosy-auto-theme \(v)")
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
    private let addW: CGFloat = 86

    init(ws: String, assigned: [String], allApps: [AppInfo]) {
        self.ws = ws
        self.assigned = assigned
        self.allApps = allApps
        self.chipStrip = ChipStrip(allApps: allApps)
        super.init(frame: .zero)
        addButton.title = "＋ Add App"
        addButton.fontSize = 12
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
                                      width: max(0, bounds.width - stripX - 96 - 8),
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
        let saveW: CGFloat = 110, saveH: CGFloat = 32
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

func customWallpaperDir() -> String? {
    let (code, out) = shell("\(HOME)/.local/bin/omacosy-custom-theme dir 2>/dev/null")
    let d = out.trimmingCharacters(in: .whitespacesAndNewlines)
    return (code == 0 && !d.isEmpty) ? d : nil
}

func customVariants() -> [ThemeCell] {
    guard (readConfKey(AUTOCONF, "auto-theme") ?? "off") == "on", let dir = customWallpaperDir() else { return [] }
    let files = ((try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? [])
        .filter { isImageFile($0) }.sorted()
    return files.enumerated().map { i, f in
        ThemeCell(logical: "custom", wallpaper: dir + "/" + f,
                  title: "Custom #\(i + 1)", isCustom: true, paletteFile: "")
    }
}

// --- wallpapers tab data ---------------------------------------------------

// The configured folder, read from the CLI so the dashboard and
// `omacosy-custom-theme status` can never disagree. status prints the path
// even while auto-theme is off, which is what lets this tab work before the
// feature is switched on.
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
    let (code, out) = shell("\(HOME)/.local/bin/omacosy-custom-theme theme \(shellQuote(wallpaper)) 2>/dev/null")
    guard code == 0 else { return [] }
    let dir = out.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "\n").last.map(String.init) ?? ""
    guard !dir.isEmpty else { return [] }
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
    let cmd = "\(HOME)/.local/bin/omacosy-theme-switch set \(c.logical) \(shellQuote(c.wallpaper))"
    DispatchQueue.global().async {
        _ = shell(cmd)
        DispatchQueue.main.async { done() }
    }
}

final class ThemeGridView: NSView {
    var cells: [ThemeCell] = []
    var customDir: String?
    var isCustomOn = false
    var thumbs: [Int: NSImage] = [:]
    var palettes: [Int: [NSColor]] = [:]
    var pending: Set<Int> = []
    var cellFrames: [Int: NSRect] = [:]
    var headers: [(NSRect, String)] = []
    var lockedMessageRect = NSRect.zero
    var onApplied: ((String) -> Void)?
    private var hoveredIndex: Int?
    private var hoverTracking: NSTrackingArea?

    private var customHeaderRect = NSRect.zero
    private var separatorRect = NSRect.zero
    private let headerH: CGFloat = 34
    private let cellH: CGFloat = 180
    private let gapX: CGFloat = 14
    private let gapY: CGFloat = 16

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

        // custom section
        let customIdx = cells.enumerated().filter { $0.element.isCustom }.map { $0.offset }
        if isCustomOn {
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
        } else {
            lockedMessageRect = NSRect(x: 0, y: top, width: W, height: 44)
            top += 44
        }

        // convert top-coords to non-flipped bottom coords
        let contentH = max(top + 8, 200)
        func flip(_ r: NSRect) -> NSRect {
            NSRect(x: r.origin.x, y: contentH - r.origin.y - r.height, width: r.width, height: r.height)
        }
        for (k, v) in cellFrames { cellFrames[k] = flip(v) }
        headers = headers.map { (flip($0.0), $0.1) }
        if !isCustomOn { lockedMessageRect = flip(lockedMessageRect) }
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
            if c.isCustom { pal = customPalette(c.wallpaper) }
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
        if !isCustomOn {
            drawTopLeft("Turn on Auto-Theme to preview your wallpapers",
                        nerdFont("Regular", 12), palette.muted,
                        x: 0, top: bounds.height - lockedMessageRect.maxY + 8, height: bounds.height)
        }
        if isCustomOn {
            palette.muted.withAlphaComponent(0.25).setFill()
            separatorRect.fill()
        }
        for (i, f) in cellFrames {
            drawCell(i, f)
        }
    }

    private func drawCell(_ i: Int, _ f: NSRect) {
        let paletteH: CGFloat = 12
        let labelH: CGFloat = 18
        // leave room under the thumbnail for the hover ring (2 px) plus air
        // before the theme name
        let thumbGap: CGFloat = 12
        let thumbRect = NSRect(x: f.minX, y: f.minY + paletteH + labelH + thumbGap,
                               width: f.width, height: f.height - paletteH - labelH - thumbGap)
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

        let title = truncate(cells[i].title, nerdFont("Regular", 11), f.width)
        drawTopLeft(title, nerdFont("Regular", 11), palette.label,
                    x: f.minX, top: bounds.height - (f.minY + paletteH + labelH), height: bounds.height)

        // palette strip along the bottom
        let colors = palettes[i] ?? []
        if !colors.isEmpty {
            let sw = f.width / CGFloat(colors.count)
            for (j, col) in colors.enumerated() {
                col.setFill()
                NSRect(x: f.minX + CGFloat(j) * sw, y: f.minY, width: sw + 0.5, height: paletteH).fill()
            }
        } else {
            palette.itemBG.withAlphaComponent(0.5).setFill()
            NSRect(x: f.minX, y: f.minY, width: f.width, height: paletteH).fill()
        }
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
            let frame = f
            // brief highlight
            _ = frame
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
        paths.append(HOME + "/.config/omacosy/themes.conf")
        for p in paths where !watchedPaths.contains(p) {
            watchedPaths.append(p)
            watch(p) { [weak self] in self?.reload() }
        }
    }

    @objc private func visibleChanged() { grid.loadVisible(scroll.documentVisibleRect); scroller.refresh() }

    func reload() {
        let cells = stockVariants() + customVariants()
        let dir = customWallpaperDir()
        let isOn = (readConfKey(AUTOCONF, "auto-theme") ?? "off") == "on"

        // Re-entering the tab re-reads the shelves. When nothing changed,
        // leave the decoded thumbnails and palettes exactly as they are:
        // clearing them repaints a grid of "loading…" placeholders for a
        // frame, which reads as a flicker when the gallery is already at
        // the top and no scroll motion hides it.
        if cells == grid.cells, dir == grid.customDir, isOn == grid.isCustomOn {
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
        grid.isCustomOn = isOn

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

// --- storage tab -----------------------------------------------------------

// where the local wallpapers folder is set and fed
final class StorageTabView: NSView {
    private let browseButton = ButtonView()
    private let addButton = ButtonView()
    private let chooseButton = ButtonView()
    private var dir = ""
    private var status = ""
    // three buttons right-aligned as one group, in the compact size the
    // Options/Workspaces "Add App" buttons use: font 12, 24 high
    private let chooseW: CGFloat = 86
    private let addW: CGFloat = 86
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
        addButton.fontSize = 12
        addButton.onClick = { [weak self] in self?.addFiles() }
        chooseButton.title = "Set Folder"
        chooseButton.fontSize = 12
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
        CGFloat(stackLines().count) * lineH + (installButton.isHidden ? 0 : 34 + 14)
    }

    override func layout() {
        super.layout()
        var top = (bounds.height - blockHeight()) / 2
        if !installButton.isHidden {
            installButton.frame = NSRect(x: (bounds.width - 160) / 2,
                                         y: bounds.height - top - 34, width: 160, height: 34)
            top += 34 + 14
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        var top = (bounds.height - blockHeight()) / 2
        if !installButton.isHidden { top += 34 + 14 }
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
                guard let self, self.window?.hideSuppressed != true else { return e }
                // only Esc aimed at the dashboard: while the app picker is
                // up it is the key window and handles its own Esc
                if e.keyCode == 53, e.window === self.window { self.hide(); return nil }
                return e
            }
        }
    }

    func hide() {
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
