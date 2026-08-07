from pathlib import Path

from dolphin_harness.models import Scenario, UiNode
from dolphin_harness.runner import HarnessRunner


class FakeDevice:
    serial: str = "test-device"
    tree: UiNode

    def __init__(self, tree: UiNode) -> None:
        self.tree = tree
        self.calls: list[str] = []

    def prepare(self) -> None:
        self.calls.append("prepare")

    def reset(self, bundle: str) -> None:
        self.calls.append(f"reset:{bundle}")

    def launch(self, bundle: str, ability: str) -> None:
        self.calls.append(f"launch:{bundle}:{ability}")

    def dump_layout(self, bundle: str, destination: Path) -> UiNode:
        _ = destination.write_text(self.tree.model_dump_json(by_alias=True), encoding="utf-8")
        self.calls.append(f"layout:{bundle}")
        return self.tree

    def screenshot(self, destination: Path) -> None:
        _ = destination.write_bytes(b"png")
        self.calls.append("screenshot")

    def tap(self, x: int, y: int) -> None:
        self.calls.append(f"tap:{x}:{y}")

    def long_press(self, x: int, y: int) -> None:
        self.calls.append(f"long_press:{x}:{y}")

    def input_text(self, x: int, y: int, text: str) -> None:
        self.calls.append(f"input:{x}:{y}:{text}")

    def swipe(self, from_x: int, from_y: int, to_x: int, to_y: int, velocity: int) -> None:
        self.calls.append(f"swipe:{from_x}:{from_y}:{to_x}:{to_y}:{velocity}")

    def key(self, key: str) -> None:
        self.calls.append(f"key:{key}")


def test_runner_drives_semantic_tap_and_records_evidence(tmp_path: Path) -> None:
    tree = UiNode.model_validate(
        {
            "attributes": {"type": "root", "bounds": "[0,0][1084,2412]"},
            "children": [
                {
                    "attributes": {
                        "id": "browser-address",
                        "bounds": "[120,2100][900,2240]",
                        "clickable": "true",
                    }
                }
            ],
        }
    )
    device = FakeDevice(tree)
    scenario = Scenario.model_validate(
        {
            "name": "tap-address",
            "bundle": "com.youdroid.dolphin",
            "ability": "EntryAbility",
            "steps": [
                {"action": "launch"},
                {"action": "tap", "locator": {"kind": "id", "value": "browser-address"}},
                {
                    "action": "assert_visible",
                    "locator": {"kind": "id", "value": "browser-address"},
                },
            ],
        }
    )

    report = HarnessRunner(device=device, artifact_root=tmp_path).run(scenario)

    assert report.status == "passed"
    assert "tap:510:2170" in device.calls
    assert len(report.steps) == 3
    assert all(step.screenshot is not None for step in report.steps)
    assert (report.artifact_dir / "report.json").exists()
