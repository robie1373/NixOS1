# yazi

A fast, Rust-based terminal file manager. Three-panel layout (parent /
current / preview), vi-style keybindings, image previews in foot, git
status integration, and a shell wrapper that changes your terminal's working
directory when you quit.

Module: `modules/home/yazi.nix` — `myHome.yazi.enable`

---

## Launching

Always use the shell wrapper, not `yazi` directly:

```bash
y
```

The `y` wrapper is a fish function that:
1. Launches yazi
2. Captures the last directory you were in when you quit
3. Changes your shell's `$PWD` to that directory

If you launch with `yazi` instead, quitting drops you back where you
started. The `y` wrapper is the whole point.

---

## The Interface

```
┌──────────┬───────────────────────┬────────────────────┐
│ Parent   │ Current directory     │ Preview            │
│          │ ▶ Documents/          │                    │
│ ~        │   Downloads/          │ (file content,     │
│ .config  │   Music/              │  image, or         │
│ ▶ home   │   Pictures/           │  directory tree)   │
│          │ > notes.md            │                    │
│          │   script.sh           │                    │
└──────────┴───────────────────────┴────────────────────┘
  [NORMAL]  ~/home                          1:20  100%
```

- **Left panel** — parent directory; shows where you came from
- **Middle panel** — current directory listing
- **Right panel** — preview of the selected item (text, image, video
  thumbnail, or subdirectory tree)
- **Status bar** — mode, current path, position in list, percentage

The border style (`full-border` plugin) draws a clean box around the
whole interface rather than three floating panels.

---

## Core Concepts

### Modes

Yazi is modal, like vim.

| Mode      | What it is                             | How to enter     |
|-----------|----------------------------------------|------------------|
| `NORMAL`  | Default — navigate and act on files    | `Esc`            |
| `SELECT`  | Multiple files selected                | `v` or `Space`   |
| `VISUAL`  | Visual range select (like vim's V)     | `V`              |
| `INSERT`  | Typing in rename / search / command    | triggered by cmd |

### The Three Panels Follow You

Moving into a directory updates all three panels simultaneously. You always
see where you came from, where you are, and what's selected — no mental
overhead tracking your position.

---

## Navigation

These work in NORMAL mode.

### Moving Around

| Key        | Action                                     |
|------------|--------------------------------------------|
| `j` / `↓` | Move selection down                        |
| `k` / `↑` | Move selection up                          |
| `h` / `←` | Go up to parent directory                  |
| `l` / `→` | Enter directory / open file                |
| `Enter`    | Open file with default app                 |
| `gg`       | Jump to top of list                        |
| `G`        | Jump to bottom of list                     |
| `[` / `]`  | Previous / next sibling directory          |

### Jumping to Common Locations

These are the custom shortcuts configured in this setup:

| Key   | Destination     |
|-------|-----------------|
| `gh`  | Home (`~`)      |
| `gd`  | `~/Downloads`   |
| `gc`  | `~/.config`     |
| `gn`  | `/mnt/nas`      |

(Standard yazi also provides `gh` for home — the above override it
with explicit paths for reliability.)

### Sorting & Filtering

| Key | Action                              |
|-----|-------------------------------------|
| `.` | Toggle hidden files (dotfiles)      |
| `,` | Cycle sort order (name/modified/size/extension) |
| `r` (in sort) | Reverse sort order          |

---

## Opening Files

| Key        | Action                                        |
|------------|-----------------------------------------------|
| `Enter`    | Open with default app (via xdg-open)          |
| `o`        | Open — shows picker if multiple openers exist |
| `O`        | Open interactively (always shows picker)      |

The openers configured in this setup:

| Opener    | Triggered by                    | App           |
|-----------|---------------------------------|---------------|
| `edit`    | Text, code, empty files         | `$EDITOR` (nvim) |
| `open`    | Everything else (fallback)      | `xdg-open`    |
| `play`    | Video and audio                 | `mpv`         |
| `extract` | Archives (zip, tar, 7z, rar)    | `unar`        |
| `reveal`  | Any file (secondary option)     | `exiftool`    |

---

## File Operations

All operations work on the **current selection** (one file) or **all
selected files** (if you've used Space or v to select multiple).

### Copy, Cut, Paste

| Key | Action                                   |
|-----|------------------------------------------|
| `y` | Yank (copy) selected file(s)             |
| `x` | Cut selected file(s)                     |
| `p` | Paste into current directory             |
| `P` | Paste and overwrite without asking       |
| `Y` | Cancel yank/cut                          |

> Yank and cut are **not destructive** until you paste. You can yank in
> one tab and paste in another. The yanked set is shown with a marker in
> the file list.

### Delete & Trash

| Key        | Action                                       |
|------------|----------------------------------------------|
| `d`        | Move to trash (recoverable)                  |
| `D`        | Delete permanently (asks for confirmation)   |

### Rename

| Key | Action                                             |
|-----|----------------------------------------------------|
| `r` | Rename — opens an input bar, edit and press Enter  |
| `b` | Bulk rename — opens selected files in `$EDITOR`, save to rename |

Bulk rename is powerful: yazi writes one filename per line into a temp
file, you edit them in nvim, save and quit, and yazi applies the renames.

### Create

| Key | Action                                   |
|-----|------------------------------------------|
| `a` | Create a new file (type name, Enter)     |
| `A` | Create a new directory (trailing `/`)    |

> To create a nested directory in one go, type `path/to/new/dir/` — yazi
> creates all intermediate directories.

---

## Selection

| Key     | Action                                              |
|---------|-----------------------------------------------------|
| `Space` | Toggle selection on current file, move down         |
| `v`     | Enter visual (range) select mode                    |
| `V`     | Toggle select all in current directory              |
| `Esc`   | Clear all selections and return to NORMAL           |

Visual select works like vim's linewise visual: press `v`, move with
`j`/`k`, everything between the cursor positions gets selected.

---

## Search & Filter

| Key | Action                                                    |
|-----|-----------------------------------------------------------|
| `f` | **Filter** — type to narrow the visible list in real time |
| `/` | **Find** — jump to next matching filename                 |
| `n` | Find next match                                           |
| `N` | Find previous match                                       |

**Filter vs Find:**
- Filter (`f`) hides non-matching files. Press `Esc` to clear.
- Find (`/`) keeps all files visible and moves the cursor to the match.

---

## Tabs

Yazi supports multiple tabs — useful for working across two directories
at once.

| Key      | Action                           |
|----------|----------------------------------|
| `t`      | New tab (opens in current dir)   |
| `1`–`9`  | Switch to tab N                  |
| `[`      | Previous tab                     |
| `]`      | Next tab                         |
| `q`      | Close tab (or quit if only one)  |

Yank in one tab, switch to another with `2`, paste with `p`. The yank
persists across tabs within the same yazi session.

---

## Shell & Misc

| Key          | Action                                         |
|--------------|------------------------------------------------|
| `!`          | Open a shell in the current directory (blocks yazi) |
| `$`          | Run a shell command (yazi stays open)          |
| `Ctrl+z`     | Suspend yazi (resume with `fg`)                |
| `?`          | Show which-key help (press any prefix to see options) |
| `~`          | Open the yazi help overlay                     |
| `q`          | Quit (or close tab)                            |
| `Q`          | Quit all tabs and exit                         |

**Which-key** is very useful while learning. Press `?` then immediately
press a key (like `g`) to see all bindings that start with that key.

---

## Git Integration

The `git` plugin shows status indicators next to filenames inside a git
repository. Indicators appear in the file list:

| Indicator | Meaning          |
|-----------|------------------|
| `✓`       | Unmodified       |
| `+`       | Staged (new)     |
| `!`       | Modified         |
| `?`       | Untracked        |
| `✗`       | Conflicted       |

---

## Exercises

Work through these in order. Each one teaches a cluster of related skills.
Open a terminal and run `y` to start.

---

### Exercise 1 — Get Your Bearings

**Goal:** Understand the three-panel layout and basic movement.

1. Launch yazi with `y`. You start in whatever directory your shell was in.
2. Press `gh` to jump to your home directory.
3. Press `j` and `k` several times. Watch all three panels update.
4. Move the cursor onto a directory. The right panel shows its contents.
5. Move the cursor onto a text file. The right panel shows its content.
6. Press `l` to enter a directory. Notice the left panel now shows
   where you just were.
7. Press `h` to go back up. You're where you were.
8. Press `gg` to jump to the top of the list. Press `G` to jump to the bottom.
9. Press `q` to quit. Notice your shell is now in the directory you were
   browsing in yazi.

**You learned:** basic navigation, three-panel context, cd-on-exit.

---

### Exercise 2 — Open Files

**Goal:** Use yazi to open files with the correct app.

1. Run `y` and navigate (`gd`) to `~/Downloads` or any directory with
   a mix of file types.
2. Move onto a text file. Press `Enter`. It opens in nvim.
   Quit nvim (`:q`) — you're back in yazi.
3. Move onto an image file (`.jpg`, `.png`). Press `Enter`. imv opens.
   Press `q` in imv to close. Back in yazi.
4. Move onto a PDF. Press `Enter`. zathura opens.
   Press `q` in zathura. Back in yazi.
5. Move onto a video file. Press `Enter`. mpv opens.
   Press `q` in mpv. Back in yazi.
6. Move onto any archive (`.zip`, `.tar.gz`). Press `o`. You should
   see multiple openers — `extract` and `reveal`. Press `Esc` to cancel.

**You learned:** xdg-open routing, the opener picker, app integration.

---

### Exercise 3 — Copy a File

**Goal:** Move a file between two directories using two tabs.

1. Run `y` and navigate to a directory that has a test file you can
   copy. (Create one if needed: press `a`, type `test.txt`, `Enter`.)
2. Move the cursor onto the file. Press `y` to yank it.
   Notice the file gets a small marker indicating it's yanked.
3. Press `t` to open a new tab.
4. Navigate to a different directory (try `gd` for Downloads).
5. Press `p` to paste. The file is now in both locations.
6. Press `1` to switch back to tab 1. Your original is still there.
7. Switch back to tab 2 (`2`). Move onto the pasted copy.
   Press `d` to move it to trash (cleaning up after yourself).
8. Press `q` to close tab 2. Press `q` again to quit.

**You learned:** yank, paste, tabs, trash delete, multi-tab workflow.

---

### Exercise 4 — Bulk Rename

**Goal:** Rename multiple files at once using your editor.

1. Create a test directory: press `A`, type `rename-test/`, press `Enter`.
2. Enter it: press `l`.
3. Create a few test files. Press `a`, type `file1.txt`, `Enter`.
   Repeat for `file2.txt`, `file3.txt`.
4. Press `V` to select all files in the directory.
5. Press `b` to bulk rename. nvim opens with one filename per line:
   ```
   file1.txt
   file2.txt
   file3.txt
   ```
6. Edit the names however you like — for example, prefix them:
   ```
   renamed-file1.txt
   renamed-file2.txt
   renamed-file3.txt
   ```
7. Save and quit (`:wq`). yazi applies the renames instantly.
8. Clean up: press `V`, then `D` to permanently delete the test files.
   Navigate up with `h`, move onto `rename-test/`, press `D` to remove it.

**You learned:** bulk rename, visual select-all, permanent delete.

---

### Exercise 5 — Search and Filter

**Goal:** Find files without navigating manually.

1. Run `y` and press `gc` to go to `~/.config`.
2. Press `f` and start typing `hypr`. Watch the list narrow in real time
   to show only items with "hypr" in the name.
3. Press `Esc` to clear the filter. Everything comes back.
4. Press `/` and type `hypr`. Instead of filtering, the cursor jumps to
   the first match. Press `n` to jump to the next match.
5. Press `Esc` to exit find mode.
6. Now go somewhere with lots of files. Press `.` to show hidden files.
   Press `.` again to hide them.

**You learned:** filter vs. find, toggling hidden files.

---

### Exercise 6 — Shell Escape

**Goal:** Drop to a shell and come back without losing your place.

1. Run `y` and navigate to an interesting directory.
2. Press `!` to drop to a shell **inside** yazi. You're now in a subshell
   with `$PWD` set to the directory you were browsing.
3. Run a command: `ls -la`, `git status`, anything useful.
4. Type `exit` to return to yazi. You're exactly where you left off.
5. Now press `$` instead. Type `echo "hello from yazi"` and press `Enter`.
   The command runs and the output flashes in a notification — yazi
   doesn't hand control to the shell, it just runs the command.

**You learned:** interactive shell escape (`!`), background command (`$`).

---

### Exercise 7 — Which-Key Discovery

**Goal:** Discover keybindings you didn't know existed.

1. Run `y`.
2. Press `?` to open which-key help.
3. Now press `g`. You'll see all the `g`-prefixed bindings, including
   `gh`, `gd`, `gc`, `gn` that this config adds.
4. Press `Esc`, then `?` again. Press `c`. See the copy/cut options.
5. Use this any time you forget a key — it's faster than looking it up.

**You learned:** which-key is your in-app cheat sheet.

---

## Tips

- **Preview pane is live.** Videos show thumbnails, PDFs show the first
  page, text files are syntax-highlighted via `bat`. The preview is
  generated by the packages installed alongside yazi (`ffmpegthumbnailer`,
  `poppler_utils`, `bat`, etc.).

- **Yank is a clipboard.** You can yank in one yazi session, close it,
  open a new one, and paste — the yank is stored on disk between sessions.

- **Archives are previewable.** Navigate onto a `.zip` or `.tar.gz` —
  the right panel shows its contents without extracting.

- **`q` is context-sensitive.** With one tab open, `q` quits. With
  multiple tabs, `q` closes the current tab. `Q` always quits everything.
