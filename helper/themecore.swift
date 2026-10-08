// themecore.swift — the Theme Studio engine: colour maths and adjustments.
//
//   omacosy-themecore color convert <hex> [--to rgb|hsl|oklab|oklch] [--json]
//   omacosy-themecore color contrast <colour-a> <colour-b> [--json]
//   omacosy-themecore color adjust <hex> [12 flags] [--json]
//   omacosy-themecore color darken <hex> <percent> [--json]
//   omacosy-themecore color lighten <hex> <percent> [--json]
//   omacosy-themecore color gradient <start> <end> [--steps N] [--json]
//   omacosy-themecore color from-color <hex> [--json]
//   omacosy-themecore color roundtrip <hex> [--json]     (test support)
//   omacosy-themecore version [--json]
//
// A PURE CLI: no AppKit, no UI, no permissions. Everything the Theme Studio
// editors need that is not drawing lives here, so the dashboard only calls a
// process and reads its answer. This file is the Phase 1a engine — colour
// spaces, WCAG contrast, adjustments, gradients; the presets, modes, theme
// records and library arrive in Phase 1b.
//
// Ported from Aether (https://github.com/omacom/aether)
// Copyright (c) Bjarne Overli — MIT License
import Foundation

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

// MARK: - CLI

let themecoreVersion = "0.1.0"

func fail(_ message: String) -> Never {
    FileHandle.standardError.write("omacosy-themecore: \(message)\n".data(using: .utf8)!)
    exit(1)
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
           omacosy-themecore version [--json]

    """.data(using: .utf8)!)
    exit(2)
}

func printJSON(_ object: [String: Any]) -> Never {
    do {
        let data = try JSONSerialization.data(withJSONObject: object,
                                              options: [.sortedKeys, .prettyPrinted])
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

default:
    usage()
}
