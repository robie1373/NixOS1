~/nixos-config/
├── flake.nix
├── flake.lock
├── modules/
│   ├── system/
│   │   ├── common.nix         # Timezone, SSH, common packages
│   │   ├── desktop-gui.nix    # Plasma, Wayland, Audio
│   │   └── server-base.nix    # Headless tweaks, Fail2Ban
│   └── home/
│       ├── common.nix         # Bash/Zsh, Git, Neovim
│       └── desktop-apps.nix   # Firefox, VLC, obsidian
├── hosts/
│   ├── workstation/           # A physical PC
│   │   ├── configuration.nix  # Host-specific tweaks
│   │   └── hardware.nix       # Result of nixos-generate-config
│   └── web-vm/                # A Proxmox/LXC/Cloud VM
│       ├── configuration.nix
│       └── hardware.nix       # Minimal or virt-specific
└── lib/                       # (Optional) Custom helper functions


