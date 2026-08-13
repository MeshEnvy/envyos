# Upstream PR: defer remote admin CLI (stack overflow fix)

## meshcore-dev/MeshCore

**Branch:** `feature/defer-remote-cli` on `MeshEnvy/meshcore-firmware`  
**Base:** `dev`  
**PR:** https://github.com/meshcore-dev/MeshCore/pull/3196 (draft)

### Title

`fix(repeater): defer remote admin CLI out of RX handler`

### Summary

- Remote admin CLI commands (`PAYLOAD_TYPE_TXT_MSG` from known admin contacts) no longer call `handleCommand()` inside `onPeerDataRecv()`.
- Commands are queued and executed at the start of `MyMesh::loop()`, before `mesh::Mesh::loop()`, matching USB serial CLI stack depth.
- Companion retries with the same timestamp resend the cached CLI reply instead of re-running the command.

### Problem

On nRF52 repeaters the FreeRTOS loop task stack is 4 KB. The RX path decrypts packets with large stack frames (`data[184]`, etc.) then runs CLI handlers inline. Commands like `set name` (`savePrefs`) and `advert` (`createAdvert` → software `ed25519_sign`, ~3 KB peak) can leave **<64 B** stack free and hard-freeze the node. USB CLI does not hit this path.

Repro: MeshCore Open / companion radio → repeater settings → save name → send advert. USB `advert` alone works.

### Test plan

- [ ] Flash `RAK_4631_repeater`, add tag as admin contact
- [ ] Tag UI: save name, send advert — node stays responsive on USB serial
- [ ] USB CLI `advert` still works
- [ ] Companion retry (same timestamp) receives cached reply
- [ ] `pio run -e RAK_4631_repeater` CI build passes

### Create PR

```bash
cd /Volumes/Code/repos/meshenvy/meshcore-firmware   # or envycore/ submodule
git fetch meshcore dev
git checkout -b feature/defer-remote-cli meshcore/dev
# apply MyMesh.{h,cpp} changes (already in working tree if synced from this doc session)
git add examples/simple_repeater/MyMesh.cpp examples/simple_repeater/MyMesh.h
git commit -m "fix(repeater): defer remote admin CLI out of RX handler"
git push -u origin feature/defer-remote-cli

gh pr create -R meshcore-dev/MeshCore \
  --base dev \
  --head MeshEnvy:feature/defer-remote-cli \
  --title "fix(repeater): defer remote admin CLI out of RX handler" \
  --body "$(cat <<'EOF'
## Summary
- Defer remote admin CLI (`handleCommand`) from the packet RX handler to `MyMesh::loop()` so it runs at the same stack depth as USB serial CLI.
- Cache and resend CLI replies on companion retry (same timestamp).

## Problem
Inline CLI in `onPeerDataRecv` stacks RX decrypt frames with `savePrefs` / `ed25519_sign` (~3 KB) on a 4 KB FreeRTOS loop task. Remote `set name` + `advert` from MeshCore Open can hard-freeze nRF52 repeaters; USB CLI does not repro.

## Test plan
- [ ] RAK4631 repeater + tag admin: save name, send advert — serial stays alive
- [ ] USB `advert` control
- [ ] Companion retry gets cached reply
- [ ] `pio run -e RAK_4631_repeater`

EOF
)"
```

### Sync to EnvyOS distro

After opening the PR, ensure the same commit is on `envyos/main` in `MeshEnvy/meshcore-firmware` (already landed during bench fix). While PR is open, push fixes to **both** `feature/defer-remote-cli` and `envyos/main`.

## vk496/MeshCore

No separate PR required. This fix is not OTA-specific. When meshcore-dev merges, rebase `vk496/feature/ota-lora` or cherry-pick onto the EnvyOS OTA stack.

If vk496 needs it before meshcore merge:

```bash
cd envycore
git fetch vk496 feature/ota-lora
git checkout -b feature/defer-remote-cli-vk496 vk496/feature/ota-lora
git cherry-pick <sha>
git push origin feature/defer-remote-cli-vk496
gh pr create -R vk496/MeshCore --base feature/ota-lora --head MeshEnvy:feature/defer-remote-cli-vk496 ...
```
