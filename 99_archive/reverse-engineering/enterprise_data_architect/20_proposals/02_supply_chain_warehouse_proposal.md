# `SupplyChain_Warehouse` — Proposal to create new domain warehouse in `EnterpriseData-Dev`

> **Author**: Aric Nguyen, VN SC team lead DE · **Date**: 2026-05-10 · **Status**: Pending Bob's review

## Context

Per Bob Horton's email reply 2026-05-09:

> "Tables like Forecasts would likely also be needed across several value streams so I would expect to see some forecast data in a clean state within the **SupplyChain_Warehouse in EnterpriseData (silver layer)**."

Currently `EnterpriseData-Dev` workspace does NOT have a `SupplyChain_Warehouse`. Existing siblings:

| Existing domain WH | Owner |
|--------------------|-------|
| `Wholesale_Warehouse` | Wholesale value-stream team |
| `Retail_Warehouse` | Retail value-stream team |
| `MasterData_Warehouse` | MasterData / central team |
| `Distribution_Warehouse` | Distribution team (incomplete) |
| `Quality_Warehouse` | TBD (empty shell) |

Bob's pattern: **each domain Silver WH is owned by the value-stream team that builds data products on it**. SC team currently owns:
- `Enterprise SupplyChain-Dev` (value-stream workspace) — Gold + Semantic + SC-specific Silver
- v8 legacy `SupplyChain_Lakehouse` + `SupplyChain_Warehouse` (`e146ffe2-...`, Cherry's Control Tower upstream)

**Missing**: SC team's contribution to enterprise hub — a `SupplyChain_Warehouse` for shared Silver (forecast data).

## Proposal

### Create `SupplyChain_Warehouse` in `EnterpriseData-Dev` hub

**Sibling to**: `Wholesale_Warehouse`, `Retail_Warehouse`, `MasterData_Warehouse`.

**Owner**: VN SC team (Aric primary, Cherry secondary).

**Permission model**: Scoped Contributor on specific schema(s) only — VN team writes within designated SC slot, cannot touch other schemas in the same WH.

### Initial schemas

Following Bob's existing convention (see [naming conventions analysis](03_naming_conventions.md)):

| Option A: single schema (mirror `Retail_Sales_Enh`) | Option B: split (mirror Wholesale + MasterData) |
|------------------------------------------------------|---------------------------------------------------|
| `SupplyChain_Warehouse.Forecast_Enh` containing:<br>• ForecastDemandMonthly (42M)<br>• NaiveForecastMonthly (2M)<br>• ForecastCycle (43)<br>• ForecastHorizon (8) | `SupplyChain_Warehouse.Forecast_Enh`:<br>• ForecastDemandMonthly<br>• NaiveForecastMonthly<br><br>`MasterData_Warehouse.MasterData_DW` (extend existing):<br>• DimForecastCycle (NEW)<br>• DimForecastHorizon (NEW) |

VN team **defers naming choice to Bob's preference**.

### Naming alignment (Bob convention evidence-verified)

| Pattern | Bob's evidence | SC application |
|---------|----------------|----------------|
| Domain canonical | `SalesHistory_AFI`, `Customers`, `Marketing` | `Forecast` (canonical) — likely too plain |
| Enhanced tier | `Retail_Sales_Enh`, `MasterData_HR_UKG_Enh` | `Forecast_Enh` ✅ |
| Source-system tagged | `SalesHistory_AFI`, `CustomerOrders_AFI` | N/A — forecast not from AFI/AS400 |
| Dim/Fact pattern | `MasterData_DW.DimDate`, `DimItemMaster` | `SupplyChain_DW.DimForecastCycle` (Option B) |
| Working set | `*_Wrk` | `Forecast_Enh_Wrk` for views |

**No `Dim/Fact` prefix on Forecast tables** unless schema is `_DW`-style — verified across all Silver WHs.

### What lives where

```
🇺🇸 EnterpriseData-Dev.SupplyChain_Warehouse  (NEW — VN team builds here)
└── Forecast_Enh
    ├── ForecastDemandMonthly      (42M, derived from Source_Data.SupplyChain_Enh raw)
    ├── NaiveForecastMonthly       (2M, derived from ActualDemand baseline)
    └── ForecastCycle              (43, reference)
    └── ForecastHorizon            (8, reference dictionary)

🇻🇳 Enterprise SupplyChain-Dev.SupplyChain_Processing_Warehouse  (VN-owned)
└── SupplyChain_Enh                (8 tables — SC-specific business logic)
    ├── ActualDemandMonthly        (2.66M, lead-time offset + AFICONS cutoff)
    ├── ActualDemandWeekly         (7.89M)
    ├── InvoiceWeekly              (37.7M, SC aggregation grain)
    ├── OpenOrderLineLevel         (175K, possibly retire if Wholesale.CustomerOrders_AFI matches)
    ├── OpenOrderMonthly           (73K)
    ├── CustomerAccountGroup       (35K, Wholesale-derived grouping)
    ├── CustomerGrouping           (35K)

🇻🇳 Enterprise SupplyChain-Dev.SupplyChain_Gold_Warehouse  (VN-owned)
└── ForecastAccuracy_DW            (5 Dim + 2 Fact star schema)

🇻🇳 Enterprise SupplyChain-Dev (semantic + reports)
└── sc_forecast_control_tower      (Direct Lake on Gold)
```

## Permission scoping (proposal)

| Role | 🇺🇸 `EnterpriseData-Dev` | 🇻🇳 `Enterprise SupplyChain-Dev` |
|------|---------------------------|-----------------------------------|
| Bob/Rakesh (US Enterprise) | Admin | Viewer (audit) |
| **Aric, Cherry (VN SC)** | **Scoped Contributor on `SupplyChain_Warehouse.Forecast_Enh` (and `SupplyChain_DW` if Option B)** + Viewer everywhere else | Admin |
| Wholesale/Retail teams | Admin on respective domain WH | (no access) |

VN team's write scope **deliberately narrow**: only the SC slot. Cannot write to `MasterData_Warehouse`, `Wholesale_Warehouse`, `ETL_Framework`, etc.

## Build process (post-creation)

1. Bob's team creates `SupplyChain_Warehouse` empty WH in hub
2. Bob's team creates schemas `Forecast_Enh` (+ `Forecast_Enh_Wrk` for views, + `SupplyChain_DW` if Option B)
3. Bob/Rakesh grants VN team Contributor on those schemas only
4. VN team gets ADO access to `Enterprise Data Services/Fabric-EnterpriseData` repo
5. VN team writes:
   - View DDLs in repo under `SupplyChain_Warehouse/Forecast_Enh_Wrk/`
   - INSERT into Bob's `TableDictionary` for new tables
   - Refresh wrapper proc `Usp_Refresh_SupplyChain_Warehouse` (mirror Wholesale/Retail pattern)
6. VN team raises PR → Rakesh/Ankit review → merge → auto-deploy via Fabric Git sync
7. VN's pipeline (in VN workspace) cross-DB calls `EXEC EnterpriseData-Dev.ETL_Framework.DW_Developer.usp_RefreshCuratedTableFromView 'SupplyChain_Warehouse', 'Forecast_Enh', 'ForecastDemandMonthly'`

## Migration of existing forecast Silver

Currently in `Enterprise SupplyChain-Dev.SupplyChain_Processing_Warehouse.ForecastHistory_Enh`:
- `ForecastDemandMonthly` (42M rows)
- `NaiveForecastMonthly` (2M rows)

Migration steps after WH creation:
1. Run `pl_sc_master` once with new target → loads to hub `SupplyChain_Warehouse.Forecast_Enh.*`
2. Verify row counts match
3. Update VN's `Meta.AssetRegistry.physical_workspace` for these 2 assets to point to hub WS ID
4. Update VN's Gold views (`vw_FactForecastActual`, `vw_FactForecastKpi`) to read from hub via 3-part name
5. Drop local copies in VN workspace
6. Verify pipeline + semantic model still work

Estimated effort: 1-2 days post-permission unblock.

## Risks + mitigations

| Risk | Mitigation |
|------|-----------|
| Cross-DB write latency for VN pipeline calling Bob hub SP | Acceptable — pipeline already cross-WH (Processing → Gold); adding hub is incremental |
| Permission scope creep over time | Quarterly review, audit Contributor role assignments |
| Drift between VN local registry and Bob hub TableDictionary | `usp_LogRun v2` cross-DB sync (per ADR-008) keeps in sync per-load |
| Schema name disagreement with Bob's team | Defer naming choice to Bob's preference (Option A vs B) |
| Failed cross-DB call breaks pipeline | Local fallback: log error to Meta.AuditLog, continue rest of pipeline (already implemented retry pattern in `usp_LogRun`) |

## Acceptance criteria

- [ ] Bob/Rakesh approve the proposal
- [ ] WH created with named schemas
- [ ] VN team granted Contributor on designated schemas
- [ ] ADO access granted (`Enterprise Data Services` project)
- [ ] First test load: `ForecastDemandMonthly` 1k rows from VN pipeline → hub WH success
- [ ] Bob's `TableDictionary` shows VN registered table
- [ ] Bob's team can query data from `Centralized_Lakehouse` shortcut

## Cross-refs

- ADR-005 v2 (US/VN promote pathway): [`../../docs/decisions/ADR-005-enterprise-promote-pathway.md`](../../docs/decisions/ADR-005-enterprise-promote-pathway.md)
- Naming conventions analysis: [`03_naming_conventions.md`](03_naming_conventions.md)
- Open questions tracker: [`../../Enterprise_SupplyChain_Dev_architect/projects/forecast/_open_questions_for_bob.md`](../../Enterprise_SupplyChain_Dev_architect/projects/forecast/_open_questions_for_bob.md)
