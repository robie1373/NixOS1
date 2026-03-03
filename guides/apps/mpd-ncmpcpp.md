# MPD + ncmpcpp

**MPD** (Music Player Daemon) runs as a background systemd user service and
manages your music library. **ncmpcpp** is a TUI client that connects to MPD
for browsing, playback control, and visualisation. **mpc** is a minimal CLI
client for scripting and quick commands.

Module: `modules/home/mpd.nix` — `myHome.mpd.enable`

---

## First-Time Setup

### 1. Point MPD at your music

The config sets `musicDirectory = "~/Music"`. Either put your music there,
symlink it to your NAS mount, or change the path in `modules/home/mpd.nix`.

```bash
# Symlink example for a NAS mount
ln -s /mnt/nas/music ~/Music
```

### 2. Start the service

MPD is a systemd user service. After rebuilding it starts automatically, but
you can control it manually:

```bash
systemctl --user start mpd
systemctl --user status mpd
systemctl --user restart mpd
```

### 3. Update the database

MPD needs to scan your library before it knows what's there:

```bash
mpc update          # scan for new/changed files
mpc update --wait   # same but blocks until done
```

---

## mpc — Quick CLI Reference

`mpc` is the fastest way to control playback from the terminal or scripts.

### Playback

```bash
mpc toggle          # play / pause
mpc stop
mpc next
mpc prev
mpc seek +10        # seek forward 10 seconds
mpc seek -10
mpc seek 50%        # seek to 50% of current track
```

### Volume

```bash
mpc volume 70       # set to 70%
mpc volume +5       # increase by 5
mpc volume -5
```

### Queue

```bash
mpc add "Artist/Album/track.flac"   # add a file to the queue
mpc clear                           # clear the queue
mpc shuffle                         # shuffle the queue
mpc ls                              # list music directory
mpc search artist "Pink Floyd"      # search library
mpc findadd genre "Jazz"            # find and add all Jazz
```

### Status

```bash
mpc                 # show current track + status
mpc status          # verbose status
mpc playlist        # show current queue
```

---

## ncmpcpp — TUI Client

Launch with:

```bash
ncmpcpp
```

The config uses the **alternative interface**: the window is split between
the playlist (top) and a spectrum visualiser (bottom).

### Screen Layout

```
┌─────────────────────────────────────────────┐
│ [Artist — Title]          [time] [vol] [mode]│  ← header
├─────────────────────────────────────────────┤
│ > Artist — Track title              3:21     │
│   Artist — Track title              4:02     │  ← playlist
│   Artist — Track title              2:55     │
├─────────────────────────────────────────────┤
│ ▂▄▆█▇▅▃▂▁▂▃▄▅▆▇▄▃▂▁▂▃▄▅▆▇▅▃▂▁          │  ← visualiser
├─────────────────────────────────────────────┤
│ ──────────────╼                   1:12/3:21  │  ← progress
└─────────────────────────────────────────────┘
```

### Essential Keybinds

#### Playback

| Key           | Action                     |
|---------------|----------------------------|
| `p`           | Play / pause               |
| `s`           | Stop                       |
| `>` / `<`     | Next / previous track      |
| `f` / `b`     | Seek forward / backward 5s |
| `+` / `-`     | Volume up / down           |
| `r`           | Toggle repeat              |
| `z`           | Toggle shuffle             |
| `x`           | Toggle crossfade           |

#### Navigation

| Key           | Action                              |
|---------------|-------------------------------------|
| `j` / `k`     | Move down / up                      |
| `g` / `G`     | Jump to top / bottom                |
| `PgDn/PgUp`   | Page down / up                      |
| `Enter`        | Play selected / open directory      |
| `Tab`          | Switch between panels               |

#### Queue Management

| Key      | Action                                    |
|----------|-------------------------------------------|
| `a`      | Add selected to queue                     |
| `Space`  | Add and move to next                      |
| `d`      | Remove selected from queue                |
| `c`      | Clear queue                               |
| `M`      | Move selected track (press again to place)|
| `R`      | Reverse the queue                         |
| `o`      | Jump to currently playing track in queue  |

#### Screens

Switch between screens with these keys:

| Key | Screen                          |
|-----|---------------------------------|
| `1` | Playlist (queue)                |
| `2` | Browser (library)               |
| `3` | Search                          |
| `4` | Library view (artist → album)   |
| `5` | Playlist editor                 |
| `6` | Tag editor                      |
| `7` | Outputs                         |
| `8` | Visualiser (full screen)        |
| `` ` `` | Clock                    |

#### Search (Screen 3)

Press `3`, fill in the fields, press `Enter` to search, then `Enter` again
on a result to play it or `a` to add it to the queue.

---

## Visualiser

The spectrum visualiser requires MPD's FIFO output to be active. This is
configured automatically in `modules/home/mpd.nix`. The full-screen
visualiser is on screen `8`. In the alternative interface it shows in the
bottom split.

If the visualiser shows no activity, check that MPD is playing and the
FIFO file exists:

```bash
ls /tmp/mpd.fifo
```

If the file doesn't exist, restart MPD:

```bash
systemctl --user restart mpd
```
