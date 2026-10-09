// themecore.swift — the Theme Studio engine: colour maths, palettes, themes.
//
//   omacosy-themecore color convert <hex> [--to rgb|hsl|oklab|oklch] [--json]
//   omacosy-themecore color contrast <colour-a> <colour-b> [--json]
//   omacosy-themecore color adjust <hex> [12 flags] [--json]
//   omacosy-themecore color darken <hex> <percent> [--json]
//   omacosy-themecore color lighten <hex> <percent> [--json]
//   omacosy-themecore color gradient <start> <end> [--steps N] [--json]
//   omacosy-themecore color from-color <hex> [--json]
//   omacosy-themecore color roundtrip <hex> [--json]     (test support)
//   omacosy-themecore curve lut --points "x,y;x,y" [--json]
//   omacosy-themecore presets [--json]
//   omacosy-themecore modes [--json]
//   omacosy-themecore theme list [--json]
//   omacosy-themecore theme show <id>
//   omacosy-themecore theme save [<file>|-] [--id ID] [--name NAME] [--replace]
//   omacosy-themecore theme delete <id>
//   omacosy-themecore theme rename <id> <new name>
//   omacosy-themecore theme duplicate <id> [--id ID] [--name NAME]
//   omacosy-themecore theme import <file> [--id ID] [--name NAME] [--replace|--rename]
//   omacosy-themecore theme export <id> [--out PATH]
//   omacosy-themecore theme materialize <id|file.json> [--wallpaper IMAGE] [--json]
//   omacosy-themecore theme wallpaper <id|file.json> [--source] [--json]
//   omacosy-themecore wallpaper list [--dir DIR] [--json]
//   omacosy-themecore wallpaper info <path> [--json]
//   omacosy-themecore wallpaper rename <old> <new> [--json]
//   omacosy-themecore wallpaper trash <path> [--json]
//   omacosy-themecore palette extract <image> [--mode ID] [--light] [--no-cache] [--json]
//   omacosy-themecore palette generate --colors CSV [--counts CSV|--weights CSV]
//                                           [--mode ID] [--light] [--normalize] [--json]
//   omacosy-themecore palette magic <image> [--roles] [--no-cache] [--json]
//   omacosy-themecore palette roles --colors CSV [--accent HEX] [--json]
//   omacosy-themecore palette roles --image PATH [--mode ID] [--light] [--json]
//   omacosy-themecore palette render --colors CSV [--accent HEX] [--cursor HEX]
//                                           [--selection-foreground HEX] [--selection-background HEX]
//                                           [12 adjustment flags] [--curve "x,y;x,y"] [--json]
//   omacosy-themecore palette suggest-mode <image> [--json]
//   omacosy-themecore palette quantize --pixels-file PATH [--count N] [--json]   (test support)
//   omacosy-themecore palette analyze <op> ...                                   (test support)
//   omacosy-themecore wallpaper scan [--dir DIR] [--json]                        (test support)
//   omacosy-themecore image info <path> [--json]
//   omacosy-themecore image histogram <path> [--json]
//   omacosy-themecore version [--json]
//
// Every verb takes --json and then prints one JSON value on stdout.
//
// A PURE CLI: no AppKit, no UI, no permissions. Everything the Theme Studio
// editors need that is not drawing lives here, so the dashboard only calls a
// process and reads its answer. Phases 1-3: colour maths, adjustments,
// presets, modes, theme records, the library, extraction and materialising.
//
// The library lives in ~/.config/omacosy/themes/<id>.json; the test harness
// redirects it and the Omacosy state files with OMACOSY_CONFIG_DIR,
// OMACOSY_STATE_DIR, OMACOSY_DATA_DIR and OMACOSY_THEMES_DIR.
//
// Ported from Aether (https://github.com/omacom/aether)
// Copyright (c) Bjarne Overli — MIT License
import AppKit
import CryptoKit
import Foundation
import ImageIO

struct RGB { var r, g, b: Double }
struct HSL { var h, s, l: Double }
struct OKLab { var l, a, b: Double }
struct OKLCH { var l, c, h: Double }

enum ColorMath {
    // MARK: sRGB transfer

    static func srgbToLinear(_ c: Double) -> Double {
        c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }

    static func linearToSrgb(_ c: Double) -> Double {
        c <= 0.0031308 ? 12.92 * c : 1.055 * pow(c, 1.0 / 2.4) - 0.055
    }

    // MARK: OKLab / OKLCH

    // Aether's own M1 matrix third row differs from the canonical Oklab
    // constants (and from term-palette.swift's); fixtures are recorded from
    // Aether, so the port keeps its numbers verbatim.
    static func oklab(fromSRGB rgb: RGB) -> OKLab {
        let r = srgbToLinear(rgb.r / 255.0)
        let g = srgbToLinear(rgb.g / 255.0)
        let b = srgbToLinear(rgb.b / 255.0)

        let l = 0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b
        let m = 0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b
        let s = 0.0883024619 * r + 0.2164557844 * g + 0.6952417517 * b

        let l_ = cbrt(l), m_ = cbrt(m), s_ = cbrt(s)

        return OKLab(
            l: 0.2104542553 * l_ + 0.7936177850 * m_ - 0.0040720468 * s_,
            a: 1.9779984951 * l_ - 2.4285922050 * m_ + 0.4505937099 * s_,
            b: 0.0259040371 * l_ + 0.7827717662 * m_ - 0.8086757660 * s_)
    }

    static func srgb(fromOKLab lab: OKLab) -> RGB {
        let l_ = lab.l + 0.3963377774 * lab.a + 0.2158037573 * lab.b
        let m_ = lab.l - 0.1055613458 * lab.a - 0.0638541728 * lab.b
        let s_ = lab.l - 0.0894841775 * lab.a - 1.2914855480 * lab.b

        let l = l_ * l_ * l_, m = m_ * m_ * m_, s = s_ * s_ * s_

        let r = min(1, max(0, 4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s))
        let g = min(1, max(0, -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s))
        let b = min(1, max(0, -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s))

        return RGB(r: (linearToSrgb(r) * 255).rounded(),
                   g: (linearToSrgb(g) * 255).rounded(),
                   b: (linearToSrgb(b) * 255).rounded())
    }

    static func oklch(fromOKLab lab: OKLab) -> OKLCH {
        let c = (lab.a * lab.a + lab.b * lab.b).squareRoot()
        var h = atan2(lab.b, lab.a) * 180.0 / .pi
        if h < 0 { h += 360 }
        return OKLCH(l: lab.l, c: c, h: h)
    }

    static func oklab(fromOKLCH lch: OKLCH) -> OKLab {
        let rad = lch.h * .pi / 180.0
        return OKLab(l: lch.l, a: lch.c * cos(rad), b: lch.c * sin(rad))
    }

    static func oklab(fromHex hex: String) -> OKLab { oklab(fromSRGB: rgb(fromHex: hex)) }
    static func oklch(fromHex hex: String) -> OKLCH { oklch(fromOKLab: oklab(fromHex: hex)) }
    static func hex(fromOKLab lab: OKLab) -> String { hex(fromRGB: srgb(fromOKLab: lab)) }
    static func hex(fromOKLCH lch: OKLCH) -> String { hex(fromOKLab: oklab(fromOKLCH: lch)) }

    static func oklabDistance(_ a: OKLab, _ b: OKLab) -> Double {
        let dl = a.l - b.l, da = a.a - b.a, db = a.b - b.b
        return (dl * dl + da * da + db * db).squareRoot()
    }

    // MARK: RGB / hex

    private static func isHexDigit(_ c: Character) -> Bool {
        guard let a = c.asciiValue else { return false }
        return (a >= 48 && a <= 57) || (a >= 97 && a <= 102) || (a >= 65 && a <= 70)
    }

    // Six hex digits with an optional "#" — what HexToRGB's pattern accepts.
    static func hexUInt32(_ value: String) -> UInt32? {
        var s = value.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6 else { return nil }
        for c in s where !isHexDigit(c) { return nil }
        return UInt32(s, radix: 16)
    }

    // The full Aether predicate: "#abc" and "#aabbcc", nothing else.
    static func isHexColor(_ value: String) -> Bool {
        let chars = Array(value)
        guard chars.count == 4 || chars.count == 7, chars.first == "#" else { return false }
        return chars.dropFirst().allSatisfy(isHexDigit)
    }

    static func rgb(fromHex hex: String) -> RGB {
        guard let v = hexUInt32(hex) else { return RGB(r: 0, g: 0, b: 0) }
        return RGB(r: Double((v >> 16) & 0xff), g: Double((v >> 8) & 0xff), b: Double(v & 0xff))
    }

    static func clampByte(_ v: Double) -> Int {
        if v <= 0 { return 0 }
        if v >= 255 { return 255 }
        return Int(v.rounded())
    }

    static func hex(fromRGB rgb: RGB) -> String {
        String(format: "#%02x%02x%02x", clampByte(rgb.r), clampByte(rgb.g), clampByte(rgb.b))
    }

    // MARK: HSL

    static func hsl(fromRGB rgb: RGB) -> HSL {
        let r = rgb.r / 255, g = rgb.g / 255, b = rgb.b / 255
        let maxV = max(r, max(g, b)), minV = min(r, min(g, b))
        var h = 0.0, s = 0.0
        let l = (maxV + minV) / 2

        if maxV == minV {
            h = 0; s = 0
        } else {
            let d = maxV - minV
            s = l > 0.5 ? d / (2 - maxV - minV) : d / (maxV + minV)
            if maxV == r {
                h = (g - b) / d
                if g < b { h += 6 }
                h /= 6
            } else if maxV == g {
                h = ((b - r) / d + 2) / 6
            } else {
                h = ((r - g) / d + 4) / 6
            }
        }
        return HSL(h: h * 360, s: s * 100, l: l * 100)
    }

    // `fma` in both slope branches because Go's compiler contracts the final
    // multiply-add on arm64; double-rounding here lands on the other side of
    // byte ties (found by the adjust fixtures).
    private static func hue2rgb(_ p: Double, _ q: Double, _ t0: Double) -> Double {
        var t = t0
        if t < 0 { t += 1 }
        if t > 1 { t -= 1 }
        if t < 1.0 / 6.0 { return fma((q - p) * 6, t, p) }
        if t < 1.0 / 2.0 { return q }
        if t < 2.0 / 3.0 { return fma((q - p) * (2.0 / 3.0 - t), 6, p) }
        return p
    }

    static func rgb(fromHSL hsl: HSL) -> RGB {
        var h = hsl.h / 360, s = hsl.s / 100
        let l = hsl.l / 100
        if h < 0 { h += 1 }
        if h > 1 { h -= 1 }

        var r = l, g = l, b = l
        if s != 0 {
            // Go's compiler contracts `l + s - l*s` into one fused
            // multiply-add on arm64; rounding it twice here lands a byte off
            // on ties (found by the adjust fixtures).
            let q = l < 0.5 ? l * (1 + s) : fma(-l, s, l + s)
            let p = 2 * l - q
            r = hue2rgb(p, q, h + 1.0 / 3.0)
            g = hue2rgb(p, q, h)
            b = hue2rgb(p, q, h - 1.0 / 3.0)
        }
        return RGB(r: r * 255, g: g * 255, b: b * 255)
    }

    static func hsl(fromHex hex: String) -> HSL { hsl(fromRGB: rgb(fromHex: hex)) }
    static func hex(fromHSL hsl: HSL) -> String { hex(fromRGB: rgb(fromHSL: hsl)) }

    // MARK: WCAG contrast

    static func relativeLuminance(_ hex: String) -> Double {
        let c = rgb(fromHex: hex)
        return 0.2126 * srgbToLinear(c.r / 255)
            + 0.7152 * srgbToLinear(c.g / 255)
            + 0.0722 * srgbToLinear(c.b / 255)
    }

    static func contrastRatio(_ a: String, _ b: String) -> Double {
        let l1 = relativeLuminance(a), l2 = relativeLuminance(b)
        return (max(l1, l2) + 0.05) / (min(l1, l2) + 0.05)
    }

    // MARK: Darken / lighten

    static func darkened(_ hex: String, _ percent: Double) -> String {
        let c = rgb(fromHex: hex)
        return self.hex(fromRGB: RGB(r: (c.r * percent / 100).rounded(),
                                     g: (c.g * percent / 100).rounded(),
                                     b: (c.b * percent / 100).rounded()))
    }

    static func lightened(_ hex: String, _ percent: Double) -> String {
        let c = rgb(fromHex: hex)
        return self.hex(fromRGB: RGB(r: (c.r + (255 - c.r) * percent / 100).rounded(),
                                     g: (c.g + (255 - c.g) * percent / 100).rounded(),
                                     b: (c.b + (255 - c.b) * percent / 100).rounded()))
    }

    // MARK: Gradient / palette from one colour

    static func gradient(from start: String, to end: String, steps: Int = 16) -> [String] {
        let s = rgb(fromHex: start), e = rgb(fromHex: end)
        let n = max(2, steps)
        return (0..<n).map { i in
            let t = Double(i) / Double(n - 1)
            return hex(fromRGB: RGB(r: (s.r + (e.r - s.r) * t).rounded(),
                                    g: (s.g + (e.g - s.g) * t).rounded(),
                                    b: (s.b + (e.b - s.b) * t).rounded()))
        }
    }

    static func paletteFromColor(_ baseColor: String) -> [String] {
        let base = hsl(fromHex: baseColor)
        let hueRanges: [(min: Double, max: Double, slot: Int)] = [
            (345, 360, 1), (0, 45, 1), (45, 75, 3), (75, 165, 2),
            (165, 195, 6), (195, 285, 4), (285, 345, 5),
        ]
        var baseSlot = 1
        for r in hueRanges where base.h >= r.min && base.h < r.max {
            baseSlot = r.slot
            break
        }

        let ansiHues: [Double] = [0, 120, 60, 240, 300, 180]
        var colors1to6: [String] = []
        for (i, hue) in ansiHues.enumerated() {
            colors1to6.append(i + 1 == baseSlot ? baseColor : hex(fromHSL: HSL(h: hue, s: base.s, l: base.l)))
        }

        let brightLight = min(100, base.l + 10)
        let brightSat = min(100, base.s * 1.1)
        var colors9to14: [String] = []
        for (i, hue) in ansiHues.enumerated() {
            if i + 1 == baseSlot {
                colors9to14.append(hex(fromHSL: HSL(h: base.h, s: brightSat, l: brightLight)))
            } else {
                colors9to14.append(hex(fromHSL: HSL(h: hue, s: brightSat, l: brightLight)))
            }
        }

        var palette = Array(repeating: "", count: 16)
        palette[0] = hex(fromHSL: HSL(h: base.h, s: base.s * 0.4, l: max(3, base.l * 0.15)))
        for i in 0..<6 { palette[i + 1] = colors1to6[i] }
        palette[7] = hex(fromHSL: HSL(h: base.h, s: base.s * 0.15, l: 92))
        palette[8] = hex(fromHSL: HSL(h: base.h, s: base.s * 0.35, l: min(40, base.l)))
        for i in 0..<6 { palette[i + 9] = colors9to14[i] }
        palette[15] = hex(fromHSL: HSL(h: base.h, s: base.s * 0.1, l: 98))
        return palette
    }
}

// MARK: - Adjustments

struct Adjustments {
    var vibrance = 0.0
    var saturation = 0.0
    var contrast = 0.0
    var brightness = 0.0
    var shadows = 0.0
    var highlights = 0.0
    var hueShift = 0.0
    var temperature = 0.0
    var tint = 0.0
    var gamma = 1.0
    var blackPoint = 0.0
    var whitePoint = 0.0

    struct Limit { let min, max, step, def: Double }

    // UI ranges, from Aether's ADJUSTMENT_LIMITS. The pipeline itself never
    // clamps to them; the editors do.
    static let limits: [String: Limit] = [
        "vibrance":    Limit(min: -50, max: 50, step: 5, def: 0),
        "saturation":  Limit(min: -100, max: 100, step: 5, def: 0),
        "contrast":    Limit(min: -30, max: 30, step: 5, def: 0),
        "brightness":  Limit(min: -30, max: 30, step: 5, def: 0),
        "shadows":     Limit(min: -50, max: 50, step: 5, def: 0),
        "highlights":  Limit(min: -50, max: 50, step: 5, def: 0),
        "hueShift":    Limit(min: -180, max: 180, step: 10, def: 0),
        "temperature": Limit(min: -50, max: 50, step: 5, def: 0),
        "tint":        Limit(min: -50, max: 50, step: 5, def: 0),
        "blackPoint":  Limit(min: -30, max: 30, step: 5, def: 0),
        "whitePoint":  Limit(min: -30, max: 30, step: 5, def: 0),
        "gamma":       Limit(min: 0.5, max: 2.0, step: 0.1, def: 1.0),
    ]
}

// The 12-step order is a contract — Aether's own comment says it must match
// the JavaScript implementation exactly, so the steps below run in this order
// and nowhere else. Fixtures in notes/theme-studio-tests/ pin every one.
func adjustColor(_ hex: String, _ a: Adjustments) -> String {
    var hsl = ColorMath.hsl(fromHex: hex)
    hsl = hueShift(hsl, a.hueShift);      hsl = temperature(hsl, a.temperature)
    hsl = tint(hsl, a.tint);              hsl = vibrance(hsl, a.vibrance)
    hsl = saturation(hsl, a.saturation);  hsl = brightness(hsl, a.brightness)
    hsl = shadows(hsl, a.shadows);        hsl = highlights(hsl, a.highlights)
    hsl = blackPoint(hsl, a.blackPoint);  hsl = whitePoint(hsl, a.whitePoint)
    hsl = contrast(hsl, a.contrast)
    return a.gamma == 1.0 ? ColorMath.hex(fromHSL: hsl) : gammaApply(hsl, a.gamma)
}

private func clamp100(_ v: Double) -> Double { min(100, max(0, v)) }

private func hueShift(_ hsl: HSL, _ amount: Double) -> HSL {
    var out = hsl
    out.h = (hsl.h + amount + 360).truncatingRemainder(dividingBy: 360)
    return out
}

private func hueTarget(_ hsl: HSL, _ target: Double, _ amount: Double) -> HSL {
    let t = abs(amount) / 100
    let diff = ((target - hsl.h + 540).truncatingRemainder(dividingBy: 360)) - 180
    var out = hsl
    out.h = (hsl.h + diff * t * 0.3 + 360).truncatingRemainder(dividingBy: 360)
    return out
}

private func temperature(_ hsl: HSL, _ temp: Double) -> HSL {
    if temp == 0 { return hsl }
    return hueTarget(hsl, temp > 0 ? 30.0 : 210.0, temp)
}

private func tint(_ hsl: HSL, _ amount: Double) -> HSL {
    if amount == 0 { return hsl }
    return hueTarget(hsl, amount > 0 ? 300.0 : 120.0, amount)
}

private func vibrance(_ hsl: HSL, _ amount: Double) -> HSL {
    var out = hsl
    out.s = clamp100(hsl.s + amount)
    return out
}

private func saturation(_ hsl: HSL, _ amount: Double) -> HSL {
    var out = hsl
    if amount != 0 { out.s = clamp100(hsl.s * (100 + amount) / 100) }
    return out
}

private func brightness(_ hsl: HSL, _ amount: Double) -> HSL {
    var out = hsl
    out.l = clamp100(hsl.l + amount)
    return out
}

private func shadows(_ hsl: HSL, _ amount: Double) -> HSL {
    var out = hsl
    if amount != 0 && hsl.l < 30 {
        let strength = 1 - hsl.l / 30
        out.l = clamp100(hsl.l + amount * strength)
    }
    return out
}

private func highlights(_ hsl: HSL, _ amount: Double) -> HSL {
    var out = hsl
    if amount != 0 && hsl.l > 70 {
        let strength = (hsl.l - 70) / 30
        out.l = clamp100(hsl.l + amount * strength)
    }
    return out
}

private func blackPoint(_ hsl: HSL, _ bp: Double) -> HSL {
    if bp == 0 { return hsl }
    var out = hsl
    let minL = max(0, bp)
    let adjustedMinL = max(0, -bp)
    out.l = adjustedMinL + (hsl.l * (100 - adjustedMinL - minL)) / 100 + minL
    out.l = clamp100(out.l)
    return out
}

private func whitePoint(_ hsl: HSL, _ wp: Double) -> HSL {
    if wp == 0 { return hsl }
    var out = hsl
    if wp > 0 {
        out.l = min(100 - wp, hsl.l)
    } else {
        out.l = clamp100(hsl.l - wp * (1 - hsl.l / 100))
    }
    out.l = clamp100(out.l)
    return out
}

private func contrast(_ hsl: HSL, _ amount: Double) -> HSL {
    var out = hsl
    let factor = amount / 100
    let deviation = hsl.l - 50
    out.l = clamp100(50 + deviation * (1 + factor))
    return out
}

private func gammaApply(_ hsl: HSL, _ gamma: Double) -> String {
    let c = ColorMath.rgb(fromHSL: hsl)
    let inv = 1 / gamma
    return ColorMath.hex(fromRGB: RGB(
        r: min(255, max(0, pow(c.r / 255, inv) * 255)),
        g: min(255, max(0, pow(c.g / 255, inv) * 255)),
        b: min(255, max(0, pow(c.b / 255, inv) * 255))))
}

// MARK: - Tone curve

// Ported from Aether (https://github.com/omacom/aether)
// Copyright (c) Bjarne Overli — MIT License
//
// The monotone-cubic (Fritsch-Carlson) 256-entry LUT and its HSL-lightness
// application, from frontend/src/lib/utils/canvas-filters.ts. Endpoints
// (0,0) and (1,1) are implicit; an empty point list means "no curve".
// notes/theme-studio-tests/record-curve-fixtures.sh pins the output against
// Aether byte for byte.
enum ToneCurve {
    static let identity: [UInt8] = (0...255).map { UInt8($0) }

    // 256-entry lightness LUT from user control points; nil when empty.
    static func lut(_ points: [[Double]]) -> [UInt8]? {
        guard !points.isEmpty else { return nil }

        // JS Array.sort is stable; the original index breaks x ties the same way.
        var tagged: [(i: Int, x: Double, y: Double)] = [(0, 0, 0)]
        for (i, p) in points.enumerated() { tagged.append((i + 1, p[0], p[1])) }
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

        // Fritsch-Carlson monotonicity correction
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

    // Aether's applyCurveToColors: the curve moves the HSL lightness only.
    // The 0..1 HSL helpers mirror the JS exactly; ColorMath's degrees/percent
    // round-trip would move a byte on the ties.
    static func apply(_ hex: String, lut: [UInt8]) -> String {
        guard lut.count == 256, hex.count >= 7 else { return hex }
        let rgb = ColorMath.rgb(fromHex: hex)
        let hsl = hsl01(rgb)
        let index = min(255, max(0, Int((hsl.l * 255).rounded())))
        let newL = Double(lut[index]) / 255
        let out = rgb01(h: hsl.h, s: hsl.s, l: newL)
        return ColorMath.hex(fromRGB: RGB(r: out.0 * 255, g: out.1 * 255, b: out.2 * 255))
    }

    private static func hsl01(_ rgb: RGB) -> (h: Double, s: Double, l: Double) {
        let r = rgb.r / 255, g = rgb.g / 255, b = rgb.b / 255
        let maxV = max(r, max(g, b)), minV = min(r, min(g, b))
        let l = (maxV + minV) / 2
        var h = 0.0, s = 0.0
        if maxV != minV {
            let d = maxV - minV
            s = l > 0.5 ? d / (2 - maxV - minV) : d / (maxV + minV)
            if maxV == r {
                h = ((g - b) / d + (g < b ? 6.0 : 0.0)) / 6
            } else if maxV == g {
                h = ((b - r) / d + 2) / 6
            } else {
                h = ((r - g) / d + 4) / 6
            }
        }
        return (h, s, l)
    }

    private static func rgb01(h: Double, s: Double, l: Double) -> (Double, Double, Double) {
        if s == 0 { return (l, l, l) }
        let q = l < 0.5 ? l * (1 + s) : l + s - l * s
        let p = 2 * l - q
        return (hue2rgb(p, q, h + 1.0 / 3.0), hue2rgb(p, q, h), hue2rgb(p, q, h - 1.0 / 3.0))
    }

    private static func hue2rgb(_ p: Double, _ q: Double, _ t0: Double) -> Double {
        var t = t0
        if t < 0 { t += 1 }
        if t > 1 { t -= 1 }
        if t < 1.0 / 6.0 { return p + (q - p) * 6 * t }
        if t < 1.0 / 2.0 { return q }
        if t < 2.0 / 3.0 { return p + (q - p) * (2.0 / 3.0 - t) * 6 }
        return p
    }
}

extension Adjustments {
    // True when the recipe changes nothing: materialise and the editor then
    // keep the base colours byte for byte.
    var isIdentity: Bool {
        vibrance == 0 && saturation == 0 && contrast == 0 && brightness == 0
            && shadows == 0 && highlights == 0 && hueShift == 0 && temperature == 0
            && tint == 0 && blackPoint == 0 && whitePoint == 0 && gamma == 1.0
    }
}

extension Palette16 {
    // The final palette the desktop shows: the stored base colours with the
    // 12 adjustments and then the tone curve applied (Aether's order). The
    // extended four go through the same chain, so the bar accent and the
    // cursor colour stay in step with the 16.
    func rendered() -> (colors: [String], extended: Extended) {
        let a = adjustments
        let lut = ToneCurve.lut(curve)
        func one(_ hex: String) -> String {
            let adjusted = a.isIdentity ? hex : adjustColor(hex, a)
            return lut.map { ToneCurve.apply(adjusted, lut: $0) } ?? adjusted
        }
        return (colors.map(one),
                Extended(accent: one(extended.accent),
                         cursor: one(extended.cursor),
                         selectionForeground: one(extended.selectionForeground),
                         selectionBackground: one(extended.selectionBackground)))
    }
}

// MARK: - Presets

// 40 named palettes, ported verbatim from Aether's PRESET_THEMES
// (frontend/src/lib/constants/colors.ts); names, order and colours kept
// exactly. `mode` is ours: WCAG luminance of colors[0], light above 0.5.
struct Preset {
    let name: String
    let colors: [String]

    var mode: String { ColorMath.relativeLuminance(colors[0]) > 0.5 ? "light" : "dark" }
}

enum Presets {
    static let all: [Preset] = [
        Preset(name: "Aether", colors: [
            "#141114", "#ff637e", "#b4e173", "#ffd568", "#ff9b66", "#c09ef5", "#76ecdb", "#ffffff",
            "#766974", "#ff637e", "#b4e173", "#ffd568", "#ff9b66", "#c09ef5", "#76ecdb", "#ffffff",
        ]),
        Preset(name: "Pina", colors: [
            "#171a18", "#7db085", "#b8c082", "#e0d480", "#7dd2b8", "#b5c9a4", "#c5e8c5", "#d4d5d5",
            "#6b8071", "#8cc098", "#cdd590", "#f2e590", "#92e2c8", "#c8dab8", "#d8f5d8", "#e2e3e3",
        ]),
        Preset(name: "Sakura", colors: [
            "#0d0509", "#E85F6F", "#F29B9A", "#D4A882", "#D9A56C", "#D1B399", "#E8C099", "#f0eaed",
            "#4a3c45", "#FF7A8A", "#FFB5B4", "#E6BA94", "#EBB97E", "#E3C5AB", "#FBD2AB", "#ffffff",
        ]),
        Preset(name: "Fireside", colors: [
            "#0a1220", "#e06b58", "#889889", "#b8b5a2", "#b8b8b6", "#e48b7a", "#d0cac7", "#f0f2f5",
            "#555c65", "#e06b58", "#9eaca1", "#c8c3b8", "#cdcbc9", "#f0a19a", "#e3ddda", "#f0f2f5",
        ]),
        Preset(name: "Frost", colors: [
            "#0a0f1c", "#869AAC", "#95A8B8", "#9FADB8", "#9BB0C2", "#A8B9C6", "#B8C7D0", "#d4d5d9",
            "#5f6374", "#869AAC", "#95A8B8", "#9FADB8", "#9BB0C2", "#A8B9C6", "#B8C7D0", "#d4d5d9",
        ]),
        Preset(name: "Dracula", colors: [
            "#282a36", "#ff5555", "#50fa7b", "#f1fa8c", "#bd93f9", "#ff79c6", "#8be9fd", "#f8f8f2",
            "#6272a4", "#ff6e6e", "#69ff94", "#ffffa5", "#d6acff", "#ff92df", "#a4ffff", "#ffffff",
        ]),
        Preset(name: "Nord", colors: [
            "#2e3440", "#bf616a", "#a3be8c", "#ebcb8b", "#81a1c1", "#b48ead", "#88c0d0", "#e5e9f0",
            "#4c566a", "#d08770", "#a3be8c", "#ebcb8b", "#81a1c1", "#b48ead", "#8fbcbb", "#eceff4",
        ]),
        Preset(name: "Gruvbox Dark", colors: [
            "#282828", "#cc241d", "#98971a", "#d79921", "#458588", "#b16286", "#689d6a", "#ebdbb2",
            "#928374", "#fb4934", "#b8bb26", "#fabd2f", "#83a598", "#d3869b", "#8ec07c", "#fbf1c7",
        ]),
        Preset(name: "Gruvbox Material", colors: [
            "#1d2021", "#ea6962", "#a9b665", "#d8a657", "#7daea3", "#d3869b", "#89b482", "#d4be98",
            "#32302f", "#ea6962", "#a9b665", "#d8a657", "#7daea3", "#d3869b", "#89b482", "#ddc7a1",
        ]),
        Preset(name: "Solarized Dark", colors: [
            "#002b36", "#dc322f", "#859900", "#b58900", "#268bd2", "#d33682", "#2aa198", "#839496",
            "#073642", "#cb4b16", "#586e75", "#657b83", "#839496", "#6c71c4", "#93a1a1", "#fdf6e3",
        ]),
        Preset(name: "Tokyo Night", colors: [
            "#1a1b26", "#f7768e", "#9ece6a", "#e0af68", "#7aa2f7", "#bb9af7", "#7dcfff", "#a9b1d6",
            "#414868", "#f7768e", "#9ece6a", "#e0af68", "#7aa2f7", "#bb9af7", "#7dcfff", "#c0caf5",
        ]),
        Preset(name: "Catppuccin Mocha", colors: [
            "#1e1e2e", "#f38ba8", "#a6e3a1", "#f9e2af", "#89b4fa", "#cba6f7", "#94e2d5", "#cdd6f4",
            "#45475a", "#f38ba8", "#a6e3a1", "#f9e2af", "#89b4fa", "#cba6f7", "#94e2d5", "#bac2de",
        ]),
        Preset(name: "One Dark", colors: [
            "#282c34", "#e06c75", "#98c379", "#e5c07b", "#61afef", "#c678dd", "#56b6c2", "#abb2bf",
            "#5c6370", "#e06c75", "#98c379", "#e5c07b", "#61afef", "#c678dd", "#56b6c2", "#ffffff",
        ]),
        Preset(name: "Monokai Pro", colors: [
            "#2d2a2e", "#ff6188", "#a9dc76", "#ffd866", "#fc9867", "#ab9df2", "#78dce8", "#fcfcfa",
            "#727072", "#ff6188", "#a9dc76", "#ffd866", "#fc9867", "#ab9df2", "#78dce8", "#fcfcfa",
        ]),
        Preset(name: "Palenight", colors: [
            "#292d3e", "#f07178", "#c3e88d", "#ffcb6b", "#82aaff", "#c792ea", "#89ddff", "#bfc7d5",
            "#676e95", "#f07178", "#c3e88d", "#ffcb6b", "#82aaff", "#c792ea", "#89ddff", "#ffffff",
        ]),
        Preset(name: "Rose Pine", colors: [
            "#191724", "#eb6f92", "#9ccfd8", "#f6c177", "#31748f", "#c4a7e7", "#ebbcba", "#e0def4",
            "#26233a", "#eb6f92", "#9ccfd8", "#f6c177", "#31748f", "#c4a7e7", "#ebbcba", "#e0def4",
        ]),
        Preset(name: "Everforest", colors: [
            "#2d353b", "#e67e80", "#a7c080", "#dbbc7f", "#7fbbb3", "#d699b6", "#83c092", "#d3c6aa",
            "#475258", "#e67e80", "#a7c080", "#dbbc7f", "#7fbbb3", "#d699b6", "#83c092", "#d3c6aa",
        ]),
        Preset(name: "Matte Black", colors: [
            "#121212", "#D35F5F", "#FFC107", "#b91c1c", "#e68e0d", "#D35F5F", "#bebebe", "#bebebe",
            "#8a8a8d", "#B91C1C", "#FFC107", "#b90a0a", "#f59e0b", "#B91C1C", "#eaeaea", "#ffffff",
        ]),
        Preset(name: "Osaka Jade", colors: [
            "#111c18", "#FF5345", "#549e6a", "#459451", "#509475", "#D2689C", "#2DD5B7", "#C1C497",
            "#53685B", "#db9f9c", "#63b07a", "#E5C736", "#ACD4CF", "#75bbb3", "#8CD3CB", "#9eebb3",
        ]),
        Preset(name: "Ristretto", colors: [
            "#2c2525", "#fd6883", "#adda78", "#f9cc6c", "#f38d70", "#a8a9eb", "#85dacc", "#e6d9db",
            "#948a8b", "#ff8297", "#c8e292", "#fcd675", "#f8a788", "#bebffd", "#9bf1e1", "#f1e5e7",
        ]),
        Preset(name: "Kanagawa", colors: [
            "#1f1f28", "#c34043", "#76946a", "#c0a36e", "#7e9cd8", "#957fb8", "#6a9589", "#dcd7ba",
            "#363646", "#e82424", "#98bb6c", "#e6c384", "#7fb4ca", "#938aa9", "#7aa89f", "#c8c093",
        ]),
        Preset(name: "Nightfox", colors: [
            "#192330", "#c94f6d", "#81b29a", "#dbc074", "#719cd6", "#9d79d6", "#63cdcf", "#cdcecf",
            "#526176", "#c94f6d", "#81b29a", "#dbc074", "#719cd6", "#9d79d6", "#63cdcf", "#cdcecf",
        ]),
        Preset(name: "Ayu Mirage", colors: [
            "#1f2430", "#f28779", "#d5ff80", "#ffd173", "#73d0ff", "#dfbfff", "#95e6cb", "#cbccc6",
            "#707a8c", "#f28779", "#d5ff80", "#ffd173", "#73d0ff", "#dfbfff", "#95e6cb", "#cbccc6",
        ]),
        Preset(name: "Oceanic Next", colors: [
            "#1b2b34", "#ec5f67", "#99c794", "#fac863", "#6699cc", "#c594c5", "#5fb3b3", "#d8dee9",
            "#65737e", "#ec5f67", "#99c794", "#fac863", "#6699cc", "#c594c5", "#5fb3b3", "#d8dee9",
        ]),
        Preset(name: "Horizon", colors: [
            "#1c1e26", "#e95678", "#29d398", "#fab795", "#26bbd9", "#ee64ac", "#59e3e3", "#fadad1",
            "#6c6f93", "#ec6a88", "#3fdaa4", "#fbc3a7", "#3fc4de", "#f075b5", "#6be4e6", "#fadad1",
        ]),
        Preset(name: "Andromeda", colors: [
            "#23262e", "#ee5d43", "#96e072", "#ffe66d", "#00a9f9", "#f92aad", "#4dd9d7", "#d5ced9",
            "#666b81", "#ee5d43", "#96e072", "#ffe66d", "#00a9f9", "#f92aad", "#4dd9d7", "#d5ced9",
        ]),
        Preset(name: "Synthwave 84", colors: [
            "#241b2f", "#fe4450", "#72f1b8", "#fede5d", "#03edf9", "#ff7edb", "#36f9f6", "#f7f7f7",
            "#495495", "#fe4450", "#72f1b8", "#fede5d", "#03edf9", "#ff7edb", "#36f9f6", "#ffffff",
        ]),
        Preset(name: "Solarized Light", colors: [
            "#fdf6e3", "#dc322f", "#859900", "#b58900", "#268bd2", "#d33682", "#2aa198", "#657b83",
            "#eee8d5", "#cb4b16", "#93a1a1", "#839496", "#657b83", "#6c71c4", "#586e75", "#073642",
        ]),
        Preset(name: "Gruvbox Light", colors: [
            "#fbf1c7", "#cc241d", "#98971a", "#d79921", "#458588", "#b16286", "#689d6a", "#3c3836",
            "#ebdbb2", "#9d0006", "#79740e", "#b57614", "#076678", "#8f3f71", "#427b58", "#282828",
        ]),
        Preset(name: "Catppuccin Latte", colors: [
            "#eff1f5", "#d20f39", "#40a02b", "#df8e1d", "#1e66f5", "#ea76cb", "#179299", "#4c4f69",
            "#ccd0da", "#d20f39", "#40a02b", "#df8e1d", "#1e66f5", "#ea76cb", "#179299", "#5c5f77",
        ]),
        Preset(name: "One Light", colors: [
            "#fafafa", "#e45649", "#50a14f", "#c18401", "#4078f2", "#a626a4", "#0184bc", "#383a42",
            "#e5e5e6", "#e45649", "#50a14f", "#c18401", "#4078f2", "#a626a4", "#0184bc", "#090a0b",
        ]),
        Preset(name: "Rose Pine Dawn", colors: [
            "#faf4ed", "#b4637a", "#56949f", "#ea9d34", "#286983", "#907aa9", "#d7827e", "#575279",
            "#fffaf3", "#b4637a", "#56949f", "#ea9d34", "#286983", "#907aa9", "#d7827e", "#575279",
        ]),
        Preset(name: "Everforest Light", colors: [
            "#fdf6e3", "#f85552", "#8da101", "#dfa000", "#3a94c5", "#df69ba", "#35a77c", "#5c6a72",
            "#f0f0f0", "#f85552", "#8da101", "#dfa000", "#3a94c5", "#df69ba", "#35a77c", "#5c6a72",
        ]),
        Preset(name: "Tokyo Night Day", colors: [
            "#d5d6db", "#f52a65", "#587539", "#8c6c3e", "#2e7de9", "#9854f1", "#007197", "#3760bf",
            "#9699a3", "#f52a65", "#587539", "#8c6c3e", "#2e7de9", "#9854f1", "#007197", "#3760bf",
        ]),
        Preset(name: "GitHub Dark", colors: [
            "#0d1117", "#ff7b72", "#3fb950", "#d29922", "#58a6ff", "#bc8cff", "#39c5cf", "#b1bac4",
            "#484f58", "#ffa198", "#56d364", "#e3b341", "#79c0ff", "#d2a8ff", "#56d4dd", "#f0f6fc",
        ]),
        Preset(name: "GitHub Light", colors: [
            "#ffffff", "#cf222e", "#116329", "#4d2d00", "#0969da", "#8250df", "#1b7c83", "#24292f",
            "#f6f8fa", "#a40e26", "#1a7f37", "#633c01", "#0550ae", "#8250df", "#1b7c83", "#1f2328",
        ]),
        Preset(name: "Monochrome Dark", colors: [
            "#000000", "#7c7c7c", "#8b8b8b", "#a0a0a0", "#686868", "#747474", "#868686", "#b9b9b9",
            "#525252", "#7c7c7c", "#8b8b8b", "#a0a0a0", "#686868", "#747474", "#868686", "#ffffff",
        ]),
        Preset(name: "Monochrome Light", colors: [
            "#ffffff", "#5a5a5a", "#6e6e6e", "#808080", "#4a4a4a", "#5e5e5e", "#707070", "#1a1a1a",
            "#d4d4d4", "#5a5a5a", "#6e6e6e", "#808080", "#4a4a4a", "#5e5e5e", "#707070", "#000000",
        ]),
        Preset(name: "Oxocarbon Dark", colors: [
            "#161616", "#3ddbd9", "#33b1ff", "#ee5396", "#42be65", "#be95ff", "#ff7eb6", "#f2f4f8",
            "#525252", "#3ddbd9", "#33b1ff", "#ee5396", "#42be65", "#be95ff", "#ff7eb6", "#08bdba",
        ]),
        Preset(name: "Oxocarbon Light", colors: [
            "#f2f4f8", "#ff7eb6", "#0f62fe", "#ff6f00", "#42be65", "#be95ff", "#673ab7", "#393939",
            "#161616", "#ff7eb6", "#0f62fe", "#ff6f00", "#42be65", "#be95ff", "#673ab7", "#08bdba",
        ]),
    ]
}

// MARK: - Extraction modes

// The 23 extraction methods and their five groups, ported verbatim from
// Aether's EXTRACTION_MODES / EXTRACTION_MODE_GROUPS; `normal`'s label is
// True Colors per the plan. `magic` is Omacosy's own bridge, added in
// Phase 2, and is the default method -- it is not one of the 23.
struct ExtractionMode {
    let value: String
    let label: String
    let group: String
    let description: String
}

struct ExtractionGroup {
    let id: String
    let label: String
    let defaultOpen: Bool
}

enum Modes {
    static let defaultMode = "magic"

    static let groups: [ExtractionGroup] = [
        ExtractionGroup(id: "auto", label: "Auto", defaultOpen: true),
        ExtractionGroup(id: "style", label: "Style", defaultOpen: true),
        ExtractionGroup(id: "theory", label: "Color Theory", defaultOpen: false),
        ExtractionGroup(id: "mood", label: "Mood", defaultOpen: false),
        ExtractionGroup(id: "practical", label: "Practical", defaultOpen: false),
    ]

    static let all: [ExtractionMode] = [
        ExtractionMode(value: "normal",
                       label: "True Colors",
                       group: "auto",
                       description: "Picks monochrome or chromatic based on image analysis"),
        ExtractionMode(value: "monochromatic",
                       label: "Monochromatic",
                       group: "theory",
                       description: "Single hue across all slots, varying lightness"),
        ExtractionMode(value: "analogous",
                       label: "Analogous",
                       group: "theory",
                       description: "Hues within ±30° of the dominant color"),
        ExtractionMode(value: "complementary",
                       label: "Complementary",
                       group: "theory",
                       description: "Base hue alternating with its 180° opposite"),
        ExtractionMode(value: "triadic",
                       label: "Triadic",
                       group: "theory",
                       description: "Three hues evenly spaced at 120°"),
        ExtractionMode(value: "split-complementary",
                       label: "Split-Complementary",
                       group: "theory",
                       description: "Base hue plus 150° and 210° (softer complement)"),
        ExtractionMode(value: "tetradic",
                       label: "Tetradic",
                       group: "theory",
                       description: "Four hues at 90° on the color wheel"),
        ExtractionMode(value: "pastel",
                       label: "Pastel",
                       group: "style",
                       description: "Soft, low chroma, high lightness"),
        ExtractionMode(value: "muted",
                       label: "Muted",
                       group: "style",
                       description: "Subdued, low chroma, lightness-staggered"),
        ExtractionMode(value: "bright",
                       label: "Bright",
                       group: "style",
                       description: "High lightness with healthy chroma"),
        ExtractionMode(value: "colorful",
                       label: "Colorful",
                       group: "style",
                       description: "Vivid, high chroma, mid lightness"),
        ExtractionMode(value: "material",
                       label: "Material",
                       group: "style",
                       description: "Material Design-inspired with fixed bg/fg"),
        ExtractionMode(value: "fire",
                       label: "Fire",
                       group: "mood",
                       description: "Bonfire warmth — deep dark, warm ANSI"),
        ExtractionMode(value: "ocean",
                       label: "Ocean",
                       group: "mood",
                       description: "Deep blue-black, cool-shifted ANSI"),
        ExtractionMode(value: "forest",
                       label: "Forest",
                       group: "mood",
                       description: "Dark green-black, sage-shifted ANSI"),
        ExtractionMode(value: "earthtone",
                       label: "Earthtone",
                       group: "mood",
                       description: "Warm browns and beiges, very low chroma"),
        ExtractionMode(value: "neon",
                       label: "Neon",
                       group: "mood",
                       description: "Cyberpunk: very dark bg, max chroma"),
        ExtractionMode(value: "sunset",
                       label: "Sunset",
                       group: "mood",
                       description: "Warm dark with magenta cast, peach fg"),
        ExtractionMode(value: "vaporwave",
                       label: "Vaporwave",
                       group: "mood",
                       description: "Pinks, purples, cyans on a soft dark"),
        ExtractionMode(value: "midnight",
                       label: "Midnight",
                       group: "mood",
                       description: "Peaceful deep indigo, subdued silver"),
        ExtractionMode(value: "aurora",
                       label: "Aurora",
                       group: "mood",
                       description: "Shimmery green-cyan glow on deep blue-night"),
        ExtractionMode(value: "high-contrast",
                       label: "High Contrast",
                       group: "practical",
                       description: "WCAG AAA (7:1) for maximum readability"),
        ExtractionMode(value: "duotone",
                       label: "Duotone",
                       group: "practical",
                       description: "Two hues only at varying lightness"),
    ]
}

// MARK: - Extraction (Phase 2)

// Ported from Aether (https://github.com/omacom/aether)
// Copyright (c) Bjarne Overli — MIT License
//
// The extraction pipeline: sample an image's pixels in sRGB, quantize them
// in OKLab with median cut, and generate the 16-colour palette. The
// constants and the arithmetic are ported line for line, because the
// recorded fixtures are Aether's own output. All 23 Aether generators are
// here; Magic, the Omacosy bridge, is ported from derive.swift and
// term-palette.swift below.

enum Extract {
    static let ansiPaletteSize = 16
    static let imageScaleSize = 400
    static let minPixelsToSample = 1000
    static let maxPixelsToSample = 50000
    static let dominantColorsToExtract = 48

    // Vivid pixels get duplicated in the median-cut pool so a small saturated
    // accent is not drowned out by a large muted background.
    static let chromaBoostThreshold = 0.04
    static let chromaBoostMaxExtra = 3
    static let chromaBoostRampChroma = 0.16

    static let backgroundDominanceWeight = 0.6

    static let monochromeChromaThreshold = 0.04
    static let monochromeImageThreshold = 0.6
    static let hueClusterMagnitudeThreshold = 0.85
    static let monoChromaticCoverageFloor = 0.06

    static let autoMonoArcDeg = 46.0
    static let explicitMonoArcDeg = 28.0
    static let monoChromaFactorFloor = 0.4
    static let monoAccentMinLStep = 0.072

    static let accentChromaFloor = 0.05
    static let accentChromaCeil = 0.16
    static let nearAchromaticChroma = 0.03
    static let accentMinDeltaE = 0.05
    static let accentSupportChroma = 0.04
    static let hueSupportTol = 30.0
    static let minAccentHueSupport = 0.025

    static let minMeaningfulTintChroma = 0.008

    static let minChromaForAnsiMatch = 0.035
    static let lowChromaThreshold = 0.05
    static let idealChromaMin = 0.06
    static let idealChromaMax = 0.20
    static let tooDarkLightness = 0.25
    static let tooBrightLightness = 0.87

    static let minContrastRatio = 4.5
    static let minHighContrastRatio = 7.0
    static let minCommentContrast = 3.0
    static let minFgBgContrast = 7.0

    static let brightColorLightnessBoost = 0.12
    static let brightColorSaturationBoost = 1.1

    static let darkColorThreshold = 0.50

    static let oklchAnsiHues: [Double] = [29.2, 139.1, 111.3, 266.7, 326.4, 194.8]
    static let canonicalLightnessOrder: [Int] = [3, 0, 4, 1, 5, 2]

    // Aether's DecodeImage guard, kept so extraction refuses the same inputs.
    static let maxImageDimension = 16384
    static let maxImagePixels = 40_000_000
}

func clampF(_ v: Double, _ lo: Double, _ hi: Double) -> Double { max(lo, min(hi, v)) }

// MARK: Median cut in OKLab

struct OKLabBucket {
    var colors: [OKLab]
    var ranges: [[Double]]

    init(_ colors: [OKLab]) {
        self.colors = colors
        self.ranges = [[0, 0], [0, 0], [0, 0]]
        computeRanges()
    }

    mutating func computeRanges() {
        guard let first = colors.first else {
            ranges = [[0, 0], [0, 0], [0, 0]]
            return
        }
        ranges = [[first.l, first.l], [first.a, first.a], [first.b, first.b]]
        for c in colors {
            let vals = [c.l, c.a, c.b]
            for ch in 0..<3 {
                if vals[ch] < ranges[ch][0] { ranges[ch][0] = vals[ch] }
                if vals[ch] > ranges[ch][1] { ranges[ch][1] = vals[ch] }
            }
        }
    }

    func axisRange(_ axis: Int) -> Double { ranges[axis][1] - ranges[axis][0] }

    // Lightness is weighted slightly higher: it is the most perceptible axis.
    func longestAxis() -> Int {
        let lRange = axisRange(0) * 1.2
        let aRange = axisRange(1)
        let bRange = axisRange(2)
        if lRange >= aRange && lRange >= bRange { return 0 }
        if aRange >= bRange { return 1 }
        return 2
    }

    func split() -> (OKLabBucket, OKLabBucket) {
        let axis = longestAxis()
        let sorted = colors.sorted { oklabAxisValue($0, axis) < oklabAxisValue($1, axis) }
        let mid = sorted.count / 2
        return (OKLabBucket(Array(sorted[0..<mid])), OKLabBucket(Array(sorted[mid...])))
    }

    func averageColor() -> (OKLab, Int) {
        let count = colors.count
        if count == 0 { return (OKLab(l: 0, a: 0, b: 0), 0) }
        var lSum = 0.0, aSum = 0.0, bSum = 0.0
        for c in colors {
            lSum += c.l
            aSum += c.a
            bSum += c.b
        }
        let n = Double(count)
        return (OKLab(l: lSum / n, a: aSum / n, b: bSum / n), count)
    }

    func volume() -> Double { axisRange(0) * axisRange(1) * axisRange(2) * Double(colors.count) }
}

func oklabAxisValue(_ c: OKLab, _ axis: Int) -> Double {
    switch axis {
    case 0: return c.l
    case 1: return c.a
    default: return c.b
    }
}

struct ColorEntry { var hex: String; var count: Int }

// Median-cut quantization in OKLab. Returns hex colours with their pixel
// counts; callers sort by count descending.
func medianCut(_ colors: [OKLab], count numColors: Int) -> [ColorEntry] {
    if colors.isEmpty { return [] }
    if colors.count <= numColors { return deduplicateOKLabColors(colors) }

    var buckets: [OKLabBucket] = [OKLabBucket(colors)]
    while buckets.count < numColors {
        let splitIdx = findLargestSplittableOKLabBucket(buckets)
        if splitIdx == -1 { break }
        let (left, right) = buckets[splitIdx].split()
        buckets.remove(at: splitIdx)
        buckets.insert(contentsOf: [left, right], at: splitIdx)
    }

    var result: [ColorEntry] = []
    for bucket in buckets {
        let (avg, count) = bucket.averageColor()
        if count > 0 {
            result.append(ColorEntry(hex: ColorMath.hex(fromOKLab: avg), count: count))
        }
    }
    return result
}

func boostChromaticPixels(_ pixels: [OKLab]) -> [OKLab] {
    var result: [OKLab] = []
    result.reserveCapacity(pixels.count * 2)
    for px in pixels {
        result.append(px)
        let chroma = (px.a * px.a + px.b * px.b).squareRoot()
        if chroma <= Extract.chromaBoostThreshold { continue }
        let t = (chroma - Extract.chromaBoostThreshold) / Extract.chromaBoostRampChroma
        let extra = max(1, min(Int((t * Double(Extract.chromaBoostMaxExtra)).rounded()), Extract.chromaBoostMaxExtra))
        for _ in 0..<extra { result.append(px) }
    }
    return result
}

func deduplicateOKLabColors(_ colors: [OKLab]) -> [ColorEntry] {
    var unique: [ColorEntry] = []
    let threshold = 0.01
    for c in colors {
        var isDuplicate = false
        for u in unique {
            let uLab = ColorMath.oklab(fromHex: u.hex)
            if ColorMath.oklabDistance(c, uLab) < threshold {
                isDuplicate = true
                break
            }
        }
        if !isDuplicate {
            unique.append(ColorEntry(hex: ColorMath.hex(fromOKLab: c), count: 1))
        }
    }
    return unique
}

func findLargestSplittableOKLabBucket(_ buckets: [OKLabBucket]) -> Int {
    var maxVolume = 0.0
    var maxIndex = -1
    for (i, bucket) in buckets.enumerated() {
        if bucket.colors.count > 1 {
            let volume = bucket.volume()
            if volume > maxVolume {
                maxVolume = volume
                maxIndex = i
            }
        }
    }
    return maxIndex
}

// MARK: Dominant colours

func extractDominantColorsFromPixels(_ pixels: [RGB], count: Int) throws -> (colors: [String], counts: [Int]) {
    if pixels.count < Extract.minPixelsToSample / 10 {
        throw ThemeError(message: "not enough pixels to extract colors")
    }
    let labs = pixels.map { ColorMath.oklab(fromSRGB: $0) }
    let boosted = boostChromaticPixels(labs)
    let quantized = medianCut(boosted, count: count)
    if quantized.isEmpty {
        throw ThemeError(message: "no colors extracted from image")
    }
    let sorted = quantized.sorted { $0.count > $1.count }
    return (sorted.map { $0.hex.uppercased() }, sorted.map { $0.count })
}

func extractDominantColors(url: URL, count: Int) throws -> (colors: [String], counts: [Int]) {
    let sample = try sampleImage(url: url)
    return try extractDominantColorsFromPixels(sample.pixels, count: count)
}

// MARK: Analysis

func isDarkColor(_ hex: String) -> Bool {
    ColorMath.oklab(fromHex: hex).l < Extract.darkColorThreshold
}

func hueDistance(_ hue1: Double, _ hue2: Double) -> Double {
    var diff = abs(hue1 - hue2)
    if diff > 180 { diff = 360 - diff }
    return diff
}

func isMonochromeImage(_ colors: [String]) -> Bool {
    if colors.isEmpty { return false }

    var lowChromaCount = 0
    var sinSum = 0.0, cosSum = 0.0
    var chromaticCount = 0

    for c in colors {
        let lch = ColorMath.oklch(fromHex: c)
        if lch.c < Extract.monochromeChromaThreshold {
            lowChromaCount += 1
            continue
        }
        let rad = lch.h * .pi / 180
        sinSum += sin(rad)
        cosSum += cos(rad)
        chromaticCount += 1
    }

    if Double(lowChromaCount) / Double(colors.count) > Extract.monochromeImageThreshold {
        return true
    }

    if chromaticCount >= 4 {
        let mag = (sinSum * sinSum + cosSum * cosSum).squareRoot() / Double(chromaticCount)
        if mag > Extract.hueClusterMagnitudeThreshold { return true }
    }
    return false
}

func isMonochromeWeighted(_ colors: [String], _ weights: [Double]?) -> Bool {
    if colors.isEmpty { return false }
    guard let weights else { return isMonochromeImage(colors) }

    var achroW = 0.0, chromaW = 0.0, sinSum = 0.0, cosSum = 0.0
    for (i, c) in colors.enumerated() {
        let w = i < weights.count ? weights[i] : 0.0
        let lch = ColorMath.oklch(fromHex: c)
        if lch.c < Extract.monochromeChromaThreshold {
            achroW += w
            continue
        }
        chromaW += w
        let rad = lch.h * .pi / 180
        sinSum += sin(rad) * w
        cosSum += cos(rad) * w
    }

    let total = achroW + chromaW
    if total == 0 { return false }
    if chromaW / total < Extract.monoChromaticCoverageFloor { return true }
    let mag = (sinSum * sinSum + cosSum * cosSum).squareRoot() / chromaW
    return mag > Extract.hueClusterMagnitudeThreshold
}

func findColorByPerceptualLightness(_ colors: [String], _ weights: [Double]?, _ findLightest: Bool,
                                    _ excludeIndices: Set<Int>?) -> (String, Int) {
    var bestIndex = 0
    var bestScore = -Double.infinity

    for i in 0..<colors.count {
        if let excludeIndices, excludeIndices.contains(i) { continue }

        let lab = ColorMath.oklab(fromHex: colors[i])
        var score = lab.l
        if !findLightest { score = 1 - lab.l }
        if let weights, i < weights.count {
            score += Extract.backgroundDominanceWeight * weights[i]
        }

        if score > bestScore {
            bestScore = score
            bestIndex = i
        }
    }
    return (colors[bestIndex], bestIndex)
}

func findBackgroundColor(_ colors: [String], _ weights: [Double]?, _ lightMode: Bool) -> (String, Int) {
    findColorByPerceptualLightness(colors, weights, lightMode, nil)
}

func findForegroundColor(_ colors: [String], _ weights: [Double]?, _ lightMode: Bool,
                         _ bgColor: String, _ usedIndices: Set<Int>) -> (String, Int) {
    let (fgColor, fgIndex) = findColorByPerceptualLightness(colors, weights, !lightMode, usedIndices)

    let contrast = ColorMath.contrastRatio(bgColor, fgColor)
    if contrast >= Extract.minFgBgContrast { return (fgColor, fgIndex) }

    var candidates: [(index: Int, contrast: Double)] = []
    for (i, c) in colors.enumerated() {
        if usedIndices.contains(i) { continue }
        let cr = ColorMath.contrastRatio(bgColor, c)
        if cr > contrast { candidates.append((i, cr)) }
    }
    candidates.sort { $0.contrast > $1.contrast }

    if let best = candidates.first, best.contrast >= Extract.minContrastRatio {
        return (colors[best.index], best.index)
    }

    // Synthesize at the contrast extreme; -1 means "not a pool colour".
    var fgLab = ColorMath.oklab(fromHex: fgColor)
    let bgLab = ColorMath.oklab(fromHex: bgColor)
    fgLab.l = bgLab.l < 0.5 ? 0.97 : 0.05
    return (ColorMath.hex(fromOKLab: fgLab), -1)
}

func calculateColorScore(_ lch: OKLCH, _ targetHue: Double, _ lightMode: Bool) -> Double {
    let hueScore = hueDistance(lch.h, targetHue) * 2.0

    var chromaScore: Double
    if lch.c < Extract.minChromaForAnsiMatch {
        chromaScore = 80
    } else if lch.c < Extract.lowChromaThreshold {
        chromaScore = 40
    } else if lch.c < Extract.idealChromaMin {
        chromaScore = 15
    } else if lch.c <= Extract.idealChromaMax {
        chromaScore = 0
    } else {
        chromaScore = (lch.c - Extract.idealChromaMax) * 50
    }

    let idealL = lightMode ? 0.45 : 0.60

    var lightnessScore: Double
    if lch.l < Extract.tooDarkLightness {
        lightnessScore = (Extract.tooDarkLightness - lch.l) * 200
    } else if lch.l > Extract.tooBrightLightness {
        lightnessScore = (lch.l - Extract.tooBrightLightness) * 150
    } else {
        lightnessScore = abs(lch.l - idealL) * 20
    }

    return hueScore + chromaScore + lightnessScore
}

func findBestColorMatch(_ targetHue: Double, _ colorPool: [String], _ usedIndices: Set<Int>, _ lightMode: Bool) -> Int {
    var bestIndex = -1
    var bestScore = Double.infinity

    for i in 0..<colorPool.count {
        if usedIndices.contains(i) { continue }
        let lch = ColorMath.oklch(fromHex: colorPool[i])
        let score = calculateColorScore(lch, targetHue, lightMode)
        if score < bestScore {
            bestScore = score
            bestIndex = i
        }
    }

    if bestIndex != -1 { return bestIndex }
    return 0
}

func generateBrightVersion(_ hex: String) -> String {
    let lab = ColorMath.oklab(fromHex: hex)
    let lch = ColorMath.oklch(fromOKLab: lab)

    if lab.l >= 0.78 {
        let newL = min(0.94, lab.l + 0.04)
        let newC = min(0.32, max(lch.c + 0.04, lch.c * 1.3))
        return ColorMath.hex(fromOKLCH: OKLCH(l: newL, c: newC, h: lch.h))
    }

    let headroom = 0.92 - lab.l
    let boost = max(0.04, min(Extract.brightColorLightnessBoost, headroom * 0.6))
    let newL = min(0.92, lab.l + boost)
    let newC = min(0.30, lch.c * Extract.brightColorSaturationBoost)

    return ColorMath.hex(fromOKLCH: OKLCH(l: newL, c: newC, h: lch.h))
}

struct ColorLightnessInfo {
    var color: String
    var lightness: Double
    var hue: Double
}

func sortColorsByLightness(_ colors: [String]) -> [ColorLightnessInfo] {
    colors.map { c in
        let lch = ColorMath.oklch(fromHex: c)
        return ColorLightnessInfo(color: c, lightness: lch.l, hue: lch.h)
    }.sorted { $0.lightness < $1.lightness }
}

struct AnsiAssignment {
    var poolIndex: Int
    var score: Double
}

// Global greedy matching: at each step the best (ANSI slot, colour) pair is
// taken, so earlier slots cannot steal a later slot's best match.
func findOptimalAnsiAssignment(_ colorPool: [String], _ usedIndices: Set<Int>, _ lightMode: Bool) -> [AnsiAssignment?] {
    var allScores: [[(poolIndex: Int, score: Double)]] = []
    for a in 0..<6 {
        let targetHue = Extract.oklchAnsiHues[a]
        var candidates: [(poolIndex: Int, score: Double)] = []
        for (i, c) in colorPool.enumerated() {
            if usedIndices.contains(i) {
                candidates.append((i, .infinity))
            } else {
                let lch = ColorMath.oklch(fromHex: c)
                candidates.append((i, calculateColorScore(lch, targetHue, lightMode)))
            }
        }
        candidates.sort { $0.score < $1.score }
        allScores.append(candidates)
    }

    var assignments: [AnsiAssignment?] = Array(repeating: nil, count: 6)
    var assignedPoolIndices = usedIndices

    for _ in 0..<6 {
        var bestAnsi = -1
        var bestPoolIndex = -1
        var bestScore = Double.infinity

        for a in 0..<6 {
            if assignments[a] != nil { continue }
            for cand in allScores[a] {
                if assignedPoolIndices.contains(cand.poolIndex) { continue }
                if cand.score < bestScore {
                    bestScore = cand.score
                    bestAnsi = a
                    bestPoolIndex = cand.poolIndex
                }
                break // the list is sorted: the first unassigned is the best
            }
        }

        if bestAnsi == -1 { break }
        assignments[bestAnsi] = AnsiAssignment(poolIndex: bestPoolIndex, score: bestScore)
        assignedPoolIndices.insert(bestPoolIndex)
    }

    return assignments
}

// MARK: Chromatic palette

func extractChromaticHues(_ dominantColors: [String], _ weights: [Double]?, _ lightMode: Bool) -> [String] {
    let topCount = min(12, dominantColors.count)
    let topColors = Array(dominantColors[0..<topCount])
    let topWeights: [Double]? = weights.map { Array($0.prefix(topCount)) }

    var (bgColor, bgIndex) = findBackgroundColor(topColors, topWeights, lightMode)
    bgColor = synthesizeBgIfTooMid(bgColor, lightMode)
    var usedIndices: Set<Int> = [bgIndex]

    let (fgColor, fgIndex) = findForegroundColor(dominantColors, weights, lightMode, bgColor, usedIndices)
    if fgIndex >= 0 { usedIndices.insert(fgIndex) }

    var palette = Array(repeating: "", count: 16)
    palette[0] = bgColor
    palette[7] = fgColor

    // Callers guarantee at least 8 dominant colours and at most 2 pre-claimed,
    // so all six ANSI slots are filled; a direct caller with fewer gets a clear
    // error instead of a crash.
    let assignments = findOptimalAnsiAssignment(dominantColors, usedIndices, lightMode)
    for i in 0..<6 {
        guard let assignment = assignments[i] else {
            fail("the chromatic generator needs at least 8 dominant colours")
        }
        palette[i + 1] = dominantColors[assignment.poolIndex]
        usedIndices.insert(assignment.poolIndex)
    }

    return palette
}

func synthesizeBgIfTooMid(_ bgColor: String, _ lightMode: Bool) -> String {
    let lch = ColorMath.oklch(fromHex: bgColor)
    if lightMode {
        if lch.l >= 0.85 { return bgColor }
        return ColorMath.hex(fromOKLCH: OKLCH(l: 0.94, c: min(lch.c, 0.04), h: lch.h))
    }
    if lch.l <= 0.20 { return bgColor }
    return ColorMath.hex(fromOKLCH: OKLCH(l: 0.12, c: min(lch.c, 0.05), h: lch.h))
}

struct HueCluster {
    var hue: Double
    var coverage: Double
}

// A coverage-weighted hue histogram: the hue bands real chromatic pixels
// actually occupy, at least MinAccentHueSupport of the frame each. Accents
// are only allowed to use these hues.
func supportedHueClusters(_ dominantColors: [String], _ weights: [Double]?) -> [HueCluster] {
    let bins = 12 // 30-degree bands
    var binW = Array(repeating: 0.0, count: bins)
    var binSin = Array(repeating: 0.0, count: bins)
    var binCos = Array(repeating: 0.0, count: bins)

    for (k, c) in dominantColors.enumerated() {
        let lch = ColorMath.oklch(fromHex: c)
        if lch.c < Extract.accentSupportChroma { continue }
        var w = 1.0 / Double(dominantColors.count)
        if let weights, k < weights.count { w = weights[k] }
        var b = Int(lch.h / 30) % bins
        if b < 0 { b += bins }
        let rad = lch.h * .pi / 180
        binW[b] += w
        binSin[b] += sin(rad) * w
        binCos[b] += cos(rad) * w
    }

    var out: [HueCluster] = []
    for b in 0..<bins where binW[b] >= Extract.minAccentHueSupport {
        let raw = atan2(binSin[b], binCos[b]) * 180 / .pi + 360
        out.append(HueCluster(hue: raw.truncatingRemainder(dividingBy: 360), coverage: binW[b]))
    }
    return out
}

func nearestClusterHue(_ target: Double, _ clusters: [HueCluster]) -> (Double, Bool) {
    var best = Double.infinity
    var bestHue = 0.0
    for c in clusters {
        let d = hueDistance(target, c.hue)
        if d < best {
            best = d
            bestHue = c.hue
        }
    }
    return (bestHue, !clusters.isEmpty)
}

func normalizeChromaticAccents(_ p: inout [String], _ dominantColors: [String], _ weights: [Double]?, _ lightMode: Bool) {
    let target = clampF(salientChroma(dominantColors) * 0.85, Extract.accentChromaFloor, Extract.accentChromaCeil)
    let clusters = supportedHueClusters(dominantColors, weights)

    for i in 1...6 {
        var lch = ColorMath.oklch(fromHex: p[i])
        let grayPick = lch.c < Extract.nearAchromaticChroma
        var supported = false
        for cl in clusters {
            if hueDistance(lch.h, cl.hue) <= Extract.hueSupportTol {
                supported = true
                break
            }
        }
        if grayPick || !supported {
            let (h, ok) = nearestClusterHue(Extract.oklchAnsiHues[i - 1], clusters)
            if ok {
                lch.h = h
            } else if grayPick {
                lch.c = 0
            }
        }
        if lch.c > 0 && lch.c < target { lch.c = target }
        p[i] = ColorMath.hex(fromOKLCH: lch)
    }

    // Lightness-only distinctness pass.
    for i in 1...6 {
        for j in stride(from: i + 1, through: 6, by: 1) {
            if ColorMath.oklabDistance(ColorMath.oklab(fromHex: p[i]), ColorMath.oklab(fromHex: p[j])) < Extract.accentMinDeltaE {
                var lch = ColorMath.oklch(fromHex: p[j])
                if lightMode {
                    lch.l = clampF(lch.l - 0.10, 0.20, 0.85)
                } else {
                    lch.l = clampF(lch.l + 0.10, 0.30, 0.92)
                }
                p[j] = ColorMath.hex(fromOKLCH: lch)
            }
        }
    }
}

func generateCommentColor(_ bgColor: String) -> String {
    let bgLab = ColorMath.oklab(fromHex: bgColor)
    let bgLch = ColorMath.oklch(fromOKLab: bgLab)

    var targetL: Double
    if bgLab.l < 0.5 {
        targetL = min(1.0, bgLab.l + 0.30)
    } else {
        targetL = max(0.0, bgLab.l - 0.30)
    }

    let commentChroma = 0.01
    var commentColor = ColorMath.hex(fromOKLCH: OKLCH(l: targetL, c: commentChroma, h: bgLch.h))

    var contrast = ColorMath.contrastRatio(bgColor, commentColor)
    if contrast < Extract.minCommentContrast {
        let step = 0.05
        if bgLab.l < 0.5 {
            while targetL < 0.95 && contrast < Extract.minCommentContrast {
                targetL += step
                commentColor = ColorMath.hex(fromOKLCH: OKLCH(l: targetL, c: commentChroma, h: bgLch.h))
                contrast = ColorMath.contrastRatio(bgColor, commentColor)
            }
        } else {
            while targetL > 0.05 && contrast < Extract.minCommentContrast {
                targetL -= step
                commentColor = ColorMath.hex(fromOKLCH: OKLCH(l: targetL, c: commentChroma, h: bgLch.h))
                contrast = ColorMath.contrastRatio(bgColor, commentColor)
            }
        }
    }

    return commentColor
}

func boostContrastAgainstBg(_ hex: String, _ bgColor: String, _ targetRatio: Double) -> String {
    let lab = ColorMath.oklab(fromHex: hex)
    var lch = ColorMath.oklch(fromOKLab: lab)
    let bgLab = ColorMath.oklab(fromHex: bgColor)

    let step = 0.03
    if bgLab.l < 0.5 {
        while lch.l < 0.95 {
            lch.l += step
            let candidate = ColorMath.hex(fromOKLCH: lch)
            if ColorMath.contrastRatio(bgColor, candidate) >= targetRatio { return candidate }
        }
    } else {
        while lch.l > 0.05 {
            lch.l -= step
            let candidate = ColorMath.hex(fromOKLCH: lch)
            if ColorMath.contrastRatio(bgColor, candidate) >= targetRatio { return candidate }
        }
    }

    return ColorMath.hex(fromOKLCH: lch)
}

func generateChromaticPalette(_ dominantColors: [String], _ weights: [Double]?, _ lightMode: Bool) -> [String] {
    var palette = extractChromaticHues(dominantColors, weights, lightMode)
    normalizeChromaticAccents(&palette, dominantColors, weights, lightMode)
    finalizePalette(&palette)
    return palette
}

// MARK: Monochrome / monochromatic palettes

func synthesizeMonoBgIfMuddy(_ bgColor: String, _ lightMode: Bool) -> String {
    let lch = ColorMath.oklch(fromHex: bgColor)
    if lightMode {
        if lch.l >= 0.75 { return bgColor }
        return ColorMath.hex(fromOKLCH: OKLCH(l: 0.94, c: min(lch.c, 0.04), h: lch.h))
    }
    if lch.l <= 0.35 { return bgColor }
    return ColorMath.hex(fromOKLCH: OKLCH(l: 0.14, c: min(lch.c, 0.06), h: lch.h))
}

func detectMonochromeTint(_ colors: [String]) -> (hue: Double, hasTint: Bool, tintStrength: Double) {
    if colors.isEmpty { return (0, false, 0) }
    var sinSum = 0.0, cosSum = 0.0, chromaSum = 0.0

    for c in colors {
        let lch = ColorMath.oklch(fromHex: c)
        if lch.c > 0.005 {
            let weight = lch.c
            let rad = lch.h * .pi / 180
            sinSum += sin(rad) * weight
            cosSum += cos(rad) * weight
            chromaSum += weight
        }
    }

    let avgChroma = chromaSum / Double(colors.count)
    if avgChroma < Extract.minMeaningfulTintChroma { return (0, false, 0) }

    let meanSin = sinSum / chromaSum
    let meanCos = cosSum / chromaSum
    let raw = atan2(meanSin, meanCos) * 180 / .pi + 360
    let avgHue = raw.truncatingRemainder(dividingBy: 360)
    let concentration = (meanSin * meanSin + meanCos * meanCos).squareRoot()
    return (avgHue, true, concentration * avgChroma)
}

func salientChroma(_ colors: [String]) -> Double {
    if colors.isEmpty { return 0 }
    var chromas = colors.map { ColorMath.oklch(fromHex: $0).c }
    chromas.sort()
    let idx = Int((0.9 * Double(chromas.count - 1)).rounded())
    return chromas[idx]
}

func mean6(_ v: [Double]) -> Double { v.reduce(0, +) / 6 }

func monoChromaFactor(_ dominantColors: [String], _ refMean: Double) -> Double {
    clampF(salientChroma(dominantColors) / refMean, Extract.monoChromaFactorFloor, 1.0)
}

func foldHueIntoArc(_ canonicalHue: Double, _ baseHue: Double, _ arcDeg: Double) -> Double {
    let d = (canonicalHue - baseHue + 540).truncatingRemainder(dividingBy: 360) - 180
    return (baseHue + (d / 180.0) * arcDeg + 360).truncatingRemainder(dividingBy: 360)
}

func monoAccentRamp(_ bg: String, _ lightMode: Bool) -> [Double] {
    var start: Double, step: Double
    if lightMode {
        let hi = neutralReadableL(bg, true, Extract.minContrastRatio) - 0.02
        start = hi
        step = -max(Extract.monoAccentMinLStep, (hi - 0.16) / 5.0)
    } else {
        let lo = neutralReadableL(bg, false, Extract.minContrastRatio) + 0.02
        start = lo
        step = max(Extract.monoAccentMinLStep, (0.92 - lo) / 5.0)
    }

    var slotL = Array(repeating: 0.0, count: 6)
    for (pos, slot) in Extract.canonicalLightnessOrder.enumerated() {
        slotL[slot] = clampF(start + step * Double(pos), 0.06, 0.97)
    }
    return slotL
}

func ensureMonoHeadroom(_ bg: String, _ lightMode: Bool) -> String {
    let lch = ColorMath.oklch(fromHex: bg)
    if lightMode {
        if neutralReadableL(bg, true, Extract.minContrastRatio) < 0.42 {
            return ColorMath.hex(fromOKLCH: OKLCH(l: 0.95, c: min(lch.c, 0.04), h: lch.h))
        }
        return bg
    }
    if neutralReadableL(bg, false, Extract.minContrastRatio) > 0.60 {
        return ColorMath.hex(fromOKLCH: OKLCH(l: 0.13, c: min(lch.c, 0.06), h: lch.h))
    }
    return bg
}

func generateMonochromePalette(_ grayColors: [String], _ lightMode: Bool) -> [String] {
    let (tintHue, hasTint, _) = detectMonochromeTint(grayColors)
    if !hasTint {
        return generateGrayscaleMonochromaticPalette(grayColors, lightMode)
    }
    return generateTintedMonochromaticPalette(grayColors, lightMode, tintHue, Extract.autoMonoArcDeg)
}

func generateMonochromaticPalette(_ dominantColors: [String], _ lightMode: Bool) -> [String] {
    let (tintHue, hasTint, _) = detectMonochromeTint(dominantColors)
    if !hasTint {
        return generateGrayscaleMonochromaticPalette(dominantColors, lightMode)
    }
    return generateTintedMonochromaticPalette(dominantColors, lightMode, tintHue, Extract.explicitMonoArcDeg)
}

func neutralReadableL(_ bg: String, _ lightMode: Bool, _ ratio: Double) -> Double {
    func gray(_ l: Double) -> String { ColorMath.hex(fromOKLCH: OKLCH(l: l, c: 0, h: 0)) }
    if !lightMode {
        var l = 0.20
        while l <= 0.95 {
            if ColorMath.contrastRatio(bg, gray(l)) >= ratio { return l }
            l += 0.01
        }
        return 0.55
    }
    var l = 0.80
    while l >= 0.05 {
        if ColorMath.contrastRatio(bg, gray(l)) >= ratio { return l }
        l -= 0.01
    }
    return 0.45
}

func generateGrayscaleMonochromaticPalette(_ dominantColors: [String], _ lightMode: Bool) -> [String] {
    let sortedByLightness = sortColorsByLightness(dominantColors)
    let darkest = sortedByLightness[0]
    let lightest = sortedByLightness[sortedByLightness.count - 1]

    var palette = Array(repeating: "", count: 16)

    if lightMode {
        palette[0] = ColorMath.hex(fromOKLCH: OKLCH(l: max(0.94, lightest.lightness), c: 0, h: 0))
        palette[7] = ColorMath.hex(fromOKLCH: OKLCH(l: min(0.22, darkest.lightness), c: 0, h: 0))
    } else {
        palette[0] = ColorMath.hex(fromOKLCH: OKLCH(l: min(0.14, darkest.lightness), c: 0, h: 0))
        palette[7] = ColorMath.hex(fromOKLCH: OKLCH(l: max(0.88, lightest.lightness), c: 0, h: 0))
    }

    palette[0] = ensureMonoHeadroom(palette[0], lightMode)
    let slotL = monoAccentRamp(palette[0], lightMode)
    for i in 0..<6 {
        palette[i + 1] = ColorMath.hex(fromOKLCH: OKLCH(l: slotL[i], c: 0, h: 0))
    }

    palette[8] = generateCommentColor(palette[0])

    let bump = lightMode ? -0.06 : 0.06
    for i in 0..<6 {
        let l = max(0.05, min(0.97, slotL[i] + bump))
        palette[i + 9] = ColorMath.hex(fromOKLCH: OKLCH(l: l, c: 0, h: 0))
    }

    palette[15] = lightMode
        ? ColorMath.hex(fromOKLCH: OKLCH(l: 0.04, c: 0, h: 0))
        : ColorMath.hex(fromOKLCH: OKLCH(l: 0.99, c: 0, h: 0))

    return palette
}

func generateTintedMonochromaticPalette(_ dominantColors: [String], _ lightMode: Bool,
                                        _ baseHue: Double, _ arcDeg: Double) -> [String] {
    let sortedByLightness = sortColorsByLightness(dominantColors)
    let darkest = sortedByLightness[0]
    let lightest = sortedByLightness[sortedByLightness.count - 1]

    var palette = Array(repeating: "", count: 16)

    if lightMode {
        palette[0] = synthesizeMonoBgIfMuddy(lightest.color, lightMode)
        palette[7] = darkest.color
    } else {
        palette[0] = synthesizeMonoBgIfMuddy(darkest.color, lightMode)
        palette[7] = lightest.color
    }
    palette[0] = ensureMonoHeadroom(palette[0], lightMode)

    if ColorMath.contrastRatio(palette[0], palette[7]) < Extract.minFgBgContrast {
        let bgLab = ColorMath.oklab(fromHex: palette[0])
        var fgLab = ColorMath.oklab(fromHex: palette[7])
        fgLab.l = bgLab.l < 0.5 ? 0.97 : 0.05
        palette[7] = ColorMath.hex(fromOKLab: fgLab)
    }

    let chromaLevels: [Double] = [0.09, 0.11, 0.13, 0.10, 0.12, 0.14]
    let brightChromaLevels: [Double] = [0.11, 0.14, 0.16, 0.12, 0.15, 0.17]
    let chromaFactor = monoChromaFactor(dominantColors, mean6(chromaLevels))

    let slotL = monoAccentRamp(palette[0], lightMode)

    for i in 0..<6 {
        let hue = foldHueIntoArc(Extract.oklchAnsiHues[i], baseHue, arcDeg)
        palette[i + 1] = ColorMath.hex(fromOKLCH: OKLCH(l: slotL[i], c: chromaLevels[i] * chromaFactor, h: hue))
    }

    palette[8] = generateCommentColor(palette[0])

    let brightAdj = lightMode ? -0.07 : 0.07
    for i in 0..<6 {
        let hue = foldHueIntoArc(Extract.oklchAnsiHues[i], baseHue, arcDeg)
        let l = clampF(slotL[i] + brightAdj, 0.18, 0.96)
        palette[i + 9] = ColorMath.hex(fromOKLCH: OKLCH(l: l, c: brightChromaLevels[i] * chromaFactor, h: hue))
    }

    palette[15] = lightMode
        ? ColorMath.hex(fromOKLCH: OKLCH(l: 0.08, c: 0.03, h: baseHue))
        : ColorMath.hex(fromOKLCH: OKLCH(l: 0.97, c: 0.015, h: baseHue))

    return palette
}

// MARK: Style, scheme, mood and practical generators (Phase 2b)

// `oklchRule` shapes an OKLCH colour into a mode-specific output, one rule
// per ladder. Ported from Aether's palette_modes.go.
struct OklchRule {
    let light: (OKLCH) -> OKLCH
    let dark: (OKLCH) -> OKLCH

    func apply(_ lch: OKLCH, _ lightMode: Bool) -> OKLCH {
        lightMode ? light(lch) : dark(lch)
    }
}

// pullHueToward shifts a hue toward target by strength along the shorter arc.
func pullHueToward(_ hue: Double, _ target: Double, _ strength: Double) -> Double {
    let diff = (target - hue + 540).truncatingRemainder(dividingBy: 360) - 180
    return (hue + diff * strength + 360).truncatingRemainder(dividingBy: 360)
}

// The hue of the image's most chromatic dominant colour: the colour identity
// the schemes and moods pivot on. Achromatic images report 0 (red).
func extractDominantHue(_ dominantColors: [String]) -> Double {
    var hue = 0.0
    var bestChroma = 0.0
    for c in dominantColors {
        let lch = ColorMath.oklch(fromHex: c)
        if lch.c > bestChroma {
            bestChroma = lch.c
            hue = lch.h
        }
    }
    return hue
}

// transformChromaticPalette extracts image-derived hues and rebuilds the
// palette in OKLCH through the three rules, then derives slots 8/9-15 and
// enforces AA contrast against the transformed background.
func transformChromaticPalette(_ dominantColors: [String], _ lightMode: Bool,
                               _ bgRule: OklchRule, _ fgRule: OklchRule, _ ansiRule: OklchRule,
                               _ ansiLightnessOffsets: [Double]) -> [String] {
    let base = extractChromaticHues(dominantColors, nil, lightMode)

    var result = Array(repeating: "", count: 16)
    result[0] = ColorMath.hex(fromOKLCH: bgRule.apply(ColorMath.oklch(fromHex: base[0]), lightMode))
    result[7] = ColorMath.hex(fromOKLCH: fgRule.apply(ColorMath.oklch(fromHex: base[7]), lightMode))

    for i in 0..<6 {
        var shaped = ansiRule.apply(ColorMath.oklch(fromHex: base[i + 1]), lightMode)
        shaped.l = clampF(shaped.l + ansiLightnessOffsets[i], 0.05, 0.95)
        result[i + 1] = ColorMath.hex(fromOKLCH: shaped)
    }

    finalizePalette(&result)
    return result
}

func generatePastelPalette(_ dominantColors: [String], _ lightMode: Bool) -> [String] {
    let bgRule = OklchRule(
        light: { OKLCH(l: 0.96, c: 0.012, h: $0.h) },
        dark: { OKLCH(l: 0.20, c: 0.022, h: $0.h) })
    let fgRule = OklchRule(
        light: { OKLCH(l: 0.32, c: 0.05, h: $0.h) },
        dark: { OKLCH(l: 0.85, c: 0.04, h: $0.h) })
    let ansiRule = OklchRule(
        light: { OKLCH(l: 0.55, c: clampF($0.c, 0.045, 0.07), h: $0.h) },
        dark: { OKLCH(l: 0.78, c: clampF($0.c, 0.05, 0.075), h: $0.h) })
    let stagger: [Double] = [-0.04, +0.02, +0.05, -0.03, -0.01, +0.03]
    return transformChromaticPalette(dominantColors, lightMode, bgRule, fgRule, ansiRule, stagger)
}

func generateColorfulPalette(_ dominantColors: [String], _ lightMode: Bool) -> [String] {
    let bgRule = OklchRule(
        light: { OKLCH(l: 0.97, c: 0.012, h: $0.h) },
        dark: { OKLCH(l: 0.10, c: 0.022, h: $0.h) })
    let fgRule = OklchRule(
        light: { OKLCH(l: 0.18, c: 0.04, h: $0.h) },
        dark: { OKLCH(l: 0.92, c: 0.03, h: $0.h) })
    let ansiRule = OklchRule(
        light: { OKLCH(l: 0.50, c: clampF(max($0.c, 0.14), 0.14, 0.20), h: $0.h) },
        dark: { OKLCH(l: 0.65, c: clampF(max($0.c, 0.14), 0.14, 0.20), h: $0.h) })
    let stagger: [Double] = [-0.05, +0.02, +0.06, -0.03, -0.02, +0.04]
    return transformChromaticPalette(dominantColors, lightMode, bgRule, fgRule, ansiRule, stagger)
}

// Muted: low chroma, subdued, with a widened lightness stagger because the
// slots cannot lean on chroma differences for distinguishability.
func generateMutedPalette(_ dominantColors: [String], _ lightMode: Bool) -> [String] {
    let bgRule = OklchRule(
        light: { OKLCH(l: 0.94, c: 0.010, h: $0.h) },
        dark: { OKLCH(l: 0.16, c: 0.018, h: $0.h) })
    let fgRule = OklchRule(
        light: { OKLCH(l: 0.28, c: 0.045, h: $0.h) },
        dark: { OKLCH(l: 0.84, c: 0.035, h: $0.h) })
    let ansiRule = OklchRule(
        light: { OKLCH(l: 0.48, c: clampF($0.c * 0.5, 0.035, 0.065), h: $0.h) },
        dark: { OKLCH(l: 0.62, c: clampF($0.c * 0.5, 0.035, 0.065), h: $0.h) })
    let stagger: [Double] = [-0.10, -0.04, +0.04, +0.10, -0.07, +0.07]
    return transformChromaticPalette(dominantColors, lightMode, bgRule, fgRule, ansiRule, stagger)
}

func generateBrightPalette(_ dominantColors: [String], _ lightMode: Bool) -> [String] {
    let bgRule = OklchRule(
        light: { OKLCH(l: 0.98, c: 0.010, h: $0.h) },
        dark: { OKLCH(l: 0.10, c: 0.020, h: $0.h) })
    let fgRule = OklchRule(
        light: { OKLCH(l: 0.15, c: 0.04, h: $0.h) },
        dark: { OKLCH(l: 0.92, c: 0.025, h: $0.h) })
    let ansiRule = OklchRule(
        light: { OKLCH(l: 0.42, c: clampF(max($0.c, 0.10), 0.10, 0.18), h: $0.h) },
        dark: { OKLCH(l: 0.78, c: clampF(max($0.c, 0.10), 0.10, 0.18), h: $0.h) })
    let stagger: [Double] = [-0.04, +0.01, +0.06, -0.03, -0.02, +0.03]
    return transformChromaticPalette(dominantColors, lightMode, bgRule, fgRule, ansiRule, stagger)
}

// Material Design-inspired, HSL rather than OKLCH like the other modes: the
// spec fixes the neutral bg/fg and an HSL accent contract, so porting this
// to OKLCH would drift from the spec.
func generateMaterialPalette(_ dominantColors: [String], _ lightMode: Bool) -> [String] {
    var palette = Array(repeating: "", count: 16)
    var usedIndices = Set<Int>()

    palette[0] = lightMode ? "#fafafa" : "#121212"
    palette[7] = lightMode ? "#212121" : "#ffffff"

    for i in 0..<Extract.oklchAnsiHues.count {
        let matchIndex = findBestColorMatch(Extract.oklchAnsiHues[i], dominantColors, usedIndices, lightMode)
        let matchedColor = dominantColors[matchIndex]
        let hsl = ColorMath.hsl(fromHex: matchedColor)

        let refinedSaturation = max(hsl.s, 35)
        let refinedLightness = lightMode ? max(35, min(60, hsl.l)) : max(45, min(70, hsl.l))

        palette[i + 1] = ColorMath.hex(fromHSL: HSL(h: hsl.h, s: refinedSaturation, l: refinedLightness))
        usedIndices.insert(matchIndex)
    }

    palette[8] = lightMode ? "#757575" : "#9e9e9e"

    for i in 1...6 {
        let hsl = ColorMath.hsl(fromHex: palette[i])
        let brightSaturation = min(100, hsl.s + 8)
        let brightLightness = lightMode ? max(30, hsl.l - 8) : min(75, hsl.l + 8)
        palette[i + 8] = ColorMath.hex(fromHSL: HSL(h: hsl.h, s: brightSaturation, l: brightLightness))
    }

    palette[15] = lightMode ? "#000000" : "#ffffff"
    return palette
}

// Analogous: ±30° around the dominant hue, lightness alternating between
// dim and bright slots so six close hues stay distinguishable.
func generateAnalogousPalette(_ dominantColors: [String], _ lightMode: Bool) -> [String] {
    let baseHue = extractDominantHue(dominantColors)
    let sortedByLightness = sortColorsByLightness(dominantColors)
    let darkest = sortedByLightness[0]
    let lightest = sortedByLightness[sortedByLightness.count - 1]

    var palette = Array(repeating: "", count: 16)

    if lightMode {
        palette[0] = ColorMath.hex(fromOKLCH: OKLCH(l: max(0.92, lightest.lightness), c: 0.02, h: baseHue))
        palette[7] = ColorMath.hex(fromOKLCH: OKLCH(l: min(0.28, darkest.lightness + 0.05), c: 0.04, h: baseHue))
    } else {
        palette[0] = ColorMath.hex(fromOKLCH: OKLCH(l: min(0.16, darkest.lightness), c: 0.03, h: baseHue))
        palette[7] = ColorMath.hex(fromOKLCH: OKLCH(l: max(0.88, lightest.lightness - 0.05), c: 0.025, h: baseHue))
    }

    let analogousOffsets: [Double] = [-30, -18, -6, 6, 18, 30]
    let chromaLevels: [Double] = [0.10, 0.13, 0.09, 0.14, 0.10, 0.12]
    let lightnessStagger: [Double] = [-0.06, +0.04, -0.04, +0.06, -0.05, +0.05]
    let lightnessBase = lightMode ? 0.50 : 0.62

    for i in 0..<6 {
        let hue = (baseHue + analogousOffsets[i] + 360).truncatingRemainder(dividingBy: 360)
        let lightness = clampF(lightnessBase + lightnessStagger[i], 0.30, 0.85)
        palette[i + 1] = ColorMath.hex(fromOKLCH: OKLCH(l: lightness, c: chromaLevels[i], h: hue))
    }

    palette[8] = generateCommentColor(palette[0])

    for i in 0..<6 {
        let hue = (baseHue + analogousOffsets[i] + 360).truncatingRemainder(dividingBy: 360)
        var brightL = clampF(lightnessBase + lightnessStagger[i] + 0.10, 0.30, 0.92)
        if lightMode { brightL = clampF(lightnessBase + lightnessStagger[i] - 0.10, 0.20, 0.70) }
        palette[i + 9] = ColorMath.hex(fromOKLCH: OKLCH(l: brightL, c: chromaLevels[i] + 0.02, h: hue))
    }

    palette[15] = lightMode
        ? ColorMath.hex(fromOKLCH: OKLCH(l: 0.10, c: 0.04, h: baseHue))
        : ColorMath.hex(fromOKLCH: OKLCH(l: 0.97, c: 0.015, h: baseHue))

    return palette
}

// MARK: Colour-theory schemes

// schemeBackground synthesizes near-extreme bg/fg with a subtle hue tint, so
// the structural hue relationships do the visual work.
func schemeBackground(_ baseHue: Double, _ lightMode: Bool) -> (String, String) {
    if lightMode {
        return (ColorMath.hex(fromOKLCH: OKLCH(l: 0.96, c: 0.012, h: baseHue)),
                ColorMath.hex(fromOKLCH: OKLCH(l: 0.22, c: 0.04, h: baseHue)))
    }
    return (ColorMath.hex(fromOKLCH: OKLCH(l: 0.13, c: 0.022, h: baseHue)),
            ColorMath.hex(fromOKLCH: OKLCH(l: 0.88, c: 0.025, h: baseHue)))
}

func buildSchemePalette(_ baseHue: Double, _ lightMode: Bool,
                        _ hues: [Double], _ chromas: [Double], _ lightnessOffsets: [Double]) -> [String] {
    let lightnessBase = lightMode ? 0.48 : 0.65

    var palette = Array(repeating: "", count: 16)
    (palette[0], palette[7]) = schemeBackground(baseHue, lightMode)

    for i in 0..<6 {
        let l = clampF(lightnessBase + lightnessOffsets[i], 0.30, 0.85)
        palette[i + 1] = ColorMath.hex(fromOKLCH: OKLCH(l: l, c: chromas[i],
                                                        h: (hues[i] + 360).truncatingRemainder(dividingBy: 360)))
    }

    finalizePalette(&palette)
    return palette
}

func generateComplementaryPalette(_ dominantColors: [String], _ lightMode: Bool) -> [String] {
    let baseHue = extractDominantHue(dominantColors)
    let compHue = (baseHue + 180).truncatingRemainder(dividingBy: 360)

    let hues: [Double] = [baseHue - 8, compHue - 8, baseHue, compHue, baseHue + 8, compHue + 8]
    let chromas: [Double] = [0.14, 0.14, 0.11, 0.11, 0.16, 0.16]
    let offsets: [Double] = [-0.06, -0.04, +0.04, +0.02, +0.08, +0.06]
    return buildSchemePalette(baseHue, lightMode, hues, chromas, offsets)
}

func generateTriadicPalette(_ dominantColors: [String], _ lightMode: Bool) -> [String] {
    let baseHue = extractDominantHue(dominantColors)
    let h2 = (baseHue + 120).truncatingRemainder(dividingBy: 360)
    let h3 = (baseHue + 240).truncatingRemainder(dividingBy: 360)

    let hues: [Double] = [baseHue, h2, h3, baseHue, h2, h3]
    let chromas: [Double] = [0.13, 0.13, 0.13, 0.16, 0.16, 0.16]
    let offsets: [Double] = [+0.05, +0.05, +0.05, -0.07, -0.07, -0.07]
    return buildSchemePalette(baseHue, lightMode, hues, chromas, offsets)
}

func generateSplitComplementaryPalette(_ dominantColors: [String], _ lightMode: Bool) -> [String] {
    let baseHue = extractDominantHue(dominantColors)
    let h2 = (baseHue + 150).truncatingRemainder(dividingBy: 360)
    let h3 = (baseHue + 210).truncatingRemainder(dividingBy: 360)

    let hues: [Double] = [baseHue, h2, h3, baseHue, h2, h3]
    let chromas: [Double] = [0.14, 0.13, 0.13, 0.17, 0.16, 0.16]
    let offsets: [Double] = [+0.05, +0.05, +0.05, -0.06, -0.06, -0.06]
    return buildSchemePalette(baseHue, lightMode, hues, chromas, offsets)
}

func generateTetradicPalette(_ dominantColors: [String], _ lightMode: Bool) -> [String] {
    let baseHue = extractDominantHue(dominantColors)
    let h2 = (baseHue + 90).truncatingRemainder(dividingBy: 360)
    let h3 = (baseHue + 180).truncatingRemainder(dividingBy: 360)
    let h4 = (baseHue + 270).truncatingRemainder(dividingBy: 360)

    let hues: [Double] = [baseHue, h2, h3, h4, baseHue, h3]
    let chromas: [Double] = [0.12, 0.12, 0.12, 0.12, 0.15, 0.15]
    let offsets: [Double] = [+0.04, -0.02, +0.04, -0.02, +0.10, +0.10]
    return buildSchemePalette(baseHue, lightMode, hues, chromas, offsets)
}

// MARK: Mood palettes

typealias MoodSpec = (
    bgDark: OKLCH, bgLight: OKLCH, fgDark: OKLCH, fgLight: OKLCH,
    ansiHueAnchor: Double, ansiTintStrength: Double,
    ansiChromaMin: Double, ansiChromaMax: Double,
    ansiLightnessDark: Double, ansiLightnessLight: Double,
    stagger: [Double]
)

// moodPalette pulls each ANSI hue toward the mood anchor by tintStrength
// (0 keeps the image hue, 1 replaces it), clamps chroma into the mood's band
// and sets lightness at the mood's target plus the per-slot stagger.
func moodPalette(_ dominantColors: [String], _ lightMode: Bool, _ spec: MoodSpec) -> [String] {
    let bgRule = OklchRule(light: { _ in spec.bgLight }, dark: { _ in spec.bgDark })
    let fgRule = OklchRule(light: { _ in spec.fgLight }, dark: { _ in spec.fgDark })
    let ansiRule = OklchRule(
        light: { lch in
            let h = pullHueToward(lch.h, spec.ansiHueAnchor, spec.ansiTintStrength)
            return OKLCH(l: spec.ansiLightnessLight, c: clampF(lch.c, spec.ansiChromaMin, spec.ansiChromaMax), h: h)
        },
        dark: { lch in
            let h = pullHueToward(lch.h, spec.ansiHueAnchor, spec.ansiTintStrength)
            return OKLCH(l: spec.ansiLightnessDark, c: clampF(lch.c, spec.ansiChromaMin, spec.ansiChromaMax), h: h)
        })
    return transformChromaticPalette(dominantColors, lightMode, bgRule, fgRule, ansiRule, spec.stagger)
}

func generateFirePalette(_ dominantColors: [String], _ lightMode: Bool) -> [String] {
    return moodPalette(dominantColors, lightMode, (
        bgDark: OKLCH(l: 0.09, c: 0.045, h: 28),
        bgLight: OKLCH(l: 0.95, c: 0.030, h: 45),
        fgDark: OKLCH(l: 0.90, c: 0.040, h: 55),
        fgLight: OKLCH(l: 0.22, c: 0.060, h: 20),
        ansiHueAnchor: 30, ansiTintStrength: 0.28,
        ansiChromaMin: 0.07, ansiChromaMax: 0.12,
        ansiLightnessDark: 0.62, ansiLightnessLight: 0.46,
        stagger: [-0.05, +0.01, +0.07, -0.04, -0.02, +0.03]))
}

func generateOceanPalette(_ dominantColors: [String], _ lightMode: Bool) -> [String] {
    return moodPalette(dominantColors, lightMode, (
        bgDark: OKLCH(l: 0.10, c: 0.050, h: 240),
        bgLight: OKLCH(l: 0.96, c: 0.030, h: 215),
        fgDark: OKLCH(l: 0.90, c: 0.035, h: 205),
        fgLight: OKLCH(l: 0.20, c: 0.055, h: 230),
        ansiHueAnchor: 220, ansiTintStrength: 0.28,
        ansiChromaMin: 0.09, ansiChromaMax: 0.14,
        ansiLightnessDark: 0.60, ansiLightnessLight: 0.44,
        stagger: [-0.05, +0.02, +0.06, -0.03, -0.01, +0.03]))
}

func generateForestPalette(_ dominantColors: [String], _ lightMode: Bool) -> [String] {
    return moodPalette(dominantColors, lightMode, (
        bgDark: OKLCH(l: 0.13, c: 0.040, h: 145),
        bgLight: OKLCH(l: 0.95, c: 0.025, h: 130),
        fgDark: OKLCH(l: 0.88, c: 0.035, h: 125),
        fgLight: OKLCH(l: 0.24, c: 0.050, h: 140),
        ansiHueAnchor: 145, ansiTintStrength: 0.25,
        ansiChromaMin: 0.06, ansiChromaMax: 0.10,
        ansiLightnessDark: 0.66, ansiLightnessLight: 0.48,
        stagger: [-0.05, +0.02, +0.07, -0.03, -0.01, +0.04]))
}

func generateEarthtonePalette(_ dominantColors: [String], _ lightMode: Bool) -> [String] {
    return moodPalette(dominantColors, lightMode, (
        bgDark: OKLCH(l: 0.18, c: 0.040, h: 40),
        bgLight: OKLCH(l: 0.93, c: 0.025, h: 60),
        fgDark: OKLCH(l: 0.84, c: 0.050, h: 50),
        fgLight: OKLCH(l: 0.26, c: 0.055, h: 35),
        ansiHueAnchor: 45, ansiTintStrength: 0.40,
        ansiChromaMin: 0.05, ansiChromaMax: 0.09,
        ansiLightnessDark: 0.58, ansiLightnessLight: 0.44,
        stagger: [-0.10, -0.04, +0.04, +0.10, -0.07, +0.07]))
}

func generateNeonPalette(_ dominantColors: [String], _ lightMode: Bool) -> [String] {
    return moodPalette(dominantColors, lightMode, (
        bgDark: OKLCH(l: 0.05, c: 0.030, h: 280),
        bgLight: OKLCH(l: 0.97, c: 0.015, h: 280),
        fgDark: OKLCH(l: 0.92, c: 0.045, h: 175),
        fgLight: OKLCH(l: 0.18, c: 0.060, h: 290),
        ansiHueAnchor: 0, ansiTintStrength: 0,
        ansiChromaMin: 0.20, ansiChromaMax: 0.26,
        ansiLightnessDark: 0.72, ansiLightnessLight: 0.50,
        stagger: [-0.03, +0.01, +0.04, -0.02, -0.01, +0.02]))
}

func generateSunsetPalette(_ dominantColors: [String], _ lightMode: Bool) -> [String] {
    return moodPalette(dominantColors, lightMode, (
        bgDark: OKLCH(l: 0.12, c: 0.060, h: 350),
        bgLight: OKLCH(l: 0.96, c: 0.030, h: 30),
        fgDark: OKLCH(l: 0.90, c: 0.050, h: 30),
        fgLight: OKLCH(l: 0.24, c: 0.060, h: 350),
        ansiHueAnchor: 20, ansiTintStrength: 0.32,
        ansiChromaMin: 0.12, ansiChromaMax: 0.18,
        ansiLightnessDark: 0.70, ansiLightnessLight: 0.50,
        stagger: [-0.05, +0.02, +0.07, -0.04, -0.02, +0.04]))
}

func generateVaporwavePalette(_ dominantColors: [String], _ lightMode: Bool) -> [String] {
    return moodPalette(dominantColors, lightMode, (
        bgDark: OKLCH(l: 0.15, c: 0.060, h: 315),
        bgLight: OKLCH(l: 0.96, c: 0.025, h: 320),
        fgDark: OKLCH(l: 0.90, c: 0.060, h: 190),
        fgLight: OKLCH(l: 0.26, c: 0.060, h: 310),
        ansiHueAnchor: 320, ansiTintStrength: 0.28,
        ansiChromaMin: 0.10, ansiChromaMax: 0.16,
        ansiLightnessDark: 0.74, ansiLightnessLight: 0.52,
        stagger: [-0.04, +0.02, +0.06, -0.03, -0.01, +0.04]))
}

func generateMidnightPalette(_ dominantColors: [String], _ lightMode: Bool) -> [String] {
    return moodPalette(dominantColors, lightMode, (
        bgDark: OKLCH(l: 0.07, c: 0.035, h: 250),
        bgLight: OKLCH(l: 0.95, c: 0.020, h: 240),
        fgDark: OKLCH(l: 0.88, c: 0.020, h: 220),
        fgLight: OKLCH(l: 0.22, c: 0.045, h: 250),
        ansiHueAnchor: 250, ansiTintStrength: 0.20,
        ansiChromaMin: 0.07, ansiChromaMax: 0.12,
        ansiLightnessDark: 0.62, ansiLightnessLight: 0.42,
        stagger: [-0.04, +0.01, +0.05, -0.03, -0.02, +0.03]))
}

func generateAuroraPalette(_ dominantColors: [String], _ lightMode: Bool) -> [String] {
    return moodPalette(dominantColors, lightMode, (
        bgDark: OKLCH(l: 0.08, c: 0.045, h: 240),
        bgLight: OKLCH(l: 0.96, c: 0.025, h: 220),
        fgDark: OKLCH(l: 0.92, c: 0.040, h: 175),
        fgLight: OKLCH(l: 0.20, c: 0.055, h: 240),
        ansiHueAnchor: 160, ansiTintStrength: 0.42,
        ansiChromaMin: 0.12, ansiChromaMax: 0.18,
        ansiLightnessDark: 0.70, ansiLightnessLight: 0.50,
        stagger: [-0.05, +0.02, +0.06, -0.03, -0.01, +0.04]))
}

// MARK: Practical palettes

// High Contrast: image-aware hues on a hard-extreme background, every ANSI
// slot at WCAG AAA (7:1).
func generateHighContrastPalette(_ dominantColors: [String], _ lightMode: Bool) -> [String] {
    let bgRule = OklchRule(
        light: { OKLCH(l: 0.99, c: 0.005, h: $0.h) },
        dark: { OKLCH(l: 0.05, c: 0.010, h: $0.h) })
    let fgRule = OklchRule(
        light: { OKLCH(l: 0.10, c: 0.020, h: $0.h) },
        dark: { OKLCH(l: 0.95, c: 0.015, h: $0.h) })
    let ansiRule = OklchRule(
        light: { OKLCH(l: 0.32, c: clampF($0.c, 0.10, 0.18), h: $0.h) },
        dark: { OKLCH(l: 0.82, c: clampF($0.c, 0.10, 0.18), h: $0.h) })
    let stagger: [Double] = [-0.03, +0.01, +0.04, -0.02, -0.01, +0.02]

    var palette = transformChromaticPalette(dominantColors, lightMode, bgRule, fgRule, ansiRule, stagger)
    for i in 1...6 {
        if ColorMath.contrastRatio(palette[0], palette[i]) >= Extract.minHighContrastRatio { continue }
        palette[i] = boostContrastAgainstBg(palette[i], palette[0], Extract.minHighContrastRatio)
        palette[i + 8] = generateBrightVersion(palette[i])
    }
    return palette
}

// Duotone: two hues only, alternating at three lightness levels; structure
// comes entirely from lightness.
func generateDuotonePalette(_ dominantColors: [String], _ lightMode: Bool) -> [String] {
    let baseHue = extractDominantHue(dominantColors)
    let compHue = (baseHue + 180).truncatingRemainder(dividingBy: 360)

    var palette = Array(repeating: "", count: 16)
    if lightMode {
        palette[0] = ColorMath.hex(fromOKLCH: OKLCH(l: 0.97, c: 0.008, h: baseHue))
        palette[7] = ColorMath.hex(fromOKLCH: OKLCH(l: 0.20, c: 0.025, h: baseHue))
    } else {
        palette[0] = ColorMath.hex(fromOKLCH: OKLCH(l: 0.12, c: 0.018, h: baseHue))
        palette[7] = ColorMath.hex(fromOKLCH: OKLCH(l: 0.90, c: 0.020, h: baseHue))
    }

    let lightnessLevels: [Double] = [-0.10, -0.10, +0.04, +0.04, +0.14, +0.14]
    let hues: [Double] = [baseHue, compHue, baseHue, compHue, baseHue, compHue]
    let chroma = 0.09
    let lightnessBase = lightMode ? 0.50 : 0.62

    for i in 0..<6 {
        let l = clampF(lightnessBase + lightnessLevels[i], 0.30, 0.85)
        palette[i + 1] = ColorMath.hex(fromOKLCH: OKLCH(l: l, c: chroma, h: hues[i]))
    }

    finalizePalette(&palette)
    return palette
}

// MARK: Finalize and dispatch

// Slots 0, 7 and 1-6 must be set; 8, 9-14 and 15 are derived here, and AA
// contrast is enforced for the ANSI colours.
func finalizePalette(_ p: inout [String]) {
    p[8] = generateCommentColor(p[0])
    for i in 1...6 {
        p[i + 8] = generateBrightVersion(p[i])
    }
    p[15] = generateBrightVersion(p[7])

    for i in 1...6 {
        if ColorMath.contrastRatio(p[0], p[i]) < Extract.minContrastRatio {
            p[i] = boostContrastAgainstBg(p[i], p[0], Extract.minContrastRatio)
            p[i + 8] = generateBrightVersion(p[i])
        }
    }
}

func normalizeBrightness(_ palette: [String]) -> [String] {
    var palette = palette
    for i in 1...6 {
        if ColorMath.contrastRatio(palette[0], palette[i]) < Extract.minContrastRatio {
            palette[i] = boostContrastAgainstBg(palette[i], palette[0], Extract.minContrastRatio)
            palette[i + 8] = generateBrightVersion(palette[i])
        }
    }
    return palette
}

func normalizeCounts(_ counts: [Int]) -> [Double]? {
    let total = counts.reduce(0, +)
    if total == 0 { return nil }
    return counts.map { Double($0) / Double(total) }
}

// generatorName maps a generator the fixtures and the editor reach directly:
// `chromatic` and `monochrome` are Aether's two auto-routed generators, not
// entries of the 23-mode list.
func generatePaletteByMode(_ dominantColors: [String], _ weights: [Double]?, _ lightMode: Bool, _ mode: String) -> [String] {
    switch mode {
    case "magic":
        fail("magic is generated from an image; use palette magic or palette extract --mode magic")
    case "monochromatic":
        return generateMonochromaticPalette(dominantColors, lightMode)
    case "analogous":
        return generateAnalogousPalette(dominantColors, lightMode)
    case "complementary":
        return generateComplementaryPalette(dominantColors, lightMode)
    case "triadic":
        return generateTriadicPalette(dominantColors, lightMode)
    case "split-complementary":
        return generateSplitComplementaryPalette(dominantColors, lightMode)
    case "tetradic":
        return generateTetradicPalette(dominantColors, lightMode)
    case "pastel":
        return generatePastelPalette(dominantColors, lightMode)
    case "colorful":
        return generateColorfulPalette(dominantColors, lightMode)
    case "muted":
        return generateMutedPalette(dominantColors, lightMode)
    case "bright":
        return generateBrightPalette(dominantColors, lightMode)
    case "material":
        return generateMaterialPalette(dominantColors, lightMode)
    case "fire":
        return generateFirePalette(dominantColors, lightMode)
    case "ocean":
        return generateOceanPalette(dominantColors, lightMode)
    case "forest":
        return generateForestPalette(dominantColors, lightMode)
    case "earthtone":
        return generateEarthtonePalette(dominantColors, lightMode)
    case "neon":
        return generateNeonPalette(dominantColors, lightMode)
    case "sunset":
        return generateSunsetPalette(dominantColors, lightMode)
    case "vaporwave":
        return generateVaporwavePalette(dominantColors, lightMode)
    case "midnight":
        return generateMidnightPalette(dominantColors, lightMode)
    case "aurora":
        return generateAuroraPalette(dominantColors, lightMode)
    case "high-contrast":
        return generateHighContrastPalette(dominantColors, lightMode)
    case "duotone":
        return generateDuotonePalette(dominantColors, lightMode)
    case "chromatic":
        return generateChromaticPalette(dominantColors, weights, lightMode)
    case "monochrome":
        return generateMonochromePalette(dominantColors, lightMode)
    case "normal":
        if isMonochromeWeighted(dominantColors, weights) {
            return generateMonochromePalette(dominantColors, lightMode)
        }
        return generateChromaticPalette(dominantColors, weights, lightMode)
    default:
        fail("unknown extraction mode \"\(mode)\"")
    }
}

func extractionModeExists(_ mode: String) -> Bool {
    mode == "magic" || mode == "chromatic" || mode == "monochrome" || Modes.all.contains { $0.value == mode }
}

// Extraction results are cached under ~/.local/state/omacosy/studio/palettes,
// keyed by resolved path + mtime (milliseconds) + ladder + mode, so a repeat
// ask answers in tens of milliseconds. Version 1; bump when a generator's
// output changes meaningfully.
enum ExtractCache {
    static let version = 1

    static var dir: String { "\(Wallpapers.stateDir)/studio/palettes" }

    static func key(path: String, light: Bool, mode: String) -> String? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let mtime = attrs[.modificationDate] as? Date else { return nil }
        let millis = Int64((mtime.timeIntervalSince1970 * 1000).rounded())
        let seed = "\(path)-\(millis)-\(light ? "light" : "dark")"
        let digest = Insecure.MD5.hash(data: Data(seed.utf8))
            .map { String(format: "%02x", $0) }.joined()
        return "\(digest)_\(mode)_v\(version)"
    }

    static func load(_ key: String) -> [String]? {
        guard let data = FileManager.default.contents(atPath: "\(dir)/\(key).json"),
              let top = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              JSONField.int(top["version"]) == version,
              let colors = top["palette"] as? [String], colors.count == 16,
              colors.allSatisfy({ $0.hasPrefix("#") && $0.count == 7 })
        else { return nil }
        return colors
    }

    static func save(_ key: String, _ palette: [String]) {
        do {
            try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            let object: [String: Any] = ["version": version, "saved": isoNow(), "palette": palette]
            let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
            try data.write(to: URL(fileURLWithPath: "\(dir)/\(key).json"), options: .atomic)
        } catch {
            warn("could not write the palette cache: \(error.localizedDescription)")
        }
    }
}

func extractColors(url: URL, light: Bool, mode: String, useCache: Bool = true,
                   canonicalOrder: Bool = false) throws -> [String] {
    if mode == "magic" { return try magicPalette(url: url, useCache: useCache) }

    var cacheKey: String? = nil
    if useCache && !canonicalOrder,
       let key = ExtractCache.key(path: url.path, light: light, mode: mode) {
        if let cached = ExtractCache.load(key) { return cached }
        cacheKey = key
    }

    var dominant = try extractDominantColors(url: url, count: Extract.dominantColorsToExtract)
    if dominant.colors.count < 8 {
        throw ThemeError(message: "not enough colors extracted from image")
    }
    // Median-cut ties have no inherent order (Aether's final sort is
    // unstable); --canonical fixes them to count-desc, hex-asc so recorded
    // corpus palettes compare byte for byte. Test support only.
    if canonicalOrder {
        let pairs = zip(dominant.colors, dominant.counts).sorted {
            $0.1 != $1.1 ? $0.1 > $1.1 : $0.0 < $1.0
        }
        dominant = (pairs.map { $0.0 }, pairs.map { $0.1 })
    }
    let weights = normalizeCounts(dominant.counts)
    let palette = normalizeBrightness(generatePaletteByMode(dominant.colors, weights, light, mode))

    if let cacheKey { ExtractCache.save(cacheKey, palette) }
    return palette
}

// MARK: - Magic: the Omacosy bridge (Phase 2b)

// Ported verbatim from helper/derive.swift — the engine that paints the bar,
// the auto-theme and the focus ring. Magic must reproduce, byte for byte,
// the colours omacosy-derive writes for the same image, so this is a
// deliberate copy: a one-file helper cannot be imported, and the harness
// diffs the copy against the original across the 30-image corpus. The
// comments and the reasoning live in derive.swift; only the code is here.
enum DerivePort {
    // derive.swift's RGB: 0...1 components, quantised to 8 bits by q8().
    struct RGB {
        var r: Double, g: Double, b: Double

        init(r: Double, g: Double, b: Double) { self.r = r; self.g = g; self.b = b }

        init(hex: String) {
            let v = ColorMath.hexUInt32(hex) ?? 0
            self.init(r: Double((v >> 16) & 0xff) / 255,
                      g: Double((v >> 8) & 0xff) / 255,
                      b: Double(v & 0xff) / 255)
        }

        var lum: Double { 0.299 * r + 0.587 * g + 0.114 * b }

        var hex: String {
            func q(_ v: Double) -> Int { Int((min(1, max(0, v)) * 255).rounded()) }
            return String(format: "%02x%02x%02x", q(r), q(g), q(b))
        }
    }

    // Fixed so the output is reproducible on any display, exactly as
    // derive.swift fixes it.
    static let frameW: Double = 1440
    static let frameH: Double = 900
    static let barHeight: Double = 34
    static let menuBarSaturation = 1.3
    static let menuBarDarken = 0.923

    static let white = RGB(r: 1, g: 1, b: 1)
    static let black = RGB(r: 0, g: 0, b: 0)

    static func clamp01(_ v: Double) -> Double { min(1, max(0, v)) }

    static func toHSV(_ c: RGB) -> (h: Double, s: Double, v: Double) {
        let mx = max(c.r, c.g, c.b), mn = min(c.r, c.g, c.b)
        let d = mx - mn
        var h = 0.0
        if d > 0 {
            if mx == c.r { h = (c.g - c.b) / d }
            else if mx == c.g { h = 2 + (c.b - c.r) / d }
            else { h = 4 + (c.r - c.g) / d }
            h *= 60
            if h < 0 { h += 360 }
        }
        return (h, mx == 0 ? 0 : d / mx, mx)
    }

    static func fromHSV(_ h: Double, _ s: Double, _ v: Double) -> RGB {
        let hh = h.truncatingRemainder(dividingBy: 360) < 0
            ? h.truncatingRemainder(dividingBy: 360) + 360
            : h.truncatingRemainder(dividingBy: 360)
        let S = clamp01(s), V = clamp01(v)
        if S == 0 { return RGB(r: V, g: V, b: V) }
        let i = Int(hh / 60) % 6
        let f = hh / 60 - Double(Int(hh / 60))
        let p = V * (1 - S), q = V * (1 - S * f), t = V * (1 - S * (1 - f))
        switch i {
        case 0: return RGB(r: V, g: t, b: p)
        case 1: return RGB(r: q, g: V, b: p)
        case 2: return RGB(r: p, g: V, b: t)
        case 3: return RGB(r: p, g: q, b: V)
        case 4: return RGB(r: t, g: p, b: V)
        default: return RGB(r: V, g: p, b: q)
        }
    }

    static func blend(_ c: RGB, toward t: RGB, _ k: Double) -> RGB {
        RGB(r: c.r * (1 - k) + t.r * k,
            g: c.g * (1 - k) + t.g * k,
            b: c.b * (1 - k) + t.b * k)
    }

    // Snap to the 8 bits per channel that actually get written; the contrast
    // loops compare quantised values.
    static func q8(_ c: RGB) -> RGB {
        func q(_ v: Double) -> Double { (clamp01(v) * 255).rounded() / 255 }
        return RGB(r: q(c.r), g: q(c.g), b: q(c.b))
    }

    // MARK: image analysis

    // The mean of the band the bar covers, in the centred fill-crop for
    // 1440x900. baseColour is this mean through the fitted menu-bar transform.
    static func fillCropMean(of url: URL) -> RGB? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cg = CGImageSourceCreateImageAtIndex(src, 0, nil)
        else { return nil }
        let bitmap = NSBitmapImageRep(cgImage: cg)
        guard bitmap.pixelsWide > 0, bitmap.pixelsHigh > 0 else { return nil }

        let sx = frameW / Double(bitmap.pixelsWide)
        let sy = frameH / Double(bitmap.pixelsHigh)
        let scale = max(sx, sy)
        let band = max(1, Int(barHeight / scale))
        let visibleW = Int(frameW / scale)
        let x0 = max(0, (bitmap.pixelsWide - visibleW) / 2)

        var r = 0.0, g = 0.0, b = 0.0, n = 0.0
        for x in stride(from: x0, to: min(x0 + visibleW, bitmap.pixelsWide),
                        by: max(1, visibleW / 64)) {
            for y in stride(from: 0, to: band, by: max(1, band / 4)) {
                // usingColorSpace(.sRGB) is NOT optional: an embedded profile
                // read raw lands up to 22/255 away.
                guard let c = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB)
                else { continue }
                r += Double(c.redComponent)
                g += Double(c.greenComponent)
                b += Double(c.blueComponent)
                n += 1
            }
        }
        guard n > 0 else { return nil }
        return RGB(r: r / n, g: g / n, b: b / n)
    }

    static func baseColour(of url: URL) -> RGB? {
        guard let mean = fillCropMean(of: url) else { return nil }
        let luma = 0.299 * mean.r + 0.587 * mean.g + 0.114 * mean.b
        func menuBarLike(_ v: Double) -> Double {
            clamp01((luma + menuBarSaturation * (v - luma)) * menuBarDarken)
        }
        return RGB(r: menuBarLike(mean.r), g: menuBarLike(mean.g), b: menuBarLike(mean.b))
    }

    static func bitmap(of url: URL) -> NSBitmapImageRep? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
        let bm = NSBitmapImageRep(cgImage: cg)
        guard bm.pixelsWide > 0, bm.pixelsHigh > 0 else { return nil }
        return bm
    }

    // The wallpaper behind the bar in 8 slices across the screen, raw pixels.
    static func stripSlices(of url: URL) -> [RGB] {
        guard let bm = bitmap(of: url) else { return [] }
        let scale = max(frameW / Double(bm.pixelsWide), frameH / Double(bm.pixelsHigh))
        let band = max(1, Int(barHeight / scale)), visW = Int(frameW / scale)
        let x0 = max(0, (bm.pixelsWide - visW) / 2)
        var out: [RGB] = []
        for i in 0..<8 {
            let xs = x0 + i * visW / 8, xe = min(bm.pixelsWide, x0 + (i + 1) * visW / 8)
            var r = 0.0, g = 0.0, b = 0.0, n = 0.0
            for x in stride(from: xs, to: xe, by: max(1, (xe - xs) / 32)) {
                for y in stride(from: 0, to: band, by: max(1, band / 6)) {
                    guard let c = bm.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                    r += Double(c.redComponent); g += Double(c.greenComponent); b += Double(c.blueComponent); n += 1
                }
            }
            if n > 0 { out.append(RGB(r: r / n, g: g / n, b: b / n)) }
        }
        return out
    }

    // The 90th percentile of OKLCH chroma over the picture: how colourful it
    // is, where HSV saturation misleads.
    static func pictureChroma(of url: URL) -> Double? {
        guard let bm = bitmap(of: url) else { return nil }
        var cs: [Double] = []
        for x in stride(from: 0, to: bm.pixelsWide, by: max(1, bm.pixelsWide / 150)) {
            for y in stride(from: 0, to: bm.pixelsHigh, by: max(1, bm.pixelsHigh / 150)) {
                guard let c = bm.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                cs.append(toOKLCH(RGB(r: Double(c.redComponent), g: Double(c.greenComponent),
                                      b: Double(c.blueComponent))).C)
            }
        }
        guard !cs.isEmpty else { return nil }
        cs.sort()
        return cs[Int(Double(cs.count - 1) * 0.9)]
    }

    // The picture's warm light: OKLCH hue 40-120 with chroma >= 0.03,
    // circular mean weighted by chroma.
    static func warmToneColour(of url: URL) -> (hue: Double, share: Double)? {
        guard let bm = bitmap(of: url) else { return nil }
        var hx = 0.0, hy = 0.0, n = 0.0, all = 0.0
        for x in stride(from: 0, to: bm.pixelsWide, by: max(1, bm.pixelsWide / 200)) {
            for y in stride(from: 0, to: bm.pixelsHigh, by: max(1, bm.pixelsHigh / 200)) {
                guard let c = bm.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                let o = toOKLCH(RGB(r: Double(c.redComponent), g: Double(c.greenComponent),
                                    b: Double(c.blueComponent)))
                all += 1
                guard o.h >= 40, o.h <= 120, o.C >= 0.03 else { continue }
                let a = o.h * .pi / 180
                hx += cos(a) * o.C; hy += sin(a) * o.C; n += 1
            }
        }
        guard all > 0, n / all >= 0.001 else { return nil }
        var h = atan2(hy, hx) * 180 / .pi
        if h < 0 { h += 360 }
        return (h, n / all)
    }

    // The hue the picture READS as, weighted by saturation x value cubed and
    // smoothed over 36 buckets; nil for a greyscale photograph.
    static func pictureColour(of url: URL) -> (hue: Double, sat: Double, share: Double)? {
        guard let bm = bitmap(of: url) else { return nil }
        let sx = max(1, bm.pixelsWide / 200), sy = max(1, bm.pixelsHigh / 200)

        var samples: [(h: Double, s: Double, v: Double)] = []
        samples.reserveCapacity(40000)
        for x in stride(from: 0, to: bm.pixelsWide, by: sx) {
            for y in stride(from: 0, to: bm.pixelsHigh, by: sy) {
                guard let c = bm.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                let t = toHSV(RGB(r: Double(c.redComponent), g: Double(c.greenComponent),
                                  b: Double(c.blueComponent)))
                if t.v >= 0.10 { samples.append((t.h, t.s, t.v)) }
            }
        }
        guard samples.count > 20 else { return nil }

        let scores = samples.map { $0.s * $0.v }.sorted()
        let cut = max(0.12, scores[Int(0.90 * Double(scores.count - 1))])
        guard samples.filter({ $0.s * $0.v >= cut && $0.s >= 0.18 }).count > 5 else { return nil }

        var bucket = [Double](repeating: 0, count: 36)
        var bs = [Double](repeating: 0, count: 36)
        for t in samples where t.s >= 0.10 {
            let w = t.s * t.v * t.v * t.v
            let i = min(35, Int(t.h / 10))
            bucket[i] += w
            bs[i] += t.s * w
        }

        var smooth = [Double](repeating: 0, count: 36)
        for i in 0..<36 { for d in -2...2 { smooth[i] += bucket[(i + d + 36) % 36] } }
        guard let best = smooth.indices.max(by: { smooth[$0] < smooth[$1] }), smooth[best] > 0
        else { return nil }

        var wsum = 0.0, hx = 0.0, hy = 0.0, ss = 0.0
        for d in -2...2 {
            let i = (best + d + 36) % 36
            let w = bucket[i]; guard w > 0 else { continue }
            let ang = (Double(i) * 10 + 5) * .pi / 180
            hx += cos(ang) * w; hy += sin(ang) * w; ss += bs[i]; wsum += w
        }
        guard wsum > 0 else { return nil }
        var h = atan2(hy, hx) * 180 / .pi
        if h < 0 { h += 360 }
        let totalWeight = bucket.reduce(0, +)
        return (h, min(1.0, ss / wsum), totalWeight > 0 ? smooth[best] / totalWeight : 0)
    }

    // The hue the picture has in its shadows, for a pill below the bar.
    static func darkToneColour(of url: URL) -> (hue: Double, sat: Double)? {
        guard let bm = bitmap(of: url) else { return nil }
        let sx = max(1, bm.pixelsWide / 200), sy = max(1, bm.pixelsHigh / 200)
        var hx = 0.0, hy = 0.0, w = 0.0, ss = 0.0, n = 0.0, all = 0.0
        for x in stride(from: 0, to: bm.pixelsWide, by: sx) {
            for y in stride(from: 0, to: bm.pixelsHigh, by: sy) {
                guard let c = bm.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                let t = toHSV(RGB(r: Double(c.redComponent), g: Double(c.greenComponent),
                                  b: Double(c.blueComponent)))
                all += 1
                guard t.v >= 0.12, t.v <= 0.50, t.s >= 0.20 else { continue }
                let a = t.h * .pi / 180
                let k = t.s * (0.55 - t.v)
                hx += cos(a) * k; hy += sin(a) * k; w += k; ss += t.s; n += 1
            }
        }
        guard n >= 0.05 * all, w > 0 else { return nil }
        var h = atan2(hy, hx) * 180 / .pi
        if h < 0 { h += 360 }
        return (h, ss / n)
    }

    // MARK: OKLCH and contrast

    static func lin(_ v: Double) -> Double { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
    static func gam(_ v: Double) -> Double { v <= 0.0031308 ? v * 12.92 : 1.055 * pow(v, 1 / 2.4) - 0.055 }

    static func toOKLCH(_ c: RGB) -> (L: Double, C: Double, h: Double) {
        let r = lin(c.r), g = lin(c.g), b = lin(c.b)
        let l = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
        let m = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
        let s = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
        let L = 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s
        let A = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s
        let B = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
        var h = atan2(B, A) * 180 / .pi; if h < 0 { h += 360 }
        return (L, (A * A + B * B).squareRoot(), h)
    }

    // nil when the colour is outside sRGB
    static func fromOKLCH(_ L: Double, _ C: Double, _ h: Double) -> RGB? {
        let A = C * cos(h * .pi / 180), B = C * sin(h * .pi / 180)
        let l = pow(L + 0.3963377774 * A + 0.2158037573 * B, 3)
        let m = pow(L - 0.1055613458 * A - 0.0638541728 * B, 3)
        let s = pow(L - 0.0894841775 * A - 1.2914855480 * B, 3)
        let r = 4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s
        let g = -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s
        let b = -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s
        let e = 0.0001
        guard r >= -e, r <= 1 + e, g >= -e, g <= 1 + e, b >= -e, b <= 1 + e else { return nil }
        return RGB(r: gam(clamp01(r)), g: gam(clamp01(g)), b: gam(clamp01(b)))
    }

    // A colour at this lightness and hue; chroma drops until it fits sRGB.
    static func oklchFit(_ L: Double, _ C: Double, _ h: Double) -> RGB? {
        var cc = C
        while cc >= 0 { if let x = fromOKLCH(L, cc, h) { return x }; cc -= 0.005 }
        return nil
    }

    static func relLum(_ c: RGB) -> Double {
        let q = q8(c)
        return 0.2126 * lin(q.r) + 0.7152 * lin(q.g) + 0.0722 * lin(q.b)
    }

    static func contrast(_ a: RGB, _ b: RGB) -> Double {
        let x = relLum(a), y = relLum(b)
        return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }

    static func legible(_ c: RGB, against refs: [RGB], ratio: Double) -> RGB {
        func worst(_ x: RGB) -> Double { refs.map { contrast(x, $0) }.min() ?? 99 }
        if worst(c) >= ratio { return c }
        let o = toOKLCH(c)
        var best = c, bestScore = worst(c)
        for dir in [1.0, -1.0] {
            var L = o.L
            while L > 0.0 && L < 1.0 {
                L += 0.005 * dir
                guard let x = oklchFit(L, o.C, o.h) else { continue }
                let w = worst(x)
                if w >= ratio {
                    if bestScore < ratio || abs(L - o.L) < abs(toOKLCH(best).L - o.L) { best = x; bestScore = w }
                    break
                }
                if bestScore < ratio && w > bestScore { best = x; bestScore = w }
            }
        }
        return best
    }

    static func brighten(_ c: RGB, from ref: RGB, need: Double) -> RGB {
        let lr = q8(ref).lum
        if lr + need > 0.85 { return separate(c, from: ref, need: need) }
        if q8(c).lum >= lr + need { return c }
        for step in 1...50 {
            let cand = blend(c, toward: white, 0.02 * Double(step))
            if q8(cand).lum >= lr + need { return cand }
        }
        return separate(c, from: ref, need: need)
    }

    // MARK: the floors

    static func separate(_ c: RGB, from ref: RGB, need: Double) -> RGB {
        let lr = q8(ref).lum
        if abs(q8(c).lum - lr) >= need { return c }
        let target = (1 - lr) >= lr ? white : black
        for step in 1...50 {
            let cand = blend(c, toward: target, 0.02 * Double(step))
            if abs(q8(cand).lum - lr) >= need { return cand }
        }
        return target
    }

    static func towardLum(_ c: RGB, _ wanted: Double) -> RGB {
        let target = wanted > q8(c).lum ? white : black
        var best = c
        for step in 0...50 {
            let cand = blend(c, toward: target, 0.02 * Double(step))
            if abs(q8(cand).lum - wanted) < abs(q8(best).lum - wanted) { best = cand }
        }
        return best
    }

    static func clearOf(_ c: RGB, bar: RGB, pill: RGB, preferUp: Bool) -> RGB {
        let lb = q8(bar).lum, lp = q8(pill).lum
        let lo = min(lb - 0.28, lp - 0.20)
        let hi = max(lb + 0.28, lp + 0.20)
        let lc = q8(c).lum
        if lc <= lo || lc >= hi { return c }
        let downOK = lo >= 0.0, upOK = hi <= 1.0
        let goUp: Bool
        if upOK && downOK { goUp = preferUp }
        else if upOK { goUp = true }
        else if downOK { goUp = false }
        else { goUp = (1.0 - lc) >= lc }
        let target = goUp ? white : black
        let wanted = goUp ? hi : lo
        for step in 1...50 {
            let cand = blend(c, toward: target, 0.02 * Double(step))
            let l = q8(cand).lum
            if goUp ? (l >= wanted) : (l <= wanted) { return cand }
        }
        return target
    }

    // MARK: the role engine

    struct Palette {
        var bar: RGB, pill: RGB, muted: RGB, label: RGB, accent: RGB, ring: RGB
        var surface: RGB
        var isLight: Bool, isLowChroma: Bool
        var hue: Double, sat: Double, val: Double
    }

    static func derive(_ base: RGB, picture: (hue: Double, sat: Double, share: Double)?,
                       darkTone: (hue: Double, sat: Double)?, strip: [RGB], chroma: Double?,
                       warm: (hue: Double, share: Double)?) -> Palette {
        let (baseH, baseS, V) = toHSV(base)
        let H = picture?.hue ?? 0
        let S = picture?.sat ?? 0
        let low = picture == nil

        var pillH = baseH, pillS = baseS
        if let p = picture, p.share >= 0.65 {
            let gap = min(abs(p.hue - baseH), 360 - abs(p.hue - baseH))
            if gap <= 90 { pillH = p.hue; pillS = max(baseS, p.sat * 0.7) }
        }

        var accentH = baseH, accentS = baseS
        if let p = picture, p.share >= 0.50 { accentH = p.hue; accentS = max(baseS, p.sat) }
        let light = base.lum > 0.45

        let greenish = accentH >= 70 && accentH <= 150
        let tame = greenish ? min(1.0, max(0.35, accentS * 1.5)) : 1.0

        var pill: RGB, muted: RGB, label: RGB, accent: RGB
        var shiftedRing: RGB? = nil
        if light {
            pill   = fromHSV(pillH, pillS * 0.75, V * 0.80)
            muted  = fromHSV(pillH, min(pillS, 0.30), V * 0.42)
            label  = fromHSV(pillH, min(pillS, 0.38), V * 0.16)
            accent = low ? fromHSV(0, 0, 0.06)
                         : fromHSV(accentH, min(tame, min(0.92, max(0.35, accentS * 2.4))), 0.92)
        } else {
            pill   = fromHSV(pillH, pillS * 0.85, max(V + 0.11, 0.20))
            muted  = fromHSV(pillH, min(pillS, 0.22), 0.48)
            label  = fromHSV(pillH, min(pillS, 0.18), 0.92)
            accent = low ? fromHSV(0, 0, 0.99)
                         : fromHSV(accentH, min(tame, min(0.95, max(0.35, accentS * 2.4))), 0.92)
        }

        pill   = separate(pill,   from: base, need: 0.085)
        label  = separate(label,  from: pill, need: 0.50)
        let brokenLabel = q8(label).lum < q8(pill).lum
        if !light {
            let want = (!brokenLabel && q8(base).lum - 0.085 < 0.10)
                ? q8(pill).lum
                : min(q8(base).lum - 0.085, 0.20)
            let dh = darkTone?.hue ?? baseH
            let ds = darkTone.map { min($0.sat, 0.55) } ?? baseS * 0.45
            pill  = towardLum(fromHSV(dh, ds, V), want)
            label = separate(fromHSV(dh, min(ds, 0.18), 0.92), from: pill, need: 0.50)
            muted = fromHSV(dh, min(ds, 0.22), 0.48)
            if darkTone != nil {
                let dark = fromHSV(dh, max(ds, 0.5), 0.35)
                let hb = toOKLCH(base).h, hd = toOKLCH(dark).h
                var gap = hd - hb
                if gap > 180 { gap -= 360 }; if gap < -180 { gap += 360 }
                if abs(gap) <= 45 {
                    let step = max(-30, min(30, gap))
                    let h = (hd + step + 360).truncatingRemainder(dividingBy: 360)
                    accent = oklchFit(0.78, 0.14, h) ?? dark
                    shiftedRing = oklchFit(0.72, 0.18, h) ?? dark
                }
            }
        }
        if light {
            if contrast(pill, base) < 1.7 {
                let o = toOKLCH(pill)
                var L = o.L
                while L > 0.0 {
                    L -= 0.005
                    if let x = oklchFit(L, o.C, o.h), contrast(x, base) >= 1.7 { pill = x; break }
                }
            }
        } else {
            let behind = strip.isEmpty ? [base] : strip
            let skip = behind.count >= 8 ? 2 : 0
            func worstVs(_ x: RGB) -> Double { behind.map { contrast(x, $0) }.sorted()[skip] }
            let darkest = behind.map(relLum).sorted()[skip]
            let o = toOKLCH(pill)
            var cands: [(L: Double, x: RGB)] = []
            var L = 0.10
            while L <= 0.95 {
                if let x = oklchFit(L, o.C, o.h), relLum(x) >= 0.012 { cands.append((L, x)) }
                L += 0.005
            }
            func nearest(_ ok: (RGB) -> Bool) -> RGB? {
                cands.filter { ok($0.x) }.min { abs($0.L - o.L) < abs($1.L - o.L) }?.x
            }
            if worstVs(pill) < 1.7 || relLum(pill) >= darkest {
                if let x = nearest({ relLum($0) < darkest && worstVs($0) >= 1.7 }) { pill = x }
                else if let x = nearest({ relLum($0) < darkest && worstVs($0) >= 1.5 }) { pill = x }
                else if relLum(pill) >= darkest {
                    let lighter = cands.filter { relLum($0.x) >= darkest && worstVs($0.x) >= 1.3 }
                    if let x = lighter.min(by: { $0.L < $1.L })?.x { pill = x }
                } else if worstVs(pill) < 1.3, let x = nearest({ worstVs($0) >= 1.3 }) { pill = x }
            }
        }

        let accHSV = toHSV(accent)
        if !light && V < 0.30 && baseH >= 140 && baseH <= 185 && accHSV.h >= 140 && accHSV.h <= 180 {
            let ha = toOKLCH(accent).h
            let h = ha + (160 - ha) * 0.5
            accent = oklchFit(0.70, 0.10, h) ?? accent
            shiftedRing = oklchFit(0.68, 0.11, h) ?? shiftedRing
            let lo = toOKLCH(label)
            label = oklchFit(lo.L, 0.04, warm?.hue ?? lo.h) ?? label
            let mo = toOKLCH(muted)
            muted = oklchFit(mo.L, min(mo.C, 0.04), mo.h) ?? muted
            let behindL = (strip.isEmpty ? [base] : strip).map { toOKLCH($0).L }.sorted()
            let shadow = darkTone.map { fromHSV($0.hue, max(min($0.sat, 0.55), 0.5), 0.35) } ?? base
            let hs = toOKLCH(shadow).h
            let pillC = min(0.05, max(0.02, 0.3 * (chroma ?? 0.1)))
            pill = oklchFit(behindL[behindL.count / 2], pillC, hs + (160 - hs) * 0.5) ?? pill
        }
        accent = clearOf(accent, bar: base, pill: pill, preferUp: !light)
        if !light {
            let lo = toOKLCH(label)
            let c = min(0.055, 0.6 * toOKLCH(accent).C)
            label = oklchFit(0.85, max(c, lo.C), lo.h) ?? label
        }
        muted = towardLum(muted, (q8(pill).lum + q8(label).lum) / 2)
        label = legible(label, against: [pill], ratio: 4.5)

        var greyCap: Double? = nil
        if let pc = chroma, pc < 0.07 {
            let cap = max(0.05, 2.5 * pc)
            greyCap = cap
            let o = toOKLCH(accent)
            if o.C > cap { accent = oklchFit(o.L, cap, o.h) ?? accent }
        }

        var surface = base
        do {
            let o = toOKLCH(pill)
            let prefer = light ? toOKLCH(base).L : max(0.12, o.L - 0.12)
            let C = min(o.C, 0.06)
            func at(_ L: Double) -> RGB? { oklchFit(L, C, o.h) }
            func score(_ x: RGB) -> Double {
                min(contrast(label, x) / 7.0, contrast(muted, x) / 4.5, contrast(accent, x) / 3.0)
            }
            var pick: RGB? = nil, pickDist = 9.0, best: RGB? = nil, bestScore = 0.0
            var L = 0.04
            while L <= 0.98 {
                if let x = at(L) {
                    let sc = score(x)
                    if sc >= 1 && abs(L - prefer) < pickDist { pick = x; pickDist = abs(L - prefer) }
                    if sc > bestScore { best = x; bestScore = sc }
                }
                L += 0.01
            }
            surface = pick ?? best ?? base
            if pick == nil {
                label  = legible(label,  against: [pill, surface], ratio: 4.5)
                muted  = legible(muted,  against: [surface], ratio: 4.5)
                accent = legible(accent, against: [pill, surface], ratio: 3.0)
            }
        }
        accent = legible(accent, against: [surface, pill], ratio: 3.0)

        var ring = accent
        if !low {
            let ringS = min(max(0.45, tame), min(0.95, max(0.45, accentS * 1.20)))
            ring = shiftedRing ?? fromHSV(accentH, ringS, light ? 0.86 : 0.94)
            ring = brighten(ring, from: base, need: 0.10)
        }

        if let cap = greyCap {
            let o = toOKLCH(ring)
            if o.C > cap + 0.02 { ring = oklchFit(o.L, cap + 0.02, o.h) ?? ring }
        }

        let rh = toHSV(ring)
        if rh.h >= 35 && rh.h <= 70 && rh.s > 0.65 { ring = fromHSV(rh.h, 0.65, rh.v) }

        return Palette(bar: base, pill: pill, muted: muted, label: label, accent: accent, ring: ring,
                       surface: surface,
                       isLight: light, isLowChroma: low, hue: H, sat: S, val: V)
    }
}

// The terminal formula of helper/term-palette.swift (the computed branch):
// the 16 OMACOSY_P values from the bar roles. Ported verbatim so Magic and
// the auto-theme pipeline open on the same colours.
enum TermFormula {
    struct C {
        var r: Double, g: Double, b: Double

        init(r: Double, g: Double, b: Double) { self.r = r; self.g = g; self.b = b }

        init(hex: String) {
            let v = ColorMath.hexUInt32(hex) ?? 0
            self.init(r: Double((v >> 16) & 0xff) / 255,
                      g: Double((v >> 8) & 0xff) / 255,
                      b: Double(v & 0xff) / 255)
        }

        var hex: String { String(format: "#%02x%02x%02x", q(r), q(g), q(b)) }
        func q(_ v: Double) -> Int { Int((min(1, max(0, v)) * 255).rounded()) }
    }

    static func lin(_ v: Double) -> Double { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
    static func gam(_ v: Double) -> Double { v <= 0.0031308 ? v * 12.92 : 1.055 * pow(v, 1 / 2.4) - 0.055 }

    static func toOK(_ c: C) -> (L: Double, C: Double, h: Double) {
        let r = lin(c.r), g = lin(c.g), b = lin(c.b)
        let l = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
        let m = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
        let s = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
        let L = 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s
        let A = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s
        let B = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
        var h = atan2(B, A) * 180 / .pi; if h < 0 { h += 360 }
        return (L, sqrt(A * A + B * B), h)
    }

    static func fromOK(_ L: Double, _ ch: Double, _ h: Double) -> C? {
        let A = ch * cos(h * .pi / 180), B = ch * sin(h * .pi / 180)
        let l = pow(L + 0.3963377774 * A + 0.2158037573 * B, 3)
        let m = pow(L - 0.1055613458 * A - 0.0638541728 * B, 3)
        let s = pow(L - 0.0894841775 * A - 1.2914855480 * B, 3)
        let r = 4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s
        let g = -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s
        let b = -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s
        let e = 0.001
        guard r >= -e, r <= 1 + e, g >= -e, g <= 1 + e, b >= -e, b <= 1 + e else { return nil }
        return C(r: gam(min(1, max(0, r))), g: gam(min(1, max(0, g))), b: gam(min(1, max(0, b))))
    }

    static func fit(_ L: Double, _ ch: Double, _ h: Double) -> C {
        var c = ch
        while c > 0 { if let x = fromOK(L, c, h) { return x }; c -= 0.005 }
        return fromOK(L, 0, h) ?? C(r: 0, g: 0, b: 0)
    }

    static func relLum(_ c: C) -> Double { 0.2126 * lin(c.r) + 0.7152 * lin(c.g) + 0.0722 * lin(c.b) }

    static func contrast(_ a: C, _ b: C) -> Double {
        let x = relLum(a), y = relLum(b); return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }

    static func legible(_ c: C, on bg: C, ratio: Double) -> C {
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

    // term-palette.swift lines 138-193. Only accent, surface and label feed
    // the 16 values; pill and muted are roles of the env, not of P0..P15.
    static func palette(accent accentHex: String, surface: String, label: String) -> [String] {
        var accent = C(hex: accentHex)
        let lab = C(hex: label)
        var bg = C(hex: surface)

        let dark = relLum(lab) > 0.4
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
        accent = legible(accent, on: bg, ratio: 4.5)

        let aOK = toOK(accent)
        let base: [Double] = [29, 142, 95, 258, 328, 210]
        func harmonised(_ h: Double) -> Double {
            var d = aOK.h - h
            if d > 180 { d -= 360 }; if d < -180 { d += 360 }
            return h + max(-15, min(15, d))
        }
        let chroma = max(0.09, min(0.16, aOK.C * 1.2))
        let normalL = dark ? 0.68 : 0.52, brightL = dark ? 0.80 : 0.62
        let bgL = toOK(bg).L, bgC = min(toOK(bg).C, 0.03), bgH = toOK(bg).h

        var ansi: [String] = []
        ansi.append(fit(bgL + (dark ? 0.10 : -0.10), bgC, bgH).hex)
        for h in base { ansi.append(legible(fit(normalL, chroma, harmonised(h)), on: bg, ratio: 4.5).hex) }
        ansi.append(legible(lab, on: bg, ratio: 7).hex)
        ansi.append(legible(fit(bgL + (dark ? 0.26 : -0.26), bgC, bgH), on: bg, ratio: 3.5).hex)
        for h in base { ansi.append(legible(fit(brightL, chroma, harmonised(h)), on: bg, ratio: 4.5).hex) }
        ansi.append(legible(lab, on: bg, ratio: 10).hex)
        return ansi
    }
}

// The bar roles of the auto-theme pipeline for one image: bar, pill, muted,
// label, accent, ring and the solid surface, all lowercase hex.
struct MagicRoles {
    var bar: DerivePort.RGB
    var pill: DerivePort.RGB
    var muted: DerivePort.RGB
    var label: DerivePort.RGB
    var accent: DerivePort.RGB
    var ring: DerivePort.RGB
    var surface: DerivePort.RGB
    var isLight: Bool
    var isLowChroma: Bool

    var ladder: String { isLight ? "light" : "dark" }
}

func magicRoles(url: URL) throws -> MagicRoles {
    guard let base = DerivePort.baseColour(of: url) else {
        throw ThemeError(message: "cannot decode image: \(url.path)")
    }
    let p = DerivePort.derive(
        base,
        picture: DerivePort.pictureColour(of: url),
        darkTone: DerivePort.darkToneColour(of: url),
        strip: DerivePort.stripSlices(of: url),
        chroma: DerivePort.pictureChroma(of: url),
        warm: DerivePort.warmToneColour(of: url))
    return MagicRoles(bar: p.bar, pill: p.pill, muted: p.muted, label: p.label,
                      accent: p.accent, ring: p.ring, surface: p.surface,
                      isLight: p.isLight, isLowChroma: p.isLowChroma)
}

func magicPalette(url: URL, useCache: Bool = true) throws -> [String] {
    let key = ExtractCache.key(path: url.path, light: false, mode: "magic")
    if useCache, let key, let cached = ExtractCache.load(key) { return cached }

    let roles = try magicRoles(url: url)
    let palette = TermFormula.palette(accent: roles.accent.hex,
                                      surface: roles.surface.hex,
                                      label: roles.label.hex)
    if useCache, let key { ExtractCache.save(key, palette) }
    return palette
}

// MARK: bar roles

struct BarRoles {
    var bar: String
    var pill: String
    var muted: String
    var label: String
    var accent: String
    var ring: String
}

// Maps any 16-colour palette onto the values the bar reads, holding the
// floors of docs/derived-themes.md 4.4 (pill vs bar >= 0.085, label vs pill
// >= 0.50, muted >= 0.18 from both, accent >= 0.28/0.20 from bar and pill,
// ring >= 0.10 from the bar) and then checking the text at WCAG 4.5:1 and
// the accent at 3:1. The blend loops are derive.swift's.
func barRoles(_ colors: [String], accent accentHex: String) -> BarRoles {
    if colors.count != 16 { fail("bar roles need exactly 16 colours") }
    let p0 = DerivePort.RGB(hex: colors[0])
    let p7 = DerivePort.RGB(hex: colors[7])
    let p8 = DerivePort.RGB(hex: colors[8])
    let accentSeed = DerivePort.RGB(hex: accentHex)
    let light = p0.lum > 0.45

    // Surface search (derive.swift): the bar tone in the pill's hue where
    // the label reads at 7:1, muted at 4.5:1 and the accent at 3:1.
    let pillLch = DerivePort.toOKLCH(p8)
    let prefer = light ? DerivePort.toOKLCH(p0).L : max(0.12, pillLch.L - 0.12)
    let chroma = min(pillLch.C, 0.06)
    func at(_ l: Double) -> DerivePort.RGB? { DerivePort.oklchFit(l, chroma, pillLch.h) }
    func score(_ x: DerivePort.RGB) -> Double {
        min(DerivePort.contrast(p7, x) / 7.0,
            DerivePort.contrast(p8, x) / 4.5,
            DerivePort.contrast(accentSeed, x) / 3.0)
    }
    var bar = p0
    var pick: DerivePort.RGB? = nil
    var pickDist = 9.0
    var best: DerivePort.RGB? = nil
    var bestScore = 0.0
    var l = 0.04
    while l <= 0.98 {
        if let x = at(l) {
            let sc = score(x)
            if sc >= 1 && abs(l - prefer) < pickDist { pick = x; pickDist = abs(l - prefer) }
            if sc > bestScore { best = x; bestScore = sc }
        }
        l += 0.01
    }
    bar = pick ?? best ?? p0

    // The pill and the label are built as a pair on the ladder's side: on a
    // light bar the pill sits below it with a dark label under that; on a
    // dark bar above it with a light label over it. The luminance targets
    // leave the 0.085 and 0.50 floors room by construction, and the WCAG
    // pass below only has to fine-tune.
    let barL = DerivePort.q8(bar).lum
    let up = !light
    func separateDir(_ c: DerivePort.RGB, from ref: DerivePort.RGB, need: Double, up: Bool) -> DerivePort.RGB {
        let lr = DerivePort.q8(ref).lum
        if abs(DerivePort.q8(c).lum - lr) >= need { return c }
        let target = up ? DerivePort.white : DerivePort.black
        for step in 1...50 {
            let cand = DerivePort.blend(c, toward: target, 0.02 * Double(step))
            if abs(DerivePort.q8(cand).lum - lr) >= need { return cand }
        }
        return target
    }

    let pillL = light ? min(0.58, barL - 0.20) : min(0.20, max(barL + 0.10, 0.10))
    var pill = DerivePort.towardLum(p8, pillL)
    pill = separateDir(pill, from: bar, need: 0.085, up: up)
    let labelL = light ? max(0.02, DerivePort.q8(pill).lum - 0.55)
                       : min(0.98, DerivePort.q8(pill).lum + 0.55)
    var label = DerivePort.towardLum(p7, labelL)
    label = separateDir(label, from: pill, need: 0.50, up: up)
    var muted = DerivePort.towardLum(p8, (DerivePort.q8(pill).lum + DerivePort.q8(label).lum) / 2)
    var accent = DerivePort.clearOf(accentSeed, bar: bar, pill: pill, preferUp: !light)

    // Text checks first, then the floors: separate() and clearOf() only move
    // a colour further away, so re-flooring cannot give the contrast back.
    func floorPass() {
        if abs(DerivePort.q8(pill).lum - DerivePort.q8(bar).lum) < 0.085 {
            pill = separateDir(pill, from: bar, need: 0.085, up: up)
        }
        if abs(DerivePort.q8(label).lum - DerivePort.q8(pill).lum) < 0.50 {
            label = separateDir(label, from: pill, need: 0.50, up: up)
        }
        let lp = DerivePort.q8(pill).lum, ll = DerivePort.q8(label).lum
        let lm = DerivePort.q8(muted).lum
        if abs(lm - lp) < 0.18 || abs(lm - ll) < 0.18 {
            muted = DerivePort.towardLum(muted, (lp + ll) / 2)
        }
        if abs(DerivePort.q8(accent).lum - DerivePort.q8(bar).lum) < 0.28 ||
           abs(DerivePort.q8(accent).lum - DerivePort.q8(pill).lum) < 0.20 {
            accent = DerivePort.clearOf(accent, bar: bar, pill: pill, preferUp: !light)
        }
    }

    for _ in 0..<3 {
        label = DerivePort.legible(label, against: [bar, pill], ratio: 4.5)
        muted = DerivePort.legible(muted, against: [bar], ratio: 4.5)
        accent = DerivePort.legible(accent, against: [bar, pill], ratio: 3.0)
        floorPass()
    }

    let ring = DerivePort.brighten(accent, from: bar, need: 0.10)
    return BarRoles(bar: bar.hex, pill: pill.hex, muted: muted.hex,
                    label: label.hex, accent: accent.hex, ring: ring.hex)
}

// The Light/Dark suggestion: the same fill-crop band baseColour reads, before
// the menu-bar transform, over the 0.5 luma line.
func suggestMode(url: URL) throws -> String {
    guard let mean = DerivePort.fillCropMean(of: url) else {
        throw ThemeError(message: "cannot decode image: \(url.path)")
    }
    return mean.lum > 0.5 ? "light" : "dark"
}

// MARK: Pixel sampling

struct SampleResult {
    var format: String
    var width: Int
    var height: Int
    var hasAlpha: Bool
    var pixels: [RGB]
    var mean: (r: Double, g: Double, b: Double)
    var digest: String
}

// Decode the image, scale it to 400 px on the long side, and take every
// step-th pixel (up to 50 000). The bitmap is an sRGB context, so an embedded
// profile is converted, never read raw — the 22/255 trap of derive.swift.
// Unlike Aether's Go CatmullRom downscale, ImageIO's resampler differs by a
// few thousandths of a byte; exact fixtures are recorded on images whose long
// side is already 400, where both pipelines are identity up to the pixel.
func sampleImage(url: URL) throws -> SampleResult {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
          let width = props[kCGImagePropertyPixelWidth] as? Int,
          let height = props[kCGImagePropertyPixelHeight] as? Int else {
        throw ThemeError(message: "cannot read image: \(url.path)")
    }
    guard width > 0, height > 0,
          width <= Extract.maxImageDimension, height <= Extract.maxImageDimension,
          width * height <= Extract.maxImagePixels else {
        throw ThemeError(message: "unsafe image dimensions \(width)x\(height)")
    }
    guard let cg = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        throw ThemeError(message: "cannot decode image: \(url.path)")
    }

    let dw: Int, dh: Int
    if width >= height {
        dw = Extract.imageScaleSize
        dh = max(1, Int((Double(height) * Double(Extract.imageScaleSize) / Double(width)).rounded()))
    } else {
        dh = Extract.imageScaleSize
        dw = max(1, Int((Double(width) * Double(Extract.imageScaleSize) / Double(height)).rounded()))
    }

    let bytesPerRow = dw * 4
    let byteCount = bytesPerRow * dh
    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: byteCount)
    defer { buffer.deallocate() }
    buffer.initialize(repeating: 0, count: byteCount)

    guard let space = CGColorSpace(name: CGColorSpace.sRGB),
          let context = CGContext(data: buffer, width: dw, height: dh, bitsPerComponent: 8,
                                  bytesPerRow: bytesPerRow, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        throw ThemeError(message: "cannot create the sRGB bitmap for \(url.path)")
    }
    context.interpolationQuality = .high
    context.draw(cg, in: CGRect(x: 0, y: 0, width: dw, height: dh))

    let step = max(1, Int(floor(Double(dw * dh) / Double(Extract.maxPixelsToSample))))
    var pixels: [RGB] = []
    pixels.reserveCapacity(min(dw * dh, Extract.maxPixelsToSample))
    var bytes: [UInt8] = []
    bytes.reserveCapacity(pixels.capacity * 3)
    var rSum = 0.0, gSum = 0.0, bSum = 0.0

    for y in stride(from: 0, to: dh, by: step) {
        for x in stride(from: 0, to: dw, by: step) {
            let offset = y * bytesPerRow + x * 4
            let alpha = buffer[offset + 3]
            if alpha < 128 { continue }
            let r: Double, g: Double, b: Double
            if alpha == 255 {
                r = Double(buffer[offset])
                g = Double(buffer[offset + 1])
                b = Double(buffer[offset + 2])
            } else {
                let a = Double(alpha) / 255.0
                r = min(255, (Double(buffer[offset]) / a).rounded())
                g = min(255, (Double(buffer[offset + 1]) / a).rounded())
                b = min(255, (Double(buffer[offset + 2]) / a).rounded())
            }
            pixels.append(RGB(r: r, g: g, b: b))
            bytes.append(UInt8(r))
            bytes.append(UInt8(g))
            bytes.append(UInt8(b))
            rSum += r
            gSum += g
            bSum += b
        }
    }

    let n = Double(pixels.count)
    let mean: (r: Double, g: Double, b: Double) = n > 0 ? (rSum / n, gSum / n, bSum / n) : (0, 0, 0)
    let digest = SHA256.hash(data: Data(bytes)).map { String(format: "%02x", $0) }.joined()
    let type = CGImageSourceGetType(source) as String? ?? ""
    let format = type.components(separatedBy: ".").last?.uppercased() ?? "UNKNOWN"
    let hasAlpha = (props[kCGImagePropertyHasAlpha] as? Bool) ?? false

    return SampleResult(format: format, width: width, height: height, hasAlpha: hasAlpha,
                        pixels: pixels, mean: mean, digest: digest)
}

// The 256-bin luminance histogram of an image, for the tone-curve backdrop.
// Ported from Aether's computeHistogram (frontend canvas-filters.ts): the
// image is drawn at no more than 512 px wide in sRGB and every pixel lands
// in bin (r*77 + g*150 + b*29) >> 8, its BT.601 luma.
func imageHistogram(url: URL, maxWidth: Int = 512) throws -> [Int] {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
          let width = props[kCGImagePropertyPixelWidth] as? Int,
          let height = props[kCGImagePropertyPixelHeight] as? Int else {
        throw ThemeError(message: "cannot read image: \(url.path)")
    }
    guard width > 0, height > 0,
          width <= Extract.maxImageDimension, height <= Extract.maxImageDimension,
          width * height <= Extract.maxImagePixels else {
        throw ThemeError(message: "unsafe image dimensions \(width)x\(height)")
    }
    guard let cg = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        throw ThemeError(message: "cannot decode image: \(url.path)")
    }

    let dw = min(width, maxWidth)
    let dh = max(1, Int((Double(height) * Double(dw) / Double(width)).rounded()))
    let bytesPerRow = dw * 4
    let byteCount = bytesPerRow * dh
    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: byteCount)
    defer { buffer.deallocate() }
    buffer.initialize(repeating: 0, count: byteCount)

    guard let space = CGColorSpace(name: CGColorSpace.sRGB),
          let context = CGContext(data: buffer, width: dw, height: dh, bitsPerComponent: 8,
                                  bytesPerRow: bytesPerRow, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        throw ThemeError(message: "cannot create the sRGB bitmap for \(url.path)")
    }
    context.interpolationQuality = .high
    context.draw(cg, in: CGRect(x: 0, y: 0, width: dw, height: dh))

    var histogram = [Int](repeating: 0, count: 256)
    for y in 0..<dh {
        for x in 0..<dw {
            let offset = y * bytesPerRow + x * 4
            let alpha = buffer[offset + 3]
            if alpha < 128 { continue }
            var r = Int(buffer[offset]), g = Int(buffer[offset + 1]), b = Int(buffer[offset + 2])
            if alpha != 255 {
                let a = Double(alpha) / 255.0
                r = min(255, Int((Double(r) / a).rounded()))
                g = min(255, Int((Double(g) / a).rounded()))
                b = min(255, Int((Double(b) / a).rounded()))
            }
            let luma = (r * 77 + g * 150 + b * 29) >> 8
            histogram[min(255, max(0, luma))] += 1
        }
    }
    return histogram
}

// MARK: - Theme records (schema v1)

// One JSON file per theme under ~/.config/omacosy/themes/. The typed fields
// are the v1 schema of the plan; `raw` keeps the document as parsed, so keys
// this build does not know survive a load -> save round-trip untouched.
// Writing is canonical: sorted keys, two-space indent, one trailing newline.
// `id` is immutable -- a rename edits `name` only.

struct ThemeError: Error { let message: String }

struct Extended {
    var accent: String
    var cursor: String
    var selectionForeground: String
    var selectionBackground: String

    // Engine rule: when absent, these derive from the palette.
    static func defaults(for colors: [String]) -> Extended {
        Extended(accent: colors[4], cursor: colors[7],
                 selectionForeground: colors[0], selectionBackground: colors[7])
    }
}

struct ThemeWallpaper {
    var path: String?
    var source = "local"
    var wallhaven: [String: Any]?
    var media: String?
    var blur = false
    var edited = false
}

struct Palette16 {
    var method: String
    var mode = "auto"
    var resolvedMode = "dark"
    var colors: [String]
    var extended: Extended
    var locked: [Int] = []
    var adjustments = Adjustments()
    var curve: [[Double]] = []
}

struct Theme {
    static let defaultTerminals = ["ghostty", "btop", "nvim", "lazygit", "fastfetch",
                                   "yazi", "bat", "delta", "fzf", "tmux"]

    var schema = 1
    var id: String
    var name: String
    var primary = false
    var created: String?
    var updated: String?
    var wallpaper = ThemeWallpaper()
    var palette: Palette16
    var appOverrides: [String: [String: String]] = [:]
    var terminals = Theme.defaultTerminals
    var favorite = false
    var raw: [String: Any] = [:]
}

func isThemeID(_ value: String) -> Bool {
    !value.isEmpty && value.range(of: "^[a-z0-9-]+$", options: .regularExpression) != nil
}

// "Sunset Drive (Night)" -> "sunset-drive-night"; the base of a new id.
func slugify(_ name: String) -> String {
    var out = ""
    var pendingDash = false
    for ch in name.lowercased() {
        if (ch.isASCII && ch.isLetter) || (ch.isASCII && ch.isNumber) {
            if pendingDash && !out.isEmpty { out.append("-") }
            out.append(ch)
            pendingDash = false
        } else {
            pendingDash = true
        }
    }
    return out.isEmpty ? "theme" : out
}

func isoNow() -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    formatter.timeZone = TimeZone(identifier: "UTC")
    return formatter.string(from: Date())
}

// "#abc" and "AABBCC" normalise to "#aabbcc"; anything else is nil.
func normalizedColorHex(_ raw: String) -> String? {
    var s = raw.trimmingCharacters(in: .whitespaces).lowercased()
    if !s.hasPrefix("#") { s = "#" + s }
    guard ColorMath.isHexColor(s) else { return nil }
    if s.count == 4 {
        let digits = Array(s.dropFirst())
        s = "#" + digits.map { "\($0)\($0)" }.joined()
    }
    return s
}

// JSONSerialization hands back NSNumber for every number. objCType "c" is
// a boolean (the shared CFBoolean singletons); only JSON booleans get it.
enum JSONField {
    static func bool(_ value: Any?) -> Bool? {
        guard let n = value as? NSNumber, String(cString: n.objCType) == "c" else { return nil }
        return n.boolValue
    }
    static func number(_ value: Any?) -> Double? {
        guard let n = value as? NSNumber, String(cString: n.objCType) != "c" else { return nil }
        return n.doubleValue
    }
    static func int(_ value: Any?) -> Int? {
        guard let d = number(value), d.rounded() == d else { return nil }
        return Int(d)
    }
    static func string(_ value: Any?) -> String? { value as? String }
    static func dict(_ value: Any?) -> [String: Any]? { value as? [String: Any] }
    static func array(_ value: Any?) -> [Any]? { value as? [Any] }
}

func jsonTopLevel(_ data: Data, label: String) throws -> [String: Any] {
    let object: Any
    do { object = try JSONSerialization.jsonObject(with: data) }
    catch { throw ThemeError(message: "\(label): not valid JSON (\(error.localizedDescription))") }
    guard let top = object as? [String: Any] else {
        throw ThemeError(message: "\(label): the top level must be a JSON object")
    }
    return top
}

extension Theme {
    static func parse(_ data: Data, label: String) throws -> Theme {
        try parse(try jsonTopLevel(data, label: label), label: label)
    }

    static func parse(_ top: [String: Any], label: String) throws -> Theme {
        func bad(_ what: String) throws -> Never {
            throw ThemeError(message: "\(label): \(what)")
        }

        guard let schema = JSONField.int(top["schema"]) else {
            try bad("missing or non-numeric \"schema\" (expected 1)")
        }
        guard schema == 1 else {
            try bad("unsupported \"schema\" \(schema); this build understands schema 1")
        }
        guard let id = JSONField.string(top["id"]) else { try bad("missing \"id\"") }
        guard isThemeID(id) else { try bad("\"id\" must match [a-z0-9-]+ (got \"\(id)\")") }
        guard let name = JSONField.string(top["name"]),
              !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            try bad("\"name\" must be a non-empty string")
        }

        guard let paletteObj = JSONField.dict(top["palette"]) else { try bad("missing \"palette\"") }
        guard let method = JSONField.string(paletteObj["method"]), isThemeID(method) else {
            try bad("\"palette.method\" must match [a-z0-9-]+")
        }
        guard let rawColors = JSONField.array(paletteObj["colors"]) else {
            try bad("\"palette.colors\" must be an array of 16 hex colours")
        }
        guard rawColors.count == 16 else {
            try bad("\"palette.colors\" holds \(rawColors.count) colours; exactly 16 are required")
        }
        var colors: [String] = []
        for (i, item) in rawColors.enumerated() {
            guard let s = JSONField.string(item), let hex = normalizedColorHex(s) else {
                try bad("\"palette.colors[\(i)]\" is not a hex colour")
            }
            colors.append(hex)
        }

        let mode = JSONField.string(paletteObj["mode"]) ?? "auto"
        guard ["auto", "dark", "light"].contains(mode) else {
            try bad("\"palette.mode\" must be auto, dark or light (got \"\(mode)\")")
        }
        let resolvedMode = JSONField.string(paletteObj["resolvedMode"]) ?? (mode == "light" ? "light" : "dark")
        guard ["dark", "light"].contains(resolvedMode) else {
            try bad("\"palette.resolvedMode\" must be dark or light (got \"\(resolvedMode)\")")
        }

        var extended = Extended.defaults(for: colors)
        if let extObj = JSONField.dict(paletteObj["extended"]) {
            func colour(_ key: String, _ fallback: String) throws -> String {
                guard let value = extObj[key] else { return fallback }
                guard let s = JSONField.string(value), let hex = normalizedColorHex(s) else {
                    try bad("\"palette.extended.\(key)\" is not a hex colour")
                }
                return hex
            }
            extended.accent = try colour("accent", extended.accent)
            extended.cursor = try colour("cursor", extended.cursor)
            extended.selectionForeground = try colour("selection_foreground", extended.selectionForeground)
            extended.selectionBackground = try colour("selection_background", extended.selectionBackground)
        } else if paletteObj["extended"] != nil && !(paletteObj["extended"] is NSNull) {
            try bad("\"palette.extended\" must be an object")
        }

        // `locked` is the v1 spelling; Aether's `lockedColors` is accepted as
        // indices or as 16 positional booleans, and normalised to `locked`.
        var locked: [Int] = []
        let lockedValue = paletteObj["locked"] ?? paletteObj["lockedColors"]
        if let value = lockedValue, !(value is NSNull) {
            guard let arr = JSONField.array(value) else {
                try bad("\"palette.locked\" must be an array of indices or booleans")
            }
            var indices: [Int] = []
            if let first = arr.first, JSONField.bool(first) != nil {
                for (i, item) in arr.enumerated() where JSONField.bool(item) == true { indices.append(i) }
            } else {
                for item in arr {
                    guard let i = JSONField.int(item), i >= 0, i < 16 else {
                        try bad("\"palette.locked\" indices must be whole numbers 0...15")
                    }
                    indices.append(i)
                }
            }
            locked = Array(Set(indices)).sorted()
        }

        var adjustments = Adjustments()
        if let adjObj = JSONField.dict(paletteObj["adjustments"]) {
            func number(_ key: String) throws -> Double? {
                guard let value = adjObj[key] else { return nil }
                guard let d = JSONField.number(value) else {
                    throw ThemeError(message: "\(label): \"palette.adjustments.\(key)\" must be a number")
                }
                return d
            }
            if let v = try number("vibrance") { adjustments.vibrance = v }
            if let v = try number("saturation") { adjustments.saturation = v }
            if let v = try number("contrast") { adjustments.contrast = v }
            if let v = try number("brightness") { adjustments.brightness = v }
            if let v = try number("shadows") { adjustments.shadows = v }
            if let v = try number("highlights") { adjustments.highlights = v }
            if let v = try number("hueShift") { adjustments.hueShift = v }
            if let v = try number("temperature") { adjustments.temperature = v }
            if let v = try number("tint") { adjustments.tint = v }
            if let v = try number("blackPoint") { adjustments.blackPoint = v }
            if let v = try number("whitePoint") { adjustments.whitePoint = v }
            if let v = try number("gamma") { adjustments.gamma = v }
        } else if paletteObj["adjustments"] != nil && !(paletteObj["adjustments"] is NSNull) {
            try bad("\"palette.adjustments\" must be an object")
        }

        var curve: [[Double]] = []
        if let value = paletteObj["curve"], !(value is NSNull) {
            guard let arr = JSONField.array(value) else {
                try bad("\"palette.curve\" must be an array of [x, y] points")
            }
            for (i, item) in arr.enumerated() {
                guard let pair = JSONField.array(item), pair.count == 2,
                      let x = JSONField.number(pair[0]), let y = JSONField.number(pair[1]) else {
                    try bad("\"palette.curve[\(i)]\" must be an [x, y] pair of numbers")
                }
                guard x >= 0, x <= 1, y >= 0, y <= 1 else {
                    try bad("\"palette.curve[\(i)]\" must lie inside 0...1")
                }
                if let last = curve.last, x <= last[0] {
                    try bad("\"palette.curve\" x values must strictly increase")
                }
                curve.append([x, y])
            }
        }

        var wallpaper = ThemeWallpaper()
        if let value = top["wallpaper"], !(value is NSNull) {
            guard let wallObj = JSONField.dict(value) else { try bad("\"wallpaper\" must be an object") }
            if let v = wallObj["path"], !(v is NSNull) {
                guard let s = JSONField.string(v) else { try bad("\"wallpaper.path\" must be a string") }
                wallpaper.path = s
            }
            if let v = wallObj["source"] {
                guard let s = JSONField.string(v), ["local", "wallhaven", "stock"].contains(s) else {
                    try bad("\"wallpaper.source\" must be local, wallhaven or stock")
                }
                wallpaper.source = s
            }
            if let v = wallObj["wallhaven"], !(v is NSNull) {
                guard let d = JSONField.dict(v) else { try bad("\"wallpaper.wallhaven\" must be an object") }
                wallpaper.wallhaven = d
            }
            if let v = wallObj["media"], !(v is NSNull) {
                guard let s = JSONField.string(v), !s.isEmpty, !s.contains("/"), !s.contains("..") else {
                    try bad("\"wallpaper.media\" must be a bare filename")
                }
                wallpaper.media = s
            }
            if let v = wallObj["blur"] {
                guard let b = JSONField.bool(v) else { try bad("\"wallpaper.blur\" must be true or false") }
                wallpaper.blur = b
            }
            if let v = wallObj["edited"] {
                guard let b = JSONField.bool(v) else { try bad("\"wallpaper.edited\" must be true or false") }
                wallpaper.edited = b
            }
        }

        var appOverrides: [String: [String: String]] = [:]
        if let value = top["appOverrides"], !(value is NSNull) {
            guard let obj = JSONField.dict(value) else { try bad("\"appOverrides\" must be an object") }
            for (app, roles) in obj {
                guard let roleObj = JSONField.dict(roles) else {
                    try bad("\"appOverrides.\(app)\" must be an object of role -> colour")
                }
                var out: [String: String] = [:]
                for (role, colour) in roleObj {
                    guard let s = JSONField.string(colour), let hex = normalizedColorHex(s) else {
                        try bad("\"appOverrides.\(app).\(role)\" is not a hex colour")
                    }
                    out[role] = hex
                }
                appOverrides[app] = out
            }
        }

        var terminals = Theme.defaultTerminals
        if let value = top["terminals"] {
            guard let arr = JSONField.array(value) else { try bad("\"terminals\" must be an array of names") }
            var out: [String] = []
            for (i, item) in arr.enumerated() {
                guard let s = JSONField.string(item), !s.isEmpty else {
                    try bad("\"terminals[\(i)]\" must be a non-empty string")
                }
                out.append(s)
            }
            terminals = out
        }

        var primary = false
        if let v = top["primary"] {
            guard let b = JSONField.bool(v) else { try bad("\"primary\" must be true or false") }
            primary = b
        }
        var favorite = false
        if let v = top["favorite"] {
            guard let b = JSONField.bool(v) else { try bad("\"favorite\" must be true or false") }
            favorite = b
        }
        let created = top["created"].flatMap { JSONField.string($0) }
        let updated = top["updated"].flatMap { JSONField.string($0) }

        return Theme(schema: schema, id: id, name: name, primary: primary,
                     created: created, updated: updated,
                     wallpaper: wallpaper,
                     palette: Palette16(method: method, mode: mode, resolvedMode: resolvedMode,
                                           colors: colors, extended: extended, locked: locked,
                                           adjustments: adjustments, curve: curve),
                     appOverrides: appOverrides, terminals: terminals, favorite: favorite, raw: top)
    }
}

private func jsonOrNull(_ value: String?) -> Any {
    value.map { $0 as Any } ?? NSNull()
}

// The canonical theme writer is hand-rolled for one reason: JSONSerialization
// prints a parsed 0.18 back as 0.17999999999999999, and these records are read
// by people in Zed. Swift's Double description is the shortest round-trip
// form, so the file stays clean and still lossless. Keys sort, indent is two
// spaces, and only `"` and `\` plus control characters are escaped.
private func jsonQuoted(_ value: String) -> String {
    var out = "\""
    for scalar in value.unicodeScalars {
        switch scalar {
        case "\"": out += "\\\""
        case "\\": out += "\\\\"
        case "\n": out += "\\n"
        case "\r": out += "\\r"
        case "\t": out += "\\t"
        default:
            if scalar.value < 0x20 {
                out += String(format: "\\u%04x", scalar.value)
            } else {
                out.unicodeScalars.append(scalar)
            }
        }
    }
    return out + "\""
}

private func jsonRendered(_ value: Any, depth: Int) -> String {
    switch value {
    case let number as NSNumber:
        let type = String(cString: number.objCType)
        if type == "c" || type == "B" { return number.boolValue ? "true" : "false" }
        if type == "d" || type == "f" { return "\(number.doubleValue)" }
        return number.stringValue
    case let bool as Bool:
        return bool ? "true" : "false"
    case let string as String:
        return jsonQuoted(string)
    case is NSNull:
        return "null"
    case let array as [Any]:
        if array.isEmpty { return "[]" }
        let inner = String(repeating: "  ", count: depth + 1)
        let body = array.map { inner + jsonRendered($0, depth: depth + 1) }
        return "[\n" + body.joined(separator: ",\n") + "\n" + String(repeating: "  ", count: depth) + "]"
    case let object as [String: Any]:
        if object.isEmpty { return "{}" }
        let inner = String(repeating: "  ", count: depth + 1)
        let body = object.keys.sorted().map {
            inner + jsonQuoted($0) + " : " + jsonRendered(object[$0]!, depth: depth + 1)
        }
        return "{\n" + body.joined(separator: ",\n") + "\n" + String(repeating: "  ", count: depth) + "}"
    default:
        return jsonQuoted(String(describing: value))
    }
}

extension Theme {
    func canonicalObject() -> [String: Any] {
        var out = raw
        out["schema"] = schema
        out["id"] = id
        out["name"] = name
        out["primary"] = primary
        if let created { out["created"] = created }
        if let updated { out["updated"] = updated }
        out["favorite"] = favorite
        out["terminals"] = terminals
        out["appOverrides"] = appOverrides

        var wall = JSONField.dict(raw["wallpaper"]) ?? [:]
        wall["path"] = jsonOrNull(wallpaper.path)
        wall["source"] = wallpaper.source
        wall["media"] = jsonOrNull(wallpaper.media)
        wall["blur"] = wallpaper.blur
        wall["edited"] = wallpaper.edited
        if let wallhaven = wallpaper.wallhaven { wall["wallhaven"] = wallhaven }
        out["wallpaper"] = wall

        var pal = JSONField.dict(raw["palette"]) ?? [:]
        pal["method"] = palette.method
        pal["mode"] = palette.mode
        pal["resolvedMode"] = palette.resolvedMode
        pal["colors"] = palette.colors
        var ext = JSONField.dict(pal["extended"]) ?? [:]
        ext["accent"] = palette.extended.accent
        ext["cursor"] = palette.extended.cursor
        ext["selection_foreground"] = palette.extended.selectionForeground
        ext["selection_background"] = palette.extended.selectionBackground
        pal["extended"] = ext
        pal["locked"] = palette.locked
        pal.removeValue(forKey: "lockedColors")
        var adj = JSONField.dict(pal["adjustments"]) ?? [:]
        adj["vibrance"] = palette.adjustments.vibrance
        adj["saturation"] = palette.adjustments.saturation
        adj["contrast"] = palette.adjustments.contrast
        adj["brightness"] = palette.adjustments.brightness
        adj["shadows"] = palette.adjustments.shadows
        adj["highlights"] = palette.adjustments.highlights
        adj["hueShift"] = palette.adjustments.hueShift
        adj["temperature"] = palette.adjustments.temperature
        adj["tint"] = palette.adjustments.tint
        adj["blackPoint"] = palette.adjustments.blackPoint
        adj["whitePoint"] = palette.adjustments.whitePoint
        adj["gamma"] = palette.adjustments.gamma
        pal["adjustments"] = adj
        pal["curve"] = palette.curve
        out["palette"] = pal
        return out
    }

    // Canonical bytes, ending in one newline: `theme show <id>` prints
    // exactly what is on disk, and re-saving an unchanged record does not
    // move a byte.
    func canonicalData() throws -> Data {
        let object = canonicalObject()
        guard JSONSerialization.isValidJSONObject(object) else {
            throw ThemeError(message: "theme \"\(id)\" does not encode as JSON")
        }
        return Data((jsonRendered(object, depth: 0) + "\n").utf8)
    }
}

// MARK: - Theme library

struct ThemeLibrary {
    let dir: URL
    let mediaDir: URL
    let materialisedDir: URL

    init() {
        let env = ProcessInfo.processInfo.environment
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let config = env["OMACOSY_CONFIG_DIR"] ?? "\(home)/.config/omacosy"
        let state = env["OMACOSY_STATE_DIR"] ?? "\(home)/.local/state/omacosy"
        let data = env["OMACOSY_DATA_DIR"] ?? "\(home)/.local/share/omacosy"
        dir = URL(fileURLWithPath: env["OMACOSY_THEMES_DIR"] ?? "\(config)/themes")
        mediaDir = URL(fileURLWithPath: "\(data)/theme-media")
        materialisedDir = URL(fileURLWithPath: "\(state)/studio/materialised")
    }

    func fileURL(id: String) -> URL { dir.appendingPathComponent("\(id).json") }

    func exists(id: String) -> Bool {
        FileManager.default.fileExists(atPath: fileURL(id: id).path)
    }

    func recordFiles() -> [URL] {
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil) else { return [] }
        return items
            .filter { $0.pathExtension == "json" && $0.lastPathComponent != "library.json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    func load(id: String) throws -> Theme {
        let url = fileURL(id: id)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ThemeError(message: "no theme \"\(id)\" in \(dir.path)")
        }
        return try load(url: url)
    }

    func load(url: URL) throws -> Theme {
        let data: Data
        do { data = try Data(contentsOf: url) }
        catch { throw ThemeError(message: "\(url.path): cannot read (\(error.localizedDescription))") }
        return try Theme.parse(data, label: url.lastPathComponent)
    }

    // Sorted the way the Themes tab shows named editions: A to Z, then id.
    // One unreadable file warns and is skipped rather than failing the list.
    func loadAll(warnings: inout [String]) -> [Theme] {
        var themes: [Theme] = []
        for url in recordFiles() {
            do { themes.append(try load(url: url)) }
            catch let e as ThemeError { warnings.append(e.message) }
            catch { warnings.append("\(url.lastPathComponent): \(error)") }
        }
        return themes.sorted {
            let a = $0.name.lowercased(), b = $1.name.lowercased()
            return a == b ? $0.id < $1.id : a < b
        }
    }

    @discardableResult
    func write(_ theme: Theme) throws -> URL {
        do { try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true) }
        catch { throw ThemeError(message: "cannot create \(dir.path): \(error.localizedDescription)") }
        let url = fileURL(id: theme.id)
        try ThemeLibrary.writeAtomically(try theme.canonicalData(), to: url)
        return url
    }

    // Temp file, fsync, rename: a reader never sees half a record, and a
    // crash never leaves the library without the theme it was editing.
    static func writeAtomically(_ data: Data, to url: URL) throws {
        let tmp = url.deletingLastPathComponent()
            .appendingPathComponent(".\(url.lastPathComponent).tmp-\(ProcessInfo.processInfo.processIdentifier)")
        do {
            try data.write(to: tmp)
            if let handle = try? FileHandle(forWritingTo: tmp) {
                try? handle.synchronize()
                try? handle.close()
            }
        } catch {
            try? FileManager.default.removeItem(at: tmp)
            throw ThemeError(message: "cannot write \(url.path): \(error.localizedDescription)")
        }
        if rename(tmp.path, url.path) != 0 {
            let reason = String(cString: strerror(errno))
            try? FileManager.default.removeItem(at: tmp)
            throw ThemeError(message: "cannot write \(url.path): \(reason)")
        }
    }

    func nextFreeId(_ base: String) -> String {
        var candidate = base
        var n = 2
        while exists(id: candidate) {
            candidate = "\(base)-\(n)"
            n += 1
        }
        return candidate
    }

    // Exactly one primary per source path: the first save becomes primary on
    // its own, an explicit primary demotes the rest, and a deleted primary
    // hands the flag to the earliest remaining edition (created, then id).
    func normalizePrimary(forPath path: String) throws {
        guard !path.isEmpty else { return }
        var warnings: [String] = []
        let group = loadAll(warnings: &warnings).filter { $0.wallpaper.path == path }
        guard !group.isEmpty else { return }
        let ordered = group.sorted {
            ($0.created ?? "", $0.id) < ($1.created ?? "", $1.id)
        }
        guard let winner = ordered.first else { return }
        for var theme in group {
            let want = theme.id == winner.id
            if theme.primary != want {
                theme.primary = want
                theme.updated = isoNow()
                try write(theme)
            }
        }
    }

    // The edition's own image copy is pruned only when no record references
    // it any more; media is content-addressed, so several editions share one.
    func pruneUnreferencedMedia(_ media: String?) {
        guard let media, !media.isEmpty,
              media.rangeOfCharacter(from: CharacterSet(charactersIn: "/")) == nil else { return }
        var warnings: [String] = []
        guard !loadAll(warnings: &warnings).contains(where: { $0.wallpaper.media == media }) else { return }
        let url = mediaDir.appendingPathComponent(media)
        if FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    // The edition's own image copy, captured at first save: content-addressed
    // (<sha256-16>.<ext>) so several editions of one wallpaper share a file,
    // and a rename, move or deletion of the source cannot break them. An
    // existing destination is already the same bytes; nothing is written.
    func captureMedia(from path: String) throws -> String {
        let url = URL(fileURLWithPath: path)
        guard let data = FileManager.default.contents(atPath: url.path) else {
            throw ThemeError(message: "cannot read \(url.path)")
        }
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        var ext = url.pathExtension.lowercased().filter { $0.isLetter || $0.isNumber }
        if ext.isEmpty { ext = "img" }
        let name = String(digest.prefix(16)) + "." + ext
        let dest = mediaDir.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: dest.path) { return name }
        do { try FileManager.default.createDirectory(at: mediaDir, withIntermediateDirectories: true) }
        catch { throw ThemeError(message: "cannot create \(mediaDir.path): \(error.localizedDescription)") }
        let tmp = mediaDir.appendingPathComponent(".\(name).tmp-\(ProcessInfo.processInfo.processIdentifier)")
        do {
            try data.write(to: tmp)
            if FileManager.default.fileExists(atPath: dest.path) {
                try? FileManager.default.removeItem(at: tmp)   // lost a race
            } else {
                try FileManager.default.moveItem(at: tmp, to: dest)
            }
        } catch {
            try? FileManager.default.removeItem(at: tmp)
            throw ThemeError(message: "cannot capture \(url.path): \(error.localizedDescription)")
        }
        return name
    }

    // Materialised directories are disposable and named <id>-<rev>; deleting
    // the record makes them orphans, so they go with it. Best effort.
    func removeMaterialised(id: String) {
        guard let items = try? FileManager.default.contentsOfDirectory(atPath: materialisedDir.path) else { return }
        for item in items where item.hasPrefix("\(id)-") {
            try? FileManager.default.removeItem(at: materialisedDir.appendingPathComponent(item))
        }
    }
}

// MARK: - Materialise

// Turns a stored theme record into a runnable theme directory. The bar, the
// ring and the terminal pipeline read DIRECTORIES through
// ~/.config/omarchy/current/theme, never a JSON file, so an edition becomes
// usable only once it has been materialised into the same shape the stock
// themes have:
//
//   sketchybar.sh   the bar palette (barRoles + the semantic trio)
//   borders.sh      the focus ring's two colours
//   colors.toml     omarchy's 22-key palette, for the terminal pipeline
//   backgrounds/    one symlink to the edition's own image
//   preview.png     a small thumbnail of that image
//
// The directory is named <id>-<rev>, where `rev` is a short content hash of
// everything that shapes those files. An unchanged re-apply therefore lands
// on the same directory the live symlink already points at, and the bar and
// the ring get no kqueue event and repaint nothing; one changed colour means
// a new revision, a new symlink target and exactly one real event. That is
// the whole point of the hash. A new directory is built beside its final
// name and renamed into place, so a reader never sees half a theme.
enum Materialise {
    static let semanticDark  = ["RED": "0xffe05f5f", "GREEN": "0xff6fcf87", "YELLOW": "0xffe5c736"]
    static let semanticLight = ["RED": "0xff9d1f1f", "GREEN": "0xff1f7a3a", "YELLOW": "0xff8a6d00"]

    // "#7aa2f7" -> "0xff7aa2f7", the 0xAARRGGBB spelling the bar and the
    // ring parse. barRoles returns the bare hex; both spellings are accepted.
    static func argb(_ hex: String) -> String {
        "0xff" + (hex.hasPrefix("#") ? hex.dropFirst() : Substring(hex))
    }

    // The plan's revision hash: palette, extended colours, resolved mode (it
    // picks the semantic trio), the adjustments and curve (the render
    // recipe), media, blur, edited flag and the app overrides. `name` is
    // deliberately absent: renaming an edition must not repaint the desktop.
    static func revision(of theme: Theme) -> String {
        var parts: [String] = []
        parts.append(theme.palette.colors.joined(separator: ","))
        let ext = theme.palette.extended
        parts.append([ext.accent, ext.cursor, ext.selectionForeground, ext.selectionBackground]
            .joined(separator: ","))
        parts.append(theme.palette.resolvedMode)
        let a = theme.palette.adjustments
        parts.append([a.vibrance, a.saturation, a.contrast, a.brightness, a.shadows,
                      a.highlights, a.hueShift, a.temperature, a.tint, a.blackPoint,
                      a.whitePoint, a.gamma].map { "\($0)" }.joined(separator: ","))
        parts.append(theme.palette.curve.map { "\($0[0]),\($0[1])" }.joined(separator: ";"))
        parts.append(theme.wallpaper.media ?? "")
        parts.append(theme.wallpaper.blur ? "1" : "0")
        parts.append(theme.wallpaper.edited ? "1" : "0")
        for app in theme.appOverrides.keys.sorted() {
            let roles = theme.appOverrides[app]!
            parts.append(app + ":" + roles.keys.sorted().map { "\($0)=\(roles[$0]!)" }.joined(separator: ","))
        }
        let digest = SHA256.hash(data: Data(parts.joined(separator: "|").utf8))
        return String(digest.map { String(format: "%02x", $0) }.joined().prefix(12))
    }

    // The edition's own image: the snapshot in theme-media when it is still
    // there, the recorded provenance path as the fallback. When media is an
    // edited render, that render is what the directory must show.
    static func liveImage(of theme: Theme, library: ThemeLibrary) throws -> URL {
        if let media = theme.wallpaper.media, !media.isEmpty, !media.hasPrefix("."),
           media.rangeOfCharacter(from: CharacterSet(charactersIn: "/\\")) == nil {
            let url = library.mediaDir.appendingPathComponent(media)
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        if let path = theme.wallpaper.path, !path.isEmpty {
            let url = URL(fileURLWithPath: Wallpapers.resolved(path))
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        throw ThemeError(message: "theme \"\(theme.id)\" has no image: media \(theme.wallpaper.media ?? "(none)") is missing and \(theme.wallpaper.path ?? "(no path)") does not exist")
    }

    static func materialize(_ theme: Theme, library: ThemeLibrary) throws -> URL {
        let image = try liveImage(of: theme, library: library)
        let rev = revision(of: theme)
        let dir = library.materialisedDir.appendingPathComponent("\(theme.id)-\(rev)")
        // An unchanged theme is already on disk: return the same directory
        // without touching a byte, so the live symlink target does not move.
        if FileManager.default.fileExists(atPath: dir.appendingPathComponent("sketchybar.sh").path) {
            return dir
        }
        try? FileManager.default.createDirectory(at: library.materialisedDir, withIntermediateDirectories: true)
        let tmp = library.materialisedDir
            .appendingPathComponent(".\(theme.id)-\(rev).tmp-\(ProcessInfo.processInfo.processIdentifier)")
        try? FileManager.default.removeItem(at: tmp)
        do {
            try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
            try writeArtifacts(theme, image: image, to: tmp)
            if FileManager.default.fileExists(atPath: dir.path) {
                // Lost a race against another writer: the winner is complete.
                try? FileManager.default.removeItem(at: tmp)
            } else {
                try FileManager.default.moveItem(at: tmp, to: dir)
            }
        } catch {
            try? FileManager.default.removeItem(at: tmp)
            throw error
        }
        return dir
    }

    static func writeArtifacts(_ theme: Theme, image: URL, to dir: URL) throws {
        // The stored colours are the base palette; the desktop sees them with
        // the 12 adjustments and the curve applied (the record's recipe).
        let rendered = theme.palette.rendered()
        let roles = barRoles(rendered.colors, accent: rendered.extended.accent)
        let sem = theme.palette.resolvedMode == "light" ? semanticLight : semanticDark

        var sb = "#!/usr/bin/env bash\n"
        sb += "# generated by omacosy-themecore from theme \(theme.id)\n"
        sb += "export BAR_BG_SOLID=\(argb(roles.bar))\n"
        sb += "export BAR_COLOR=\(argb(roles.bar))\n"
        sb += "export ITEM_BG=\(argb(roles.pill))\n"
        sb += "export MUTED=\(argb(roles.muted))\n"
        sb += "export LABEL_COLOR=\(argb(roles.label))\n"
        sb += "export ICON_COLOR=\(argb(roles.label))\n"
        sb += "export ACCENT=\(argb(roles.accent))\n"
        for key in ["RED", "GREEN", "YELLOW"] { sb += "export \(key)=\(sem[key]!)\n" }

        var bd = "#!/usr/bin/env bash\n"
        bd += "# generated by omacosy-themecore from theme \(theme.id)\n"
        bd += "export ACTIVE_COLOR=\(argb(roles.ring))\n"
        bd += "export INACTIVE_COLOR=\(argb(roles.pill))\n"

        let ext = rendered.extended
        var toml = ""
        toml += "accent = \"\(ext.accent)\"\n"
        toml += "cursor = \"\(ext.cursor)\"\n"
        toml += "foreground = \"\(rendered.colors[7])\"\n"
        toml += "background = \"\(rendered.colors[0])\"\n"
        toml += "selection_foreground = \"\(ext.selectionForeground)\"\n"
        toml += "selection_background = \"\(ext.selectionBackground)\"\n"
        for i in 0..<16 { toml += "color\(i) = \"\(rendered.colors[i])\"\n" }

        try sb.write(to: dir.appendingPathComponent("sketchybar.sh"), atomically: true, encoding: .utf8)
        try bd.write(to: dir.appendingPathComponent("borders.sh"), atomically: true, encoding: .utf8)
        try toml.write(to: dir.appendingPathComponent("colors.toml"), atomically: true, encoding: .utf8)

        let backgroundDir = dir.appendingPathComponent("backgrounds", isDirectory: true)
        try FileManager.default.createDirectory(at: backgroundDir, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: backgroundDir.appendingPathComponent(image.lastPathComponent), withDestinationURL: image)

        try writeThumbnail(from: image, to: dir.appendingPathComponent("preview.png"))
    }

    // A small PNG for the Themes tab, written without decoding the full
    // picture: ImageIO hands back a downsampled thumbnail.
    static func writeThumbnail(from image: URL, to dest: URL, maxPixel: Int = 640) throws {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let src = CGImageSourceCreateWithURL(image as CFURL, nil),
              let thumb = CGImageSourceCreateThumbnailAtIndex(src, 0, options as CFDictionary),
              let out = CGImageDestinationCreateWithURL(dest as CFURL, "public.png" as CFString, 1, nil) else {
            throw ThemeError(message: "cannot make a preview of \(image.path)")
        }
        CGImageDestinationAddImage(out, thumb, nil)
        guard CGImageDestinationFinalize(out) else {
            throw ThemeError(message: "cannot write \(dest.path)")
        }
    }
}

// Loads a theme by library id, or from a JSON file when the argument is a
// path instead. `theme materialize` and `theme wallpaper` accept either.
func loadThemeArgument(_ raw: String, library: ThemeLibrary) throws -> Theme {
    if library.exists(id: raw) { return try library.load(id: raw) }
    let path = Wallpapers.resolved(raw)
    guard FileManager.default.fileExists(atPath: path) else {
        throw ThemeError(message: "no theme \"\(raw)\" in \(library.dir.path), and no such file: \(path)")
    }
    return try library.load(url: URL(fileURLWithPath: path))
}

// MARK: - Wallpaper files

enum Wallpapers {
    static let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "webp", "heic", "gif"]

    static var home: String { FileManager.default.homeDirectoryForCurrentUser.path }
    static var configDir: String {
        ProcessInfo.processInfo.environment["OMACOSY_CONFIG_DIR"] ?? "\(home)/.config/omacosy"
    }
    static var stateDir: String {
        ProcessInfo.processInfo.environment["OMACOSY_STATE_DIR"] ?? "\(home)/.local/state/omacosy"
    }
    static var derivedDir: String { "\(stateDir)/derived" }

    static func expand(_ raw: String) -> String {
        var s = raw
        if s.hasPrefix("~") { s = home + s.dropFirst() }
        s = s.replacingOccurrences(of: "$HOME", with: home)
        return s
    }

    static func resolved(_ raw: String) -> String {
        let expanded = expand(raw)
        let absolute = expanded.hasPrefix("/") ? expanded
            : FileManager.default.currentDirectoryPath + "/" + expanded
        return URL(fileURLWithPath: absolute).resolvingSymlinksInPath().path
    }

    // The same rule as omacosy-custom-theme: custom_wallpapers in
    // themes.conf (last line wins), else ~/Pictures/wallpapers.
    static func configuredDir() -> String {
        let fallback = "\(home)/Pictures/wallpapers"
        guard let text = try? String(contentsOfFile: "\(configDir)/themes.conf", encoding: .utf8) else {
            return fallback
        }
        var value: String?
        for line in text.components(separatedBy: "\n") {
            guard let eq = line.firstIndex(of: "=") else { continue }
            guard line[..<eq].trimmingCharacters(in: .whitespaces) == "custom_wallpapers" else { continue }
            let v = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
            if !v.isEmpty { value = v }
        }
        return value.map(expand) ?? fallback
    }

    static func list(dir: String) throws -> [(name: String, path: String)] {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: dir, isDirectory: &isDir) else {
            throw ThemeError(message: "wallpaper directory does not exist: \(dir)")
        }
        guard isDir.boolValue else { throw ThemeError(message: "not a directory: \(dir)") }
        guard let names = try? fm.contentsOfDirectory(atPath: dir) else {
            throw ThemeError(message: "cannot read \(dir)")
        }
        var out: [(name: String, path: String)] = []
        for name in names {
            guard imageExtensions.contains((name as NSString).pathExtension.lowercased()) else { continue }
            let path = (dir as NSString).appendingPathComponent(name)
            var entryIsDir: ObjCBool = false
            guard fm.fileExists(atPath: path, isDirectory: &entryIsDir), !entryIsDir.boolValue else { continue }
            out.append((name, path))
        }
        return out.sorted { $0.path < $1.path }
    }

    // Ported from Aether's wallpaper/local.go ScanDirectory: recursive,
    // hidden directories and symlinked directories skipped, files in
    // subfolders named by their path relative to the root.
    struct ScannedWallpaper {
        var path: String
        var name: String
        var size: Int64
        var modTime: Int64
        var key: String
    }

    static func scan(dir: String) -> [ScannedWallpaper] {
        let fm = FileManager.default
        let root = resolved(dir)
        let prefix = root.hasSuffix("/") ? root : root + "/"
        var out: [ScannedWallpaper] = []

        func walk(_ directory: String) {
            guard let names = try? fm.contentsOfDirectory(atPath: directory) else { return }
            for name in names.sorted() {
                let path = (directory as NSString).appendingPathComponent(name)
                if (try? fm.destinationOfSymbolicLink(atPath: path)) != nil { continue }
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: path, isDirectory: &isDir) else { continue }
                if isDir.boolValue {
                    if name.hasPrefix(".") { continue }
                    walk(path)
                    continue
                }
                guard imageExtensions.contains((name as NSString).pathExtension.lowercased()) else { continue }
                let attrs = try? fm.attributesOfItem(atPath: path)
                let size = (attrs?[.size] as? NSNumber)?.int64Value ?? 0
                let modTime = Int64((attrs?[.modificationDate] as? Date ?? Date(timeIntervalSince1970: 0))
                    .timeIntervalSince1970)
                let rel = path.hasPrefix(prefix) ? String(path.dropFirst(prefix.count)) : name
                out.append(ScannedWallpaper(path: path, name: rel, size: size,
                                            modTime: modTime, key: derivedKey(for: path)))
            }
        }
        walk(root)
        return out
    }

    // Must equal omacosy-custom-theme's key: first 16 hex of SHA-1(path).
    static func derivedKey(for path: String) -> String {
        let digest = Insecure.SHA1.hash(data: Data(path.utf8))
        return digest.prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    static func pixelSize(_ path: String) -> (width: Int, height: Int)? {
        guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = props[kCGImagePropertyPixelWidth] as? Int,
              let height = props[kCGImagePropertyPixelHeight] as? Int else { return nil }
        return (width, height)
    }

    struct RenameOutcome {
        var oldPath: String
        var newPath: String
        var indexUpdated = false
        var confUpdated = false
        var derivedMoved = false
        var themeIDs: [String] = []
        var warnings: [String] = []
    }

    // One step, every reference: the file, custom-index, day/night specs, the
    // derived cache (re-keyed, backgrounds relinked) and edition provenance.
    static func rename(old rawOld: String, new rawNew: String) throws -> RenameOutcome {
        let fm = FileManager.default
        let oldPath = resolved(rawOld)
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: oldPath, isDirectory: &isDir), !isDir.boolValue else {
            throw ThemeError(message: "no such wallpaper: \(oldPath)")
        }
        let newPath: String
        if rawNew.contains("/") || rawNew.hasPrefix("~") || rawNew.contains("$HOME") {
            newPath = resolved(rawNew)
        } else {
            newPath = ((oldPath as NSString).deletingLastPathComponent as NSString)
                .appendingPathComponent(rawNew)
        }
        var outcome = RenameOutcome(oldPath: oldPath, newPath: newPath)
        if newPath == oldPath { return outcome }

        guard imageExtensions.contains((newPath as NSString).pathExtension.lowercased()) else {
            throw ThemeError(message: "the new name must keep an image extension (jpg, jpeg, png, webp, heic, gif)")
        }
        guard !fm.fileExists(atPath: newPath) else {
            throw ThemeError(message: "destination already exists: \(newPath)")
        }
        let newParent = (newPath as NSString).deletingLastPathComponent
        guard fm.fileExists(atPath: newParent, isDirectory: &isDir), isDir.boolValue else {
            throw ThemeError(message: "destination directory does not exist: \(newParent)")
        }
        do { try fm.moveItem(atPath: oldPath, toPath: newPath) }
        catch { throw ThemeError(message: "cannot move \(oldPath): \(error.localizedDescription)") }

        let indexURL = URL(fileURLWithPath: "\(stateDir)/custom-index")
        if let text = try? String(contentsOf: indexURL, encoding: .utf8),
           resolved(text.trimmingCharacters(in: .whitespacesAndNewlines)) == oldPath {
            do {
                try Data((newPath + "\n").utf8).write(to: indexURL)
                outcome.indexUpdated = true
            } catch {
                outcome.warnings.append("could not update \(indexURL.path)")
            }
        }

        let confURL = URL(fileURLWithPath: "\(configDir)/themes.conf")
        if fm.fileExists(atPath: confURL.path) {
            do { outcome.confUpdated = try updateSpecs(at: confURL, oldPath: oldPath, newPath: newPath) }
            catch let e as ThemeError { outcome.warnings.append(e.message) }
        }

        let oldDerived = "\(derivedDir)/\(derivedKey(for: oldPath))"
        let newDerived = "\(derivedDir)/\(derivedKey(for: newPath))"
        var derivedIsDir: ObjCBool = false
        if fm.fileExists(atPath: oldDerived, isDirectory: &derivedIsDir), derivedIsDir.boolValue {
            if fm.fileExists(atPath: newDerived) {
                // the new path already has a current cache: drop the stale one
                try? fm.removeItem(atPath: oldDerived)
            } else {
                try? fm.moveItem(atPath: oldDerived, toPath: newDerived)
            }
            rebuildBackgrounds(derived: newDerived, wallpaper: newPath)
            outcome.derivedMoved = true
        }

        let library = ThemeLibrary()
        var warnings: [String] = []
        for var theme in library.loadAll(warnings: &warnings) {
            guard let recorded = theme.wallpaper.path, resolved(recorded) == oldPath else { continue }
            theme.wallpaper.path = newPath
            theme.updated = isoNow()
            do {
                try library.write(theme)
                outcome.themeIDs.append(theme.id)
            } catch let e as ThemeError {
                outcome.warnings.append(e.message)
            }
        }
        outcome.warnings.append(contentsOf: warnings)
        return outcome
    }

    static func rebuildBackgrounds(derived: String, wallpaper: String) {
        let fm = FileManager.default
        let backgrounds = (derived as NSString).appendingPathComponent("backgrounds")
        if let items = try? fm.contentsOfDirectory(atPath: backgrounds) {
            for item in items {
                try? fm.removeItem(atPath: (backgrounds as NSString).appendingPathComponent(item))
            }
        }
        try? fm.createDirectory(atPath: backgrounds, withIntermediateDirectories: true)
        let link = (backgrounds as NSString).appendingPathComponent((wallpaper as NSString).lastPathComponent)
        try? fm.createSymbolicLink(atPath: link, withDestinationPath: wallpaper)
    }

    // day=/night= values say: "gruvbox", "gruvbox/2-flower.webp", a bare
    // filename in the custom folder, or an absolute path. Only the last two
    // can be this file; everything else is left byte-for-byte.
    static func updateSpecs(at url: URL, oldPath: String, newPath: String) throws -> Bool {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return false }
        let hadTrailingNewline = text.hasSuffix("\n")
        var lines = text.components(separatedBy: "\n")
        if hadTrailingNewline { lines.removeLast() }
        let wallpaperDir = resolved(configuredDir())
        let oldName = (oldPath as NSString).lastPathComponent
        let newName = (newPath as NSString).lastPathComponent
        let oldParent = (oldPath as NSString).deletingLastPathComponent
        let newParent = (newPath as NSString).deletingLastPathComponent
        var changed = false
        for (i, line) in lines.enumerated() {
            guard let eq = line.firstIndex(of: "=") else { continue }
            let key = line[..<eq].trimmingCharacters(in: .whitespaces)
            guard key == "day" || key == "night" else { continue }
            let value = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
            let replacement: String?
            if value.hasPrefix("/") || value.hasPrefix("~") || value.hasPrefix("$HOME") {
                replacement = resolved(value) == oldPath ? newPath : nil
            } else if value.contains("/") {
                replacement = nil                       // <stock theme>/<wallpaper>
            } else if oldParent == wallpaperDir && value == oldName {
                replacement = newParent == wallpaperDir ? newName : newPath
            } else {
                replacement = nil
            }
            if let replacement {
                lines[i] = "\(key)=\(replacement)"
                changed = true
            }
        }
        guard changed else { return false }
        var out = lines.joined(separator: "\n")
        if hadTrailingNewline { out += "\n" }
        do { try Data(out.utf8).write(to: url) }
        catch { throw ThemeError(message: "cannot update \(url.path): \(error.localizedDescription)") }
        return true
    }

    struct TrashOutcome {
        var path: String
        var trashedTo: String
        var derivedRemoved = false
        var indexCleared = false
    }

    static func trash(_ rawPath: String) throws -> TrashOutcome {
        let fm = FileManager.default
        let path = resolved(rawPath)
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: path, isDirectory: &isDir), !isDir.boolValue else {
            throw ThemeError(message: "no such wallpaper: \(path)")
        }
        var resulting: NSURL?
        do { try fm.trashItem(at: URL(fileURLWithPath: path), resultingItemURL: &resulting) }
        catch { throw ThemeError(message: "cannot move \(path) to Trash: \(error.localizedDescription)") }
        var outcome = TrashOutcome(path: path, trashedTo: resulting?.path ?? "Trash")

        let derived = "\(derivedDir)/\(derivedKey(for: path))"
        if fm.fileExists(atPath: derived) {
            try? fm.removeItem(atPath: derived)
            outcome.derivedRemoved = true
        }
        let indexURL = URL(fileURLWithPath: "\(stateDir)/custom-index")
        if let text = try? String(contentsOf: indexURL, encoding: .utf8),
           resolved(text.trimmingCharacters(in: .whitespacesAndNewlines)) == path {
            try? fm.removeItem(at: indexURL)
            outcome.indexCleared = true
        }
        return outcome
    }
}

func fileSize(_ path: String) -> Int? {
    guard let attrs = try? FileManager.default.attributesOfItem(atPath: path) else { return nil }
    return (attrs[.size] as? NSNumber)?.intValue
}

func humanSize(_ bytes: Int) -> String {
    if bytes >= 1_048_576 { return String(format: "%.1f MB", Double(bytes) / 1_048_576) }
    if bytes >= 1024 { return String(format: "%.0f KB", Double(bytes) / 1024) }
    return "\(bytes) B"
}

func padded(_ value: String, _ width: Int) -> String {
    value + String(repeating: " ", count: max(0, width - value.count))
}

func themeError(_ error: Error) -> Never {
    if let e = error as? ThemeError { fail(e.message) }
    fail("\(error)")
}

// MARK: - CLI

let themecoreVersion = "0.6.0"

func fail(_ message: String) -> Never {
    FileHandle.standardError.write("omacosy-themecore: \(message)\n".data(using: .utf8)!)
    exit(1)
}

func warn(_ message: String) {
    FileHandle.standardError.write("omacosy-themecore: warning: \(message)\n".data(using: .utf8)!)
}

func usage() -> Never {
    FileHandle.standardError.write("""
    usage: omacosy-themecore color convert <hex> [--to rgb|hsl|oklab|oklch] [--json]
           omacosy-themecore color contrast <a> <b> [--json]
           omacosy-themecore color adjust <hex> [--vibrance N] [--saturation N] [--contrast N]
                                          [--brightness N] [--shadows N] [--highlights N]
                                          [--hue-shift N] [--temperature N] [--tint N]
                                          [--black-point N] [--white-point N] [--gamma N] [--json]
           omacosy-themecore color darken <hex> <percent> [--json]
           omacosy-themecore color lighten <hex> <percent> [--json]
           omacosy-themecore color gradient <start> <end> [--steps N] [--json]
           omacosy-themecore color from-color <hex> [--json]
           omacosy-themecore curve lut --points "x,y;x,y" [--json]
           omacosy-themecore presets [--json]
           omacosy-themecore modes [--json]
           omacosy-themecore theme list [--json]
           omacosy-themecore theme show <id> [--json]
           omacosy-themecore theme save [<file>|-] [--id ID] [--name NAME] [--replace] [--json]
           omacosy-themecore theme delete <id> [--json]
           omacosy-themecore theme rename <id> <new name> [--json]
           omacosy-themecore theme duplicate <id> [--id ID] [--name NAME] [--json]
           omacosy-themecore theme import <file> [--id ID] [--name NAME] [--replace|--rename] [--json]
           omacosy-themecore theme export <id> [--out PATH] [--json]
           omacosy-themecore theme materialize <id|file.json> [--wallpaper IMAGE] [--json]
           omacosy-themecore theme wallpaper <id|file.json> [--source] [--json]
           omacosy-themecore wallpaper list [--dir DIR] [--json]
           omacosy-themecore wallpaper scan [--dir DIR] [--json]
           omacosy-themecore wallpaper info <path> [--json]
           omacosy-themecore wallpaper rename <old> <new> [--json]
           omacosy-themecore wallpaper trash <path> [--json]
           omacosy-themecore palette extract <image> [--mode ID] [--light] [--no-cache] [--json]
           omacosy-themecore palette generate --colors CSV [--counts CSV|--weights CSV]
                                           [--mode ID] [--light] [--normalize] [--json]
           omacosy-themecore palette magic <image> [--roles] [--no-cache] [--json]
           omacosy-themecore palette roles --colors CSV [--accent HEX] [--json]
           omacosy-themecore palette roles --image PATH [--mode ID] [--light] [--json]
           omacosy-themecore palette render --colors CSV [--accent HEX] [--cursor HEX]
                                           [--selection-foreground HEX] [--selection-background HEX]
                                           [12 adjustment flags] [--curve "x,y;x,y"] [--json]
           omacosy-themecore palette suggest-mode <image> [--json]
           omacosy-themecore palette quantize --pixels-file PATH [--count N] [--json]
           omacosy-themecore palette analyze <op> ...
           omacosy-themecore image info <path> [--json]
           omacosy-themecore image histogram <path> [--json]
           omacosy-themecore version [--json]

    """.data(using: .utf8)!)
    exit(2)
}

func printJSON(_ object: Any) -> Never {
    do {
        let data = try JSONSerialization.data(withJSONObject: object,
                                              options: [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes])
        print(String(data: data, encoding: .utf8)!)
        exit(0)
    } catch {
        fail("could not encode JSON: \(error.localizedDescription)")
    }
}

var args = Array(CommandLine.arguments.dropFirst())

func takeFlag(_ name: String) -> String? {
    guard let i = args.firstIndex(of: name) else { return nil }
    guard i + 1 < args.count else { fail("\(name) needs a value") }
    let value = args[i + 1]
    args.removeSubrange(i...(i + 1))
    return value
}

func takeBool(_ name: String) -> Bool {
    guard let i = args.firstIndex(of: name) else { return false }
    args.remove(at: i)
    return true
}

func takeNumber(_ name: String) -> Double? {
    guard let raw = takeFlag(name) else { return nil }
    guard let value = Double(raw) else { fail("\(name): not a number: \(raw)") }
    return value
}

func normalizedHex(_ raw: String) -> String {
    var s = raw.trimmingCharacters(in: .whitespaces)
    if !s.hasPrefix("#") { s = "#" + s }
    guard ColorMath.hexUInt32(s) != nil else {
        fail("invalid hex colour \"\(raw)\" (expected #rrggbb)")
    }
    return s
}

func hexArgument(_ label: String) -> String {
    guard let raw = args.first else { usage() }
    args.removeFirst()
    return normalizedHex(raw)
}

func hexListArgument(_ raw: String) -> [String] {
    let parts = raw.split(separator: ",").map { normalizedHex(String($0)) }
    if parts.isEmpty { fail("empty colour list") }
    return parts
}

func intListArgument(_ raw: String) -> [Int] {
    let parts = raw.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
    if parts.isEmpty { fail("empty number list") }
    return parts.map {
        guard let n = Int($0) else { fail("not a whole number: \($0)") }
        return n
    }
}

func doubleListArgument(_ raw: String) -> [Double] {
    let parts = raw.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
    if parts.isEmpty { fail("empty number list") }
    return parts.map {
        guard let n = Double($0) else { fail("not a number: \($0)") }
        return n
    }
}

// The 12 adjustment flags, shared by `color adjust` and `palette render`.
func takeAdjustments() -> Adjustments {
    var a = Adjustments()
    if let v = takeNumber("--vibrance") { a.vibrance = v }
    if let v = takeNumber("--saturation") { a.saturation = v }
    if let v = takeNumber("--contrast") { a.contrast = v }
    if let v = takeNumber("--brightness") { a.brightness = v }
    if let v = takeNumber("--shadows") { a.shadows = v }
    if let v = takeNumber("--highlights") { a.highlights = v }
    if let v = takeNumber("--hue-shift") { a.hueShift = v }
    if let v = takeNumber("--temperature") { a.temperature = v }
    if let v = takeNumber("--tint") { a.tint = v }
    if let v = takeNumber("--black-point") { a.blackPoint = v }
    if let v = takeNumber("--white-point") { a.whitePoint = v }
    if let v = takeNumber("--gamma") { a.gamma = v }
    return a
}

// "x,y;x,y"; empty means no curve. Same validation as the record parser:
// values inside 0...1, x strictly increasing.
func curvePointsArgument(_ raw: String) -> [[Double]] {
    let trimmed = raw.trimmingCharacters(in: .whitespaces)
    if trimmed.isEmpty { return [] }
    var out: [[Double]] = []
    for pair in trimmed.split(separator: ";") {
        let parts = pair.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2, let x = Double(parts[0]), let y = Double(parts[1]),
              x >= 0, x <= 1, y >= 0, y <= 1 else {
            fail("--curve must be \"x,y;x,y\" with values inside 0...1")
        }
        if let last = out.last, x <= last[0] {
            fail("--curve x values must strictly increase")
        }
        out.append([x, y])
    }
    return out
}

func noExtraArguments() {
    if !args.isEmpty { usage() }
}

let jsonOut = takeBool("--json")

guard let verb = args.first else { usage() }
args.removeFirst()

switch verb {
case "version":
    if jsonOut {
        printJSON(["name": "omacosy-themecore", "version": themecoreVersion])
    }
    print("omacosy-themecore \(themecoreVersion)")
    exit(0)

case "color":
    guard let sub = args.first else { usage() }
    args.removeFirst()

    switch sub {
    case "convert":
        let hex = hexArgument("hex")
        let target = takeFlag("--to") ?? "rgb"
        noExtraArguments()
        switch target {
        case "rgb":
            let c = ColorMath.rgb(fromHex: hex)
            if jsonOut {
                printJSON(["input": hex, "format": "rgb", "r": c.r, "g": c.g, "b": c.b,
                           "string": "rgb(\(ColorMath.clampByte(c.r)),\(ColorMath.clampByte(c.g)),\(ColorMath.clampByte(c.b)))"])
            }
            print("rgb(\(ColorMath.clampByte(c.r)),\(ColorMath.clampByte(c.g)),\(ColorMath.clampByte(c.b)))")
        case "hsl":
            let c = ColorMath.hsl(fromHex: hex)
            if jsonOut { printJSON(["input": hex, "format": "hsl", "h": c.h, "s": c.s, "l": c.l]) }
            print(String(format: "hsl(%.1f, %.1f%%, %.1f%%)", c.h, c.s, c.l))
        case "oklab":
            let c = ColorMath.oklab(fromHex: hex)
            if jsonOut { printJSON(["input": hex, "format": "oklab", "l": c.l, "a": c.a, "b": c.b]) }
            print(String(format: "oklab(%.4f, %.4f, %.4f)", c.l, c.a, c.b))
        case "oklch":
            let c = ColorMath.oklch(fromHex: hex)
            if jsonOut { printJSON(["input": hex, "format": "oklch", "l": c.l, "c": c.c, "h": c.h]) }
            print(String(format: "oklch(%.4f, %.4f, %.1f)", c.l, c.c, c.h))
        default:
            fail("unknown format: \(target) (valid: rgb, hsl, oklab, oklch)")
        }
        exit(0)

    case "contrast":
        guard args.count == 2 else { usage() }
        let a = normalizedHex(args[0]), b = normalizedHex(args[1])
        let ratio = ColorMath.contrastRatio(a, b)
        let aaLarge = ratio >= 3.0, aa = ratio >= 4.5, aaaLarge = ratio >= 4.5, aaa = ratio >= 7.0
        if jsonOut {
            printJSON(["color1": a, "color2": b, "ratio": ratio,
                       "wcag": ["aa_large": aaLarge, "aa": aa, "aaa_large": aaaLarge, "aaa": aaa]])
        }
        print(String(format: "Contrast ratio: %.2f:1", ratio))
        print("  AA large text:  \(aaLarge ? "PASS" : "FAIL")")
        print("  AA normal text: \(aa ? "PASS" : "FAIL")")
        print("  AAA large text: \(aaaLarge ? "PASS" : "FAIL")")
        print("  AAA normal text: \(aaa ? "PASS" : "FAIL")")
        exit(0)

    case "adjust":
        let a = takeAdjustments()
        let hex = hexArgument("hex")
        noExtraArguments()
        let out = adjustColor(hex, a)
        if jsonOut { printJSON(["input": hex, "output": out]) }
        print(out)
        exit(0)

    case "darken", "lighten":
        let hex = hexArgument("hex")
        guard let raw = args.first else { usage() }
        args.removeFirst()
        guard let percent = Double(raw) else { fail("percent: not a number: \(raw)") }
        noExtraArguments()
        let out = sub == "darken" ? ColorMath.darkened(hex, percent)
                                  : ColorMath.lightened(hex, percent)
        if jsonOut { printJSON(["input": hex, "percent": percent, "output": out]) }
        print(out)
        exit(0)

    case "gradient":
        guard args.count >= 2 else { usage() }
        let start = normalizedHex(args[0]), end = normalizedHex(args[1])
        args.removeFirst(2)
        var steps = 16
        if let raw = takeFlag("--steps") {
            guard let n = Int(raw), n >= 2, n <= 256 else {
                fail("--steps must be a whole number between 2 and 256")
            }
            steps = n
        }
        noExtraArguments()
        let colors = ColorMath.gradient(from: start, to: end, steps: steps)
        if jsonOut { printJSON(["start": start, "end": end, "steps": steps, "colors": colors]) }
        colors.forEach { print($0) }
        exit(0)

    case "from-color":
        let hex = hexArgument("hex")
        noExtraArguments()
        let colors = ColorMath.paletteFromColor(hex)
        if jsonOut { printJSON(["input": hex, "colors": colors]) }
        colors.forEach { print($0) }
        exit(0)

    case "roundtrip":
        let hex = hexArgument("hex")
        noExtraArguments()
        let oklabHex = ColorMath.hex(fromOKLab: ColorMath.oklab(fromHex: hex))
        let oklchHex = ColorMath.hex(fromOKLCH: ColorMath.oklch(fromHex: hex))
        let hslHex = ColorMath.hex(fromHSL: ColorMath.hsl(fromHex: hex))
        if jsonOut { printJSON(["input": hex, "oklab": oklabHex, "oklch": oklchHex, "hsl": hslHex]) }
        print(oklabHex); print(oklchHex); print(hslHex)
        exit(0)

    default:
        usage()
    }

case "curve":
    guard let sub = args.first else { usage() }
    args.removeFirst()

    switch sub {
    case "lut":
        let points = curvePointsArgument(takeFlag("--points") ?? "")
        noExtraArguments()
        let lut = ToneCurve.lut(points) ?? ToneCurve.identity
        if jsonOut { printJSON(["lut": lut.map { Int($0) }]) }
        lut.forEach { print($0) }
        exit(0)

    default:
        usage()
    }

case "presets":
    noExtraArguments()
    if jsonOut {
        printJSON(Presets.all.map { ["name": $0.name, "mode": $0.mode, "colors": $0.colors] })
    }
    for preset in Presets.all { print(preset.name) }
    exit(0)

case "modes":
    noExtraArguments()
    if jsonOut {
        let groups: [[String: Any]] = Modes.groups.map { group in
            [
                "id": group.id,
                "label": group.label,
                "defaultOpen": group.defaultOpen,
                "modes": Modes.all.filter { $0.group == group.id }.map {
                    ["value": $0.value, "label": $0.label, "description": $0.description]
                },
            ]
        }
        printJSON(["count": Modes.all.count, "default": Modes.defaultMode, "groups": groups])
    }
    print("\(Modes.defaultMode) (the default; Omacosy's bridge, built in Phase 2)")
    for group in Modes.groups {
        print(group.label)
        for mode in Modes.all where mode.group == group.id {
            print("  \(padded(mode.value, 22))  \(mode.label)")
        }
    }
    exit(0)

case "theme":
    guard let sub = args.first else { usage() }
    args.removeFirst()
    let library = ThemeLibrary()

    switch sub {
    case "list":
        noExtraArguments()
        var warnings: [String] = []
        let themes = library.loadAll(warnings: &warnings)
        for warning in warnings { warn(warning) }
        if jsonOut { printJSON(themes.map { $0.canonicalObject() }) }
        let idWidth = themes.map { $0.id.count }.max() ?? 0
        for theme in themes {
            var flags: [String] = []
            if theme.primary { flags.append("primary") }
            if theme.favorite { flags.append("favorite") }
            let suffix = flags.isEmpty ? "" : "  (\(flags.joined(separator: ", ")))"
            print(padded(theme.id, idWidth) + "  " + theme.name + suffix)
        }
        exit(0)

    case "show":
        do {
            guard let id = args.first else { throw ThemeError(message: "theme show needs an id") }
            args.removeFirst()
            noExtraArguments()
            let theme = try library.load(id: id)
            FileHandle.standardOutput.write(try theme.canonicalData())
            exit(0)
        } catch { themeError(error) }

    case "materialize":
        do {
            let wallpaperFlag = takeFlag("--wallpaper")
            let raw = args.first
            if raw != nil { args.removeFirst() }
            noExtraArguments()
            let theme: Theme
            if let path = wallpaperFlag {
                // The routing query omacosy-custom-theme asks: the primary
                // edition for a wallpaper, or the earliest remaining one as
                // the defensive fallback when no primary is flagged.
                // Both sides resolve through symlinks so a /tmp spelling and
                // a /private/tmp spelling of one file still match.
                let resolved = URL(fileURLWithPath: Wallpapers.resolved(path))
                    .resolvingSymlinksInPath().path
                var warnings: [String] = []
                let group = library.loadAll(warnings: &warnings).filter { theme in
                    guard let recorded = theme.wallpaper.path else { return false }
                    return URL(fileURLWithPath: Wallpapers.resolved(recorded))
                        .resolvingSymlinksInPath().path == resolved
                }
                for warning in warnings { warn(warning) }
                let pick = group.first(where: { $0.primary })
                    ?? group.sorted { ($0.created ?? "", $0.id) < ($1.created ?? "", $1.id) }.first
                guard let found = pick else {
                    throw ThemeError(message: "no theme is recorded for \(resolved)")
                }
                theme = found
            } else if let raw {
                theme = try loadThemeArgument(raw, library: library)
            } else {
                throw ThemeError(message: "theme materialize needs an id, a JSON file or --wallpaper <image>")
            }
            let image = try Materialise.liveImage(of: theme, library: library)
            let dir = try Materialise.materialize(theme, library: library)
            let dirPath = dir.path
            if jsonOut {
                let payload: [String: Any] = ["id": theme.id, "dir": dirPath,
                                              "rev": Materialise.revision(of: theme),
                                              "wallpaper": image.path,
                                              "source": theme.wallpaper.path ?? NSNull()]
                printJSON(payload)
            }
            print(dirPath)
            exit(0)
        } catch { themeError(error) }

    case "wallpaper":
        do {
            let sourceFlag = takeBool("--source")
            guard let raw = args.first else {
                throw ThemeError(message: "theme wallpaper needs an id or a JSON file")
            }
            args.removeFirst()
            noExtraArguments()
            let theme = try loadThemeArgument(raw, library: library)
            if sourceFlag {
                guard let path = theme.wallpaper.path, !path.isEmpty else {
                    throw ThemeError(message: "theme \"\(theme.id)\" records no source path")
                }
                print(Wallpapers.resolved(path))
                exit(0)
            }
            let image = try Materialise.liveImage(of: theme, library: library)
            if jsonOut {
                let payload: [String: Any] = ["id": theme.id, "path": image.path,
                                              "source": theme.wallpaper.path ?? NSNull()]
                printJSON(payload)
            }
            print(image.path)
            exit(0)
        } catch { themeError(error) }

    case "save":
        do {
            let idFlag = takeFlag("--id")
            let nameFlag = takeFlag("--name")
            let replace = takeBool("--replace")
            let input = args.first
            if input != nil { args.removeFirst() }
            noExtraArguments()

            let data: Data
            let label: String
            if let input, input != "-" {
                let path = Wallpapers.resolved(input)
                guard let contents = FileManager.default.contents(atPath: path) else {
                    throw ThemeError(message: "cannot read \(path)")
                }
                data = contents
                label = (path as NSString).lastPathComponent
            } else {
                data = FileHandle.standardInput.readDataToEndOfFile()
                label = "stdin"
            }
            var top = try jsonTopLevel(data, label: label)
            let hadID = top["id"] != nil || idFlag != nil
            if let idFlag { top["id"] = idFlag }
            if let nameFlag { top["name"] = nameFlag }
            if top["id"] == nil {
                guard let name = JSONField.string(top["name"]), !name.isEmpty else {
                    throw ThemeError(message: "\(label): needs \"id\" or a \"name\" to derive one from")
                }
                top["id"] = slugify(name)
            }
            var theme = try Theme.parse(top, label: label)
            // First save captures the source into the edition's own image
            // store (content-addressed, shared between editions). A source
            // that no longer exists is left alone; an unreadable one fails.
            if theme.wallpaper.media == nil, let path = theme.wallpaper.path, !path.isEmpty {
                let resolved = Wallpapers.resolved(path)
                if FileManager.default.fileExists(atPath: resolved) {
                    theme.wallpaper.media = try library.captureMedia(from: resolved)
                }
            }
            let exists = library.exists(id: theme.id)
            if exists && !hadID && !replace {
                throw ThemeError(message: "theme \"\(theme.id)\" already exists — pass --replace to overwrite it, or --name to save under another name")
            }
            let old = exists ? (try? library.load(id: theme.id)) : nil
            let previousPath = old?.wallpaper.path
            if let existing = old {
                theme.created = existing.created ?? theme.created
                // An unchanged record is not rewritten: Save twice is a
                // no-op, and show -> save round-trips byte for byte.
                if let stored = try? Data(contentsOf: library.fileURL(id: theme.id)),
                   let candidate = try? theme.canonicalData(),
                   stored == candidate {
                    if jsonOut {
                        let payload: [String: Any] = ["saved": true, "id": theme.id, "name": theme.name,
                                                      "primary": existing.primary,
                                                      "path": library.fileURL(id: theme.id).path,
                                                      "unchanged": true]
                        printJSON(payload)
                    }
                    print("saved \(theme.id) (unchanged)")
                    exit(0)
                }
            } else if theme.created == nil {
                theme.created = isoNow()
            }
            theme.updated = isoNow()
            if theme.primary, let path = theme.wallpaper.path {
                var warnings: [String] = []
                for var other in library.loadAll(warnings: &warnings)
                where other.id != theme.id && other.wallpaper.path == path && other.primary {
                    other.primary = false
                    other.updated = isoNow()
                    try library.write(other)
                }
            }
            _ = try library.write(theme)
            if let path = theme.wallpaper.path { try library.normalizePrimary(forPath: path) }
            if let previousPath, previousPath != theme.wallpaper.path {
                // the record moved to another source: keep that source's primary correct too
                try library.normalizePrimary(forPath: previousPath)
            }
            let saved = (try? library.load(id: theme.id)) ?? theme
            if jsonOut {
                printJSON(["saved": true, "id": saved.id, "name": saved.name,
                           "primary": saved.primary, "path": library.fileURL(id: saved.id).path])
            }
            print("saved \(saved.id) (\(library.fileURL(id: saved.id).path))")
            exit(0)
        } catch { themeError(error) }

    case "delete":
        do {
            guard let id = args.first else { throw ThemeError(message: "theme delete needs an id") }
            args.removeFirst()
            noExtraArguments()
            let theme = try library.load(id: id)
            do { try FileManager.default.removeItem(at: library.fileURL(id: id)) }
            catch { throw ThemeError(message: "cannot delete \(library.fileURL(id: id).path): \(error.localizedDescription)") }
            library.pruneUnreferencedMedia(theme.wallpaper.media)
            library.removeMaterialised(id: id)
            var promoted: String?
            if theme.primary, let path = theme.wallpaper.path {
                try library.normalizePrimary(forPath: path)
                var warnings: [String] = []
                promoted = library.loadAll(warnings: &warnings)
                    .first { $0.wallpaper.path == path && $0.primary }?.id
            }
            if jsonOut {
                let payload: [String: Any] = ["deleted": id,
                                              "promoted": promoted ?? NSNull(),
                                              "media": theme.wallpaper.media ?? NSNull()]
                printJSON(payload)
            }
            print("deleted \(id)")
            if let promoted { print("promoted \(promoted) as primary") }
            exit(0)
        } catch { themeError(error) }

    case "rename":
        do {
            guard args.count == 2 else {
                throw ThemeError(message: "theme rename needs <id> and a name")
            }
            let id = args[0], newName = args[1]
            var theme = try library.load(id: id)
            theme.name = newName
            theme.updated = isoNow()
            try library.write(theme)
            if jsonOut { printJSON(["id": id, "name": newName]) }
            print("renamed \(id) to \"\(newName)\"")
            exit(0)
        } catch { themeError(error) }

    case "duplicate":
        do {
            guard let id = args.first else { throw ThemeError(message: "theme duplicate needs an id") }
            args.removeFirst()
            let nameFlag = takeFlag("--name")
            let idFlag = takeFlag("--id")
            noExtraArguments()
            let original = try library.load(id: id)
            var copy = original
            copy.name = nameFlag ?? "\(original.name) Copy"
            let base = idFlag ?? slugify(copy.name)
            guard isThemeID(base) else {
                throw ThemeError(message: "--id must match [a-z0-9-]+")
            }
            copy.id = idFlag ?? library.nextFreeId(base)
            if library.exists(id: copy.id) {
                throw ThemeError(message: "theme \"\(copy.id)\" already exists")
            }
            copy.created = isoNow()
            copy.updated = copy.created
            copy.primary = false
            try library.write(copy)
            if let path = copy.wallpaper.path { try library.normalizePrimary(forPath: path) }
            if jsonOut { printJSON(["duplicated": id, "id": copy.id, "name": copy.name]) }
            print("duplicated \(id) as \(copy.id)")
            exit(0)
        } catch { themeError(error) }

    case "import":
        do {
            guard let file = args.first else { throw ThemeError(message: "theme import needs a file") }
            args.removeFirst()
            let idFlag = takeFlag("--id")
            let nameFlag = takeFlag("--name")
            let replace = takeBool("--replace")
            let renameInstead = takeBool("--rename")
            noExtraArguments()
            if replace && renameInstead {
                throw ThemeError(message: "--replace and --rename cannot be combined")
            }
            let path = file == "-" ? nil : Wallpapers.resolved(file)
            let data: Data
            if let path {
                guard let contents = FileManager.default.contents(atPath: path) else {
                    throw ThemeError(message: "cannot read \(path)")
                }
                data = contents
            } else {
                data = FileHandle.standardInput.readDataToEndOfFile()
            }
            let label = path.map { ($0 as NSString).lastPathComponent } ?? "stdin"
            var top = try jsonTopLevel(data, label: label)
            if let idFlag { top["id"] = idFlag }
            if let nameFlag { top["name"] = nameFlag }
            if top["id"] == nil {
                guard let name = JSONField.string(top["name"]), !name.isEmpty else {
                    throw ThemeError(message: "\(label): needs \"id\" or a \"name\" to derive one from")
                }
                top["id"] = slugify(name)
            }
            var theme = try Theme.parse(top, label: label)
            var replaced: Theme?
            if library.exists(id: theme.id) {
                if replace {
                    replaced = try? library.load(id: theme.id)
                } else if renameInstead {
                    theme.id = library.nextFreeId(theme.id)
                } else {
                    throw ThemeError(message: "theme \"\(theme.id)\" already exists — pass --replace to overwrite it, or --rename to keep both")
                }
            }
            if theme.created == nil { theme.created = isoNow() }
            theme.updated = isoNow()
            try library.write(theme)
            if let path = theme.wallpaper.path { try library.normalizePrimary(forPath: path) }
            if let old = replaced {
                if let oldPath = old.wallpaper.path, oldPath != theme.wallpaper.path {
                    try library.normalizePrimary(forPath: oldPath)
                }
                library.pruneUnreferencedMedia(old.wallpaper.media)
            }
            if jsonOut {
                let payload: [String: Any] = ["imported": true, "id": theme.id, "name": theme.name,
                                              "replaced": replaced?.id ?? NSNull()]
                printJSON(payload)
            }
            print("imported \(theme.id)")
            exit(0)
        } catch { themeError(error) }

    case "export":
        do {
            guard let id = args.first else { throw ThemeError(message: "theme export needs an id") }
            args.removeFirst()
            let out = takeFlag("--out")
            noExtraArguments()
            let theme = try library.load(id: id)
            let data = try theme.canonicalData()
            guard let out else {
                FileHandle.standardOutput.write(data)
                exit(0)
            }
            let target = Wallpapers.resolved(out)
            let parent = (target as NSString).deletingLastPathComponent
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: parent, isDirectory: &isDir), isDir.boolValue else {
                throw ThemeError(message: "no such directory: \(parent)")
            }
            try ThemeLibrary.writeAtomically(data, to: URL(fileURLWithPath: target))
            if jsonOut { printJSON(["id": id, "path": target, "bytes": data.count]) }
            print("exported \(id) to \(target)")
            exit(0)
        } catch { themeError(error) }

    default:
        usage()
    }

case "wallpaper":
    guard let sub = args.first else { usage() }
    args.removeFirst()

    switch sub {
    case "list":
        do {
            let dirFlag = takeFlag("--dir")
            noExtraArguments()
            let dir = dirFlag.map { Wallpapers.resolved($0) } ?? Wallpapers.resolved(Wallpapers.configuredDir())
            let entries = try Wallpapers.list(dir: dir)
            if jsonOut {
                let objects: [[String: Any]] = entries.enumerated().map { index, entry in
                    var obj: [String: Any] = [
                        "index": index + 1,
                        "name": entry.name,
                        "path": entry.path,
                        "key": Wallpapers.derivedKey(for: entry.path),
                    ]
                    if let size = fileSize(entry.path) { obj["bytes"] = size }
                    return obj
                }
                printJSON(objects)
            }
            for (index, entry) in entries.enumerated() {
                let size = fileSize(entry.path).map(humanSize) ?? "-"
                print("\(String(format: "%3d", index + 1))  \(entry.name)  \(size)")
            }
            exit(0)
        } catch { themeError(error) }

    case "scan":
        do {
            let dirFlag = takeFlag("--dir")
            noExtraArguments()
            let dir = dirFlag.map { Wallpapers.resolved($0) } ?? Wallpapers.resolved(Wallpapers.configuredDir())
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: dir, isDirectory: &isDir), isDir.boolValue else {
                throw ThemeError(message: "wallpaper directory does not exist: \(dir)")
            }
            let entries = Wallpapers.scan(dir: dir)
            if jsonOut {
                printJSON(entries.map { entry in
                    ["name": entry.name, "path": entry.path, "bytes": entry.size,
                     "modTime": entry.modTime, "key": entry.key] as [String: Any]
                })
            }
            for entry in entries { print(entry.name) }
            exit(0)
        } catch { themeError(error) }

    case "info":
        do {
            guard let raw = args.first else { throw ThemeError(message: "wallpaper info needs a path") }
            args.removeFirst()
            noExtraArguments()
            let path = Wallpapers.resolved(raw)
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), !isDir.boolValue else {
                throw ThemeError(message: "no such wallpaper: \(path)")
            }
            let size = fileSize(path)
            let pixels = Wallpapers.pixelSize(path)
            let key = Wallpapers.derivedKey(for: path)
            let derived = "\(Wallpapers.derivedDir)/\(key)"
            let derivedCached = FileManager.default.fileExists(atPath: derived)
            var warnings: [String] = []
            let referencing = ThemeLibrary().loadAll(warnings: &warnings).filter {
                ($0.wallpaper.path.map { Wallpapers.resolved($0) } ?? "") == path
            }.map { $0.id }
            for warning in warnings { warn(warning) }
            if jsonOut {
                var obj: [String: Any] = [
                    "path": path,
                    "name": (path as NSString).lastPathComponent,
                    "key": key,
                    "derived": derived,
                    "derivedCached": derivedCached,
                    "themes": referencing,
                ]
                if let size { obj["bytes"] = size }
                if let pixels { obj["width"] = pixels.width; obj["height"] = pixels.height }
                printJSON(obj)
            }
            print(path)
            if let size { print("  size       \(humanSize(size))") }
            if let pixels { print("  pixels     \(pixels.width)x\(pixels.height)") }
            print("  key        \(key)")
            print("  derived    \(derivedCached ? "cached" : "not built") (\(derived))")
            print("  themes     \(referencing.isEmpty ? "none" : referencing.joined(separator: ", "))")
            exit(0)
        } catch { themeError(error) }

    case "rename":
        do {
            guard args.count == 2 else {
                throw ThemeError(message: "wallpaper rename needs <old> and <new>")
            }
            let outcome = try Wallpapers.rename(old: args[0], new: args[1])
            if jsonOut {
                printJSON([
                    "old": outcome.oldPath,
                    "new": outcome.newPath,
                    "indexUpdated": outcome.indexUpdated,
                    "confUpdated": outcome.confUpdated,
                    "derivedMoved": outcome.derivedMoved,
                    "themes": outcome.themeIDs,
                ])
            }
            if outcome.oldPath == outcome.newPath {
                print("already named \((outcome.oldPath as NSString).lastPathComponent)")
                exit(0)
            }
            print("renamed \((outcome.oldPath as NSString).lastPathComponent) -> \((outcome.newPath as NSString).lastPathComponent)")
            if outcome.indexUpdated { print("updated custom-index") }
            if outcome.confUpdated { print("updated themes.conf (day/night)") }
            if outcome.derivedMoved { print("moved the derived theme cache") }
            for id in outcome.themeIDs { print("updated theme \(id)") }
            for warning in outcome.warnings { warn(warning) }
            exit(0)
        } catch { themeError(error) }

    case "trash":
        do {
            guard let raw = args.first else { throw ThemeError(message: "wallpaper trash needs a path") }
            args.removeFirst()
            noExtraArguments()
            let outcome = try Wallpapers.trash(raw)
            if jsonOut {
                printJSON(["path": outcome.path, "trashed": outcome.trashedTo,
                           "derivedRemoved": outcome.derivedRemoved,
                           "indexCleared": outcome.indexCleared])
            }
            print("moved to Trash: \((outcome.path as NSString).lastPathComponent) -> \(outcome.trashedTo)")
            if outcome.derivedRemoved { print("removed the derived theme cache") }
            if outcome.indexCleared { print("cleared custom-index") }
            exit(0)
        } catch { themeError(error) }

    default:
        usage()
    }

case "palette":
    guard let sub = args.first else { usage() }
    args.removeFirst()

    switch sub {
    case "extract":
        do {
            guard let raw = args.first else { throw ThemeError(message: "palette extract needs an image path") }
            args.removeFirst()
            let mode = takeFlag("--mode") ?? "normal"
            let light = takeBool("--light")
            let noCache = takeBool("--no-cache")
            let canonical = takeBool("--canonical")
            noExtraArguments()
            guard extractionModeExists(mode) else { fail("unknown extraction mode: \(mode)") }
            let path = Wallpapers.resolved(raw)
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), !isDir.boolValue else {
                throw ThemeError(message: "no such image: \(path)")
            }
            let palette = try extractColors(url: URL(fileURLWithPath: path), light: light,
                                            mode: mode, useCache: !noCache,
                                            canonicalOrder: canonical)
            if jsonOut {
                printJSON(["path": path, "mode": mode, "light": light, "colors": palette])
            }
            palette.forEach { print($0) }
            exit(0)
        } catch { themeError(error) }

    case "magic":
        do {
            guard let raw = args.first else { throw ThemeError(message: "palette magic needs an image path") }
            args.removeFirst()
            let rolesOnly = takeBool("--roles")
            let noCache = takeBool("--no-cache")
            noExtraArguments()
            let path = Wallpapers.resolved(raw)
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), !isDir.boolValue else {
                throw ThemeError(message: "no such image: \(path)")
            }
            let url = URL(fileURLWithPath: path)
            if rolesOnly {
                let roles = try magicRoles(url: url)
                let low = roles.isLowChroma ? "+lowchroma" : ""
                if jsonOut {
                    printJSON([
                        "bar": roles.bar.hex, "pill": roles.pill.hex, "muted": roles.muted.hex,
                        "label": roles.label.hex, "accent": roles.accent.hex, "ring": roles.ring.hex,
                        "surface": roles.surface.hex, "ladder": roles.ladder, "lowChroma": roles.isLowChroma,
                    ])
                }
                print("\(roles.bar.hex) \(roles.pill.hex) \(roles.muted.hex) \(roles.label.hex) "
                    + "\(roles.accent.hex) \(roles.ring.hex) \(roles.surface.hex) \(roles.ladder)\(low) "
                    + (path as NSString).lastPathComponent)
                exit(0)
            }
            let palette = try magicPalette(url: url, useCache: !noCache)
            if jsonOut {
                printJSON(["path": path, "mode": "magic", "colors": palette])
            }
            palette.forEach { print($0) }
            exit(0)
        } catch { themeError(error) }

    case "roles":
        do {
            let colorsRaw = takeFlag("--colors")
            let imageRaw = takeFlag("--image")
            let mode = takeFlag("--mode") ?? "normal"
            let light = takeBool("--light")
            let accentRaw = takeFlag("--accent")
            noExtraArguments()
            if colorsRaw != nil && imageRaw != nil {
                fail("use either --colors or --image, not both")
            }
            guard extractionModeExists(mode) else { fail("unknown extraction mode: \(mode)") }
            let colors: [String]
            if let imageRaw {
                let path = Wallpapers.resolved(imageRaw)
                var isDir: ObjCBool = false
                guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), !isDir.boolValue else {
                    throw ThemeError(message: "no such image: \(path)")
                }
                colors = try extractColors(url: URL(fileURLWithPath: path), light: light, mode: mode)
            } else if let colorsRaw {
                colors = hexListArgument(colorsRaw)
                guard colors.count == 16 else { fail("bar roles need exactly 16 colours") }
            } else {
                fail("palette roles needs --colors CSV or --image PATH")
            }
            let accent = normalizedHex(accentRaw ?? colors[4])
            let roles = barRoles(colors, accent: accent)
            if jsonOut {
                printJSON(["bar": roles.bar, "pill": roles.pill, "muted": roles.muted,
                           "label": roles.label, "accent": roles.accent, "ring": roles.ring])
            }
            print("bar    \(roles.bar)")
            print("pill   \(roles.pill)")
            print("muted  \(roles.muted)")
            print("label  \(roles.label)")
            print("accent \(roles.accent)")
            print("ring   \(roles.ring)")
            exit(0)
        } catch { themeError(error) }

    case "suggest-mode":
        do {
            guard let raw = args.first else { throw ThemeError(message: "palette suggest-mode needs an image path") }
            args.removeFirst()
            noExtraArguments()
            let path = Wallpapers.resolved(raw)
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), !isDir.boolValue else {
                throw ThemeError(message: "no such image: \(path)")
            }
            let mode = try suggestMode(url: URL(fileURLWithPath: path))
            if jsonOut { printJSON(["path": path, "suggested": mode]) }
            print(mode)
            exit(0)
        } catch { themeError(error) }

    // Aether's derived shade variables (template.BuildVariables): the ramps
    // behind the semantic colour groups. Pure composition of the already
    // fixture-pinned darken/lighten maths.
    case "shades":
        guard let colorsRaw = takeFlag("--colors") else {
            fail("palette shades needs --colors (#rrggbb,#rrggbb,...)")
        }
        let colors = hexListArgument(colorsRaw)
        guard colors.count == 16 else { fail("palette shades needs exactly 16 colours") }
        noExtraArguments()
        let orange = ColorMath.lightened(colors[1], 15)
        let shades: [(String, String)] = [
            ("darker_bg", ColorMath.darkened(colors[0], 50)),
            ("dark_bg", ColorMath.darkened(colors[0], 75)),
            ("lighter_bg", ColorMath.lightened(colors[0], 10)),
            ("dark_fg", ColorMath.darkened(colors[7], 75)),
            ("light_fg", ColorMath.lightened(colors[7], 15)),
            ("bright_fg", ColorMath.lightened(colors[7], 25)),
            ("orange", orange),
            ("brown", ColorMath.darkened(orange, 60)),
        ]
        if jsonOut { printJSON(Dictionary(uniqueKeysWithValues: shades)) }
        for (key, hex) in shades { print("\(key) \(hex)") }
        exit(0)

    case "render":
        guard let colorsRaw = takeFlag("--colors") else {
            fail("palette render needs --colors (#rrggbb,#rrggbb,...)")
        }
        let colors = hexListArgument(colorsRaw)
        guard colors.count == 16 else { fail("palette render needs exactly 16 colours") }
        var extended = Extended.defaults(for: colors)
        if let v = takeFlag("--accent") { extended.accent = normalizedHex(v) }
        if let v = takeFlag("--cursor") { extended.cursor = normalizedHex(v) }
        if let v = takeFlag("--selection-foreground") {
            extended.selectionForeground = normalizedHex(v)
        }
        if let v = takeFlag("--selection-background") {
            extended.selectionBackground = normalizedHex(v)
        }
        let adjustments = takeAdjustments()
        let curve = curvePointsArgument(takeFlag("--curve") ?? "")
        noExtraArguments()
        let palette = Palette16(method: "render", colors: colors, extended: extended,
                                adjustments: adjustments, curve: curve)
        let out = palette.rendered()
        if jsonOut {
            printJSON([
                "colors": out.colors,
                "extended": ["accent": out.extended.accent,
                             "cursor": out.extended.cursor,
                             "selection_foreground": out.extended.selectionForeground,
                             "selection_background": out.extended.selectionBackground],
            ])
        }
        out.colors.forEach { print($0) }
        print(out.extended.accent)
        print(out.extended.cursor)
        print(out.extended.selectionForeground)
        print(out.extended.selectionBackground)
        exit(0)

    case "generate":
        guard let colorsRaw = takeFlag("--colors") else {
            fail("palette generate needs --colors (#rrggbb,#rrggbb,...)")
        }
        let colors = hexListArgument(colorsRaw)
        let mode = takeFlag("--mode") ?? "normal"
        let light = takeBool("--light")
        let normalize = takeBool("--normalize")
        let countsRaw = takeFlag("--counts")
        let weightsRaw = takeFlag("--weights")
        noExtraArguments()
        guard extractionModeExists(mode) else { fail("unknown extraction mode: \(mode)") }
        if countsRaw != nil && weightsRaw != nil {
            fail("--counts and --weights cannot be combined")
        }
        var weights: [Double]? = nil
        if let countsRaw {
            let counts = intListArgument(countsRaw)
            guard counts.count == colors.count else { fail("--counts must have one value per colour") }
            weights = normalizeCounts(counts)
        } else if let weightsRaw {
            let values = doubleListArgument(weightsRaw)
            guard values.count == colors.count else { fail("--weights must have one value per colour") }
            weights = values
        }
        if mode == "chromatic" && colors.count < 8 {
            fail("chromatic needs at least 8 dominant colours")
        }
        var palette = generatePaletteByMode(colors, weights, light, mode)
        if normalize { palette = normalizeBrightness(palette) }
        if jsonOut {
            printJSON(["mode": mode, "light": light, "colors": palette])
        }
        palette.forEach { print($0) }
        exit(0)

    case "quantize":
        var count = Extract.dominantColorsToExtract
        if let raw = takeFlag("--count") {
            guard let n = Int(raw), n >= 1, n <= 256 else {
                fail("--count must be a whole number between 1 and 256")
            }
            count = n
        }
        let fileRaw = takeFlag("--pixels-file")
        let inlineRaw = takeFlag("--pixels")
        noExtraArguments()
        let hexes: [String]
        if let fileRaw {
            if fileRaw == "-" {
                let data = FileHandle.standardInput.readDataToEndOfFile()
                hexes = String(data: data, encoding: .utf8)?
                    .split(whereSeparator: { $0 == "," || $0 == "\n" || $0 == " " || $0 == "\t" })
                    .map(String.init) ?? []
            } else {
                let path = Wallpapers.resolved(fileRaw)
                guard let text = try? String(contentsOfFile: path, encoding: .utf8) else {
                    fail("cannot read \(path)")
                }
                hexes = text.split(whereSeparator: { $0 == "," || $0 == "\n" || $0 == " " || $0 == "\t" })
                    .map(String.init)
            }
        } else if let inlineRaw {
            hexes = inlineRaw.split(separator: ",").map(String.init)
        } else {
            fail("palette quantize needs --pixels-file or --pixels")
        }
        let pixels = hexes.map { raw -> RGB in
            guard let v = ColorMath.hexUInt32(raw) else { fail("invalid pixel colour \"\(raw)\"") }
            return RGB(r: Double((v >> 16) & 0xff), g: Double((v >> 8) & 0xff), b: Double(v & 0xff))
        }
        do {
            let (colors, counts) = try extractDominantColorsFromPixels(pixels, count: count)
            if jsonOut {
                printJSON(zip(colors, counts).map { ["hex": $0.0, "count": $0.1] })
            }
            for (hex, n) in zip(colors, counts) { print("\(hex) \(n)") }
            exit(0)
        } catch { themeError(error) }

    case "analyze":
        guard let op = args.first else { fail("palette analyze needs an operation") }
        args.removeFirst()
        switch op {
        case "dark":
            let hex = hexArgument("hex")
            noExtraArguments()
            print(isDarkColor(hex) ? "true" : "false")

        case "hue-distance":
            guard args.count >= 2, let a = Double(args[0]), let b = Double(args[1]) else {
                fail("hue-distance needs two numbers")
            }
            args.removeFirst(2)
            noExtraArguments()
            print(String(format: "%.9f", hueDistance(a, b)))

        case "is-monochrome":
            guard let raw = args.first else { fail("is-monochrome needs a colour list") }
            args.removeFirst()
            noExtraArguments()
            print(isMonochromeImage(hexListArgument(raw)) ? "true" : "false")

        case "weighted":
            guard args.count >= 2 else { fail("weighted needs colours and counts") }
            let colors = hexListArgument(args[0])
            let counts = args[1] == "-" ? nil : intListArgument(args[1])
            args.removeFirst(2)
            noExtraArguments()
            print(isMonochromeWeighted(colors, counts.flatMap(normalizeCounts)) ? "true" : "false")

        case "tint":
            guard let raw = args.first else { fail("tint needs a colour list") }
            args.removeFirst()
            noExtraArguments()
            let (hue, hasTint, strength) = detectMonochromeTint(hexListArgument(raw))
            print(String(format: "%@ %.9f %.9f", hasTint ? "true" : "false", hue, strength))

        case "salient":
            guard let raw = args.first else { fail("salient needs a colour list") }
            args.removeFirst()
            noExtraArguments()
            print(String(format: "%.9f", salientChroma(hexListArgument(raw))))

        case "bright":
            let hex = hexArgument("hex")
            noExtraArguments()
            print(generateBrightVersion(hex))

        case "sort":
            guard let raw = args.first else { fail("sort needs a colour list") }
            args.removeFirst()
            noExtraArguments()
            print(sortColorsByLightness(hexListArgument(raw)).map { $0.color }.joined(separator: ","))

        case "bg":
            guard args.count >= 3 else { fail("bg needs colours, counts and dark|light") }
            let colors = hexListArgument(args[0])
            let weights = args[1] == "-" ? nil : normalizeCounts(intListArgument(args[1]))
            guard args[2] == "dark" || args[2] == "light" else { fail("bg needs dark|light") }
            let light = args[2] == "light"
            args.removeFirst(3)
            noExtraArguments()
            let (hex, index) = findBackgroundColor(colors, weights, light)
            print("\(hex) \(index)")

        case "fg":
            guard args.count >= 4 else { fail("fg needs colours, counts, dark|light and a background hex") }
            let colors = hexListArgument(args[0])
            let weights = args[1] == "-" ? nil : normalizeCounts(intListArgument(args[1]))
            guard args[2] == "dark" || args[2] == "light" else { fail("fg needs dark|light") }
            let light = args[2] == "light"
            let bg = normalizedHex(args[3])
            args.removeFirst(4)
            noExtraArguments()
            let (hex, index) = findForegroundColor(colors, weights, light, bg, [])
            print("\(hex) \(index)")

        case "assign":
            guard args.count >= 3 else { fail("assign needs colours, counts and dark|light") }
            let colors = hexListArgument(args[0])
            guard args[2] == "dark" || args[2] == "light" else { fail("assign needs dark|light") }
            let light = args[2] == "light"
            args.removeFirst(3)
            noExtraArguments()
            let assignments = findOptimalAnsiAssignment(colors, [], light)
            print(assignments.map { $0.map { String($0.poolIndex) } ?? "-1" }.joined(separator: ","))

        default:
            usage()
        }
        exit(0)

    default:
        usage()
    }

case "image":
    guard let sub = args.first else { usage() }
    args.removeFirst()

    switch sub {
    case "info":
        do {
            guard let raw = args.first else { throw ThemeError(message: "image info needs a path") }
            args.removeFirst()
            noExtraArguments()
            let path = Wallpapers.resolved(raw)
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), !isDir.boolValue else {
                throw ThemeError(message: "no such image: \(path)")
            }
            let sample = try sampleImage(url: URL(fileURLWithPath: path))
            let meanR = (sample.mean.r * 100).rounded() / 100
            let meanG = (sample.mean.g * 100).rounded() / 100
            let meanB = (sample.mean.b * 100).rounded() / 100
            if jsonOut {
                printJSON([
                    "path": path,
                    "name": (path as NSString).lastPathComponent,
                    "format": sample.format,
                    "width": sample.width,
                    "height": sample.height,
                    "hasAlpha": sample.hasAlpha,
                    "sampledPixels": sample.pixels.count,
                    "sampleMean": [sample.mean.r, sample.mean.g, sample.mean.b],
                    "sampleDigest": sample.digest,
                ])
            }
            print(path)
            print("  format      \(sample.format)")
            print("  pixels      \(sample.width)x\(sample.height)")
            print("  alpha       \(sample.hasAlpha ? "yes" : "no")")
            print("  samples     \(sample.pixels.count)")
            print("  sample mean \(meanR), \(meanG), \(meanB)")
            exit(0)
        } catch { themeError(error) }

    case "histogram":
        do {
            guard let raw = args.first else { throw ThemeError(message: "image histogram needs a path") }
            args.removeFirst()
            noExtraArguments()
            let path = Wallpapers.resolved(raw)
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), !isDir.boolValue else {
                throw ThemeError(message: "no such image: \(path)")
            }
            let bins = try imageHistogram(url: URL(fileURLWithPath: path))
            if jsonOut { printJSON(["path": path, "bins": bins]) }
            bins.forEach { print($0) }
            exit(0)
        } catch { themeError(error) }

    default:
        usage()
    }

default:
    usage()
}
