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
  ntfy   = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFsO2AFvp2lJUJAyQ3PXWbU1/nrDEcN/UuqzfMXoC+aQ";
  omada  = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMAptqMehU2xN/Oc/s26C9GC3TggyoxRuhisDkFrtxYo";

  # langlab: PLACEHOLDER — replace with real key from hosts/langlab/ssh_host_ed25519_key.pub
  # after running Phase 3 of new-nixos-service.md, then re-key:
  #   nix run github:ryantm/agenix -- -r
  langlab = "REPLACE_WITH_REAL_KEY_FROM_hosts/langlab/ssh_host_ed25519_key.pub";

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
  # Encrypt: op read 'op://devops/LangLab env/notesPlain' | \
  #   nix run nixpkgs#age -- -r "<langlab-pubkey>" -o secrets/langlab-env.age
  "langlab-env.age".publicKeys = [ langlab ];
}
