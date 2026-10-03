# omacosy-daily

A personal build of [omacosy](https://github.com/paulsp94/omacosy) by
Paul Spende. It is the build I run every day. It adds fixes and
features, and I offer each one that fits upstream as a pull request.
[FORK.md](FORK.md) lists what it adds.

**It takes no contributions.** Open issues and pull requests at
[paulsp94/omacosy](https://github.com/paulsp94/omacosy).

omakase + macOS + cosy. An [omarchy](https://omarchy.org)-style setup
for macOS: tiling window management with a real Super key and
Hyprland's dwindle layout, a status bar built for it (bar, popups,
sliders and screen dimming in one process), focus follows mouse,
trackpad workspace swipes, a Mission-Control-style workspace overview
with live previews, focused-window border rings, and one theme switch
that covers everything down to the wallpaper. All of it installs from
this one repo.

![The omacosy desktop — themed bar over the osaka-jade wallpaper](docs/screenshots/desktop.jpg)

The whole environment idles at about **157MB** of memory. Numbers per
process in [Memory use](#memory-use).

Most of it is eight small binaries (Swift and C) built by the installer,
because several of the existing tools are broken on macOS 26. The
details are under [What's inside](#whats-inside).

## Where it runs

| Setup | Status |
| --- | --- |
| Apple silicon, macOS 27, one display with no notch | runs every day on a MacBook Air M1, under AeroSpace and under OmniWM |
| macOS 26 (Tahoe) | supported. Upstream omacosy is built and measured on macOS 26.3, and this build keeps that code |
| A MacBook with a notch | supported in the code, and not yet run on a notched MacBook. The six things it does differently are listed below |
| An external monitor, or two displays | supported in the code: each display gets its own nine workspaces. Upstream runs it docked to a second display. This build is tested on one display: the MacBook Air M1 drives only one external display, so two external displays need other hardware. A test on a Mac mini with two displays is in progress |
| An Intel Mac | not supported. `install.sh` builds the gesture daemon and the OmniWM client for Apple silicon only |
| `./uninstall.sh` | tested in a sandbox, for every starting state of `~/.zshrc`. Not yet run on a real Mac |

The first tests on a notched MacBook and of `uninstall.sh` use release
`v1.0.0`. Their results go into this section.

### On a MacBook with a notch

The code reads the notch height of each display from macOS, so a notched
built-in display and a flat external monitor each get their own layout.
On a notched display it does six things differently. Each one is written,
and each one waits for its first run on a notched MacBook:

1. The bar stays visible at rest. macOS already keeps the camera strip
   out of the space windows use, so hiding the bar there gains nothing.
   The default, `autohide=off` in `bar.conf`, keeps it visible on every
   display; `autohide=auto` also keeps it visible on a notched one.
2. The top gap for windows subtracts the notch height, so tiled windows
   start just below the bar and not one notch lower.
3. The media pill sits at the left edge, because the camera takes the
   centre of the strip.
4. The media title is cut at 20 characters, not 28.
5. At the top edge, the native menu bar comes down over the bar, so its
   menus and status icons are reachable. The bar rests below the native
   menu bar and above other apps' windows.
6. A fullscreen window starts below the camera strip, and the strip is
   painted black, so fullscreen looks complete.

## What install.sh changes on your Mac

Read this before you run it.

- It installs Homebrew if it is missing, then the packages in `Brewfile`:
  AeroSpace, Karabiner-Elements, Ghostty, Raycast, a Nerd Font and a
  set of command-line tools.
- It writes `~/.zshrc` as a short stub. A `~/.zshrc` you had before is
  backed up and copied to `~/.zshrc.local`, which keeps loading.
- It replaces `~/.config/karabiner/karabiner.json` to make Caps Lock the
  Super key. Karabiner-Elements runs as root; see
  [What it does not do](#what-it-does-not-do).
- It hides the native menu bar and turns off the four-finger swipe
  gestures of macOS, so the bar and the swipe daemon can take them.
- It builds its helpers into `~/.local/bin` and starts them as launch
  agents.

It records each change in a manifest, and `./uninstall.sh` reverses
exactly those changes.

## Upstream pull requests

The fixes this build offers upstream, and their state today.

<!-- upstream-prs:start -->
| PR | State | Title |
| --- | --- | --- |
| [#78](https://github.com/paulsp94/omacosy/pull/78) | OPEN | fix(install): restore the OmniWM chords right after the Karabiner reset |
| [#77](https://github.com/paulsp94/omacosy/pull/77) | MERGED | feat(chords): the browser and mail chords follow the macOS defaults |
| [#76](https://github.com/paulsp94/omacosy/pull/76) | OPEN | fix(ws-collapse): the restore never drops a live window's record |
| [#75](https://github.com/paulsp94/omacosy/pull/75) | MERGED | fix(ws-collapse): the fold map survives an OmniWM restart |
| [#73](https://github.com/paulsp94/omacosy/pull/73) | OPEN | fix(spawn): a Super+F window leaves fullscreen before a new window opens beside it |
| [#71](https://github.com/paulsp94/omacosy/pull/71) | MERGED | fix(ghostty): close a window without a prompt, as on Omarchy |
| [#70](https://github.com/paulsp94/omacosy/pull/70) | MERGED | fix(spawn): a burst waits for each window to settle before the next one |
| [#69](https://github.com/paulsp94/omacosy/pull/69) | MERGED | docs(readme): name the Screen Recording entries macOS checks |
| [#68](https://github.com/paulsp94/omacosy/pull/68) | OPEN | fix(uninstall): remove the apps omacosy installed, and show what fails |
| [#67](https://github.com/paulsp94/omacosy/pull/67) | MERGED | fix(uninstall): keep a backup of your settings, and say to open a new terminal |
| [#66](https://github.com/paulsp94/omacosy/pull/66) | MERGED | fix(uninstall): restore recorded booleans |
| [#65](https://github.com/paulsp94/omacosy/pull/65) | MERGED | docs(readme): one command to install or reinstall |
| [#64](https://github.com/paulsp94/omacosy/pull/64) | MERGED | feat(install): test the signing certificate and clear stale permissions |
| [#63](https://github.com/paulsp94/omacosy/pull/63) | MERGED | fix(ffm): stand down while OmniWM runs |
| [#62](https://github.com/paulsp94/omacosy/pull/62) | CLOSED | fix(ws-collapse): restore keeps the map until the windows are back |
| [#61](https://github.com/paulsp94/omacosy/pull/61) | MERGED | fix(toggle): on brings back the setup of this Mac's window manager |
| [#60](https://github.com/paulsp94/omacosy/pull/60) | MERGED | fix(bar): one routine follows the window manager, and the bar stays when none answers |
| [#59](https://github.com/paulsp94/omacosy/pull/59) | MERGED | feat(install): choose the window manager with --aerospace or --omniwm |
| [#58](https://github.com/paulsp94/omacosy/pull/58) | MERGED | fix(wm-switch): the switch to OmniWM checks itself and does not ask |
| [#56](https://github.com/paulsp94/omacosy/pull/56) | MERGED | fix(install): a re-run keeps OmniWM when it is the window manager |
| [#55](https://github.com/paulsp94/omacosy/pull/55) | MERGED | docs(readme): say where to run uninstall.sh and what to do after it |
| [#54](https://github.com/paulsp94/omacosy/pull/54) | MERGED | fix(overview): hold the thumbnail in a let, not a mutable var |
| [#53](https://github.com/paulsp94/omacosy/pull/53) | MERGED | fix(install): compile the gesture code as C11, not C99 |
| [#52](https://github.com/paulsp94/omacosy/pull/52) | MERGED | feat(files): yazi on Super+Shift+Y, opt-in with ./install.sh --yazi |
| [#51](https://github.com/paulsp94/omacosy/pull/51) | OPEN | fix(borders): the ring leaves the moment the app reports its window closed |
| [#50](https://github.com/paulsp94/omacosy/pull/50) | MERGED | fix(wallpaper): a screen connected later takes the current theme's picture |
| [#49](https://github.com/paulsp94/omacosy/pull/49) | MERGED | fix(overview): the overview keeps an old theme's colour and wallpaper |
| [#47](https://github.com/paulsp94/omacosy/pull/47) | MERGED | feat(bar): the icon-only pills are squares |
| [#46](https://github.com/paulsp94/omacosy/pull/46) | OPEN | fix(aerospace): Super+F comes out identical to Super+N |
| [#45](https://github.com/paulsp94/omacosy/pull/45) | OPEN | fix(omniwm): Cmd+H leaves the workspace, and the Dock icon does not return to it |
| [#44](https://github.com/paulsp94/omacosy/pull/44) | MERGED | fix(spawn): a burst of launch chords opens one window, 13 s late |
| [#42](https://github.com/paulsp94/omacosy/pull/42) | MERGED | fix(install): keep a real ~/.zshrc working, and out of the clone |
| [#41](https://github.com/paulsp94/omacosy/pull/41) | MERGED | fix(uninstall): stop relinking ~/.zshrc to one machine's dotfiles path |
| [#40](https://github.com/paulsp94/omacosy/pull/40) | MERGED | fix(install): quote the app names written to apps.conf |
| [#39](https://github.com/paulsp94/omacosy/pull/39) | MERGED | fix(install): match Karabiner's current agent label |
| [#37](https://github.com/paulsp94/omacosy/pull/37) | OPEN | fix(gesture): the trackpad arms at once when OmniWM is the manager |
| [#36](https://github.com/paulsp94/omacosy/pull/36) | CLOSED | fix(bar): a window-manager switch is noticed while the bar runs |
| [#35](https://github.com/paulsp94/omacosy/pull/35) | OPEN | fix(omniwm): one engine owns the four-finger swipe |
| [#34](https://github.com/paulsp94/omacosy/pull/34) | MERGED | fix(wm-switch): a config swap reaches the daemon that reads it |
| [#33](https://github.com/paulsp94/omacosy/pull/33) | MERGED | fix(gesture): the OmniWM swipe config points at another user's home |
| [#32](https://github.com/paulsp94/omacosy/pull/32) | MERGED | fix(omniwm): tiled windows keep a margin from the screen edges |
| [#31](https://github.com/paulsp94/omacosy/pull/31) | OPEN | feat(tiling): a workspace holding one window can fill the display |
| [#30](https://github.com/paulsp94/omacosy/pull/30) | OPEN | feat(bar): one command for autohide and the top gap it implies |
| [#29](https://github.com/paulsp94/omacosy/pull/29) | OPEN | feat(bar): split the top edge between this bar and the native one |
| [#28](https://github.com/paulsp94/omacosy/pull/28) | MERGED | fix(tiling): a new window chains only off a verified slot on its own workspace |
| [#27](https://github.com/paulsp94/omacosy/pull/27) | OPEN | fix(helper): split-hint stacks slots that are wider than tall |
| [#26](https://github.com/paulsp94/omacosy/pull/26) | MERGED | fix(aerospace): Super+Shift+F raises the Finder window instead of opening a new one |
| [#25](https://github.com/paulsp94/omacosy/pull/25) | OPEN | fix(config): size the top gap from the display's safe-area inset |
| [#24](https://github.com/paulsp94/omacosy/pull/24) | MERGED | fix(bar): take the bar height from the menu bar macOS draws |
| [#23](https://github.com/paulsp94/omacosy/pull/23) | OPEN | fix(ffm): a full-display overlay stops hover focus everywhere |
| [#22](https://github.com/paulsp94/omacosy/pull/22) | MERGED | fix(theme): the first Super+Shift+B after a theme change does nothing |
| [#21](https://github.com/paulsp94/omacosy/pull/21) | MERGED | fix(bar): the activity chip keeps the old theme's accent |
<!-- upstream-prs:end -->

## Fresh Mac

The same command installs and reinstalls. It clones the repo, or updates
the clone that is already there, then runs the installer:

```sh
d=~/.local/share/omacosy
if [ -d "$d/.git" ]; then git -C "$d" pull --ff-only; else git clone https://github.com/datarip/omacosy-daily.git "$d"; fi &&
cd "$d" && ./install.sh
```

Upstream omacosy already in `~/.local/share/omacosy`? Run its
`./uninstall.sh`, delete that folder, then run the command above.

Put your own apps and values in `~/.config/omacosy/settings.conf`.
`install.sh` applies them at every run; to apply a change at once, run
`omacosy-settings`. See [Your own settings](#your-own-settings).

This installs AeroSpace. For [OmniWM](#two-window-managers-omniwm-option-beta)
instead, run `./install.sh --omniwm`: AeroSpace is then not installed.
A later `install.sh` or `omacosy-update` keeps the window manager you
chose.

The clone location matters. Configs are symlinked into the repo, and
macOS privacy (TCC) blocks launchd services from reading `~/Documents`,
`~/Desktop` and `~/Downloads`. If you clone there anyway, the installer
falls back to copying configs; that still works, but edits then need an
`install.sh` re-run to apply.

The installer is idempotent. It installs Homebrew if missing, runs
`brew bundle`, compiles the helper binaries, generates the AeroSpace
config from your app choices, symlinks configs (backing up anything it
would replace), hides the native menu bar, applies the default theme,
and starts the services.

See [Permissions](#permissions) for the grants it asks of you, what
each one is used for, and what breaks without it. Karabiner-Elements
also asks you to approve its driver extension.

## Updating

```sh
omacosy-update          # pull, then re-run the installer
omacosy-update --check  # just say whether there is anything new
```

`install.sh` rebuilds only the binaries whose sources changed and
restarts their agents, so an update is a pull plus a re-run, and this
command wraps both. It refuses a clone with local edits, and refuses
one whose branch has diverged, rather than deciding either for you.

The installer resets the files your settings go into, and then runs
`omacosy-settings`, which puts your values back.

There is no background update check. The bar makes exactly one network
call (the weather), and a daemon polling GitHub on a timer would
quietly make that two. Nothing here contacts the network unless you
run it.

## Permissions

A window manager needs broad permissions, so here is the whole list:
every grant, which binary asks, what it is used for, and what you lose
by refusing it. Everything is refusable; the parts that depend on a
grant hide themselves rather than half-work.

| Grant | Who asks | What it does | Without it |
|---|---|---|---|
| **Accessibility** | AeroSpace *or* OmniWM, `omacosy-gesture`, `omacosy-bar` (reads the focused app's menus for the app-pill popup), `omacosy-ffm` (AeroSpace mode only), `omacosy-borders` (optional; hears the ringed window close) | Move, resize and focus other apps' windows. This is the tiling itself, and it is the broadest permission here. The focus ring uses it only to hear an app report that the ringed window is closing. | Nothing tiles. Not optional in practice. Without it for `omacosy-borders` alone, the ring leaves a window closed with Cmd-W about 0.25 s later. |
| **Input Monitoring** | Karabiner-Elements, `omacosy-gesture` (and OmniWM, under that option) | Karabiner reads keys to remap Caps Lock; `omacosy-gesture` reads raw trackpad contacts, because macOS 26 stopped carrying touch data in normal events. | No Super key, no swipe gestures. |
| **Screen Recording** | the program that first starts `omacosy-overview` ([see below](#permissions)), `omacosy-bar` | Overview captures a thumbnail per window for its cards, including windows the window manager has stashed offscreen, which a screenshot of the visible screen could not see. The bar samples the native menu bar's colour once, so an auto-hiding bar can paint it on the first frame instead of resolving a blur on every reveal. | Cards fall back to app icons and titles; the bar falls back to a live blur, which reveals more slowly and matches the menu bar less exactly. |
| **Bluetooth** | `omacosy-bar` | Reads adapter power and the paired-device list for the bluetooth pill and its menu. | The pill hides itself. |
| **Location** | `omacosy-bar` | Reads **only** the wi-fi network's name, which macOS classes as location data. No coordinate is ever requested; the authorisation itself is what unlocks `CWInterface.ssid()`. | The wi-fi popup's title row reads "wi-fi" instead of your network's name. Everything else is unaffected. |
| **Automation** | `omacosy-bar`, `theme-set` | Apple Events to **Spotify** (what is playing; play/pause/next from the media pill) and to **System Events** (sleep, lock and restart from the Apple menu; setting the wallpaper). | The media pill hides; those menu rows do nothing. |
| **Automation (Finder)** | `omacosy-finder-window` | Apple Events to **Finder**, to open a new Finder window on the current workspace (Super+Shift+F). macOS asks on the first press. | Super+Shift+F opens no window. |
| **Files and Folders** | `omacosy-bar` | Only if your clone lives in `~/Documents`, `~/Desktop` or `~/Downloads`. The bar reads its palette from the theme directory inside the repo, and macOS walls launchd agents off from those folders. | The bar **hangs at startup** waiting on the prompt. Clone to `~/.local/share/omacosy` and this never comes up. |

More on **Location**, because it sounds worse than it is: it buys
exactly one string. The bar requests authorisation and then reads
`ssid()`. It never asks for a position, holds no coordinate and starts
no location updates. Two things are required and neither alone is
enough: measured on macOS 26.3, an unbundled binary reads `nil` however
it is authorised, which is why the bar ships inside a minimal `.app`.
Refuse the grant and you lose the name, nothing else.

More on **Screen Recording**, because the entry that counts is not the
one you would expect. `omacosy-overview` takes the thumbnails, but it keeps
running in the background after it first opens, and macOS holds the program
that started it that first time responsible for every later opening too.
Observed in macOS's permission log on macOS 27.2, with the overview started
fresh each time: `omacosy-gesture` when a four-finger swipe up started it,
Karabiner-Elements (`Karabiner-Console-User-Server`) when Super+O started it
under OmniWM, and the overview's own entry not consulted. Those are the
entries to switch on. An overview first started from a terminal answers to
that terminal's entry until it stops. Under AeroSpace, Super+O does
something else, and the swipe is the only way in.

The bar asks for Screen Recording only when it auto-hides: it then samples
the native menu bar at a hover, once for each new wallpaper, and macOS
shows its dialog at the first one. With `autohide=off` it never asks.

### What it does not do

- **No telemetry, no analytics, no crash reporting.** Nothing is sent
  anywhere about you or this machine.
- **One network call**, ever: `https://wttr.in/?format=j1` on a long
  timer, for the weather pill. wttr.in infers your city from the IP the
  request arrives on; no coordinates are gathered or sent, and the bar
  holds no location API. Delete the weather pill and nothing leaves the
  machine.
- **The focus ring only listens.** `omacosy-borders` asks for
  Accessibility to hear an app report that the ringed window is closing.
  It reads the app's window list and registers for that one report on
  that one window. It never clicks, types, moves a window or reads what a
  window shows. Refuse the grant and the ring still works; a window
  closed with Cmd-W keeps its ring about 0.25 s longer.
- **omacosy's own binaries never run as root.** `install.sh` uses no
  sudo, installs no LaunchDaemon, and every helper it builds runs as
  you, in your login session.
- **Karabiner-Elements does run as root, and you should know that
  before installing.** It is a Homebrew dependency here, purely to turn
  Caps Lock into Super. It ships a DriverKit system extension plus
  daemons that run as root (`Karabiner-VirtualHIDDevice-Daemon`,
  `Karabiner-Core-Service`); that is what the driver-extension approval
  during install is. It is the most privileged thing this repo puts on
  your Mac, and it is third-party. Skip it if that trade is wrong for
  you; you lose the Super key and keep everything else.
- **Nothing here reads your keystrokes.** No omacosy binary opens a
  keyboard event tap. Only Karabiner sees keys, which is inherent to
  remapping one. `omacosy-gesture`'s event tap is gesture-only and
  listen-only (`1 << NSEventTypeGesture`, `kCGEventTapOptionListenOnly`),
  so it cannot see or alter a keystroke. Debug logs
  (`/tmp/omacosy-*.log`) carry window titles, app names and workspace
  numbers, never input.

### Keep your permissions across updates

macOS keeps each permission with the program's code signature. With an
Apple Development certificate on this Mac, `install.sh` signs every
helper with it, and an update keeps all your permissions. Without one,
macOS treats each rebuilt helper as a new app, and you grant its
permissions again after an update. omacosy works either way, and
`install.sh` ends with a warning while no certificate signs.

To add a certificate (free, needs an Apple ID):

1. Install Xcode from the App Store and open it once.
2. Xcode → Settings → Accounts: add your Apple ID.
3. Select it, then **Manage Certificates → + → Apple Development**.
4. Run `./install.sh` again, or `omacosy-update`.

You can do this before or after installing omacosy. The next install
signs with the certificate. macOS then asks once more for each
permission, because the signature changed; after that, no update asks
again.

If `install.sh` says the certificate cannot sign because Apple's G3
certificate is missing, answer `y` when it offers to add it, or add it
yourself:

```sh
cd /tmp && curl -fsSLO https://www.apple.com/certificateauthority/AppleWWDRCAG3.cer
security add-certificates -k ~/Library/Keychains/login.keychain-db AppleWWDRCAG3.cer
```

## Your own settings

Your values live in one file outside the clone,
`~/.config/omacosy/settings.conf`. `install.sh` copies it from
`config/settings.template.conf` once, and never overwrites it.

| Setting | What it sets |
| --- | --- |
| `TERMINAL`, `BROWSER`, `EMAIL`, `MUSIC`, `MESSENGER` | the apps the launch chords open. The defaults are Ghostty, Spotify and Slack; an empty `BROWSER` or `EMAIL` makes that chord follow the Mac's default web browser or mail app (how to change those is in [docs/customising.md](docs/customising.md)) |
| `APP_WORKSPACE_RULES` | the workspace an app's windows open on |
| `APP_FLOAT_RULES` | the windows that float instead of tile, under OmniWM |
| `RING_RADIUS`, `WINDOW_CORNER` | the focus ring radius, and the radius macOS draws window corners with. The `Super+K` cheatsheet, the popup panel under a bar pill and the Settings card (its theme thumbnails too) are drawn by Omacosy, so they follow the same corner; the bar's pills stay rounded |
| `AUTOHIDE` | whether the bar hides at rest: `off`, `on` or `auto`. `omacosy-bar-autohide` keeps it current, so your choice survives a reinstall |
| `SERIALIZE_APP_SPAWNS` | one window at a time from a burst of presses on the music and messenger chords |

`install.sh` regenerates the window-manager configs on each run, then
runs `omacosy-settings`, which writes your values back into them. After
an edit, run `omacosy-settings` to apply it at once. A file that still
equals the template is left alone, because it holds only examples. Set the apps in
`settings.conf`, not in `config/apps.local.conf`: `omacosy-settings`
rewrites that file. [docs/customising.md](docs/customising.md) explains
each setting, how to find an app's bundle id, and what survives a
re-install.

Your own shell config belongs in `~/.zshrc.local`. `install.sh` writes
`~/.zshrc` once, as a short stub that loads the repo's `zshrc`, and that
file loads `~/.zshrc.local`.

## Settings

`Super`+`,` opens a cheatsheet-style modal — the same card as `Super`+`k` —
with four tabs:

- **Options** — the window manager (AeroSpace or OmniWM), window corners,
  menu-bar mode, fullscreen, and auto-theme.
- **Workspaces** — which apps open on which workspace, per display, with a
  searchable picker. **Save** writes `~/.config/omacosy/settings.conf`, runs
  `omacosy-settings`, and drops any app rule you removed (under OmniWM that
  also prunes the manager's own rule).
- **Themes** — every theme as a card with its colours; click one to apply it.
- **Update** — `omacosy-update --check`, with the install button behind it.

It reads and writes the same files and commands as the CLI, so the window and
the shell can never disagree, and it follows the theme palette — its wordmark
included. `bin/omacosy-dashboard` is a single-instance launcher: the first
press opens it, later presses toggle the one window it owns.

## Commands

The commands you run:

| Command | What it does |
| --- | --- |
| `omacosy-settings` | applies `~/.config/omacosy/settings.conf`. `install.sh` runs it; run it yourself after an edit |
| `omacosy-update [--check]` | pulls this repo and runs `install.sh` again |
| `omacosy-wm-switch omniwm\|aerospace` | moves this Mac from one window manager to the other |
| `omacosy-toggle [on\|off]` | parks the whole setup without uninstalling it. No argument flips |
| `omacosy-bar-autohide on\|off\|auto\|status` | sets whether the bar hides at rest, and the top gap that goes with it |
| `omacosy-solo-fullscreen on\|off\|status` | a workspace with one tiled window fills the display. Off by default |
| `omacosy-window-corners [square\|round\|<radius>]` | sets the radius macOS draws window corners with; the `Super+K` cheatsheet, the popup panel under a bar pill and the Settings card (theme thumbnails included) follow it. No argument shows it |
| `omacosy-harvest-zshrc` | moves the lines installers appended to `~/.zshrc` into `~/.zshrc.local` |
| `omacosy-auto-theme on\|off\|status` | whether your own wallpapers become themes, with the terminal and its tools to match. `on desktop-only` themes the desktop alone. Off by default |
| `theme-set <name>` | switches the whole theme |
| `theme-next` | the next theme (Super+Shift+T) |
| `theme-bg-next [path]` | the next wallpaper of the theme, or the image you name (Super+Shift+B) |
| `omacosy-theme-switch theme\|wallpaper` | what Super+Shift+T and B run: the theme and the wallpaper change instantly and in sync (see Themes) |
| `omacosy-dashboard` | Super+,: opens Settings, or toggles it closed if it is already open |

The keys and the daemons run these. You do not need to run them:

| Command | Run by |
| --- | --- |
| `omacosy-ws` | Super+1..9, Super+Shift+1..9 and Super+Tab: the workspace slots of the focused display |
| `omacosy-cycle` | Alt+Tab, under AeroSpace: the windows of this workspace |
| `omacosy-float` | Super+S, under AeroSpace: the next floating window |
| `omacosy-layout` | Super+J, Super+- and Super+=, under AeroSpace: split direction and resize |
| `omacosy-spawn`, `omacosy-spawn-cmd` | the launch chords: one new window at a time |
| `omacosy-browser` | Super+Shift+Return: opens the macOS default web browser, or `BROWSER` when set |
| `omacosy-open` | opens a URL, a file, or a scheme (`mailto`) with its macOS default app. Super+Shift+E runs `omacosy-open mailto` for mail |
| `omacosy-finder-window` | Super+Shift+F: a new Finder window on this workspace |
| `omacosy-files` | Super+Shift+Y: yazi in a new terminal window |
| `omacosy-auto-theme apply` | `theme-set`, `theme-bg-next` and `omacosy-theme-switch`, when auto-theme is on |
| `omacosy-theme-switch` | Super+Shift+T and Super+Shift+B: the instant, synced switch |
| `omacosy-focus-guard` | AeroSpace, on each workspace change: it undoes a switch that an app caused by activating itself |
| `omacosy-ws-collapse` | the bar, when a display is unplugged or plugged back in |
| `omacosy-karabiner-omniwm` | `omacosy-wm-switch` and `omacosy-settings`: the launch chords under OmniWM |

## What's inside

| Piece | Tool | Config |
|---|---|---|
| Tiling WM | [AeroSpace](https://github.com/nikitabobko/AeroSpace) *or* [OmniWM](https://github.com/BarutSRB/OmniWM) via `omacosy-wm-switch` | `config/aerospace/aerospace.template.toml`, `config/omniwm/settings.template.toml` |
| Super key | [Karabiner](https://karabiner-elements.pqrs.org) (Caps Lock → cmd+ctrl+alt) | `config/karabiner/` (copied, not symlinked — TCC) |
| Status bar, popups, shade | `omacosy-bar` (self-compiled launchd agent, one process draws all of it) | `helper/bar.swift`, `config/bar.conf` (live copy: `~/.config/omacosy/bar.conf`) |
| Window borders + fullscreen shroud | `omacosy-borders` (self-compiled launchd agent) | `helper/borders.swift`, `config/borders.conf` |
| Focus follows mouse | `omacosy-ffm` (self-compiled launchd agent; parked under OmniWM, whose native ffm takes over) | `helper/ffm.swift`, `config/ffm-ignore` |
| Trackpad gestures | `omacosy-gesture` (self-compiled launchd agent; engine absorbed from [aerospace-swipe](https://github.com/acsandmann/aerospace-swipe), MIT) | `helper/gesture/`, `config/gesture/` (live copy: `~/.config/omacosy/gesture.json`) |
| Workspace overview | `omacosy-overview` (self-compiled resident daemon) | `helper/overview.swift` |
| One window, whole display | `omacosy-solo` (self-compiled resident daemon; runs only while switched on) | `helper/solo.swift`, `bin/omacosy-solo-fullscreen` |
| Dwindle split direction | AeroSpace: `on-focus-changed` hook running `omacosy-helper split-hint`; OmniWM: native dwindle + a preselect in `omacosy-spawn` (omarchy's right/below insertion) | `config/aerospace/aerospace.template.toml`, `helper/main.swift` |
| Workspace / window navigation | `omacosy-ws`, `omacosy-cycle`, `omacosy-float`, `omacosy-wm-switch`; under OmniWM all of it rides `omacosy-omni`, a held-socket IPC client | `bin/`, `helper/gesture/omniwm.c` |
| Terminal look & spawn size | Ghostty (hidden titlebar; new windows spawn small so tiling never flashes full-screen) | `config/ghostty/config` |
| Park/restore the stack | `omacosy-toggle` | `bin/omacosy-toggle` |
| System glue | `omacosy-helper` (self-compiled) | `helper/main.swift` |
| Your settings | `omacosy-settings` | `config/settings.template.conf` (live copy: `~/.config/omacosy/settings.conf`) |
| Settings | `omacosy-dashboard` (self-compiled accessory app on Super+,) | `helper/dashboard.swift`, `bin/omacosy-dashboard`, `helper/assets/omacosy-logo.*` |
| Prompt | starship | `config/starship.toml` |
| Shell | zsh | `zsh/zshrc` + your `~/.zshrc.local` |
| CLI stack | fzf, eza, zoxide, ripgrep, bat, lazygit, btop | wired in `zsh/zshrc` |
| More terminal tools, opt-in | `./install.sh --tui-tools` installs neovim, git-delta, tmux and fastfetch, the tools `omacosy-auto-theme` colours beyond the ones above. Only the missing ones are installed, and `uninstall.sh` removes what it added | `install.sh` |
| Files, opt-in | yazi on `Super+shift+y`. `./install.sh --yazi` installs it with fd, poppler, resvg and sevenzip for its previews; `--yazi-full` adds ffmpeg-full, imagemagick-full and the symbols font. Without either flag nothing is installed and the key stays unbound | run `yazi` in a terminal |

Why so much of it is self-built:

- **AutoRaise** broke on macOS 26 (cooperative activation), so
  `omacosy-ffm` focuses windows through the same SkyLight calls
  AeroSpace uses.
- **aerospace-swipe** broke because CGEvent taps stopped carrying
  multi-touch data on macOS 26.3. We fixed it (raw MultitouchSupport
  frames) and offered the fixes upstream as
  [#29](https://github.com/acsandmann/aerospace-swipe/pull/29) and
  [#30](https://github.com/acsandmann/aerospace-swipe/pull/30); once
  the daemon had to serve both window managers and carried more of
  our patches than upstream commits, the engine moved in-tree as
  `omacosy-gesture` (MIT notice kept).
- **JankyBorders** keeps a bitmap per window and costs hundreds of MB.
  `omacosy-borders` strokes one CAShapeLayer that the WindowServer
  rasterizes, driven by SkyLight notifications for focus, move and
  resize, so the ring glides with drags without polling. With
  Accessibility it also hears an app report that the ringed window is
  closing, so the ring is gone before the window starts to fade.
- **Mission Control** cannot see AeroSpace's virtual workspaces, so a
  workspace overview cannot be had any other way than
  `omacosy-overview` capturing them itself.
- **`omacosy-helper`** covers wallpaper setting (System Events
  scripting half-broke in macOS 14+), CoreAudio output switching,
  IOBluetooth control, cursor position, per-display notch detection,
  the default browser and mail app bundle ids, and the dwindle split hint.
- **`omacosy-bar`** holds the window model in memory and subscribes to
  the system's own publishers: SkyLight for window churn, IOBluetooth
  for connects, SCDynamicStore for the network, IOPS for battery,
  CoreAudio for volume, DisplayServices for brightness, Spotify's own
  broadcast for the track. It polls for nothing macOS announces; its
  only timers are the weather fetch and the clock. A workspace switch
  repaints in 2.5 ms because it asks no one anything; the shell bar it
  replaced took 164 ms to answer the same event.

## The bar

One process draws all of it: bar, popups and sliders are surfaces of
`helper/bar.swift`. Transparent bar, everything a flat radius-4 pill.
A popup stays open while the pointer is anywhere in the bar or the
popup, and closes when it is in neither. The bar hides itself when a
window takes the whole display, and comes back if you put the pointer
on the very top edge, so brightness and volume stay reachable mid-film
without leaving fullscreen. The climb happens only when a fullscreen
window actually covers the bar — otherwise the top edge belongs to the
auto-hidden native menu bar, which reveals ABOVE the bar and stays
clickable (app menus were unreachable before that fix). It drops back
behind everything when the pointer leaves. Under OmniWM the bar simply
stays visible in its reserved strip and never plays this game.

If the native menu bar ever gets stuck revealed over the bar (a
Tahoe bug, most often poked by a Focus mode's menu-bar icon),
`killall SystemUIServer` resets it.

### Hiding the bar, and the split top edge

`~/.config/omacosy/bar.conf` holds three settings. The bar reads the
file when it starts.

| Setting | Values | What it does |
| --- | --- | --- |
| `autohide` | `off` (default), `auto`, `on` | `off` keeps the bar visible on every display. `auto` keeps it visible on a notched display, and hides it at rest on a display with no notch or on an external monitor. `on` hides it at rest everywhere |
| `split` | `0.0` to `1.0` | where the top edge divides, as a fraction of the display width. The left part belongs to this bar, the right part to the native menu bar |
| `slide` | milliseconds, or `off` | how long the bar takes to slide in and out, on a display where it hides |

Change `autohide` with `omacosy-bar-autohide on|off|auto`. It also sets
the top gap for windows, and restarts the bar. An edit by hand sets the
bar but not the gap.

### Workspace icons

You can set workspace icons in the optional
`~/.config/omacosy/workspace-icons.conf` file. Each non-comment line has one
workspace name, an equals sign, and either one Unicode scalar or a reverse-DNS
application bundle identifier.

```
1 = ★
14 = ◆

4 = com.apple.Safari
```

The bar first uses a configured icon. It then uses the icon of the sole app on
that workspace, and finally shows the workspace's last digit. Exact workspace
names win. In this example, workspace `14` uses `◆`, not the `4` shorthand.
The shorthand applies only to multi-digit, all-numeric workspace names ending
in `1` through `9` when they have no valid exact declaration.

The bar reads the file once at startup. To apply an edit, restart it with:

```sh
launchctl kickstart -k "gui/$(id -u)/com.omacosy.bar"
```

Malformed lines are logged and ignored. A well-formed bundle identifier that
does not resolve to an installed app is unavailable. It blocks shorthand for
that exact workspace, then the bar falls back to the sole app or the digit.
Image paths are unsupported because the bar resolves configured app icons at
startup and does no config-file or image-file I/O while it draws.

- **Apple menu**: the REAL one, read over Accessibility — About This
  Mac, System Settings, Recent Items (drills in, with app and
  file-type icons resolved locally since AX exposes none), Force Quit,
  the power verbs — plus omacosy's Next Theme at the bottom. Hidden
  hold-Option duplicates are collapsed; falls back to a hand-rolled
  list without the Accessibility grant.
- **App menus**: clicking the front-app pill drops that app's actual
  menu bar into a popup — File/Edit/… drill into their real items,
  nested submenus included, and clicking a leaf performs it directly
  via AXPress with no native menu ever appearing. Shortcuts sit
  right-aligned; enabled-state is not rendered because apps validate
  menu items only when a menu opens, so closed-menu reads lie. Menus
  taller than the screen scroll. The one thing the auto-hidden native
  bar still owned, gone.
- **Workspaces**: one segmented capsule per monitor showing only that
  monitor's workspaces; accent pill on the focused one; click to jump.
- **Media**: prev / play-pause / next + track title (Spotify). Centered
  on flat displays, left cluster on notched ones (per-display notch
  detection via `NSScreen.safeAreaInsets`), hidden when Spotify isn't
  running.
- **Bluetooth**: device menu (click to connect/disconnect), power
  toggle.
- **WiFi**: the pill is the icon alone; the popup names the network and
  adds ip and router, signal with a verdict, link rate and security
  generation, channel with its band and width. The name is in the popup
  because an SSID can be arbitrarily wide, and on a notched display a
  long one pushed the right cluster under the notch. The name needs the
  Location grant (see [Permissions](#permissions)).
- **Weather**: wttr.in, cached details popup.
- **Volume**: scroll adjusts, click opens slider + output-device menu,
  right-click mutes.
- **Brightness**: scroll adjusts, click opens a slider (DisplayServices,
  no deps). Scrolling past 0 keeps going: a **shade** dims the display
  below its hardware minimum by scaling gamma, so there is no overlay
  window in the z-order and screenshots come out normal. It survives
  sleep/wake and it reaches external displays, which have no backlight
  API. Gamma is reset when the setting process exits, so a crash or an
  uninstall restores the screen by itself.
- **Battery** / **Clock** (calendar popup) / **Activity** (floating
  btop).
- **Floats**: appears only while the workspace holds floating windows;
  click surfaces the next one.

## Keybindings — Super = hold Caps Lock

Karabiner remaps Caps Lock to `cmd+ctrl+alt` (a combo macOS never
uses), so omarchy's scheme works letter-for-letter without breaking
typing or app shortcuts. Caps Lock tapped alone is Escape.

| Chord | Action |
|---|---|
| **Navigation** | |
| `Super+1..9` | switch to this display's workspace N |
| `Super+tab` / `Super+shift+tab` | next / previous workspace, within this display's set |
| `Super+b` | back and forth between the last two workspaces |
| `Alt+tab` / `Alt+shift+tab` | cycle windows **on this workspace**, floats included |
| `Ctrl+Alt+tab` | cycle focus between displays |
| `Super+arrows` | focus the window in that direction |
| `Super+s` | surface the next floating window (and bring the cursor) |
| **Moving windows** | |
| `Super+shift+arrows` | AeroSpace: move the window in that direction. OmniWM: **swap** tiles (`ctrl+opt+shift+arrows` stacks into the neighbor as a group instead) |
| `Super+shift+1..9` | move the window to workspace N and follow it |
| `Super+shift+o` | throw the window to the same slot on the other display |
| `Super+shift+space` | throw the WHOLE workspace to the other display |
| **Layout** | |
| `Super+w` | close window |
| `Super+t` | toggle floating |
| `Super+j` | toggle split direction |
| `Super+-` / `Super+=` | resize |
| `Super+f` | fullscreen — on notched displays the camera strip is blacked out so it reads as true fullscreen, while the window stays in its workspace (swipes still reach it) |
| `Super+n` | native macOS fullscreen (a separate Space — outside the workspace model, avoid unless an app needs it) |
| `Super+r` | resize mode (`h/j/k/l`, `-`/`=`, `esc`) — AeroSpace only; OmniWM has no binding modes |
| `Super+shift+;` | service mode (`esc` reload, `r` flatten, `⌫` close others) |
| **Apps and system** | |
| `Super+enter` / `Super+shift+enter` | terminal / browser |
| `Super+space` | launcher (Raycast; the OmniWM option opens OmniWM's command palette instead) |
| `Super+shift+f` / `+m` / `+g` | files / music / messenger (set in `settings.conf`) |
| `Super+shift+y` | yazi, the terminal file manager, in a new window (after `./install.sh --yazi` or `--yazi-full`) |
| `Super+shift+t` | next theme |
| `Super+shift+b` | next wallpaper of the current theme |
| `Super+shift+l` | lock the screen |
| `Super+k` | keybinding cheatsheet (this table, rendered from the config) |
| `Super+,` | Settings — options, app→workspace assignment, and a theme gallery |

![The keybinding cheatsheet — every binding, parsed from aerospace.toml](docs/screenshots/cheatsheet.jpg)

Screenshots, clipboard and app switching stay macOS's own
(`Cmd+Shift+3/4/5`, `Cmd+C/V`, `Cmd+Tab`). `Alt+Tab` above is the
*window*-scoped switcher macOS lacks.

**On the modifier space.** omarchy layers `Super+Ctrl` and `Super+Alt`
on top of `Super`. This setup cannot: Super IS `cmd+ctrl+alt`, so those
modifiers are already spent and Shift is the only layer left, two
against omarchy's four. Bindings that would collide are re-homed by
mnemonic (lock is `Super+Shift+L`, not `Super+Ctrl+L`), and the
overflow lives in binding modes instead.

Each display owns an independent set of nine workspaces, omarchy style:
main holds 1–9, secondary holds 11–19. Same last digit means the same
slot, and the bar and overview render only the slot digit. `Super+N`
switches the focused monitor's slot N (via `omacosy-ws`);
`Super+Shift+N` moves the window to that slot; `Super+Shift+O` throws
the window to the same slot on the other monitor. Windows open on the
workspace you're on; nothing is auto-assigned by app.

**Unplugging folds the second display's workspaces into the first.**
AeroSpace parks 11–19 on the remaining display, but `Super+N` and
`Super+Tab` only match single-digit slots, so without help every window
on a secondary workspace would be stranded where no keybinding reaches
it. On a monitor-count change the bar runs `omacosy-ws-collapse`: each
occupied guest workspace empties into the lowest free 1–9 slot,
occupied slots are never touched, and every moved window is recorded
with its origin. Plug the display back in and they go home
individually, so anything you opened while undocked stays put.

## Themes

`theme-set <name>` switches everything at once: bar, borders, wallpaper
on every display, and any terminal that follows omarchy's
`~/.config/omarchy/current/theme` convention (the upstream author's does).
`Super+Shift+T` cycles.

`Super+Shift+T` and `Super+Shift+B` run `omacosy-theme-switch`, which makes
the switch instant and in sync. macOS takes about 4.5 s to paint a new desktop
picture; omacosy instead draws the chosen wallpaper itself, in a desktop-level
window, in about 0.15 s (`helper/overlay.swift`), recolours the bar and the
focus ring the moment it is on screen, and only then asks macOS for the real
wallpaper — hiding the overlay when macOS has caught up with the same picture,
so the handoff is invisible. A few seconds with no further press
(`OMACOSY_SETTLE_SECONDS`, default 4) is taken as the choice; the wallpaper
request itself is never stacked. It works the same for the four shipped themes
and for `custom`. [docs/theme-switching.md](docs/theme-switching.md) has the
problem, the rejected options and the measurements.

Each theme ships omarchy's full wallpaper set. `Super+Shift+B` (or
`theme-bg-next`) cycles through them; `theme-bg-next <path>` sets any
image you like. Switching themes restarts at the theme's first
wallpaper.

Themes: `tokyo-night`, `catppuccin`, `gruvbox`, `osaka-jade`. Each
`themes/<name>/` holds `colors.toml` (omarchy's 22-color palette),
`sketchybar.sh` / `borders.sh` (bar and ring colors; the file keeps its
omarchy name and format, and the ring uses the theme accent, omarchy's
own convention), and `backgrounds/` (wallpapers from omarchy's
MIT-licensed theme packs). Copy a directory to add one.

### Your own wallpapers, with colors to match

Four themes means four color schemes, and they were chosen to suit their
own wallpapers. A picture of your own gets whichever scheme you were on,
which is how you end up with osaka-jade's dark green pills on a red bar.

Turn on `omacosy-auto-theme`, put images in `~/Pictures/wallpapers`, and
`Super+Shift+T` reaches a fifth theme, `custom`, after the four. Inside it **every wallpaper is its own
theme**: `Super+Shift+B` moves to the next picture and recomputes the bar
color, the pill color, the icon color and the focus ring from it.

```sh
omacosy-auto-theme on
mkdir -p ~/Pictures/wallpapers      # install.sh already made it
cp ~/Downloads/walls/*.jpg ~/Pictures/wallpapers/
omacosy-custom-theme status
```

That is the whole setup. It is off on a new install. While it is off, or
while the directory is empty, the cycle stays four themes and nothing is
printed.

**How the colors are chosen.** The bar's own background keeps the
measurement omacosy already makes to match the real macOS menu bar — a
34-point strip across the top of the picture. Everything else reads the
**whole** image, because a strip across the top is usually sky and says
nothing about the picture: a power-station photo measures near-grey at the
top and orange everywhere else.

The picture's hue is its pixels weighted by saturation x value cubed. The
cube is fitted, not chosen — a moonlit scene that is 61% dark purple by
area and 7% bright blue glow reads as blue, and only the cube agrees.

**A pastel wallpaper gets a pastel theme, a saturated one gets neon.** The
accent's saturation follows the picture rather than a fixed floor: across a
48-image folder, pastel wallpapers average an accent saturation of 0.53 and
saturated ones 0.77.

**The bar and the focus ring always name the same color.** They differ only
in treatment — the ring keeps more of the picture's saturation and stays
brighter, because it is a stroke on a window rather than text on a pill.

Every color is then checked against the surface it sits on and corrected
until it passes: first the luminance gaps the four shipped themes hold,
then WCAG contrast ratios for anything a person reads — text on a pill at
4.5:1, the focused workspace number and the cheat sheet's own text. Pills
are measured against the real wallpaper behind the bar, in eight slices, so
a bright sky in the middle cannot hide a pill sitting on dark slate. The
derivation is pure: the same image always yields the same palette, so a
cached theme and a fresh one cannot disagree.

Optionally, a day and a night theme that follow the macOS appearance, so
sunrise and sunset are macOS's schedule rather than a second one:

```sh
omacosy-custom-theme day   gruvbox
omacosy-custom-theme night osaka-jade/1-glowing-city.webp
omacosy-custom-theme follow on
```

Either may name a shipped theme, one of its wallpapers, or a file of your
own. Full manual: **[docs/derived-themes.md](docs/derived-themes.md)**.

### Auto-theme: the terminal and its apps follow your wallpaper

Off by default, because a terminal's colors are a personal choice:

```sh
omacosy-auto-theme            # status
omacosy-auto-theme on         # custom themes, and the apps follow them
omacosy-auto-theme on desktop-only   # custom themes for the bar, ring and cheat sheet only
omacosy-auto-theme off        # stock themes only; your own colors come back
```

**Desktop only.** `on desktop-only` keeps the custom themes for the desktop,
the bar, the focus ring and the cheat sheet, and leaves the terminal and every
tool in its own colors, as on a stock theme. `on` alone turns the apps back
on. It is stored as `apps = on | off` in `~/.config/omacosy/auto-theme.conf`.

`on` makes the **custom** theme appear (see *Your own wallpapers* above).
While a custom theme is on screen, the terminal and its apps take the colors
of the same wallpaper. The 16 terminal colors are derived from the picture,
and red, green, yellow, blue, magenta and cyan keep their hue, so an error
message still reads as red.

A **stock** theme changes none of this. When one is on screen, every generated
file is removed and each app shows its own colors again.

| App | What follows the wallpaper | When it changes | One-time setup |
| --- | --- | --- | --- |
| Ghostty | background, the 16 colors, cursor, selection | at once, also in new windows | none |
| Starship | the prompt, by role (`err`, `ok`, `accent`, …) | at once | none |
| `ls`, `eza` | the directory color, in the accent | at once | none |
| yazi | directories and folder icons in the accent, markers, borders | when it opens | none |
| btop | meters from green to red, highlights in the accent, the terminal's own background | at once | none |
| Neovim | a base16 colorscheme from the palette, the terminal's own background | at once | `on` links the plugin |
| bat, delta | code in the 16 colors | at once | none |
| delta | the added and removed line strips, in the palette's green and red | at once | `[include] path = ~/.config/omacosy/delta.gitconfig` in `~/.gitconfig` |
| fzf, lazygit, fastfetch | accent, borders, selection | the next time they run | none |
| tmux | the band behind the bar takes the terminal's background; a theme plugin keeps its pills | at once | `source-file -q ~/.config/omacosy/tmux-theme.conf` at the end of `tmux.conf` |

With an `applier` (below), Ghostty, Starship and fzf are that tool's job, and
omacosy hands it the palette instead.

Ghostty makes only the terminal's own background transparent, so btop, Neovim
and the tmux band draw on that background instead of painting a color: their
background shows the same transparency as the shell.

neovim, git-delta, tmux and fastfetch are not in the base install;
`./install.sh --tui-tools` adds them.

**Recommended with auto-theme: a transparent terminal.** Add these two lines
to your own Ghostty config, `~/Library/Application Support/com.mitchellh.ghostty/config`,
then quit and reopen Ghostty (on macOS a reload does not change the
transparency):

```
background-opacity = 0.85
background-blur = 10
```

The wallpaper then shows through the terminal, and btop, Neovim and the tmux
band show it too. Use your own config, not omacosy's `~/.config/ghostty/config`:
an update replaces omacosy's file and keeps yours.

**What it writes**, all under `~/.config/omacosy/` unless the path says otherwise:

| File | Read by |
| --- | --- |
| `term-palette.env` | the palette of the theme on screen, `OMACOSY_BG`, `OMACOSY_P0` … `OMACOSY_P15` |
| `ghostty-theme.conf` | Ghostty, through `config-file = ?…` in the shipped config. The `?` makes it optional |
| `starship.toml` | Starship, generated from `config/starship-omacosy.template.toml`, whose colors are named by role |
| `term-env.sh` | `zsh/zshrc`: `EZA_COLORS`, `LS_COLORS`, `BAT_THEME=ansi` for bat and delta, `LG_CONFIG_FILE` for lazygit, a `fastfetch` function with the colors, and, when omacosy owns the prompt, `STARSHIP_CONFIG` and fzf's colors. Your own values come back on a stock theme |
| `lazygit-theme.yml` | lazygit's theme keys only, added after your own `config.yml` |
| `tmux-theme.conf` | tmux, for the band behind the bar |
| `delta.gitconfig` | delta's line strips |
| `nvim/palette.lua` | Neovim, through `config/nvim/omacosy-theme.lua` |
| `~/.config/yazi/theme.toml` | yazi. A `theme.toml` of your own is never overwritten |
| `~/.config/btop/themes/omacosy.theme` | btop, with `color_theme = "omacosy"` in `btop.conf`. A stock theme puts back btop's own theme |

Your own Ghostty config is read **after** the generated one, so a color you
set by hand still wins. `omacosy-auto-theme off` deletes the generated files,
and the next window reads your own colors again.

**Handing the terminal to another tool.** `~/.config/omacosy/auto-theme.conf`:

```
auto-theme = on | off         off by default
apps = on | off               on by default; off: the desktop only (on desktop-only)
applier = <command>           empty: omacosy writes the config itself
```

When `applier` names a command, omacosy writes the palette and then runs
`<command> <palette-file> <theme-label>`, and writes no terminal config of its
own. On a stock theme it runs `<command> --clear <theme-label>`, so that tool
puts back its own colors. That is the hand-off point for a tool that already
owns your terminal's colors, and it keeps exactly one writer: two programs
writing the same Ghostty file would fight, and the winner would depend on the
order the includes are read.

**What it does not touch:** any other program with colors of its own.

Full manual: **[docs/auto-theme.md](docs/auto-theme.md)**.

### yazi and your editor

`Super+Shift+Y` opens **yazi**, a file manager in a terminal window. It tiles
like any other window and wears the theme's colors. It is opt-in:
`./install.sh --yazi` installs it and binds the key, and `--yazi-full` adds
video and raw-photo previews; without a flag, neither happens.

Opening a file from yazi hands it to `$EDITOR`. omacosy sets no editor, so an
unset `$EDITOR` means `vi`, and Vim opened on a **directory** shows its own
file browser, netrw:

```
" Netrw Directory Listing                    (netrw v184)
"   /Users/you/some-dir
```

That screen is Vim, not yazi. Leave it with `:q`. Nothing is modified unless
you type a netrw command such as `D` (delete) or `R` (rename).

To use another editor, set it in `~/.zshrc.local`, which is yours and survives
an update:

```sh
export EDITOR="nvim"        # or: zed --wait, code --wait, hx, micro
```

Only yazi, without touching the shell, is `~/.config/yazi/yazi.toml`:

```toml
[opener]
edit = [ { run = 'nvim "$@"', block = true } ]
```

omacosy writes `~/.config/yazi/theme.toml` while a custom theme is on screen, and
never writes `yazi.toml`, so that file is yours alone.

## Tiling: dwindle

![Three terminals in a dwindle layout — README, git log and btop — accent border ring on the focused one](docs/screenshots/tiling.jpg)

AeroSpace natively inserts new windows as equal siblings, so three
windows become three columns. Hyprland's dwindle splits the focused
window along its own longer edge instead: a new window lands beside a
wide window and below a tall one. That is the omarchy feel, and on a
3440-wide display it is also the difference between a usable third
window and three narrow strips.

AeroSpace cannot express that rule. Its config language has no window
geometry; the format variables are ids, titles and container layouts,
with no width or height anywhere. So the direction is decided in code:
the `on-focus-changed` hook runs `omacosy-helper split-hint`, which
reads the newly focused window's frame and issues
`aerospace split horizontal` or `vertical` on it.

The timing is what matters. The hint lands before the next window
exists, so AeroSpace places that window correctly in its first pass.
An earlier version was a daemon that re-nested windows after AeroSpace
had already placed them, and you could see it: the screen laid out
twice, about 250ms apart. What remains now is the new window's own
first frame, which appears about 150ms before AeroSpace tiles it. No
window manager can place a window that does not exist yet.

Two implementation notes. `enable-normalization-flatten-containers` is
off, because it dissolves the very container `split` creates (AeroSpace
prints a warning saying so if you try). And the hint waits for the
window's frame to hold still before reading it, then names its window
with `--window-id` instead of trusting "the focused window". Both guard
against the same thing: a new window fires the hook too (it takes focus
on open), at a moment when its frame is still the app's default shape
and another window may grab focus before the hint lands. One hook
covers both hover and keyboard focus: AeroSpace notices the focus
`omacosy-ffm` moves, even though ffm moves it through SkyLight.

Manual control (Super+J flips, resize, float) works unchanged.

Floats get a rescue path, because macOS will not keep them on top:
z-order is per app, not per window, so a float sinks behind whichever
app you focus next, and pinning it would need a private call with SIP
off. Instead the bar grows a pill whenever the focused workspace holds
floats, and **Super+S** or a click on that pill surfaces the next one
and brings the cursor with it.

### One window, whole display

Opt-in, off by default: `omacosy-solo-fullscreen on`. A workspace holding a
single tiled window then shows it the way `Super+F` does: the whole display,
no outer gaps. A second window drops back to normal tiling, and closing down
to one goes full again. `omacosy-solo-fullscreen off` hands back every window
it took, and `status` says what it is holding.

`Super+F` keeps its meaning. The rule acts on a workspace's window COUNT, and
pressing `Super+F` changes no count, so a deliberate choice is never undone a
second later; the workspace returns to automatic at the next open or close. A
window counts as the rule's own only when `fullscreen on --fail-if-noop`
actually changed it, so a window you fullscreened by hand is never taken over
and never handed back. Floating windows, and the windows of hidden apps, do
not count — a workspace *showing* one window behaves as one window.

The rule runs in `omacosy-solo`, a small resident daemon under launchd,
rather than on a focus hook. It has to be resident: waking from sleep fires
no focus change and no window event at all, and only a live process receives
the sleep and wake notifications needed to put fullscreen back. It is also
its own process rather than part of `omacosy-bar`, because a Swift trap
cannot be caught and nothing about fullscreening a window should be able to
take the menu bar down. Switched off, the daemon exits and nothing runs.

Under OmniWM there is nothing to switch: its dwindle layout already gives a
lone window the frame its own `Super+F` uses (`singleWindowFit = "fill"`).

## Two window managers (OmniWM option, beta)

AeroSpace is the default. [OmniWM](https://github.com/BarutSRB/OmniWM)
is a newer, signed-and-notarized tiling WM with a native dwindle
layout — omacosy can run on either, and switching is one command:

```sh
omacosy-wm-switch omniwm      # installs OmniWM on first use, then
                              # switches with a guarded handover
omacosy-wm-switch aerospace   # the way back, and installs AeroSpace
                              # on first use after ./install.sh --omniwm
```

The switch checks itself: it snapshots your windows, stops AeroSpace,
starts OmniWM and waits until OmniWM manages them. On a first switch,
grant OmniWM's permissions when macOS asks. If OmniWM does not take
over within 2 minutes, or you press Ctrl-C, the switch reverts to
AeroSpace and puts your windows back.

Under OmniWM everything keeps working — bar, overview (with
type-to-search), gestures, keybindings, themes — and the dwindle
layout is native, so the split-hint machinery below simply isn't
needed there. What changes: OmniWM draws the focus border (themed by
theme-set), app-launching chords run through Karabiner rules that the
switch installs and removes, and Super+Space opens OmniWM's command
palette instead of Raycast.

Under OmniWM the plumbing changes shape: `Super+N`/`Hyper+N` route
through Karabiner into `omacosy-omni` (a held-socket IPC client) so
slots resolve on the display under your cursor — OmniWM's native
hotkeys are name-global and would always hit the main set — at the
cost of ~40 ms per chord. `Hyper+arrows` swap tiles; OmniWM's own
directional move *stacks* windows into a group, which stays available
on `ctrl+opt+shift+arrows`.

Honesty section: the upstream author daily-drives this option (0.6.4,
docked multi-monitor, each display running its own nine workspaces),
and this build runs it daily on one display. docs/omniwm-port.md
carries a ledger of upstream
quirks found while porting — read it before assuming a weird layout is
omacosy's fault. AeroSpace remains the longer-tested default.

## Focus follows mouse & swipes

Under the OmniWM option this daemon is parked: OmniWM's native
focus-follows-mouse (with warp-to-focus and hover-raise) replaces it.
Under AeroSpace, `omacosy-ffm`: hover focuses, with no raise over floating windows, so
floats stay in front. It is event-driven off mouse movement, so a
parked cursor never steals focus from a launching window. It never
changes focus during drags, and never through an always-on-top panel:
hovering a Touch ID prompt leaves focus exactly where it is instead of
falling through to the window beneath. Per-app opt-out lives in
`config/ffm-ignore` (omarchy's JetBrains-style exception).

4-finger swipes left/right switch workspaces on the display under the
cursor (native-Spaces semantics), with wrap-around, on any trackpad.
The system's own 4-finger gestures are disabled by `macos-defaults.sh`
so Mission Control never fights the daemon; `uninstall.sh` restores
them.

## Workspace overview

![Workspace overview — live preview cards over the zoomed-out wallpaper, chips for empty workspaces](docs/screenshots/overview.jpg)

4-finger **swipe up**: the wallpaper breathes in behind a dim wash and
every non-empty workspace of the cursor's monitor gets a card
(per-display Mission Control semantics), with live window previews
(ScreenCaptureKit, composed into the tile layout), app icons, and an
accent ring on the focused workspace. Click a card or press its digit
to jump; empty workspaces show as small chips, and digits work for them
too. **Swipe down**, Esc, or a backdrop click dismisses. It is a
resident daemon, so it opens instantly.

**Type to search** while it is open: a search pill filters cards to
matching window titles and apps as you type, `Enter` jumps to the
first hit, `Esc` clears the filter before it closes the overview.
Digits type into an active filter instead of switching, so numeric
titles stay reachable.

**Drag a card** to reorganize: the row makes room as you move, and the
drop slides everything between the old and new position over by one.
Workspaces cannot be renamed or resequenced in either WM (the name is
the position), so what actually moves is their windows, which means a
split layout inside a moved workspace comes back as a flat row. Dropping a
card on an empty chip moves that workspace there instead.

## Parking the setup

`omacosy-toggle off` returns to a vanilla Mac in one command (AeroSpace
stops managing, all daemons and the bar stop) without uninstalling;
`omacosy-toggle on` brings everything back. No argument flips.

## Memory use

About **157MB** of physical footprint (what Activity Monitor calls
Memory) across WM, bar, three background daemons, the gesture daemon and
Karabiner, measured by upstream, docked to a second display. Resident set size reads
~322MB, but RSS counts each process's share of the same shared system
frameworks more than once, so footprint is the number to compare.
(Measured in AeroSpace mode; OmniWM mode is a wash — its ~44MB WM
replaces AeroSpace plus the parked `omacosy-ffm`.)
Largest first:

| | footprint | RSS |
|---|---|---|
| `omacosy-overview` | 36MB | 46MB |
| `omacosy-bar` | 32MB | 55MB |
| AeroSpace | 24MB | 85MB |
| Karabiner (4 processes) | 24MB | 61MB |
| `omacosy-borders` | 19MB | 29MB |
| `omacosy-gesture` | 13MB | 22MB |
| `omacosy-ffm` | 10MB | 24MB |

On one display the same set measured ~155MB; the bar and the border
overlay each draw per-screen, and AeroSpace carries a second workspace
set. The figures move with uptime. `omacosy-overview` caches a
half-resolution capture per window shown, so it starts near 9MB and
settles around 37MB; it plateaus there rather than climbing, because
the cache is refiltered to the visible set on each open. AeroSpace
drifts the other way, reading higher the longer it runs. Packaging the
bar as an `.app` (which is what unlocks the wi-fi network name) cost
about 1MB; the bundle is a directory and an Info.plist, not a second
copy of anything.

## Back to a normal Mac

```sh
~/.local/share/omacosy/uninstall.sh
```

If you cloned omacosy somewhere else, run `<your clone>/uninstall.sh`.
The script finds the clone from its own path.

Manifest-driven: `install.sh` records what this machine actually gained
(Homebrew packages that weren't already present, cloned repos, every
`defaults` key's prior value), and `uninstall.sh` removes and restores
exactly that. Tools and settings you had before omacosy are never
touched. Pre-manifest installs fall back to a conservative teardown
that leaves all Homebrew packages in place.

Before it removes anything, the script saves your omacosy settings, the
record of this install and your `karabiner.json` in
`~/omacosy-backup-<date>-<time>/`. It prints that folder's path at the end.

During the script, it lists the apps and tools omacosy installed and asks
which ones to keep. Use the arrow keys to move, space to mark or unmark
an item, `a` to mark all, and enter when you are done. The script then
shows what it keeps and what it removes: `y` continues, `n` goes back to
the list. It removes the others and names each one it could not remove.

After the script, do these steps in this order:

1. Close the terminal window and open a new one. The old window still
   uses omacosy's shell setup, and some of the programs it calls are gone.
2. Optional: delete the clone. The script keeps it, and nothing breaks
   if it stays. With the clone kept, a reinstall is one command. To
   delete it, run `rm -rf <your clone>`. The default clone is
   `~/.local/share/omacosy`.
3. If omacosy installed Homebrew, the script says so. To remove Homebrew
   too, use Homebrew's own uninstall script. Homebrew packages you had
   before omacosy stay installed.
4. In System Settings → General → Login Items, remove AeroSpace if it is
   still in the list.
5. If you used the Caps Lock dictation shortcut in the Claude desktop app,
   turn it on again in Claude's settings. The install removed it.
6. Optional: in System Settings → Privacy & Security, delete the entries
   omacosy added. The script removes those of the bar, `omacosy-gesture`
   and `omacosy-ffm`. The others stay, `omacosy-overview` among them. The
   [permissions table](#permissions) lists each one and the program it
   names. They do nothing once the programs are gone.
7. Log out and log in again. The native menu bar comes back fully only
   then.

To stop omacosy for a while without removing it, see
[Parking the setup](#parking-the-setup).

## License & credits

MIT (see `LICENSE`). This is a build of
[omacosy](https://github.com/paulsp94/omacosy) by Paul Spende, whose
copyright notice `LICENSE` keeps. Standing on: [omarchy](https://omarchy.org)
(the whole idea, plus MIT-licensed theme palettes and wallpapers),
[AeroSpace](https://github.com/nikitabobko/AeroSpace),
[Karabiner-Elements](https://karabiner-elements.pqrs.org),
[aerospace-swipe](https://github.com/acsandmann/aerospace-swipe) (MIT;
its gesture engine lives on here as `omacosy-gesture`, notice kept in
`helper/gesture/`).
