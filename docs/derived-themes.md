# Themes computed from your own wallpapers

This page describes the `custom` theme: a directory of your own images
where **every wallpaper is its own theme**. Its bar colour, pill colour,
icon colour and focus ring are computed from the picture rather than read
from a file.

It also covers the optional day and night switch, which follows the macOS
appearance.

- [1. The problem](#1-the-problem)
- [2. What a theme actually is](#2-what-a-theme-actually-is)
- [3. What the four shipped themes have in common](#3-what-the-four-shipped-themes-have-in-common)
- [4. How the colours are computed](#4-how-the-colours-are-computed)
- [5. How a computed theme reaches the screen](#5-how-a-computed-theme-reaches-the-screen)
- [6. Setting it up](#6-setting-it-up)
- [7. Configuration](#7-configuration)
- [8. Day and night](#8-day-and-night)
- [9. Command reference](#9-command-reference)
- [10. What it will not do](#10-what-it-will-not-do)
- [11. Troubleshooting](#11-troubleshooting)

---

## 1. The problem

omacosy ships four themes, each a directory of matching wallpapers with
one hand-picked colour scheme. `Super+Shift+T` moves between themes and
`Super+Shift+B` moves between the wallpapers inside one.

Four themes means four colour schemes. Every wallpaper inside
`gruvbox/backgrounds/` gets gruvbox's orange accent, whichever of them is
showing.

That works because those wallpapers were chosen to go with those colours.
It stops working the moment you use a picture of your own.

`theme-bg-next ~/Pictures/wallpapers/red-sunset.png` sets the wallpaper
and nothing else. The menu bar tints itself from the new picture, because
macOS tints the real menu bar from the desktop and omacosy follows it. The
pills, the icons and the focus ring keep the colours of whichever theme
you were on. Measured on a fully saturated red wallpaper: an orange-red
bar carrying osaka-jade's dark green pills. Legible, and wrong.

There is a second, quieter version of the same problem. Every shipped
wallpaper is dark along its top edge — measured, luminance 0.09 to 0.28.
The shipped label colour is near-white because of that. Use a bright
picture and the bar goes bright while the text stays near-white.

The fix is to stop reading the colours from a file and compute them from
the picture.

---

## 2. What a theme actually is

A theme is a directory. The shipped ones live in `themes/`:

```
themes/osaka-jade/
├── backgrounds/        the wallpapers
├── colors.toml         omarchy's 22-colour palette, for terminals
├── sketchybar.sh       the bar's colours
└── borders.sh          the focus ring's colour
```

Only `sketchybar.sh` and `borders.sh` are read by omacosy.
`colors.toml` is there for terminals that follow the omarchy convention;
nothing in this repo reads it.

Between them those two files declare nine keys. **They are five colours.**
In all four shipped themes:

```
BAR_COLOR   == BAR_BG_SOLID     duplicate name for the bar background
ICON_COLOR  == LABEL_COLOR      icons and text are one colour
ACCENT      == ACTIVE_COLOR     the focus ring IS the accent
```

So a computed theme has five numbers to produce:

| colour | where you see it |
| --- | --- |
| `BAR_BG_SOLID` | the focused workspace number, the popups and the cheat sheet, **computed separately**, see 4.7 |
| `ITEM_BG` | the pill behind each item |
| `MUTED` | unfocused workspace numbers, the clock |
| `LABEL_COLOR` | text and icons |
| `ACCENT` | the focused workspace chip, and the app name's text |
| `ACTIVE_COLOR` | the focus ring, **computed separately**, see 4.6 |

`RED`, `GREEN` and `YELLOW` are also declared. They carry meaning — a low
battery has to read as red — so they are fixed and the wallpaper gets no
say in them.

---

## 3. What the four shipped themes have in common

The derivation is not invented. It reproduces the structure the shipped
themes already have, measured across all four.

**Each theme is one hue.** Converting every key to hue, saturation and
value:

| theme | hue range across all keys | spread | the one exception |
| --- | --- | --- | --- |
| tokyo-night | 221–235 | **14°** | none |
| catppuccin | 226–240 | 14° | accent at 267, +27° out |
| osaka-jade | 143–158 | 15° | label at 64, +79° out |
| gruvbox | 20–43 | 23° | bar is neutral grey |

One hue held to about fifteen degrees, with at most one deliberate escape.

**The lightness ladder is shared.** Reading value down the five colours:

| | catppuccin | gruvbox | osaka-jade | tokyo-night | shape |
| --- | --- | --- | --- | --- | --- |
| bar background | 0.18 | 0.16 | 0.11 | 0.15 | 0.15 |
| pill background | 0.27 | 0.24 | 0.22 | 0.26 | 0.25 |
| muted | 0.53 | 0.57 | 0.41 | 0.54 | 0.51 |
| label and icons | 0.96 | 0.92 | 0.77 | 0.96 | 0.90 |
| accent and ring | 0.97 | 1.00 | 0.58 | 0.97 | 0.88 |

Four themes, one ladder, agreeing to a few hundredths.

**The accent is the background, lifted.** Background to accent, the value
multiplier is 5.3, 6.3, 5.3 and 6.5. Saturation climbs a little.

So the four shipped themes are one structure instantiated four times: a
hue, a fixed lightness ladder, a saturation curve. That structure is
computable from a single colour.

---

## 4. How the colours are computed

`omacosy-derive` does the work. It is a small Swift binary built from
`helper/derive.swift`, with no dependencies beyond AppKit and ImageIO.

### 4.1 The base colour

The one input is the colour the menu bar takes from the wallpaper. omacosy
already computes this, in `seedStrip()` in `helper/bar.swift`, and has
done since before this feature existed. `omacosy-derive` uses the same
maths:

1. Decode the image with `CGImageSource`.
2. Work out the **centred fill crop** — macOS scales a wallpaper to fill,
   so the band under the bar is not simply the top of the file. The scale
   is the larger of the two ratios and the crop is centred.
3. Average the band the bar covers.
4. Push saturation by 1.3 and darken by 0.923.

Those last two numbers are fitted, not documented. Apple's real pipeline
is a private `CABackdropLayer` with a saturation factor and a tint, which
is not reachable from public API. They were measured over seven
wallpapers, twice each, by least squares: worst residual 9.1 per 255
against 18.5 for a raw average.

One detail is load-bearing. Every sample goes through
`.usingColorSpace(.sRGB)`. Skipping it reads raw component values and
lands up to **22 per 255** away — larger than the whole correction above.
A Python prototype of this code did skip it, via Pillow's
`convert("RGB")`, and produced a systematically darker base for every
image.

### 4.2 The picture's colour

The base colour is the right input for the **bar**, because the bar sits over
that strip. It is the wrong input for everything else. A thin band across the
top of a picture is usually sky, and it says nothing about the picture.

Measured on real failures:

| wallpaper | top strip | what you see |
| --- | --- | --- |
| Battersea power station | 179° near-grey | orange brick and sunset |
| purple line art on grey paper | 218° blue | purple |
| red sun over a teal sky | 186° teal | the red sun |
| moon over a tent | purple sky edge | the blue centre |

So a second pass reads the **whole** image on a 200x200 grid and finds the
hue the picture reads as. That is not the colour covering the most area: the
line-art page is 87% paper, and an average of it says blue.

The weight is **saturation x value cubed**. The cube was fitted, not chosen.
Moon-over-a-mountain is 61% dark purple by area and 7% bright blue glow, and
the eye calls it blue; linear and squared weighting both answer purple, and
cubed answers blue. On the lighthouse, whose hues are so spread that no
10-degree bucket holds more than 11%, cubed is also the first that answers
pink rather than one narrow blue band.

Hues go into 36 buckets smoothed over +/-20 degrees, so a hue spread across
several buckets is not beaten by a narrow one, and the winner is merged with
its neighbours by a circular mean. The function also returns a **share**: how
much of the total weight that winning window holds.

**Whether there is any colour at all is a separate test, and it is the older
one.** A greyscale image has a 90th percentile of saturation too, and it is
sensor noise, so the gate is: the top tenth by saturation x value, with a
floor of 0.12, must hold more than five samples. Inventing a hue when it does
not is what painted a black-and-white city yellow and a black-and-white
portrait pink.

Cost: one grid pass over an already-decoded image, about 40,000 samples.

### 4.3 The other four colours — two hues, for two jobs

**The pills, the muted text and the labels keep the BASE hue**, the same
one as the bar. The bar is the wallpaper showing through, so anything on
it in that hue family belongs there. Giving them the loud hue instead made
a beige picture wear blue pills and a pink one wear blue pills, and both
read as foreign objects pasted onto the desktop:

```
                bar hue          pill hue      apart
cat with ball   25  beige        195 blue       170 degrees
lighthouse      297 lilac        235 blue        62 degrees
```

**The ring wears the SAME hue as the accent.** A desktop cannot name two
colours at once. The ring used to take the picture's hue unconditionally, and
whenever the accent fell back to the bar the two disagreed — an earth-brown
bar with a blue ring, a blue bar with a yellow ring. Only the treatment
differs: the ring keeps more of the picture's saturation and stays brighter,
because it is a stroke on a window rather than text on a pill.

**The accent's saturation follows the picture's.** A pastel wallpaper gets a
pastel accent and a saturated one gets a neon accent. Forcing a floor of 0.85
put a colour on the bar that the picture does not contain: a near-white rain
scene wore pure red, a lilac seascape wore hot magenta. Measured across the
corpus, pastel wallpapers now average an accent saturation of 0.53 and
saturated ones 0.77.

**The accent's hue follows the picture when the picture is confident, and the
bar otherwise — with no distance limit.** That last part is the one
difference from the pills below. The pills sit on the bar and must belong to
it, so a hue 179 degrees away is foreign. The accent is one chip and one line
of text, and it is the bar's chance to name the picture: a red sun over a
teal sky should give a red accent even though the bar is teal. The threshold is **0.50**. Five wallpapers were reported whose bar and ring
disagreed and their shares cluster tightly — 49, 51, 55, 61, 63. Only the
beige room with a dog falls under half, and that is the one whose BAR colour
the eye trusts; the rest are dark skies whose hue is barely a colour at all.

**The accent escapes its bands in the LADDER's direction**, bright on a dark
bar and dark on a light one, rather than toward whichever side is nearer.
Taking the nearer side sent that red accent on its teal bar down to
near-black, because raising its saturation had lowered its luminance past the
midpoint.

**The pills normally take the bar's hue, and the picture overrules it only
when confident and nearby.** A 34-point strip can lie about a picture: on
moon-over-a-mountain it catches the purple edge of a sky whose body is blue,
and the mauve pills that produced read as foreign. So the picture wins when
its share is at least 65% **and** it is within 90 degrees of the strip. The
beige picture with a small blue jacket fails both tests, 49% and 170 degrees,
and keeps its beige pills. That guard is the reason the rule is safe.

From there: a ladder.

```
low   = no loud colour found    a greyscale picture
light = luminance   > 0.45      which way the ladder runs
```

**Use luminance, not value, to choose the ladder.** A saturated purple at
value 0.62 has luminance 0.27 and needs light text. Choosing on value
called it a light bar and painted near-black text on it.

Dark ladder — light text on a dark bar:

```
pill   = hue,  saturation × 0.85,       max(value + 0.11, 0.20)
muted  = hue,  0.22,                    0.48
label  = hue,  0.18,                    0.92
accent = accent hue,  min(0.95, max(0.35, accent sat x 2.4)),  0.92
```

Light ladder — dark text on a light bar:

```
pill   = base hue,  base sat × 0.75,     value × 0.80
muted  = base hue,  min(base sat, 0.30), value × 0.42
label  = base hue,  min(base sat, 0.38), value × 0.16
accent = accent hue,  min(0.92, max(0.35, accent sat x 2.4)),  0.92
```

With no loud colour the saturations become 0 and the result is a neutral
grey scheme. **The accent then goes to the opposite end of the ladder** —
near-white on a dark bar, near-black on a light one. That is the most
visible thing available and it is honest about the picture having no
colour.

The accent keeps the base hue with **no shift**. Three of the four shipped
themes shift their accent negative from their wallpaper's hue and one
shifts positive, so zero is the centre.

### 4.4 Contrast is checked, not assumed

Ladder values alone are not enough. Every colour is then checked against
the surface it sits on and corrected until it passes.

| check | floor | why that number |
| --- | --- | --- |
| pill vs bar | 0.085 | the gap the shipped themes hold |
| label vs pill | 0.50 | the shipped gap is 0.56 to 0.64 |
| muted vs pill | 0.18 | the shipped gap is 0.19 to 0.24 |
| muted vs label | 0.18 | same |
| accent vs bar | 0.28 | so the accent reads against the bar |
| accent vs pill | 0.20 | the accent is drawn ON pills, see below |
| ring vs bar | 0.10 | a stroke on a window edge, see 4.6 |

Two failures during development shaped how this is done.

**A fixed offset cannot separate a pill from a bar.** On a wallpaper whose
base is value 1.00, adding 0.11 clamps and only saturation moves. The
result was a bright red bar carrying bright red pills. The correction now
**blends toward white or black**, which always has somewhere to go, in a
loop that stops only when the gap is real.

**Two corrections in a row fight each other.** `muted` has to clear both
the pill and the label. Separating it from one then the other made the
second undo the first whenever the gap was too small to hold a colour
between them. `muted` is now **placed at the midpoint** of pill and label,
which clears both by construction.

**The accent has to clear two surfaces, not one.** It fills the focused
workspace chip and it is the app name's text colour, so clearing the bar
says nothing about whether it can be read on a pill. Measured before this
floor existed, 33 of 65 wallpapers put the accent within 0.25 of its own
pill, the worst at 0.048 — an invisible ring and unreadable text.

Two `separate()` calls in a row cannot fix it, because the second lands
back inside the first band. `clearOf()` solves both at once: it finds the
luminance nearest the accent's own that sits outside **both** forbidden
bands and blends to it.

**The checks compare 8-bit values.** Satisfied in floating point and then
rounded to hex, three of the five floors fell back under by about 0.002.
Rounding costs up to 0.5/255 per channel, and luminance is a weighted sum,
so two colours can drift 0.004 apart. The floors are a promise about the
hex written to the file.

These floors give the ladder its shape. They do not decide whether text is
legible: the focused workspace number passed all of them at 2.5:1. Section
4.7 adds WCAG contrast checks after them, and those win. Measured over 66
images, four floors now give way to them: label vs pill on 9 wallpapers
and pill vs bar on 8, where the pill moved to sit on the real wallpaper
behind it, and muted vs label and accent vs bar on 5 and 2, where no
surface suits light text and a dark accent together. Muted vs pill,
accent vs pill and ring vs bar hold on all 66. Two full runs produce
byte-identical output.

### 4.5 The fixture

Running the derivation on the first wallpaper of each shipped theme must
produce exactly:

| wallpaper | bar | pill | muted | label | accent | ring | surface | ladder |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `catppuccin/1-totoro.webp` | `1d1d33` | `333444` | `7f8095` | `c8caf3` | `a7b0fd` | `909afe` | `161725` | dark |
| `gruvbox/1-the-backwater.jpg` | `464c35` | `2c2b16` | `7d7d63` | `d1d1a7` | `d4b53b` | `c2ab44` | `0f0e01` | dark |
| `osaka-jade/1-glowing-city.webp` | `003c30` | `1e382f` | `6c857f` | `dbcda5` | `56b394` | `43ae8d` | `021b13` | dark |
| `tokyo-night/0-winding-road.webp` | `7540ac` | `3a2859` | `847c92` | `d5c5ef` | `bba8fd` | `aa8eff` | `1c1130` | dark |

`omacosy-derive --print <image>...` prints these columns in this order.

Reproducing a hand judgement is not the goal; producing a coherent scheme
is. Still, reading the whole image rather than the top strip moved three
of the four a long way toward the colour a designer chose:

```
              hand-picked   top strip    loud colour
catppuccin      cba6f7        30°     ->      1°
gruvbox         fe8019        51°     ->      9°
osaka-jade      509475        15°     ->      9°
tokyo-night     7aa2f7        49°     ->    122°
```

Gruvbox is the striking one: its accent is orange, its top strip is olive,
and the orange only appears once the whole picture is read. Tokyo-night
goes the other way — its wallpaper has a large magenta sky, so pink is a
fair reading of the picture and blue was the designer's taste.

---

### 4.6 The ring is not the accent

All four shipped themes write the same value into `sketchybar.sh`'s `ACCENT`
and `borders.sh`'s `ACTIVE_COLOR`. A computed theme does not, because they
are different surfaces with different jobs.

**The accent sits on the bar and on a pill.** It has to clear both, and those
two bands are what crush it dark: a pale bar leaves nowhere to go but down,
and down on a warm hue is brown. Measured on four reported wallpapers, the
accent's saturation was pinned at exactly 0.85 by a floor while the pictures
themselves were pastel:

| wallpaper | picture sat | accent sat | result |
| --- | --- | --- | --- |
| umbrellas | 0.20 | 0.85 | aggressive pure red |
| spider | 0.17 | 0.85 | dark brown |
| tiger | 0.68 | 0.85 | dark maroon at value 0.48 |

**The ring is drawn around a window, on the wallpaper.** It never touches the
bar. So it keeps the picture's own saturation, which lets a pastel picture
have a pastel ring, and it resolves **brighter, never darker** — darkening a
warm hue is exactly how the browns happened.

```
ring = picture hue,  min(0.95, max(0.45, picture sat x 1.20)),  0.86 light / 0.94 dark
       then lifted until it clears the bar by 0.10
```

Only the lift direction is special. Past a bar luminance of 0.75 there is no
room above, and climbing anyway washes the hue out toward white, so those
fall back to going down.

```
umbrellas   eb3523 -> db8279   dusty rose
clouds      ae301a -> e7ada3   soft salmon
tiger       7a122c -> e7728f   bright pink
spider      755f12 -> e5d69e   light golden
```

**A saturated yellow ring glares.** Around a window, amber and yellow at
full saturation are the loudest thing on the screen: a circuit board gave
`d89603`. For a ring hue from 35 to 70 degrees, the saturation drops to
0.65 and the hue and value stay. The accent on the bar does not change.

### 4.7 Legible by rule, and the dark ladder

The checks in 4.4 compare luminance. These compare what a person reads:
WCAG contrast ratios, on the 8-bit values written to the file. They run
after 4.4, in this order.

**The dark ladder takes the picture's shadow.** On a mid-tone bar, the
ladder lifted the pill until the label had nowhere to go but black. A
magenta sunset got salmon pills with black text. On the dark ladder the
pill now goes below the bar, at most luminance 0.20, in the hue of the
picture's dark tones: the pixels between value 0.12 and 0.50, darker ones
weighted more. A pink sky has purple shadows, so its pills are plum. A bar
too dark to have a pill under it keeps the pill's lightness and only
changes hue.

**The accent follows the shadow when it is the same family.** If the dark
tone is within 45 degrees of the bar's hue, the accent and the ring move
one step further in the same direction, up to 30 degrees: from pink, past
plum, to purple. A dark tone of another family, like palm leaves under a
blue sky, is a different object, and the accent keeps naming the picture.
The move is done in OKLCH. Lightened in HSV, the plum at 300 degrees
reads as orchid pink.

**No neon green.** The accent's saturation is up to 2.4 times the
picture's. Blue looks fine at that level and yellow-green looks
fluorescent. From 70 to 150 degrees the factor is 1.5 at most.

**Jade.** A deep green scene came out bright aqua and mint, where the stock
osaka-jade theme is a subdued jade, `509475`. The rule acts when the bar
is dark (value under 0.30) and green to teal (140 to 185 degrees), and the
accent is green to aqua (140 to 180 degrees). The accent and the ring then
drop to about a third of their chroma in OKLCH, their hue moves halfway to
jade (160), and the text loses most of its mint. Cyan accents, from 185
degrees, belong to bright teal scenes and do not change.

The pill in such a scene is made the way the stock theme makes it. The
stock pill, `23372b`, has the same lightness as its wallpaper: 1.0:1, so no
contrast floor could ever choose it. It stands out by colour. The derived
pill takes the wallpaper's lightness (the median of the strip slices
below), the hue of the picture's shadow moved halfway to jade, and 0.3
times the picture's chroma, kept between 0.02 and 0.05. On osaka-jade's own
wallpaper that gives `1e382f`.

**The text is tinted, as the stock themes tint it.** Their label sits at
OKLCH lightness 0.81 to 0.89 with chroma 0.04 to 0.06. The derived label
reached 0.91 and read as white in the cheat sheet. On the dark ladder it now
sits at 0.85 with chroma 0.055 in its own hue, never above 0.6 times the
accent's chroma, so a grey scene keeps near-neutral text.

**A jade scene gets warm text.** osaka-jade sets khaki text (hue 111)
against a jade accent (163): a colour temperature contrast, warm on cool.
The derived theme takes the warm hue from the picture: the pixels at OKLCH
hue 40 to 120 with some chroma, averaged. If they cover at least 0.1% of
the picture, the text takes their hue. osaka-jade's own wallpaper has a
little yellow light at 91 degrees and gets cream `dbcda5`. A jade scene
with no warm light keeps cool text, and blue, violet and warm scenes keep
their own temperature, as catppuccin, tokyo-night and gruvbox do.

**Grey scenes keep a quiet accent.** On a near-grey photograph with a cool
cast, the 2.4x boost turned a faint blue-grey into sky blue `38c7ff`.
Twenty dark wallpapers wore accents 3 to 20 times more colourful than
anything in them. HSV saturation cannot see this, so the picture's
colourfulness is measured as the 90th percentile of OKLCH chroma over its
pixels. Under 0.07, the accent's chroma is at most 2.5 times the picture's,
never under 0.05, and the ring's 0.02 more. Hue and lightness stay.

**The pill is seen on the real wallpaper.** The base colour is one average
across the bar. On a street with a bright sky in the middle, that average
was lighter than the dark slate under the pills, and a pill that passed
against it was invisible. The pill is now judged against the wallpaper
itself, in 8 slices across the bar, and it must pass against 6 of them, so
one bright window or dark corner does not decide. A dark pill is preferred,
because a light pill on a dark desktop glows. In order, the lightness
nearest the ladder's own pill wins:

```
1. darker than the wallpaper, 1.7:1     never near black: relative
2. darker than the wallpaper, 1.5:1     luminance under 0.012 reads as a hole
3. any lightness, 1.3:1                 a lighter pill takes the DARKEST value
                                        that passes, so it stays close to the
                                        bar on a very dark desktop
```

The light ladder keeps one check, 1.7:1 against the base.

**Text on a pill.** The label reaches 4.5:1 on the pill, the accent 3:1 on
the pill and on the surface.

**The surface is searched.** `BAR_BG_SOLID` is not the bar strip, which is
the wallpaper showing through. The bar uses it in three places: the colour
of the focused workspace number, and the background of the popups and the
cheat sheet (Super+K). In the cheat sheet the keys are the label, the
descriptions are `MUTED` and the headings are the accent. `MUTED` was
designed as dim text on a pill and never checked there, and 48 of 64
wallpapers put the descriptions under 4.5:1.

So the surface's lightness is searched, in the pill's hue with little
chroma, for keys 7:1, descriptions 4.5:1 and accent 3:1. Of the values
that pass, the one nearest the theme's own look wins: the bar colour on
the light ladder, a step under the pill on the dark one. On 5 wallpapers
the text is light and the accent is dark, and no surface suits both. The
text colours then move instead: the descriptions reach 4.5:1, the keys
4.5:1 in place of 7:1, and the two become almost the same colour. On a
dark pill the surface is darker still, so on the slate wallpapers the
popups and the cheat sheet are almost black.

```
                          before        after
focused number, quattro   2.5:1         8.7:1
cheat sheet, village      1.5:1        10.4:1   descriptions
```

## 5. How a computed theme reaches the screen

omacosy's bar and its focus-ring daemon watch `~/.config/omarchy/current`
with **kqueue**, a kernel service that wakes a program when a directory
changes. `theme-set` relies on it: swapping the `theme` symlink inside
that directory *is* the reload notification. There is no reload command.

kqueue on a directory fires when an entry is added, removed or renamed. A
write to a file one level deeper is not an entry change, and whether it
reaches the daemons was never established here.

So nothing depends on it. **Each wallpaper gets its own generated theme
directory**, named after a hash of the wallpaper's path:

```
~/.local/state/omacosy/derived/7ab23b1ea0c77153/
├── backgrounds/<image>   a symlink to your file
├── borders.sh            generated
└── sketchybar.sh         generated
```

Because the directory name changes with the wallpaper, re-pointing
`current/theme` at it is a real change and the daemons reload. That path
was exercised on 53 consecutive wallpaper changes without a miss.

The directories are built on first use and kept. `omacosy-custom-theme
rebuild` discards and regenerates them all.

Nothing is written into your wallpaper directory, and nothing is written
into the repo.

### 5.1 The cache

A theme is computed **once per wallpaper, ever** — not on each wallpaper
change. `Super+Shift+B` in steady state writes a symlink and does no colour
work at all.

```sh
~/.local/state/omacosy/derived/        48 themes, 384 KB in total
```

Two text files and one symlink per wallpaper. The key is the SHA-1 of the
image's **absolute path**, so two copies of the same picture in different
folders get their own entries, and moving a folder invalidates its themes.

One staleness check exists:

```sh
[ "$img" -nt "$out/sketchybar.sh" ]
```

Edit an image in place and its theme is recomputed the next time you land on
it. Replacing a file at the same path with a different picture is usually
caught the same way, by the timestamp.

The derivation is **pure**: the same image always yields the same hex.
Verified by deriving the whole corpus twice and diffing — byte identical. So
a cached theme and a freshly computed one can never disagree.

### 5.2 Adding and removing wallpapers

**Adding needs no command.** The wallpaper list is a `find` run at the moment
you press the key, so a new image is in the cycle immediately. Its theme is
computed the first time you reach it, once, then cached.

**Removing needs no command either.** The image leaves the cycle at once. If
it was the one showing, `custom-index` now names a missing file, `theme-set`
notices with `[ -f "$IMG" ]` and falls back to the first image.

**Emptying the directory** removes `custom` from the cycle entirely and you
are back to the four shipped themes, silently.

One thing removal does NOT do: **it leaves the derived theme behind.** A
derived directory is named after a hash of its wallpaper's path, and nothing
links it back the other way, so deleting the image orphans its theme. At
about 8 KB each this is harmless in normal use, and `rebuild` clears them —
it builds a fresh tree and swaps, so orphans do not survive it. Nothing
prunes them automatically.

Spot them by their dangling `backgrounds/` symlink — the entry is still
there, only its target is gone, so the test has to be `-type l ! -e`:

```sh
find ~/.local/state/omacosy/derived -mindepth 3 -maxdepth 3 \
  -path '*/backgrounds/*' -type l ! -exec test -e {} \; -print \
  | sed 's|/backgrounds/.*||'
```

Delete the directories it names, or just run `rebuild`.

### 5.3 Reload, and the one case that needs help

The bar and the borders daemon each watch `~/.config/omarchy/current` with
kqueue. **Re-creating the `theme` symlink inside it IS the reload signal.**
There is no reload command, no polling and no restart.

That works because each derived directory is named after its wallpaper's
hash: change wallpaper, the symlink target changes, the daemons wake.

**A rebuild is the one case where that fails.** It regenerates every theme
under the same names, so the symlink would not change and nothing would fire
— the files on disk would be new and the desktop would keep the old colours.
`rebuild` therefore re-creates the symlink explicitly once the files are in
place. The bar log is the proof it worked:

```
09:39:23  theme 26.20 ms
09:39:23  theme  7.97 ms
```

No `theme` line after a rebuild means the daemons did not reload.

### 5.4 Maintenance commands

```sh
omacosy-custom-theme rebuild     # recompute every theme, clear orphans, reload
omacosy-custom-theme status      # directory, image count, cached theme count
rm -rf ~/.local/state/omacosy/derived   # nuke the cache; rebuilt on next use
```

`rebuild` is the one to reach for after changing the derivation itself, or to
reclaim orphans. It is safe at any time: it builds into a scratch directory
and swaps, so `current/theme` is never left dangling.

To force a reload without recomputing anything:

```sh
ln -sfn "$(readlink ~/.config/omarchy/current/theme)" ~/.config/omarchy/current/theme
```

---

## 6. Setting it up

**Put images in the directory.**

```sh
mkdir -p ~/Pictures/wallpapers
cp ~/Downloads/some-wallpapers/*.jpg ~/Pictures/wallpapers/
```

`install.sh` creates that directory for you, empty. Whenever it holds at
least one image, `Super+Shift+T` reaches a fifth theme, `custom`, after the
four shipped ones; an empty directory keeps the cycle at four themes. The
desktop, the bar, the ring and the cheat sheet always follow it. The terminal
and its apps follow only if you ask them to with `omacosy-term-auto-theme on`:
[auto-theme.md](auto-theme.md).

`Super+Shift+B` inside `custom` moves through your images, and
every press recolours the bar, the pills, the icons and the focus ring.

Check what omacosy sees:

```sh
omacosy-custom-theme status
```

```
wallpaper directory : /Users/you/Pictures/wallpapers
  set by            : default (no ~/.config/omacosy/themes.conf, or no custom_wallpapers key)
  images            : 48
  state             : active — Super+Shift+T reaches it last
follow_appearance   : off
day                 : (unset)
night               : (unset)
derived themes      : 5 cached in /Users/you/.local/state/omacosy/derived
```

**Auto-theme off, or an empty or missing directory, hides the feature
completely.** The cycle
stays four themes, `theme-set list` prints four names, and `theme-set
custom` is an unknown theme. No warning is printed, because a machine that
never opted in has nothing to warn about.

Accepted files: `jpg`, `jpeg`, `png`, `webp`, `heic`, `gif`.

---

## 7. Configuration

`~/.config/omacosy/themes.conf`. **The file is optional and is not created
for you.** It exists only to override the default directory or to
configure day and night. Same `key=value` format as `bar.conf` beside it.

```ini
# omacosy custom theme — all keys optional
custom_wallpapers=~/Pictures/wallpapers
day=gruvbox
night=osaka-jade/1-glowing-city.webp
follow_appearance=off
```

| key | default | what it does |
| --- | --- | --- |
| `custom_wallpapers` | `~/Pictures/wallpapers` | where your images live |
| `day` | unset | what to show in the light appearance |
| `night` | unset | what to show in the dark appearance |
| `follow_appearance` | `off` | whether to act on the appearance flip |

`custom_wallpapers` accepts `~`, `$HOME`, and any absolute path including
one on an external volume.

```sh
omacosy-custom-theme path /Volumes/Photos/walls
```

If the directory you point at does not exist or holds no images, the
custom theme is hidden. **It does not quietly fall back to
`~/Pictures/wallpapers`** — a directory you named on purpose should not be
silently replaced by a different one. `omacosy-custom-theme status` says
what it found.

---

## 8. Day and night

Two keys name what to show in each appearance. Either may be a **shipped
theme** or a **wallpaper of your own**, so this is not limited to the
custom theme.

Four forms, one rule each:

| you write | it means |
| --- | --- |
| `gruvbox` | that shipped theme, its first wallpaper |
| `gruvbox/2-flower-basket.webp` | that shipped theme, that wallpaper |
| `a_beach.jpg` | that file in your wallpaper directory |
| `/Volumes/Photos/dawn.jpg` | any absolute path |

A leading `/` is a path. A name matching a directory under `themes/` is a
shipped theme. `theme/file` is that theme's wallpaper. Anything else is a
filename in your directory.

```sh
omacosy-custom-theme day   gruvbox
omacosy-custom-theme night osaka-jade/1-glowing-city.webp
omacosy-custom-theme follow on
```

Check a value before relying on it:

```sh
omacosy-custom-theme resolve gruvbox/2-flower-basket.webp
# theme gruvbox, wallpaper /…/themes/gruvbox/backgrounds/2-flower-basket.webp

omacosy-appearance --status
# appearance        : dark
# follow_appearance : on
# would apply       : osaka-jade/1-glowing-city.webp -> theme osaka-jade, wallpaper …
```

### Why the appearance and not a clock

macOS already owns the schedule. With **System Settings → Appearance →
Auto**, macOS flips Light and Dark at sunrise and sunset using its own
location. Reading that flip means:

- one schedule on the machine instead of two
- it follows the seasons with no maintenance
- if you prefer fixed times, set them in System Settings and this follows

**No hours are stored in omacosy's config.**

Night Shift was the obvious candidate and is the wrong one. It is colour
temperature, not appearance, and its schedule lives undocumented in
`com.apple.CoreBrightness.plist` keyed by UID — a file that does not exist
until Night Shift is switched on.

One quirk worth knowing: `defaults read -g AppleInterfaceStyle` **exits
non-zero in Light mode**, because the key is absent rather than set to
`Light`. That is the documented shape of the setting.

### How it runs

`com.omacosy.appearance`, a launch agent that runs `omacosy-appearance`
once a minute. It exits immediately unless `follow_appearance=on`, so an
install that never configures it costs one `defaults read` a minute.

A poll rather than a resident notification observer: this does nothing on
almost every machine, and a script that exits in milliseconds costs less
than a process holding an observer.

**It acts only on a change of appearance.** Without that it would re-apply
every minute and stamp on a theme you picked by hand thirty seconds
earlier. Pick gruvbox at 3pm with `night=osaka-jade` and gruvbox stays
until the appearance actually flips.

Setting only one of the two keys is fine. A missing value for the other
half means that half does nothing.

The agent is created and loaded by `install.sh`. It remembers the last
appearance it saw in `~/.local/state/omacosy/appearance`, which is how it
tells a change from a repeat.

Measured on an M1 Air: **30 ms per run**, whether following is on or off —
about 43 seconds of CPU a day, spread over 1440 wake-ups, from a script
that exits rather than a process that stays resident.

Turning it off:

```sh
omacosy-custom-theme follow off      # the intended switch: the agent still
                                     # runs and exits immediately
launchctl unload ~/Library/LaunchAgents/com.omacosy.appearance.plist
                                     # heavier: stops it running at all,
                                     # until the next install.sh
```

Checking it:

```sh
omacosy-appearance --status    # appearance, config, last seen, what it would apply
omacosy-appearance --force     # act now, whatever the cached value says
launchctl list | grep omacosy.appearance
```

---

## 9. Command reference

```
omacosy-custom-theme                   status (default)
omacosy-custom-theme status            the directory, image count, and config
omacosy-custom-theme path <dir>        point the custom theme somewhere else
omacosy-custom-theme day <spec>        what to show in the light appearance
omacosy-custom-theme night <spec>      what to show in the dark appearance
omacosy-custom-theme follow on|off     follow the macOS appearance
omacosy-custom-theme resolve <spec>    say what a spec would do, without doing it
omacosy-custom-theme apply <spec>      put a spec on screen now
omacosy-custom-theme rebuild           discard and regenerate every derived theme

omacosy-appearance                     act if the appearance changed
omacosy-appearance --force             act whatever the cached value says
omacosy-appearance --status            say what it would do, change nothing

omacosy-derive <image> <outdir>        write sketchybar.sh and borders.sh
omacosy-derive --print <image>...      print the palette, for fixtures
```

Three more exist for the scripts rather than for you: `dir`, `list` and
`current`, and `theme <image>`. They are the machine-readable half, so
that `theme-set`, `theme-next` and `theme-bg-next` do not each carry a
copy of the rules.

---

## 10. What it will not do

**It does not reproduce a hand-picked theme.** See the fixture in 4.5.
Gruvbox's wallpaper is olive and gruvbox is orange.

**A greyscale image gives a grey scheme.** When no pixel is loud enough to
vote, there is no hue to use, so the palette is neutral and the accent is
near-white on a dark bar or near-black on a light one. That is the rule for
black-and-white photographs, and it replaces an earlier version that
invented a vivid accent from a noise hue.

**A fully saturated bright wallpaper gives a flat scheme.** Everything
stays legible because the contrast floors hold, but a base at saturation
1.00 and value 1.00 leaves little room for the ladder to breathe.

**Animated GIFs do not animate.** macOS accepts one as a desktop picture
and paints a still frame. Measured, and confirmed in use: 38 frames at
40 ms, and not one desktop pixel moved over 1.7 s. They are accepted because a still frame is
a usable wallpaper and the colours come out fine.

**The theme cache grows without bound.** It is the only structure here that
does: everything else holds one entry per current wallpaper. Deleting a
wallpaper orphans its derived theme, because the hash maps a path to a theme
and nothing maps back (5.2). About 8 KB each, so a hundred deletions is
800 KB.

Three ways to handle it were weighed, and the first was chosen:

| option | cost | why |
| --- | --- | --- |
| **leave it, `rebuild` is the cleanup** | none | the bound is slow enough that a documented command covers it |
| prune on `rebuild` only | none | already the behaviour, it just was not deliberate |
| prune opportunistically, say every hundredth lookup | small | adds a background side effect to a command whose job is to be fast and predictable, for very little |

Revisit it if anyone reports a cache worth noticing. Until then `rebuild`
clears orphans and 5.2 says how to find them.

**The four shipped themes are untouched.** They keep their hand-picked
files and their exact behaviour, including restarting at their first
wallpaper on a theme change. The custom theme differs there on purpose: it
**remembers** which wallpaper it was on, because a shipped theme holds 3
to 7 images and a folder of your own can hold hundreds.

---

## 11. Troubleshooting

**`Super+Shift+T` does not reach a fifth theme.**

```sh
omacosy-custom-theme status
```

`MISSING` or `empty` means the directory is not there or holds no images
of an accepted type. That is the whole condition.

**Colours do not change when I press `Super+Shift+B`.**

Check you are on the custom theme:

```sh
omacosy-custom-theme current     # should print: custom
```

On a shipped theme the wallpaper changes and the colours do not, which is
the original behaviour and is unchanged.

**A wallpaper looks wrong and I want it recomputed.**

```sh
omacosy-custom-theme rebuild
```

`rebuild` builds into a scratch directory, swaps it in, and then re-creates
the `current/theme` symlink so the bar and the borders daemon reload. That
last step is not optional: a derived directory is named after a hash of its
wallpaper's path, so a rebuild recreates it under the same name, the symlink
never changes, kqueue never fires, and the desktop keeps showing the palette
the daemons already had while the files on disk are new.

The generated directories are a cache keyed by path. Editing an image in
place is detected by its timestamp; replacing the file at the same path
with a different image is not, until a rebuild.

**Day and night do nothing.**

```sh
omacosy-appearance --status
```

Check `follow_appearance` is `on`, the relevant key is set, and macOS is
actually switching appearance — System Settings → Appearance → Auto.
Force one round to see it work:

```sh
omacosy-appearance --force
```

**I want to see what a colour scheme will look like before applying it.**

```sh
omacosy-derive --print ~/Pictures/wallpapers/*.jpg
```

Five hex values per line — bar, pill, muted, label, accent — then the
ladder and the filename.

**Start again from nothing.**

```sh
rm -rf ~/.local/state/omacosy/derived
rm -f  ~/.config/omacosy/themes.conf
```

Both are rebuilt or optional. Your wallpapers are never touched.
