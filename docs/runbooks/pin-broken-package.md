# Runbook: Pinning a Broken nixpkgs Package

Use this when `nix flake update` pulls in a nixpkgs commit where a package is broken (e.g. fetches a version that 404s on the upstream registry).

## Strategy

Add a `nixpkgs.overlays` entry in the affected host's `configuration.nix` that overrides the broken package to a known-good version. The overlay is **unconditional** — remove it once nixpkgs ships a working version.

See `hosts/flipper/configuration.nix` for a live example (claude-code).

---

## Lessons learned from claude-code (2026-04-05)

### 1. You cannot conditionally check `prev.<pkg>.version` in a NixOS overlay

Accessing `prev.claude-code.version` inside `nixpkgs.overlays` causes infinite recursion via `pkgs/top-level/by-name-overlay.nix`. The overlay must be unconditional. Document the known-broken versions in a comment instead.

### 2. Understand the package builder before overriding

`buildNpmPackage` packages need three things overridden — not just `src`:
- `src` — use `fetchzip`, not `fetchurl` (strips the top-level directory)
- `postPatch` — may be required to supply a `package-lock.json`
- `npmDeps` — must be rebuilt with `fetchNpmDeps`, passing both `src` and `postPatch`

Getting the wrong fetcher (`fetchurl` vs `fetchzip`) produces a hash mismatch even with the correct hash. Read the upstream `package.nix` first:

```bash
cat $(nix eval --raw nixpkgs#claude-code.meta.position | cut -d: -f1)
# or find it in /nix/store/<hash>-source/pkgs/by-name/...
```

### 3. `fetchNpmDeps` needs `postPatch` forwarded

`buildNpmPackage` internally passes `postPatch` to `fetchNpmDeps` so it can find the `package-lock.json`. When constructing `npmDeps` manually in `overrideAttrs`, you must do the same:

```nix
npmDeps = prev.fetchNpmDeps {
  inherit src postPatch;
  name = "...";
  hash = "sha256-...";
};
```

### 4. The package-lock.json may live in nixpkgs, not the upstream tarball

claude-code's tgz does not include a `package-lock.json`. nixpkgs ships one alongside `package.nix`. To pin to an old version, fetch the lock file from the old nixpkgs commit and store it in the repo:

```bash
curl -sf "https://raw.githubusercontent.com/NixOS/nixpkgs/<old-rev>/pkgs/by-name/cl/claude-code/package-lock.json" \
  -o hosts/flipper/claude-code-<version>-package-lock.json
```

### 5. Path references require `git add`

Files referenced via `${./relative-path}` in nix expressions must be tracked by git (even if not committed) when building from a flake. Nix copies the git-tracked tree into the store and the file won't exist otherwise.

```bash
git add hosts/flipper/claude-code-2.1.77-package-lock.json
```

---

## To update the pin

1. Get the new version's hashes from nixpkgs `package.nix`
2. Fetch the new `package-lock.json` from that nixpkgs commit
3. Update `version`, `src.hash`, `postPatch` path, and `npmDeps.hash` in the overlay
4. `git add` the new lock file
5. If the new version builds cleanly without the overlay, remove the overlay entirely
