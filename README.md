# maia2-local

**Run [Maia 2](https://www.maiachess.com/) locally as a human-like chess opponent, with opening books built from real Lichess games at your rating.**

Stockfish plays perfectly. Humans don't. If you want to *improve*, you need an opponent that makes the kind of mistakes a player at your level actually makes — and capitalizes on yours the way a human would. That's what this project gives you.

Maia 2 is a neural network from the University of Toronto's CSSLab that predicts what a human at a specific rating would play. This repo wraps it as a UCI engine with opening books generated from millions of real Lichess games at your rating range, realistic thinking delays, and full multi-engine analysis support.

---

## What you get

- **Human-like play** at any rating from 600 to 2600
- **Opening books** weighted by how often real players at your level actually choose each move
- **HumanTime** — realistic thinking delays (0.5–15 seconds, scaled by position complexity)
- **Multi-engine analysis** — run Maia + Stockfish side by side to see "what a human would play" vs "what's objectively best"
- **Separate blitz and rapid engines** — Maia 2 has distinct weight files for each time control
- Works with **[En Croissant](https://encroissant.org/)** or any UCI-compatible chess GUI
- Runs on **Linux** (Pop!_OS / Ubuntu 24.04) and **macOS** (Apple Silicon with MPS acceleration)

---

## Quick start — Linux

```bash
git clone https://github.com/Dash1971/maia2-local.git
cd maia2-local
chmod +x *.sh

# 1. Install Maia 2, UCI wrapper, Stockfish, En Croissant (~10 min)
./setup-maia2.sh

# 2. Build opening books (~30-60 min total, interactive)
./build-books.sh
```

The book builder prompts you for target rating(s), time control, and download size. Default is `1400,1600,1800` across all time controls from 5 GB of data — sufficient for strong books in about 45 minutes.

Then point En Croissant at `~/chess/maia2-engine/maia2-engine.sh` with BookFile set to your generated `.bin`. See [GUIDE.md](GUIDE.md) for the complete walkthrough.

## Quick start — macOS (Apple Silicon)

I didn't build any book file on Mac. (just copy a `.bin` book file from your Linux machine (or grab one from this repo's Releases).

See [GUIDE-macOS.md](GUIDE-macOS.md) for the full walkthrough. Uses Apple Silicon's GPU via MPS for faster inference.

---

## What's in the repo

| File | Purpose |
|---|---|
| `setup-maia2.sh` | One-shot Linux installer for Maia 2, UCI wrapper, Stockfish, En Croissant |
| `maia2_uci.py` | UCI engine wrapper (book support, HumanTime, analysis mode, flat eval) |
| `build-books.sh` | Interactive book builder — downloads Lichess data, streams it through Python, writes `.bin` books |
| [`GUIDE.md`](GUIDE.md) | Full Linux setup guide |
| [`GUIDE-macOS.md`](GUIDE-macOS.md) | Full macOS setup guide (Apple Silicon / MPS) |

---

## How the book builder works

```
Lichess .pgn.zst → curl (5 GB slice) → zstdcat → Python (in-memory) → .bin books
```

The builder downloads a portion of a Lichess monthly archive (you choose 2/5/10 GB), streams the decompressed PGN through Python, and keeps move-frequency stats in memory per rating bucket. When the stream ends, it writes one Polyglot `.bin` file per requested rating.

**Key details:**

- **Multiple ratings in one pass.** Ask for `1400,1600,1800` and each game gets counted in every bucket its average rating falls into (±100 by default). The download only happens once.
- **Choose your data source.** The builder prompts for a Lichess monthly archive (e.g. `2024-01`, `2025-06`). Default is `2024-01`. Browse available months at [database.lichess.org](https://database.lichess.org).
- **Proportional weight scaling.** The most-popular move in any position gets the Polyglot max weight of 65,535, and everything else is scaled proportionally — so popular first moves don't all cap at the same value.
- **PyPy auto-detected.** If `pypy3` is installed with the `chess` package, the builder uses it for 3-5x speedup. Otherwise falls back to the CPython venv created by the setup script.
- **Ctrl-C safe.** If you abort mid-stream, it still writes books with whatever data it has collected.

---

## Difficulty calibration

Maia plays stronger than its nominal rating because it never tilts, never blunders from time pressure, and always picks its most-likely move (real players sometimes pick the 3rd or 4th). Start here:

| Your Rating | Set Maia ELO To |
|:-:|:-:|
| 1200 | 800 |
| 1400 | 1000 |
| 1600 | 1200 |
| 1800 | 1400 |
| 2000 | 1700 |

Adjust ±200 from there to find your sparring sweet spot. For higher ratings (2200+) the gap narrows — Maia 2200 plays roughly like a real 2200.

---

## Multi-engine analysis

Set up two Maia engines in En Croissant:

1. **Maia 2 (play)** — `HumanTime=true`, BookFile set, Depth=1
2. **Maia 2 Analysis** — `HumanTime=false`, no BookFile, Depth=1

Plus Stockfish for objective evaluation. In the Analysis panel, add both Stockfish and Maia 2 Analysis. As you step through a game:

- **Stockfish** says what's objectively best
- **Maia** says what a human at your target rating would actually play

When they agree, the move is both good and natural to find. When they disagree, that's exactly where your improvement opportunities are.

---

## Credits

- **[Maia 2](https://www.maiachess.com/)** by CSSLab, University of Toronto — the neural network that makes this possible
- **[En Croissant](https://encroissant.org/)** by Francisco Salgueiro — the GUI
- **[Lichess](https://lichess.org/)** — the game database (released under CC0)
- **[python-chess](https://python-chess.readthedocs.io/)** — board representation, zobrist hashing, Polyglot reading

---

## License

MIT for scripts and wrapper code in this repo. Maia 2 model weights have their own license — see the [Maia chess repo](https://github.com/CSSLab/maia-chess). Lichess data is CC0.
| `lichess-import-parallel.sh` | Parallel Lichess game importer with awk pre-filter |
| `build-stats-fast.sh` | Opening stats builder (staging table + PyPy) |
| `build-book.sh` | Polyglot `.bin` generator with proportional weight scaling |
| `query.sh` | Interactive queries against your local Lichess database |
| `sanity-check.sh` | Verifies books and database against known expectations |
| [`GUIDE.md`](GUIDE.md) | Full Linux setup guide |
| [`GUIDE-macOS.md`](GUIDE-macOS.md) | Full macOS setup guide (Apple Silicon / MPS) |
