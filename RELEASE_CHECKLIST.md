# Release Checklist

Use this checklist before tagging a release or publishing the repo more broadly.

## 1. Repository consistency

- [ ] Repo name is correct everywhere: `maia2-local-stack`
- [ ] Clone URLs are correct in `README.md`, `GUIDE.md`, and `GUIDE-macOS.md`
- [ ] Screenshot paths and image references resolve correctly
- [ ] `.gitignore` excludes local junk such as `.DS_Store` and `__MACOSX/`

## 2. Script verification

Run from the repo root:

```bash
bash -n setup-maia2.sh
bash -n build-books.sh
python3 -m py_compile maia2_uci.py
```

- [ ] Shell scripts pass syntax check
- [ ] `maia2_uci.py` compiles cleanly

## 3. Cross-platform review

### Linux
- [ ] `GUIDE.md` matches current `setup-maia2.sh` behavior
- [ ] Linux package names and paths still look valid (`apt`, `/usr/games/stockfish`)
- [ ] En Croissant `.deb` version/url is current

### macOS
- [ ] `GUIDE-macOS.md` matches current `setup-maia2.sh` behavior
- [ ] Homebrew package names still resolve
- [ ] macOS smoke test still works without GNU-only assumptions
- [ ] En Croissant Apple Silicon `.dmg` url is current

## 4. Wrapper consistency

- [ ] Review both `maia2_uci.py` and the embedded wrapper inside `setup-maia2.sh`
- [ ] Confirm UCI options still match: `ELO`, `BookFile`, `HumanTime`
- [ ] Confirm changes to wrapper behavior were applied in both places, or explicitly document why not

## 5. Documentation accuracy

- [ ] Rating-bucket description matches actual builder logic (average rating ±100)
- [ ] Calibration language stays heuristic, not overstated
- [ ] README tone is factual and businesslike
- [ ] Any new flags, paths, or limitations are documented

## 6. Manual spot checks

Recommended if release risk is non-trivial:

- [ ] Fresh Linux run on Pop!_OS/Ubuntu 24.04
- [ ] Fresh Apple Silicon macOS run
- [ ] Engine launches in En Croissant
- [ ] Book builder completes a small run
- [ ] Analysis mode returns a legal move and `bestmove`

## 7. Release notes

- [ ] Summarize user-visible changes
- [ ] List known limitations honestly
- [ ] Mention any unverified platform paths
