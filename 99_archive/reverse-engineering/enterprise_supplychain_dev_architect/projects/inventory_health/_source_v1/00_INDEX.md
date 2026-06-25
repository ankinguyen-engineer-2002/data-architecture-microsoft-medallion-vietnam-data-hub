# Inventory Health — Deliverable Bundle v1

**Owner**: Aric Nguyen — Data Analytics Team, Ashley Furniture
**Date packaged**: 2026-05-18
**Status**: Track A code fixes applied. NOT deployed to production. Awaiting Robert sign-off + DE data load.

---

## What this folder contains

This is a self-contained handoff bundle for the Inventory Health ETL + Semantic Model project. Everything needed to review, deploy, or hand off the work is here. No external repo lookups required.

```
Deliverable_InventoryHealth_v1_2026-05-18/
├── 00_INDEX.md              ← you are here
├── 04_TRACK_A_FIXES.md      ← formal log of 14 code fixes applied
├── 05_NEXT_STEPS.md         ← roadmap: Track B/C/D/E + open dependencies
│
├── 01_docs/
│   ├── 01_MASTER_PLAN.md    ← Bronze→Silver→Gold architecture, KPI map, tier plan
│   ├── 02_QC_REPORT.md      ← 18 bugs identified during 2-person review (5H+6M+7L)
│   └── 03_BRONZE_STATUS.md  ← 32-source probe results, gap analysis, sign-off status
│
├── sql/                     ← T-SQL ETL pipeline (Fabric Warehouse)
│   ├── 01_setup.sql              schemas + watermark table
│   ├── 02_silver_dims.sql        ItemMaster, Warehouse, Vendor [B3 applied]
│   ├── 03_silver_base.sql        14 base procs + 2 Tier-2 snapshots [H1/H2/H3/B1/B2 applied]
│   ├── 04_silver_helpers.sql     AWD, LastInvoice, MovementFlag, SafetyStock helpers
│   ├── 05_silver_snapshots.sql   PO/MO/Hold daily + Logility weekly capture
│   ├── 06_gold_dims.sql          DimDate, DimItem, DimWarehouse, DimVendor, DimRuleVersion
│   ├── 07_gold_helpers.sql       CogsRollingHelper (Cogs52M trailing) [H4/M3 applied]
│   ├── 08_gold_facts.sql         FactInventoryHealthSnapshot + FactInventoryRiskForward [H5/M3/M4 applied]
│   ├── 09_master.sql             silver.usp_RefreshAll + gold.usp_RefreshAll [M1 applied]
│   ├── 10_verify.sql             Smoke tests + KPI sample queries [M2/M3 applied]
│   ├── 99_cleanup_silver.sql     DROP all silver objects (post dev test)
│   └── 99_cleanup_gold.sql       DROP all gold objects (post dev test)
│
├── 04_semantic/                ← Power BI semantic model
│   ├── SemanticModel.tmdl   5 Dim + 2 Fact + 9 relationships [M3 applied]
│   └── Measures_DAX.dax     30+ DAX measures mapped to 30 BRD KPIs [M5/M3 applied]
│
└── reference/               ← background docs (read-only inputs)
    ├── bronze_source_truth.md          32 Bronze table probe (real cols + row counts)
    ├── source_corrections.md           dedupe rules + business key clarifications
    ├── brd_full.md                     original BRD parsed
    └── Matrix_v3_Final_Lakehouse_Mapping.md   30 KPI → Bronze field map
```

---

## Quick start

| Goal | Start here |
|---|---|
| Understand the architecture | [01_docs/01_MASTER_PLAN.md](01_docs/01_MASTER_PLAN.md) |
| See what bugs were found and fixed | [04_TRACK_A_FIXES.md](04_TRACK_A_FIXES.md) + [01_docs/02_QC_REPORT.md](01_docs/02_QC_REPORT.md) |
| Deploy ETL to a Fabric Warehouse | [sql/](sql/) — run `01 → 10` in order on Processing WH, then `06 → 09` on Gold WH |
| Deploy semantic model | [04_semantic/](04_semantic/) — upload TMDL + DAX via Fabric API |
| What to do next | [05_NEXT_STEPS.md](05_NEXT_STEPS.md) |
| Source verification | [reference/bronze_source_truth.md](reference/bronze_source_truth.md) |

---

## Architecture in 1 paragraph

**Bronze** (lakehouse, 32 sources verified via `probe_all_sources.py`) →
**Silver** (Fabric `SupplyChain Processing Warehouse`, schema `silver`, 25 tables built in 4 tiers: dims → base → helpers → snapshots) →
**Gold** (Fabric `SupplyChain Gold Warehouse`, schema `gold`, 5 Dim + 2 Fact star schema, `FactInventoryHealthSnapshot` for current+historical, `FactInventoryRiskForward` for forward-looking weeks) →
**Semantic** (Power BI DirectLake, TMDL + 30+ DAX measures, maps 26/30 BRD KPIs in Phase 1 = 87% coverage).

---

## Critical caveats — read before deploying

1. **NOT production-ready yet.** Blockers:
   - 3 business-rule sign-offs pending from Robert (see [05_NEXT_STEPS.md](05_NEXT_STEPS.md) §Track D)
   - 4 Bronze data sources missing or stale — DE backfill request in flight
2. **Bundle file `FinalDecision/InventoryHealth_FULL_BUNDLE.md` is STALE.** It predates Track A. Use the files in `sql/` + `04_semantic/` here, not the bundle.
3. **Test deploy only on dev/sandbox WH.** After exec test, MUST run [sql/99_cleanup_silver.sql](sql/99_cleanup_silver.sql) + [sql/99_cleanup_gold.sql](sql/99_cleanup_gold.sql) to drop artifacts.
4. **Phase 1 = 87% KPI coverage.** Deferred to Phase 2: KPI #28 Aged Inventory, #29 Capacity Utilization, Container tracking, OnHold past trend.

---

## Sign-off status

| Item | Status | Owner |
|---|---|---|
| 14 code fixes in Track A | ✅ Applied + grep-verified | Claude (Aric proxy) |
| 18 bugs in QC report | 14 fixed in Track A; 4 LOW defer Phase 2 | Aric |
| 3 business-rule questions for Robert | ⏳ Email pending | Aric → Robert |
| 4 Bronze data sources missing | ⏳ DE backfill request sent | DE team |
| Dev WH exec test | ⏳ Not yet executed | Aric (after sign-off) |
| Production deploy | 🚫 Blocked on above | — |

---

## Contact

- **Aric Nguyen** (Person B / QC reviewer / sole owner) — aricnguyen.analytics2002@gmail.com
- **Robert** — business rule sign-off authority
- **DE team** — Bronze data load (PoMaster, Logility, ItemBalance, PurchaseOrderSnapshot)
