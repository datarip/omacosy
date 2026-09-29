# This fork

A daily-driver build of
[paulsp94/omacosy](https://github.com/paulsp94/omacosy). It runs every
day on one machine: a MacBook Air M1 with macOS 27 and one 1440x900
display with no notch, under AeroSpace and OmniWM both.

Every fix and feature in the first two tables below is also offered
upstream as a pull request. The fork is where they run today. The pull
requests are where they can become everyone's. See
[those pull requests](https://github.com/paulsp94/omacosy/pulls?q=is%3Apr+author%3Adatarip).

## What it adds

### Fixes, each also a pull request upstream

| Area | Fix | Files |
| --- | --- | --- |
| Tiling | split-hint waits for a window frame to settle after a close, and predicts only from a live layout | `helper/main.swift` |
| Tiling | split-hint puts a slot that is wider than tall side by side, not stacked | `helper/main.swift` |
| Top gap | the gap comes from the display's safe-area inset, so a display with no notch reserves no notch | `helper/main.swift`, `install.sh`, `config/aerospace/` |
| Bar | the bar height comes from the menu bar macOS draws | `helper/bar.swift` |
| Bar | the activity chip takes the new theme's accent | `helper/bar.swift` |
| Bar | a window-manager switch is noticed while the bar runs | `helper/bar.swift` |
| Focus | a full-display overlay no longer stops focus-follows-mouse | `helper/ffm.swift` |
| Finder | Super+Shift+F opens a new Finder window on the current workspace | `bin/omacosy-finder-window` |
| Theme | the first Super+Shift+B after a theme change works | `bin/theme-bg-next` |
| OmniWM | tiled windows keep a margin from the screen edges | `config/omniwm/` |
| OmniWM | one engine owns the four-finger swipe | `bin/omacosy-wm-switch`, `config/omniwm/` |
| OmniWM | a config swap reaches the daemon that reads it | `bin/omacosy-wm-switch` |
| OmniWM | an update or a re-run of `install.sh` keeps OmniWM, and does not start AeroSpace beside it | `install.sh` |
| Overview | the overview follows a theme or wallpaper change, open or closed, and shows the desktop's wallpaper | `helper/overview.swift` |
| Gestures | the OmniWM swipe config no longer points at another user's home | `config/gesture/` |
| Gestures | the trackpad arms at once when OmniWM is the manager | `helper/gesture/` |
| Undock | the fold map survives an OmniWM restart, so folded windows still return to their workspace | `bin/omacosy-ws-collapse` |
| Undock | the restore never drops a live window's record when no window manager answers | `bin/omacosy-ws-collapse` |

### Features, each also a pull request upstream

| Feature | How to use it |
| --- | --- |
| The top edge is split: the left part belongs to this bar, the right part to the native menu bar | `split` in `~/.config/omacosy/bar.conf` |
| One command sets bar auto-hide and the top gap that goes with it | `omacosy-bar-autohide on\|off\|auto` |
| A workspace holding one tiled window fills the display. Off by default | `omacosy-solo-fullscreen on\|off` |

### Only in this fork

| Change | Where |
| --- | --- |
| A fifth theme, `custom`, where **every wallpaper is its own theme**: turn on `omacosy-auto-theme`, drop images in `~/Pictures/wallpapers`, and `Super+Shift+B` recomputes the bar, pill, icon and ring colours from each picture. The hue comes from the whole image weighted by saturation x value cubed, a pastel wallpaper gets a pastel theme and a saturated one gets neon, the bar and the ring always name the same colour, dark pills take the picture's shadow hue, and WCAG contrast checks keep the bar text, the focused workspace number and the cheat sheet legible across 66 wallpapers. Auto-theme off or an empty directory hides it entirely, and the four shipped themes are untouched. [docs/derived-themes.md](docs/derived-themes.md) | `helper/derive.swift`, `bin/omacosy-custom-theme`, `bin/theme-set`, `bin/theme-next`, `bin/theme-bg-next` |
| Auto-theme, off by default (`omacosy-auto-theme on`, or `on desktop-only` for the desktop alone): the custom theme appears, and while one is on screen the terminal and its apps follow the wallpaper: Ghostty (background, 16 colours, also in new windows), the Starship prompt, `ls` and `eza`, yazi, btop, Neovim (a base16 colourscheme through a linked plugin), bat, delta and its line strips, fzf, lazygit, fastfetch, and the band behind tmux's bar. The 16 colours keep six fixed hues, so red stays red; delta's strips stay green and red on every wallpaper. btop, Neovim and tmux draw on the terminal's own background, so Ghostty's transparency shows. A stock theme is never changed: the generated files go and every app shows its own colours. Open apps change at once. `applier` in `auto-theme.conf` hands the palette to another tool instead, with `--clear` on a stock theme, so only one program ever writes the terminal config. `./install.sh --tui-tools` adds neovim, git-delta, tmux and fastfetch. [docs/auto-theme.md](docs/auto-theme.md) | `helper/term-palette.swift`, `bin/omacosy-auto-theme`, `bin/omacosy-custom-theme`, `config/nvim/omacosy-theme.lua`, `config/starship-omacosy.template.toml`, `zsh/zshrc`, `install.sh` |
| Instant, synced theme switching: `Super+Shift+T`/`Super+Shift+B` draw the chosen wallpaper themselves in a desktop-level window in ~0.15 s and recolour the bar and the focus ring the moment it is on screen, so colours and wallpaper always arrive together; macOS's real wallpaper is applied underneath and the overlay is removed when it has caught up, with no visible flicker. No polling: the handoff is a filesystem event, and the only wait is one settle timer. [docs/theme-switching.md](docs/theme-switching.md) | `helper/overlay.swift`, `bin/omacosy-theme-switch`, `bin/omacosy-karabiner-omniwm`, `config/aerospace/aerospace.template.toml` |
| yazi, the terminal file manager, on `Super+Shift+Y` under both window managers, with its previewers in the Brewfile | `bin/omacosy-files`, `Brewfile`, `config/aerospace/aerospace.template.toml`, `bin/omacosy-karabiner-omniwm` |
| A day and a night theme following the macOS appearance, so sunrise and sunset stay macOS's schedule. Either may name a shipped theme, one of its wallpapers, or a file of your own | `bin/omacosy-appearance`, `install.sh` |
| Your own values live in `~/.config/omacosy/settings.conf`, outside the clone. `omacosy-settings` applies them after every install | `bin/omacosy-settings`, `config/settings.template.conf` |
| `omacosy-window-corners` sets the radius macOS draws window corners with, and keeps the focus ring concentric | `bin/omacosy-window-corners` |
| `omacosy-spawn-cmd` opens one window at a time from a burst of presses on the music and messenger chords | `bin/omacosy-spawn-cmd` |
| `omacosy-harvest-zshrc` moves installer appends out of `~/.zshrc` into `~/.zshrc.local` | `bin/omacosy-harvest-zshrc` |
| `~/.zshrc` is a real stub file, not a link into the clone. An existing `~/.zshrc` is copied to `~/.zshrc.local` first, and `uninstall.sh` puts it back | `install.sh`, `uninstall.sh` |
| OmniWM's `settings.toml` is generated from `settings.template.toml`, so OmniWM's rewrites of it never make the clone dirty | `install.sh`, `config/omniwm/` |
| Both window-manager configs are **seeded once and never overwritten**. Your keybindings, and everything OmniWM writes through its own interface, survive every install. When the shipped default moves you are told, and given the path to diff against | `install.sh` (`seed_config`) |
| The focus ring hides when a layer-0 window in front of the focused window reaches its stroke, instead of painting over it. Awaits #51, then a pull request | `helper/borders.swift` |

## Known limitations

- **A floating window (System Settings, a settings / About panel, a
  permission prompt) cannot be kept above a tiled window.** On OmniWM, mouse
  focus raises the hovered tile over the float, and no setting changes that;
  an external helper cannot reorder another app's window either (macOS needs
  Dock injection with SIP off). This needs a change in OmniWM. Under AeroSpace
  the same wall is by design — see [docs/why-aerospace.md](docs/why-aerospace.md)
  — and `omacosy-float` (`Super+S`) surfaces a buried float. The focus ring no
  longer paints over a window that covers the focused one.

## Your settings

| File | What it holds | Survives `install.sh` |
| --- | --- | --- |
| `~/.config/omacosy/settings.conf` | app choices, app-to-workspace rules, float rules, ring radius, window corners | yes |
| `~/.config/omacosy/bar.conf` | `autohide`, `split`, `slide` | yes |
| `~/.config/omacosy/solo-fullscreen` | its presence turns the one-window fullscreen on | yes |
| `config/aerospace/aerospace.toml` | your AeroSpace keybindings and layout | yes — seeded once, then yours |
| `config/omniwm/settings.toml` | everything OmniWM saves for itself | yes — seeded once, then OmniWM's |

The last two are written once and then left alone. When a new version ships a
different default, `install.sh` keeps yours and prints the `diff` command to
compare against `~/.local/state/omacosy/<name>.shipped`.

`docs/customising.md` explains them, and what `install.sh` resets.

## Installing this instead of upstream

```sh
git clone https://github.com/datarip/omacosy-daily.git ~/.local/share/omacosy &&
cd ~/.local/share/omacosy && ./install.sh
```

Then edit `~/.config/omacosy/settings.conf` and run `omacosy-settings`.

## Going back to upstream

Run `./uninstall.sh` in the clone, then install upstream as its README
says. `uninstall.sh` removes what `install.sh` added. It keeps
`~/.config/omacosy/settings.conf` if you edited it.
