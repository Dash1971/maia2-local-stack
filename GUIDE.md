# Maia 2 Local Chess — Linux Setup Guide

Complete walkthrough for setting up Maia 2 on Pop!_OS 24.04 (or another Ubuntu 24.04 derivative), with opening books built from Lichess games and optional side-by-side analysis with Stockfish.

**Tested on:** Pop!_OS 24.04 LTS (COSMIC desktop). Should work on any Ubuntu 24.04 base. Requires ~8 GB disk space (includes 5 GB temporary download during book build).

---

## 1. Install Maia 2 + En Croissant

Run:

```bash
git clone https://github.com/Dash1971/maia2-local-stack.git
cd maia2-local-stack
chmod +x *.sh
./setup-maia2.sh
```

This takes about 10 minutes and installs:

- Python venv at `~/chess/maia2-engine/venv/`
- PyTorch (CPU build) + Maia 2 + undeclared dependencies
- Stockfish (from `apt`)
- En Croissant (from the official `.deb`)
- The UCI wrapper at `~/chess/maia2-engine/maia2_uci.py`
- A launcher at `~/chess/maia2-engine/maia2-engine.sh`

`pip install maia2` does not declare all of its runtime dependencies. The setup script pre-installs them (`pyyaml gdown chess einops pyzstd requests pandas numpy tqdm`).

### Smoke test

After setup finishes, verify the engine responds:

```bash
echo -e "uci\nisready\nposition startpos\ngo\nquit" | ~/chess/maia2-engine/maia2-engine.sh
```

First run takes about 20 seconds while the neural network loads. You should see `uciok`, `readyok`, then a `bestmove` with a legal move.

---

## 2. Build opening books

Run the interactive book builder:

```bash
./build-books.sh
```

It will ask you four questions:

**1. Target rating(s)** — any comma-separated list from 600 to 2600 in 100-elo steps. Default: `1400,1600,1800`. Each book includes games whose average player rating is within ±100 of that target.

**2. Time control:**
- Rapid only
- Blitz only
- Classical only
- Blitz + Rapid
- All (default)

**3. Download size:**
- 2 GB (~5M games, ~25 min total)
- 5 GB (~15M games, ~45 min total) ← default
- 10 GB (~30M games, ~90 min total)

**4. Lichess monthly archive** — the month of game data to use (format: `YYYY-MM`). Default: `2024-01`. Recent months have more games. Browse all available months at [database.lichess.org](https://database.lichess.org). A month typically becomes available a few days into the following month.

Confirm, and it will:
1. Download the chosen amount of data from the specified month
2. Stream it through Python, filtering and aggregating in memory
3. Write one `.bin` per requested rating to `~/chess/books/`
4. Delete the temporary download

Output filenames follow the pattern `lichess_<rating>_<speed>.bin`:
- `lichess_1600_all.bin`
- `lichess_1600_rapid.bin`
- `lichess_1600_blitz_rapid.bin`

### Faster with PyPy

Install PyPy for 3-5× speedup on the book-building inner loop:

```bash
sudo apt install pypy3
pypy3 -m pip install chess --break-system-packages
```

`build-books.sh` auto-detects PyPy and uses it if available.

### Non-interactive mode

For scripting or re-runs:

```bash
./build-books.sh --defaults
```

Uses the defaults (`1400,1600,1800` / all speeds / 5 GB) without prompting.

---

## 3. Configure En Croissant

Launch En Croissant. Set up **three engines** in the Engines tab.

### Engine 1: Maia 2 (for playing)

- **Engines → Add New → Local → Binary file**
- **Path:** `/home/<your-username>/chess/maia2-engine/maia2-engine.sh`
- **Depth:** `1` (critical — Maia does no search, it just asks the network once)
- **ELO:** your target strength (see calibration table below)
- **BookFile:** `/home/<your-username>/chess/books/lichess_1600_all.bin` (or whichever book matches your target)
- **HumanTime:** `true` (optional thinking delays)

### Engine 2: Maia 2 Analysis (for the analysis panel)

Same path as Engine 1, but:
- **Name:** `Maia 2 Analysis`
- **HumanTime:** `false`
- **BookFile:** leave blank

Using two separate engine entries keeps play settings and analysis settings separate.

### Engine 3: Stockfish (for objective evaluation)

- **Path:** `/usr/games/stockfish`

### Important: two ELO fields in En Croissant

En Croissant shows the ELO setting in two places. The **General settings** one (top, under the engine's card) is essentially a cosmetic label. The **Advanced settings** one (bottom, under the UCI options section) is the real one that gets sent to the engine. Set both the same value; only the bottom one actually affects play.

---

## 4. Calibration

Use this as a starting point rather than a measured equivalence table:

| Your Rating | Set Maia ELO To | Adjust Range |
|:-:|:-:|:-:|
| 1200 | 800 | 600–1000 |
| 1400 | 1000 | 800–1200 |
| 1600 | 1200 | 1000–1400 |
| 1800 | 1400 | 1200–1600 |
| 2000 | 1700 | 1500–1900 |

For higher-rated play (2200+), the gap may narrow.

---

## 5. Multi-engine analysis

In En Croissant's **Analysis** tab:

1. Open a game (or start a new position)
2. Click the **+** button to add a second engine line
3. Set one line to **Stockfish** and the other to **Maia 2 Analysis**

As you step through moves:

- **Stockfish** shows what's objectively best
- **Maia** shows what a human at your target rating would actually play

When both engines agree, the move is both good and natural to find. When they disagree, that's exactly where your improvement opportunities are — positions where humans at your level systematically miss something.

**Note on Maia's evaluation:** the Maia engine always reports `score cp 0` (flat evaluation bar). This is intentional — Maia predicts human moves, not position value. Its internal `win_prob` is a statistical prediction about game outcomes, not a tactical evaluation, and it's wildly unreliable for specific positions (it'll show "losing" when there's mate in one). Let Stockfish handle the evaluation bar.

---

## 6. Playing a game

1. **Game → New game**
2. Pick a color
3. Select **Maia 2** as the opponent (the one with BookFile + HumanTime)
4. Start playing

Expect Maia to think for 1-6 seconds per move, with longer pauses on complex or tactical positions. If it moves instantly every time, `HumanTime` isn't set — double-check the Advanced settings tab.

---

## 7. Blitz-specific engine (optional)

Maia 2 has separate weight files for blitz and rapid. The default setup uses the rapid weights. To add a blitz-specific engine:

```bash
cp ~/chess/maia2-engine/maia2_uci.py ~/chess/maia2-engine/maia2_uci_blitz.py
sed -i 's/type="rapid"/type="blitz"/' ~/chess/maia2-engine/maia2_uci_blitz.py

cat > ~/chess/maia2-engine/maia2-engine-blitz.sh << 'EOF'
#!/bin/bash
DIR="$(cd "$(dirname "$0")" && pwd)"
source "$DIR/venv/bin/activate"
exec python3 "$DIR/maia2_uci_blitz.py" "$@"
EOF
chmod +x ~/chess/maia2-engine/maia2-engine-blitz.sh
```

Add it as a separate engine in En Croissant pointing at `maia2-engine-blitz.sh`. Blitz Maia can produce a different style from the rapid weights and is useful as a separate practice engine.

---

## 8. Tuning HumanTime

Edit `~/chess/maia2-engine/maia2_uci.py` and find the `calculate_think_time()` function. The main knob is the base delay:

```python
base = 2.0 + min(num_legal / 10.0, 4.0)
```

- **Faster moves:** change `2.0` to `1.0`
- **Slower moves:** change `2.0` to `4.0`

Other factors stack on top: captures, checks, and promotions each add 1.5-2 seconds. The endgame (≤12 pieces) multiplies by 1.2, the opening (≥28 pieces) multiplies by 0.7. Random variance of ±30% keeps moves from feeling robotic.

Changes take effect on the next new game.

---

## Troubleshooting

### `maia2-engine.sh: Permission denied`
```bash
chmod +x ~/chess/maia2-engine/maia2-engine.sh ~/chess/maia2-engine/maia2_uci.py
```

### First move takes 20+ seconds
Normal — the neural network loads on first use. Subsequent moves are faster.

### "Maia moves a knight back and forth" or doesn't follow opening theory
The opening book isn't loading. Check:
- `BookFile` path in En Croissant uses the absolute path (`/home/you/chess/books/...`), not `~`
- No quotes around the path
- The `.bin` file actually exists at that path (`ls -l ~/chess/books/`)

### No analysis shows in the analysis panel
Make sure you're using **Maia 2 Analysis** (HumanTime off) in the analysis panel, not the play engine. The play engine has HumanTime on which causes delays that don't work well for analysis.

### Book builder fails with "HTTP 404"
The monthly Lichess file for that month isn't available yet — new months are published a few days into the following month. Re-run `./build-books.sh` and pick a different month when prompted, or check [database.lichess.org](https://database.lichess.org) for the list of available months.

### `build-books.sh` runs out of memory
Unlikely with 8+ GB RAM, but if it does, try with a smaller data size (option 1: 2 GB).

---

## File layout after setup

```
~/chess/
├── maia2-engine/
│   ├── maia2-engine.sh         # launcher (point En Croissant here)
│   ├── maia2_uci.py            # UCI wrapper with book + HumanTime
│   └── venv/                   # Python environment
└── books/
    ├── lichess_1400_all.bin    # your opening books
    ├── lichess_1600_all.bin
    └── lichess_1800_all.bin
```

At that point, the local setup is complete.
