from __future__ import annotations

import json
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[3]


class ForecastDqContractTests(unittest.TestCase):
    def test_forecast_gold_proc_inserts_dq_history(self) -> None:
        sql_path = REPO_ROOT / "03_operations" / "orchestration" / "forecast_accuracy" / "sql" / "SupplyChain_Gold_Warehouse.dbo.Usp_Refresh_ForecastAccuracy_Gold.sql"
        sql_text = sql_path.read_text(encoding="utf-8")
        self.assertIn("INSERT INTO [ForecastAccuracy_DW].[DQForecastAccuracy]", sql_text)
        self.assertIn("FROM [ForecastAccuracy_DW_Wrk].[v_DQForecastAccuracy]", sql_text)

    def test_dq_view_exposes_etl_load_timestamp(self) -> None:
        sql_path = REPO_ROOT / "02_marts" / "forecast_accuracy" / "03_gold" / "ForecastAccuracy_DW_Wrk" / "v_DQForecastAccuracy.sql"
        sql_text = sql_path.read_text(encoding="utf-8")
        self.assertIn("run_meta AS", sql_text)
        self.assertIn("rm.DQRunAtUTC AS LoadDT", sql_text)
        self.assertIn("CROSS JOIN run_meta AS rm", sql_text)

    def test_dq_object_is_registered_in_lineage_catalog(self) -> None:
        assets_path = REPO_ROOT / "02_marts" / "forecast_accuracy" / "05_catalog" / "assets.json"
        run_order_path = REPO_ROOT / "02_marts" / "forecast_accuracy" / "05_catalog" / "run_order.json"
        edges_path = REPO_ROOT / "02_marts" / "forecast_accuracy" / "05_catalog" / "lineage_edges.json"
        assets = json.loads(assets_path.read_text(encoding="utf-8"))
        run_order = json.loads(run_order_path.read_text(encoding="utf-8"))
        edges = json.loads(edges_path.read_text(encoding="utf-8"))
        serialized_assets = json.dumps(assets)
        serialized_run_order = json.dumps(run_order)
        self.assertIn("ForecastAccuracy_DW.DQForecastAccuracy", serialized_assets)
        self.assertIn("ForecastAccuracy_DW_Wrk.v_DQForecastAccuracy", serialized_assets)
        self.assertIn("ForecastAccuracy_DW.DQForecastAccuracy", serialized_run_order)
        self.assertIn(
            {
                "edge_type": "direct_sql_insert_materializes_final_table",
                "evidence_file": "03_operations/orchestration/forecast_accuracy/sql/SupplyChain_Gold_Warehouse.dbo.Usp_Refresh_ForecastAccuracy_Gold.sql",
                "source": "ForecastAccuracy_DW_Wrk.v_DQForecastAccuracy",
                "source_asset_key": "forecastaccuracy.dw.wrk.v.dqforecastaccuracy",
                "target": "ForecastAccuracy_DW.DQForecastAccuracy",
                "target_asset_key": "forecastaccuracy.dw.dqforecastaccuracy",
            },
            edges["edges"],
        )


if __name__ == "__main__":
    unittest.main()
