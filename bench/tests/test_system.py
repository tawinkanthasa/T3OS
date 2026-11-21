import pytest

from bench import system as SY


def test_split_terse_handles_escaped_colons():
    assert SY._split_terse(r"*:My\:Net:80:WPA2") == ["*", "My:Net", "80", "WPA2"]
    assert SY._split_terse(r" :a\\b:1:") == [" ", "a\\b", "1", ""]


@pytest.mark.parametrize("bad", ["", "x" * 33, None])
def test_ssid_validation(bad):
    with pytest.raises(SY.SysError):
        SY._ssid(bad)


@pytest.mark.parametrize("bad", ["", "x; rm -rf /", "AA:BB:CC:DD:EE", "--help"])
def test_bt_address_validation(bad):
    with pytest.raises(SY.SysError):
        SY._mac(bad)
    with pytest.raises(SY.SysError):
        SY.bt_action("pair", bad)


def test_bt_unknown_action():
    with pytest.raises(SY.SysError):
        SY.bt_action("rm", "AA:BB:CC:DD:EE:FF")


def test_keyboard_rejects_unknown_choice():
    with pytest.raises(SY.SysError):
        SY.keyboard_set("grp:evil")


def test_short_wifi_password_rejected():
    with pytest.raises(SY.SysError):
        SY.wifi_connect("Home", "short")


def test_kcm_open_rejects_unknown_module():
    with pytest.raises(SY.SysError):
        SY.kcm_open("kcm_bogus; rm -rf /")
