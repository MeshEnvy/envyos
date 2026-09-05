---
name: envyos
description: >-
  What EnvyOS is (and is not) for site copy, blog posts, and partner-facing
  prose. Read before describing EnvyOS, the distro CLI, packages, or releases.
---

# EnvyOS

## What it is

EnvyOS is MeshEnvy's **mesh operating system distro**. Think Linux, not a single app and not a repeater-only product.

It is a collection of software pinned and released together. The list is growing. It includes user applications, repeaters, utilities, and more.

The distro repo is [`MeshEnvy/envyos`](https://github.com/MeshEnvy/envyos). It owns recipes, versioning, builds, and releases (`MANIFEST.json`, `./envyos` CLI, `packages-meta/`).

## What it includes (examples, not the whole product)

| Package | Role |
| --- | --- |
| `meshcore` | Custom MeshCore firmware (MeshEnvy fork under `packages/meshcore`). Repeaters, companions, and other roles. |
| `meshcore-open` | Flutter MeshCore client (user application, when pinned) |
| `adafruit-nrf52-bootloader` | nRF52 bootloader with OTA fixes |
| `motatool` | Host CLI for builds, OTA, and bench work |
| `mcmt-gateway` | Gateway tooling |

Peaky and envybot are workspace siblings the distro can pin. They are not inside the envyos git repo.

MeshCore/OTA is the current stack, not the whole product definition. Do not treat today's package list as the ceiling.

## What it is not

Do **not** call EnvyOS:

- "MeshEnvy's MeshCore fork"
- "the firmware fork"
- "EnvyOS firmware" when you mean the whole distro
- "a mesh repeater distro"
- "a mesh-utility distro"

The **custom MeshCore build** is one package inside the distro. Repeaters are one class of application the distro ships. The distro is the integration and release layer around all of those applications.

## Copy patterns (blog and site)

**Do:**

- "EnvyOS is MeshEnvy's mesh operating system distro."
- "EnvyOS includes user applications, repeaters, utilities, and more."
- "The EnvyOS meshcore package adds …" (when you mean firmware-only changes)
- "Stock Heltec firmware" vs "an EnvyOS meshcore build" (when comparing what is flashed)

**Don't:**

- "EnvyOS fork firmware" → use "EnvyOS meshcore build" or "custom MeshCore in EnvyOS"
- "Flash EnvyOS" without context → say which artifact (repeater UF2, companion, bootloader, client) or "an EnvyOS release"
- Narrow the product to repeaters, utilities, or firmware alone

## Deeper references

| Need | Read |
| --- | --- |
| Distro layout, MANIFEST, publish | `envyos/MEMORY.md`, `envyos/docs/distro-packaging.md` |
| Git workflow, upstream PRs | `.cursor/skills/envyos-meshcore/SKILL.md` |
| OTA, motatool, bench | sibling skills under `envyos/.cursor/skills/` |
