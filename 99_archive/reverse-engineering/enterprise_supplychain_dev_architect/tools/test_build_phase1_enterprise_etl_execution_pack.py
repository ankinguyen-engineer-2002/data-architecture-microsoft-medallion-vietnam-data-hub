from __future__ import annotations

import importlib.util
import sys
import unittest
from pathlib import Path


MODULE_PATH = Path(__file__).with_name("build_phase1_enterprise_etl_execution_pack.py")
SPEC = importlib.util.spec_from_file_location("build_phase1_enterprise_etl_execution_pack", MODULE_PATH)
MODULE = importlib.util.module_from_spec(SPEC)
assert SPEC and SPEC.loader
sys.modules[SPEC.name] = MODULE
SPEC.loader.exec_module(MODULE)


class BuildPhase1enterprise_etlExecutionPackTests(unittest.TestCase):
    def test_normalize_dependencies_rewrites_incremental_commands(self) -> None:
        manifest_rows = [
            {
                "run_sequence": "1",
                "layer": "Staging",
                "project": "shared",
                "wave_number": "",
                "database_name": "SupplyChain_Processing_Warehouse",
                "schema_name": "Staging",
                "object_name": "DemandForecastSnapshotDaily",
                "asset_id": "Staging.DemandForecastSnapshotDaily",
                "depends_on": "",
                "source_objects": '["Enterprise_Lakehouse.SupplyChain_Enh.DemandForecastSnapshotDaily"]',
                "enterprise_etl_exec_command": "PENDING_Enterprise ETL_INCREMENTAL_PATH::SupplyChain_Processing_Warehouse.Staging.DemandForecastSnapshotDaily",
                "is_manual_run_enabled": "False",
                "load_type": "incremental",
                "wave_found": "False",
            },
            {
                "run_sequence": "2",
                "layer": "DomainSilver",
                "project": "forecast_accuracy",
                "wave_number": "0",
                "database_name": "SupplyChain_Processing_Warehouse",
                "schema_name": "ForecastHistory_Enh",
                "object_name": "ForecastDemandMonthly",
                "asset_id": "ForecastHistory_Enh.ForecastDemandMonthly",
                "depends_on": "",
                "source_objects": '["Staging_Wrk.DemandForecastSnapshotDaily","ReferenceMaster_Enh.ForecastCycle"]',
                "enterprise_etl_exec_command": "EXEC DW_Developer.usp_RefreshCuratedTableFromView 'SupplyChain_Processing_Warehouse', 'ForecastHistory_Enh', 'ForecastDemandMonthly'",
                "is_manual_run_enabled": "True",
                "load_type": "overwrite",
                "wave_found": "True",
            },
            {
                "run_sequence": "3",
                "layer": "DomainSilver",
                "project": "inventory_health",
                "wave_number": "1",
                "database_name": "SupplyChain_Processing_Warehouse",
                "schema_name": "InventoryHistory_Enh",
                "object_name": "HoldingTransferSnapshotDaily",
                "asset_id": "InventoryHistory_Enh.HoldingTransferSnapshotDaily",
                "depends_on": "",
                "source_objects": '["InventoryHistory_Enh_Wrk.v_HoldingTransferSnapshotDaily"]',
                "enterprise_etl_exec_command": "EXEC DW_Developer.usp_RefreshCuratedTableFromView 'SupplyChain_Processing_Warehouse', 'InventoryHistory_Enh', 'HoldingTransferSnapshotDaily'",
                "is_manual_run_enabled": "True",
                "load_type": "datekey",
                "wave_found": "True",
            },
            {
                "run_sequence": "4",
                "layer": "DomainSilver",
                "project": "inventory_health",
                "wave_number": "1",
                "database_name": "SupplyChain_Processing_Warehouse",
                "schema_name": "InventoryHistory_Enh",
                "object_name": "ManufacturingOrderSnapshotDaily",
                "asset_id": "InventoryHistory_Enh.ManufacturingOrderSnapshotDaily",
                "depends_on": "",
                "source_objects": '["InventoryHistory_Enh_Wrk.v_ManufacturingOrderSnapshotDaily"]',
                "enterprise_etl_exec_command": "EXEC DW_Developer.usp_RefreshCuratedTableFromView 'SupplyChain_Processing_Warehouse', 'InventoryHistory_Enh', 'ManufacturingOrderSnapshotDaily'",
                "is_manual_run_enabled": "True",
                "load_type": "datekey",
                "wave_found": "True",
            },
        ]

        normalized_rows, _ = MODULE.normalize_dependencies(manifest_rows)
        by_asset = {row["asset_id"]: row for row in normalized_rows}

        self.assertEqual(
            by_asset["Staging.DemandForecastSnapshotDaily"]["enterprise_etl_exec_command"],
            "EXEC DW_Developer.usp_IncrementalTableLoad 'SupplyChain_Processing_Warehouse', 'Staging', 'DemandForecastSnapshotDaily', 'NULL'",
        )
        self.assertEqual(by_asset["Staging.DemandForecastSnapshotDaily"]["schema_name"], "Staging")
        self.assertEqual(
            by_asset["Staging.DemandForecastSnapshotDaily"]["source_objects"],
            '["Staging_Wrk.v_DemandForecastSnapshotDaily"]',
        )
        self.assertEqual(
            by_asset["ForecastHistory_Enh.ForecastDemandMonthly"]["source_objects"],
            '["Staging.DemandForecastSnapshotDaily","ReferenceMaster_Enh.ForecastCycle"]',
        )
        self.assertEqual(
            by_asset["InventoryHistory_Enh.HoldingTransferSnapshotDaily"]["enterprise_etl_exec_command"],
            "EXEC DW_Developer.usp_IncrementalTableLoad 'SupplyChain_Processing_Warehouse', 'InventoryHistory_Enh', 'HoldingTransferSnapshotDaily', 'NULL'",
        )
        self.assertEqual(
            by_asset["InventoryHistory_Enh.ManufacturingOrderSnapshotDaily"]["enterprise_etl_exec_command"],
            "EXEC DW_Developer.usp_IncrementalTableLoad 'SupplyChain_Processing_Warehouse', 'InventoryHistory_Enh', 'ManufacturingOrderSnapshotDaily', 'NULL'",
        )

    def test_build_manual_run_artifacts_orders_sections_and_keeps_disabled_execs_out(self) -> None:
        manifest_rows = [
            {
                "run_sequence": "1",
                "layer": "LogicalBronze",
                "project": "forecast_accuracy",
                "wave_number": "",
                "database_name": "Enterprise_Lakehouse",
                "schema_name": "bronze",
                "object_name": "brz_example",
                "asset_id": "Enterprise_Lakehouse.bronze.brz_example",
                "depends_on": "",
                "source_objects": "",
                "enterprise_etl_exec_command": "REGISTER_ONLY::Enterprise_Lakehouse.bronze.brz_example",
                "is_manual_run_enabled": "True",
                "load_type": "overwrite",
                "wave_found": "False",
            },
            {
                "run_sequence": "2",
                "layer": "Staging",
                "project": "shared",
                "wave_number": "",
                "database_name": "SupplyChain_Processing_Warehouse",
                "schema_name": "Staging",
                "object_name": "DemandForecastSnapshotDaily",
                "asset_id": "Staging.DemandForecastSnapshotDaily",
                "depends_on": "",
                "source_objects": "",
                "enterprise_etl_exec_command": "EXEC DW_Developer.usp_IncrementalTableLoad 'SupplyChain_Processing_Warehouse', 'Staging', 'DemandForecastSnapshotDaily', 'NULL'",
                "is_manual_run_enabled": "False",
                "load_type": "incremental",
                "wave_found": "False",
            },
            {
                "run_sequence": "3",
                "layer": "DomainSilver",
                "project": "forecast_accuracy",
                "wave_number": "0",
                "database_name": "SupplyChain_Processing_Warehouse",
                "schema_name": "ForecastHistory_Enh",
                "object_name": "ForecastDemandMonthly",
                "asset_id": "ForecastHistory_Enh.ForecastDemandMonthly",
                "depends_on": "",
                "source_objects": "",
                "enterprise_etl_exec_command": "EXEC DW_Developer.usp_RefreshCuratedTableFromView 'SupplyChain_Processing_Warehouse', 'ForecastHistory_Enh', 'ForecastDemandMonthly'",
                "is_manual_run_enabled": "True",
                "load_type": "overwrite",
                "wave_found": "True",
            },
            {
                "run_sequence": "4",
                "layer": "Gold",
                "project": "forecast_accuracy",
                "wave_number": "",
                "database_name": "SupplyChain_Gold_Warehouse",
                "schema_name": "ForecastAccuracy_DW",
                "object_name": "FactForecastActual",
                "asset_id": "ForecastAccuracy_DW.FactForecastActual",
                "depends_on": "ForecastHistory_Enh.ForecastDemandMonthly",
                "source_objects": "",
                "enterprise_etl_exec_command": "EXEC DW_Developer.usp_RefreshCuratedTableFromView 'SupplyChain_Gold_Warehouse', 'ForecastAccuracy_DW', 'FactForecastActual'",
                "is_manual_run_enabled": "True",
                "load_type": "overwrite",
                "wave_found": "False",
            },
        ]

        artifacts = MODULE.build_manual_run_artifacts(manifest_rows, "phase1_manual_refresh_manifest_v2")

        self.assertIn("phase1g_manual_refresh_all.sql", artifacts)
        all_sql = artifacts["phase1g_manual_refresh_all.sql"]

        self.assertLess(all_sql.index("Bronze / Reference"), all_sql.index("Silver Wave 0"))
        self.assertLess(all_sql.index("Silver Wave 0"), all_sql.index("Gold"))
        self.assertNotIn(
            "EXEC DW_Developer.usp_IncrementalTableLoad 'SupplyChain_Processing_Warehouse', 'Staging', 'DemandForecastSnapshotDaily', 'NULL'",
            all_sql,
        )
        self.assertIn("approval required before heavy incremental catch-up", all_sql)


if __name__ == "__main__":
    unittest.main()
