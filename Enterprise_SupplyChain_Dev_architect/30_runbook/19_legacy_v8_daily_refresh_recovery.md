# 19 — Legacy v8 Daily Refresh Recovery

> Last verified: 2026-06-02 via Fabric REST API, Power BI REST API, SQL endpoint, and semantic DAX smoke. Scope is legacy v8 only; v10 `pl_sc_*`, `SupplyChain_Gold_Warehouse`, and v10 semantic models were not changed.

## Purpose

This runbook records the 2026-06-02 recovery of the legacy v8 `Supply Chain Control Tower` refresh path. The goal was to keep the old v8 report operational while v10 remains separate.

## Fabric Items

| Item | Value |
|---|---|
| Workspace | `c8d9fc83-18b6-4e1d-8264-0b49eed36fe0` |
| Legacy lakehouse | `SupplyChain_Lakehouse` |
| Legacy warehouse / SQL endpoint DB | `SupplyChain_Warehouse` |
| SQL endpoint | `7woj2wroypauvkpn72b56t46ju-qp6ntsfwdaou5atebne65u3p4a.datawarehouse.fabric.microsoft.com` |
| Legacy semantic model | `Supply Chain Control Tower` |
| Legacy semantic model ID | `3eecf594-a75e-46ab-9162-63c95ee68e45` |
| Legacy report | `Forecast Accuracy Gold` |

## Legacy v8 Pipeline Chain

```text
pl_master_daily
  -> pl_brz_daily
  -> pl_slv_daily
  -> pl_gld_daily
  -> pl_sp_daily_v2
  -> Supply Chain Control Tower semantic refresh / Direct Lake framing
```

| Pipeline | ID | Latest verified state |
|---|---|---|
| `pl_master_daily` | `4214332e-392f-4d2e-ac11-99094ac33aa7` | Completed |
| `pl_brz_daily` | `e388c9ef-f067-4e95-91b2-961436b8a683` | Completed |
| `pl_slv_daily` | `188d52f4-ff31-4459-904d-ea3a6e89b87f` | Completed |
| `pl_gld_daily` | `8a8fabf1-634e-4705-9909-929b5b451438` | Completed |
| `pl_sp_daily_v2` | `1acd2d5d-6406-4a5c-94bd-848adca3d848` | Completed |

## Root Cause Fixed

Two v8 Bronze notebooks still referenced retired source paths under `Enterprise_Lakehouse/Tables/SupplyChain_DW`:

| Notebook | Retired source | Replacement |
|---|---|---|
| `nb_ref_warehouse` | `SupplyChain_DW/DimAFIWarehouses` | `CustomerOrders_AFI/WarehouseMaster` plus legacy 55-warehouse mapping contract |
| `nb_ref_product` | `SupplyChain_DW/DimCurrentProductDetails` | `SupplyChain_Lakehouse.dbo.ref_product_ver2` supplement, cast/reordered into legacy `ref_product` schema |

Backups and live definition snapshots are stored under:

```text
Enterprise_SupplyChain_Dev_architect/artifacts/v8_hotfix_warehouse_source_20260602/
Enterprise_SupplyChain_Dev_architect/artifacts/v8_hotfix_product_source_20260602/
```

## Full Run Evidence

Latest verified `pl_master_daily` run:

| Field | Value |
|---|---|
| Run instance | `255c243b-2260-4a44-93a5-a30ea0c3ab0b` |
| Invoke type | Manual |
| Status | Completed |
| Start UTC | `2026-06-02T08:49:26.8178242` |
| End UTC | `2026-06-02T09:13:06.7218901` |
| Runtime | About 23m 40s |

Child pipeline completion evidence:

| Pipeline | Run instance | Start UTC | End UTC |
|---|---|---|---|
| `pl_brz_daily` | `88bdccb2-3c5e-4a5d-8504-a7221ca50d73` | `2026-06-02T08:49:44.2489963` | `2026-06-02T08:51:28.9255571` |
| `pl_slv_daily` | `2f456f5d-aea0-4d88-bf5f-799ee7e32092` | `2026-06-02T08:55:10.7618829` | `2026-06-02T08:55:53.971895` |
| `pl_gld_daily` | `94424d35-b876-46a4-b90a-fff10d60b687` | `2026-06-02T08:56:33.2711446` | `2026-06-02T09:04:04.7079608` |
| `pl_sp_daily_v2` | `24825c83-6ed8-4b4f-af3d-0cd187e46ffd` | `2026-06-02T09:07:17.0915929` | `2026-06-02T09:09:25.8787254` |

## Semantic Evidence

Latest legacy semantic refresh history:

| Refresh type | Request ID | Start UTC | End UTC | Status |
|---|---|---|---|---|
| DirectLakeFraming | `258f930d-332a-41bc-8743-18478e01ce28` | `2026-06-02T09:09:52Z` | `2026-06-02T09:09:55.097Z` | Completed |
| DataFactory | `a5325e71-a8b2-46e9-97d5-a605e40b5a4c` | `2026-06-02T09:12:29.253Z` | `2026-06-02T09:12:33.257Z` | Completed |

Earlier Direct Lake framing failures during the same run were transient while Gold/SP materialization was still replacing tables. The final refresh attempts completed.

Power BI `executeQueries` smoke test against `Supply Chain Control Tower`:

```text
fact_forecast_kpi rows          = 37,225,012
fact_flat_forecast_actual rows  = 51,015,312
Max dt_snapshot                 = 2026-05-16
Max KPI fiscal month first      = 2027-04-25
Max actual fiscal month first   = 2027-04-25
Updated-card probe date         = 2026-05-24
```

The old report screenshot showing `4/26/2026` was not proof of stale ETL after recovery. The current probe returns `2026-05-24`; the displayed value is driven by the report's fiscal-month visual logic, not by Fabric pipeline job time.

## Metadata Registry State

Legacy v8 registry table: `SupplyChain_Lakehouse.dbo.utl_pipeline_metadata`.

Verified active rows after the successful run:

| Layer/order | Active rows | Next run |
|---|---:|---|
| `BRZ`, order 1 | 8 | `2026-06-03 02:00:00` |
| `REF`, order 1 | 8 | `2026-06-03 02:00:00` |
| `SLV`, order 2 | 3 | `2026-06-03 02:00:00` |
| `SLV`, order 3 | 4 | `2026-06-03 02:00:00` |
| `SLV`, order 4 | 1 | `2026-06-03 02:00:00` |
| `GLD`, order 5 | 2 | `2026-06-03 03:00:00` |

One inactive legacy row remains by design:

```text
ref_customer_shipping_location | REF | is_active = 0
```

## Daily Schedule

The existing disabled schedule on `pl_master_daily` was reused and updated. No duplicate schedule was created.

| Field | Value |
|---|---|
| Schedule ID | `8667733d-625c-4b7f-8dca-19816c7b0775` |
| Enabled | `true` |
| Type | Daily |
| Time zone | `SE Asia Standard Time` |
| Times | `02:00` |
| Start | `2026-06-03T00:00:00` |
| End | `2099-01-01T23:59:00` |

## Verification Commands

List v8 master schedule:

```bash
az rest --method GET \
  --resource https://api.fabric.microsoft.com \
  --url "https://api.fabric.microsoft.com/v1/workspaces/c8d9fc83-18b6-4e1d-8264-0b49eed36fe0/items/4214332e-392f-4d2e-ac11-99094ac33aa7/jobs/Pipeline/schedules"
```

List latest v8 master job instances:

```bash
az rest --method GET \
  --resource https://api.fabric.microsoft.com \
  --url "https://api.fabric.microsoft.com/v1/workspaces/c8d9fc83-18b6-4e1d-8264-0b49eed36fe0/items/4214332e-392f-4d2e-ac11-99094ac33aa7/jobs/instances"
```

List legacy semantic refreshes:

```bash
az rest --method GET \
  --resource https://analysis.windows.net/powerbi/api \
  --url "https://api.powerbi.com/v1.0/myorg/groups/c8d9fc83-18b6-4e1d-8264-0b49eed36fe0/datasets/3eecf594-a75e-46ab-9162-63c95ee68e45/refreshes?\$top=10"
```

## Operational Rule

Do not use this v8 recovery path to mutate v10. The v10 operational path remains under:

```text
SupplyChain_Processing_Warehouse
SupplyChain_Gold_Warehouse
pl_sc_master / pl_sc_mart / pl_sc_staging / pl_sc_silver / pl_sc_gold
sc_forecast_control_tower
sc_inventory_health_control_tower
```
