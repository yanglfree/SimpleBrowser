import json
from pathlib import Path
from tempfile import TemporaryDirectory
from typing import Annotated, Final, NoReturn

import typer
from pydantic import ValidationError

from dolphin_harness.device import HdcDevice, find_hdc, select_device
from dolphin_harness.errors import HarnessError
from dolphin_harness.layout import find_node
from dolphin_harness.models import Locator, LocatorKind, Scenario
from dolphin_harness.runner import HarnessRunner

app = typer.Typer(no_args_is_help=True, pretty_exceptions_enable=False)
DEFAULT_ARTIFACTS: Final = Path("artifacts")
DEFAULT_MANUAL_OUTPUT: Final = Path("artifacts/manual")


def _device(serial: str | None, hdc: Path | None) -> HdcDevice:
    return select_device(find_hdc(hdc), serial)


def _scenario(path: Path) -> Scenario:
    return Scenario.model_validate_json(path.read_text(encoding="utf-8"))


def _fail(error: HarnessError | OSError | ValidationError) -> NoReturn:
    typer.echo(json.dumps({"status": "failed", "error": str(error)}, ensure_ascii=False))
    raise typer.Exit(code=1)


@app.command()
def doctor(
    serial: Annotated[str | None, typer.Option(help="Connected hdc target.")] = None,
    hdc: Annotated[Path | None, typer.Option(help="Path to the hdc executable.")] = None,
) -> None:
    try:
        device = _device(serial, hdc)
        device.prepare()
    except (HarnessError, OSError) as error:
        _fail(error)
    typer.echo(
        json.dumps(
            {"status": "passed", "device": device.serial, "hdc": str(find_hdc(hdc))},
            ensure_ascii=False,
        )
    )


@app.command("install")
def install_hap(
    hap: Annotated[Path, typer.Argument(exists=True, dir_okay=False)],
    serial: Annotated[str | None, typer.Option(help="Connected hdc target.")] = None,
    hdc: Annotated[Path | None, typer.Option(help="Path to the hdc executable.")] = None,
) -> None:
    try:
        device = _device(serial, hdc)
        device.install(hap)
    except (HarnessError, OSError) as error:
        _fail(error)
    typer.echo(json.dumps({"status": "passed", "device": device.serial, "hap": str(hap.resolve())}))


@app.command("run")
def run_scenario(
    scenario_path: Annotated[Path, typer.Argument(exists=True, dir_okay=False)],
    artifacts: Annotated[
        Path, typer.Option(help="Root directory for run evidence.")
    ] = DEFAULT_ARTIFACTS,
    serial: Annotated[str | None, typer.Option(help="Connected hdc target.")] = None,
    hdc: Annotated[Path | None, typer.Option(help="Path to the hdc executable.")] = None,
) -> None:
    try:
        scenario = _scenario(scenario_path)
        report = HarnessRunner(device=_device(serial, hdc), artifact_root=artifacts).run(scenario)
    except (HarnessError, OSError, ValidationError) as error:
        _fail(error)
    typer.echo(report.model_dump_json(indent=2))
    if report.status == "failed":
        raise typer.Exit(code=1)


@app.command()
def snapshot(
    bundle: Annotated[str, typer.Option()] = "com.youdroid.dolphin",
    output: Annotated[Path, typer.Option()] = DEFAULT_MANUAL_OUTPUT,
    serial: Annotated[str | None, typer.Option(help="Connected hdc target.")] = None,
    hdc: Annotated[Path | None, typer.Option(help="Path to the hdc executable.")] = None,
) -> None:
    try:
        device = _device(serial, hdc)
        output.mkdir(parents=True, exist_ok=True)
        screenshot_path = output / "screen.png"
        layout_path = output / "layout.json"
        device.screenshot(screenshot_path)
        _ = device.dump_layout(bundle, layout_path)
    except (HarnessError, OSError) as error:
        _fail(error)
    typer.echo(
        json.dumps(
            {
                "status": "passed",
                "screenshot": str(screenshot_path.resolve()),
                "layout": str(layout_path.resolve()),
            }
        )
    )


@app.command()
def tap(
    value: Annotated[str, typer.Argument(min=1)],
    kind: Annotated[LocatorKind, typer.Option()] = LocatorKind.ID,
    bundle: Annotated[str, typer.Option()] = "com.youdroid.dolphin",
    exact: Annotated[bool, typer.Option()] = True,
    index: Annotated[int | None, typer.Option(min=0)] = None,
    serial: Annotated[str | None, typer.Option(help="Connected hdc target.")] = None,
    hdc: Annotated[Path | None, typer.Option(help="Path to the hdc executable.")] = None,
) -> None:
    try:
        device = _device(serial, hdc)
        with TemporaryDirectory(prefix="dolphin-harness-") as temporary:
            tree = device.dump_layout(bundle, Path(temporary) / "layout.json")
            matched = find_node(tree, Locator(kind=kind, value=value, exact=exact, index=index))
            device.tap(matched.bounds.center_x, matched.bounds.center_y)
    except (HarnessError, OSError) as error:
        _fail(error)
    typer.echo(
        json.dumps(
            {
                "status": "passed",
                "x": matched.bounds.center_x,
                "y": matched.bounds.center_y,
                "node": matched.node.attributes.model_dump(by_alias=True),
            },
            ensure_ascii=False,
        )
    )


if __name__ == "__main__":
    app()
