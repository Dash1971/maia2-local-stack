#!/usr/bin/env bash
# ╔══════════════════════════════════════════════════════════════════════╗
# ║  setup-maia2.sh — One-shot installer (Linux + macOS)                 ║
# ║                                                                    ║
# ║  Installs:                                                         ║
# ║    • Maia 2 (human-like neural network chess engine)               ║
# ║    • UCI wrapper with opening book + HumanTime support             ║
# ║    • Stockfish (for post-game analysis)                            ║
# ║    • En Croissant (chess GUI) — installed on Linux,                ║
# ║                                  manual download on macOS           ║
# ║                                                                    ║
# ║  Usage:  chmod +x setup-maia2.sh && ./setup-maia2.sh               ║
# ║  Safe to re-run — skips what's already done.                       ║
# ║                                                                    ║
# ║  Linux: Tested on Pop!_OS 24.04 / Ubuntu 24.04                     ║
# ║  macOS: Tested on M4 MacBook Air / macOS Sequoia                   ║
# ╚══════════════════════════════════════════════════════════════════════╝

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; DIM='\033[2m'; RESET='\033[0m'

# ─── Detect OS ─────────────────────────────────────────────────────────
OS="$(uname -s)"
if [[ "$OS" == "Darwin" ]]; then
    PLATFORM="macos"
    PLATFORM_NAME="macOS"
    DEVICE="mps"    # Apple Silicon GPU
elif [[ "$OS" == "Linux" ]]; then
    PLATFORM="linux"
    PLATFORM_NAME="Linux"
    DEVICE="cpu"
else
    echo "Unsupported OS: $OS (only Linux and macOS are supported)"
    exit 1
fi

CHESS_DIR="$HOME/chess"
ENGINE_DIR="$CHESS_DIR/maia2-engine"
BOOKS_DIR="$CHESS_DIR/books"
VENV_DIR="$ENGINE_DIR/venv"
UCI_SCRIPT="$ENGINE_DIR/maia2_uci.py"
LAUNCHER="$ENGINE_DIR/maia2-engine.sh"
EC_VERSION="0.15.0"

step_num=0
total_steps=6

step() {
    step_num=$((step_num + 1))
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo -e "${BOLD}${CYAN}  [$step_num/$total_steps]  $1${RESET}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo ""
}

ok()   { echo -e "  ${GREEN}✔${RESET}  $1"; }
skip() { echo -e "  ${YELLOW}⏭${RESET}  $1 ${DIM}(already done)${RESET}"; }
info() { echo -e "  ${CYAN}ℹ${RESET}  $1"; }
warn() { echo -e "  ${YELLOW}⚠${RESET}  $1"; }
fail() { echo -e "  ${RED}✖${RESET}  $1"; exit 1; }

echo ""
echo -e "${BOLD}${CYAN}  ♟  Maia 2 Local Chess — Setup (${PLATFORM_NAME})${RESET}"
echo -e "${DIM}  Human-like AI  •  Opening book support  •  HumanTime thinking  •  En Croissant GUI${RESET}"
echo ""

# ════════════════════════════════════════════════════════════════════════
#  STEP 1: System dependencies
# ════════════════════════════════════════════════════════════════════════
step "Installing system dependencies"

if [[ "$PLATFORM" == "linux" ]]; then
    sudo apt update -qq
    sudo apt install -y -qq \
        python3 python3-pip python3-venv \
        git curl wget stockfish zstd sqlite3 \
        libwebkit2gtk-4.1-0 gstreamer1.0-plugins-good 2>/dev/null

    PY_CMD="python3"
    SF_PATH=$(which stockfish 2>/dev/null || echo "/usr/games/stockfish")

    ok "System packages installed"
    ok "Stockfish: $SF_PATH"

elif [[ "$PLATFORM" == "macos" ]]; then
    # Check for Homebrew
    if ! command -v brew &>/dev/null; then
        echo -e "  ${RED}✖${RESET}  Homebrew is required on macOS but not installed."
        echo ""
        echo "  Install it with:"
        echo -e "    ${CYAN}/bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\"${RESET}"
        echo ""
        echo "  Then re-run this script."
        exit 1
    fi

    info "Installing packages with Homebrew..."
    brew install python@3.12 stockfish zstd

    PY_CMD="python3.12"
    if ! command -v $PY_CMD &>/dev/null; then
        PY_CMD="python3"
    fi

    # En Croissant needs Stockfish at a non-sandboxed path
    # (built-in Stockfish downloader on Apple Silicon downloads wrong arch)
    if command -v stockfish &>/dev/null; then
        if [[ ! -f "$CHESS_DIR/stockfish" ]]; then
            mkdir -p "$CHESS_DIR"
            cp "$(which stockfish)" "$CHESS_DIR/stockfish"
            chmod +x "$CHESS_DIR/stockfish"
        fi
        SF_PATH="$CHESS_DIR/stockfish"
    else
        SF_PATH="(not installed)"
    fi

    ok "Homebrew packages installed"
    ok "Stockfish: $SF_PATH"
fi

PY_VERSION=$($PY_CMD --version)
ok "$PY_VERSION"

# ════════════════════════════════════════════════════════════════════════
#  STEP 2: Directory structure
# ════════════════════════════════════════════════════════════════════════
step "Creating directory structure"

mkdir -p "$ENGINE_DIR" "$BOOKS_DIR"
ok "~/chess/maia2-engine/"
ok "~/chess/books/"

# ════════════════════════════════════════════════════════════════════════
#  STEP 3: Python venv + Maia 2
# ════════════════════════════════════════════════════════════════════════
step "Setting up Python environment & installing Maia 2"

if [[ ! -d "$VENV_DIR" ]]; then
    $PY_CMD -m venv "$VENV_DIR"
    ok "Virtual environment created"
else
    skip "Virtual environment exists"
fi

source "$VENV_DIR/bin/activate"

if python3 -c "from maia2 import model" &>/dev/null; then
    skip "maia2 already installed and working"
else
    info "Upgrading pip..."
    pip install --upgrade pip -q

    if [[ "$PLATFORM" == "linux" ]]; then
        info "Installing PyTorch CPU build (~800 MB download)..."
        pip install torch --index-url https://download.pytorch.org/whl/cpu 2>&1 | \
            grep -E "(Downloading|Successfully)" | head -3
    else
        # macOS: standard install includes MPS support for Apple Silicon
        info "Installing PyTorch with MPS support..."
        pip install torch 2>&1 | \
            grep -E "(Downloading|Successfully)" | head -3
    fi

    if ! python3 -c "import torch" &>/dev/null; then
        echo -e "  ${RED}✖${RESET}  PyTorch install failed. Error:"
        python3 -c "import torch" 2>&1 | head -10
        deactivate
        exit 1
    fi
    ok "PyTorch installed"

    if [[ "$PLATFORM" == "macos" ]]; then
        if python3 -c "import torch; exit(0 if torch.backends.mps.is_available() else 1)" 2>/dev/null; then
            ok "MPS (Apple Silicon GPU) available"
        else
            warn "MPS not available — will fall back to CPU"
        fi
    fi

    # maia2's package doesn't declare most of its real dependencies.
    # Install them explicitly before installing maia2 itself.
    info "Installing maia2 + dependencies..."
    pip install pyyaml gdown chess einops pyzstd requests pandas numpy tqdm -q
    pip install maia2 -q
    ok "All packages installed"

    if python3 -c "from maia2 import model, inference" &>/dev/null; then
        ok "maia2 import verified"
    else
        echo -e "  ${RED}✖${RESET}  maia2 import failed. Error:"
        python3 -c "from maia2 import model" 2>&1 | head -20
        deactivate
        exit 1
    fi
fi

deactivate

# ════════════════════════════════════════════════════════════════════════
#  STEP 4: UCI wrapper + launcher
# ════════════════════════════════════════════════════════════════════════
step "Creating Maia 2 UCI engine wrapper"

# Note: this overwrites maia2_uci.py on every run. If you've customized
# the HumanTime parameters, back up your copy before re-running setup.
# The DEVICE placeholder below gets replaced with cpu (Linux) or mps (macOS).

cat > "$UCI_SCRIPT" << PYTHON_EOF
#!/usr/bin/env python3
"""
maia2_uci.py — UCI wrapper for Maia 2 with:
  - Polyglot opening book support (BookFile option)
  - Human-like thinking time (HumanTime option)
  - Analysis mode support (proper go infinite / stop handling)
"""
import sys, os, random, time, chess, chess.polyglot

maia2_model = None
maia2_prepared = None

DEFAULT_ELO = 1500
BOOK_FILE = ""
HUMAN_TIME = False
elo_self = DEFAULT_ELO
elo_oppo = DEFAULT_ELO
board = chess.Board()

_analyzing = False
_pending_bestmove = None


def load_model():
    global maia2_model, maia2_prepared
    if maia2_model is None:
        from maia2 import model, inference
        maia2_model = model.from_pretrained(type="rapid", device="${DEVICE}")
        maia2_prepared = inference.prepare()


def get_book_move(b, book_path):
    if not book_path or not os.path.isfile(book_path):
        return None
    try:
        with chess.polyglot.open_reader(book_path) as reader:
            entries = list(reader.find_all(b))
            if not entries:
                return None
            total = sum(e.weight for e in entries)
            if total == 0:
                return random.choice(entries).move
            r = random.randint(0, total - 1)
            cumulative = 0
            for entry in entries:
                cumulative += entry.weight
                if r < cumulative:
                    return entry.move
            return entries[0].move
    except Exception:
        return None


def get_maia_move(b):
    load_model()
    from maia2 import inference
    move_probs, win_prob = inference.inference_each(
        maia2_model, maia2_prepared, b.fen(), elo_self, elo_oppo
    )
    if not move_probs:
        return random.choice(list(b.legal_moves)).uci(), 0
    best = max(move_probs, key=move_probs.get)
    cp = 0
    return best, cp


def calculate_think_time(b, is_book_move, chosen_move):
    if is_book_move:
        return random.uniform(0.5, 2.0)
    num_legal = len(list(b.legal_moves))
    base = 2.0 + min(num_legal / 10.0, 4.0)
    try:
        move_obj = chess.Move.from_uci(chosen_move) if isinstance(chosen_move, str) else chosen_move
        if b.is_capture(move_obj):
            base += 1.5
        if b.gives_check(move_obj):
            base += 1.5
        if move_obj.promotion:
            base += 2.0
    except Exception:
        pass
    piece_count = len(b.piece_map())
    if piece_count >= 28:
        base *= 0.7
    elif piece_count <= 12:
        base *= 1.2
    return max(0.5, min(base * random.uniform(0.7, 1.3), 15.0))


def compute_move():
    bm = get_book_move(board, BOOK_FILE)
    if bm and bm in board.legal_moves:
        return bm.uci(), 0, True
    uci, cp = get_maia_move(board)
    return uci, cp, False


def uci_loop():
    global board, elo_self, elo_oppo, BOOK_FILE, HUMAN_TIME
    global _analyzing, _pending_bestmove

    while True:
        try:
            line = input().strip()
        except EOFError:
            break
        if not line:
            continue

        parts = line.split()
        cmd = parts[0]

        if cmd == "uci":
            print("id name Maia 2 (local)")
            print("id author Maia + Dash1971")
            print("option name ELO type spin default 1500 min 600 max 2600")
            print("option name BookFile type string default")
            print("option name HumanTime type check default false")
            print("uciok")
            sys.stdout.flush()

        elif cmd == "setoption":
            if len(parts) >= 5 and parts[1] == "name":
                name = parts[2]
                value = " ".join(parts[4:])
                if name == "ELO":
                    try:
                        elo_self = int(value); elo_oppo = int(value)
                    except ValueError:
                        pass
                elif name == "BookFile":
                    BOOK_FILE = value
                elif name == "HumanTime":
                    HUMAN_TIME = value.lower() == "true"

        elif cmd == "isready":
            print("readyok")
            sys.stdout.flush()

        elif cmd == "ucinewgame":
            board = chess.Board()
            _analyzing = False
            _pending_bestmove = None

        elif cmd == "position":
            _analyzing = False
            _pending_bestmove = None
            if "startpos" in line:
                board = chess.Board()
                if "moves" in line:
                    idx = line.index("moves") + len("moves")
                    moves_part = line[idx:].strip().split()
                    for m in moves_part:
                        try:
                            board.push_uci(m)
                        except Exception:
                            break
            elif "fen" in line:
                try:
                    idx = line.index("fen") + len("fen")
                    fen_and_more = line[idx:].strip()
                    if " moves " in fen_and_more:
                        fen, _, moves_str = fen_and_more.partition(" moves ")
                        board = chess.Board(fen.strip())
                        for m in moves_str.strip().split():
                            try:
                                board.push_uci(m)
                            except Exception:
                                break
                    else:
                        board = chess.Board(fen_and_more.strip())
                except Exception:
                    board = chess.Board()

        elif cmd == "go":
            is_infinite = "infinite" in parts
            chosen_uci, cp, is_book = compute_move()

            if is_infinite:
                _analyzing = True
                _pending_bestmove = chosen_uci
                print(f"info depth 1 seldepth 1 score cp {cp} pv {chosen_uci}")
                sys.stdout.flush()
            else:
                if HUMAN_TIME:
                    delay = calculate_think_time(board, is_book, chosen_uci)
                    time.sleep(delay)
                print(f"info depth 1 seldepth 1 score cp {cp} pv {chosen_uci}")
                print(f"bestmove {chosen_uci}")
                sys.stdout.flush()

        elif cmd == "stop":
            if _analyzing and _pending_bestmove:
                print(f"bestmove {_pending_bestmove}")
                sys.stdout.flush()
            _analyzing = False
            _pending_bestmove = None

        elif cmd == "quit":
            break


if __name__ == "__main__":
    uci_loop()
PYTHON_EOF

chmod +x "$UCI_SCRIPT"
ok "maia2_uci.py (device=${DEVICE})"

cat > "$LAUNCHER" << LAUNCHER_EOF
#!/bin/bash
DIR="\$(cd "\$(dirname "\$0")" && pwd)"
source "\$DIR/venv/bin/activate"
exec python3 "\$DIR/maia2_uci.py" "\$@"
LAUNCHER_EOF
chmod +x "$LAUNCHER"
ok "maia2-engine.sh"

# ════════════════════════════════════════════════════════════════════════
#  STEP 5: En Croissant
# ════════════════════════════════════════════════════════════════════════
step "Installing En Croissant"

if [[ "$PLATFORM" == "linux" ]]; then
    if command -v en-croissant &>/dev/null || dpkg -s en-croissant &>/dev/null 2>&1; then
        skip "En Croissant already installed"
    else
        DEB="/tmp/en-croissant_${EC_VERSION}_amd64.deb"
        info "Downloading En Croissant v${EC_VERSION}..."
        wget -q --show-progress -O "$DEB" \
            "https://github.com/franciscoBSalgueiro/en-croissant/releases/download/v${EC_VERSION}/en-croissant_${EC_VERSION}_amd64.deb"
        info "Installing..."
        sudo apt install -y "$DEB" 2>&1 | tail -3
        rm -f "$DEB"
        ok "En Croissant installed"
    fi

elif [[ "$PLATFORM" == "macos" ]]; then
    if [[ -d "/Applications/En Croissant.app" ]]; then
        skip "En Croissant already installed"
    else
        info "En Croissant cannot be auto-installed on macOS (requires manual .dmg install)"
        echo ""
        echo -e "  ${BOLD}Please do this manually:${RESET}"
        echo ""
        echo "  1. Download the Apple Silicon .dmg from:"
        echo -e "     ${CYAN}https://github.com/franciscoBSalgueiro/en-croissant/releases/download/v${EC_VERSION}/en-croissant_${EC_VERSION}_aarch64.dmg${RESET}"
        echo ""
        echo "  2. Open the .dmg and drag En Croissant to Applications"
        echo ""
        echo "  3. First launch: macOS will block the app. Go to:"
        echo "     System Settings → Privacy & Security → click 'Open Anyway'"
        echo ""
    fi
fi

# ════════════════════════════════════════════════════════════════════════
#  STEP 6: Smoke test
# ════════════════════════════════════════════════════════════════════════
step "Smoke test"

info "Testing engine (first run loads the model — may take 20-30s)..."

TIMEOUT_CMD=()
if command -v timeout &>/dev/null; then
    TIMEOUT_CMD=(timeout 120)
elif command -v gtimeout &>/dev/null; then
    TIMEOUT_CMD=(gtimeout 120)
fi

TEST=$(echo -e "uci\nisready\nposition startpos\ngo\nquit" \
    | "${TIMEOUT_CMD[@]}" "$LAUNCHER" 2>/dev/null || true)

if echo "$TEST" | grep -q "bestmove"; then
    ok "Engine works: $(echo "$TEST" | grep bestmove | tail -1)"
else
    warn "Engine didn't respond in time. Sometimes happens on first run."
    warn "Try manually: echo -e 'uci\\nisready\\nposition startpos\\ngo\\nquit' | $LAUNCHER"
fi

if echo "$TEST" | grep -q "HumanTime"; then
    ok "HumanTime option is exposed"
fi

# ════════════════════════════════════════════════════════════════════════
#  Done
# ════════════════════════════════════════════════════════════════════════
echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo -e "${BOLD}${GREEN}  ✔  Setup complete${RESET}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo ""
echo -e "  ${BOLD}Configure En Croissant:${RESET}"
echo ""
echo -e "  ${YELLOW}MAIA 2 engine:${RESET}"
echo -e "    Engines → Add New → Local → Binary file"
echo -e "    Path:      ${CYAN}$LAUNCHER${RESET}"
echo -e "    Depth:     ${BOLD}1${RESET}  (critical — Maia 2 does no search)"
echo -e "    ELO:       your target strength (600–2600)"
echo -e "    BookFile:  path to your .bin book (optional but recommended)"
echo -e "    HumanTime: ${BOLD}true${RESET}  (for human-like thinking delays)"
echo ""
echo -e "  ${YELLOW}STOCKFISH (for analysis):${RESET}"
echo -e "    Path:      ${CYAN}$SF_PATH${RESET}"
if [[ "$PLATFORM" == "macos" ]]; then
    echo -e "    ${DIM}(Copied from brew to ~/chess/ because En Croissant can't${RESET}"
    echo -e "    ${DIM} run binaries from /opt/homebrew/ on Apple Silicon.)${RESET}"
fi
echo ""
echo -e "  ${BOLD}Next steps:${RESET}"
echo -e "    • Build opening books from real Lichess games (interactive):"
echo -e "      ${CYAN}./build-books.sh${RESET}"
echo -e ""
if [[ "$PLATFORM" == "linux" ]]; then
    echo -e "    See ${BOLD}GUIDE.md${RESET} for the full walkthrough."
else
    echo -e "    See ${BOLD}GUIDE-macOS.md${RESET} for the full walkthrough."
fi
echo ""
