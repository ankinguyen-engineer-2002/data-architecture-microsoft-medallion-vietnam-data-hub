# PurchaseOrderSnapshotHistorical DateRange Cutover Plan

Date: 2026-07-10  
Status: **LIVE — deployed and controlled DateRange prove-out passed**

## Decision

- `InventoryHistory_Enh.InventorySnapshotWeekly` remains **full overwrite** while the US team confirms its duplicate/source semantics.
- Prioritize `InventoryHistory_Enh.PurchaseOrderSnapshotHistorical` because its existing target is materially larger: **2,066,414,716 rows** baseline, versus the inventory target under discussion.
- Change PO daily refresh from full overwrite to a `SnapshotDate` **DateRange -30** only after the live-deploy approval gate.

## Preflight baseline — 2026-07-10

Live Dev, evaluated with `SnapshotDate >= 2026-06-10`:

| Check | Result |
|---|---:|
| Source rows in candidate 30-day window | 40,733,444 |
| Source snapshot dates | 30 (`2026-06-10` through `2026-07-09`) |
| Duplicate groups at proposed TableDictionary key | 0 |
| Current target rows in 30-day window | 38,089,965 |
| Current target rows outside 30-day window | 2,028,324,751 |

Proposed PO TableDictionary/deduplication key for the DateRange window:

```text
SnapshotDate, ItemSku, WarehouseCode, VendorNumber, StatusCode, DueDate, UnitCost
```

This is a load-safety uniqueness check, not a claim that it replaces a source-system PO-line business key. Do not invent a tie-break/deduplication rule if this check later fails.

## Repository changes completed

- [x] W02 wrapper uses `usp_UpdateCuratedTableFromView_DateRange` with `SnapshotDate`, `-30`.
- [x] Before any delete/insert, W02 validates source window is non-empty.
- [x] Before any delete/insert, W02 validates no duplicate groups on the proposed key.
- [x] Guard failure `THROW`s and makes no target-table change.
- [x] Manifest/catalog/operating registry record the DateRange intent.
- [x] Generator supports the PO DateRange instruction for future wrapper regeneration.

## Live deployment and prove-out — PASS (2026-07-10)

Authorized scope: alter W02 and run the guarded PO DateRange only; the remaining W02 tables were not executed.

| Check | Result |
|---|---:|
| Live preflight source rows | 40,733,444 |
| Live preflight duplicate groups | 0 |
| W02 guarded DateRange deployment | PASS |
| Controlled PO DateRange duration | 33.8 sec |
| Source vs target rows inside window | 40,733,444 = 40,733,444 |
| OrderedQty / POOnOrderQty / POInTransitQty deltas | 0.0000 / 0.0000 / 0.0000 |
| Per-date source vs target mismatches | 0 |
| Outside-window target rows preserved | 2,028,324,751 |
| Outside-window OrderedQty preserved | 1,689,895,830,143.8390 |
| Outside-window POOnOrderQty preserved | 261,542,995,364.0750 |
| Outside-window POInTransitQty preserved | 143,790,020,740.6810 |

The live W02 definition now includes the empty-source and duplicate-key guards. Do not call the entire W02 wrapper merely to refresh PO; it has other W02 targets. The production scheduler may use W02 as designed, while an isolated PO rerun must execute the guarded PO block/date-range call only.

## Live execution checklist

1. [x] Re-run read-only preflight immediately before deployment: source range/count/key duplicates and target in-window/out-of-window baselines.
2. [x] Verify the live wrapper was replaced by the guarded DateRange definition.
3. [x] Obtain explicit Aric approval for live `ALTER PROCEDURE` and controlled execution.
4. [x] Alter W02 only; leave `InventorySnapshotWeekly` and its TableDictionary configuration unchanged.
5. [x] Run the guarded PO DateRange only and capture source/target 30-day metrics.
6. [x] Confirm in-window parity per date and preservation of all recorded outside-window metrics.
7. [x] Record results in `00_CONTEXT/current.md`.
8. [ ] Observe the next scheduled W02 execution and its downstream DQ/Gold checks before changing PO TableDictionary metadata, if such a metadata change is required.

## Rollback

If preflight guard, DateRange load, or post-run validation fails:

1. Stop at the failure; do not retry with overwrite.
2. Restore the prior W02 full-overwrite wrapper definition.
3. Retain the before/after evidence and investigate source/key semantics.
4. Any target repair/backfill is a separate explicitly approved operation.
