export const MESHTUNES_PREFIX = '🎶'
export const DEFAULT_TICK_MS = 200
export const MAX_TEXT_LEN = 160
/** Full channel post budget (matches official MeshCore client public-channel cap). */
export const MAX_POST_LEN = 143
export const DEFAULT_SENDER_NAME = 'Alice'
export const LOWEST_NOTE = 'H'.charCodeAt(0)
export const HIGHEST_NOTE = 'z'.charCodeAt(0)

export type Part = string
export type Song = Part[]

export type ComposerGridCell = {
  occupied: boolean
  isActive: boolean
  /** True when this cell continues a held note from the previous column. */
  heldFromPrev: boolean
}

export type ComposerGridState = ComposerGridCell[][]

export const rowToNote = (row: number) => String.fromCharCode(HIGHEST_NOTE - row)
export const noteToRow = (note: string) => HIGHEST_NOTE - note.charCodeAt(0)

const encodeRestRun = (count: number): string => {
  let remaining = count
  let out = ''
  while (remaining > 0) {
    const chunk = Math.min(remaining, 9)
    out += chunk === 1 ? '0' : String(chunk)
    remaining -= chunk
  }
  return out
}

// Encodes `extra` additional onsets of `note`. A digit after '-' is always
// the repeat count, so a lone leftover repeat is emitted as the note char
// itself (same byte cost, and never leaves a bare '-' before a rest digit).
const encodeRepeatRun = (note: string, extra: number): string => {
  let remaining = extra
  let out = ''
  while (remaining > 0) {
    if (remaining === 1) {
      out += note
      remaining = 0
    } else {
      const chunk = Math.min(remaining, 9)
      out += `-${chunk}`
      remaining -= chunk
    }
  }
  return out
}

const encodeHoldRun = (extra: number): string => {
  let remaining = extra
  let out = ''
  while (remaining > 0) {
    const chunk = Math.min(remaining, 9)
    out += chunk === 1 ? '~' : `~${chunk}`
    remaining -= chunk
  }
  return out
}

const hasNotesInGrid = (grid: ComposerGridState, rows: number, cols: number): boolean => {
  for (let row = 0; row < rows; row++) {
    for (let col = 0; col < cols; col++) {
      if (grid[row]?.[col]?.occupied) return true
    }
  }
  return false
}

export const compressFromGrid = (grid: ComposerGridState, rows: number, cols: number): Song => {
  const gridCopy: ComposerGridState = grid.map((row) => row.map((cell) => ({ ...cell })))
  const song: Song = []

  while (hasNotesInGrid(gridCopy, rows, cols)) {
    let highestCol = -1
    for (let row = 0; row < rows; row++) {
      for (let col = cols - 1; col >= 0; col--) {
        if (gridCopy[row]?.[col]?.occupied) {
          highestCol = Math.max(highestCol, col)
          break
        }
      }
    }
    if (highestCol === -1) break

    const partNotes = Array(highestCol + 1).fill('0')
    const partHolds = Array(highestCol + 1).fill(false)

    for (let row = 0; row < rows; row++) {
      for (let col = 0; col <= highestCol; col++) {
        const cell = gridCopy[row]?.[col]
        if (!cell?.occupied || cell.heldFromPrev || partNotes[col] !== '0') continue

        const note = rowToNote(row)
        partNotes[col] = note
        cell.occupied = false

        let nextCol = col + 1
        while (nextCol <= highestCol) {
          const next = gridCopy[row]?.[nextCol]
          if (!next?.occupied || !next.heldFromPrev || partNotes[nextCol] !== '0') break
          partNotes[nextCol] = note
          partHolds[nextCol] = true
          next.occupied = false
          nextCol++
        }
      }
    }

    song.push(compressPartWithHolds(partNotes, partHolds))
  }

  return song.filter((part) => part.length > 0)
}

const compressPartWithHolds = (notes: string[], holds: boolean[]): string => {
  let lastIndex = -1
  for (let idx = notes.length - 1; idx >= 0; idx--) {
    if (notes[idx] !== '0') {
      lastIndex = idx
      break
    }
  }
  if (lastIndex < 0) return ''

  let out = ''
  let i = 0

  while (i <= lastIndex) {
    const note = notes[i]
    if (note === '0') {
      let rest = 0
      while (i <= lastIndex && notes[i] === '0') {
        rest++
        i++
      }
      out += encodeRestRun(rest)
      continue
    }

    if (holds[i]) {
      i++
      continue
    }

    out += note
    i++

    let holdExtra = 0
    let staccatoExtra = 0
    while (i <= lastIndex && notes[i] === note) {
      if (holds[i]) {
        holdExtra++
      } else {
        staccatoExtra++
      }
      i++
    }

    if (holdExtra > 0) out += encodeHoldRun(holdExtra)
    if (staccatoExtra > 0) out += encodeRepeatRun(note, staccatoExtra)
  }

  return out
}

export const compressPartRunLength = (part: string): string => {
  const holds = Array(part.length).fill(false)
  return compressPartWithHolds(part.split(''), holds)
}

export const encodeWireString = (song: Song, tickMs = DEFAULT_TICK_MS): string => {
  const body = song.join('|')
  const tickPrefix = tickMs !== DEFAULT_TICK_MS ? `${tickMs}:` : ''
  return `${MESHTUNES_PREFIX}${tickPrefix}${body}`
}

/** Copy/paste tune payload (no diamond, no sender prefix). */
export const encodeTuneString = (song: Song, tickMs = DEFAULT_TICK_MS): string => {
  const body = song.join('|')
  const tickPrefix = tickMs !== DEFAULT_TICK_MS ? `${tickMs}:` : ''
  return `${MESHTUNES_PREFIX}${tickPrefix}${body}`
}

export const channelMessagePrefix = (senderName: string) => `${senderName}: `

export const encodeChannelMessage = (wire: string, senderName = DEFAULT_SENDER_NAME) =>
  `${channelMessagePrefix(senderName)}${wire}`

export const parseWireString = (
  input: string
): { song: Song; tickMs: number } | null => {
  const trimmed = input.trim()
  const prefixIndex = trimmed.indexOf(MESHTUNES_PREFIX)
  if (prefixIndex < 0) return null

  let body = trimmed.slice(prefixIndex + MESHTUNES_PREFIX.length)
  let tickMs = DEFAULT_TICK_MS

  const colonIndex = body.indexOf(':')
  if (colonIndex > 0 && /^[0-9]+$/.test(body.slice(0, colonIndex))) {
    tickMs = Number(body.slice(0, colonIndex))
    body = body.slice(colonIndex + 1)
  }

  const parts = body.split('|').filter((part) => part.length > 0)
  if (parts.length === 0) return null

  return { song: parts, tickMs }
}

export const utf8ByteLength = (value: string): number => new TextEncoder().encode(value).length

export const maxWireBytes = (senderName = DEFAULT_SENDER_NAME) =>
  MAX_POST_LEN - utf8ByteLength(channelMessagePrefix(senderName))

const isNoteChar = (c: string) => {
  const code = c.charCodeAt(0)
  return code >= LOWEST_NOTE && code <= HIGHEST_NOTE
}

export const partColumnCount = (part: string): number => {
  let col = 0
  let pos = 0

  while (pos < part.length) {
    const c = part[pos]

    if (c === '0') {
      col++
      pos++
      continue
    }
    if (c >= '1' && c <= '9') {
      col += Number(c)
      pos++
      continue
    }
    if (c === '-' || c === '~') {
      pos++
      let hold = 1
      if (part[pos] >= '1' && part[pos] <= '9') {
        hold = Number(part[pos])
        pos++
      }
      col += hold
      continue
    }
    if (isNoteChar(c)) {
      col++
      pos++
      continue
    }
    pos++
  }

  return col
}

const applyPartToGrid = (grid: ComposerGridState, part: string) => {
  let col = 0
  let pos = 0
  let lastRow = -1

  while (pos < part.length) {
    const c = part[pos]

    if (c === '0') {
      col++
      pos++
      lastRow = -1
      continue
    }
    if (c >= '1' && c <= '9') {
      col += Number(c)
      pos++
      lastRow = -1
      continue
    }
    if (c === '-') {
      pos++
      let repeat = 1
      if (part[pos] >= '1' && part[pos] <= '9') {
        repeat = Number(part[pos])
        pos++
      }
      if (lastRow >= 0) {
        for (let i = 0; i < repeat; i++) {
          while (grid[lastRow].length <= col) {
            for (const row of grid) row.push({ occupied: false, isActive: false, heldFromPrev: false })
          }
          grid[lastRow][col].occupied = true
          grid[lastRow][col].heldFromPrev = false
          col++
        }
      } else {
        col += repeat
      }
      continue
    }
    if (c === '~') {
      pos++
      let hold = 1
      if (part[pos] >= '1' && part[pos] <= '9') {
        hold = Number(part[pos])
        pos++
      }
      if (lastRow >= 0) {
        for (let i = 0; i < hold; i++) {
          while (grid[lastRow].length <= col) {
            for (const row of grid) row.push({ occupied: false, isActive: false, heldFromPrev: false })
          }
          grid[lastRow][col].occupied = true
          grid[lastRow][col].heldFromPrev = true
          col++
        }
      } else {
        col += hold
      }
      continue
    }
    if (isNoteChar(c)) {
      lastRow = noteToRow(c)
      while (grid[lastRow].length <= col) {
        for (const row of grid) row.push({ occupied: false, isActive: false, heldFromPrev: false })
      }
      grid[lastRow][col].occupied = true
      grid[lastRow][col].heldFromPrev = false
      col++
      pos++
      continue
    }
    pos++
  }
}

export const uncompressSong = (song: Song, rows: number): ComposerGridState => {
  const gridCols = Math.max(...song.map(partColumnCount), 1)

  const grid: ComposerGridState = Array(rows)
    .fill(null)
    .map(() =>
      Array(gridCols)
        .fill(null)
        .map(() => ({ occupied: false, isActive: false, heldFromPrev: false }))
    )

  for (const part of song) {
    applyPartToGrid(grid, part)
  }

  return grid
}
