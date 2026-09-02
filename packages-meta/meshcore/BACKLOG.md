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
| EC-005 | OTA self-serve policy (merkle bench + disable) | `feature/ota-self-serve-policy` | P2 | S | EC-001 | Superseded — keep synthetic, do not disable | icebox |
| EC-006 | `ota ls` installable-only + apply-identity listing | `feature/ota-catalog-filter` | P2 | M | EC-001 | `ota ls` lists only installable fulls/deltas; pages are content-only; no `1n`/`99999s`; line uses apply-identity tokens | backlog |
| EC-007 | Firmware identity codegen | `feature/firmware-identity-codegen` | P2 | S | EC-001 | Release rebuild only touches generated identity | backlog |
| EC-008 | Bench `-debug` target twins | `feature/debug-targets` | P2 | S | EC-001 | `-debug` twin builds and boots with log tail | backlog |
| EC-009 | Release tooling + changelog docs | `chore/release-tooling` | P2 | S | EC-001 | `./envyos` + CHANGELOG + publish skeleton | in_progress |
| EC-011 | Repeater `stealth_mode` — minimize discovery-plane leaks | `feature/stealth-mode` | P2 | M | EC-001 | Stealth slim: no self-advert/anon/discover/OTA beacon; admin-only status ping; still relays | backlog |
| EC-012 | OTA release provenance — signed distro motas + fleet allowlist; field seeder reject unsigned | `feature/ota-provenance` | P1 | M | EC-001 | Release mota verifies + applies with allowlisted signer; seeder does not advertise/serve unsigned; rejects unknown signer | backlog |
| EC-013 | Battery + temp telemetry history ring + CLI dump | `feature/telemetry-history` | P2 | M | EC-001 | `battery history` compact line; set/get interval; survives reboot (FS) | backlog |
| EC-014 | Directional telemetry backhaul — zero-hop custody toward known sink | `feature/telemetry-backhaul` | Icebox | L | EC-013 | Know sink dest (not a set path); next-hop to any node that has heard the sink; ACK then ship self + predecessors | backlog |
| EC-015 | Login reply echoes sender_timestamp (keep node clock) | `feature/login-reply-tag` | Icebox | S | EC-001 | Trailing 4-byte request tag on LOGIN_OK/fail; companion `request_timestamp`; CLI `NN|` and binary REQ already tagged | backlog |
| EC-016 | SenseCAP P1-Pro NOR superseeder (2 MB QSPI cache) | `feature/sensecap-qspi-seeder` | Icebox | M | EC-001 | NOR/mota layout first; then slim + superseeder in `targets.txt`; NOR mount; RF capture; DUT pull; skip-if-full. EnvyBoot `sensecap_solar_p1` 0.9.2-ev1 already built. | icebox |
| EC-017 | Admin CLI force clock backwards | `feature/clock-force` | P2 | S | EC-001 | `time force <epoch>` sets RTC when node is ahead; stock `time`/`clock sync` still refuse | backlog |
| EC-018 | Repeater neighbor keepalive (no public advert) | `feature/neighbor-keepalive` | P2 | M | EC-001 | Periodic probe + direct pong; table TTL; stealth-safe (no anon discover/advert) | backlog |
| EC-019 | Slim full-mota field path — seeder admit signed fulls + OTAFIX `CODEC_FULL` apply | `feature/ota-rejoin` | P1 | M | EC-001 | Slim RAK/T096 stage a same-size full (measured). Seeders capture+serve signed fulls. nRF52 apply accepts `CODEC_FULL`. Orphan / OS-switch without a host-packed delta. WisMesh/companion stay delta-only. | backlog |
| EC-020 | Drop on-device `OtaTargets.h`; host maps `target_id` → env | `feature/ota-target-client` | P2 | S | EC-001 | `ota status`/`ls` print hex only; `seed allow add` hex-only; no `OtaTargets.h` in image. Envybot names `5c6ab408`. | backlog |
| EC-021 | OTA serve self + slot; never fetch a second copy of running image | `feature/ota-serve-self-and-slot` | P2 | S | EC-001 | `wantRow` skips self mid / same EndF image; slot served after reboot; `ota get` self → ERR | backlog |

EC-001 is the first integrate under [`integration-policy.md`](../../envyos/docs/integration-policy.md) v2: merge companion into `envyos/main`, no vk496 OTA replay.

### EC-006 — `ota ls` installable-only + apply-identity listing (design)

**Trigger (operator 09-02, companion USB):**

```
> ota ls
Updates nearby (3 src) — `ota get <#>` to download:
 1) v0.1.0 full [RAK_WisMesh_Tag_companion_radio_ble] 1n 99999s
 +4 more
> ota ls 2
Updates nearby (3 src) — `ota get <#>` to download:
 2) v0.1.0 full [RAK_WisMesh_Tag_companion_radio_ble] 1n 99999s
 +3 more
```

**Problems**

1. `ota ls N` repeats the header and `+N more` footer. Subsequent pages should be **rows only**.
2. `1n` (seeder count) and `99999s` (age cap) are noise.
3. PIO env in `[brackets]` wastes the 160 B reply and does not match host artifacts.
4. Catalog shows motas that cannot apply on this node.

**Doctrine (operator 09-02)**

- List only what **can install**:
  - **full** whose `hw_id` and `target_id` both match this device
  - **delta** whose `base_hash` matches running `EndF.body_hash`
- Line content aligns with envyos / `motatool name` apply-identity tokens (same fields as the `.mota` basename). Host names are `fw-<slug>-<ver>-full-hwid.<hw>-to.<body16>-mid.<mid8>.mota` and `…-delta-hwid.<hw>-from.<old>-to.<new>-mid.<mid8>.mota`. On-device, drop `fw-<slug>-` (EC-020: no env table). Keep `ver`, `full|delta`, `hwid`, `from`/`to`, `mid`.
- Drop `n_seeders` and age from the line.
- First page may keep a one-line header. `ota ls N` (N>1) is content only: no “Updates nearby…”, no repeated `+N more`.

**Today**

- `OtaCli.cpp` prints header + `ver codec [env|yours] Nn Ns` every page.
- `HaveRow` is 16 B: `mid target_id fw_version codec flags have_count`. No `hw_id`, no `base_hash`, no dest body. Fulls can be filtered by `target_id` now (`target_id` is hw+role, so it implies `hw_id` for well-formed motas). Deltas cannot be filtered by base until the catalog carries `base_hash`.
- Original cherry-pick also mentioned cache layout. Listing + installable filter is the 09-02 spec.

**Work**

1. Filter `ota ls` to the installable set above. Hide other targets / other-base deltas.
2. Reprint with apply-identity tokens. No env string, no `1n`/`99999s`.
3. Pagination: later pages are rows only.
4. Grow `HaveRow` if `base_hash` (and dest body / short `hw_id`) are required to decide or to print `from`/`to`/`hwid` without fetching the manifest.

**Bench gate**

1. Mix on air: own-target full, other-target full, delta for this `body_hash`, delta for another base.
2. `ota ls` shows only the own-target full and the matching delta. Other-target full and other-base delta absent.
3. `ota ls 2` is rows only (no header, no repeated footer).
4. A line is parseable as apply-identity tokens (ver, full|delta, hwid, from/to if known, mid). No `n`/`s` suffix pair.

**Adjacent:** EC-020 (hex / no `OtaTargets.h`). EC-021 (do not fetch running self). Whether the running self-serve full appears in `ls` is open.

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
| Neighbor table refresh | zero-hop advert + `discover.neighbors` | **EC-018 keepalive** (stock discover stays off) |

**Status ping detail:** `simple_repeater/MyMesh.cpp` `handleRequest()` serves `REQ_TYPE_GET_STATUS` to guest ACL clients today (`// guests can also access this now`). Stealth closes that hole so strangers cannot confirm node presence or read uptime/battery/RSSI without an admin key.

**Fleet tooling:** `./envybot monitor` always admin-logins before status. On stealth nodes, unauthenticated `req_status_sync` will time out — do not add a ping-without-login path.

**Bench gate add-on:** guest status ping → silence; admin status ping → stats reply; relay still forwards third-party traffic.

### EC-012 — OTA release provenance (design)

Enterprise: `ops/initiatives/signed-mota-deltas.md`. Merkle/hash is integrity. Signature is authorization.

**Operator 08-30:** field seeders and apply reject anything not signed by the MeshEnvy fleet key. Auto-install already requires signed+allowlisted. Manual `ota install`, seeder advertise/USB-relay/SD-serve, and host `motatool serve` (field folder) must reject unsigned and unknown signer. Superseeder may write-to-SD for forensics; must not serve until verify-with-allowlist passes. Self-serve stays unsigned (EC-021: keep advertising the synthetic; never fetch a second copy; seeders still must not treat it as an installable release).

**Work:** sign in `build.sh` (`motatool build --sign`); `ota key` allowlist; apply reject (manual + auto); seeder index skip; bench gate. Do not disable field self-serve (EC-005 superseded).

### EC-018 — neighbor keepalive (design)

**Goal:** Repeaters refresh the neighbor table after public adverts are off, without restoring `NODE_DISCOVER_RESP` or self-advert.

**Today:** table is RAM, no TTL; updates from zero-hop repeater adverts or `discover.neighbors`. Fleet interim (09-01): remote discover + GET; UI 7-day filter. Enterprise: `ops/initiatives/meshcore-neighbor-keepalive.md`.

**Candidate:** periodic probe; neighbor answers with a **direct pong** (pubkey + SNR). Age-out stale slots on-device. Silent to anonymous callers when stealth is on (EC-011). Wire format not locked.

**Fleet after ship:** drop remote `discover.neighbors`; GET only.

### EC-019 — slim full-mota field path (design)

**Doctrine (operator 09-02, locked):** signed full `.mota` is first-class on **RAK4631 slim** and **Heltec T096 slim**. Superseeders capture and serve those fulls. “Deltas only” is retired for slim. Deltas stay the cheap hop when `base_hash` matches. WisMesh Tag repeater / companion still cannot stage a same-size full.

**Why it opened:** `mota_nrf52_stage_plan` + real artifacts. Window `[0x26000, 0xED000)`. Same-size slim fulls fit. Max stageable mota on 1.17.1-ev1: **454656** B (RAK) / **450560** B (T096). v0.1.3 RAK: **421888** B. July 426/372 figures are stale. 1.16→1.17 CC310 shrink is why slack grew (~24 KB → ~90 KB on slim).

**Still blocked at apply:** `ota_apply_mota_nrf52` refuses `CODEC_FULL` (`not an in-place delta`). Staging a full does nothing until OTAFIX + app accept it.

**Work**

1. Drop `ota_seeder_is_delta` for slim targets (or admit any signed mota the DUT can stage). Capture **and** serve signed fulls. Unsigned self-serve may land on SD; do not advertise it (EC-012).
2. nRF52 apply + OTAFIX: `CODEC_FULL` writes the reconstructed image into `[APP_BASE, APP_BASE+image_len)` when it fits below the staged container.
3. Publish continues to emit full + `delta_from_*` per slim slug. Superseeder library = latest signed full + delta matrix.
4. Heatshrink compressed-full stays for WisMesh / companion only.

**Fielding a new OTAFIX (09-02 idea, not this item):** complementary write path. The bootloader cannot overwrite itself. The **app** writes the BL slot. Sequence: today’s in-place app delta → firmware that applies a bootloader `.mota` → reboot → new OTAFIX applies `CODEC_FULL`. USB only for stock BL. No EC id yet. Ops: `initiatives/ota-rollout.md`.

**Field options this unlocks**

- Orphan / custom-hash slim: pull latest signed full, no host-packed delta.
- OS-switch: stage a whole other OS if the full ≤ max mota for the running image.
- Epidemic slim roll: seed one signed full; peers stage it.

**Bench gate**

1. Slim DUT on unpublished hex. Superseeder serves a **signed** published full for that target. `ota ls` shows it.
2. DUT `ota get` / `ota install` → running `body_hash` matches published. Next official delta applies.
3. WisMesh Tag still rejects same-size full at stage. Unsigned self-serve is not advertised.

### EC-021 — serve self + slot (design)

Enterprise: `ops/initiatives/ota-serve-self-and-slot.md`.

Keep `ota_serve_self`. Never `startFetch` a mid that is view0, or a full whose image matches running EndF. Always advertise a valid stage-slot container (including after reboot). Boot must not `reset_session` a COMPLETE *other* mota out of the serve set.

Supersedes EC-005 “disable self-serve.”

## Icebox

| ID | Item | Notes |
|----|------|-------|
| EC-005 | Disable unsigned self-serve | **Superseded 09-02 by EC-021.** Keep synthetic. |
| EC-010 | Companion FS wedge | Deferred to v0.3.0 per dev monolith changelog |
| — | App-side bootloader mota (app writes BL slot) | Idea 09-02. Complementary write path: app updates BL, BL updates app. Field new OTAFIX without USB. No EC id. |

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
| 2026-09-02 | EC-006 expanded: `ota ls` installable-only (full = matching hw+target; delta = matching base_hash). Apply-identity listing. Later pages content-only. Drop `1n`/`99999s`. Enterprise `ops/initiatives/envyos-backlog.md`. |
| 2026-09-02 | EC-021: keep synthetic self-serve; never fetch a second copy of running image; serve the stage slot across reboot. EC-005 disable plan iceboxed. Enterprise `ops/initiatives/ota-serve-self-and-slot.md`. |
| 2026-09-02 | EC-020: drop on-device target-name table. Client lookup. Enterprise `ops/initiatives/ota-target-name-client.md`. |
| 2026-09-02 | EC-019: slim full-mota doctrine locked. Seeders admit signed fulls on RAK/T096 slim. OTAFIX `CODEC_FULL` apply still required. Complementary write path noted (app updates BL). Enterprise `ops/initiatives/ota-rollout.md`. |
| 2026-09-01 | EC-018: neighbor keepalive after adverts-off. Fleet discover-on-poll is interim. Enterprise `ops/initiatives/meshcore-neighbor-keepalive.md`. |
| 2026-08-30 | EC-016: EnvyBoot `sensecap_solar_p1` 0.9.2-ev1 built. Slim firmware still icebox until NOR/mota layout. |
| 2026-08-30 | EC-017: admin CLI force clock backwards. Stock `time`/`clock sync` refuse past; remote field repair needs a force. Enterprise `ops/initiatives/meshcore-clock-force.md`. |
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
