# Maia 2 Local Chess — macOS Setup Guide (Apple Silicon)

Set up Maia 2 on your Apple Silicon Mac: human-like AI opponent, opening books built from real Lichess games at your rating, HumanTime thinking delays, and multi-engine analysis with Stockfish.

**Tested on:** M4 MacBook Air, macOS Sequoia. Works on any Apple Silicon Mac (M1/M2/M3/M4). PyTorch uses **MPS** (Apple Silicon GPU) for faster neural network inference.

**Disk space needed:** about 8 GB (PyTorch ~3 GB + temporary book-build download ~5 GB).

---

## 1. Install Homebrew

Open Terminal (Cmd+Space → type "Terminal") and run:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

Follow the prompts. After it finishes, run whatever PATH commands it prints (usually something like):

```bash
echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
eval "$(/opt/homebrew/bin/brew shellenv)"
```

Verify: `brew --version`

---

## 2. Install Maia 2 (one command)

```bash
cd ~
git clone https://github.com/Dash1971/maia2-local-stack.git
cd maia2-local-stack
chmod +x *.sh

./setup-maia2.sh
```

This takes about 10 minutes and handles everything:

- `brew install` for Python 3.12, Stockfish, zstd
- Python venv at `~/chess/maia2-engine/venv/`
- PyTorch with MPS (Apple Silicon GPU) support
- Maia 2 + undeclared dependencies
- UCI wrapper with `device="mps"` baked in
- Launcher at `~/chess/maia2-engine/maia2-engine.sh`
- Local copy of Stockfish at `~/chess/stockfish` (En Croissant workaround — see note below)
- Smoke test to confirm the engine works

**About the Stockfish workaround:** En Croissant on Apple Silicon can't run binaries from `/opt/homebrew/bin/` directly due to macOS permissions. The script copies Stockfish to `~/chess/stockfish` so En Croissant has a path it can execute.

**About En Croissant itself:** The script can't auto-install it on macOS (the `.dmg` requires a manual drag-to-Applications). It'll print instructions at the end — do step 3 below.

---

## 3. Install En Croissant

Download the **aarch64 (Apple Silicon) .dmg** from:

https://github.com/franciscoBSalgueiro/en-croissant/releases/download/v0.15.0/en-croissant_0.15.0_aarch64.dmg

Open the .dmg and drag En Croissant to Applications.

**First launch:** macOS will block the app. Go to System Settings → Privacy & Security → scroll down and click "Open Anyway."

---

## 4. Build opening books

Same command as Linux — the script auto-detects your OS:

```bash
./build-books.sh
```

It will ask you four questions:

**1. Target rating(s)** — comma-separated, from 600 to 2600 in 100-elo steps. Default: `1400,1600,1800`. Each book uses games whose average player rating is within ±100 of the target.

**2. Time control:**
- Rapid only
- Blitz only
- Classical only
- Blitz + Rapid
- All (default)

**3. Download size:**
- 2 GB (~5M games, ~25 min)
- 5 GB (~15M games, ~45 min) ← default
- 10 GB (~30M games, ~90 min)

**4. Lichess monthly archive** — format `YYYY-MM`. Default: `2024-01`. Browse all available months at [database.lichess.org](https://database.lichess.org).

The script downloads the chosen portion of the archive, streams it through Python in memory, writes `.bin` books to `~/chess/books/`, and deletes the temporary download.

### Optional: speed it up with PyPy

PyPy's JIT compiler makes the book build 3-5× faster:

```bash
brew install pypy3
pypy3 -m pip install chess
```

`build-books.sh` auto-detects PyPy and uses it if available.

### Non-interactive mode

For scripting or re-runs:

```bash
./build-books.sh --defaults
```

Uses defaults (`1400,1600,1800` / all speeds / 5 GB / `2024-01`) without prompting.

---

## 5. Configure En Croissant

Launch En Croissant. Set up **three engines** in the Engines tab.

### Engine 1: Maia 2 (for playing)

- **Engines → Add New → Local → Binary file**
- macOS Finder hides your home folder by default. When the file picker opens, press **Cmd+Shift+G** and type: `~/chess/maia2-engine/maia2-engine.sh`
- **Depth:** `1` (critical — Maia does no search)
- **ELO:** your target strength (your rating minus 200-400, see calibration below)
- **BookFile:** `/Users/YOUR_USERNAME/chess/books/lichess_1600_all.bin` (use full absolute path, not `~`)
- **HumanTime:** `true` (for realistic thinking delays)

### Engine 2: Maia 2 Analysis (for the analysis panel)

Same path as Engine 1, but:
- **Name:** `Maia 2 Analysis`
- **HumanTime:** `false`
- **BookFile:** leave blank

### Engine 3: Stockfish

- **Path:** `~/chess/stockfish` (the local copy from the setup script)

### Important: two ELO fields

En Croissant shows the ELO setting in two places. The **General settings** one (top) is cosmetic. The **Advanced settings** one (bottom, under UCI options) is the real one sent to the engine. Set both to the same value; only the bottom one actually affects play.

---

## 6. Calibration

Maia plays stronger than its nominal rating because it never tilts, never blunders from time pressure, and always picks its most-likely move. Start here:

| Your Rating | Set ELO To | Adjust Range |
|-------------|-----------|--------------|
| 1200 | 800 | 600–1000 |
| 1400 | 1000 | 800–1200 |
| 1600 | 1200 | 1000–1400 |
| 1800 | 1400 | 1200–1600 |
| 2000 | 1700 | 1500–1900 |

For higher ratings (2200+) the gap narrows — Maia 2200 plays roughly like a real 2200.

---

## 7. Multi-engine analysis

In En Croissant's Analysis tab:

1. Open a game → Analysis tab
2. Click **+** to add a second engine line
3. Set one to Stockfish, the other to Maia 2 Analysis

Stockfish shows the objectively best move. Maia shows what a human at your configured rating would actually play. Maia reports a flat evaluation (always `cp 0`) — this is intentional; Maia predicts human moves, not position value. Use Stockfish for the real eval.

When they agree: the move is both good and natural to find. When they disagree: that's where your improvement opportunities are.

---

## 8. Playing a game

1. **Game → New game**
2. Pick a color
3. Select **Maia 2** as the opponent (the one with BookFile + HumanTime)
4. Start playing

Expect Maia to think for 1-6 seconds per move. If it moves instantly every time, HumanTime isn't set — double-check the Advanced settings.

---

## 9. Blitz engine (optional)

Maia 2 has separate weight files for blitz and rapid. Default uses rapid. For a blitz practice partner:

```bash
cp ~/chess/maia2-engine/maia2_uci.py ~/chess/maia2-engine/maia2_uci_blitz.py
sed -i '' 's/type="rapid"/type="blitz"/' ~/chess/maia2-engine/maia2_uci_blitz.py

cat > ~/chess/maia2-engine/maia2-engine-blitz.sh << 'EOF'
#!/bin/bash
DIR="$(cd "$(dirname "$0")" && pwd)"
source "$DIR/venv/bin/activate"
exec python3 "$DIR/maia2_uci_blitz.py" "$@"
EOF
chmod +x ~/chess/maia2-engine/maia2-engine-blitz.sh
```

Add as a separate engine in En Croissant. You can also build a blitz-specific opening book by re-running `./build-books.sh` and choosing option 2 (Blitz only) for the time control.

---

## 10. Tuning HumanTime

Edit `~/chess/maia2-engine/maia2_uci.py` and find `calculate_think_time()`. The main knob:

```python
base = 2.0 + min(num_legal / 10.0, 4.0)
```

- Faster moves: change `2.0` to `1.0`
- Slower moves: change `2.0` to `4.0`

Start a new game to pick up changes.

---

## Troubleshooting

### "maia2-engine.sh: Permission denied"

```bash
chmod +x ~/chess/maia2-engine/maia2-engine.sh ~/chess/maia2-engine/maia2_uci.py
```

### En Croissant can't find the engine file

Press **Cmd+Shift+G** in the file picker and type the full path (e.g., `/Users/YOUR_USERNAME/chess/maia2-engine/maia2-engine.sh`).

### "Maia moves its knight back and forth"

Opening book isn't loading. Check BookFile uses the absolute path (`/Users/YOUR_USERNAME/...` not `~`), no quotes, and the `.bin` file exists at that path.

### First move takes 20+ seconds

Normal — the neural network loads on first use. Subsequent moves are much faster.

### Stockfish download in En Croissant fails / crashes

Known bug on Apple Silicon (downloads wrong architecture binary). The setup script copies Stockfish to `~/chess/stockfish` to work around this — point En Croissant there instead of using the built-in downloader.

### "No analysis available" in analysis panel

Make sure you're using **Maia 2 Analysis** (HumanTime off), not the play engine.

### `build-books.sh` can't find zstdcat or curl

The setup script installs `zstd` via Homebrew, but if it didn't run: `brew install zstd`. `curl` is built into macOS.

### `build-books.sh` fails with "HTTP 404"

The Lichess archive for that month isn't available yet (new months publish a few days into the following month). Re-run and pick a different month, or check [database.lichess.org](https://database.lichess.org).

### `setup-maia2.sh` says "Homebrew is required"

Install Homebrew first (see step 1), then re-run the setup script.

---

## File Layout

```
~/chess/
├── maia2-engine/
│   ├── maia2-engine.sh      # launcher (point En Croissant here)
│   ├── maia2_uci.py         # UCI wrapper (MPS-accelerated)
│   └── venv/                # Python environment
├── books/
│   ├── lichess_1400_all.bin  # your opening books
│   ├── lichess_1600_all.bin
│   └── lichess_1800_all.bin
└── stockfish                 # local copy for En Croissant
```

That's it. One setup command, one book-builder command, one En Croissant download — and you've got human-like chess running locally on your Mac with MPS acceleration.
