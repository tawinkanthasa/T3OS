import os
from pathlib import Path

import pytest


@pytest.fixture(autouse=True)
def env(tmp_path, monkeypatch):
    monkeypatch.setenv("BENCH_HOME", str(tmp_path))
    monkeypatch.setenv("BENCH_SIM", "1")


def test_sim_boards_detected():
    from bench import boards
    bs = [b for b in boards.list_boards() if b.simulated]
    assert {b.family for b in bs} == {"esp32", "rp2040"}
    assert boards.find("SIM0").family == "esp32"


def test_find_by_family_and_missing():
    from bench import boards
    assert boards.find("rp2040").port == "SIM1"
    with pytest.raises(LookupError):
        boards.find("nope")


def test_serial_sim_flags_brownout():
    from bench import boards, logbook, serialmon
    out = serialmon.read(boards.find("SIM0"), seconds=5, max_lines=30)
    assert any("Brownout" in l for l in out)
    assert logbook.tail(kind="alert")


def test_flash_plan_addresses():
    from bench import boards, flash
    b = boards.find("SIM0")
    assert flash.plan(b, Path("firmware.bin"))["addr"] == "0x10000"
    assert flash.plan(b, Path("app-merged.bin"))["addr"] == "0x0"
    with pytest.raises(flash.FlashError):
        flash.plan(boards.find("SIM1"), Path("x.bin"))


def test_flash_sim_logs():
    from bench import boards, flash, logbook
    flash.flash(boards.find("SIM0"), Path("firmware.bin"), log=lambda _: None)
    assert logbook.tail(kind="flash")[-1]["board"] == "SIM0"


def test_mcp_flash_requires_confirm():
    from bench import mcp_server
    r = mcp_server.flash("firmware.bin", "SIM0")
    assert "refused" in r


def test_cli_runs(capsys):
    from bench import cli
    assert cli.main(["boards"]) == 0
    assert "SIM0" in capsys.readouterr().out
    assert cli.main(["pins", "esp32"]) == 0
    assert cli.main(["flash", "firmware.bin", "SIM0", "-y"]) == 0
    assert cli.main(["log"]) == 0
