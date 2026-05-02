# 1Password HM → NixOS Migration Plan

Written before any code changes. Decisions are recorded here so they can be reviewed
if something breaks.

## What moves and where

All four items from `modules/_home/1password.nix` move to `modules/_features/1password.nix`.
The goal is transplant, not simplification. Nothing is removed until it's been verified
working at the NixOS level.

### 1. SSH_AUTH_SOCK

**From (HM):**
```nix
home.sessionVariables.SSH_AUTH_SOCK = "~/.1password/agent.sock";
```

**To (NixOS):**
```nix
environment.sessionVariables.SSH_AUTH_SOCK = "/home/robie/.1password/agent.sock";
```

NixOS `environment.sessionVariables` writes to `/etc/environment` via PAM. This is more
fundamental than HM's approach (`~/.profile`): it is inherited by all login shells, all
graphical sessions, and all systemd user units. Path is hardcoded (HM used
`config.home.homeDirectory`), which is correct for a single-user machine.

### 2. Bash export

**From (HM):**
```nix
programs.bash.initExtra = ''
  export SSH_AUTH_SOCK="${config.home.homeDirectory}/.1password/agent.sock"
'';
```

**To (NixOS):**
```nix
programs.bash.interactiveShellInit = ''
  export SSH_AUTH_SOCK="/home/robie/.1password/agent.sock"
'';
```

Appends to `/etc/bash.bashrc` (system-wide interactive bash init). The HM version covered
contexts where `home.sessionVariables` didn't reach. At NixOS level, `environment.sessionVariables`
via PAM is more comprehensive, but this is kept as documented safety. Reason the original was
needed: unknown. Do not assume it's redundant.

### 3. IdentityAgent in ssh_config

**From (HM):**
```nix
programs.ssh = {
  enable = true;
  enableDefaultConfig = false;
  matchBlocks."*" = {
    identityAgent = "${config.home.homeDirectory}/.1password/agent.sock";
  };
};
```
Generated `~/.ssh/config` with `Host *` / `IdentityAgent`.

**To (NixOS):**
```nix
programs.ssh.extraConfig = ''
  Host *
    IdentityAgent /home/robie/.1password/agent.sock
'';
```

Appends to `/etc/ssh/ssh_config`. After HM is removed there is no `~/.ssh/config`,
so the system config applies cleanly. The `~` in `IdentityAgent` expands to the user's
home at SSH runtime — using the full path instead to avoid any ambiguity.

**Critical:** SSH_AUTH_SOCK alone was NOT sufficient on this system. The IdentityAgent
line was required for SSH auth to work. Reason unknown. Do not remove it.

### 4. onepassword-gui user service

**From (HM):**
```nix
systemd.user.services.onepassword-gui = {
  Unit = {
    Description = "1Password GUI";
    After = [ "graphical-session.target" ];
    PartOf = [ "graphical-session.target" ];
  };
  Service = {
    ExecStart = "/run/current-system/sw/bin/1password --silent --disable-gpu";
    Restart = "on-failure";
  };
  Install.WantedBy = [ "graphical-session.target" ];
};
```

**To (NixOS):**
```nix
systemd.user.services.onepassword-gui = {
  description = "1Password GUI";
  wantedBy    = [ "graphical-session.target" ];
  after       = [ "graphical-session.target" ];
  partOf      = [ "graphical-session.target" ];
  serviceConfig = {
    ExecStart = "/run/current-system/sw/bin/1password --silent --disable-gpu";
    Restart   = "on-failure";
  };
};
```

NixOS-level user services land in `/etc/systemd/user/`. The `wantedBy` option (NixOS
lowercasekey, not systemd [Install] directive) causes NixOS to create the symlink in
`/etc/systemd/user/graphical-session.target.wants/`. Equivalent to what HM activation did.

`--disable-gpu`: Required. Caused session crashes on flipper without it.
`--silent`: Start to tray, no main window.

## Sequence

1. Add all four items to `_features/1password.nix` (keep `_home/1password.nix` active)
2. `nh os build` — confirm clean build
3. `nh os test` — activate without making it the boot default
4. Verify (with HM still active):
   - `echo $SSH_AUTH_SOCK` → `/home/robie/.1password/agent.sock`
   - `ssh -T git@github.com` → authenticated
   - `op item get <any item>` → returns data
   - `git push` on any repo → succeeds
5. Remove `../../_home/1password.nix` from the imports list in `modules/hosts/flipper/default.nix`
6. `nh os test` again
7. Repeat all four checks
8. Reboot (full cycle, not just test)
9. Repeat all four checks after login
10. `nh os switch`

## Rollback

Git tag `pre-1password-migration` → commit `bee01ede0a9b58232d3145c6f0c75f931b80a1c7`

If nixos-rollback fails: `git checkout pre-1password-migration && sudo nixos-rebuild switch --flake .`
