{ pkgs, ... }:
# MPD + ncmpcpp — system-level port of modules/_home/mpd.nix (HM removal Phase C).
# The mpd.conf and ncmpcpp config below are verbatim copies of what HM generated
# (captured live 2026-07-02), so behavior is identical: user-session mpd with
# PipeWire output plus the FIFO feeding ncmpcpp's spectrum visualiser.
let
  mpdConf = pkgs.writeText "mpd.conf" ''
    music_directory     "~/Music"
    playlist_directory  "/home/robie/.local/share/mpd/playlists"
    db_file             "/home/robie/.local/share/mpd/tag_cache"
    state_file          "/home/robie/.local/share/mpd/state"
    sticker_file        "/home/robie/.local/share/mpd/sticker.sql"

    bind_to_address     "127.0.0.1"
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

  ncmpcppConf = pkgs.writeText "ncmpcpp-config" ''
    active_column_color=blue
    active_window_border=blue
    alternative_ui_separator_color=blue
    browser_display_mode=columns
    colors_enabled=yes
    display_remaining_time=yes
    follow_now_playing_lyrics=yes
    header_window_color=cyan
    main_window_color=white
    mouse_list_scroll_whole_page=no
    mouse_support=yes
    mpd_music_dir=~/Music
    playlist_display_mode=columns
    progressbar_color=black
    progressbar_elapsed_color=blue
    progressbar_look="─╼ "
    song_columns_list_format=(50)[blue]{t|f:Title} (25)[cyan]{a:Artist} (25)[]{b:Album} (7f)[]{l:Length}
    song_list_format= {%a - }{%t}|{%f} $R {%l}
    song_status_format=%t $3[ %a ]$9
    startup_screen=playlist
    state_flags_color=cyan:b
    user_interface=alternative
    visualizer_color=blue,cyan,green,yellow,magenta
    visualizer_data_source=/tmp/mpd.fifo
    visualizer_in_stereo=yes
    visualizer_look=●▋
    visualizer_output_name=Visualizer
    visualizer_type=spectrum
    volume_color=cyan
    window_border_color=black
  '';

  # ncmpcpp with the config baked in (same pattern as the wrapper modules).
  ncmpcppWrapped = pkgs.writeShellScriptBin "ncmpcpp" ''
    exec ${pkgs.ncmpcpp}/bin/ncmpcpp --config ${ncmpcppConf} "$@"
  '';
in
{
  environment.systemPackages = [
    pkgs.mpc          # quick shell control: mpc toggle, mpc next, ...
    ncmpcppWrapped
  ];

  systemd.user.services.mpd = {
    description = "Music Player Daemon";
    after       = [ "network.target" "sound.target" ];
    wantedBy    = [ "default.target" ];
    serviceConfig = {
      Type         = "notify";
      ExecStartPre = "${pkgs.coreutils}/bin/mkdir -p /home/robie/.local/share/mpd/playlists";
      ExecStart    = "${pkgs.mpd}/bin/mpd --no-daemon ${mpdConf}";
    };
  };
}
