{ ... }:
# Firefox — system-level port of modules/_home/firefox.nix (HM removal Phase C).
# The HM version wrote the same four prefs into the default profile's user.js;
# NixOS applies them as managed preferences instead. preferencesStatus "user"
# keeps about:config editable — the defaults are reapplied, not locked.
# Existing profile data (~/.mozilla/firefox) is untouched.
{
  programs.firefox = {
    enable = true;
    preferencesStatus = "user";
    preferences = {
      "browser.startup.homepage" = "about:blank";
      "browser.newtabpage.enabled" = false;
      "privacy.trackingprotection.enabled" = true;
      "toolkit.telemetry.enabled" = false;
    };
  };
}
