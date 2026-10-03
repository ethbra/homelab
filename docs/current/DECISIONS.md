# Decisions

> **Current state.** This describes the live server as it runs today (hand-managed
> and CasaOS). The planned infrastructure-as-code setup is in
> [../design/IAC-DESIGN.md](../design/IAC-DESIGN.md). This doc changes only when a migration
> phase actually lands.

Short records of *why* things are the way they are. Newest first.

## Velocity passthrough off; MOTD and icon set by hand (2026-10-01)
- **Problem:** with passthrough on, the server list silently showed Velocity's
  defaults. Cause: after the normal status reply, the pack's Better
  Compatibility Checker mod appends a second blob
  (`{"name":"All the Mods 10","version":"4.12"}`) with no packet ID. Vanilla
  clients ignore it; Velocity rejects the ping and falls back to its own reply.
  Proven with a fake backend (worked) and a logging relay (showed the extra bytes).
- **Decision:** disable passthrough, copy ATM10's MOTD/icon into Velocity.
- **Rejected:** removing the mod (it's part of how ATM10 handles pack versions;
  not worth risking a live 448-mod server for a cosmetic detail).
- **Cost:** the version tooltip says "Velocity", not "1.21.1". Cosmetic.

## ATM10 `online-mode=false` (2026-10-01)
- Velocity authenticates players with Mojang; a backend that also asks for
  authentication makes Velocity abort (`Backend server is online-mode!`).
- Safe **only** while ATM10 is unreachable except through Velocity and PCF
  enforces the secret and `approvedProxyHosts`. See the invariant in NETWORK-AND-SECURITY.

## Proxy Compatible Forge, not NeoVelocity (2026-10-01)
- Both implement Velocity modern forwarding for NeoForge. Running both at once
  conflicts. PCF has ~9x the downloads, was updated months more recently,
  supports many more versions, and adds CrossStitch (wraps modded command
  arguments, relevant for a 448-mod pack). Kept PCF, removed NeoVelocity.

## Bind Velocity to a specific IP, not 0.0.0.0 (2026-10-01)
- Docker holds `127.0.0.1:25565`; Linux then refuses a wildcard bind on the same
  port. Binding `192.168.1.22:25565` works and is also tighter. Cost: the IP is
  hardcoded (reserve it in the router).

## Publish ATM10 on loopback and let Velocity take the public port (2026-10-01)
- Instead of renumbering ATM10 (server.properties, Crafty records, TCPShield),
  change one line in the crafty compose (`host_ip: 127.0.0.1`). ATM10 keeps
  25565 internally, TCPShield still points at 25565, and no one can bypass the
  proxy by hitting ATM10 directly.

## Real player IPs need a proxy layer, not a Bukkit plugin (2026-10-01)
- TCPShield's RealIP supports Spigot/CraftBukkit, BungeeCord and Velocity only,
  not Forge/NeoForge. ATM10 stays a stock NeoForge server; Velocity + RealIP
  sits in front, and PCF on ATM10 consumes Velocity's forwarding. Hybrid
  Bukkit+NeoForge loaders were rejected as too risky for ATM10.

## Firewall for Velocity via INPUT, not DOCKER-USER (2026-10-01)
- Velocity is a host process, so Docker's `DOCKER-USER` chain never sees its
  traffic. The old script's rules only protected Docker-published ports. The new
  `TCPSHIELD_MC` chain hangs off `INPUT`, scoped to the LAN IP so loopback is
  unaffected, and is applied by a systemd oneshot before Velocity starts.

## Run Plex in the container, migrate from native (2026-09-25..30)
- Goal was unified management in CasaOS and GPU transcoding via the NVIDIA
  runtime. The real library lived in the *native* install; the container was an
  empty, unclaimed instance. Copied the full native config tree (preserves
  server identity/claim), set ownership 911:911, and made the container mount
  the same `/DATA/Media` path the library database already references, so no
  database editing was needed.
- Native Plex is stopped/disabled, not yet removed (rollback).

## `nvidia` as Docker's default runtime (2026-09-25)
- The nvidia runtime was registered, but containers kept `Runtime: runc` and no
  `/dev/nvidia*` nodes. After setting it as the default **and recreating** the
  container, the devices appeared. Not tested: whether recreating alone (without
  changing the default) would have been enough. The runtime wrapper is
  transparent to non-GPU containers.
