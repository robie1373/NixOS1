# imv

Lightweight, Wayland-native image viewer. Keyboard-driven, no GUI chrome,
renders cleanly with EGL/Vulkan. Handles JPEG, PNG, GIF, WebP, TIFF, SVG,
and most common formats.

Module: `modules/home/imv.nix` — `myHome.imv.enable`

---

## Launching

```bash
imv photo.jpg                  # open a single image
imv ~/Pictures/                # open all images in a directory
imv *.png                      # open a glob
```

From **yazi**: navigate to an image and press `o` or `Enter` — xdg-open
routes common image MIME types to imv via the mimeApps registration.

When opened with a directory or multiple files, imv loads them all as a
list and you can move through them with `j`/`k` (or `←`/`→`).

---

## Navigation

| Key              | Action                           |
|------------------|----------------------------------|
| `j` or `→`       | Next image                       |
| `k` or `←`       | Previous image                   |
| `gg`             | First image                      |
| `G`              | Last image                       |
| `nG`             | Jump to image n                  |

## Pan & Zoom

| Key           | Action                          |
|---------------|---------------------------------|
| `+` / `=`     | Zoom in                         |
| `-`           | Zoom out                        |
| `r`           | Reset zoom / position           |
| `f`           | Fit image to window (default)   |
| Arrow keys    | Pan when zoomed in              |
| Click + drag  | Pan                             |
| Scroll wheel  | Zoom                            |

## View

| Key    | Action                          |
|--------|---------------------------------|
| `s`    | Scale to fit window             |
| `S`    | Scale to actual (100%) size     |
| `x`    | Close current image             |
| `q`    | Quit                            |
| `f`    | Toggle fullscreen               |
| `t`    | Toggle overlay (filename/index) |
| `r`    | Rotate 90° clockwise            |
| `R`    | Rotate 90° counter-clockwise    |

## Slideshow

| Key    | Action                                          |
|--------|-------------------------------------------------|
| `p`    | Toggle slideshow (uses `slideshow_duration` from config) |

The config sets `slideshow_duration = 0` which disables auto-advance.
Set a positive integer (seconds) to enable: `:set slideshow_duration 5`

---

## Opening from the Terminal with Context

A common pattern: browse in yazi, press `Enter` on one image, and imv opens
the whole directory so you can flip through the rest:

In yazi's opener config, the `open` rule for `image/*` calls `xdg-open`,
which hands off to imv. imv receives just the one file but you can load
the rest manually with `imv ~/path/to/dir` instead.

Alternatively, configure a custom yazi opener:

```toml
# in yazi opener config
[opener]
view_dir = [
  { run = 'imv "$(dirname "$1")"', desc = "View directory in imv" }
]
```
