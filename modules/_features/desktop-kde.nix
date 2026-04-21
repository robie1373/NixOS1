# modules/_features/desktop-kde.nix
#
# KDE Plasma 6 desktop. Enables SDDM, Plasma 6, X11 (required by SDDM), Firefox.
# To switch back to Hyprland: swap this for _features/desktop-hyprland.nix in
# modules/hosts/<host>/default.nix and re-enable _home/desktop-hyprland.nix.
{ ... }:
{
  services.xserver.enable                = true;
  services.displayManager.sddm.enable   = true;
  services.desktopManager.plasma6.enable = true;

  services.xserver.xkb = {
    layout  = "us";
    variant = "";
  };

  # polkit is pulled in by the Hyprland feature; keep it explicit here so
  # 1Password and other polkit agents work regardless of which desktop is active.
  security.polkit.enable = true;

  programs.firefox.enable = true;
}
