import pytest

from dolphin_harness.layout import AmbiguousLocatorError, find_node, parse_bounds
from dolphin_harness.models import Locator, LocatorKind, UiNode


@pytest.fixture
def tree() -> UiNode:
    return UiNode.model_validate(
        {
            "attributes": {"type": "root", "bounds": "[0,0][1084,2412]"},
            "children": [
                {
                    "attributes": {
                        "id": "browser-address",
                        "type": "Row",
                        "bounds": "[120,2100][900,2240]",
                        "clickable": "true",
                        "visible": "true",
                    },
                    "children": [
                        {
                            "attributes": {
                                "text": "搜索或输入网址",
                                "type": "Text",
                                "bounds": "[260,2120][760,2220]",
                                "visible": "true",
                            }
                        }
                    ],
                }
            ],
        }
    )


def test_parse_bounds_returns_center() -> None:
    bounds = parse_bounds("[120,2100][900,2240]")

    assert bounds.center_x == 510
    assert bounds.center_y == 2170


def test_find_node_promotes_text_to_clickable_ancestor(tree: UiNode) -> None:
    match = find_node(tree, Locator(kind=LocatorKind.TEXT, value="搜索或输入网址"))

    assert match.node.attributes.id == "browser-address"
    assert match.bounds.center_x == 510


def test_find_node_rejects_ambiguous_semantic_match(tree: UiNode) -> None:
    duplicated = tree.model_copy(update={"children": tree.children + tree.children})

    with pytest.raises(AmbiguousLocatorError):
        _ = find_node(duplicated, Locator(kind=LocatorKind.ID, value="browser-address"))
