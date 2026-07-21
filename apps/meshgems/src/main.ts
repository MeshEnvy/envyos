import {
  createSongPlayer,
  noteToFrequency,
  playSingleNote,
  type MusicPlayer,
} from "./audio.js";
import {
  DEFAULT_SENDER_NAME,
  HIGHEST_NOTE,
  LOWEST_NOTE,
  MAX_POST_LEN,
  compressFromGrid,
  encodeChannelMessage,
  encodeTuneString,
  parseWireString,
  uncompressSong,
  utf8ByteLength,
  type ComposerGridState,
  type Song,
} from "./format.js";
import { PortIndependentStorage } from "./storage.js";

const NOTE_RANGE = HIGHEST_NOTE - LOWEST_NOTE + 1;
const DEFAULT_TICK_MS = 200;
const GRID_COLS = 64;

const DEMO_SONG: Song = [
  "ll0n0j0jYll00uYvusqs[p0pp00qpnlj0n0q00l0^p00s000v0u0s0pq",
  "ii0j0e0e00i00q000Y^0T00dd000000g0j0n00]00`0000000000d0d",
  "0Y0^000000Y000000000000``000000[0^0]0000000000000000`0`",
];

class MusicComposer {
  private grid: ComposerGridState = [];
  private cellElements: HTMLDivElement[][] = [];
  private playheadTicks: HTMLDivElement[] = [];
  private gridRows = NOTE_RANGE;
  private gridCols = GRID_COLS;
  private isPlaying = false;
  private player: MusicPlayer | null = null;
  private playheadPosition = 0;
  private sweepCol = -1;
  private dragState: {
    isDragging: boolean;
    startCell: { row: number; col: number } | null;
    hoverCol: number | null;
  } = {
    isDragging: false,
    startCell: null,
    hoverCol: null,
  };
  private dragPreview: { row: number; startCol: number; endCol: number } | null =
    null;
  private throbbingCells = new Set<string>();
  private audioContext: AudioContext;

  constructor() {
    this.audioContext = new AudioContext();
    this.initializeGrid();
    this.loadFromStorage();
    this.buildGrid();
    this.buildPlayheadRuler();
    this.setupEventListeners();
    this.refreshGrid();
    this.updateBudget();
    this.updatePlayStopButton();
  }

  private initializeGrid() {
    this.grid = Array(this.gridRows)
      .fill(null)
      .map(() =>
        Array(this.gridCols)
          .fill(null)
          .map(() => ({ occupied: false, isActive: false, heldFromPrev: false })),
      );
  }

  private hasNotesInGrid(): boolean {
    for (let row = 0; row < this.gridRows; row++) {
      for (let col = 0; col < this.gridCols; col++) {
        if (this.grid[row][col].occupied) return true;
      }
    }
    return false;
  }

  private compress(): Song {
    return compressFromGrid(this.grid, this.gridRows, this.gridCols);
  }

  private tuneString(): string {
    return encodeTuneString(this.compress(), DEFAULT_TICK_MS);
  }

  private channelPost(): string {
    return encodeChannelMessage(this.tuneString(), DEFAULT_SENDER_NAME);
  }

  private setupEventListeners() {
    document
      .getElementById("playStopBtn")!
      .addEventListener("click", () => this.togglePlayStop());
    document
      .getElementById("clearBtn")!
      .addEventListener("click", () => this.confirmClear());
    document
      .getElementById("shareBtn")!
      .addEventListener("click", () => this.shareSong());
    document
      .getElementById("importBtn")!
      .addEventListener("click", () => this.showImportModal());
    document
      .getElementById("demoBtn")!
      .addEventListener("click", () => this.confirmDemo());

    document.addEventListener("keydown", (e) => {
      if (e.code === "Space" && !(e.target instanceof HTMLTextAreaElement)) {
        e.preventDefault();
        this.togglePlayStop();
      }
    });

    document.addEventListener("mouseup", () => {
      if (!this.dragState.isDragging || !this.dragState.startCell) return;
      const { row, col: startCol } = this.dragState.startCell;
      this.commitDrag(row, this.dragState.hoverCol ?? startCol);
    });
  }

  private buildPlayheadRuler() {
    const ruler = document.getElementById("playheadRuler")!;
    ruler.innerHTML = "";
    this.playheadTicks = [];

    for (let col = 0; col < this.gridCols; col++) {
      const tick = document.createElement("div");
      tick.className = "playhead-tick";
      tick.title = `Loop start: step ${col + 1}`;
      tick.addEventListener("click", () => {
        this.playheadPosition = col;
        if (this.isPlaying) {
          this.sweepCol = -1;
          this.throbbingCells.clear();
          this.startPlayback();
        }
        this.refreshGrid();
      });
      ruler.appendChild(tick);
      this.playheadTicks.push(tick);
    }
  }

  private refreshPlayheadRuler() {
    for (let col = 0; col < this.gridCols; col++) {
      const tick = this.playheadTicks[col];
      tick.classList.toggle(
        "active",
        col === this.playheadPosition && !this.isPlaying,
      );
      tick.classList.toggle("sweep", this.isPlaying && col === this.sweepCol);
    }
  }

  // Build cells once; later updates only toggle classes (no flicker, hover survives)
  private buildGrid() {
    const gridElement = document.getElementById("grid")!;
    gridElement.innerHTML = "";
    this.cellElements = [];

    for (let row = 0; row < this.gridRows; row++) {
      const rowElements: HTMLDivElement[] = [];
      // octave guide rows relative to reference note 'i' (A4)
      const isGuideRow = (HIGHEST_NOTE - row - "i".charCodeAt(0)) % 12 === 0;

      for (let col = 0; col < this.gridCols; col++) {
        const cell = document.createElement("div");
        cell.className = "cell";
        if (Math.floor(col / 4) % 2 === 1) cell.classList.add("beat");
        else if (isGuideRow) cell.classList.add("guide");

        cell.addEventListener("mousedown", (e) => {
          e.preventDefault();
          this.dragState.isDragging = true;
          this.dragState.startCell = { row, col };
          this.dragState.hoverCol = col;
          this.updateDragPreview(row, col, col);
          this.playNote(row);
        });
        cell.addEventListener("mouseenter", () => {
          if (!this.dragState.isDragging || !this.dragState.startCell) return;
          if (this.dragState.startCell.row !== row) return;
          this.dragState.hoverCol = col;
          this.updateDragPreview(
            row,
            this.dragState.startCell.col,
            col,
          );
        });

        gridElement.appendChild(cell);
        rowElements.push(cell);
      }
      this.cellElements.push(rowElements);
    }
  }

  private segmentAt(
    row: number,
    col: number,
  ): { startCol: number; length: number } | null {
    if (!this.grid[row][col].occupied) return null;

    let startCol = col;
    while (startCol > 0 && this.grid[row][startCol].heldFromPrev) {
      startCol--;
    }

    let length = 0;
    for (let c = startCol; c < this.gridCols; c++) {
      if (!this.grid[row][c].occupied) break;
      if (c > startCol && !this.grid[row][c].heldFromPrev) break;
      length++;
    }

    return { startCol, length };
  }

  private clearSegment(row: number, startCol: number, length: number) {
    for (let c = startCol; c < startCol + length; c++) {
      this.grid[row][c].occupied = false;
      this.grid[row][c].heldFromPrev = false;
    }
  }

  private clearRowSpan(row: number, startCol: number, endCol: number) {
    const minCol = Math.min(startCol, endCol);
    const maxCol = Math.max(startCol, endCol);
    for (let c = minCol; c <= maxCol; c++) {
      const seg = this.segmentAt(row, c);
      if (seg) this.clearSegment(row, seg.startCol, seg.length);
    }
  }

  private createHeldSegment(row: number, startCol: number, endCol: number) {
    const minCol = Math.min(startCol, endCol);
    const maxCol = Math.max(startCol, endCol);
    this.clearRowSpan(row, minCol, maxCol);

    this.grid[row][minCol].occupied = true;
    this.grid[row][minCol].heldFromPrev = false;
    for (let c = minCol + 1; c <= maxCol; c++) {
      this.grid[row][c].occupied = true;
      this.grid[row][c].heldFromPrev = true;
    }
  }

  private updateDragPreview(row: number, startCol: number, endCol: number) {
    this.dragPreview = {
      row,
      startCol: Math.min(startCol, endCol),
      endCol: Math.max(startCol, endCol),
    };
    this.refreshGrid();
  }

  private clearDragPreview() {
    this.dragPreview = null;
  }

  private refreshGrid() {
    for (let row = 0; row < this.gridRows; row++) {
      for (let col = 0; col < this.gridCols; col++) {
        const el = this.cellElements[row][col];
        const cell = this.grid[row][col];
        const seg = cell.occupied ? this.segmentAt(row, col) : null;
        const preview =
          this.dragPreview &&
          row === this.dragPreview.row &&
          col >= this.dragPreview.startCol &&
          col <= this.dragPreview.endCol;

        el.classList.toggle("note", cell.occupied);
        el.classList.toggle(
          "hold-start",
          !!seg && seg.length > 1 && col === seg.startCol,
        );
        el.classList.toggle(
          "hold-mid",
          !!seg &&
            cell.heldFromPrev &&
            col > seg.startCol &&
            col < seg.startCol + seg.length - 1,
        );
        el.classList.toggle(
          "hold-tail",
          !!seg &&
            cell.heldFromPrev &&
            col === seg.startCol + seg.length - 1,
        );
        el.classList.toggle(
          "drag-preview",
          !!preview &&
            this.dragPreview!.startCol !== this.dragPreview!.endCol,
        );
        el.classList.toggle(
          "throbbing",
          this.throbbingCells.has(`${row},${col}`),
        );
        el.classList.toggle(
          "sweep",
          this.isPlaying &&
            col === this.sweepCol &&
            !cell.occupied,
        );
        el.classList.toggle(
          "playhead-col",
          !this.isPlaying && col === this.playheadPosition,
        );
      }
    }
    this.refreshPlayheadRuler();
    this.updateEmptyHint();
  }

  private updateEmptyHint() {
    document.getElementById("emptyHint")!.style.display = this.hasNotesInGrid()
      ? "none"
      : "flex";
  }

  private commitDrag(row: number, col: number) {
    if (!this.dragState.isDragging || !this.dragState.startCell) return;
    const start = this.dragState.startCell;

    if (start.row === row && start.col === col) {
      const seg = this.segmentAt(row, col);
      if (seg) {
        this.clearSegment(row, seg.startCol, seg.length);
      } else {
        this.grid[row][col].occupied = true;
        this.grid[row][col].heldFromPrev = false;
      }
    } else if (start.row === row) {
      this.createHeldSegment(row, start.col, col);
    }

    this.clearDragPreview();
    this.dragState.isDragging = false;
    this.dragState.startCell = null;
    this.dragState.hoverCol = null;
    this.refreshGrid();
    this.updateBudget();
    this.saveToStorage();
  }

  private playNote(row: number) {
    const note = String.fromCharCode(HIGHEST_NOTE - row);
    playSingleNote(
      this.audioContext,
      noteToFrequency(note),
      this.audioContext.currentTime,
      {
        noteLengthMs: 200,
        volume: 0.1,
      },
    );
  }

  private createShiftedGrid(): ComposerGridState {
    let highestCol = -1;
    for (let col = this.gridCols - 1; col >= 0; col--) {
      for (let row = 0; row < this.gridRows; row++) {
        if (this.grid[row][col].occupied) {
          highestCol = col;
          break;
        }
      }
      if (highestCol !== -1) break;
    }

    if (highestCol === -1) return [];

    const shiftedGrid: ComposerGridState = Array(this.gridRows)
      .fill(null)
      .map(() =>
        Array(this.gridCols)
          .fill(null)
          .map(() => ({ occupied: false, isActive: false, heldFromPrev: false })),
      );

    for (let row = 0; row < this.gridRows; row++) {
      for (let col = this.playheadPosition; col <= highestCol; col++) {
        if (this.grid[row][col].occupied) {
          shiftedGrid[row][col - this.playheadPosition].occupied = true;
          shiftedGrid[row][col - this.playheadPosition].heldFromPrev =
            this.grid[row][col].heldFromPrev;
        }
      }
      for (let col = 0; col < this.playheadPosition; col++) {
        if (this.grid[row][col].occupied) {
          const targetCol = highestCol - this.playheadPosition + 1 + col;
          shiftedGrid[row][targetCol].occupied = true;
          shiftedGrid[row][targetCol].heldFromPrev = this.grid[row][col].heldFromPrev;
        }
      }
    }

    return shiftedGrid;
  }

  private play() {
    if (this.isPlaying || !this.hasNotesInGrid()) return;

    this.isPlaying = true;
    this.updatePlayStopButton();
    this.startPlayback();
  }

  private startPlayback() {
    this.player?.stop();

    const shiftedGrid = this.createShiftedGrid();
    const song = compressFromGrid(shiftedGrid, this.gridRows, this.gridCols);

    this.player = createSongPlayer(song);
    this.player.play({
      noteLengthMs: DEFAULT_TICK_MS,
      loop: true,
      onNotesPlayed: (col) => this.onNotesPlayed(col),
    });
  }

  private stop() {
    this.isPlaying = false;
    this.sweepCol = -1;
    this.throbbingCells.clear();
    this.player?.stop();
    this.player = null;
    this.updatePlayStopButton();
    this.refreshGrid();
  }

  private togglePlayStop() {
    if (this.isPlaying) this.stop();
    else this.play();
  }

  private updatePlayStopButton() {
    const btn = document.getElementById("playStopBtn")!;
    btn.classList.toggle("playing", this.isPlaying);
    document.getElementById("playStopText")!.textContent = this.isPlaying
      ? "Stop"
      : "Play";
    document.getElementById("playIcon")!.style.display = this.isPlaying
      ? "none"
      : "block";
    document.getElementById("stopIcon")!.style.display = this.isPlaying
      ? "block"
      : "none";
  }

  private onNotesPlayed(col: number) {
    const originalCol = this.mapShiftedColumnToOriginal(col);
    this.sweepCol = originalCol;
    let maxDuration = DEFAULT_TICK_MS;

    for (let row = 0; row < this.gridRows; row++) {
      const cell = this.grid[row][originalCol];
      if (!cell.occupied || cell.heldFromPrev) continue;

      const seg = this.segmentAt(row, originalCol);
      if (!seg) continue;

      for (let c = seg.startCol; c < seg.startCol + seg.length; c++) {
        this.throbbingCells.add(`${row},${c}`);
      }
      maxDuration = Math.max(maxDuration, seg.length * DEFAULT_TICK_MS);
    }

    this.refreshGrid();
    setTimeout(() => {
      for (let row = 0; row < this.gridRows; row++) {
        const seg = this.segmentAt(row, originalCol);
        if (!seg) continue;
        for (let c = seg.startCol; c < seg.startCol + seg.length; c++) {
          this.throbbingCells.delete(`${row},${c}`);
        }
      }
      this.refreshGrid();
    }, maxDuration);
  }

  private mapShiftedColumnToOriginal(shiftedCol: number): number {
    let highestCol = -1;
    for (let col = this.gridCols - 1; col >= 0; col--) {
      for (let row = 0; row < this.gridRows; row++) {
        if (this.grid[row][col].occupied) {
          highestCol = col;
          break;
        }
      }
      if (highestCol !== -1) break;
    }
    if (highestCol === -1) return shiftedCol;

    if (shiftedCol < highestCol - this.playheadPosition + 1) {
      return this.playheadPosition + shiftedCol;
    }
    return shiftedCol - (highestCol - this.playheadPosition + 1);
  }

  private importSong(song: Song) {
    this.playheadPosition = 0;

    const imported = uncompressSong(song, this.gridRows);
    this.initializeGrid();
    for (let row = 0; row < Math.min(imported.length, this.gridRows); row++) {
      for (
        let col = 0;
        col < Math.min(imported[row].length, this.gridCols);
        col++
      ) {
        this.grid[row][col].occupied = imported[row][col].occupied;
        this.grid[row][col].heldFromPrev = imported[row][col].heldFromPrev;
      }
    }
    this.refreshGrid();
    this.updateBudget();
    this.saveToStorage();
  }

  private shareSong() {
    if (!this.hasNotesInGrid()) return;
    navigator.clipboard.writeText(this.tuneString()).catch(() => {
      /* clipboard may fail on insecure context */
    });
  }

  private showImportModal() {
    const modal = document.createElement("div");
    modal.className = "modal";
    modal.innerHTML = `
      <div class="modal-content">
        <h3>Import MeshTunes message</h3>
        <textarea id="importTextarea" placeholder="🎶..." rows="5"></textarea>
        <div class="modal-buttons">
          <button type="button" id="importConfirm" class="primary">Import</button>
          <button type="button" id="importCancel">Cancel</button>
        </div>
      </div>
    `;
    document.body.appendChild(modal);
    const textarea = modal.querySelector(
      "#importTextarea",
    ) as HTMLTextAreaElement;
    textarea.focus();
    modal.querySelector("#importConfirm")!.addEventListener("click", () => {
      const parsed = parseWireString(textarea.value.trim());
      if (!parsed) return;
      this.importSong(parsed.song);
      modal.remove();
    });
    modal
      .querySelector("#importCancel")!
      .addEventListener("click", () => modal.remove());
    modal.addEventListener("click", (e) => {
      if (e.target === modal) modal.remove();
    });
  }

  private confirmClear() {
    if (confirm("Clear all notes?")) this.clear();
  }

  private confirmDemo() {
    if (confirm("Load demo song?")) this.importSong(DEMO_SONG);
  }

  private clear() {
    this.playheadPosition = 0;
    this.initializeGrid();
    this.refreshGrid();
    this.updateBudget();
    this.saveToStorage();
  }

  private saveToStorage() {
    PortIndependentStorage.save({
      grid: this.grid.map((row) =>
        row.map((cell) => ({
          occupied: cell.occupied,
          heldFromPrev: cell.heldFromPrev,
        })),
      ),
    });
  }

  private loadFromStorage() {
    const storageData = PortIndependentStorage.load() as {
      grid?: ComposerGridState;
    } | null;

    if (storageData?.grid) {
      for (
        let row = 0;
        row < Math.min(storageData.grid.length, this.gridRows);
        row++
      ) {
        for (
          let col = 0;
          col < Math.min(storageData.grid[row].length, this.gridCols);
          col++
        ) {
          this.grid[row][col].occupied = !!storageData.grid[row][col]?.occupied;
          this.grid[row][col].heldFromPrev =
            !!storageData.grid[row][col]?.heldFromPrev;
        }
      }
    } else {
      const imported = uncompressSong(DEMO_SONG, this.gridRows);
      for (let row = 0; row < Math.min(imported.length, this.gridRows); row++) {
        for (
          let col = 0;
          col < Math.min(imported[row].length, this.gridCols);
          col++
        ) {
          this.grid[row][col].occupied = imported[row][col].occupied;
        this.grid[row][col].heldFromPrev = imported[row][col].heldFromPrev;
        }
      }
    }
  }

  private updateBudget() {
    const song = this.compress();
    const message = song.length > 0 ? this.channelPost() : "";
    const bytes = utf8ByteLength(message);

    const warn = bytes >= MAX_POST_LEN * 0.75 && bytes <= MAX_POST_LEN;
    const over = bytes > MAX_POST_LEN;

    const budget = document.getElementById("byteBudget")!;
    budget.innerHTML = `<strong>${bytes}</strong> / ${MAX_POST_LEN} bytes`;
    budget.classList.toggle("warn", warn);
    budget.classList.toggle("over", over);

    const limitBarFill = document.getElementById("limitBarFill")!;
    const limitBarWrap = document.getElementById("limitBarWrap")!;
    limitBarFill.style.width = `${Math.min(100, (bytes / MAX_POST_LEN) * 100)}%`;
    limitBarFill.classList.toggle("warn", warn);
    limitBarFill.classList.toggle("over", over);
    limitBarWrap.title = `Public channel limit: ${bytes} / ${MAX_POST_LEN} bytes (${DEFAULT_SENDER_NAME}: 🎶…)`;
  }
}

document.addEventListener("DOMContentLoaded", () => {
  new MusicComposer();
});
