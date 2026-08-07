from enum import StrEnum, unique
from pathlib import Path
from typing import Annotated, ClassVar, Literal

from pydantic import BaseModel, ConfigDict, Field


class FrozenModel(BaseModel):
    model_config: ClassVar[ConfigDict] = ConfigDict(frozen=True, extra="forbid")


@unique
class LocatorKind(StrEnum):
    ID = "id"
    TEXT = "text"
    DESCRIPTION = "description"
    TYPE = "type"


@unique
class KeyName(StrEnum):
    BACK = "Back"
    HOME = "Home"
    POWER = "Power"


class Locator(FrozenModel):
    kind: LocatorKind
    value: str = Field(min_length=1)
    exact: bool = True
    index: int | None = Field(default=None, ge=0)


class LaunchStep(FrozenModel):
    action: Literal["launch"]
    reset: bool = False


class TapStep(FrozenModel):
    action: Literal["tap"]
    locator: Locator


class LongPressStep(FrozenModel):
    action: Literal["long_press"]
    locator: Locator


class InputTextStep(FrozenModel):
    action: Literal["input_text"]
    locator: Locator
    text: str = Field(min_length=1)


class SwipeStep(FrozenModel):
    action: Literal["swipe"]
    from_x: int = Field(ge=0)
    from_y: int = Field(ge=0)
    to_x: int = Field(ge=0)
    to_y: int = Field(ge=0)
    velocity: int = Field(default=600, ge=200, le=40_000)


class KeyStep(FrozenModel):
    action: Literal["key"]
    key: KeyName


class AssertVisibleStep(FrozenModel):
    action: Literal["assert_visible"]
    locator: Locator


class SnapshotStep(FrozenModel):
    action: Literal["snapshot"]
    name: str = Field(pattern=r"^[a-zA-Z0-9][a-zA-Z0-9_-]*$")


type ScenarioStep = Annotated[
    LaunchStep
    | TapStep
    | LongPressStep
    | InputTextStep
    | SwipeStep
    | KeyStep
    | AssertVisibleStep
    | SnapshotStep,
    Field(discriminator="action"),
]


class Scenario(FrozenModel):
    name: str = Field(pattern=r"^[a-zA-Z0-9][a-zA-Z0-9_-]*$")
    bundle: str = Field(min_length=3)
    ability: str = Field(min_length=1)
    capture_each_step: bool = True
    steps: tuple[ScenarioStep, ...] = Field(min_length=1)


class UiAttributes(BaseModel):
    model_config: ClassVar[ConfigDict] = ConfigDict(frozen=True, extra="ignore")

    id: str = ""
    text: str = ""
    description: str = ""
    type: str = ""
    bounds: str = ""
    clickable: str = "false"
    enabled: str = "true"
    visible: str = "true"
    bundle_name: str = Field(default="", alias="bundleName")
    ability_name: str = Field(default="", alias="abilityName")


class UiNode(BaseModel):
    model_config: ClassVar[ConfigDict] = ConfigDict(frozen=True, extra="ignore")

    attributes: UiAttributes
    children: tuple["UiNode", ...] = ()


class StepResult(FrozenModel):
    index: int
    action: str
    status: Literal["passed", "failed"]
    duration_ms: int = Field(ge=0)
    screenshot: Path | None = None
    layout: Path | None = None
    message: str = ""


class RunReport(FrozenModel):
    scenario: str
    device: str
    status: Literal["passed", "failed"]
    started_at: str
    finished_at: str
    artifact_dir: Path
    steps: tuple[StepResult, ...]
