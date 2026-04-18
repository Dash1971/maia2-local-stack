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

# State for analysis mode
_analyzing = False
_pending_bestmove = None


def load_model():
    global maia2_model, maia2_prepared
    if maia2_model is None:
        from maia2 import model, inference
        maia2_model = model.from_pretrained(type="rapid", device="cpu")
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
    # Maia's win_prob is a statistical prediction, not a tactical evaluation.
    # It's unreliable for specific positions (e.g. shows losing when mate is on
    # the board). We report cp 0 and let Stockfish handle real evaluation.
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
    """Compute the best move for the current board. Returns (uci_str, cp, is_book)."""
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
        tokens = line.split()
        cmd = tokens[0]

        if cmd == "uci":
            print("id name Maia 2 UCI")
            print("id author CSSLab, University of Toronto")
            print(f"option name ELO type spin default {DEFAULT_ELO} min 600 max 2600")
            print("option name BookFile type string default ")
            print("option name HumanTime type check default false")
            print("uciok")
            sys.stdout.flush()

        elif cmd == "setoption" and "name" in tokens and "value" in tokens:
            ni = tokens.index("name") + 1
            vi = tokens.index("value") + 1
            name = " ".join(tokens[ni:vi-1]).upper()
            value = " ".join(tokens[vi:])
            if name == "ELO":
                try:
                    elo_self = elo_oppo = int(value)
                except ValueError:
                    pass
            elif name == "BOOKFILE":
                BOOK_FILE = value
            elif name == "HUMANTIME":
                HUMAN_TIME = value.strip().lower() in ("true", "1", "yes", "on")

        elif cmd == "isready":
            print("readyok")
            sys.stdout.flush()

        elif cmd == "ucinewgame":
            board = chess.Board()
            _analyzing = False
            _pending_bestmove = None

        elif cmd == "position":
            if tokens[1] == "startpos":
                board = chess.Board()
                if "moves" in tokens:
                    for m in tokens[tokens.index("moves")+1:]:
                        try:
                            board.push_uci(m)
                        except Exception:
                            break
            elif tokens[1] == "fen":
                if "moves" in tokens:
                    mi = tokens.index("moves")
                    board = chess.Board(" ".join(tokens[2:mi]))
                    for m in tokens[mi+1:]:
                        try:
                            board.push_uci(m)
                        except Exception:
                            break
                else:
                    board = chess.Board(" ".join(tokens[2:]))

        elif cmd == "go":
            chosen_uci, cp, is_book = compute_move()

            if "infinite" in tokens:
                # Analysis mode: send info with pv, hold bestmove for stop
                print(f"info depth 1 seldepth 1 score cp {cp} pv {chosen_uci}")
                if is_book:
                    print("info string book move")
                sys.stdout.flush()
                _analyzing = True
                _pending_bestmove = chosen_uci
            else:
                # Game mode: optional delay, then full response
                if HUMAN_TIME:
                    move_obj = chess.Move.from_uci(chosen_uci)
                    think_sec = calculate_think_time(board, is_book, move_obj)
                    print(f"info string thinking for {think_sec:.1f}s")
                    sys.stdout.flush()
                    time.sleep(think_sec)

                print(f"info depth 1 seldepth 1 score cp {cp} pv {chosen_uci}")
                if is_book:
                    print("info string book move")
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
