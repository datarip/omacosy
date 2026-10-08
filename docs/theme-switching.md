# Instant, synced theme switching

`Super+Shift+T` and `Super+Shift+B` make the wallpaper, the bar and the focus
ring change **together and at once**, instead of the colours arriving seconds
before the picture.

This page is the record: what was wrong, what was tried, what shipped, and how
it works.

## 1. The problem

Before this, the two theme keys ran `theme-next` / `theme-bg-next` →
`theme-set`, and the result looked broken:

- the **bar and the focus ring recoloured in ~15 ms** — they only read the
  theme symlink `~/.config/omarchy/current/theme`, which the script moves
  first;
- the **wallpaper appeared seconds later** — it is a request to macOS, and
  macOS paints it on its own schedule.

Measured on this machine (MacBook Air M1, macOS 27.2):

| what | time |
| --- | --- |
| bar repaint after the symlink moves | **7–20 ms** |
| desktop picture actually on screen after the request | **~4.5 s** |
| same, with a 309-byte 100×100 solid PNG | ~4.5 s |
| four requests 0.3 s apart | **one** paint, **17 s** later |

Two consequences fall out of that:

- it is not the image size and not the API choice: `NSWorkspace.setDesktopImageURL`
  and AppleScript's System Events both take ~4.5 s, because this macOS routes
  the picture through `WallpaperAgent` and an image extension that does work
  and throttles changes;
- **repeated requests make it worse** — the system coalesces them and delays
  the result. So the theme key cannot simply ask for every wallpaper as the
  user cycles.

macOS also has **no public notification** for "the desktop picture changed";
`NSWorkspace.desktopImageURL` only flips when the picture is actually painted.
A desktop-level window, by contrast, can show a new picture in ~30 ms.

## 2. The options

1. **Do nothing.** The colours keep arriving seconds before the wallpaper.
2. **Hide the bar and the ring while switching, reveal them after a settle.**
   Removes the mismatch by removing the bar, but speeds nothing up and is a
   bigger change to how the desktop looks.
3. **Overlay only (the Backdrop / Plash approach):** draw the wallpaper in a
   desktop-level window and never set the system wallpaper. Rejected. The lock
   screen and login window, Mission Control, and omacosy's own
   `wallpaper get`/`resync`, the bar's colour derivation and the overview all
   read the **real** desktop picture; and a desktop window cannot reach the
   lock screen — Backdrop only does that by reverse-engineering the wallpaper
   store, which is private and brittle.
4. **Delay the colours to match the wallpaper.** No speed gain; the colours
   simply arrive late.
5. **Shipped: instant preview + real wallpaper handoff, event-driven.** Draw
   the chosen wallpaper ourselves at once, recolour the bar and ring with it,
   and let macOS apply the real wallpaper underneath; remove our window when
   macOS has caught up. A settle debounce collapses a burst of presses into
   one real wallpaper request.

### The one trade inside option 5: decode size

The preview window's image is decoded at the **display's device-pixel size**
(points × the display's own backing scale, capped at 5120), so it is as sharp
as the wallpaper it hands off to and the handoff is invisible.

Decoding at **1×** (point size) was tried and rejected: it uses less memory —
~5 MB per wallpaper instead of ~18 MB, because ImageIO leaks per decode — but
the preview is then softer than the system wallpaper and the handoff becomes a
visible resolution flash. Sharpness wins; the memory is handled by the helper
exiting once it has settled (below).

## 3. How it works, technically

Two new pieces, plus a shortcut change.

**`bin/omacosy-theme-switch`** is what the two keys run (Karabiner under
OmniWM, `aerospace.toml` under AeroSpace). On each press it:

1. computes the target (advancing from the pending choice, not the live
   symlink), and derives the custom palette if the target is a custom
   wallpaper;
2. writes the wallpaper path to `~/.local/state/omacosy/overlay` (written
   atomically, so the helper never reads a half-written file);
3. blocks on a **FIFO** until the helper acknowledges that the wallpaper is on
   screen;
4. only then moves the theme symlink. The bar and ring repaint ~15 ms later —
   **3 ms** after the overlay in the measurement — so they always match the
   wallpaper instead of leading it.

**`helper/overlay.swift` → `omacosy-overlay`** is a launchd agent
(`com.omacosy.overlay`), one desktop-level window per display:

- level `CGWindowLevelForKey(.desktopWindow) + 1` — above the system
  wallpaper, below the desktop icons (`+ 20`), on all Spaces, ignoring the
  mouse;
- it watches the state directory with **kqueue**, decodes the image straight
  to the screen's device-pixel size with ImageIO, and swaps the window's layer
  contents with CoreAnimation actions disabled, so the change is one frame,
  not a fade (`displayIfNeeded` + `CATransaction.flush`);
- it writes one byte to the FIFO, which is the ack above.

**The settle and the handoff are events, not polls:**

- a few seconds with no further press (`OMACOSY_SETTLE_SECONDS`, default 4) is
  taken as the choice — one one-shot deadline, the only timer in the feature;
- the coordinator then asks macOS for the real wallpaper and writes the path
  to `~/.local/state/omacosy/overlay-target`;
- the helper watches `~/Library/Application Support/com.apple.wallpaper/Store`
  with a **kqueue** source, and when the applied picture matches the target it
  hides the overlay. That event lands *after* macOS has painted, so no grace
  timer is needed either.

**The real wallpaper is asked for by two mechanisms, not one.** `omacosy-helper
wallpaper <path>` sets it through `NSWorkspace.setDesktopImageURL` (the public
API, and the one whose choice macOS stores) **and** through System Events'
`set picture`, the legacy AppleScript that `theme-set` and `theme-bg-next`
already fall back to when the helper is not installed. They are independent, so
a switch still lands when one of them breaks. This is not detection: both are
asked every time, whichever works does the work, and on a healthy build the two
agree. There is no retry, no poll and no new timer — the apply is a short-lived
child process beside the API call, and the handoff watch above is unchanged
because both mechanisms update the same `desktopImageURL` the watch reads.

It exists because macOS **27.2 build 26B5101f** (the Beta 3 patch, seen
2026-10-06) changed the wallpaper image extension: the public API returns
success but the request is rejected (`WallpaperFoundation.WallpaperURLError
(2)`, logged by `com.apple.wallpaper.extension.image`) and nothing moves. The
picture still *seems* to change because the overlay above draws it; the lock
screen and the first picture at boot keep the old one. Asking System Events as
well restores the live picture on that build. See "Limitations" for the half it
cannot restore.

**Memory.** ImageIO leaks about 18 MB per decoded wallpaper on macOS 27.2
(decoding the same image repeatedly grows the same way; a plain alloc/free
loop plateaus, so it is real). The helper only keeps the current image, and
once it has settled it **exits** to give the memory back; launchd restarts it
on demand. Idle ~38 MB, ~110–180 MB while a 6K wallpaper is shown.

**Displays.** One window per screen at the screen's **local** origin
(`NSWindow(contentRect:screen:)` takes the rect relative to that screen; a
global origin is added twice and lands the window off-screen). The texture is
decoded to the longest screen dimension across all displays, so every display
is crisp.

## 4. How it works, for the user

- **Press** `Super+Shift+T` (theme) or `Super+Shift+B` (wallpaper): the
  wallpaper changes at once, and the bar and the ring change with it.
- **Browse:** keep pressing. Every press is instant; the real wallpaper
  request is collapsed to the last one, so nothing stacks and nothing lags.
- **Settle:** after ~4 s with no press, the chosen wallpaper is applied for
  real, underneath the overlay; when macOS has caught up the overlay is
  removed on top of the same picture, so you see no second change.
- **External displays:** the same wallpaper fills each one, sharp, and a
  display plugged in while a switch is pending is covered the same way.
- **Lock screen and login:** these show the **real** wallpaper, which is why
  the real wallpaper is still applied through both mechanisms. The preview
  window does not reach them.

## 5. Limitations

- The wallpaper store path is **private**. If a future macOS moves it, the
  overlay simply stays on screen (which is visually correct — it shows the
  chosen wallpaper) and the log says the store was not found. There is no
  polling fallback by design.
- **System Events needs the Automation (Apple Events) permission**, attributed
  to whichever process sends the Apple event, and a rebuild can invalidate it —
  the same class of nuisance as the accessibility grant. If it is denied, the
  System Events half does nothing and a switch is back to the public API alone,
  so it degrades rather than breaks.
- **The public API is the only persisting mechanism.** System Events changes
  the live picture but does **not** write the wallpaper store (measured on
  27.2 build 26B5101f: the store's Desktop entry is unchanged 34 s after a
  `set picture`). So on a build where the API is broken, the lock screen during
  a session follows the live picture, but the picture stored for the next boot
  is not updated by this fallback; only Apple fixing the API restores that
  half.
- The **terminal and its apps** are told at the same moment as the bar and the
  ring, but they are separate programs that must rewrite their configs and
  reload, so they settle about a second later.
- It depends on the custom/auto themes (`omacosy-custom-theme`,
  `omacosy-auto-theme`), which are not upstream yet, so it is a fork-only
  feature for now.

## 6. Files

| File | What |
| --- | --- |
| `helper/overlay.swift` | the desktop-level wallpaper window (launchd agent `com.omacosy.overlay`) |
| `bin/omacosy-theme-switch` | the coordinator the two keys run |
| `bin/omacosy-karabiner-omniwm` | the OmniWM shortcut rules now call it |
| `config/aerospace/aerospace.template.toml` | the AeroSpace bindings now call it |
| `install.sh`, `uninstall.sh` | build and link the helper; the launch agent |
