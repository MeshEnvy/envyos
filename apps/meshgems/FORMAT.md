# MeshTunes wire format

Polyphonic songs sent as MeshCore text messages. Author with [MeshTunes Composer](./index.html).

## Message envelope

```
🎶[<tickms>:]<part>|<part>|...
```

Channel post (MeshCore public channel form):

```
<sender>: 🎶[<tickms>:]<part>|<part>|...
```

| Field | Description |
|-------|-------------|
| Prefix | Literal UTF-8 `🎶` (4 bytes) — message must **begin** with this (after `sender: ` on channels) |
| `tickms` | Optional column duration in ms (default **200**) |
| `part` | One voice / polyphony layer |

## Part grammar

```
part   := ( note | rest | repeat | hold )*
note   := 'H'..'z'
rest   := '0' | '1'..'9'
repeat := '-' [ '1'..'9' ]
hold   := '~' [ '1'..'9' ]
```

A digit immediately after `-` or `~` always binds to that token as its count. A single extra staccato repeat is written as the note char itself (`ll`, not `l-`). A single extra hold tick is written as `~` alone (`l~`, not `l~1`).

| Token | Meaning | Example |
|-------|---------|---------|
| `-` | Retrigger same note (staccato) | `l-4` = 5 separate onsets |
| `~` | Hold/sustain previous note | `l~4` = one 5-tick tone |

**Firmware note:** current companion firmware ignores unknown chars without advancing time, so tunes containing `~` will mis-time on-device until firmware adds hold support.

## Triggers (companion firmware)

| Source | Behavior |
|--------|----------|
| Direct message starting with `🎶` | Plays immediately; no RTTTL notification beep |
| `#meshtunes` channel with `🎶` in body | Queued into 8-slot playlist loop (~3 s gaps) |
| Other channels | Ignored (no playback) |

## Controls (`ui-orig`, e.g. WisMesh Tag)

| Button | Action |
|--------|--------|
| Short press (while playing) | Skip song |
| Double press | Pause/resume `#meshtunes` loop (advert if queue empty) |
| Triple press | Global buzzer mute |

## Limits

| Limit | Value |
|-------|-------|
| Composer post budget | **143 bytes** UTF-8 (`Alice: 🎶…`) |
| Firmware RF cap | **160 bytes** |

## Example

```
Alice: 🎶ii0j0e|0Y0^0]
```
