# 1Password — Safe Rollback Point

## Git tag
```
tag:    pre-1password-migration
commit: bee01ede0a9b58232d3145c6f0c75f931b80a1c7
branch: refactor/dendritic
```

To restore to this state:
```bash
git checkout pre-1password-migration
# or
git checkout bee01ede0a9b58232d3145c6f0c75f931b80a1c7
```

This commit is the last known-good state of the 1Password config before any
HM → NixOS migration work. 1Password SSH agent was working at this point:
SSH auth, git push, op CLI all functional.

## Why this doc exists

1Password took days to get working. The current config in `modules/_home/1password.nix`
has four components that all need to be present. See the inline comments in that file
and the full analysis in any Claude session that reads this.

## Before touching 1Password config

Read `modules/_home/1password.nix` in full. Every line is load-bearing.
Then write `docs/flipper/1password-wrapper-plan.md` before changing anything.
Test each piece individually. Do not batch changes.

Verification checklist after any change:
- [ ] `echo $SSH_AUTH_SOCK` → `/home/robie/.1password/agent.sock`
- [ ] `ssh -T git@github.com` → authenticated (not permission denied)
- [ ] `op item get <any item>` → returns data (not auth error)
- [ ] `git push` on any repo → succeeds
- [ ] Reboot → all of the above still work on next login
