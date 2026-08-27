# Git Server Recovery Runbook — by hand, no AI required

**When to use this:** the in-lab git server (`git.home.lab`, a microVM guest of vhost2) is
gone, unreachable, or its repos are damaged — and you need the Ledger, `work`, or any other
lab repo back.

This lives in the repo, not the Ledger, on purpose: **the Ledger's own remote is the thing
that just died.** `nixos-config` has a GitHub remote and a working copy on flipper, so this
file survives a bare-metal event. Companion runbook for laptop/host restores:
`restic-restore.md` in this directory.

---

## Read this first — you probably have not lost anything

Git is replicated by construction. **Every clone is a complete copy including full history.**
Before doing anything dramatic, check what you already have:

```
ls -d ~/ledger2/.git ~/work/.git ~/nixos-config/.git
```

If flipper has a current clone, the server did not hold anything unique. Recovery is
"stand the server back up and push," not "restore data." Skip to **Path C**.

---

## The four paths, fastest first

| Path | Use when | Cost |
|---|---|---|
| **A — clone from the NAS mirror** | The server is gone but the NAS is fine | Minutes. Repos arrive as git repos. |
| **B — push from a surviving clone** | flipper (or any consumer) has the repo | Minutes. Only what that clone has. |
| **C — rebuild the guest from the flake** | The guest is gone but its volume survived | One `nixos-rebuild`. No data movement. |
| **D — restore the restic image** | The NAS mirror is also gone or stale | Slowest. Cold image, needs loop-mounting. |

Paths A and D both read the NAS but are **not** the same thing. A is a live git repo you can
clone straight from. D is a 10 GiB ext4 disk image you must restore and mount before git can
see anything inside it.

---

## Path A — clone from the NAS mirror

The mirror is a set of **git-native bare repos** on the NAS's RAIDZ2 pool, refreshed hourly by
a job on vhost1 and verified ref-identical to the server each run. See the Ledger page `git`
for how it works.

### ⚠️ Step 0 — the export is restricted to vhost1. Read this before you need it.

The NFS share is authorized for **192.168.20.40 (vhost1) and nothing else**. That was a
deliberate choice — the mirrors are plaintext `ledger2` and `work`, and the NAS's other export
reaches the trusted home VLAN. **The cost is that you cannot mount the mirror from an arbitrary
machine during an emergency.**

If vhost1 is alive, use it and skip ahead. Otherwise, in the TrueNAS UI:

- Shares → Unix (NFS) Shares → the `/mnt/tank/backups/git-mirror` share → Edit
- Add your recovery host's IP to **Authorized Hosts and IP addresses**
- Save. Takes about a minute.

Remove it again when you are done.

### Step 1 — mount it

```
mkdir -p /mnt/git-mirror && mount -t nfs -o nfsvers=4.1,hard,noatime 192.168.20.12:/mnt/tank/backups/git-mirror /mnt/git-mirror
```

If this fails with `mount program didn't pass remote address`, the host has no `mount.nfs`
helper — install `nfs-utils` (`boot.supportedFilesystems = [ "nfs" ]` on a NixOS host).

### Step 2 — check how fresh the mirror is BEFORE you trust it

```
cat /mnt/git-mirror/.last-run /mnt/git-mirror/.last-success
```

- `.last-run` — the job completed end to end.
- `.last-success` — **every** repo verified ref-identical to the server.

If `.last-success` is older than `.last-run`, some repo was failing. The mirror is still
usable; just know that at least one repo may be behind. Both stamps are UTC.

### Step 3 — clone what you need

```
git clone /mnt/git-mirror/ledger2.git ~/ledger2-recovered
```

Repos available: `ledger2`, `work`, `nixos-config`, `homeLab`, `langlab`, `qwak`, `teacha`,
`nibbles`, `languages`, `pages-content`, `test`.

### Step 4 — verify you got a real tree, not an empty one

```
cd ~/ledger2-recovered && git log --oneline -1 && ls | wc -l
```

**A populated working tree is the check that matters.** A bare repo whose `HEAD` names a
branch that does not exist clones silently into an *empty* directory — no error, no warning.
If `ls` shows nothing, see "Empty working tree" under Troubleshooting.

---

## Path B — push from a surviving clone

If the server is back up but empty (fresh guest, empty volume), refill it from any working
copy. This is the original recovery story and still works:

```
cd ~/ledger2 && git push lab HEAD:main
```

Repeat per repo. Remotes are named `lab`, not `origin`.

---

## Path C — rebuild the guest from the flake

The guest is entirely declarative. Its repo list, users, keys and permissions all come from
`hosts/vhost2/guests/git.nix`. Nothing about it is hand-configured.

```
ssh root@vhost2.home.lab systemctl restart microvm@git
```

If that is not enough, redeploy vhost2 from flipper:

```
cd ~/nixos-config && ./scripts/update-fleet.sh --no-update --no-reboot vhost2
```

On boot the guest recreates any missing bare repo (create-only, never deletes), re-owns the
tree to `git`, and repairs any repo whose `HEAD` points at a nonexistent ref.

**Expect the host key to have changed** — the guest's `/etc` is tmpfs by design, so it mints a
new one every restart. Clear the stale entry:

```
ssh-keygen -R git.home.lab
```

---

## Path D — restore the restic image (last resort)

Only if the NAS mirror is gone or too stale. The repo is
`tank/backups/services/git`; the password is in 1Password at
`devops/restic-repo-password-vhost2-git`. Full mechanics are in `restic-restore.md`.

Two gotchas that will bite:

- **Restore to a disk-backed path.** vhost2's `/` and `/var/tmp` are tmpfs, and the restore
  writes the 10 GiB image non-sparse. Use `/persist/...` and clean up afterwards.
- **Loop-mount read-only with `-o ro,noload`.** Live-capture images carry a dirty ext4
  journal. A real recovery mounts read-write and lets the journal replay.

---

## Troubleshooting

**Empty working tree after cloning.** The source repo's `HEAD` names a ref that does not
exist. Confirm with:

```
git ls-remote --symref <repo>
```

A healthy repo prints a `ref: refs/heads/<branch>  HEAD` line first. If that line is missing,
HEAD is dangling. On the lab server this repairs itself at guest boot; on a mirror or a copy,
fix it by hand:

```
git --git-dir=<repo> symbolic-ref HEAD refs/heads/main
```

**`pack-objects died of signal 9` / "possible repository corruption on the remote side".**
The repository is almost certainly **fine**. That message is upload-pack's generic reaction to
its packer being killed — on this server it has meant the guest ran out of memory packing a
repo containing large binary blobs. The guest caps `core.bigFileThreshold` and the pack window
to prevent it; if it recurs, check the guest's journal for an OOM kill before suspecting the
repo.

**Mirror is stale and nobody noticed.** The mirror job alerts by ntfy on failure and has a
separate staleness timer, but both run on vhost1 — if vhost1 itself is down, neither fires.
Check `.last-run` by hand as part of any recovery.
