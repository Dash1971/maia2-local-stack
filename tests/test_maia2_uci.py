from __future__ import annotations

from unittest.mock import patch

import maia2_uci


def run_commands(*commands: str) -> None:
    with patch("builtins.input", side_effect=[*commands, "quit"]):
        maia2_uci.uci_loop()


def test_elo_sets_both_ratings() -> None:
    run_commands("setoption name ELO value 1400")
    assert maia2_uci.elo_self == 1400
    assert maia2_uci.elo_oppo == 1400


def test_specific_ratings_override_general_rating() -> None:
    run_commands(
        "setoption name ELO value 1500",
        "setoption name SelfElo value 1100",
        "setoption name OppoElo value 1900",
    )
    assert maia2_uci.elo_self == 1100
    assert maia2_uci.elo_oppo == 1900


def test_uci_advertises_specific_rating_options(capsys) -> None:
    run_commands("uci")
    output = capsys.readouterr().out
    assert "option name SelfElo" in output
    assert "option name OppoElo" in output
