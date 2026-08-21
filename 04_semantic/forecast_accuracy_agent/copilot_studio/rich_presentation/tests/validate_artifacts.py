#!/usr/bin/env python3
"""Validate source-controlled contracts, fixtures and Adaptive Card templates."""

from __future__ import annotations

import json
import sys
from pathlib import Path
from typing import Any

from jsonschema import Draft202012Validator, FormatChecker


ROOT = Path(__file__).resolve().parents[1]
SCHEMA_DIR = ROOT / "contracts"
FORBIDDEN_TOKENS = {
    "action.execute",
    "chart.",
    "select ",
    "insert ",
    "update ",
    "delete ",
    "drop ",
    "userprincipalname",
    "impersonatedusername",
    "authorization",
    "rls",
}


def load(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def fail(message: str, failures: list[str]) -> None:
    failures.append(message)


def walk(value: Any):
    yield value
    if isinstance(value, dict):
        for key, nested in value.items():
            yield key
            yield from walk(nested)
    elif isinstance(value, list):
        for nested in value:
            yield from walk(nested)


def validate_json_files(
    directory: Path,
    validator: Draft202012Validator,
    failures: list[str],
) -> None:
    for path in sorted(directory.glob("*.json")):
        document = load(path)
        errors = sorted(validator.iter_errors(document), key=lambda error: list(error.path))
        for error in errors:
            location = ".".join(str(part) for part in error.path) or "$"
            fail(f"{path.relative_to(ROOT)}:{location}: {error.message}", failures)


def main() -> int:
    failures: list[str] = []
    checker = FormatChecker()
    schemas = {
        path.stem: load(path)
        for path in SCHEMA_DIR.glob("*.schema.json")
    }
    validators = {}
    for name, schema in schemas.items():
        try:
            Draft202012Validator.check_schema(schema)
            validators[name] = Draft202012Validator(schema, format_checker=checker)
        except Exception as exc:  # pragma: no cover - diagnostic path
            fail(f"invalid schema {name}: {exc}", failures)

    if "presentation-request" in validators:
        validate_json_files(ROOT / "fixtures" / "requests", validators["presentation-request"], failures)
    if "evidence-envelope" in validators:
        validate_json_files(ROOT / "fixtures" / "evidence", validators["evidence-envelope"], failures)
    if "presentation-envelope" in validators:
        validate_json_files(ROOT / "fixtures" / "presentations", validators["presentation-envelope"], failures)
    if "interaction-envelope" in validators:
        validate_json_files(ROOT / "fixtures" / "interactions", validators["interaction-envelope"], failures)

    profiles = load(ROOT / "registry" / "channel-profiles.json")
    if "channel-capability" in validators:
        for index, profile in enumerate(profiles):
            for error in validators["channel-capability"].iter_errors(profile):
                fail(f"registry/channel-profiles.json[{index}]: {error.message}", failures)

    registry = load(ROOT / "registry" / "presentation-registry.json")
    flow_branches = load(ROOT / "registry" / "flow-presentation-branches.json")
    branch_ids = [branch.get("id") for branch in flow_branches.get("branches", [])]
    if branch_ids != [f"B{number:02d}_{name}" for number, name in [
        (1, "INVALID_EVIDENCE"),
        (2, "GOVERNANCE_DRAFT"),
        (3, "CURATED_FLASHCARD"),
        (4, "SCALAR"),
        (5, "RICH_TREND"),
        (6, "TREND_HOST_FALLBACK"),
        (7, "SMALL_TABLE"),
        (8, "OVERFLOW"),
        (9, "NO_TEMPLATE"),
    ]]:
        fail("finite Flow branch order drifted", failures)
    for forbidden in ["dax", "sql", "rawCardJson", "userId", "role", "approvalState", "nextReviewAt"]:
        if forbidden not in flow_branches.get("forbiddenInputs", []):
            fail(f"Flow branch spec does not forbid {forbidden}", failures)
    profile_ids = {profile["profileId"] for profile in profiles}
    card_names = {path.stem for path in (ROOT / "cards" / "ac15").glob("*.json")}
    required_card_names = {
        "forecast-kpi-v1",
        "forecast-table-v1",
        "forecast-trend-fallback-v1",
        "forecast-flashcard-v1",
        "forecast-governance-form-v1",
        "forecast-text-v1",
    }
    missing_cards = required_card_names - card_names
    for missing in sorted(missing_cards):
        fail(f"missing Adaptive Card template: cards/ac15/{missing}.json", failures)

    for entry in registry.get("templates", []):
        if entry.get("registryVersion") != "1.0.0":
            fail(f"registry version drift: {entry.get('templateId')}", failures)
        if not set(entry.get("supportedProfiles", [])) <= profile_ids:
            fail(f"unknown channel profile in {entry.get('templateId')}", failures)
        if entry.get("fallbackTemplateId") not in {item.get("templateId") for item in registry.get("templates", [])}:
            fail(f"unknown fallback for {entry.get('templateId')}", failures)

    for path in sorted((ROOT / "cards" / "ac15").glob("*.json")):
        card = load(path)
        if card.get("type") != "AdaptiveCard":
            fail(f"{path.relative_to(ROOT)} is not an AdaptiveCard", failures)
        if card.get("version") != "1.5":
            fail(f"{path.relative_to(ROOT)} must stay on Adaptive Card 1.5", failures)
        serialized = json.dumps(card, sort_keys=True).lower()
        for token in FORBIDDEN_TOKENS:
            if token in serialized:
                fail(f"{path.relative_to(ROOT)} contains forbidden token {token}", failures)
        for value in walk(card):
            if isinstance(value, dict) and value.get("type") == "Action.Submit":
                data = value.get("data")
                if not isinstance(data, dict) or not isinstance(data.get("actionId"), str):
                    fail(f"{path.relative_to(ROOT)} Action.Submit has no allowlisted actionId", failures)
                if isinstance(data, dict) and "userId" in data:
                    fail(f"{path.relative_to(ROOT)} accepts userId from card payload", failures)

    flashcards = load(ROOT / "registry" / "flashcard-registry.json")
    concept_ids = [concept.get("conceptId") for concept in flashcards.get("concepts", [])]
    if len(concept_ids) != len(set(concept_ids)):
        fail("flashcard registry contains duplicate concept IDs", failures)
    if not concept_ids:
        fail("flashcard registry is empty", failures)

    if failures:
        print(json.dumps({"ok": False, "failures": failures}, indent=2))
        return 1

    print(json.dumps({
        "ok": True,
        "schemaCount": len(validators),
        "channelProfileCount": len(profiles),
        "templateCount": len(registry.get("templates", [])),
        "cardTemplateCount": len(card_names),
        "flashcardCount": len(concept_ids),
    }, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
