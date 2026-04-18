#!/usr/bin/env bash
# ╔══════════════════════════════════════════════════════════════════════╗
# ║  build-books.sh — Interactive book builder, no database              ║
# ║                                                                    ║
# ║  Prompts for rating(s), time control, and download size, then      ║
# ║  downloads a portion of a Lichess monthly archive, streams it      ║
# ║  through a Python builder that keeps stats in memory, writes       ║
# ║  Polyglot .bin books, and deletes the download.                    ║
# ║                                                                    ║
# ║  No database. No WAL. No intermediate files on disk.               ║
# ║                                                                    ║
# ║  Usage:                                                            ║
# ║    ./build-books.sh                  # interactive                  ║
# ║    ./build-books.sh --defaults       # non-interactive              ║
# ╚══════════════════════════════════════════════════════════════════════╝

set -eu

BOOKS_DIR="$HOME/chess/books"
TMP_DIR="$HOME/chess/bookbuild-tmp"
PYSCRIPT="$TMP_DIR/build.py"

GREEN='\033[0;32m'; CYAN='\033[0;36m'; RED='\033[0;31m'; YELLOW='\033[1;33m'
BOLD='\033[1m'; DIM='\033[2m'; RESET='\033[0m'

# ═══════════════════════════════════════════════════════════════════════
#  Interactive prompts
# ═══════════════════════════════════════════════════════════════════════
clear
echo ""
echo -e "${BOLD}${CYAN}╔══════════════════════════════════════════════════════════════════╗${RESET}"
echo -e "${BOLD}${CYAN}║  ♟  Lichess Opening Book Builder                                 ║${RESET}"
echo -e "${BOLD}${CYAN}║                                                                  ║${RESET}"
echo -e "${BOLD}${CYAN}║  Builds Polyglot .bin opening books from real Lichess games      ║${RESET}"
echo -e "${BOLD}${CYAN}║  at your chosen rating level.                                    ║${RESET}"
echo -e "${BOLD}${CYAN}║                                                                  ║${RESET}"
echo -e "${BOLD}${CYAN}║  Runtime: ~30-60 min  •  Memory: 1-3 GB  •  Temp disk: ~5 GB     ║${RESET}"
echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════════════════════════════╝${RESET}"
echo ""

# ─── Defaults (used if --defaults flag or all prompts accept defaults) ─
DEFAULT_RATINGS="1400,1600,1800"
DEFAULT_SPEED=5      # All
DEFAULT_SIZE=2       # 5 GB
DEFAULT_MONTH="2024-01"  # well-tested, known to be available

if [[ "${1:-}" == "--defaults" ]]; then
    RATINGS="$DEFAULT_RATINGS"
    SPEED_CHOICE="$DEFAULT_SPEED"
    SIZE_CHOICE="$DEFAULT_SIZE"
    MONTH="$DEFAULT_MONTH"
else
    # ─── Step 1: Ratings ────────────────────────────────────────────
    echo -e "${BOLD}Step 1 of 4: TARGET RATING(S)${RESET}"
    echo -e "${DIM}─────────────────────────────────${RESET}"
    echo ""
    echo -e "  Which rating(s) do you want books for?"
    echo -e "  ${DIM}Valid: 600, 700, 800 ... 2500, 2600 (100-elo steps)${RESET}"
    echo -e "  ${DIM}Each book uses games whose average rating is within ±100 of target.${RESET}"
    echo ""
    echo -e "  Pick one or more (comma-separated), or press Enter for default."
    echo -e "  Example: ${CYAN}1400,1600,1800${RESET}"
    echo ""
    read -p "  > " RATINGS
    RATINGS="${RATINGS:-$DEFAULT_RATINGS}"
    echo ""

    # ─── Step 2: Speed ──────────────────────────────────────────────
    echo -e "${BOLD}Step 2 of 4: TIME CONTROL${RESET}"
    echo -e "${DIM}─────────────────────────${RESET}"
    echo ""
    echo -e "  ${CYAN}1)${RESET} Rapid only"
    echo -e "  ${CYAN}2)${RESET} Blitz only"
    echo -e "  ${CYAN}3)${RESET} Classical only"
    echo -e "  ${CYAN}4)${RESET} Blitz + Rapid"
    echo -e "  ${CYAN}5)${RESET} All (Blitz + Rapid + Classical)  ${DIM}[default]${RESET}"
    echo ""
    read -p "  > " SPEED_CHOICE
    SPEED_CHOICE="${SPEED_CHOICE:-$DEFAULT_SPEED}"
    echo ""

    # ─── Step 3: Size ───────────────────────────────────────────────
    echo -e "${BOLD}Step 3 of 4: DATA SIZE${RESET}"
    echo -e "${DIM}──────────────────────${RESET}"
    echo ""
    echo -e "  ${DIM}More data = better book but longer download + process time.${RESET}"
    echo ""
    echo -e "  ${CYAN}1)${RESET} 2 GB   ${DIM}(~5M games,  ~25 min total)${RESET}"
    echo -e "  ${CYAN}2)${RESET} 5 GB   ${DIM}(~15M games, ~45 min total)${RESET}  ${DIM}[default]${RESET}"
    echo -e "  ${CYAN}3)${RESET} 10 GB  ${DIM}(~30M games, ~90 min total)${RESET}"
    echo ""
    read -p "  > " SIZE_CHOICE
    SIZE_CHOICE="${SIZE_CHOICE:-$DEFAULT_SIZE}"
    echo ""

    # ─── Step 4: Month ──────────────────────────────────────────────
    echo -e "${BOLD}Step 4 of 4: LICHESS DATA MONTH${RESET}"
    echo -e "${DIM}────────────────────────────────${RESET}"
    echo ""
    echo -e "  Which Lichess monthly archive to use?"
    echo -e "  ${DIM}Format: YYYY-MM   e.g. 2024-01, 2025-06${RESET}"
    echo -e "  ${DIM}Recent months have more games. See database.lichess.org${RESET}"
    echo -e "  ${DIM}for all available months (updated monthly from 2013 onwards).${RESET}"
    echo ""
    echo -e "  Press Enter for default: ${CYAN}$DEFAULT_MONTH${RESET}"
    echo ""
    read -p "  > " MONTH
    MONTH="${MONTH:-$DEFAULT_MONTH}"
    echo ""
fi

# ─── Validate ratings ──────────────────────────────────────────────────
IFS=',' read -ra RATING_ARRAY <<< "$RATINGS"
VALID_RATINGS=()
for r in "${RATING_ARRAY[@]}"; do
    r=$(echo "$r" | tr -d ' ')
    if [[ "$r" =~ ^[0-9]+$ ]] && [[ $((r % 100)) -eq 0 ]] && [[ $r -ge 600 ]] && [[ $r -le 2600 ]]; then
        VALID_RATINGS+=("$r")
    else
        echo -e "${RED}✖${RESET} Invalid rating: '$r'  (must be 600-2600 in 100-elo steps)"
        exit 1
    fi
done
RATINGS=$(IFS=','; echo "${VALID_RATINGS[*]}")

# ─── Translate speed choice ────────────────────────────────────────────
case "$SPEED_CHOICE" in
    1) SPEED_NAME="rapid";       SPEED_FILTER="rapid" ;;
    2) SPEED_NAME="blitz";       SPEED_FILTER="blitz" ;;
    3) SPEED_NAME="classical";   SPEED_FILTER="classical" ;;
    4) SPEED_NAME="blitz_rapid"; SPEED_FILTER="blitz,rapid" ;;
    5) SPEED_NAME="all";         SPEED_FILTER="blitz,rapid,classical" ;;
    *) echo -e "${RED}✖${RESET} Invalid speed choice"; exit 1 ;;
esac

# ─── Translate size choice ─────────────────────────────────────────────
case "$SIZE_CHOICE" in
    1) MAX_GB=2 ;;
    2) MAX_GB=5 ;;
    3) MAX_GB=10 ;;
    *) echo -e "${RED}✖${RESET} Invalid size choice"; exit 1 ;;
esac
MAX_BYTES=$((MAX_GB * 1073741824))

# ─── Validate month format ─────────────────────────────────────────────
if ! [[ "$MONTH" =~ ^[0-9]{4}-[0-9]{2}$ ]]; then
    echo -e "${RED}✖${RESET} Invalid month format: '$MONTH' (must be YYYY-MM)"
    exit 1
fi
MONTH_YEAR="${MONTH%-*}"
MONTH_MONTH="${MONTH#*-}"
if [[ $MONTH_YEAR -lt 2013 ]] || [[ $MONTH_YEAR -gt 2099 ]]; then
    echo -e "${RED}✖${RESET} Invalid year in month '$MONTH' (Lichess archives start in 2013)"
    exit 1
fi
if [[ $((10#$MONTH_MONTH)) -lt 1 ]] || [[ $((10#$MONTH_MONTH)) -gt 12 ]]; then
    echo -e "${RED}✖${RESET} Invalid month number in '$MONTH'"
    exit 1
fi

# Set CHUNK path based on chosen month
CHUNK="$TMP_DIR/lichess-${MONTH}.pgn.zst"

# ─── Confirm ───────────────────────────────────────────────────────────
echo -e "${BOLD}Summary${RESET}"
echo -e "${DIM}───────${RESET}"
echo -e "  Ratings:  ${CYAN}${RATINGS}${RESET}"
echo -e "  Speed:    ${CYAN}${SPEED_NAME}${RESET}"
echo -e "  Size:     ${CYAN}${MAX_GB} GB${RESET}"
echo -e "  Month:    ${CYAN}${MONTH}${RESET}"
echo -e "  Books →   ${CYAN}${BOOKS_DIR}/${RESET}"
echo ""

if [[ "${1:-}" != "--defaults" ]]; then
    read -p "  Proceed? [Y/n] " CONFIRM
    if [[ "$CONFIRM" =~ ^[Nn] ]]; then
        echo "Cancelled."
        exit 0
    fi
fi
echo ""

# ═══════════════════════════════════════════════════════════════════════
#  Dependencies (cross-platform: Linux + macOS)
# ═══════════════════════════════════════════════════════════════════════
OS="$(uname -s)"

install_hint() {
    local pkg="$1"
    if [[ "$OS" == "Darwin" ]]; then
        echo -e "${RED}✖${RESET} $pkg not found. Install with: ${CYAN}brew install $pkg${RESET}"
    else
        echo -e "${RED}✖${RESET} $pkg not found. Install with: ${CYAN}sudo apt install $pkg${RESET}"
    fi
    exit 1
}

command -v zstdcat &>/dev/null || install_hint "zstd"
command -v curl     &>/dev/null || install_hint "curl"

if command -v pypy3 &>/dev/null && pypy3 -c "import chess; import chess.polyglot; import chess.pgn" 2>/dev/null; then
    PYTHON_CMD="pypy3"
    echo -e "  ${GREEN}✔${RESET} Using PyPy3 (3-5x faster for this workload)"
else
    VENV="$HOME/chess/maia2-engine/venv"
    if [[ ! -d "$VENV" ]]; then
        echo -e "${RED}✖${RESET} Maia 2 venv not found at $VENV"
        if [[ "$OS" == "Darwin" ]]; then
            echo "   Follow GUIDE-macOS.md steps 1-6 first."
        else
            echo "   Run setup-maia2.sh first."
        fi
        exit 1
    fi
    source "$VENV/bin/activate"
    PYTHON_CMD="python3"
    if [[ "$OS" == "Darwin" ]]; then
        echo -e "  ${DIM}Using CPython. For 3-5x speedup: brew install pypy3${RESET}"
        echo -e "  ${DIM}  then: pypy3 -m pip install chess${RESET}"
    else
        echo -e "  ${DIM}Using CPython. For 3-5x speedup: sudo apt install pypy3${RESET}"
        echo -e "  ${DIM}  then: pypy3 -m pip install chess --break-system-packages${RESET}"
    fi
fi

mkdir -p "$BOOKS_DIR" "$TMP_DIR"

# ═══════════════════════════════════════════════════════════════════════
#  Step A: Download
# ═══════════════════════════════════════════════════════════════════════
echo ""
echo -e "${BOLD}[1/3] Downloading ${MAX_GB} GB of Lichess ${MONTH} data${RESET}"
echo ""

DB_URL="https://database.lichess.org/standard/lichess_db_standard_rated_${MONTH}.pgn.zst"

# Portable file size (Linux stat -c%s vs macOS stat -f%z → just use wc)
file_size() { wc -c < "$1" 2>/dev/null | tr -d ' ' || echo 0; }

if [[ -f "$CHUNK" ]] && [[ $(file_size "$CHUNK") -gt $((MAX_BYTES / 2)) ]]; then
    SIZE_GB=$(awk "BEGIN{printf \"%.1f\", $(file_size "$CHUNK") / 1024 / 1024 / 1024}")
    echo -e "  ${GREEN}✔${RESET} Using existing download (${SIZE_GB} GB at $CHUNK)"
else
    HTTP=$(curl -sI -o /dev/null -w "%{http_code}" "$DB_URL")
    if [[ "$HTTP" != "200" ]]; then
        echo -e "  ${RED}✖${RESET} HTTP $HTTP — month ${MONTH} not available"
        echo -e "     The Lichess archive for $MONTH may not exist yet"
        echo -e "     (new months publish a few days into the following month)"
        echo -e "     Browse available months at: ${CYAN}https://database.lichess.org${RESET}"
        exit 1
    fi

    curl -L \
        --range "0-$((MAX_BYTES - 1))" \
        --progress-bar \
        --user-agent "maia2-book-builder/2.0" \
        -o "$CHUNK" \
        "$DB_URL"

    SIZE_GB=$(awk "BEGIN{printf \"%.1f\", $(file_size "$CHUNK") / 1024 / 1024 / 1024}")
    echo -e "  ${GREEN}✔${RESET} Downloaded ${SIZE_GB} GB"
fi

# Verify it decompresses
if ! zstdcat "$CHUNK" 2>/dev/null | head -c 500 | grep -q "\[Event"; then
    echo -e "  ${RED}✖${RESET} Download doesn't decompress to valid PGN. Deleting."
    rm -f "$CHUNK"
    exit 1
fi

# ═══════════════════════════════════════════════════════════════════════
#  Step B: Write the Python builder
# ═══════════════════════════════════════════════════════════════════════
cat > "$PYSCRIPT" << 'PYEOF'
"""
Streaming book builder.
Reads PGN from stdin. Keeps stats in memory per rating bucket.
Writes Polyglot books.
"""
import sys
import os
import struct
import time
import signal
from collections import defaultdict

import chess
import chess.pgn
import chess.polyglot

# Config from environment
RATINGS = [int(x) for x in os.environ["RATINGS"].split(",")]
SPEEDS  = set(os.environ["SPEED_FILTER"].split(","))
SPEED_NAME = os.environ["SPEED_NAME"]

RATING_HALF_WIDTH = 100  # each book = target rating ±100
MAX_PLIES         = 30
MIN_FREQ          = 3    # moves appearing less than this many times are dropped

OUTPUT_DIR = os.path.expanduser("~/chess/books")


def buckets_for(avg_elo):
    """Return all target ratings this game falls within (±RATING_HALF_WIDTH)."""
    return [r for r in RATINGS if abs(r - avg_elo) <= RATING_HALF_WIDTH]


# stats[rating][(zobrist_hash, uci)] = [games, wwins, draws, bwins]
stats = {r: defaultdict(lambda: [0, 0, 0, 0]) for r in RATINGS}


def encode_move(uci_str):
    """Encode a UCI move in Polyglot 16-bit format."""
    move = chess.Move.from_uci(uci_str)
    to_f = chess.square_file(move.to_square)
    to_r = chess.square_rank(move.to_square)
    fr_f = chess.square_file(move.from_square)
    fr_r = chess.square_rank(move.from_square)

    if fr_f == 4 and (fr_r == 0 or fr_r == 7) and abs(to_f - fr_f) == 2:
        to_f = 7 if to_f > fr_f else 0

    promo = 0
    if move.promotion:
        promo = {chess.KNIGHT: 1, chess.BISHOP: 2,
                 chess.ROOK: 3, chess.QUEEN: 4}[move.promotion]

    return to_f | (to_r << 3) | (fr_f << 6) | (fr_r << 9) | (promo << 12)


def write_book(rating, stats_dict):
    if not stats_dict:
        print(f"    {rating}: no data — skipping")
        return

    filtered = [(k, v[0]) for k, v in stats_dict.items() if v[0] >= MIN_FREQ]
    if not filtered:
        print(f"    {rating}: no moves met MIN_FREQ={MIN_FREQ}")
        return

    max_count = max(c for _, c in filtered)
    entries = []
    for (key, uci), count in filtered:
        weight = max(1, int(count / max_count * 65535))
        entries.append((key, encode_move(uci), weight))

    entries.sort(key=lambda e: (e[0], -e[2]))

    output = os.path.join(OUTPUT_DIR, f"lichess_{rating}_{SPEED_NAME}.bin")
    with open(output, "wb") as f:
        for k, m, w in entries:
            f.write(struct.pack(">QHHi", k, m, w, 0))

    size_kb = os.path.getsize(output) / 1024
    print(f"    {rating}: {len(entries):>7,} entries, {size_kb:>7,.1f} KB → {output}")


def save_and_exit(signum=None, frame=None):
    print("\n\n[Ctrl-C] Writing books with data collected so far...")
    for rating, data in stats.items():
        write_book(rating, data)
    sys.exit(0)

signal.signal(signal.SIGINT, save_and_exit)

os.makedirs(OUTPUT_DIR, exist_ok=True)

print(f"  Target ratings: {RATINGS}  (±{RATING_HALF_WIDTH})")
print(f"  Max plies:      {MAX_PLIES}   Min frequency: {MIN_FREQ}")
print(f"  Speeds:         {', '.join(sorted(SPEEDS))}")
print(f"  Output dir:     {OUTPUT_DIR}")
print()

start = time.time()
last_print = start
games_scanned = 0
games_matched = 0
bucket_counts = {r: 0 for r in RATINGS}

try:
    while True:
        try:
            game = chess.pgn.read_game(sys.stdin)
        except Exception:
            continue
        if game is None:
            break

        games_scanned += 1

        h = game.headers
        event = h.get("Event", "")

        if "Rated" not in event:
            continue

        ev_lower = event.lower()
        if not any(s in ev_lower for s in SPEEDS):
            continue

        try:
            w = int(h.get("WhiteElo", "0"))
            b = int(h.get("BlackElo", "0"))
        except ValueError:
            continue

        avg = (w + b) // 2
        matching = buckets_for(avg)
        if not matching:
            continue

        result = h.get("Result", "*")

        mainline = list(game.mainline_moves())
        if len(mainline) < 6:
            continue

        games_matched += 1

        # Walk the moves once, record stats for every matching bucket
        board = chess.Board()
        move_hashes = []
        for i, move in enumerate(mainline):
            if i >= MAX_PLIES:
                break
            key = chess.polyglot.zobrist_hash(board)
            move_hashes.append((key, move.uci()))
            board.push(move)

        for rating in matching:
            bucket_counts[rating] += 1
            sd = stats[rating]
            for key, uci in move_hashes:
                s = sd[(key, uci)]
                s[0] += 1
                if result == "1-0":
                    s[1] += 1
                elif result == "1/2-1/2":
                    s[2] += 1
                elif result == "0-1":
                    s[3] += 1

        now = time.time()
        if now - last_print >= 3:
            elapsed = now - start
            rate = games_scanned / elapsed if elapsed > 0 else 0
            match_pct = 100 * games_matched / games_scanned if games_scanned else 0
            bucket_summary = " ".join(
                f"{r}={bucket_counts[r]//1000}k" for r in RATINGS
            )
            print(f"  Scanned: {games_scanned:>10,}  "
                  f"Matched: {games_matched:>9,} ({match_pct:.0f}%)  "
                  f"{rate:>7,.0f}/s  "
                  f"[{bucket_summary}]",
                  flush=True)
            last_print = now

except (BrokenPipeError, IOError):
    print("\n[Stream ended]")

# Write books
print()
print(f"─── Final stats ───")
print(f"  Scanned: {games_scanned:,} games")
print(f"  Matched: {games_matched:,} games")
for r in RATINGS:
    print(f"    {r}: {bucket_counts[r]:,} games → {len(stats[r]):,} unique (pos, move)")

print()
print(f"─── Writing books ───")
for rating, data in stats.items():
    write_book(rating, data)

print()
print(f"Total time: {(time.time() - start) / 60:.1f} min")
PYEOF

# ═══════════════════════════════════════════════════════════════════════
#  Step C: Stream download through builder
# ═══════════════════════════════════════════════════════════════════════
echo ""
echo -e "${BOLD}[2/3] Streaming PGN → Python builder${RESET}"
echo -e "${DIM}  No database, no intermediate files. All in-memory.${RESET}"
echo ""

export RATINGS SPEED_FILTER SPEED_NAME

set +e
zstdcat "$CHUNK" 2>/dev/null | $PYTHON_CMD -u "$PYSCRIPT"
BUILD_RESULT=$?
set -e

# ═══════════════════════════════════════════════════════════════════════
#  Step D: Cleanup
# ═══════════════════════════════════════════════════════════════════════
echo ""
echo -e "${BOLD}[3/3] Cleanup${RESET}"

rm -f "$PYSCRIPT"

if [[ $BUILD_RESULT -eq 0 ]]; then
    rm -f "$CHUNK"
    rmdir "$TMP_DIR" 2>/dev/null || true
    echo -e "  ${GREEN}✔${RESET} Temp files removed"
else
    echo -e "  ${YELLOW}⚠${RESET} Build failed (exit $BUILD_RESULT)"
    echo -e "     Download kept at: $CHUNK"
    echo -e "     Re-run to retry without re-downloading."
fi

if [[ "$PYTHON_CMD" == "python3" ]] && command -v deactivate &>/dev/null; then
    deactivate 2>/dev/null || true
fi

echo ""
if [[ $BUILD_RESULT -eq 0 ]]; then
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo -e "${BOLD}${GREEN}  ✔  Books built!${RESET}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo ""
    ls -lh "$BOOKS_DIR"/*.bin 2>/dev/null || true
    echo ""
    echo -e "  Set ${BOLD}BookFile${RESET} in En Croissant to whichever matches your target rating."
    echo ""
fi

exit $BUILD_RESULT
