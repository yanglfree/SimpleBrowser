from dolphin_harness.device import is_device_locked


def test_screenlock_dump_reports_locked_device() -> None:
    output = (
        "* screenState          true\n* deviceLocked         true\n* screenLocked         true\n"
    )

    assert is_device_locked(output)


def test_screenlock_dump_reports_unlocked_device() -> None:
    output = (
        "* screenState          true\n* deviceLocked         false\n* screenLocked         false\n"
    )

    assert not is_device_locked(output)
