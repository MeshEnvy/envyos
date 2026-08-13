# Incident: remote admin advert lockup (RAK4631 slim)

**Date:** 2026-08-13  
**Severity:** P0 field blocker  
**Status:** Fixed on bench (`processPendingRemoteCli` defer); upstream PR prepared  
**Affected builds:** EnvyOS v0.1.x on `RAK_4631_repeater_slim` (OTA enabled)  
**Ops initiative:** `ops/initiatives/envyos-field-stability.md`

## Symptom

Remote admin change (tag / MeshCore Open web UI) then **Send Advert** hard-freezes the repeater. USB serial stops responding. USB CLI `set name` + `advert` does **not** repro.

Field mitigation (2026-07-31): adverts disabled on deployed repeaters.

## Repro (confirmed 2026-08-13)

1. RAK4631 slim repeater on bench, EnvyOS with OTA self-serve active.
2. WisMesh Tag + MeshCore Open: login as admin, **Save name**, then **Send Advert** (not USB).
3. Node freezes after both commands log success.

## Root cause

**Stack exhaustion on the remote CLI receive path**, not flash-write collision or TX queue logic.

Remote admin CLI runs inline inside the packet RX handler:

```text
loop() → mesh.loop() → checkRecv() → processRecvPacket() → onRecvPacket()
  → decrypt (data[184] on stack) → onPeerDataRecv() → handleCommand()
  → savePrefs / advert → createAdvert() → ed25519_sign()
```

USB CLI runs at the **top** of `loop()` with a shallow stack. Same `handleCommand()` code, different call depth.

Software `ed25519_sign()` needs ~3–4 KB stack peak. Adafruit nRF52 FreeRTOS **loop task** is 4 KB (`256*4`). The RX path already consumed most of it before sign.

### Measured stack (fault-repro build, 2026-08-13)

| Step | Loop task `hwm_free` |
|------|----------------------|
| Remote `get name` | 1276 B |
| Remote `set name` + `savePrefs` | **448 B** |
| Remote `advert`, before `ed25519_sign` | **448 B** |
| After `ed25519_sign` | **32 B** |

32 B remaining is effectively overflow. Corruption can surface after logging completes (reply TX, OTA tick, next RX).

Stock meshcore-firmware has the same inline `handleCommand()` in `onPeerDataRecv()` (`examples/simple_repeater/MyMesh.cpp`). EnvyOS OTA merkle self-serve and debug logging reduce baseline headroom and make the bug easier to hit, but the architecture bug is upstream.

## Fix

**Defer remote CLI execution to the main loop task**, before `mesh::Mesh::loop()`:

- `onPeerDataRecv`: enqueue command + metadata; return immediately.
- `MyMesh::loop()`: `processPendingRemoteCli()` calls `handleCommand()` at loop-task stack depth (same as USB).
- Retry: resend cached reply if companion retransmits same timestamp.

EnvyOS implementation: `envycore/examples/simple_repeater/MyMesh.{h,cpp}`.

Bench verified: remote save name + advert succeeds; serial stays alive; advert TX visible.

## Upstream

| Target | Branch | Base | Notes |
|--------|--------|------|-------|
| meshcore-dev/MeshCore | `feature/defer-remote-cli` | `dev` | [#3196](https://github.com/meshcore-dev/MeshCore/pull/3196) (draft) |
| vk496/MeshCore | — | — | Pick up via meshcore merge / rebase onto `feature/ota-lora` |

PR prep: [upstream-pr.md](./2026-08-13-remote-admin-advert-lockup-upstream-pr.md)

## Follow-ups (not blocking field)

- Port defer to `simple_room_server` / `simple_sensor` (same inline CLI pattern).
- Consider CC310 hardware sign for `createAdvert()` on nRF52840 (verify path already uses CC310 on EnvyOS).
- nRF watchdog (safety net if another deep-stack path appears).

## References

- EnvyOS MEMORY.md § Active threads (advert lockup)
- Ops cross-link: `ops/docs/2026-08-13-envyos-remote-admin-advert-lockup.md`
- Incident capture skill: `ops/.cursor/skills/incident/SKILL.md`
