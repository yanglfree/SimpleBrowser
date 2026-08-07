import re
import shutil
import subprocess
from dataclasses import dataclass
from pathlib import Path
from typing import Final, override
from uuid import uuid4

from pydantic import ValidationError

from dolphin_harness.errors import HarnessError
from dolphin_harness.models import UiNode

COMMAND_TIMEOUT_SECONDS: Final = 30
DEVICE_LOCKED_PATTERN: Final = re.compile(r"^\s*\*\s+deviceLocked\s+true\b", re.MULTILINE)


@dataclass(frozen=True, slots=True)
class DeviceCommandError(HarnessError):
    command: tuple[str, ...]
    return_code: int
    output: str

    @override
    def __str__(self) -> str:
        rendered = " ".join(self.command)
        return f"device command failed ({self.return_code}): {rendered}\n{self.output.strip()}"


@dataclass(frozen=True, slots=True)
class DeviceSelectionError(HarnessError):
    requested: str | None
    available: tuple[str, ...]

    @override
    def __str__(self) -> str:
        if self.requested is not None:
            return f"device {self.requested!r} is unavailable; connected={list(self.available)!r}"
        return f"expected exactly one connected device; connected={list(self.available)!r}"


@dataclass(frozen=True, slots=True)
class InvalidLayoutError(HarnessError):
    path: Path
    detail: str

    @override
    def __str__(self) -> str:
        return f"invalid layout document at {self.path}: {self.detail}"


@dataclass(frozen=True, slots=True)
class DeviceLockedError(HarnessError):
    serial: str

    @override
    def __str__(self) -> str:
        return f"device {self.serial} is locked; unlock it and keep the screen on"


class HdcDevice:
    _hdc: Path
    serial: str

    def __init__(self, hdc: Path, serial: str) -> None:
        self._hdc = hdc
        self.serial = serial

    def install(self, hap: Path) -> None:
        _ = self._command("install", "-r", str(hap.resolve()))

    def prepare(self) -> None:
        _ = self._shell("power-shell", "wakeup")
        lock_state = self._shell("hidumper", "-s", "ScreenlockService", "-a", "-all")
        if is_device_locked(lock_state):
            raise DeviceLockedError(serial=self.serial)

    def reset(self, bundle: str) -> None:
        _ = self._shell("bm", "clean", "-n", bundle, "-d")

    def launch(self, bundle: str, ability: str) -> None:
        _ = self._shell("aa", "force-stop", bundle)
        _ = self._shell("aa", "start", "-a", ability, "-b", bundle)

    def dump_layout(self, bundle: str, destination: Path) -> UiNode:
        remote = self._remote_path("json")
        destination.parent.mkdir(parents=True, exist_ok=True)
        try:
            _ = self._shell("uitest", "dumpLayout", "-b", bundle, "-p", remote)
            _ = self._command("file", "recv", remote, str(destination.resolve()))
        finally:
            _ = self._shell("rm", "-f", remote)
        try:
            return UiNode.model_validate_json(destination.read_text(encoding="utf-8"))
        except (OSError, ValidationError) as error:
            raise InvalidLayoutError(path=destination, detail=str(error)) from error

    def screenshot(self, destination: Path) -> None:
        remote = self._remote_path("png")
        destination.parent.mkdir(parents=True, exist_ok=True)
        try:
            _ = self._shell("uitest", "screenCap", "-p", remote)
            _ = self._command("file", "recv", remote, str(destination.resolve()))
        finally:
            _ = self._shell("rm", "-f", remote)

    def tap(self, x: int, y: int) -> None:
        _ = self._shell("uitest", "uiInput", "click", str(x), str(y))

    def long_press(self, x: int, y: int) -> None:
        _ = self._shell("uitest", "uiInput", "longClick", str(x), str(y))

    def input_text(self, x: int, y: int, text: str) -> None:
        _ = self._shell("uitest", "uiInput", "inputText", str(x), str(y), text)

    def swipe(self, from_x: int, from_y: int, to_x: int, to_y: int, velocity: int) -> None:
        _ = self._shell(
            "uitest",
            "uiInput",
            "swipe",
            str(from_x),
            str(from_y),
            str(to_x),
            str(to_y),
            str(velocity),
        )

    def key(self, key: str) -> None:
        _ = self._shell("uitest", "uiInput", "keyEvent", key)

    def _shell(self, *arguments: str) -> str:
        return self._command("shell", *arguments)

    def _command(self, *arguments: str) -> str:
        command = (str(self._hdc), "-t", self.serial, *arguments)
        completed = subprocess.run(
            command,
            capture_output=True,
            text=True,
            timeout=COMMAND_TIMEOUT_SECONDS,
            check=False,
        )
        output = completed.stdout + completed.stderr
        normalized = output.casefold()
        failed_output = "error:" in normalized or "failed to" in normalized
        if completed.returncode != 0 or failed_output:
            raise DeviceCommandError(
                command=command, return_code=completed.returncode, output=output
            )
        return output

    @staticmethod
    def _remote_path(extension: str) -> str:
        return f"/data/local/tmp/dolphin_harness_{uuid4().hex}.{extension}"


def find_hdc(explicit: Path | None = None) -> Path:
    if explicit is not None and explicit.is_file():
        return explicit
    discovered = shutil.which("hdc")
    if discovered is None:
        raise DeviceSelectionError(requested="hdc executable", available=())
    return Path(discovered)


def connected_devices(hdc: Path) -> tuple[str, ...]:
    completed = subprocess.run(
        (str(hdc), "list", "targets"),
        capture_output=True,
        text=True,
        timeout=COMMAND_TIMEOUT_SECONDS,
        check=False,
    )
    if completed.returncode != 0:
        raise DeviceCommandError(
            command=(str(hdc), "list", "targets"),
            return_code=completed.returncode,
            output=completed.stdout + completed.stderr,
        )
    return tuple(
        line.strip()
        for line in completed.stdout.splitlines()
        if line.strip() not in {"", "[Empty]"}
    )


def select_device(hdc: Path, requested: str | None = None) -> HdcDevice:
    available = connected_devices(hdc)
    if requested is not None:
        if requested not in available:
            raise DeviceSelectionError(requested=requested, available=available)
        return HdcDevice(hdc=hdc, serial=requested)
    if len(available) != 1:
        raise DeviceSelectionError(requested=None, available=available)
    return HdcDevice(hdc=hdc, serial=available[0])


def is_device_locked(screenlock_dump: str) -> bool:
    return DEVICE_LOCKED_PATTERN.search(screenlock_dump) is not None
