# Envycore backlog

Canonical queue for **MeshEnvy firmware work** in this repo. Each item gets its own `feature/<name>` branch, its own bench gate, and merges to `envyos/main` **only when you explicitly pull it from the backlog**. Distro semver is chosen at publish time in `envyos/`.

Enterprise index: `ops/initiatives/envyos-backlog.md` (summary rows only).

## How to use

| Column | Meaning |
|--------|---------|
| **ID** | Stable backlog ID (`EC-###`) |
| **Priority** | P0 field blocker; P1 high leverage; P2 polish; Icebox deferred |
| **Effort** | S / M / L / XL desk or bench days |
| **Depends** | Other EC IDs whose branch must merge to `envyos/main` first |
| **Status** | `backlog` · `in_progress` · `bench` · `merged_main` · `published` · `icebox` |

**`merged_main` means git-merged to `envyos/main` only.** It is not field flash, not a distro publish, and not an upstream PR merge. User-facing overlay notes: fork `CHANGELOG.md` plus the README overlay table (PR links). Drop or mark `upstreamed` when a PR merges.

## Backlog

| ID | Item | Branch | Priority | Effort | Depends | Bench gate | Status |
|----|------|--------|----------|--------|---------|------------|--------|
| EC-001 | MeshCore companion-v1.17.1 upgrade | `feature/companion-v1.17` | P1 | L | EC-000 | slim repeater build; native tests; FRESHEN.lock v2 | merged_main |
| EC-002 | nRF52 hardware WDT + EnvyBoot gate | `feature/nrf52-watchdog` | P1 | M | EC-001 | WDT trip/recover; OTA apply with EnvyBoot WDT feed | backlog |
| EC-003 | EndF version restamp on rebuild | `feature/endf-restamp` | P2 | S | EC-001 | Rebuild same version — EndF trailer matches | backlog |
| EC-004 | doctor CLI + atomic prefs | `feature/doctor` | P1 | M | EC-001 | `doctor check`; atomic prefs save under low FS space | backlog |
| EC-005 | OTA self-serve policy (merkle bench + disable) | `feature/ota-self-serve-policy` | P2 | S | EC-001 | No self-serve hash traffic at boot | backlog |
| EC-006 | OTA catalog filter + cache layout | `feature/ota-catalog-filter` | P2 | M | EC-001 | `ota ls` filtered to own target | backlog |
| EC-007 | Firmware identity codegen | `feature/firmware-identity-codegen` | P2 | S | EC-001 | Release rebuild only touches generated identity | backlog |
| EC-008 | Bench `-debug` target twins | `feature/debug-targets` | P2 | S | EC-001 | `-debug` twin builds and boots with log tail | backlog |
| EC-009 | Release tooling + changelog docs | `chore/release-tooling` | P2 | S | EC-001 | `./envyos` + CHANGELOG + publish skeleton | in_progress |
| EC-011 | Repeater `stealth_mode` — minimize discovery-plane leaks | `feature/stealth-mode` | P2 | M | EC-001 | Stealth slim: no self-advert/anon/discover/OTA beacon; admin-only status ping; still relays | backlog |
| EC-012 | OTA release provenance — signed distro motas + fleet allowlist; field seeder reject unsigned | `feature/ota-provenance` | P1 | M | EC-001 | Release mota verifies + applies with allowlisted signer; seeder does not advertise/serve unsigned; rejects unknown signer | backlog |
| EC-013 | Battery + temp telemetry history ring + CLI dump | `feature/telemetry-history` | P2 | M | EC-001 | `battery history` compact line; set/get interval; survives reboot (FS) | backlog |
| EC-014 | Directional telemetry backhaul — zero-hop custody toward known sink | `feature/telemetry-backhaul` | Icebox | L | EC-013 | Know sink dest (not a set path); next-hop to any node that has heard the sink; ACK then ship self + predecessors | backlog |
| EC-015 | Login reply echoes sender_timestamp (keep node clock) | `feature/login-reply-tag` | Icebox | S | EC-001 | Trailing 4-byte request tag on LOGIN_OK/fail; companion `request_timestamp`; CLI `NN|` and binary REQ already tagged | backlog |
| EC-016 | SenseCAP P1-Pro NOR superseeder (2 MB QSPI cache) | `feature/sensecap-qspi-seeder` | Icebox | M | EC-001 | Slim + superseeder in `targets.txt`; NOR mount; RF capture; DUT pull; skip-if-full | icebox |

EC-001 is the first integrate under [`integration-policy.md`](../../envyos/docs/integration-policy.md) v2: merge companion into `envyos/main`, no vk496 OTA replay.

### EC-013 — telemetry history (design)

**Goal:** Ring-buffer recent battery voltage and (when present) board/sensor temperature. Configurable sample interval. One-line CLI dump suitable for serial, BLE, and remote CLI (fits ~160-byte reply with pagination).

**Prior art:** `examples/simple_sensor/TimeSeriesData.{h,cpp}` — in-RAM float ring, interval-gated `recordData()`. Promote to `src/helpers/TelemetryHistory.*`, switch samples to `uint8_t` encoded values, add FS persistence.

**Sampling**

| Stream | Source | When |
|--------|--------|------|
| Battery | `_board` ADC / `getBootVoltage()` path where available | Every interval if board reports voltage |
| Temp | `SensorManager` or onboard sensor | Every interval when sensor present; omit slot char when absent |

**Prefs (persisted in node prefs / sidecar file)**

| Key | Default | Notes |
|-----|---------|-------|
| `battery.history.interval` | 300 | Seconds between samples; min 60 |
| `battery.history.slots` | 288 | Fixed at compile time for v1 (24 h @ 5 min) |
| `temp.history.interval` | 300 | Same as battery unless split later |

CLI: `get battery.history.interval`, `set battery.history.interval <sec>` (mirror for `temp`).

**Wire encoding — printable byte**

Each sample is one ASCII char: `ch = '!' + value` where `value` is 0–93 (`!` … `~`).

| Stream | `value` meaning | Decode |
|--------|-----------------|--------|
| Battery | Tenths of volt | `V = value / 10.0` (42 → 4.2 V) |
| Temp | Whole °C offset | `T = value - 40` (-40 … +53 °C) |
| Missing / gap | `_` (0x5F) | No sample this slot (sensor absent or pre-fill) |

Examples: 4.2 V → `value=42` → `'K'`; 22 °C → `value=62` → `'o'`.

**Dump format**

Oldest→newest, one line:

```
<start_unix>|<interval_sec>|B:<battery_chars>|T:<temp_chars>
```

- `start_unix` — RTC epoch of oldest slot (0 if buffer not yet filled).
- `interval_sec` — active sample period.
- `B:` — battery run only.
- `T:` — temp run only (may be shorter or all `_` when no sensor).

Combined interleaved (optional alias `telemetry history`):

```
<start_unix>|<interval_sec>|:<interleaved>
```

Each slot contributes two chars when both streams exist: battery then temp (`KoooKK...`). Temp-only-absent slots use `_` for the temp char.

**CLI surface**

| Command | Action |
|---------|--------|
| `battery history` | Full `B:` dump |
| `temp history` | Full `T:` dump |
| `telemetry history` | Interleaved `:` form |
| `battery history clear` | Zero ring + reset `start_unix` |
| `get/set battery.history.interval <sec>` | Interval prefs |

**Pagination:** If payload exceeds reply buffer (~140 chars body), support `battery history <offset>` where offset is slot index (0 = oldest). Reply prefix `> part <offset>/<total>|` then truncated payload.

**Persistence:** Small file on InternalFS/LittleFS (`/tel_hist`) — header (magic, version, start_unix, interval, write_idx) + raw uint8 slot arrays. Load at boot; append on sample; wear-friendly (rewrite whole file every N samples or use circular file — v1 may be RAM-only with FS save on interval if EC-004 atomic prefs lands first).

**Bench gate**

1. `set battery.history.interval 10`; wait ≥3 samples.
2. `battery history` → `start_unix>0`, `interval=10`, three monotonic-ish `B:` chars decodable to plausible voltage.
3. Reboot → history still present (if FS enabled).
4. Board without temp → `T:` all `_` or empty; no crash.

**Out of scope v1:** LPP export, mesh-side pull, motatool parser (follow-on once format stable).

### EC-014 — directional telemetry backhaul (design sketch)

**Working names:** *telemetry suction*, telemetry backhaul, gradient relay.

**Goal:** Move fleet telemetry from edge repeaters to a collector/sink (envybot ingest / warehouse) without periodic mesh-wide status flood or advert-as-telemetry noise.

**Routing decision (operator 08-28):** **next hop, not a set path.** Each node knows the **sink destination** (identity). Any neighbor that has **heard of the sink** may accept the payload. A pinned A→B→C chain is rejected as brittle.

**Rough model (operator 08-28)**

1. **Sample locally** — EC-013 ring (battery, temp, optional traffic/neighbor stats later).
2. **Zero-hop toward sink** — dest = sink. Offer to a neighbor that has heard the sink. Retry until an **ACK** (custody accepted into its buffer, not just airtime). If that neighbor dies, another heard-of-sink neighbor can take it.
3. **Accept rule** — a node that has heard the sink accepts; a node that has not, refuses (does not take custody).
4. **Custody leap** — after ACK, the sender may drop (or mark shipped) those records. The receiving node now owns them.
5. **Aggregate ship** — when that node makes *its* leap, it ships **itself plus everything queued from downstream**. Same zero-hop + ACK to whoever has heard the sink next.
6. **Sink** — mothership / collector with envybot telemetry harvest; warehouse + Peaky fleet book consume (`ops/initiatives/envybot-radio-daemon.md`, `ops/initiatives/peaky-fleet-management.md`).

Bucket-brigade along a live gradient, not a declared path.

**Incomplete (operator 08-28):** this is an *app* (dest = sink, aggregate payload), not a network. Dest, next-hop, hop ACK, and retry belong in a real routing/delivery layer. Do **not** grow a telem-only routing stack in MeshCore. TCP/IP solved the *ideas*; what is too heavy for LoRa is the Ethernet-era *stack* (40 B headers, SYN/ARP/keepalive chatter, RTT timers in ms). Sequencing: Prns/RNS transport (`ops/initiatives/darticulum-reticulum.md`) is the bet; MeshCore EC-014 only if a field blocker forces it (R&D doctrine: no MeshCore-depth features).

**Anti-patterns:** global status advert cadence as fleet telemetry; flooding telemetry on shared channels; requiring admin CLI poll of every edge node; end-to-end multi-hop send without per-leap ACK; Peaky/admin static hop list; reinventing next-hop inside a telemetry opcode.

**Open (see `ops/initiatives/envyos-backlog.md` § Missing information):** transport vs app split; what counts as "heard the sink"; pick among several heard neighbors; radio ACK vs buffer-accept ACK; bundle MTU; drop-on-hop-ACK vs wait-for-sink; cadence; wire format; EC-011 stealth vs sink hearability.

**Out of scope v1:** cross-mesh MQTT bridge; Prns transport (spec transport-agnostic until LoRa gate).

### Source commits (from `envyos/dev-pre-split` monolith)

| ID | Cherry-pick SHAs |
|----|------------------|
| EC-001 | merge `origin/envyos/freshen/companion-v1.17.0` + `80766f40` + `9e71d50f` |
| EC-002 | `589c8db6`, `3674c1b7`, `aaa6e583` |
| EC-003 | `163dc2c3` |
| EC-004 | `f79f12d1`, `ad4b1265`, `62a48440` (+ native guard from split session if needed) |
| EC-005 | `e15e986d`, `5b06eb74` |
| EC-006 | `56dc37ac` |
| EC-007 | `165e7277` |
| EC-008 | `830ffa4d` |
| EC-009 | `ac4a48db`, `c79c9029` (skip duplicate `918c7ad8` if changelog already on branch) |

EC-001 includes freshen overlay: SenseCAP slim OTA env, NOR/SD seeder allow CLI.

### EC-011 — stealth mode (design)

**Goal:** Field repeaters stay on the mesh as relays but stop leaking identity and health on the discovery plane.

**Gated when `stealth_mode` pref is on**

| Surface | Today | Stealth |
|---------|-------|---------|
| Self-advert / node discover | on | off |
| Anon owner / region / clock | on | off |
| OTA beacons | on | off |
| `REQ_TYPE_GET_STATUS` (status ping) | guest + admin | **admin only** — drop (reply_len 0) for non-admin senders |
| Path hash on relay | on | on (unchanged) |

**Status ping detail:** `simple_repeater/MyMesh.cpp` `handleRequest()` serves `REQ_TYPE_GET_STATUS` to guest ACL clients today (`// guests can also access this now`). Stealth closes that hole so strangers cannot confirm node presence or read uptime/battery/RSSI without an admin key.

**Fleet tooling:** `./envybot monitor` always admin-logins before status. On stealth nodes, unauthenticated `req_status_sync` will time out — do not add a ping-without-login path.

**Bench gate add-on:** guest status ping → silence; admin status ping → stats reply; relay still forwards third-party traffic.

### EC-012 — OTA release provenance (design)

Enterprise: `ops/initiatives/signed-mota-deltas.md`. Merkle/hash is integrity. Signature is authorization.

**Operator 08-30:** field seeders and apply reject anything not signed by the MeshEnvy fleet key. Auto-install already requires signed+allowlisted. Manual `ota install`, seeder advertise/USB-relay/SD-serve, and host `motatool serve` (field folder) must reject unsigned and unknown signer. Superseeder may write-to-SD for forensics; must not serve until verify-with-allowlist passes. Self-serve is unsigned by construction (EC-005): field roles must stop serving it or seeder-reject is a no-op.

**Work:** sign in `build.sh` (`motatool build --sign`); `ota key` allowlist; apply reject (manual + auto); seeder index skip; disable unsigned self-serve on field roles; bench gate.

## Icebox

| ID | Item | Notes |
|----|------|-------|
| EC-010 | Companion FS wedge | Deferred to v0.3.0 per dev monolith changelog |

## Done

| ID | Item | Date | SHA / version |
|----|------|------|---------------|
| EC-000 | defer-remote-cli lockup fix | 2026-08-13 | `a2a13e18` on `envyos/main` (v0.1.3 hotfix) |

### Upstream PR branches (pure track — optional, not merged to main)

| ID | Branch | PR base | Notes |
|----|--------|---------|-------|
| EC-000 | `feature/defer-remote-cli-upstream` | meshcore-dev `dev` | On origin; open cross-fork PR when ready |

## Log

| Date | Note |
|------|------|
| 2026-08-30 | EC-012 → P1. Field seeder advertise/serve must reject unsigned (operator). Enterprise `ops/initiatives/signed-mota-deltas.md`. |
| 2026-08-25 | Opened backlog; split `envyos/dev-pre-split` monolith into feature branches. **`envyos/main` stays on v1.16 + 0.1.3 hotfix** until items are pulled deliberately. |
| 2026-08-25 | Reverted mistaken merge of EC-001–EC-009 to `envyos/main`. Feature branches only. |
| 2026-08-25 | EC-011: repeater `stealth_mode` — gate self-adverts, anon owner/region/clock, node discover, OTA beacons; path hash on relay remains. |
| 2026-08-25 | EC-012: OTA release provenance — sign published motas, fleet `ota key` allowlist, apply trust separate from discovery (EC-011). |
| 2026-08-28 | EC-013: battery + temp telemetry history ring — compact ASCII CLI dump (`battery history`), set/get interval; builds on `TimeSeriesData` example. |
| 2026-08-28 | EC-011: admin-only `REQ_TYPE_GET_STATUS` when stealth on — closes guest status ping fingerprint; fleet `--ping` must login. |
| 2026-08-28 | EC-014: directional telemetry backhaul (*telemetry suction*) — zero-hop neighbor relay chain toward mothership; depends EC-013; Icebox. |
| 2026-08-28 | EC-014 refined: known path to sink; retry zero-hop until ACK; hop ships self + queued predecessors (custody transfer). |
| 2026-08-28 | EC-014 routing: **next hop, not set path.** Know sink dest; any node that has heard the sink may accept. |
| 2026-08-28 | EC-014 marked incomplete: app on a real delivery layer, not a MeshCore routing project. "IP too heavy" = stack folklore, not dest/ACK/next-hop. → `darticulum-reticulum`. |
| 2026-08-29 | EC-001: merged `companion-v1.17.1` onto 1.17.0 overlay (`envyos/integrate/companion-v1.17.1`). Native tests + slim build passed. Status `bench`. Not on `envyos/main`. |
| 2026-08-29 | EC-001 landed on `envyos/main` (`2cf4a528` integrate, `3881ceb1` lock). Pulled EnvyBoot + T096. Status `merged_main`. Not published. |
