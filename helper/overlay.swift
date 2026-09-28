// overlay.swift — a desktop-level window that shows a wallpaper image
// above the system wallpaper and below the desktop icons.
//
//   omacosy-overlay            run forever (launchd, or nohup while testing)
//
// It watches ~/.local/state/omacosy/overlay. The file holds either an
// absolute path to an image, or the word "off". The switch coordinator
// writes the target wallpaper there the instant a theme starts changing,
// so the user sees the new wallpaper immediately; macOS paints the real
// system wallpaper seconds later and the coordinator then writes "off".
//
// Why a window, and not the system wallpaper: NSWorkspace's wallpaper
// path takes 4.5 s to appear on this machine (measured), and coalesces
// rapid requests into one even later. A window at desktopWindow+1 shows
// the same pixels in ~30 ms. The desktop icons live at desktopWindow+20,
// so the overlay sits under them, exactly like a wallpaper.
//
// Window level, spaces and scaling mirror what the throwaway demo proved
// on this Mac; the image is pre-scaled to the display and swapped with
// CoreAnimation actions disabled, so the change is one frame, not a fade.

import AppKit

let stateDir = NSHomeDirectory() + "/.local/state/omacosy"
let commandFile = stateDir + "/overlay"
let shownFile = stateDir + "/overlay-shown"
let targetFile = stateDir + "/overlay-target"
let ackFIFO = stateDir + "/overlay-ack"
// Where macOS records the desktop picture it has applied. We watch it so the
// handoff from overlay to system wallpaper is an EVENT, never a poll.
let wallpaperStore = NSHomeDirectory()
    + "/Library/Application Support/com.apple.wallpaper/Store"
let logURL = URL(fileURLWithPath: "/tmp/omacosy-overlay.log")

let t0ref = Date()
func tlog(_ m: String) {
    let line = String(format: "%.0fms %@\n", Date().timeIntervalSince(t0ref) * 1000, m)
    if let h = try? FileHandle(forWritingTo: logURL) {
        h.seekToEndOfFile()
        try? h.write(contentsOf: Data(line.utf8))
        try? h.close()
    } else {
        try? line.write(to: logURL, atomically: true, encoding: .utf8)
    }
}

// ImageIO leaks ~17 MB per decode on this macOS build (measured: 30 distinct
// wallpapers -> 540 MB; decoding the SAME image 30 times also grows, so it is
// per decode, not a cache). The system wallpaper engine does not. The helper
// is stateless, so once it has settled and the overlay is off it can exit and
// be restarted by the coordinator on the next press, returning the memory.
func rssMB() -> Double {
    var info = mach_task_basic_info()
    var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size
                                       / MemoryLayout<natural_t>.size)
    let r = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
        }
    }
    return r == KERN_SUCCESS ? Double(info.resident_size) / 1048576 : 0
}
let rssLimitMB: Double = 200

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

// Without this the helper is App-Napped between commands (accessory, no
// active window), and the ack — the signal the coordinator waits for before
// it recolours the bar — lands ~2 s late (measured). Latency-critical keeps
// the run loop and the directory watch responsive.
let activity = ProcessInfo.processInfo.beginActivity(
    options: [.userInitiated, .latencyCritical, .idleSystemSleepDisabled],
    reason: "omacosy theme overlay")
_ = activity

let overlayLevel = Int(CGWindowLevelForKey(.desktopWindow)) + 1

final class ScreenWindow {
    let window: NSWindow
    let layer: CALayer
    let screen: NSScreen
    init(screen: NSScreen) {
        self.screen = screen
        // contentRect is relative to `screen`, so a global origin here is
        // added twice and the window lands off-screen (seen on a second
        // display: x=2880 instead of 1440). Use the screen-local origin.
        let frame = NSRect(origin: .zero, size: screen.frame.size)
        let w = NSWindow(contentRect: frame, styleMask: [.borderless],
                         backing: .buffered, defer: false, screen: screen)
        w.isOpaque = true
        w.isReleasedWhenClosed = false
        w.hasShadow = false
        w.level = NSWindow.Level(rawValue: overlayLevel)
        w.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle,
                                .fullScreenAuxiliary]
        w.ignoresMouseEvents = true
        let v = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
        v.wantsLayer = true
        v.layer?.contentsGravity = .resizeAspectFill
        v.layer?.masksToBounds = true
        w.contentView = v
        self.window = w
        self.layer = v.layer!
    }
    func setImage(_ cg: CGImage) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.contents = cg
        CATransaction.commit()
        CATransaction.flush()
        window.orderFrontRegardless()
    }
    func hide() { window.orderOut(nil) }
}

var windows: [ScreenWindow] = []
var currentPath = ""            // path currently shown, "" = off
var shown = false
let loadQueue = DispatchQueue(label: "omacosy.overlay.load", qos: .userInitiated)
// Only the CURRENT image is kept. A cache across wallpapers grew to 750 MB
// of RSS after a few dozen distinct pictures (measured), for no benefit: at
// most one is on screen.
var currentImagePath = ""
var currentImage: CGImage?
var loading = false
var latestPath = ""

func scaled(_ cg: CGImage, to size: CGSize, scale: CGFloat) -> CGImage? {
    let w = max(1, Int(size.width * scale)), h = max(1, Int(size.height * scale))
    guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                              bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return nil }
    let iw = CGFloat(cg.width), ih = CGFloat(cg.height)
    let s = max(CGFloat(w) / iw, CGFloat(h) / ih)
    let dw = iw * s, dh = ih * s
    ctx.interpolationQuality = .medium
    ctx.draw(cg, in: CGRect(x: (CGFloat(w) - dw) / 2, y: (CGFloat(h) - dh) / 2,
                            width: dw, height: dh))
    return ctx.makeImage()
}

func rebuildWindows() {
    for w in windows { w.window.close() }
    windows = NSScreen.screens.map { ScreenWindow(screen: $0) }
    tlog("windows rebuilt: \(windows.count) screen(s)")
}

func image(for path: String, maxPixel: CGSize) -> CGImage? {
    if path == currentImagePath, let img = currentImage { return img }
    guard let src = CGImageSourceCreateWithURL(
        URL(fileURLWithPath: path) as CFURL,
        [kCGImageSourceShouldCache: false] as CFDictionary)
    else { return nil }
    // Decode STRAIGHT to display size. Decoding the full 6016x3384 source
    // costs ~80 MB of bitmap per wallpaper and made the helper's peak RSS
    // 660 MB after a couple of dozen pictures (measured). A thumbnail
    // decode never materialises the full image.
    // Decode straight to the screen's DEVICE pixel size. The overlay must be
    // as sharp as the system wallpaper it hands off to, or removing it is a
    // visible resolution flicker (seen with 1x). overlayMaxPixel() respects
    // each display's backing scale, so this is crisp on Retina and non-Retina
    // alike and needs no hard-coded resolution.
    let maxSide = max(maxPixel.width, maxPixel.height)
    let opts: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceThumbnailMaxPixelSize: maxSide,
        kCGImageSourceShouldCache: false,
        kCGImageSourceShouldCacheImmediately: false,
    ]
    guard let img = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary)
    else { return nil }
    currentImagePath = path
    currentImage = img
    return img
}

// The pixel size to decode for: the largest screen dimension, in DEVICE
// pixels (points x that display's own backing scale, so Retina factors are
// respected). One texture at this size is crisp on every connected display
// and the handoff to the system wallpaper is invisible. A cap keeps a very
// high-resolution external display from decoding a needlessly large texture.
func overlayMaxPixel() -> CGSize {
    let cap: CGFloat = 5120
    let longest = NSScreen.screens.map {
        max($0.frame.width, $0.frame.height) * $0.backingScaleFactor
    }.max() ?? 1440
    let side = min(longest, cap)
    return CGSize(width: side, height: side)
}

// One decode at a time, always the LATEST request. A burst of presses used
// to queue a decode per press and spike RSS to ~660 MB (measured); this
// drops everything but the one that will actually be shown.
func loadNext() {
    let path = latestPath
    if path.isEmpty { loading = false; return }
    tlog("load start \(URL(fileURLWithPath: path).lastPathComponent)")
    let maxPixel = overlayMaxPixel()
    loadQueue.async {
        guard path == latestPath else {
            DispatchQueue.main.async { loadNext() }
            return
        }
        let d0 = DispatchTime.now().uptimeNanoseconds
        let decoded: CGImage? = autoreleasepool { image(for: path, maxPixel: maxPixel) }
        let decodeMS = Double(DispatchTime.now().uptimeNanoseconds - d0) / 1_000_000
        DispatchQueue.main.async {
            if latestPath == path, let cg = decoded {
                let t0 = DispatchTime.now().uptimeNanoseconds
                for w in windows { w.setImage(cg) }
                let ms = Double(DispatchTime.now().uptimeNanoseconds - t0) / 1_000_000
                shown = true
                try? (path + "\n").write(toFile: shownFile, atomically: true, encoding: .utf8)
                // Tell the coordinator (blocked on the FIFO) that the new
                // wallpaper is on screen. An event, not a poll.
                let fd = open(ackFIFO, O_WRONLY | O_NONBLOCK)
                if fd >= 0 {
                    _ = write(fd, "1", 1)
                    close(fd)
                }
                tlog(String(format: "overlay %@ (decode %.0f ms, display %.0f ms)",
                            (path as NSString).lastPathComponent, decodeMS, ms))
            }
            if latestPath == path { loading = false } else { loadNext() }
        }
    }
}

func apply(_ raw: String) {
    let target = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    if target == currentPath { return }
    tlog("apply \((target as NSString).lastPathComponent)")
    currentPath = target
    if target.isEmpty || target == "off" {
        latestPath = ""
        for w in windows { w.hide() }
        shown = false
        try? "off\n".write(toFile: shownFile, atomically: true, encoding: .utf8)
        tlog("overlay off")
        if rssMB() > rssLimitMB {
            tlog(String(format: "exiting to reclaim %.0f MB (decode leak)", rssMB()))
            exit(0)
        }
        return
    }
    latestPath = target
    if !loading { loading = true; loadNext() }
}

// Hide the overlay once macOS has actually applied the requested wallpaper.
// Called by the wallpaper-store watch (and whenever a target is written), so
// the handoff is event-driven — no timer, no poll. It hides only when the
// image the overlay is showing IS the target, so a newer preview is never
// hidden by an older apply.
func checkHandoff() {
    let target = (try? String(contentsOfFile: targetFile, encoding: .utf8))?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    guard !target.isEmpty, target == currentPath else { return }
    let want = URL(fileURLWithPath: target).resolvingSymlinksInPath().path
    let applied = NSScreen.screens.allSatisfy { screen in
        NSWorkspace.shared.desktopImageURL(for: screen)?
            .resolvingSymlinksInPath().path == want
    }
    guard applied else { return }
    for w in windows { w.hide() }
    currentPath = "off"
    shown = false
    // keep the command file consistent, so re-showing the same image works
    try? "off\n".write(toFile: commandFile, atomically: true, encoding: .utf8)
    try? "off\n".write(toFile: shownFile, atomically: true, encoding: .utf8)
    try? "".write(toFile: targetFile, atomically: true, encoding: .utf8)
    tlog("handoff: system wallpaper applied")
    if rssMB() > rssLimitMB {
        tlog(String(format: "exiting to reclaim %.0f MB (decode leak)", rssMB()))
        exit(0)
    }
}

// --- run ---------------------------------------------------------------

try? FileManager.default.createDirectory(atPath: stateDir,
                                         withIntermediateDirectories: true)
rebuildWindows()
apply((try? String(contentsOfFile: commandFile, encoding: .utf8)) ?? "off")

NotificationCenter.default.addObserver(
    forName: NSApplication.didChangeScreenParametersNotification,
    object: nil, queue: .main) { _ in
        rebuildWindows()
        let shownPath = currentPath
        currentPath = ""
        apply(shownPath)
    }

// Watch the state directory instead of polling it. That removes the poll's
// CPU and up to 40 ms of latency from every switch (the coordinator waits for
// the ack before it recolours the bar).
let watchFD = open(stateDir, O_EVTONLY)
var dirWatch: DispatchSourceFileSystemObject?
if watchFD >= 0 {
    let src = DispatchSource.makeFileSystemObjectSource(
        fileDescriptor: watchFD,
        eventMask: [.write, .rename, .delete, .attrib],
        queue: .main)
    src.setEventHandler {
        apply((try? String(contentsOfFile: commandFile, encoding: .utf8)) ?? "off")
        checkHandoff()
    }
    src.setCancelHandler { close(watchFD) }
    src.resume()
    dirWatch = src   // must be retained, or it is cancelled at once
}

// Watch the wallpaper store: when macOS writes the applied picture there, the
// handoff is an event. No timer, no poll.
let storeFD = open(wallpaperStore, O_EVTONLY)
var storeWatch: DispatchSourceFileSystemObject?
if storeFD >= 0 {
    let src = DispatchSource.makeFileSystemObjectSource(
        fileDescriptor: storeFD,
        eventMask: [.write, .rename, .delete, .attrib],
        queue: .main)
    src.setEventHandler { checkHandoff() }
    src.setCancelHandler { close(storeFD) }
    src.resume()
    storeWatch = src
} else {
    tlog("wallpaper store not found at \(wallpaperStore); handoff stays on screen")
}

tlog("omacosy-overlay started, level \(overlayLevel)")
app.run()
