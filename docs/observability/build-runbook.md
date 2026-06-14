# Visibility stack — build runbook

**Stack:** VictoriaMetrics (metrics) + VictoriaLogs (logs) + Grafana (dashboards),
agents = node-exporter + Grafana Alloy on every lab server.

**Decided + deployed:** 2026-06-14 (fresh requirements interview; replaces the
stale `homeLab/docs/design-docs/logging-proposal.md`, which was Loki/Blocky-centric).

## STATUS: DEPLOYED 2026-06-14

- **VMID 114** on pve, **192.168.20.56/24** VLAN 20, 2 vCPU / 2048 MB / 16 GB, OVMF.
- Tailscale: `observ` / `100.70.13.99` / observ.vimba-stairs.ts.net.
- Host SSH key: 1Password devops / "observ host SSH key".
- Grafana http://192.168.20.56:3000 (admin/admin first login — change it).
- Verified: all services active, agenix secret non-empty, survives a reboot
  with 0 failed units and auto-rejoins Tailscale.
- **Provisioned end-to-end by Claude** following [[nixos-service-provisioning]]
  (clone 9001 → SeaBIOS install via nixos-anywhere → OVMF). The steps below are
  the canonical procedure; the Ledger page has the full gotcha list.

**DNS note (important):** VLAN 20's internal resolver is dns1 (192.168.20.53,
Blocky); it was *stopped* during this deploy, and VLAN 20 can't reach the VLAN 7
Technitium hosts, and the fw gateway (.254) doesn't forward external DNS on this
segment. So observ uses external DNS (1.1.1.1/1.0.0.1) — it only needs external
resolution (scrapes by IP) and this avoids depending on dns1 being up. This is
NOT a claim that VLAN 20 lacks DNS: once dns1 is running, .53 is the proper
internal resolver for hosts that need .home.lab names.

**Remaining:** roll the agent to the rest of the fleet (rebuild each host so it
serves node-exporter + ships logs), then the follow-ups below.

**Why this stack:** short-retention troubleshooting + health-at-a-glance + alerting,
on a clean vendor base. VictoriaMetrics/VictoriaLogs are Apache-2.0 and bootstrapped;
Grafana is the swappable dashboard layer only. OpenObserve was rejected on vendor
trust ($10M Series A + Apache→AGPL relicense). See ledger `vendor-trust.md`.

---

## What the NixOS config already provides

- `hosts/observ/` — the VM (192.168.20.56/24, VLAN 20, suggest 2 vCPU / 2 GB / 16 GB).
- `modules/_system/observability.nix` — VictoriaMetrics + VictoriaLogs + Grafana,
  fleet scrape config, optional pve-exporter. Enabled via `mySystem.observability.enable`.
- `modules/_features/observability-agent.nix` — node-exporter + Alloy. Enabled
  fleet-wide in `server-common.nix`; activates on each host's next rebuild.

Ports: Grafana 3000, VictoriaMetrics 8428 (local + scrape), VictoriaLogs 9428
(ingest), node-exporter 9100 (per host), pve-exporter 9221 (local, optional).

---

## Provisioning procedure (Claude executes this)

Claude can and did run all of this: pve over `ssh root@192.168.7.40` (ansible2
key via the 1Password SSH agent) and credentials via the `op` CLI against the
devops vault. The one genuinely human-gated prerequisite is that **1Password is
unlocked** in the session (the op CLI auth prompt + the SSH agent both depend on
it). Recorded actuals for observ are in the STATUS block above.

### 1. Create the VM on pve
- VMID of your choosing, 2 vCPU, 2048 MB, 16 GB virtio disk, UEFI (OVMF), VLAN 20 tag.
- Note the VMID and record it in `hosts/observ/configuration.nix` header.

### 2. Generate the host SSH key (so secrets can target it)
```
ssh-keygen -t ed25519 -N "" -f /tmp/observ_host_ed25519_key -C "robie@flipper"
```
- Commit the public half to `hosts/observ/ssh_host_ed25519_key.pub`.
- Store the private half in 1Password: devops / "observ host SSH key".

### 3. Add observ as an age recipient and re-encrypt the Tailscale key
- Add observ's host pubkey to `secrets/secrets.nix` recipients.
- Re-encrypt `secrets/tailscale-auth-key.age` to include observ (so
  tailscale-autoconnect works on first boot), matching how dns1/dns2 are wired.

### 4. Deploy with nixos-anywhere
- Same flow as dns1 — plant the host key via `--extra-files`, target the VM's
  DHCP/bootstrap IP, let disko partition, switch to the static IP after.

### 5. First-boot verification
- Grafana: `http://192.168.20.56:3000` (admin/admin — change on first login).
- Metrics UI: `http://192.168.20.56:8428/vmui` — query `up` to see scrape health.
- Logs: confirm Alloy is pushing — `http://192.168.20.56:9428/select/vmui`.

### 6. Roll the agent out to 2–3 hosts (see data first)
- The agent is already enabled in `server-common.nix`. Rebuild a couple of
  existing servers (e.g. dns1, ntfy) so they start serving node-exporter and
  pushing logs. They appear in VictoriaMetrics' `node` job automatically.

---

## Follow-ups (next sittings, not blockers)

- **VictoriaLogs Grafana datasource** — install the `victorialogs-datasource`
  plugin and add it to `services.grafana` provisioning so logs are queryable in
  Grafana Explore (job #3, forensics). Metrics work without it.
- **Proxmox metrics** — create a PVE API token, store it as
  `secrets/pve-exporter-token.age` (env: `PVE_USER`, `PVE_TOKEN_NAME`,
  `PVE_TOKEN_VALUE`, `PVE_VERIFY_SSL=false`), then set
  `mySystem.observability.pveExporter.enable = true`. Confirm observ (VLAN 20)
  can reach the PVE API (8006) on VLAN 7 through OPNsense.
- **Dashboards** — import community dashboards for node-exporter and PVE.
- **Alerting → ntfy** — wire Grafana alert rules to the existing ntfy server
  (reuse the auth pattern from `restic-staleness-alert.nix`). Per chaos-monkey,
  power/UPS alerting is nice-to-have, not load-bearing — resilience (auto-restart,
  BIOS restore-on-AC) is the real answer to power events.
- **Grafana admin password** — wire an agenix `grafana-admin-pass` secret to
  replace the first-login default.
- **Durable Grafana secret_key (only if you hand-build UI dashboards you want
  to keep)** — by default the `secret_key` is random-generated on first boot and
  is orphaned on every redeploy, which is correct for a declarative, disposable
  Grafana. If you start persisting Grafana's DB across rebuilds, the key must be
  stable AND backed up, or the DB becomes undecryptable. To make it durable:
  1. Generate once and store in 1Password (devops / "grafana secret_key"):
     `openssl rand -hex 32 | op item create --category=password --vault devops --title "grafana secret_key" password=-`
  2. Pull it into an agenix secret `secrets/grafana-secret-key.age` (recipient =
     observ host key), same flow as the other lab secrets.
  3. Set `mySystem.observability.secretKeyFile = config.age.secrets.grafana-secret-key.path;`
     — the first-boot generator switches off automatically.
  Until then, there is no key to save: it doesn't exist until the VM boots, and
  in the disposable design it isn't worth banking.

---

## Open dependencies / known unknowns

- **Technitium DNS metrics** — Technitium's Prometheus support is unverified;
  likely needs a sidecar exporter. DNS host/process metrics come free via the
  node-exporter agent regardless.
- **Pulse** — already deleted (VM 100 destroyed); VictoriaMetrics owns Proxmox
  metrics outright. The only leftover is a Terraform `state rm` (tracked separately).
