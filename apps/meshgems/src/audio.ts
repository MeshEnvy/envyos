import type { Song } from './format.js'
import { DEFAULT_TICK_MS } from './format.js'

export type MusicPlayerOptions = {
  noteLengthMs?: number
  volume?: number
  baseNote?: string
  onNotesPlayed?: (col: number) => void
  onEnded?: () => void
  loop?: boolean
}

export const noteToFrequency = (note: string, baseNote = 'i', baseFreq = 440) =>
  note === '0' ? 0 : baseFreq * Math.pow(2, (-baseNote.charCodeAt(0) + note.charCodeAt(0)) / 12)

const isNoteChar = (c: string) => {
  const code = c.charCodeAt(0)
  return code >= 'H'.charCodeAt(0) && code <= 'z'.charCodeAt(0)
}

type NoteEvent = { note: string; startTick: number; durationTicks: number }

export const partEvents = (part: string): NoteEvent[] => {
  const events: NoteEvent[] = []
  let pos = 0
  let tick = 0
  let current: NoteEvent | null = null

  while (pos < part.length) {
    const c = part[pos]

    if (c === '0') {
      current = null
      tick++
      pos++
      continue
    }

    if (c >= '1' && c <= '9') {
      current = null
      tick += Number(c)
      pos++
      continue
    }

    if (c === '-') {
      pos++
      let repeat = 1
      if (pos < part.length && part[pos] >= '1' && part[pos] <= '9') {
        repeat = Number(part[pos])
        pos++
      }
      if (current) {
        for (let i = 0; i < repeat; i++) {
          events.push({ note: current.note, startTick: tick + i, durationTicks: 1 })
        }
      }
      tick += repeat
      continue
    }

    if (c === '~') {
      pos++
      let hold = 1
      if (pos < part.length && part[pos] >= '1' && part[pos] <= '9') {
        hold = Number(part[pos])
        pos++
      }
      if (current) {
        current.durationTicks += hold
      }
      tick += hold
      continue
    }

    if (isNoteChar(c)) {
      current = { note: c, startTick: tick, durationTicks: 1 }
      events.push(current)
      tick++
      pos++
      continue
    }

    pos++
  }

  return events
}

/** Ticks until the last note finishes — ignores trailing silence in encoded parts. */
export const songTickCount = (song: Song): number => {
  let max = 0
  for (const part of song) {
    for (const event of partEvents(part)) {
      max = Math.max(max, event.startTick + event.durationTicks)
    }
  }
  return Math.max(max, 1)
}

export const playSingleNote = (
  audioContext: AudioContext,
  frequency: number,
  start: number,
  options?: { noteLengthMs?: number; volume?: number }
) => {
  const { noteLengthMs = DEFAULT_TICK_MS, volume = 0.1 } = options || {}
  if (frequency === 0) return

  const noteLengthSeconds = noteLengthMs / 1000
  const end = start + noteLengthSeconds

  const oscillator = audioContext.createOscillator()
  const gainNode = audioContext.createGain()
  const envelope = audioContext.createGain()

  oscillator.connect(envelope)
  envelope.connect(gainNode)
  gainNode.connect(audioContext.destination)

  oscillator.frequency.setValueAtTime(frequency, start)
  oscillator.type = 'sine'

  gainNode.gain.setValueAtTime(volume, start)
  envelope.gain.setValueAtTime(0.5, start)
  envelope.gain.setTargetAtTime(0.001, Math.max(start, end - 0.05), 0.02)

  oscillator.start(start)
  oscillator.stop(end)

  oscillator.onended = () => {
    oscillator.disconnect()
    envelope.disconnect()
    gainNode.disconnect()
  }
}

const LOOPS_AHEAD = 6

export const createSongPlayer = (song: Song) => {
  let audioContext: AudioContext | null = null
  const timeoutIds = new Set<ReturnType<typeof setTimeout>>()
  let cancelled = false
  let scheduledLoops = 0
  let nextLoopIndex = 0

  const stop = () => {
    cancelled = true
    scheduledLoops = 0
    nextLoopIndex = 0
    timeoutIds.forEach((timeoutId) => clearTimeout(timeoutId))
    timeoutIds.clear()
    if (audioContext && audioContext.state !== 'closed') {
      audioContext.close()
    }
    audioContext = null
  }

  const scheduleLoop = (
    loopIndex: number,
    loopStartTime: number,
    options: Required<Pick<MusicPlayerOptions, 'noteLengthMs' | 'volume' | 'baseNote'>> &
      Pick<MusicPlayerOptions, 'onNotesPlayed'>
  ) => {
    if (cancelled || !audioContext) return

    const { noteLengthMs, volume, baseNote, onNotesPlayed } = options
    const tickSeconds = noteLengthMs / 1000
    const loopTicks = songTickCount(song)

    for (const part of song) {
      for (const event of partEvents(part)) {
        const frequency = noteToFrequency(event.note, baseNote)
        playSingleNote(audioContext, frequency, loopStartTime + event.startTick * tickSeconds, {
          noteLengthMs: event.durationTicks * noteLengthMs,
          volume,
        })
      }
    }

    if (onNotesPlayed) {
      const visualLeadMs = Math.max(0, (loopStartTime - audioContext.currentTime) * 1000)
      for (let col = 0; col < loopTicks; col++) {
        const timeoutId = setTimeout(() => {
          if (!cancelled) onNotesPlayed(col)
        }, visualLeadMs + col * noteLengthMs)
        timeoutIds.add(timeoutId)
      }
    }

    scheduledLoops = loopIndex + 1
  }

  const ensureLoopsScheduled = (
    anchorTime: number,
    options: Required<Pick<MusicPlayerOptions, 'noteLengthMs' | 'volume' | 'baseNote'>> &
      Pick<MusicPlayerOptions, 'onNotesPlayed'>
  ) => {
    if (cancelled || !audioContext) return

    const loopTicks = songTickCount(song)
    const loopDurationSec = loopTicks * (options.noteLengthMs / 1000)

    while (scheduledLoops < nextLoopIndex + LOOPS_AHEAD) {
      scheduleLoop(scheduledLoops, anchorTime + scheduledLoops * loopDurationSec, options)
    }

    const nextBoundaryMs =
      Math.max(0, (anchorTime + nextLoopIndex * loopDurationSec - audioContext.currentTime) * 1000) +
      loopDurationSec * 1000 * 0.5

    const timeoutId = setTimeout(() => {
      if (cancelled) return
      nextLoopIndex += LOOPS_AHEAD
      ensureLoopsScheduled(anchorTime, options)
    }, nextBoundaryMs)
    timeoutIds.add(timeoutId)
  }

  const play = (options?: MusicPlayerOptions) => {
    const {
      noteLengthMs = DEFAULT_TICK_MS,
      volume = 0.1,
      baseNote = 'i',
      onNotesPlayed,
      onEnded,
      loop = false,
    } = options || {}

    stop()
    cancelled = false
    scheduledLoops = 0
    nextLoopIndex = 0
    audioContext = new AudioContext()

    const loopTicks = songTickCount(song)
    const leadInSeconds = 0.05
    const anchorTime = audioContext.currentTime + leadInSeconds
    const resolved = { noteLengthMs, volume, baseNote, onNotesPlayed }

    if (loop) {
      ensureLoopsScheduled(anchorTime, resolved)
      return
    }

    scheduleLoop(0, anchorTime, resolved)

    if (onEnded) {
      const timeoutId = setTimeout(onEnded, leadInSeconds * 1000 + loopTicks * noteLengthMs + 100)
      timeoutIds.add(timeoutId)
    }
  }

  return { play, stop }
}

export type MusicPlayer = ReturnType<typeof createSongPlayer>
