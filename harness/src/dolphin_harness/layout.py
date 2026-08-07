import re
from dataclasses import dataclass
from typing import Final, assert_never, override

from dolphin_harness.errors import HarnessError
from dolphin_harness.models import Locator, LocatorKind, UiNode

BOUNDS_PATTERN: Final = re.compile(r"^\[(-?\d+),(-?\d+)]\[(-?\d+),(-?\d+)]$")


@dataclass(frozen=True, slots=True)
class Bounds:
    left: int
    top: int
    right: int
    bottom: int

    @property
    def center_x(self) -> int:
        return (self.left + self.right) // 2

    @property
    def center_y(self) -> int:
        return (self.top + self.bottom) // 2


@dataclass(frozen=True, slots=True)
class NodeMatch:
    node: UiNode
    bounds: Bounds


@dataclass(frozen=True, slots=True)
class InvalidBoundsError(HarnessError):
    raw: str

    @override
    def __str__(self) -> str:
        return f"invalid UI bounds: {self.raw!r}"


@dataclass(frozen=True, slots=True)
class LocatorNotFoundError(HarnessError):
    locator: Locator

    @override
    def __str__(self) -> str:
        return f"no visible node matched {self.locator.kind}={self.locator.value!r}"


@dataclass(frozen=True, slots=True)
class AmbiguousLocatorError(HarnessError):
    locator: Locator
    count: int

    @override
    def __str__(self) -> str:
        return f"{self.count} visible nodes matched {self.locator.kind}={self.locator.value!r}"


def parse_bounds(raw: str) -> Bounds:
    matched = BOUNDS_PATTERN.fullmatch(raw)
    if matched is None:
        raise InvalidBoundsError(raw=raw)
    left, top, right, bottom = (int(value) for value in matched.groups())
    return Bounds(left=left, top=top, right=right, bottom=bottom)


def find_node(root: UiNode, locator: Locator) -> NodeMatch:
    matches = _matching_nodes(root, locator, ())
    if locator.index is not None:
        if locator.index >= len(matches):
            raise LocatorNotFoundError(locator=locator)
        return matches[locator.index]
    if len(matches) == 0:
        raise LocatorNotFoundError(locator=locator)
    if len(matches) > 1:
        raise AmbiguousLocatorError(locator=locator, count=len(matches))
    return matches[0]


def _matching_nodes(
    root: UiNode, locator: Locator, ancestors: tuple[UiNode, ...]
) -> list[NodeMatch]:
    matches: list[NodeMatch] = []
    if root.attributes.visible != "false" and _matches(root, locator):
        target = _clickable_target(root, ancestors)
        matches.append(NodeMatch(node=target, bounds=parse_bounds(target.attributes.bounds)))
    next_ancestors = (*ancestors, root)
    for child in root.children:
        matches.extend(_matching_nodes(child, locator, next_ancestors))
    return matches


def _matches(node: UiNode, locator: Locator) -> bool:
    match locator.kind:
        case LocatorKind.ID:
            actual = node.attributes.id
        case LocatorKind.TEXT:
            actual = node.attributes.text
        case LocatorKind.DESCRIPTION:
            actual = node.attributes.description
        case LocatorKind.TYPE:
            actual = node.attributes.type
        case unreachable:
            assert_never(unreachable)
    return actual == locator.value if locator.exact else locator.value in actual


def _clickable_target(node: UiNode, ancestors: tuple[UiNode, ...]) -> UiNode:
    if node.attributes.clickable == "true":
        return node
    for ancestor in reversed(ancestors):
        if ancestor.attributes.clickable == "true":
            return ancestor
    return node
