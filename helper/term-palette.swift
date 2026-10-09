// term-palette.swift — a terminal palette for the theme on screen.
//
//   omacosy-term-palette <theme-dir> <out.env> [<label>] [--preview <png>]
//
// A THEME DIRECTORY, not an image: this runs on whatever theme-set just put on
// ~/.config/omarchy/current/theme, shipped or computed.
//
//   shipped  themes/<name>/colors.toml holds a designer's own 16 colours, and
//            they are used as they are. A theme named gruvbox must give the
//            gruvbox terminal, not our reading of its wallpaper.
//   computed a derived directory has no colours.toml, so the 16 come from
//            sketchybar.sh: the six meaning-carrying hues stay FIXED (red is
//            red, whatever the picture), and only their lightness and chroma
//            follow the wallpaper, each pushed until it reads on the
//            background.
//
// The output is one file of KEY='#rrggbb' lines, meant to be sourced by a
// shell. WHO applies it is not this program's business: omacosy-term-auto-theme
// renders the terminal's own config files from it, or hands the file to a
// command named in term-auto-theme.conf. The surface ramp is not written: a
// consumer that wants one derives it from the background, the foreground and
// MUTED.
import AppKit

struct C { var r: Double, g: Double, b: Double
    var hex: String { String(format: "#%02x%02x%02x", q(r), q(g), q(b)) }
    func q(_ v: Double) -> Int { Int((min(1, max(0, v)) * 255).rounded()) } }

func lin(_ v: Double) -> Double { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
func gam(_ v: Double) -> Double { v <= 0.0031308 ? v * 12.92 : 1.055 * pow(v, 1 / 2.4) - 0.055 }
func toOK(_ c: C) -> (L: Double, C: Double, h: Double) {
    let r = lin(c.r), g = lin(c.g), b = lin(c.b)
    let l = cbrt(0.4122214708*r + 0.5363325363*g + 0.0514459929*b)
    let m = cbrt(0.2119034982*r + 0.6806995451*g + 0.1073969566*b)
    let s = cbrt(0.0883024619*r + 0.2817188376*g + 0.6299787005*b)
    let L = 0.2104542553*l + 0.7936177850*m - 0.0040720468*s
    let A = 1.9779984951*l - 2.4285922050*m + 0.4505937099*s
    let B = 0.0259040371*l + 0.7827717662*m - 0.8086757660*s
    var h = atan2(B, A) * 180 / .pi; if h < 0 { h += 360 }
    return (L, sqrt(A*A + B*B), h)
}
func fromOK(_ L: Double, _ ch: Double, _ h: Double) -> C? {
    let A = ch * cos(h * .pi/180), B = ch * sin(h * .pi/180)
    let l = pow(L + 0.3963377774*A + 0.2158037573*B, 3)
    let m = pow(L - 0.1055613458*A - 0.0638541728*B, 3)
    let s = pow(L - 0.0894841775*A - 1.2914855480*B, 3)
    let r = 4.0767416621*l - 3.3077115913*m + 0.2309699292*s
    let g = -1.2684380046*l + 2.6097574011*m - 0.3413193965*s
    let b = -0.0041960863*l - 0.7034186147*m + 1.7076147010*s
    let e = 0.001
    guard r >= -e, r <= 1+e, g >= -e, g <= 1+e, b >= -e, b <= 1+e else { return nil }
    return C(r: gam(min(1, max(0, r))), g: gam(min(1, max(0, g))), b: gam(min(1, max(0, b))))
}
func fit(_ L: Double, _ ch: Double, _ h: Double) -> C {
    var c = ch
    while c > 0 { if let x = fromOK(L, c, h) { return x }; c -= 0.005 }
    return fromOK(L, 0, h) ?? C(r: 0, g: 0, b: 0)
}
func relLum(_ c: C) -> Double { 0.2126*lin(c.r) + 0.7152*lin(c.g) + 0.0722*lin(c.b) }
func contrast(_ a: C, _ b: C) -> Double {
    let x = relLum(a), y = relLum(b); return (max(x, y) + 0.05) / (min(x, y) + 0.05)
}
// lift (or drop) until it reads on the background, hue kept
func legible(_ c: C, on bg: C, ratio: Double) -> C {
    if contrast(c, bg) >= ratio { return c }
    let o = toOK(c), up = relLum(bg) < 0.2
    var L = o.L
    while L > 0.02 && L < 0.99 {
        L += up ? 0.01 : -0.01
        let x = fit(L, o.C, o.h)
        if contrast(x, bg) >= ratio { return x }
    }
    return up ? C(r: 1, g: 1, b: 1) : C(r: 0, g: 0, b: 0)
}

func read(_ dir: String) -> [String: C] {
    let text = (try? String(contentsOfFile: dir + "/sketchybar.sh", encoding: .utf8)) ?? ""
    var out: [String: C] = [:]
    for line in text.split(separator: "\n") where line.hasPrefix("export ") {
        let kv = line.dropFirst(7).split(separator: "=", maxSplits: 1)
        guard kv.count == 2, let v = UInt64(kv[1].replacingOccurrences(of: "0x", with: ""), radix: 16)
        else { continue }
        out[String(kv[0])] = C(r: Double((v >> 16) & 0xff)/255, g: Double((v >> 8) & 0xff)/255, b: Double(v & 0xff)/255)
    }
    return out
}

let args = CommandLine.arguments
guard args.count >= 3 else {
    FileHandle.standardError.write("usage: omacosy-term-palette <theme-dir> <out.env> [label] [--preview <png>]\n".data(using: .utf8)!)
    exit(2)
}
let themeDir = args[1], outPath = args[2]
var label = "omacosy", previewPath: String? = nil
var rest = Array(args.dropFirst(3))
while let first = rest.first {
    if first == "--preview", rest.count >= 2 { previewPath = rest[1]; rest.removeFirst(2) }
    else { label = first; rest.removeFirst() }
}

// A shipped theme carries its own colours. Read them verbatim.
func readColoursToml(_ dir: String) -> [String: C]? {
    guard let text = try? String(contentsOfFile: dir + "/colors.toml", encoding: .utf8) else { return nil }
    var out: [String: C] = [:]
    for line in text.split(separator: "\n") {
        let parts = line.split(separator: "=", maxSplits: 1)
        guard parts.count == 2 else { continue }
        let key = parts[0].trimmingCharacters(in: .whitespaces)
        let hex = parts[1].trimmingCharacters(in: CharacterSet(charactersIn: " \"#"))
        guard hex.count == 6, let v = UInt64(hex, radix: 16) else { continue }
        out[key] = C(r: Double((v >> 16) & 0xff)/255, g: Double((v >> 8) & 0xff)/255, b: Double(v & 0xff)/255)
    }
    return out.isEmpty ? nil : out
}

var bg: C, fg: C, cursor: C, cursorText: C, selBG: C, selFG: C, accent: C, muted: C, peach: C
var ansi: [C] = []
var dark = true
var swatches: [(String, C)] = []
func col(_ n: String) -> C { swatches.first { $0.0 == n }!.1 }
let names = ["BLACK", "RED", "GREEN", "YELLOW", "BLUE", "MAGENTA", "CYAN", "WHITE",
             "BR_BLACK", "BR_RED", "BR_GREEN", "BR_YELLOW", "BR_BLUE", "BR_MAGENTA", "BR_CYAN", "BR_WHITE"]

if let t = readColoursToml(themeDir), let b = t["background"], let f = t["foreground"] {
    bg = b; fg = f
    cursor = t["cursor"] ?? f
    cursorText = t["cursor_text"] ?? b
    selBG = t["selection_background"] ?? f
    selFG = t["selection_foreground"] ?? b
    accent = t["accent"] ?? f
    dark = relLum(bg) < 0.2
    for i in 0..<16 { ansi.append(t["color\(i)"] ?? fg) }
    muted = ansi[8]
    // peach is a role the prompt uses between red and green; a shipped theme
    // does not name one, so it is the midpoint of its own red and yellow
    let r = toOK(ansi[1]), y = toOK(ansi[3])
    peach = fit((r.L + y.L) / 2, (r.C + y.C) / 2, r.h + (y.h - r.h) / 2)
} else {
    // computed theme: the bar's own palette, plus six fixed hues
    let p = read(themeDir)
    guard let a = p["ACCENT"], let surface = p["BAR_BG_SOLID"], let lab = p["LABEL_COLOR"],
          let pill = p["ITEM_BG"], let mut = p["MUTED"] else {
        FileHandle.standardError.write("omacosy-term-palette: no palette in \(themeDir)\n".data(using: .utf8)!)
        exit(1)
    }
    accent = a; muted = mut
    // WHICH WAY ROUND THE TERMINAL RUNS is the theme's own answer: light text
    // means a dark terminal. Reading it off the surface fails, because a
    // light-ladder theme can hand over a MID-TONE surface (a dusty pink bar at
    // relative luminance 0.19), and a terminal cannot be mid-tone: every colour
    // then has to run to white or black to stay legible on it.
    dark = relLum(lab) > 0.4
    // So the surface is pushed AWAY from the text until the text reads on it,
    // 8:1. A theme that already has a deep surface does not move.
    bg = surface
    if contrast(lab, bg) < 8 {
        let o = toOK(bg)
        var L = o.L
        while L > 0.03 && L < 0.99 {
            L += dark ? -0.01 : 0.01
            let x = fit(L, min(o.C, 0.05), o.h)
            if contrast(lab, x) >= 8 { bg = x; break }
            bg = x
        }
    }
    fg = legible(lab, on: bg, ratio: 8)
    // the accent is the cursor and the prompt's last segment, so it has to be
    // readable on THIS background, not only on the bar's pill
    accent = legible(accent, on: bg, ratio: 4.5)
    cursor = accent; cursorText = bg; selBG = pill; selFG = fg
    let aOK = toOK(accent)
    // Six hues that carry meaning, in OKLCH, nudged up to 15 degrees toward the
    // accent: enough to belong to the picture, not enough to stop red being red.
    let base: [Double] = [29, 142, 95, 258, 328, 210]   // red green yellow blue magenta cyan
    func harmonised(_ h: Double) -> Double {
        var d = aOK.h - h
        if d > 180 { d -= 360 }; if d < -180 { d += 360 }
        return h + max(-15, min(15, d))
    }
    let chroma = max(0.09, min(0.16, aOK.C * 1.2))      // pastel picture, pastel set
    let normalL = dark ? 0.68 : 0.52, brightL = dark ? 0.80 : 0.62
    // The two greys are measured FROM the background, not from fixed values:
    // colour 0 is a shade of it, colour 8 is what dimmed text is written in, so
    // it has to stay readable (3.5:1) whatever the background turned out to be.
    let bgL = toOK(bg).L, bgC = min(toOK(bg).C, 0.03), bgH = toOK(bg).h
    ansi.append(fit(bgL + (dark ? 0.10 : -0.10), bgC, bgH))
    for h in base { ansi.append(legible(fit(normalL, chroma, harmonised(h)), on: bg, ratio: 4.5)) }
    ansi.append(legible(lab, on: bg, ratio: 7))
    ansi.append(legible(fit(bgL + (dark ? 0.26 : -0.26), bgC, bgH), on: bg, ratio: 3.5))
    for h in base { ansi.append(legible(fit(brightL, chroma, harmonised(h)), on: bg, ratio: 4.5)) }
    ansi.append(legible(lab, on: bg, ratio: 10))
    peach = legible(fit(normalL, chroma, harmonised(55)), on: bg, ratio: 4.5)
}

var env = ["OMACOSY_THEME='\(label)'",
           "OMACOSY_BG='\(bg.hex)'", "OMACOSY_FG='\(fg.hex)'",
           "OMACOSY_CURSOR='\(cursor.hex)'", "OMACOSY_CURSOR_TEXT='\(cursorText.hex)'",
           "OMACOSY_SEL_BG='\(selBG.hex)'", "OMACOSY_SEL_FG='\(selFG.hex)'"]
for (i, c) in ansi.enumerated() {
    env.append("OMACOSY_\(names[i])='\(c.hex)'")
    env.append("OMACOSY_P\(i)='\(c.hex)'")
    swatches.append((names[i], c))
}
// WHICH PALETTE SLOT THE ACCENT IS NEAREST, by name. A program that paints
// itself in true colour cannot follow a live repaint: the terminal's own 16
// slots can, because setting them IS the repaint. So a consumer that wants to
// change colour while it runs (yazi) asks for this slot by name and gets the
// nearest thing to the accent that updates live. Distance is measured in
// OKLab, where equal steps look equal.
let ansiNames = ["black", "red", "green", "yellow", "blue", "magenta", "cyan", "gray",
                 "darkgray", "lightred", "lightgreen", "lightyellow", "lightblue",
                 "lightmagenta", "lightcyan", "white"]
func oklab(_ c: C) -> (Double, Double, Double) {
    let o = toOK(c)
    return (o.L, o.C * cos(o.h * .pi / 180), o.C * sin(o.h * .pi / 180))
}
let aLab = oklab(accent)
var nearest = 0, nearestD = Double.greatestFiniteMagnitude
for (i, c) in ansi.enumerated() {
    // black and white are not colours to name an accent with: on a dark
    // terminal slot 0 is the background's own shade, and both would give a
    // file list with no accent at all.
    if i == 0 || i == 7 || i == 8 || i == 15 { continue }
    let l = oklab(c)
    let d = pow(aLab.0 - l.0, 2) + pow(aLab.1 - l.1, 2) + pow(aLab.2 - l.2, 2)
    if d < nearestD { nearestD = d; nearest = i }
}
env.append("OMACOSY_ACCENT_ANSI='\(ansiNames[nearest])'")
env.append("OMACOSY_ACCENT_ANSI_N=\(nearest)")

// The same colours again under the names a prompt uses, so a template can say
// "err" rather than "red". Every theme fills the same roles.
env += ["OMACOSY_ACCENT='\(accent.hex)'", "OMACOSY_ALT='\(col("MAGENTA").hex)'",
        "OMACOSY_OK='\(col("GREEN").hex)'", "OMACOSY_WARN='\(col("YELLOW").hex)'",
        "OMACOSY_ERR='\(col("RED").hex)'", "OMACOSY_INFO='\(col("CYAN").hex)'",
        "OMACOSY_PEACH='\(peach.hex)'", "OMACOSY_MUTED='\(muted.hex)'",
        "OMACOSY_IS_DARK=\(dark ? 1 : 0)"]
do {
    try env.joined(separator: "\n").appending("\n").write(toFile: outPath, atomically: true, encoding: .utf8)
} catch {
    FileHandle.standardError.write("omacosy-term-palette: \(error.localizedDescription)\n".data(using: .utf8)!)
    exit(1)
}

guard let preview = previewPath else { exit(0) }
let args3 = ["", "", "", preview]   // the preview block below reads args[3]
// ---- preview: a fake terminal window, so the set can be judged by eye ----
func ns(_ c: C) -> NSColor { NSColor(srgbRed: c.r, green: c.g, blue: c.b, alpha: 1) }
let W = 900.0, H = 420.0
let img = NSImage(size: NSSize(width: W, height: H))
img.lockFocus()
ns(bg).setFill(); NSRect(x: 0, y: 0, width: W, height: H).fill()
let mono = NSFont.monospacedSystemFont(ofSize: 15, weight: .regular)
let bold = NSFont.monospacedSystemFont(ofSize: 15, weight: .bold)
func t(_ s: String, _ x: Double, _ y: Double, _ c: C, _ f: NSFont = mono) -> Double {
    let a: [NSAttributedString.Key: Any] = [.font: f, .foregroundColor: ns(c)]
    let str = NSAttributedString(string: s, attributes: a)
    str.draw(at: NSPoint(x: x, y: y))
    return x + str.size().width
}
var y = H - 34
var x = t("~/Projects/omacosy", 24, y, col("BR_BLUE"), bold)
x = t(" on ", x, y, col("BR_BLACK"))
x = t(" mine ", x, y, col("MAGENTA"), bold)
_ = t(" [!]", x, y, col("YELLOW"))
y -= 26
x = t("❯ ", 24, y, col("GREEN"), bold); _ = t("eza -l", x, y, fg)
y -= 30
for (name, kind) in [("helper", "dir"), ("themes", "dir"), ("install.sh", "exec"), ("FORK.md", "file"), ("derive.swift", "file")] {
    x = t("drwxr-xr-x  ", 24, y, col("BR_BLACK"))
    switch kind {
    case "dir":  x = t(name, x, y, accent, bold)          // ← directories use the ACCENT
    case "exec": x = t(name, x, y, col("GREEN"))
    default:     x = t(name, x, y, fg)
    }
    _ = t("   3.2 KiB  20 Sep 10:12", x, y, col("BR_BLACK"))
    y -= 22
}
y -= 12
x = t("❯ ", 24, y, col("GREEN"), bold); _ = t("git status", x, y, fg)
y -= 24
x = t("  modified:   ", 24, y, col("RED")); _ = t("helper/derive.swift", x, y, col("RED"))
y -= 22
x = t("  new file:   ", 24, y, col("GREEN")); _ = t("notes/tools/termpalette.swift", x, y, col("GREEN"))
y -= 22
_ = t("  warning: 2 files ignored", 24, y, col("YELLOW"))
y -= 30
x = 24
for (name, c) in swatches {
    ns(c).setFill(); NSRect(x: x, y: y - 6, width: 34, height: 20).fill()
    x += 38
    if name == "WHITE" { x = 24; y -= 26 }
}
img.unlockFocus()
let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args3[3]))
print("preview \(preview)")
