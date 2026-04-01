# modules/_system/tailscale-autoconnect.nix
#
# Automated Tailscale join on first boot using an agenix-encrypted auth key.
# Requires tailscale-auth-key.age to be encrypted for the importing host.
#
# Usage: import from individual host configs (NOT server-common) until all
# hosts have the secret encrypted for them. Once all servers have it, this
# can be moved into server-common.nix.
#
# Provisioning note:
#   - Before nixos-anywhere: generate host key, add to secrets.nix recipients,
#     then re-key: nix run github:ryantm/agenix -- -r
#   - Auth key source: 1Password devops/"Tailscale Auth Key" — must be a
#     REUSABLE key (not one-time-use). Tag: tag:terraformhost.
#   - Idempotent: tailscale up is a no-op if already connected.

{ config, ... }:

{
  services.tailscale = {
    authKeyFile = config.age.secrets.tailscale-auth-key.path;
    extraUpFlags = [
      "--ssh"
      "--advertise-tags=tag:terraformhost"
    ];
  };

  age.secrets.tailscale-auth-key = {
    file = ../../secrets/tailscale-auth-key.age;
  };
}
