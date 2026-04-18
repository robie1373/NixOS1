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
#   nix run github:ryantm/agenix -- -r
#
# Host keys are committed at hosts/<hostname>/ssh_host_ed25519_key.pub
# Private keys are in 1Password (devops/"<hostname> host SSH key") and
# planted on the host by nixos-anywhere via --extra-files.
#
# Hard rule: hard-to-rotate secrets (CA keys, master credentials) never go
# here. 1Password only. See CLAUDE.md Secrets section.

let
  # Host SSH public keys — age recipients
  ntfy    = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFsO2AFvp2lJUJAyQ3PXWbU1/nrDEcN/UuqzfMXoC+aQ";
  omada   = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMAptqMehU2xN/Oc/s26C9GC3TggyoxRuhisDkFrtxYo";
  langlab = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDb0aYMGmaB70EJZ32jqi9+tKncViDYp9CEYUAuoa2Td";
  flipper = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIL8IYPm1NhuaOhtarrtZTCDXtETLqA7IHSBvQCKaAAjO";
  fivenix = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPjxC4iKXkoDqa8RQVoxelZfnCZM9HtRQbV0yoJbMImM";

  # All servers that use tailscale-autoconnect.nix must be listed here.
  # Re-key after adding each new server: nix run github:ryantm/agenix -- -r
  tailscaleServers = [ ntfy omada langlab ];
in
{
  # ntfy admin password — local user database (pre-Kanidm migration)
  # After Kanidm is deployed, migrate ntfy auth to LDAP and remove this secret.
  "ntfy-admin-password.age".publicKeys = [ ntfy ];

  # Tailscale reusable auth key — shared across all lab servers.
  # Source: 1Password devops/"Tailscale Auth Key" — must be a reusable key.
  # To create/re-encrypt: nix run github:ryantm/agenix -- -e secrets/tailscale-auth-key.age
  "tailscale-auth-key.age".publicKeys = tailscaleServers;

  # LangLab API keys — systemd EnvironmentFile consumed by the langlab service.
  # Contents (KEY=value, one per line):
  #   GEMINI_API_KEY=<key>
  #   CLAUDE_API_KEY=<key>
  # Source: 1Password devops/"LangLab env"
  "langlab-env.age".publicKeys = [ langlab ];

  # Restic backup SSH keys — ed25519 keypairs used by restic SFTP to authenticate
  # as svc_backup on the NAS. One per host. Private key encrypted here; public key
  # must be added to svc_backup's authorized_keys on the NAS.
  # Source: 1Password devops/"restic-backup-<hostname>"
  "restic-backup-flipper.age".publicKeys  = [ flipper ];
  "restic-backup-fivenix.age".publicKeys  = [ fivenix ];
  "restic-backup-ntfy.age".publicKeys     = [ ntfy ];
  "restic-backup-omada.age".publicKeys    = [ omada ];
  "restic-backup-langlab.age".publicKeys  = [ langlab ];

  # Restic repo passwords — one per host, used to encrypt backup data at rest.
  # Source: 1Password devops/"restic-repo-password-<hostname>"
  # Keep a copy in 1Password — needed at restore time when the host may be unavailable.
  "restic-repo-password-flipper.age".publicKeys  = [ flipper ];
  "restic-repo-password-fivenix.age".publicKeys  = [ fivenix ];
  "restic-repo-password-ntfy.age".publicKeys     = [ ntfy ];
  "restic-repo-password-omada.age".publicKeys    = [ omada ];
  "restic-repo-password-langlab.age".publicKeys  = [ langlab ];
}
