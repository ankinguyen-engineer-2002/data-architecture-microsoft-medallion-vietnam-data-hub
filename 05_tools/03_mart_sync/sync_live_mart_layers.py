#!/usr/bin/env python3
"""Sync mart layer SQL files from live Fabric Warehouse definitions.

Read-only against Fabric SQL endpoints. Local changes are non-destructive:
files no longer in the live active closure are moved to mart history.
"""

from __future__ import annotations

import json
import re
import shutil
import struct
import subprocess
from collections import defaultdict, deque
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Iterable

import pyodbc


ROOT = Path(__file__).resolve().parents[2]
SERVER = "7woj2wroypauvkpn72b56t46ju-qp6ntsfwdaou5atebne65u3p4a.datawarehouse.fabric.microsoft.com"
PROCESSING_DB = "SupplyChain_Processing_Warehouse"
GOLD_DB = "SupplyChain_Gold_Warehouse"
SCAN_ID = "20260623_live_scan"

PROJECTS = ("forecast_accuracy", "inventory_health")
SHARED_PROJECT = "shared"
PROJECT_GOLD_SCHEMAS = {
    "forecast_accuracy": {"ForecastAccuracy_DW"},
    "inventory_health": {"InventoryHealth_DW"},
}

PROCESSING_SCHEMAS = {
    "Staging",
    "Staging_Wrk",
    "ProcessingSeed",
    "ReferenceMaster_Enh",
    "SalesHistory_Enh",
    "ForecastHistory_Enh",
    "OpenOrderHistory_Enh",
    "InventoryHistory_Enh",
}
GOLD_SCHEMAS = {"ForecastAccuracy_DW", "InventoryHealth_DW", "Shared_DW"}
EXTERNAL_DBS = {"Enterprise_Lakehouse", "SupplyChain_Lakehouse"}

THREE_PART_RE = re.compile(
    r"(?:(?:\[([^\]]+)\])|([A-Za-z_][A-Za-z0-9_]*))"
    r"\s*\.\s*"
    r"(?:(?:\[([^\]]+)\])|([A-Za-z_][A-Za-z0-9_]*))"
    r"\s*\.\s*"
    r"(?:(?:\[([^\]]+)\])|([A-Za-z_][A-Za-z0-9_]*))"
)
TWO_PART_RE = re.compile(
    r"(?:(?:\[([^\]]+)\])|([A-Za-z_][A-Za-z0-9_]*))"
    r"\s*\.\s*"
    r"(?:(?:\[([^\]]+)\])|([A-Za-z_][A-Za-z0-9_]*))"
)


@dataclass(frozen=True)
class Obj:
    db: str
    schema: str
    name: str

    @property
    def short(self) -> str:
        return f"{self.schema}.{self.name}"

    @property
    def full(self) -> str:
        return f"{self.db}.{self.schema}.{self.name}"


def az_token(resource: str) -> str:
    return subprocess.check_output(
        [
            "az",
            "account",
            "get-access-token",
            "--resource",
            resource,
            "--query",
            "accessToken",
            "-o",
            "tsv",
        ],
        text=True,
    ).strip()


def connect(database: str, db_token: str) -> pyodbc.Connection:
    token_bytes = db_token.encode("UTF-16-LE")
    token_struct = struct.pack(f"<I{len(token_bytes)}s", len(token_bytes), token_bytes)
    return pyodbc.connect(
        f"DRIVER={{ODBC Driver 18 for SQL Server}};"
        f"SERVER={SERVER};DATABASE={database};Encrypt=yes;TrustServerCertificate=no;",
        attrs_before={1256: token_struct},
    )


def fetch_modules(conn: pyodbc.Connection, db: str) -> dict[Obj, str]:
    cur = conn.cursor()
    cur.execute(
        """
        SELECT s.name AS schema_name, o.name AS object_name, m.definition
        FROM sys.objects AS o
        JOIN sys.schemas AS s ON s.schema_id = o.schema_id
        JOIN sys.sql_modules AS m ON m.object_id = o.object_id
        WHERE o.type IN ('V','P','FN','IF','TF')
        ORDER BY s.name, o.name
        """
    )
    return {
        Obj(db, str(row.schema_name), str(row.object_name)): str(row.definition)
        for row in cur.fetchall()
    }


def fetch_registry(conn: pyodbc.Connection) -> list[dict[str, object]]:
    cur = conn.cursor()
    cur.execute(
        """
        SELECT project, canonical_layer, physical_schema, physical_object,
               legacy_view_name, source_objects, is_active
        FROM Meta.AssetRegistry
        WHERE is_active = 1
          AND project IN ('forecast_accuracy', 'inventory_health', 'shared')
        ORDER BY project, canonical_layer, physical_schema, physical_object
        """
    )
    rows = []
    for row in cur.fetchall():
        rows.append({desc[0]: value for desc, value in zip(cur.description, row)})
    return rows


def parse_legacy_view_name(value: object) -> tuple[str, str] | None:
    if not value:
        return None
    parts = str(value).strip().replace("[", "").replace("]", "").split(".")
    if len(parts) != 2:
        return None
    return parts[0], parts[1]


def obj_for_schema(schema: str, name: str) -> Obj | None:
    if schema in GOLD_SCHEMAS:
        return Obj(GOLD_DB, schema, name)
    if schema in PROCESSING_SCHEMAS:
        return Obj(PROCESSING_DB, schema, name)
    return None


def refs_from_definition(definition: str) -> set[Obj]:
    refs: set[Obj] = set()
    cleaned = re.sub(r"--.*?$", "", definition, flags=re.M)
    for match in THREE_PART_RE.finditer(cleaned):
        db = match.group(1) or match.group(2)
        schema = match.group(3) or match.group(4)
        name = match.group(5) or match.group(6)
        if db and schema and name:
            refs.add(Obj(db, schema, name))
    for match in TWO_PART_RE.finditer(cleaned):
        schema = match.group(1) or match.group(2)
        name = match.group(3) or match.group(4)
        if not schema or not name:
            continue
        obj = obj_for_schema(schema, name)
        if obj:
            refs.add(obj)
    return refs


def live_closure(seed: Iterable[Obj], modules: dict[Obj, str]) -> set[Obj]:
    seen: set[Obj] = set()
    queue = deque(seed)
    while queue:
        obj = queue.popleft()
        if obj in seen:
            continue
        seen.add(obj)
        definition = modules.get(obj)
        if not definition:
            continue
        for ref in refs_from_definition(definition):
            module_ref = module_for_ref(ref, modules)
            if ref.db in {PROCESSING_DB, GOLD_DB} and module_ref and module_ref not in seen:
                queue.append(module_ref)
            elif ref.db in EXTERNAL_DBS:
                continue
            elif ref.schema in PROCESSING_SCHEMAS or ref.schema in GOLD_SCHEMAS:
                candidate = obj_for_schema(ref.schema, ref.name)
                module_candidate = module_for_ref(candidate, modules) if candidate else None
                if module_candidate and module_candidate not in seen:
                    queue.append(module_candidate)
    return seen


def module_for_ref(ref: Obj, modules: dict[Obj, str]) -> Obj | None:
    """Resolve physical table refs to the live source view module when present.

    Fabric Gold views often reference curated physical tables such as
    InventoryHistory_Enh.PurchaseOrderSnapshotHistorical, while the reusable
    SQL logic lives in InventoryHistory_Enh.v_PurchaseOrderSnapshotHistorical.
    The repo stores the source module definition, so follow the v_* counterpart.
    """
    if ref in modules:
        return ref
    view_ref = Obj(ref.db, ref.schema, f"v_{ref.name}")
    if view_ref in modules:
        return view_ref
    return None


def mart_dir(project: str) -> Path:
    return ROOT / "02_marts" / project


def path_for_obj(project: str, obj: Obj) -> Path | None:
    base = mart_dir(project)
    if obj.schema == "Staging_Wrk":
        return base / "00_source_wrk" / "staging_wrk" / f"{obj.short}.sql"
    if obj.db == PROCESSING_DB and obj.schema in PROCESSING_SCHEMAS:
        if obj.schema in {"Staging", "ProcessingSeed"}:
            return None
        return base / "02_silver" / f"{obj.short}.sql"
    if obj.db == GOLD_DB and obj.schema in GOLD_SCHEMAS:
        return base / "03_gold" / f"{obj.short}.sql"
    return None


def path_for_source_note(project: str, obj: Obj) -> Path | None:
    base = mart_dir(project)
    if obj.db == PROCESSING_DB and obj.schema == "ProcessingSeed":
        return base / "00_source_wrk" / "processing_seed" / f"{obj.short}.sql"
    if obj.db == PROCESSING_DB and obj.schema == "Staging":
        return base / "00_source_wrk" / "staging_wrk" / f"{obj.short}.sql"
    return None


def active_sql_files(project: str) -> list[Path]:
    base = mart_dir(project)
    roots = [
        base / "00_source_wrk",
        base / "02_silver",
        base / "03_gold",
    ]
    files: list[Path] = []
    for folder in roots:
        if folder.exists():
            files.extend(sorted(folder.rglob("*.sql")))
    return files


def write_sql(path: Path, definition: str) -> bool:
    path.parent.mkdir(parents=True, exist_ok=True)
    body = definition.strip() + "\n\nGO\n"
    if path.exists() and path.read_text(encoding="utf-8") == body:
        return False
    path.write_text(body, encoding="utf-8")
    return True


def write_source_note(path: Path, obj: Obj, project: str) -> bool:
    path.parent.mkdir(parents=True, exist_ok=True)
    body = (
        f"-- {obj.short}\n"
        f"-- Database: {obj.db}\n"
        f"-- Mart: {project}\n"
        "-- Status: live source object referenced by current Fabric SQL code.\n"
        "-- This object has no local CREATE VIEW definition in sys.sql_modules.\n"
    )
    if path.exists() and path.read_text(encoding="utf-8") == body:
        return False
    path.write_text(body, encoding="utf-8")
    return True


def move_to_history(path: Path, project: str, reason: str) -> Path:
    hist = mart_dir(project) / "99_history" / f"not_live_after_{SCAN_ID}" / reason
    hist.mkdir(parents=True, exist_ok=True)
    target = hist / path.name
    suffix = 1
    while target.exists():
        target = hist / f"{path.stem}_{suffix}{path.suffix}"
        suffix += 1
    shutil.move(str(path), str(target))
    return target


def source_note(source: Obj, project: str) -> str:
    return (
        f"-- {source.full}\n"
        f"-- Layer: Bronze/source shortcut reference for mart `{project}`.\n"
        "-- Status: live active source reference from current Fabric SQL module definitions.\n"
        "-- This is not a local view/table definition in this repo.\n"
    )


def sync_bronze(project: str, sources: set[Obj]) -> dict[str, list[str]]:
    base = mart_dir(project) / "01_bronze"
    folders = {
        "Enterprise_Lakehouse": base / "01_enterprise_lakehouse",
        "SupplyChain_Lakehouse": base / "02_supplychain_lakehouse",
    }
    expected: dict[Path, str] = {}
    for source in sorted(sources, key=lambda x: x.full.lower()):
        folder = folders.get(source.db)
        if not folder:
            continue
        expected[folder / f"{source.full}.sql"] = source_note(source, project)

    changed: list[str] = []
    moved: list[str] = []
    for folder in folders.values():
        folder.mkdir(parents=True, exist_ok=True)
        for path in sorted(folder.glob("*.sql")):
            if path not in expected:
                moved_path = move_to_history(path, project, "bronze_source_not_in_live_code")
                moved.append(f"{path} -> {moved_path}")
    for path, text in expected.items():
        if not path.exists() or path.read_text(encoding="utf-8") != text:
            path.write_text(text, encoding="utf-8")
            changed.append(str(path))

    supplychain_readme = folders["SupplyChain_Lakehouse"] / "README.md"
    if any(source.db == "SupplyChain_Lakehouse" for source in sources):
        readme = (
            "# SupplyChain Lakehouse\n\n"
            "Files here are current live `SupplyChain_Lakehouse` / Dataflow Gen2 source references found in active Fabric SQL code.\n"
        )
    else:
        readme = (
            "# SupplyChain Lakehouse\n\n"
            "No active live source reference for this mart currently uses `SupplyChain_Lakehouse`.\n"
        )
    if not supplychain_readme.exists() or supplychain_readme.read_text(encoding="utf-8") != readme:
        supplychain_readme.write_text(readme, encoding="utf-8")
        changed.append(str(supplychain_readme))
    return {"changed": changed, "moved": moved}


def refs_from_registry_source_objects(value: object) -> set[str]:
    if not value:
        return set()
    text = str(value)
    try:
        loaded = json.loads(text)
        if isinstance(loaded, list):
            return {str(item) for item in loaded}
    except json.JSONDecodeError:
        pass
    return {match.group(0) for match in re.finditer(r"[A-Za-z_][A-Za-z0-9_]*\.[A-Za-z_][A-Za-z0-9_]*\.[A-Za-z_][A-Za-z0-9_]*", text)}


def main() -> None:
    db_token = az_token("https://database.windows.net/")
    with connect(PROCESSING_DB, db_token) as processing, connect(GOLD_DB, db_token) as gold:
        modules = {}
        modules.update(fetch_modules(processing, PROCESSING_DB))
        modules.update(fetch_modules(gold, GOLD_DB))
        registry = fetch_registry(processing)

    registry_by_project: dict[str, list[dict[str, object]]] = defaultdict(list)
    for row in registry:
        registry_by_project[str(row["project"])].append(row)

    shared_seeds: set[Obj] = set()
    for row in registry_by_project.get(SHARED_PROJECT, []):
        parsed = parse_legacy_view_name(row.get("legacy_view_name"))
        if parsed:
            obj = obj_for_schema(*parsed)
            if obj:
                shared_seeds.add(obj)
    shared_closure = live_closure(shared_seeds, modules)

    artifact_dir = ROOT / "01_docs" / "runbook" / "artifacts" / SCAN_ID
    artifact_dir.mkdir(parents=True, exist_ok=True)

    summary: dict[str, object] = {
        "scan_id": SCAN_ID,
        "generated_at_utc": datetime.now(timezone.utc).isoformat(),
        "server": SERVER,
        "processing_db": PROCESSING_DB,
        "gold_db": GOLD_DB,
        "projects": {},
    }

    for project in PROJECTS:
        seeds: set[Obj] = set()
        active_registry_objects: list[str] = []
        for obj in modules:
            if obj.db == GOLD_DB and obj.schema in PROJECT_GOLD_SCHEMAS.get(project, set()):
                seeds.add(obj)
                active_registry_objects.append(obj.full)
        for row in registry_by_project.get(project, []):
            parsed = parse_legacy_view_name(row.get("legacy_view_name"))
            if not parsed:
                continue
            obj = obj_for_schema(*parsed)
            if obj:
                seeds.add(obj)
                active_registry_objects.append(obj.full)

        closure = live_closure(seeds, modules)

        # Include shared Gold views when this mart uses Shared_DW tables in active code.
        uses_shared = any(
            any(ref.schema == "Shared_DW" for ref in refs_from_definition(modules[obj]))
            for obj in closure
            if obj in modules
        )
        if uses_shared:
            closure |= shared_closure

        expected_paths: dict[Path, Obj] = {}
        changed_sql: list[str] = []
        for obj in sorted(closure, key=lambda x: x.full.lower()):
            path = path_for_obj(project, obj)
            if not path:
                continue
            expected_paths[path] = obj
            if obj in modules and write_sql(path, modules[obj]):
                changed_sql.append(str(path))

        external_sources: set[Obj] = set()
        internal_source_notes: set[Obj] = set()
        for obj in closure:
            definition = modules.get(obj)
            if not definition:
                continue
            for ref in refs_from_definition(definition):
                if ref.db in EXTERNAL_DBS:
                    external_sources.add(ref)
                elif path_for_source_note(project, ref):
                    internal_source_notes.add(ref)

        changed_source_notes: list[str] = []
        for ref in sorted(internal_source_notes, key=lambda x: x.full.lower()):
            path = path_for_source_note(project, ref)
            if path:
                expected_paths[path] = ref
                if write_source_note(path, ref, project):
                    changed_source_notes.append(str(path))

        moved_sql: list[str] = []
        for path in active_sql_files(project):
            if path.name == "README.md":
                continue
            if path not in expected_paths:
                moved_path = move_to_history(path, project, "sql_object_not_in_live_active_closure")
                moved_sql.append(f"{path} -> {moved_path}")

        bronze_result = sync_bronze(project, external_sources)

        registry_source_refs: set[str] = set()
        for row in registry_by_project.get(project, []):
            registry_source_refs |= refs_from_registry_source_objects(row.get("source_objects"))
        code_source_refs = {obj.full for obj in external_sources}
        stale_registry_source_refs = sorted(
            ref for ref in registry_source_refs
            if "_1." in ref or any(part.endswith("_1") for part in ref.split("."))
        )

        project_summary = {
            "active_registry_seed_objects": sorted(active_registry_objects),
            "live_closure_objects": sorted(obj.full for obj in closure),
            "live_external_sources_from_code": sorted(obj.full for obj in external_sources),
            "live_internal_source_notes_from_code": sorted(obj.full for obj in internal_source_notes),
            "registry_source_refs_with_suffix_1": stale_registry_source_refs,
            "code_external_refs_with_suffix_1": sorted(
                ref for ref in code_source_refs
                if "_1." in ref or any(part.endswith("_1") for part in ref.split("."))
            ),
            "changed_sql_files": changed_sql,
            "changed_source_note_files": changed_source_notes,
            "moved_sql_files": moved_sql,
            "changed_bronze_files": bronze_result["changed"],
            "moved_bronze_files": bronze_result["moved"],
        }
        summary["projects"][project] = project_summary

        (artifact_dir / f"{project}_live_closure.json").write_text(
            json.dumps(project_summary, indent=2, sort_keys=True),
            encoding="utf-8",
        )

    (artifact_dir / "summary.json").write_text(
        json.dumps(summary, indent=2, sort_keys=True),
        encoding="utf-8",
    )

    lines = [
        "# Live Mart Layer Scan — 2026-06-23\n\n",
        "Source of truth: active `Meta.AssetRegistry` rows plus current live `sys.sql_modules.definition` code in Processing/Gold warehouses.\n\n",
    ]
    for project, data in summary["projects"].items():
        assert isinstance(data, dict)
        lines.append(f"## {project}\n\n")
        lines.append("### Live External Sources From Code\n\n")
        for source in data["live_external_sources_from_code"]:
            lines.append(f"- `{source}`\n")
        lines.append("\n### Live Internal Source Notes From Code\n\n")
        for source in data["live_internal_source_notes_from_code"]:
            lines.append(f"- `{source}`\n")
        lines.append("\n### `_1` Suffix Check\n\n")
        code_suffix = data["code_external_refs_with_suffix_1"]
        registry_suffix = data["registry_source_refs_with_suffix_1"]
        if code_suffix:
            lines.append("Active code refs with `_1` suffix:\n")
            for source in code_suffix:
                lines.append(f"- `{source}`\n")
        else:
            lines.append("- Active code refs with `_1` suffix: none.\n")
        if registry_suffix:
            lines.append("- Registry metadata refs with `_1` suffix:\n")
            for source in registry_suffix:
                lines.append(f"  - `{source}`\n")
        else:
            lines.append("- Registry metadata refs with `_1` suffix: none.\n")
        lines.append("\n### Live Closure Objects\n\n")
        for obj in data["live_closure_objects"]:
            lines.append(f"- `{obj}`\n")
        lines.append("\n")
    (artifact_dir / "live_mart_layer_scan.md").write_text("".join(lines), encoding="utf-8")

    print(json.dumps(summary, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
