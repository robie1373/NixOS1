# Runbook: Wrapping a Program with nix-wrapper-modules

This runbook documents how to wrap a program as a self-contained Nix derivation
with its config baked in. This is the Phase 1.7 pattern for all desktop programs
in the dendritic migration.

**Reference:** `github.com/BirdeeHub/nix-wrapper-modules` — 40+ program wrappers available.

---

## Two Paths

### Path A — nix-wrapper-modules (supported programs)

For programs with an existing wrapper: foot, rofi, waybar, zathura, kitty, and ~40 others.
Check `nix-wrapper-modules.wrappers` in the flake.

### Path B — custom symlinkJoin (unsupported programs)

For programs not in nix-wrapper-modules (fish, dunst, hypridle, hyprlock, hyprpaper).
Use `pkgs.writeText` + `pkgs.writeShellScriptBin` + `pkgs.symlinkJoin`.

---

## Path A: nix-wrapper-modules Wrapper

### File layout

```
modules/programs/<name>/default.nix
```

### Template

```nix
{ inputs, ... }:
{
  perSystem = { pkgs, ... }: {
    packages.<name> =
      inputs.nix-wrapper-modules.wrappers.<name>.wrap {
        inherit pkgs;
        # program-specific options here
      };
  };
}
```

### Config format per program

| Program | Config key | Format |
|---------|------------|--------|
| foot    | `settings` | Nix attrset → INI sections (`main = { font = "..."; }`) |
| rofi    | `settings` | Nix attrset → `configuration { }` block; `theme` = string path |
| waybar  | `settings` | Nix attrset → JSON (see waybar docs for module names) |
| zathura | (see source) | Key/value options, per `man zathurarc` |

### Critical gotcha: derivation vs string for rofi `theme`

`pkgs.writeText` returns a **derivation**, which is a Nix attrset. The rofi wrapper's
`builtins.isAttrs` check treats any attrset as a Rasi section attrset and tries to call
`toRasi` on it — which fails with "Unhandled value type set" on the derivation's own attrs.

**Fix:** coerce the derivation to its store-path string before passing:

```nix
let
  theme = pkgs.writeText "catppuccin-macchiato.rasi" ''...rasi content...'';
in
inputs.nix-wrapper-modules.wrappers.rofi.wrap {
  inherit pkgs;
  theme = "${theme}";   # <-- coerce to string; wrapper then emits @theme "/nix/store/..."
  settings = { ... };
};
```

This applies anywhere a wrapper API uses `builtins.isAttrs` to dispatch on input type.

---

## Path B: Custom symlinkJoin Wrapper

For programs not supported by nix-wrapper-modules. The pattern:

1. **Write config to the store** with `pkgs.writeText`
2. **Wrap the binary** with `pkgs.writeShellScriptBin` — exec the real binary, injecting
   config via a flag or env var
3. **Merge binaries** with `pkgs.symlinkJoin` — the wrapper binary shadows the real one,
   but all other files (man pages, completions, data) are reachable via symlinks

### Template

```nix
{ inputs, ... }:
{
  perSystem = { pkgs, ... }: {
    packages.<name> =
      let
        config = pkgs.writeText "<name>.conf" ''
          # ... program config ...
        '';
        wrapper = pkgs.writeShellScriptBin "<name>" ''
          exec ${pkgs.name}/bin/<name> --config ${config} "$@"
        '';
      in
      pkgs.symlinkJoin {
        name = "<name>";
        paths = [ wrapper pkgs.<name> ];
        # wrapper is listed first — its bin/<name> takes priority over pkgs.<name>'s
      };
  };
}
```

### Fish wrapper: `--init-command`

Fish has no `--config` flag for interactive sessions. Use `--init-command` (`-C`) to
source a config file before the shell becomes interactive:

```nix
wrapper = pkgs.writeShellScriptBin "fish" ''
  exec ${pkgs.fish}/bin/fish --init-command "source ${configFish}" "$@"
'';
```

Fish data files (completions, functions, `$__fish_data_dir`) are resolved at compile time
to the real fish store path, so the symlinkJoin wrapper has full access to all fish built-ins.

### Fish as login shell: `shellPath` and per-host wiring

`symlinkJoin` does not inherit `shellPath` from the wrapped package. NixOS requires
`shellPath` to be set on any package used as a login shell (via `users.users.*.shell`
or listed in `environment.shells`). Without it, evaluation fails with a type error.

**Fix:** append `shellPath` with `//` after the `symlinkJoin` call:

```nix
(pkgs.symlinkJoin {
  name = "fish";
  paths = [ fishWrapper pkgs.fish ];
}) // { shellPath = "/bin/fish"; };
```

**Do not set the login shell in a shared feature module** (e.g. `_features/common.nix`).
Hosts that don't use the wrapped fish (e.g. a minimal VM) would break. Set it per-host:

```nix
# hosts/<name>/configuration.nix
{ self, pkgs, ... }:
{
  users.users.robie.shell = self.packages.${pkgs.system}.fish;
  environment.shells      = [ self.packages.${pkgs.system}.fish ];
}
```

`environment.shells` must include the wrapped path — `programs.fish.enable` only registers
`pkgs.fish`, not the wrapper. Without the entry, login authentication may reject the shell.

### Aliases in Fish config

Fish's `alias` command creates a wrapper function that passes `$argv`. Use it for simple
aliases. For anything that needs `$argv[1]` explicitly (like positional args), write a
full `function ... end` block:

```fish
alias ll 'ls -lh'         # simple alias — $argv auto-appended

function gc               # needs $argv[1] explicitly
  sudo nix-env --delete-generations $argv[1] --profile /nix/var/nix/profiles/system \
    && nix-env --delete-generations $argv[1] \
    && sudo nix-collect-garbage
end
```

---

## Wiring the wrapper into a host

1. Add the package to `home.packages` in the host's `home.nix`:
   ```nix
   home.packages = with self.packages.${pkgs.system}; [
     foot rofi waybar fish   # ...
   ];
   ```

2. For programs launched at desktop startup (exec-once), use the full store path:
   ```nix
   exec-once = [
     "${self.packages.${pkgs.system}.waybar}/bin/waybar"
   ];
   ```
   PATH is not populated when greetd starts Hyprland — full paths are required.

3. For keybinds inside Hyprland, same rule — use full store paths:
   ```nix
   "$mod, Return, exec, ${self.packages.${pkgs.system}.foot}/bin/foot"
   ```

4. `self` must be in `home-manager.extraSpecialArgs` for HM modules to reference it:
   ```nix
   home-manager.extraSpecialArgs = { inherit self; };
   ```
   The HM module receives it via `{ ..., self, ... }:` in its args.

---

## `useUserPackages = true` — where binaries land

With `useUserPackages = true`, `home.packages` are installed to:
```
/etc/profiles/per-user/<user>/bin/
```
Not `~/.nix-profile/bin/`. This path is on `$PATH` in a Hyprland session, but **not**
when Hyprland itself is launched by greetd (hence full store paths for exec-once/keybinds).

---

## Testing after rebuild

```bash
# Build only (no activation):
build   # → nh os build /home/robie/nixos-config

# Activate without becoming boot default:
ntest   # → nh os test /home/robie/nixos-config

# Verify binary is the wrapper (check store path):
which foot
readlink -f $(which foot)

# Test a wrapped program directly:
/etc/profiles/per-user/robie/bin/foot
/etc/profiles/per-user/robie/bin/rofi -show drun
/etc/profiles/per-user/robie/bin/waybar
```

---

## Lessons learned

| Issue | Cause | Fix |
|-------|-------|-----|
| `attribute 'zathuraPlugins' missing` | Correct attr is `zathuraPkgs` | Use `pkgs.zathuraPkgs` |
| Rofi: "Unhandled value type set" | `pkgs.writeText` returns a derivation (attrset); wrapper calls `toRasi` on it | Coerce: `"${theme}"` |
| `waybar: command not found` in PATH | `useUserPackages = true` — binary is in `/etc/profiles/per-user/…/bin/` | Expected; use full path for exec-once |
| Fish aliases missing after removing programs.fish | `home.shellAliases` applies via `programs.fish.shellAliases` — removing the module drops them | Bake all aliases into the wrapper's config.fish |
| `symlinkJoin` wrapper rejected as login shell | `shellPath` attribute missing — NixOS `types.shellPackage` requires it | Add `// { shellPath = "/bin/fish"; }` after the `symlinkJoin` call |
| Wrapped fish not launching in terminal | `users.users.robie.shell` still pointed to `pkgs.fish`, not the wrapper | Set shell to `self.packages.${pkgs.system}.fish` per-host, not in shared feature module |
| Login shell not in `/etc/shells` | `programs.fish.enable` only registers `pkgs.fish`; wrapper path is absent | Add `environment.shells = [ self.packages.${pkgs.system}.fish ]` in host config |
