# Runbook: Debug a Build Failure

---

## Step 1 — Get the full error

The shell aliases truncate output. Use the explicit command and pipe to a pager:

```bash
nixos-rebuild build --flake .#<hostname> 2>&1 | less
```

Or to a file for easier reading:

```bash
nixos-rebuild build --flake .#<hostname> 2>&1 | tee /tmp/build-error.txt
less /tmp/build-error.txt
```

---

## Step 2 — Match the error to a known type

### "attribute '<x>' missing" or "undefined variable '<x>'"

**Cause:** A module references an option or variable that doesn't exist in scope.

**Most common causes in this repo:**
- Module file not listed in `parts/nixos.nix`. The module file exists but was never imported.
  → Check that the module is in the `modules = [ ... ]` list (system) or `home-manager.users.robie.imports = [ ... ]` (home) for the relevant host.
- Typo in option name (`mySystem.audio` vs `mySystem.Audio`).
- Using a deprecated alias that was removed. Check the current option name at [search.nixos.org](https://search.nixos.org/options).

**Quick check:**

```bash
# Does the option path exist?
nix eval .#nixosConfigurations.<hostname>.options.mySystem.<name> 2>&1
```

---

### "infinite recursion encountered"

**Cause:** A `config` value depends on itself — either directly or through a chain of options.

**Most common causes:**
- Using `config.<option>` inside the same `config` block that defines `<option>`.
- A `mkIf` condition that reads from `config` in a way that creates a loop.

**Diagnostic:**

```bash
# Increase recursion limit to see further into the stack
NIX_SHOW_STATS=1 nixos-rebuild build --flake .#<hostname> 2>&1 | head -50
```

The error will show which attribute triggered the recursion. Trace that option back to where it's defined.

---

### "error: value is X while Y was expected" (type error)

**Cause:** Wrong type passed to a NixOS option.

**Common cases in this repo:**
- Passing a string where a list is expected (e.g. `environment.systemPackages = pkgs.foo` instead of `[ pkgs.foo ]`).
- Passing a boolean where a string is expected.
- `services.someService.settings` expecting an attrset, receiving a list.

**Fix:** Check the option's type at [search.nixos.org](https://search.nixos.org/options) or in the nixpkgs source.

---

### "file not found" or "path does not exist"

**Cause:** A file path referenced in the flake doesn't exist on disk.

**Common causes:**
- New host file not created yet (e.g. `hosts/<name>/configuration.nix` missing).
- Typo in a path in `parts/nixos.nix`.
- A `pkgs.runCommand` or `builtins.readFile` pointing at a path that doesn't exist.

---

### "collision between packages" (home-manager activation, not build)

**Cause:** Two HM modules install the same file to the same path.

**Symptom:** Build succeeds, but `nixos-rebuild switch` fails at the home-manager activation step.

**Fix:** Find the conflicting file and determine which module owns it. Usually one module should be disabled, or one definition should be removed.

```bash
# See HM activation output
journalctl --user -u home-manager-robie.service -n 50
```

---

### "backupFileExtension" error during HM activation

**Symptom:** "Existing file ... is not owned by Home Manager"

**Cause:** A file that HM wants to manage as a symlink already exists as a real file (e.g. written by KDE or another tool).

**Fix:** This should not happen — `backupFileExtension = "backup"` is set in `parts/nixos.nix`. If it does:

```bash
# Find the conflicting file (reported in the error) and rename or remove it
mv ~/.config/<conflicting-file> ~/.config/<conflicting-file>.bak
sudo nixos-rebuild switch --flake .#<hostname>
```

---

## Step 3 — Test a single module file for syntax errors

```bash
# Parse check only (catches syntax errors, not type errors)
nix-instantiate --parse modules/system/<name>.nix
nix-instantiate --parse modules/home/<name>.nix
```

---

## Step 4 — Evaluate without building (faster feedback)

```bash
# Evaluate the full NixOS config — catches attribute and type errors without
# actually building any derivations
nix eval .#nixosConfigurations.<hostname>.config.system.build.toplevel --no-build 2>&1 | head -30
```

---

## Step 5 — Rollback

If a bad config was activated:

```bash
sudo nixos-rollback          # activate previous generation
git checkout flake.lock      # if the issue was a flake update
```

List all generations:

```bash
sudo nix-env --list-generations --profile /nix/var/nix/profiles/system
```
