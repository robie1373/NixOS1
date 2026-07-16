# secrets/secrets.nix
#
# agenix recipient declarations. Each secret lists which hosts can decrypt it,
# identified by their SSH public key (used as an age recipient).
#
# To add a new secret:
#   1. Add an entry here with the appropriate host keys as recipients
#   2. Run: nix run github:ryantm/agenix -- -e secrets/<name>.age
#   3. Commit the encrypted .age file (safe — only listed hosts can decrypt)
#
# To re-key after adding a new host:
#   cd ~/nixos-config/secrets && nix run github:ryantm/agenix -- -r
#   (must be run from secrets/ dir; admin key allows re-keying from flipper)
#
# Host keys are committed at hosts/<hostname>/ssh_host_ed25519_key.pub
# Private keys are in 1Password (devops/"<hostname> host SSH key") and
# planted on the host by nixos-anywhere via --extra-files.
#
# Hard rule: hard-to-rotate secrets (CA keys, master credentials) never go
# here. 1Password only. See CLAUDE.md Secrets section.

let
  # Admin key — robie's personal SSH key on flipper (~/.ssh/id_ed25519).
  # Added to ALL secrets so agenix -r can always be run from flipper.
  # This is the standard agenix admin pattern — keeps re-keying unblocked.
  admin = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIC/F5DsOqJb2KM0JGV3Tx6kYVYOxR0xXGuJOyu/benFU";

  # Host SSH public keys — age recipients
  ntfy    = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFsO2AFvp2lJUJAyQ3PXWbU1/nrDEcN/UuqzfMXoC+aQ";
  omada   = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMAptqMehU2xN/Oc/s26C9GC3TggyoxRuhisDkFrtxYo";
  langlab = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDb0aYMGmaB70EJZ32jqi9+tKncViDYp9CEYUAuoa2Td";
  flipper = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIL8IYPm1NhuaOhtarrtZTCDXtETLqA7IHSBvQCKaAAjO";
  fivenix = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOWzymn122S/aRhofQtfxsjze7dVxH/tmB/6UsVdG8Z0";
  dns1    = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIG7QRVt1c+o7HR1OQBqcvrRY4T4fLksAKbPCmGJjC8hE";
  dns2    = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIK5FZLBveMFgzXA/xYHGgMRu9urFqf+H7Q43jilwF/n0";
  nixsrv1 = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJX6AZgzVx5nVNG8AujqQ6Knchc79NrowlUaYH1fPLIZ";
  observ  = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINQnS795H+GiGzkNsoWrcfyMD7BLcZMO/gheMgcBKAEO";
  pages   = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICtcGrKW2op/gqVOUqS29Uhr7++xogRQo/fVlsaaNrof";
  # vhost2 (formerly pve2) — NixOS+microvm hypervisor, all-nixos-lab rung 4.
  # No agenix secrets target it yet (guests carry their own); listed so `agenix -r`
  # includes it and future host secrets can be added. NOT in tailscaleServers.
  vhost2  = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIN9de13zdtiIsB15rigtdziSOLWbYSQuBZn6KE8ynPCq";

  # All servers that use tailscale-autoconnect.nix must be listed here.
  # Re-key after adding each new server: cd secrets && nix run github:ryantm/agenix -- -r
  tailscaleServers = [ admin ntfy omada langlab dns1 dns2 nixsrv1 observ pages ];

  # Bare-metal NixOS hypervisors — recipients of the fleet console-recovery root
  # password (consumed by modules/_system/hypervisor.nix hashedPasswordFile). Only
  # machines with a real console belong here; the microVM guests never do (no
  # console — recovered from their host). vhost1 joins at its host-key ceremony
  # (all-nixos-lab rung 5). Re-key after adding: cd secrets && agenix -- -r.
  hypervisors = [ admin vhost2 nixsrv1 ];
in
{
  # Fleet root console-recovery password (sha-512 crypt hash). Break-glass login
  # at the JetKVM/physical console when a hypervisor is up but unreachable — the
  # locked-root trap we dodged on the vhost2 conversion (Robie, 2026-07-05).
  # Consumed by hypervisor.nix (users.users.root.hashedPasswordFile). Plaintext is
  # in 1Password devops/"Hypervisor root recovery (fleet)".
  "root-recovery.age".publicKeys = hypervisors;

  # ntfy admin password — local user database (pre-Kanidm migration)
  # After Kanidm is deployed, migrate ntfy auth to LDAP and remove this secret.
  "ntfy-admin-password.age".publicKeys = [ admin ntfy ];

  # ntfy alert topic — the (secret) topic name the alerting spine on observ
  # publishes to; same topic Robie's phone subscribes to (source of truth:
  # /home/robie/work/.ntfy-topic on flipper). Topic obscurity is ntfy's access
  # model, hence secret-grade handling.
  "ntfy-alert-topic.age".publicKeys = [ admin observ vhost2 ];  # vhost2 added 2026-07-06: patch-automation ntfy reports

  # Patch-automation git deploy key — read+write to the NixOS1 repo (GitHub
  # deploy key, minted 2026-07-06). The lab's first standing off-op push
  # credential: held by hypervisors (doctrine law 3), Robie minted it
  # deliberately. Recipients = admin + vhost2 today; ADD vhost1 AT ITS HOST-KEY
  # CEREMONY (agenix -r). Source: 1Password devops/"patch-automation deploy key".
  "patch-deploy-key.age".publicKeys = [ admin vhost2 ];

  # Grafana admin password (observ visibility host). Makes the admin login
  # durable across redeploys — otherwise the UI-set password lives on the
  # disposable disk and resets to the module default on reinstall.
  # Source: 1Password devops/"grafana - homelab".
  "grafana-admin-pass.age".publicKeys = [ admin observ ];

  # snmp_exporter config for the Omada fabric (switch + EAP773 APs) — the WHOLE
  # snmp.yml with the community baked in. (snmp_exporter 0.30.1's env-var expansion
  # doesn't substitute the community, so we can't keep it in an EnvironmentFile;
  # the config is delivered whole instead.) Decrypted file is consumed via
  # configurationPath and read by the exporter's DynamicUser, so it's mode 0444.
  # Regenerate from modules/_system/snmp.yml — see that file's header.
  # Source community: 1Password devops/"Omada SNMP community string".
  "snmp-config.age".publicKeys = [ admin observ ];

  # Tailscale reusable auth key — shared across all lab servers.
  # Source: 1Password devops/"Tailscale Auth Key" — must be a reusable key.
  # To create/re-encrypt: nix run github:ryantm/agenix -- -e secrets/tailscale-auth-key.age
  "tailscale-auth-key.age".publicKeys = tailscaleServers;

  # LangLab API keys — systemd EnvironmentFile consumed by the langlab service.
  # Contents (KEY=value, one per line):
  #   GEMINI_API_KEY=<key>
  #   CLAUDE_API_KEY=<key>
  # Source: 1Password devops/"LangLab env"
  "langlab-env.age".publicKeys = [ admin langlab ];

  # Restic backup SSH keys — ed25519 keypairs used by restic SFTP to authenticate
  # as svc_backup on the NAS. One per host. Private key encrypted here; public key
  # must be added to svc_backup's authorized_keys on the NAS.
  # Source: 1Password devops/"restic-backup-<hostname>"
  "restic-backup-flipper.age".publicKeys  = [ admin flipper ];
  "restic-backup-fivenix.age".publicKeys  = [ admin fivenix ];
  "restic-backup-ntfy.age".publicKeys     = [ admin ntfy ];
  "restic-backup-omada.age".publicKeys    = [ admin omada ];
  # vhost2 runs the omada guest's backup (all-nixos-lab rung 4). Named per
  # runner+service (vhost2-omada) since vhost2 will host more guests, each with
  # its own reused creds. Same material as restic-backup-omada, re-encrypted to
  # vhost2 → same NAS repo + svc_backup key, no NAS-side change.
  "restic-backup-vhost2-omada.age".publicKeys = [ admin vhost2 ];
  "restic-backup-langlab.age".publicKeys  = [ admin langlab ];

  # Restic repo passwords — one per host, used to encrypt backup data at rest.
  # Source: 1Password devops/"restic-repo-password-<hostname>"
  # Keep a copy in 1Password — needed at restore time when the host may be unavailable.
  "restic-repo-password-flipper.age".publicKeys  = [ admin flipper ];
  "restic-repo-password-fivenix.age".publicKeys  = [ admin fivenix ];
  "restic-repo-password-ntfy.age".publicKeys     = [ admin ntfy ];
  "restic-repo-password-omada.age".publicKeys    = [ admin omada ];
  "restic-repo-password-vhost2-omada.age".publicKeys = [ admin vhost2 ];
  # git guest's repo password — NEW repo (tank/backups/services/git); transport
  # reuses restic-backup-vhost2-omada (same svc_backup NAS key; documented reuse
  # path in restic.nix — separate repo + password keep the piles apart). Also in
  # 1Password devops/"restic-repo-password-vhost2-git". (2026-07-16, Fable 5)
  "restic-repo-password-vhost2-git.age".publicKeys = [ admin vhost2 ];
  "restic-repo-password-langlab.age".publicKeys  = [ admin langlab ];
}
