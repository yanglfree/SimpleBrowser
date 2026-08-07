import pytest
from pydantic import ValidationError

from dolphin_harness.models import AssertVisibleStep, Scenario, TapStep


def test_scenario_parses_discriminated_steps() -> None:
    scenario = Scenario.model_validate(
        {
            "name": "smoke",
            "bundle": "com.youdroid.dolphin",
            "ability": "EntryAbility",
            "steps": [
                {"action": "launch", "reset": False},
                {
                    "action": "tap",
                    "locator": {"kind": "id", "value": "browser-address"},
                },
                {
                    "action": "assert_visible",
                    "locator": {"kind": "text", "value": "取消"},
                },
            ],
        }
    )

    assert isinstance(scenario.steps[1], TapStep)
    assert isinstance(scenario.steps[2], AssertVisibleStep)


def test_scenario_rejects_unknown_action() -> None:
    with pytest.raises(ValidationError):
        _ = Scenario.model_validate(
            {
                "name": "invalid",
                "bundle": "com.youdroid.dolphin",
                "ability": "EntryAbility",
                "steps": [{"action": "guess"}],
            }
        )
