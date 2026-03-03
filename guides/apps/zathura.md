# zathura

Minimal, keyboard-driven PDF (and PostScript/EPUB/DjVu) reader. All
keybindings follow vim conventions. This config applies the Catppuccin
Macchiato palette and enables recolor mode by default.

Module: `modules/home/zathura.nix` — `myHome.zathura.enable`

---

## Launching

```bash
zathura document.pdf
```

From **yazi**: navigate to a `.pdf` and press `o` or `Enter` — xdg-open
routes PDFs to zathura via the mimeApps registration in the module.

---

## Recolor Mode

Recolor inverts the document colours to dark-background/light-text, which
is far easier on the eyes for long reading sessions. It is **enabled by
default** in this config.

| Key       | Action               |
|-----------|----------------------|
| `Ctrl+r`  | Toggle recolor on/off |

---

## Navigation

| Key                  | Action                              |
|----------------------|-------------------------------------|
| `j` / `k`            | Scroll down / up                    |
| `h` / `l`            | Scroll left / right                 |
| `d` / `u`            | Half-page down / up                 |
| `Space` / `Shift+Space` | Page down / up                  |
| `gg`                 | Go to first page                    |
| `G`                  | Go to last page                     |
| `nG` or `ngg`        | Go to page n (e.g. `42G`)           |
| `H` / `L`            | Top / bottom of current view        |

## Zoom

| Key         | Action             |
|-------------|--------------------|
| `+` / `-`   | Zoom in / out      |
| `=`         | Zoom to fit width  |
| `a`         | Zoom to fit page   |
| `s`         | Zoom to fit width  |
| `z`         | Original zoom      |

## Search

| Key        | Action                          |
|------------|---------------------------------|
| `/`        | Search forward                  |
| `?`        | Search backward                 |
| `n` / `N`  | Next / previous result          |

## Bookmarks & Index

| Key       | Action                                   |
|-----------|------------------------------------------|
| `:bmark`  | Add bookmark at current page             |
| `:blist`  | List bookmarks                           |
| `Tab`     | Show table of contents (if PDF has one)  |
| `F5`      | Toggle presentation mode                 |

## Miscellaneous

| Key       | Action                                    |
|-----------|-------------------------------------------|
| `r`       | Reload document (useful for live previews)|
| `R`       | Rotate 90° clockwise                      |
| `q`       | Quit                                      |
| `Ctrl+c`  | Copy selected text to clipboard           |
| `f`       | Follow links (highlight clickable areas)  |

---

## Command Mode

Press `:` to open the command bar (similar to vim).

```
:set zoom 150        set zoom to 150%
:set first-page-column 1:1   single-column layout
:print               print document
:bmark name          bookmark current page with a name
:blist               list all bookmarks
:version             show zathura version
```

---

## Multi-column Layouts

Useful for wide monitors or two-page spreads:

```
:set pages-per-row 2          show two pages side by side
:set first-page-column 1:2    offset for book spreads
```
