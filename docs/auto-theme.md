# Auto-theme: the terminal and its apps follow your wallpaper

Off by default. `omacosy-auto-theme on` turns on the custom theme, where every
wallpaper in `~/Pictures/wallpapers` is a theme of its own
([derived-themes.md](derived-themes.md)). While a custom theme is on screen,
the terminal and its apps take the colours of the same wallpaper: Ghostty, the
Starship prompt, the directory colour in `ls` and `eza`, yazi, btop, Neovim,
bat, delta and its line strips, fzf, lazygit, fastfetch, and the band behind
tmux's bar.

```sh
omacosy-auto-theme            # status: switch, custom theme, applier, palette file, btop, Neovim
omacosy-auto-theme on
omacosy-auto-theme on desktop-only
omacosy-auto-theme off
```

**Desktop only.** `on desktop-only` sets `apps = off`: the custom themes stay,
and the bar, the focus ring and the cheat sheet follow the wallpaper, but on a
custom theme `apply` does what it does on a stock theme for the apps. Every
generated file is removed and each app shows its own colours. `on` alone sets
`apps = on` again and links the Neovim plugin back.

`theme-set`, `theme-bg-next` and `omacosy-theme-switch` call
`omacosy-auto-theme apply <label>` after they repoint
`~/.config/omarchy/current/theme`. Nothing else calls it, except tmux, which
runs `omacosy-auto-theme tmux-bar` from its own config.

The two theme keys run `omacosy-theme-switch` (README, Themes), which applies
this in step with the instant wallpaper switch: the terminal and its tools are
told at the same moment the bar and ring are recoloured, instead of waiting
for macOS to paint the wallpaper.

**A stock theme is never changed.** When one of the shipped themes is on
screen, `apply` removes every generated file, puts back the settings it
replaced (btop's `color_theme`, the shell variables), resets the colours of
open terminals (OSC 104, 110, 111, 112) or runs `<applier> --clear <label>`,
and makes Ghostty and tmux read their own config again. Each app shows its own
colours.

- [1. Where the colors come from](#1-where-the-colors-come-from)
- [2. The palette file](#2-the-palette-file)
- [3. Who applies it](#3-who-applies-it): yazi, btop, delta's line strips
- [4. Windows that are already open, and the next one](#4-windows-that-are-already-open-and-the-next-one)
- [5. Neovim](#5-neovim)
- [6. tmux](#6-tmux)
- [7. What it does not touch](#7-what-it-does-not-touch)

**Recommended: a transparent terminal.** The apps above draw on the terminal's
own background so that Ghostty's transparency shows through them. Ghostty is
opaque by default; two lines in your own Ghostty config,
`~/Library/Application Support/com.mitchellh.ghostty/config`, turn it on:

```
background-opacity = 0.85
background-blur = 10
```

On macOS, Ghostty applies a change to `background-opacity` only after a full
restart, so quit and reopen it. This is a setting of yours, not of
auto-theme: it stays the same on every theme.

## 1. Where the colors come from

`omacosy-term-palette <theme-dir> <out.env> [<label>]` reads the theme that is
on screen and writes one palette file.

**A shipped theme** (`themes/<name>/`) carries `colors.toml`, a designer's own
16 colors, and they are used as they are. `omacosy-auto-theme` never asks for
this: a stock theme leaves the terminal alone.

**A computed theme** (a wallpaper of your own) has no `colors.toml`, so the 16
colors are derived from the palette `omacosy-derive` already wrote:

- Six hues carry meaning and stay FIXED: red 29, green 142, yellow 95, blue
  258, magenta 328, cyan 210 degrees in OKLCH. Each is nudged at most 15
  degrees toward the accent, so the set belongs to the picture without red
  ceasing to be red. This is where `pywal` and its kin fail: filling all 16
  slots from the image makes a beige photograph print errors in beige.
- Their chroma follows the picture, so a pastel wallpaper gets a pastel set.
- Every one is then pushed in lightness until it reaches 4.5:1 against the
  background.
- The background itself is the theme's surface, pushed AWAY from the text until
  the text reads at 8:1. A terminal cannot be mid-tone: a dusty pink bar at
  relative luminance 0.19 would force every color to run to white or black.
  Which way it runs is the theme's own answer — light text means a dark
  terminal.

## 2. The palette file

`~/.config/omacosy/term-palette.env`, one `KEY='#rrggbb'` per line, meant to be
sourced by a shell.

| Key | What it is |
| --- | --- |
| `OMACOSY_THEME` | the theme's name, for a label |
| `OMACOSY_BG`, `OMACOSY_FG` | terminal background and foreground |
| `OMACOSY_CURSOR`, `OMACOSY_CURSOR_TEXT` | cursor and the text under it |
| `OMACOSY_SEL_BG`, `OMACOSY_SEL_FG` | selection |
| `OMACOSY_P0` … `OMACOSY_P15` | the 16 ANSI colors, by number |
| `OMACOSY_BLACK` … `OMACOSY_BR_WHITE` | the same 16, by name |
| `OMACOSY_ACCENT`, `OMACOSY_ALT` | the theme's accent, and a second one |
| `OMACOSY_OK`, `OMACOSY_WARN`, `OMACOSY_ERR`, `OMACOSY_INFO`, `OMACOSY_PEACH` | the roles a prompt uses, so a template says `err` and not `red` |
| `OMACOSY_MUTED` | dimmed text |
| `OMACOSY_IS_DARK` | 1 on a dark terminal, 0 on a light one |

No surface ramp is written. A consumer that wants one derives it from the
background, the foreground and `OMACOSY_MUTED`.

## 3. Who applies it

`~/.config/omacosy/auto-theme.conf` (`term.conf`, the file of the old name
`omacosy-term-sync`, is read once and moved into it):

```
auto-theme = on | off         off by default
apps = on | off               on by default; off = `on desktop-only`
applier = <command>           empty: omacosy writes the config itself
```

**omacosy as the applier** writes these files, under `~/.config/omacosy/`
unless the path says otherwise. The ones marked *both modes* are also written
when another tool is the applier, because no terminal palette reaches them:

| File | Read by |
| --- | --- |
| `ghostty-theme.conf` | Ghostty, through `config-file = ?~/.config/omacosy/ghostty-theme.conf` in the shipped config |
| `starship.toml` | Starship, generated from `config/starship-omacosy.template.toml` plus the palette |
| `term-env.sh` | `zsh/zshrc`: `EZA_COLORS`, `LS_COLORS`, `BAT_THEME=ansi` (bat and delta then draw in the 16 colours), `STARSHIP_CONFIG`, fzf's `--color` added to your own `FZF_DEFAULT_OPTS`, `LG_CONFIG_FILE` for lazygit, and a `fastfetch` function that adds the colours as options. Your own values are kept and put back on a stock theme, and a `fastfetch` function of your own is never replaced |
| `lazygit-theme.yml` | lazygit, as the last file in `LG_CONFIG_FILE`: only the `gui.theme` keys, so your own `config.yml` keeps everything else. lazygit refuses to start when a named file is missing, so your `config.yml` is named only when it exists. *Both modes* |
| `delta.gitconfig` | delta's line strips, through an include in `~/.gitconfig`. *Both modes* |
| `tmux-theme.conf` | tmux, through `source-file -q` at the end of `tmux.conf`. *Both modes* |
| `nvim/palette.lua` | Neovim, through `config/nvim/omacosy-theme.lua`. *Both modes* |
| `~/.config/yazi/theme.toml` | yazi. *Both modes* |
| `~/.config/btop/themes/omacosy.theme` | btop, through `color_theme = "omacosy"` in `btop.conf`. *Both modes* |

The `?` makes Ghostty's include optional, so a machine that never turns this on
reads no such file. Your own config is read after it, so a color you set by hand
still wins.

**Another tool as the applier.** omacosy runs `<command> <palette-file>
<theme-label>` on a custom theme and `<command> --clear <theme-label>` on a
stock one, and writes no terminal config of its own, not even a stale file
an include could pick up. It still writes `term-env.sh` for the directory
color and `BAT_THEME`, which are nobody else's job, and it still repaints open
windows. The prompt and fzf's colours are left to the applier.

This exists to keep exactly ONE writer. Two programs writing Ghostty's config
would fight, and the winner would depend on the order the includes are read.

### yazi

yazi ignores the terminal's 16 colours: its default theme names its own blues
and cyans, so a themed terminal still showed a blue file list. The generated
`theme.toml` gives it the palette, and a directory — name and folder glyph —
wears the ACCENT, the colour the bar and the focus ring already name.

yazi MERGES a user theme over its defaults, so only the keys written here
change; the icon table's 650 entries for file types stay. Two things learned
from yazi's own error messages, kept so they are not learned twice:

- A filetype rule needs `url` or `mime`; `is` only qualifies one of them, and a
  directory is the url pattern `*/`. Without that, yazi refuses to start:
  "at least one of `url` or `mime` must be specified".
- The folder GLYPH is coloured by the icon table, not by the filetype rules.
  Colouring the rules alone leaves accent names next to blue icons.

A `theme.toml` of your own is never touched: the file is only written when it
is missing or when its first line says omacosy wrote it. `omacosy-auto-theme
off` deletes ours and leaves yours.

yazi reads its theme when it starts, so a window that is already open keeps
the old colours until you reopen it.

**Why not palette slot names, which would update live.** Tried, and it works:
a name means "the terminal's slot N", and repainting those slots is what this
script already does to every live window, so an open yazi recoloured on a theme
switch. Two things sank it. A slot is only the NEAREST of 16 — gruvbox's orange
accent lands on yellow — and the CHOICE is frozen at startup: a window opened
under gruvbox keeps drawing "yellow", which after a switch to catppuccin is
cream. The colour stayed live and stopped being the accent. The palette file
still carries `OMACOSY_ACCENT_ANSI`, the nearest slot by name, for a consumer
that would rather have live colour than an exact one.

### btop

btop paints itself from a theme file too. The CPU, temperature and memory
meters run from `OK` to `WARN` to `ERR`, because load has a meaning, as red
does in the terminal. The highlights take the accent. Box outlines, dividers
and meter backgrounds are the accent or the dimmed text, mixed toward the
background. `main_bg` is left empty, so btop draws on the terminal's own
background: Ghostty makes only that background transparent, and draws any
colour a program paints fully solid.

On a custom theme, `color_theme` in `btop.conf` is set to `omacosy`, and
btop's own value is kept in `~/.local/state/omacosy/btop-color-theme`. A
stock theme puts it back, but only while `btop.conf` still names `omacosy`: a
theme chosen in btop's menu since then stays. An `omacosy.theme` of your own,
without the first line omacosy writes, is never touched.

A running btop changes at once: `SIGUSR2` makes it read `btop.conf` and the
theme file again. That also matters when it quits, because btop writes
`btop.conf` on exit. After the reload, the value it writes is the new one.

### delta's line strips

`BAT_THEME=ansi` colours the code in a diff, but the strips behind added and
removed lines are delta's own dark green and dark red. On a light terminal
they sit under dark text, which then cannot be read. delta reads those styles
only from git's config, so omacosy writes `~/.config/omacosy/delta.gitconfig`
and `~/.gitconfig` includes it:

```
[include]
	path = ~/.config/omacosy/delta.gitconfig
```

git skips an include whose file is missing, so on a stock theme delta uses its
own colours again.

Each strip is built in OKLCH, not mixed in sRGB. A mix of the palette's green
into a blue background came out teal, and red into a light background came
out brown: tested on 10 wallpapers, both stopped reading as added and removed.
So the hue is the palette's green or red held within 8 degrees of pure green
(142) and pure red (29), the lightness is the background's moved by 0.07 away
from black or white (at least 0.29 on a dark terminal), and the chroma is
0.075, lowered only as far as sRGB requires. The word-level highlights use a
step of 0.14 and a chroma of 0.12. On those 10 wallpapers the text on a strip
reads at 7.4:1 or more.

## 4. Windows that are already open, and the next one

Ghostty reads its config when it starts, not when it opens a window. So after
every switch `omacosy-auto-theme` sends `SIGUSR2` to each Ghostty process,
which makes it read its config again; without that, a window opened after a
switch took the colours Ghostty had at its start.

A config file does not repaint a window that is open, so `omacosy-auto-theme`
also writes the colors to the tty of every shell as escape sequences (OSC 4,
10, 11 and 12). The terminal consumes them, so a shell running Neovim or yazi
is unharmed.

The prompt needs one more step. Starship builds its prompt string when it draws
a prompt, so the one on screen keeps the old colors. `omacosy-auto-theme` sends
SIGWINCH, and `zsh/zshrc` traps it, re-runs Starship's own precmd and redraws
the line.

Two details that cost an afternoon, kept here so they are not learned twice:

- A login shell is called `-zsh`, not `zsh`. A filter matching `zsh` or
  `/bin/zsh` finds nothing, and no window is repainted.
- Karabiner runs a keybinding with `PATH=/usr/bin:/bin`. A command in
  `~/.local/bin` is not found there, so anything looked up by name alone
  silently does nothing when the switch comes from the keyboard.

## 5. Neovim

`omacosy-auto-theme on` links `config/nvim/omacosy-theme.lua` into
`~/.config/nvim/lua/plugins/`, the folder a lazy.nvim config (LazyVim,
kickstart) loads plugins from. `off` removes the link. A file of your own with
that name is never replaced or removed. Without that folder nothing is linked,
and the palette file below is still there to use by hand.

**The palette.** On a custom theme omacosy writes
`~/.config/omacosy/nvim/palette.lua`. It returns one table: the theme name,
`dark`, the roles (`bg`, `fg`, `accent`, `alt`, `ok`, `warn`, `err`, `info`,
`peach`, `muted`), the 16 colours as `ansi`, and a `base16` table. Any config
can read it with `dofile()`.

**The colourscheme.** The plugin gives `base16` to `mini.base16`, which lazy.nvim
installs the first time. Functions wear the accent; strings, keywords and
constants keep the six fixed hues of section 1, so red stays red in the editor
too.

| base16 | from |
| --- | --- |
| base00 | background |
| base01 | background mixed 8% toward the text |
| base02 | selection background |
| base03 | `MUTED` (comments) |
| base04 | `MUTED` mixed halfway to the text |
| base05 | foreground |
| base06, base07 | the brightest of the 16 |
| base08, base0A, base0B, base0C, base0E | red, yellow, green, cyan, magenta |
| base09 | `PEACH` |
| base0D | `ACCENT` |
| base0F | `ALT` |

`terminal_color_0` to `terminal_color_15` are set too, so a `:terminal` matches
the one outside.

`Normal`, `NormalNC`, `SignColumn`, `EndOfBuffer`, `LineNr` and `FoldColumn`
get no background, so the editor shows the terminal's own background and its
transparency. Popups, the status line and selections keep their colour, to
stay readable.

**Following a switch.** The plugin watches `~/.config/omacosy/nvim/`, the
folder and not the file, because omacosy replaces the file with a rename and
a watch on a file stops after the first rename. On a stock theme the file is
deleted, and the plugin puts back the colourscheme your config set at startup.
It applies its own at `VimEnter`, after your config, so that scheme is the one
it remembers.

**One plugin only.** Some terminal-theme tools ship a Neovim plugin that also
sets the colourscheme from a palette. Two such plugins fight over it, so keep
one of the two.

## 6. tmux

tmux keeps its own bar, from `tmux.conf` or a theme plugin. Only the band
behind the bar changes: the colour it is painted on becomes the terminal's
background.

A theme plugin such as tmux-tokyo-night writes fixed colours into the text of
the bar and takes no colours from outside. So `omacosy-auto-theme tmux-bar`,
run by tmux itself, reads the band colour from `status-style` after the bar is
drawn. As a background it becomes `default`, the terminal's own, with its
transparency. As a text colour it draws the arrows between a pill and the
band, so it becomes the terminal's background colour. The pills keep their
colours: without knowing what each colour means, moving them to the palette
is a guess.

On each switch omacosy reads `tmux.conf` again in every running server, so the
bar is first what it draws on its own, and then the band is replaced. On a
stock theme only the first step runs, and the band comes back.

A server that starts later needs one line at the end of `tmux.conf`, after a
plugin manager's `run` line:

```
source-file -q ~/.config/omacosy/tmux-theme.conf
```

`-q` keeps tmux silent while the file does not exist: on a stock theme, and
while auto-theme is off.

## 7. What it does not touch

Any other program with colours of its own. `omacosy-auto-theme off`
deletes the generated files; the next window reads your own colours again.
