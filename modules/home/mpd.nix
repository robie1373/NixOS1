{ lib, config, pkgs, ... }:

{
  options.myHome.mpd.enable =
    lib.mkEnableOption "MPD music daemon + ncmpcpp TUI client";

  config = lib.mkIf config.myHome.mpd.enable {

    # ── MPD daemon ───────────────────────────────────────────────────────
    services.mpd = {
      enable       = true;
      musicDirectory = "~/Music";

      extraConfig = ''
        # Primary output — PipeWire (Wayland)
        audio_output {
          type "pipewire"
          name "PipeWire"
        }

        # FIFO output feeds the ncmpcpp spectrum visualiser
        audio_output {
          type   "fifo"
          name   "Visualizer"
          path   "/tmp/mpd.fifo"
          format "44100:16:2"
        }
      '';
    };

    # mpc gives you quick shell control: mpc toggle, mpc next, etc.
    home.packages = [ pkgs.mpc ];

    # ── ncmpcpp TUI client ───────────────────────────────────────────────
    programs.ncmpcpp = {
      enable = true;
      mpdMusicDir = "~/Music";

      settings = {

        # ── Layout ───────────────────────────────────────────────────────
        # "alternative" splits the screen: playlist on top, visualiser below
        user_interface             = "alternative";
        alternative_ui_separator_color = "blue";

        playlist_display_mode      = "columns";
        browser_display_mode       = "columns";
        startup_screen             = "playlist";

        # ── Song format ──────────────────────────────────────────────────
        song_list_format           = " {%a - }{%t}|{%f} $R {%l}";
        song_status_format         = "%t $3[ %a ]$9";
        song_columns_list_format   = "(50)[blue]{t|f:Title} (25)[cyan]{a:Artist} (25)[]{b:Album} (7f)[]{l:Length}";

        # ── Visualiser ───────────────────────────────────────────────────
        visualizer_data_source     = "/tmp/mpd.fifo";
        visualizer_output_name     = "Visualizer";
        visualizer_in_stereo       = "yes";
        visualizer_type            = "spectrum";
        visualizer_look            = "●▋";
        # The terminal's Catppuccin palette means these look on-theme automatically
        visualizer_color           = "blue,cyan,green,yellow,magenta";

        # ── Progress bar ─────────────────────────────────────────────────
        progressbar_look           = "─╼ ";
        progressbar_color          = "black";
        progressbar_elapsed_color  = "blue";

        # ── Colours ──────────────────────────────────────────────────────
        # ncurses colour names map to Catppuccin via foot's terminal palette
        colors_enabled             = "yes";
        main_window_color          = "white";
        header_window_color        = "cyan";
        volume_color               = "cyan";
        state_flags_color          = "cyan:b";
        active_column_color        = "blue";
        active_window_border       = "blue";
        window_border_color        = "black";

        # ── Misc ─────────────────────────────────────────────────────────
        display_remaining_time     = "yes";
        follow_now_playing_lyrics  = "yes";
        mouse_support              = "yes";
        mouse_list_scroll_whole_page = "no";
      };
    };
  };
}
