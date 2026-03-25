# mpv

Minimal, scriptable video and audio player. This config adds **uosc** (a
modern on-screen UI overlay) and **SponsorBlock** (auto-skips sponsored
segments in YouTube videos).

Module: `modules/home/mpv.nix` — `myHome.mpv.enable`

---

## Launching

```bash
mpv video.mkv                        # play a local file
mpv https://www.youtube.com/watch?v= # stream from YouTube (via yt-dlp)
mpv --shuffle ~/Music/*.flac         # audio-only, shuffled
```

From **yazi**: navigate to a video or audio file and press `o` (open) or
`Enter` — xdg-open routes media files to mpv automatically.

---

## uosc UI

uosc replaces mpv's default on-screen controls with a cleaner overlay.
It appears when you move the mouse and hides when idle.

| Element          | What it does                            |
|------------------|-----------------------------------------|
| Bottom bar       | Seek bar, time, volume, fullscreen      |
| Top-left icons   | Playlist, chapters, subtitles, audio tracks |
| Right-click      | Context menu for all settings           |

---

## Essential Keybinds

### Playback

| Key          | Action                          |
|--------------|---------------------------------|
| `Space`      | Play / pause                    |
| `q`          | Quit                            |
| `Q`          | Quit and remember position      |
| `→` / `←`   | Seek +5 / -5 seconds            |
| `↑` / `↓`   | Seek +60 / -60 seconds          |
| `.` / `,`    | Step forward / backward one frame |
| `l`          | Loop file toggle                |

### Speed

| Key     | Action              |
|---------|---------------------|
| `[`     | Decrease speed 10%  |
| `]`     | Increase speed 10%  |
| `{`     | Halve speed         |
| `}`     | Double speed        |
| `Backspace` | Reset speed to 1x |

### Volume & Audio

| Key       | Action                    |
|-----------|---------------------------|
| `9` / `0` | Volume down / up          |
| `m`       | Mute toggle               |
| `#`       | Cycle audio tracks        |
| `Ctrl+→`  | Audio delay +0.1s         |
| `Ctrl+←`  | Audio delay -0.1s         |

### Subtitles

| Key    | Action                        |
|--------|-------------------------------|
| `v`    | Subtitle visibility toggle    |
| `j`    | Cycle subtitle tracks         |
| `J`    | Cycle subtitles backwards     |
| `z`/`Z` | Subtitle delay ±0.1s        |

### Video

| Key        | Action                    |
|------------|---------------------------|
| `f`        | Fullscreen toggle         |
| `Alt+Enter`| Fullscreen toggle (alt)   |
| `s`        | Screenshot                |
| `S`        | Screenshot without subs   |
| `1`–`9`   | Contrast / brightness adjustments (hold) |

### Playlist

| Key              | Action                    |
|------------------|---------------------------|
| `<` / `>`        | Previous / next file      |
| `Shift+Enter`    | Show playlist             |

---

## Streaming from YouTube

mpv uses **yt-dlp** to fetch streams. The config requests the best available
quality by default (`ytdl-format = "bestvideo+bestaudio"`).

```bash
# Stream a video
mpv "https://www.youtube.com/watch?v=..."

# Open a URL interactively while mpv is running
# Press Ctrl+v in the uosc context menu, or use:
mpv --script-opts=osc-visibility=always "url"
```

SponsorBlock runs automatically on YouTube URLs and skips sponsor segments,
intros, outros, and self-promotion sections. A brief OSD message shows when
a skip occurs.

---

## Config

Lives in `modules/home/mpv.nix` as `programs.mpv.config`. Key settings:

| Option            | Value              | Effect                            |
|-------------------|--------------------|-----------------------------------|
| `profile`         | `high-quality`     | Enables high-quality scalers/shaders |
| `ytdl-format`     | `bestvideo+bestaudio` | Best quality for streams       |
| `cache-default`   | `4000000`          | 4 MB cache for network streams    |
