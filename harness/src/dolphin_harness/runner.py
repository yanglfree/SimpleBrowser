from datetime import UTC, datetime
from pathlib import Path
from time import monotonic_ns
from typing import Protocol, assert_never

from dolphin_harness.errors import HarnessError
from dolphin_harness.layout import find_node
from dolphin_harness.models import (
    AssertVisibleStep,
    InputTextStep,
    KeyStep,
    LaunchStep,
    LongPressStep,
    RunReport,
    Scenario,
    ScenarioStep,
    SnapshotStep,
    StepResult,
    SwipeStep,
    TapStep,
    UiNode,
)


class Device(Protocol):
    serial: str

    def prepare(self) -> None: ...

    def reset(self, bundle: str) -> None: ...

    def launch(self, bundle: str, ability: str) -> None: ...

    def dump_layout(self, bundle: str, destination: Path) -> UiNode: ...

    def screenshot(self, destination: Path) -> None: ...

    def tap(self, x: int, y: int) -> None: ...

    def long_press(self, x: int, y: int) -> None: ...

    def input_text(self, x: int, y: int, text: str) -> None: ...

    def swipe(self, from_x: int, from_y: int, to_x: int, to_y: int, velocity: int) -> None: ...

    def key(self, key: str) -> None: ...


class HarnessRunner:
    _device: Device
    _artifact_root: Path

    def __init__(self, device: Device, artifact_root: Path) -> None:
        self._device = device
        self._artifact_root = artifact_root

    def run(self, scenario: Scenario) -> RunReport:
        started = datetime.now(tz=UTC)
        artifact_dir = self._artifact_directory(scenario, started)
        artifact_dir.mkdir(parents=True)
        results: list[StepResult] = []

        for index, step in enumerate(scenario.steps):
            result = self._run_step(scenario, step, index, artifact_dir)
            results.append(result)
            if result.status == "failed":
                break

        finished = datetime.now(tz=UTC)
        report = RunReport(
            scenario=scenario.name,
            device=self._device.serial,
            status="failed" if any(result.status == "failed" for result in results) else "passed",
            started_at=started.isoformat(),
            finished_at=finished.isoformat(),
            artifact_dir=artifact_dir,
            steps=tuple(results),
        )
        _ = (artifact_dir / "report.json").write_text(
            report.model_dump_json(indent=2),
            encoding="utf-8",
        )
        return report

    def _run_step(
        self,
        scenario: Scenario,
        step: ScenarioStep,
        index: int,
        artifact_dir: Path,
    ) -> StepResult:
        started_ns = monotonic_ns()
        try:
            self._execute(scenario, step, index, artifact_dir)
            screenshot, layout = self._capture_if_needed(scenario, step, index, artifact_dir)
        except (HarnessError, OSError) as error:
            screenshot, layout = self._capture_failure(scenario, index, artifact_dir)
            return StepResult(
                index=index,
                action=step.action,
                status="failed",
                duration_ms=self._elapsed_ms(started_ns),
                screenshot=screenshot,
                layout=layout,
                message=str(error),
            )
        return StepResult(
            index=index,
            action=step.action,
            status="passed",
            duration_ms=self._elapsed_ms(started_ns),
            screenshot=screenshot,
            layout=layout,
        )

    def _execute(
        self,
        scenario: Scenario,
        step: ScenarioStep,
        index: int,
        artifact_dir: Path,
    ) -> None:
        match step:
            case LaunchStep(reset=reset):
                self._device.prepare()
                if reset:
                    self._device.reset(scenario.bundle)
                self._device.launch(scenario.bundle, scenario.ability)
            case TapStep(locator=locator):
                matched = find_node(self._lookup(scenario, index, artifact_dir), locator)
                self._device.tap(matched.bounds.center_x, matched.bounds.center_y)
            case LongPressStep(locator=locator):
                matched = find_node(self._lookup(scenario, index, artifact_dir), locator)
                self._device.long_press(matched.bounds.center_x, matched.bounds.center_y)
            case InputTextStep(locator=locator, text=text):
                matched = find_node(self._lookup(scenario, index, artifact_dir), locator)
                self._device.input_text(matched.bounds.center_x, matched.bounds.center_y, text)
            case SwipeStep(from_x=from_x, from_y=from_y, to_x=to_x, to_y=to_y, velocity=velocity):
                self._device.swipe(from_x, from_y, to_x, to_y, velocity)
            case KeyStep(key=key):
                self._device.key(key.value)
            case AssertVisibleStep(locator=locator):
                _ = find_node(self._lookup(scenario, index, artifact_dir), locator)
            case SnapshotStep():
                return
            case unreachable:
                assert_never(unreachable)

    def _lookup(self, scenario: Scenario, index: int, artifact_dir: Path) -> UiNode:
        return self._device.dump_layout(scenario.bundle, artifact_dir / f"{index:02d}-lookup.json")

    def _capture_if_needed(
        self,
        scenario: Scenario,
        step: ScenarioStep,
        index: int,
        artifact_dir: Path,
    ) -> tuple[Path | None, Path | None]:
        match step:
            case SnapshotStep(name=name):
                slug = name
                should_capture = True
            case (
                LaunchStep()
                | TapStep()
                | LongPressStep()
                | InputTextStep()
                | SwipeStep()
                | KeyStep()
                | AssertVisibleStep()
            ):
                slug = step.action
                should_capture = scenario.capture_each_step
            case unreachable:
                assert_never(unreachable)
        if not should_capture:
            return None, None
        return self._capture(scenario.bundle, index, slug, artifact_dir)

    def _capture_failure(
        self,
        scenario: Scenario,
        index: int,
        artifact_dir: Path,
    ) -> tuple[Path | None, Path | None]:
        try:
            return self._capture(scenario.bundle, index, "failed", artifact_dir)
        except (HarnessError, OSError):
            return None, None

    def _capture(
        self,
        bundle: str,
        index: int,
        slug: str,
        artifact_dir: Path,
    ) -> tuple[Path, Path]:
        prefix = f"{index:02d}-{slug}"
        screenshot = artifact_dir / f"{prefix}.png"
        layout = artifact_dir / f"{prefix}.json"
        self._device.screenshot(screenshot)
        _ = self._device.dump_layout(bundle, layout)
        return screenshot, layout

    def _artifact_directory(self, scenario: Scenario, started: datetime) -> Path:
        timestamp = started.strftime("%Y%m%dT%H%M%S.%fZ")
        return self._artifact_root / f"{timestamp}-{scenario.name}"

    @staticmethod
    def _elapsed_ms(started_ns: int) -> int:
        return max(0, (monotonic_ns() - started_ns) // 1_000_000)
