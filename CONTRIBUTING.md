# Contributing

## Scope

This repository packages Maia 2 for local use with En Croissant and other UCI-compatible GUIs. Contributions should keep the project reliable, minimal, and easy to follow for end users.

## Priorities

1. Keep documentation aligned with actual script behavior.
2. Keep Linux and Apple Silicon macOS paths explicit.
3. Prefer small, reviewable changes.
4. Avoid unnecessary abstraction or marketing language.

## Before opening a change

Check the affected files first:

- `README.md`
- `setup-maia2.sh`
- `build-books.sh`
- `maia2_uci.py`
- `GUIDE.md`
- `GUIDE-macOS.md`

If the change touches installation, wrapper behavior, or user-facing instructions, review both the docs and scripts together.

## Verification

At minimum, run:

```bash
bash -n setup-maia2.sh
bash -n build-books.sh
python3 -m py_compile maia2_uci.py
```

If you changed docs, confirm the claims still match the code.

## Important maintenance note

`setup-maia2.sh` embeds the wrapper it installs into `~/chess/maia2-engine/maia2_uci.py`. That means the repository copy of `maia2_uci.py` can drift from the installer-generated copy if changes are applied in only one place.

If you change wrapper behavior, review both locations before merging.

## Style

- Keep README and guides factual.
- Prefer direct instructions over persuasive copy.
- Avoid vague claims unless clearly marked as heuristics.
- Keep command examples copy-pasteable.
- Use absolute paths in En Croissant examples where required.

## Files not to commit

Do not commit:

- `.DS_Store`
- `__MACOSX/`
- `__pycache__/`
- generated book files (`*.bin`)
- local virtual environments
- temporary downloads or test artifacts

## Pull requests / patches

Good changes usually do one of these:

- fix installation drift
- correct documentation
- improve cross-platform reliability
- clarify En Croissant configuration
- tighten verification or troubleshooting

If a path is unverified, say so directly in the PR or commit message.
