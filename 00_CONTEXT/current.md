# Context 2026-06-24 to 2026-06-30

## 2026-07-12 08:15:00 ICT — Module 05 downstream+perf DONE + report-contract constraint locked; Wave 0 COMPLETE (read-only, no live mutation)

**Scope lock:**
- Still Wave 0 / pre-Wave-1. Read-only only: `ApplicationIntent=ReadOnly`, SELECT + metadata. Zero CREATE/ALTER/DROP/INSERT/UPDATE/DELETE on live Fabric. No optimization deployed.

**User instruction:**
- "tiếp tục cho xong plan." Mid-way user raised a hard business concern: Power BI report (both Forecast + Inventory Gold facts) is already built on the existing physical facts, so replacing/dropping facts would destroy visual/measure/report work — must be added to the plan as a top optimization constraint.

**Actions executed (all read-only / repo-only):**
- Hardened `05_tools/03_gold_parity/05_downstream_perf.py`: added `--include-target` / `--measures-for`; heavy views default to rowcount-only; e2e now runs each heavy count on its own short-lived read-only connection + one retry (fixes TCP-session cascade); `run_e2e_view_vs_table(timeout=...)`; e2e target list honors `--include-target`. `lib_conn.query` timeout arg reverted (pyodbc.Cursor has no settable timeout).
- Ran Layer F sanity per-target (dims batched; heavy views one-by-one).
- Ran Layer D e2e for both small consumers (SubStatus + ClassQty).
- Added HARD CONSTRAINT §2.1 to `2026-07-10-inventory-gold-business-parity-optimization-plan.md` (in-place identity: same physical object, columns/order/types/nullability/key byte-compatible; refactor producer `_Wrk.v_*`+loader, not the report-facing object; Direct Lake binding must survive; applies to both marts). Added parity check #1 sub-bullet and §6.3 release gate 7.
- Updated evidence pack `2026-07-10-inventory-gold-wave0-evidence-pack.md` §7 (Layer F/G + e2e), new §8 (report-contract preservation), §9 next actions; status header → Wave 0 COMPLETE.

**Verified results (all read-only live):**
- Layer F view-vs-table sanity, all 9 targets PASS, 0 diffs. Row counts match Module 03 baseline exactly: DimCalendar 21,551; DimProduct 783,945; DimWarehouse 53; DimVendor 87,003; SubStatusWeekly 19,605,162; ClassQtyWeekly 19,605,162; ProjectedSubStatus 3,785,137; FutureWeekEnding 3,785,137; FactSnapshot 19,501,346. Dim measure SUMs also 0-diff.
- Layer D e2e full-tuple A(table)-vs-B(view recompute): SubStatusWeekly a=b=19,605,162, a∉b=0, b∉a=0, value_mismatches=0 (513s, run 20260711T131645Z). ClassQtyWeekly a=b=19,605,162, a∉b=0, b∉a=0, value_mismatches=0 (1388s, run 20260712T010259Z).
- Layer G perf baseline (30d, run 20260711T084148Z): chain median elapsed=643s, chain median remote scan=10,150MB. Hotspots: FutureWeekEnding p95=886s (compute), FactSnapshot rem_med=5,154MB (scan), SubStatusWeekly rem_med=3,703MB.

**Infra note (not a logic failure):**
- First ClassQty e2e attempt hit Fabric capacity pause (error 24800 "capacity is currently not active") mid-run, then a long anti-join dropped the shared TCP session (08S01 0x36 → IMC06 cascade). Capacity came back; per-query fresh-connection design made the rerun clean.

**Files changed (repo only, no live):**
- `05_tools/03_gold_parity/05_downstream_perf.py`, `lib_conn.py`
- `05_tools/03_gold_parity/runs/2026071{1,2}T*_downstream_perf_{sanity,e2e}.*`
- `01_docs/plans/2026-07-10-inventory-gold-business-parity-optimization-plan.md` (§2.1, §4.1, §6.3)
- `01_docs/plans/2026-07-10-inventory-gold-wave0-evidence-pack.md` (§7–§9, status)
- `00_CONTEXT/current.md`

**Verdict:** Wave 0 COMPLETE. C1 inv_base business parity proven at inv_base + downstream serving level; oracle confirmed non-stale; perf baseline set; report-contract preservation now a blocking gate. C1 is compatible with §2.1 because it only refactors shared inv_base feeding the existing `INSERT ... SELECT *` into the same physical facts.

**Blocker/risk:**
- No production change is authorized. Wave 1 deploy blocked until Aric approves the exact in-place object(s) + implementation + run + validation scope (§6.3, incl. new gate 7).

**Next concrete step:**
- Request Wave 1 gate for the first in-place C1 candidate (shared inv_base → FactSnapshot/SubStatus/ClassQty), including the §7 report-contract diff + `sc_control_tower` smoke as part of the gate-7 evidence.

## 2026-07-11 09:30:00 ICT — Module 04 C1 inv_base parity PASS (read-only, no live mutation)

**Scope lock:**
- Still Wave 0 / pre-Wave-1. User: proceed as long as live Fabric production is not touched.
- Module 04 implemented as **inline pure SELECT** A-vs-B. **No** CREATE/ALTER/DROP/INSERT/UPDATE/DELETE on live Fabric. No shadow schema/table/view created.

**Actions:**
- Built `05_tools/03_gold_parity/04_shadow_parity.py` (T1 R3 extended, T2 shared counts, T3 Fact A-vs-B, T4 SubStatus A-vs-B, T5 SnapshotType dist; `--recent-weeks` / `--full` / `--only-antijoin`).
- Smoke 8 weeks: overall PASS (`runs/20260711T021117Z_shadow_parity_c1.*`).
- Full history T1/T2/T5 + invariants PASS; first T3 wide-EXCEPT TCP-timeouted → rewritten to key anti-join + null-safe value mismatch.
- Full history T3/T4 PASS (`runs/20260711T022510Z_shadow_parity_c1.*`).
- Updated evidence pack `01_docs/plans/2026-07-10-inventory-gold-wave0-evidence-pack.md` §5–§7.

**Verified results (full history, source `InventoryHistory_Enh.InventorySnapshotWeekly`):**
- multi_row_groups = 19,605,162; FMD ties = 0; all carried cols constant within group (OnHandQty, MakeBuyCode, PrimaryVendorName, SecondaryVendorName, ReplenishmentLeadTime, SnapshotType).
- shared_rn1 = 19,605,162 (= weekly family); fact_eligible WEEKLY = 19,501,346 (= FactSnapshot table); LATEST excluded = 103,816.
- T3 Fact A-vs-B: a=b=19,605,162; a∉b=0; b∉a=0; value_mismatches=0.
- T4 SubStatus A-vs-B: a=b=19,605,162; a∉b=0; b∉a=0; value_mismatches=0.
- Verdict: `C1_SHARED_INV_BASE_PARITY_PASS` for inv_base surface only.

**Not proven / not done:**
- End-to-end view parity (joins/CASE after inv_base).
- Performance gain (no materialization).
- Production deploy of C1 (not requested; not approved).
- Module 05 downstream/perf.

**Next:**
1. Module 05 (downstream serving + perf/rollback), still read-only first.
2. Optional pure-SELECT end-to-end A-vs-B for FactSnapshot/SubStatus/ClassQty.
3. Only then request approval before any production object change.

---

## 2026-07-11 00:50:00 ICT — Inventory Health Gold Wave 0 audit/baseline harness (read-only, no live mutation)

**Scope lock:**
- Wave 0 of `2026-07-10-inventory-gold-business-parity-optimization-plan.md`.
- Read-only live audit + frozen baseline only. No production DDL/DML, no wrapper/pipeline/semantic mutation. User approved building test scaffolding and read-only probing; no production object touched.

**User instruction:**
- Read context + repo + optimization plan, then design and execute a very detailed audit/test/parity system so an optimized B provably equals current A on business logic, code logic, and performance. Approved doing anything per plan except changing live-running production; may create-then-drop test objects.

**Actions executed (all read-only):**
- Built harness `05_tools/03_gold_parity/`: `lib_conn.py` (read-only-intent pyodbc + Entra token, reused 01_dq pattern), `01_contract_inventory.py`, `02_risk_probes.py`, `03_baseline_capture.py`.
- Module 01: captured contract for all 9 `Usp_Refresh_InventoryHealth_Gold` targets (live view SQL + INFORMATION_SCHEMA + static parse + loader positional contract). Output `contracts/*.contract.json`.
- Module 02: risk probes R1 (helper-join multiplicity), R2 (DimProduct uniqueness), R3 (inv_base tie-break materiality).
- Module 03: baseline pack per target (rowcount, key uniqueness, date coverage, exact measure sums, categorical distributions, weekly reconciliation, best-effort Query Insights). Output `contracts/*.baseline.json`.
- Evidence pack written to `01_docs/plans/2026-07-10-inventory-gold-wave0-evidence-pack.md`.

**Key findings:**
- Loader safety: all 9 view→table column sets match exactly (`INSERT ... SELECT *` safe); 2026-07-03 DimWarehouse drift class not present now.
- Live-vs-repo view drift recorded (not a blocker): live `FactInventoryHealthSnapshot` has 54 cols incl `WeightedSINegScore`,`OutageClass`; live FutureWeekEnding has `ProjectedShortageValue` vs repo `ProjectedRevenueAtRisk`. Oracle uses live columns.
- R1: all 7 FactSnapshot LEFT-JOIN tables have 0 dup groups at join grain → no fan-out.
- R2: DimProduct unique at ItemSKU (783,945; 0 dup).
- R3: `InventorySnapshotWeekly` = 705,785,832 raw rows → 19,605,162 dedup groups (~36:1), scanned+deduped 3× by weekly family. Tie-break immaterial for OnHandQty (0 groups differ, 0 FiscalMonthDate ties). GAP: tie-break stability for MakeBuyCode/PrimaryVendorName/SecondaryVendorName/ReplenishmentLeadTime still UNVERIFIED.
- Baseline-time hypothesis: weekly family 19,605,162 vs FactSnapshot 19,501,346 (Δ=103,816) was initially attributed to the fact-only NULL filter. Module 04 later corrected this: rn=1 null-key exclusion is 0; the full Δ is `SnapshotType='LATEST'` excluded by the post-dedup WEEKLY filter.
- Frozen FactSnapshot totals (max date 2026-07-04): SUM(OnHandQty)=2,146,230,631; SUM(OnHandValue)=76,277,084,285.2561; SUM(SIQty)=1,538,875,984; SUM(ShortageValue)=-18,577,955,997. Classification + shortage distributions frozen.

**Files changed (repo only, no live):**
- `05_tools/03_gold_parity/*` (new harness + contracts + baselines + run logs)
- `01_docs/plans/2026-07-10-inventory-gold-wave0-evidence-pack.md` (new)
- `00_CONTEXT/current.md`

**Candidate ranking (test-only, NOT approved):** C1 shared deduped inv_base (High ROI, pending R3 gap), C2 shared PO/MO aggregate, C3 shared sp_latest/as-of for future family, C4 column narrowing, C5 predicate pushdown.

**Next concrete step:**
- Close R3 gap (4 non-OnHand cols tie-break stability), then build Module 04 shadow parity + Module 05 downstream/perf before any C1 shadow implementation or approval request.

## 2026-07-06 12:45:00 ICT — Read-only audit of `2026-07-03` post-18:00 activity for full mart vs DQ-only reruns

**Scope lock:**
- Read-only live Fabric REST + warehouse SQL audit.
- No live mutation.

**User instruction:**
- Read `00_CONTEXT` and `CLAUDE.md`, then check whether after `18:00 ICT` on `2026-07-03` the full mart chain ran, with special attention to duplicate DQ / repeated snapshot symptoms.

**Actions executed:**
- Re-read `CLAUDE.md` and `00_CONTEXT/current.md`.
- Queried live Fabric job instances for pipeline `pl_backup_full_refresh` (`41948342-d7e7-4166-8638-9af0633e6a49`).
- Queried live `ETL_Framework.DW_Developer.AuditLog`.
- Queried live `ETL_Framework.DW_Developer.TableDictionary_UpdateLog`.
- Queried live `SupplyChain_Gold_Warehouse.ForecastAccuracy_DW.DQForecastAccuracy` grouped by `DQRunId`, `DQRunAtUTC`.

**Key findings:**
- `pl_backup_full_refresh` has no job instance on `2026-07-03` after `2026-07-03T07:31:53Z` (`14:31:53 ICT`).
- The only `2026-07-03` full-refresh pipeline runs visible were:
  - `56c337d6-4717-425e-b0ac-d00aa9639c96` — `Cancelled`, `01:21:27Z` to `01:21:53Z` (`08:21 ICT`)
  - `191f0cd6-6d20-4c4a-bfab-0156ad826e74` — `Completed`, `02:35:01Z` to `03:32:27Z` (`09:35` to `10:32 ICT`)
  - `8397b46a-c12b-46a9-a428-6e9c3468b640` — `Failed`, `06:52:22Z` to `07:31:53Z` (`13:52` to `14:31 ICT`)
- `AuditLog` has `0` rows from `2026-07-03T10:30:00Z` onward (`17:30 ICT` onward), and the latest `2026-07-03` row is `OpenOrderHistory_Enh.OpenOrderMonthly` at `2026-07-03 03:39:32Z` (`10:39:32 ICT`).
- `TableDictionary_UpdateLog` has `0` rows from `2026-07-03T11:00:00Z` onward (`18:00 ICT` onward), confirming no framework-tracked curated table refresh completed after `18:00 ICT`.
- `DQForecastAccuracy` did run multiple times on `2026-07-03`, but the latest visible DQ batch is `EA441173-6047-4304-90DD-FE98A14ED5D7` at `2026-07-03 08:54:30Z` (`15:54:30 ICT`), still before `18:00 ICT`.
- Total visible DQ batches on `2026-07-03`: `9`; latest cluster was around `14:17`, `14:25`, `14:52`, `15:04`, `15:20`, `15:31`, `15:39`, `15:54 ICT`, which is consistent with repeated DQ/manual reruns earlier in the afternoon, not an evening full mart rerun.

**Conclusion:**
- No evidence that the canonical 10-step full mart chain ran after `18:00 ICT` on `2026-07-03`.
- No evidence that a SQL Agent / external job executed a framework-tracked full mart refresh after `18:00 ICT` either; if such a job existed for that window, it did not leave `AuditLog` or `TableDictionary_UpdateLog` evidence.
- The duplicate DQ / repeated snapshot symptoms are supported by multiple DQ reruns earlier on `2026-07-03`, but not by any post-`18:00 ICT` full mart execution.

## 2026-07-06 13:05:00 ICT — DQ timestamp interpretation audit for evening-hour confusion

**Scope lock:**
- Read-only repo + live SQL audit for `ForecastAccuracy_DW.DQForecastAccuracy`.
- No live mutation.

**User instruction:**
- Explain why some DQ checks appear to happen around `18:00`, `19:00`, `20:00`.

**Actions executed:**
- Re-read repo DQ view `02_marts/forecast_accuracy/03_gold/ForecastAccuracy_DW_Wrk/v_DQForecastAccuracy.sql`.
- Queried live schema and sample rows from `SupplyChain_Gold_Warehouse.ForecastAccuracy_DW.DQForecastAccuracy`.
- Queried live DQ runs for `2026-07-03` with explicit `DATEADD(hour, 7, DQRunAtUTC)` conversion to ICT.
- Queried last 14-day/30-day windows for any runs landing in `18`, `19`, `20` ICT or UTC hour buckets.

**Key findings:**
- Repo DQ logic hardcodes UTC timestamps:
  - `DQRunAtUTC = SYSUTCDATETIME()`
  - `LoadDT = DQRunAtUTC`
- Live table columns are only:
  - `RuleName`
  - `RuleDescription`
  - `Result`
  - `LoadDT`
  - `DQRunId`
  - `DQRunAtUTC`
- For `2026-07-03`, live DQ runs convert to these ICT times only:
  - `09:59:07`
  - `14:17:13`
  - `14:25:57`
  - `14:52:13`
  - `15:04:07`
  - `15:20:49`
  - `15:31:37`
  - `15:39:52`
  - `15:54:30`
- Live query returned `0` rows for:
  - `2026-07-03 18:00:00` to `20:59:59` ICT
  - any DQ run in the last 14 days whose ICT hour is `18`, `19`, or `20`
  - any DQ run in the last 30 days whose raw UTC hour is `18`, `19`, or `20`

**Conclusion:**
- Current live `DQForecastAccuracy` evidence does **not** support actual DQ execution in the evening-hour windows the user mentioned.
- If another screen/query shows `18:xx` / `19:xx` / `20:xx`, that screen is almost certainly not reading the live table/time fields in the same way as the direct warehouse query:
  - wrong timezone interpretation
  - stale import/cache/report snapshot
  - different source table/query/date slice

## 2026-07-06 13:20:00 ICT — Root-cause audit of `PASS -> FAIL` flips inside physical `DQForecastAccuracy` history

**Scope lock:**
- Read-only live SQL audit of physical DQ history table only.
- No live mutation.

**User instruction:**
- Recheck Data Quality because several snapshots show `PASS` then later `FAIL`; explain why a rule that previously passed can later fail.

**Actions executed:**
- Queried full history of `SupplyChain_Gold_Warehouse.ForecastAccuracy_DW.DQForecastAccuracy`.
- Built:
  - per-rule transition list (`LAG(Result)`)
  - per-rule pass/fail summary
  - per-run fail matrix
- Cross-checked the transition timings against earlier `2026-07-03` context entries for manual reruns and DQ contract changes.

**Key findings:**
- The physical DQ table currently contains only `9` runs, and **all 9 occurred on `2026-07-03`**.
- Therefore the observed `PASS -> FAIL` behavior is **intra-day rerun instability**, not long-term nightly drift.
- There are three distinct root-cause patterns:
  1. **Snapshot drift against mutable source data**
     - `DQ_B2S2_OpenOrder_Qty` flipped `PASS -> FAIL` at `14:17 ICT`, then `FAIL -> PASS` at `15:20 ICT`.
     - This matches the earlier proven root cause: DQ compared mutable bronze/raw current data against an earlier persisted Silver table, so re-running one layer changes which side is stale.
     - `DQ_B2S2_Invoice_Qty` showed the same unstable shape (`PASS -> FAIL` at `14:52 ICT`, back to `PASS` at `15:20 ICT`) and was later included in the DQ contract fix path.
  2. **Partial rerun / layer desynchronization**
     - `DQ_S2S1_OpenOrder_Qty` and `DQ_S2S1_Invoice_Qty` both flipped `PASS -> FAIL` at `15:20 ICT`, then back to `PASS` at `15:31 ICT`.
     - This is consistent with rerunning one Silver wave before the dependent next wave, temporarily making upstream/downstream tables inconsistent.
     - `DQ_S2G_Actual_Qty` flipped `PASS -> FAIL` at `15:31 ICT` and stayed failed in later runs, which is consistent with Silver being refreshed later than Gold so the cross-layer comparison stopped using the same cut of data.
  3. **Rule-set / contract changed between DQ batches**
     - Some DQ runs have `32` rules, others have `47`.
     - Several rules appear only in `4` or `5` runs, proving the DQ definition itself changed during the same day.
     - So some snapshot-to-snapshot comparisons are not apples-to-apples: both data state and active rule inventory changed.
- Stable always-fail rules are a separate class and should not be mixed with the above transition problem:
  - `DQ_B2S2_Forecast_Qty`
  - `DQ_Bronze_Grain_DemandForecastSnapshotDaily`
  - `DQ_Bronze_Grain_InvoiceHeader`

**Conclusion:**
- When a DQ rule passed and later failed on `2026-07-03`, the main cause was **not necessarily new bad data**.
- The dominant causes were:
  - comparing mutable bronze/live sources to persisted downstream snapshots from a different moment
  - rerunning only part of the dependency chain
  - changing the DQ rule contract itself between batches
- For this DQ history table, a `PASS -> FAIL` flip must be interpreted together with rerun timing and active DQ-view version; by itself it does **not** prove a new source-data regression.

## 2026-07-06 14:05:00 ICT — Deep grouping audit of physical `DQForecastAccuracy` fail history

**Scope lock:**
- Read-only live SQL audit of physical DQ table plus live object metadata for the DQ view.
- No live mutation.

**User instruction:**
- Check in detail why earlier DQ looked mostly passed except DemandForecastSnapshot source issues, but later many more fails appeared.

**Actions executed:**
- Grouped physical `ForecastAccuracy_DW.DQForecastAccuracy` by `DQRunId`.
- Built fail-rule list per run with `STRING_AGG`.
- Compared per-rule run presence across all `9` runs.
- Read live `sys.objects.modify_date` / `sys.sql_modules` for `ForecastAccuracy_DW_Wrk.v_DQForecastAccuracy`.

**Key findings:**
- The physical DQ table is append-only history. Reading raw fail rows across the whole table overstates the problem because multiple rerun snapshots are mixed together.
- There were **three distinct fail patterns** across the `9` runs on `2026-07-03`:
  1. `09:59 ICT`:
     - fails = `DQ_B2S2_Forecast_Qty`, `DQ_Bronze_Grain_DemandForecastSnapshotDaily`, `DQ_Bronze_Grain_InvoiceHeader`, `DQ_Gold_Grain_FactForecastActual`, `DQ_Silver_Grain_ForecastDemandMonthly`
  2. `14:17` to `15:04 ICT`:
     - transient extra fails shifted across reruns:
       - `DQ_B2S2_OpenOrder_Qty`
       - `DQ_B2S2_Invoice_Qty`
  3. `15:20` to `15:54 ICT`:
     - transient cross-layer fails shifted again:
       - `DQ_S2S1_Invoice_Qty`
       - `DQ_S2S1_OpenOrder_Qty`
       - then later `DQ_S2G_Actual_Qty`
- The “too many fail khác” effect is amplified by a **rule inventory change during the same day**:
  - some runs have `32` rules
  - some runs have `47` rules
  - `15` rules appear only in the middle `5` runs (`14:52` to `15:39 ICT`) and are absent from the first `3` and last `1` runs
- Therefore the DQ history that day is **not a single stable test suite**. It is a mixture of:
  - different data snapshots
  - partial/manual reruns
  - different DQ-view versions
- Live object metadata confirms the DQ view was edited on `2026-07-03 09:18:55 UTC` (`16:18:55 ICT`), i.e. after all currently stored DQ batches, so the live DQ definition changed during that troubleshooting window.

**Conclusion:**
- The later “many more fails” were not a clean signal of broad new data regression.
- They were mainly caused by:
  - grouping historical rows from multiple DQ snapshots together
  - transient layer desynchronization during manual reruns
  - DQ rule inventory/definition changes within the same day
- The durable fail set at the end of the stored history narrowed back down to `4` rules:
  - `DQ_B2S2_Forecast_Qty`
  - `DQ_Bronze_Grain_DemandForecastSnapshotDaily`
  - `DQ_Bronze_Grain_InvoiceHeader`
- `DQ_S2G_Actual_Qty`

## 2026-07-06 14:06:00 ICT — Live trigger and monitoring of new `pl_backup_full_refresh` run

**Scope lock:**
- Live Fabric pipeline execution monitoring plus read-only warehouse diagnostics.
- No destructive live change.

**User instruction:**
- Run the current live full pipeline in Fabric, then watch until it passes forecast and moves into inventory so forecast DQ can be checked immediately.

**Actions executed:**
- Triggered live pipeline `pl_backup_full_refresh` (`41948342-d7e7-4166-8638-9af0633e6a49`) via Fabric REST.
- Confirmed new job instance `d276499a-e2fe-4a9d-b28c-82cf170c9509` was created with `startTimeUtc = 2026-07-06T07:01:45.1351939Z`.
- Polled live job history and confirmed the new run moved from `NotStarted` to `InProgress`.
- Queried `sys.dm_exec_requests` to infer pipeline stage because public Fabric REST still exposes only pipeline-level job status.

**Key findings:**
- At `2026-07-06 14:03 ICT`, pipeline run `d276499a-e2fe-4a9d-b28c-82cf170c9509` is still `InProgress`.
- Live warehouse DMV shows an active command:
  - `DROP TABLE SupplyChain_Processing_Warehouse.ReferenceMaster_Enh.Calendar`
- That command is from the beginning of the canonical shared/reference sequence, so the run has **not** passed forecast into inventory yet.
- Forecast DQ should only be rechecked once a new `ForecastAccuracy_Gold` batch has inserted a newer `DQRunAtUTC` than the prior baseline `2026-07-03 15:54:30 ICT`.

**Risk / blocker:**
- Direct SELECTs against `ForecastAccuracy_DW.DQForecastAccuracy` are currently hanging unusually long while the refresh is active, so stage inference is more reliable from DMVs than from immediate DQ-table reads until forecast gold finishes.

**Next concrete step:**
- Continue polling the live run; when execution evidence moves beyond forecast gold or a new `DQRunId` appears, query the latest DQ batch and summarize pass/fail immediately.

## 2026-07-06 14:14:00 ICT — Unblocked live full-refresh run and verified current forecast-stage position

**Scope lock:**
- Live operational monitoring plus non-data-destructive session cleanup.

**User instruction:**
- Keep watching the live full pipeline and only check forecast DQ once execution has passed forecast into inventory.

**Actions executed:**
- Queried `sys.dm_exec_requests` repeatedly to identify the current live SQL step for pipeline run `d276499a-e2fe-4a9d-b28c-82cf170c9509`.
- Found step `DROP TABLE SupplyChain_Processing_Warehouse.ReferenceMaster_Enh.Calendar` waiting on `LCK_M_SCH_M`.
- Identified blocker `session_id = 188`, which was a lingering read-only DQ query from the assistant (`SELECT ... FROM ForecastAccuracy_DW_Wrk.v_DQForecastAccuracy`).
- Issued `KILL` for the assistant-owned stuck read sessions (`188`, `174`, `185`, `186`, `132`, `53`, `134`, `212`, `211`, `213`) to release the schema lock and avoid blocking the live refresh.
- Re-polled DMVs and latest physical `ForecastAccuracy_DW.DQForecastAccuracy` timestamp after cleanup.

**Key findings:**
- The pipeline resumed immediately after the stuck assistant sessions were killed; `session_id = 192` moved from blocked `DROP TABLE` to active framework execution.
- Current active forecast-stage workload is:
  - `INSERT INTO SupplyChain_Processing_Warehouse.Staging.DemandForecastSnapshotDaily_LOAD SELECT * FROM SupplyChain_Processing_Warehouse.Staging_Wrk.v_DemandForecastSnapshotDaily`
- This proves the run has entered the forecast path but has **not yet** reached forecast gold completion or inventory.
- Latest physical forecast DQ batch is still unchanged:
  - `DQRunId = EA441173-6047-4304-90DD-FE98A14ED5D7`
  - `DQRunAtICT = 2026-07-03 15:54:30.776756`
- Therefore no new forecast DQ result is available yet from the current run.

**Risk / blocker:**
- The long-running `DemandForecastSnapshotDaily_LOAD` insert is the current pacing item; until it finishes and forecast gold runs, DQ cannot be re-evaluated from the physical table.

**Next concrete step:**
- Continue monitoring until the run advances beyond forecast into inventory or a new `DQRunId` appears, then read and summarize the new forecast DQ batch immediately.

## 2026-07-06 14:24:00 ICT — Live progress poll for current full-refresh pipeline

**Scope lock:**
- Read-only live Fabric REST + warehouse DMV progress check.

**User instruction:**
- Check live Fabric pipeline progress now.

**Actions executed:**
- Polled Fabric job instances for `pl_backup_full_refresh`.
- Queried live `sys.dm_exec_requests` to infer the currently executing SQL step.
- Queried latest physical `ForecastAccuracy_DW.DQForecastAccuracy` batch timestamp.

**Key findings:**
- Current run `d276499a-e2fe-4a9d-b28c-82cf170c9509` is still `InProgress` as of `2026-07-06 14:24 ICT`.
- The currently active SQL work has moved forward to:
  - `INSERT INTO SupplyChain_Processing_Warehouse.SalesHistory_Enh.InvoiceDetailLineLevel_LOAD SELECT * FROM SupplyChain_Processing_Warehouse.SalesHistory_Enh_Wrk.v_InvoiceDetailLineLevel`
- This is progress beyond the earlier `DemandForecastSnapshotDaily_LOAD` step, but it still does **not** prove the run has crossed into inventory.
- Latest physical forecast DQ batch remains unchanged:
  - `DQRunId = EA441173-6047-4304-90DD-FE98A14ED5D7`
  - `DQRunAtICT = 2026-07-03 15:54:30.776756`
- Therefore forecast gold / forecast DQ from the current run has not completed yet.

## 2026-07-07 14:20:00 ICT — Live audit of Inventory BRZ/raw source to first Silver touch

**Scope lock:**
- Read-only live SQL audit against `SupplyChain_Processing_Warehouse`.
- No repo code edit and no live mutation.

**User instruction:**
- Audit live Fabric, list all Bronze/raw source tables and the first Silver table they touch for Inventory mart scope, ignoring execution wave.

**Actions executed:**
- Re-read `CLAUDE.md` and `00_CONTEXT/current.md`.
- Queried live wrapper procedure definitions:
  - `dbo.Usp_Refresh_Shared_ReferenceMaster`
  - `dbo.Usp_Refresh_InventoryHealth_Silver_W01`
  - `dbo.Usp_Refresh_InventoryHealth_Silver_W02`
  - `dbo.Usp_Refresh_InventoryHealth_Silver_W03`
- Queried live `_Wrk` view definitions in:
  - `ReferenceMaster_Enh_Wrk`
  - `InventoryHistory_Enh_Wrk`
  - `SalesHistory_Enh_Wrk`
  - `Staging_Wrk`
- Parsed `FROM/JOIN/APPLY` references and mapped direct `Enterprise_Lakehouse.*` / `ProcessingSeed.*` sources to first physical Silver targets.

**Key findings:**
- Live wrapper target scope scanned: `25` targets:
  - `11` shared `ReferenceMaster_Enh` targets
  - `13` `InventoryHistory_Enh` targets
  - `1` `SalesHistory_Enh.InvoiceDetailLineLevel` inventory dependency
- Direct raw/seed to final Silver:
  - `22` targets have direct raw/seed source refs.
  - `28` unique direct raw/seed sources.
- Including the staging hop `Enterprise_Lakehouse.SupplyChain_Enh.DemandForecastSnapshotDaily -> Staging.DemandForecastSnapshotDaily -> InventoryHistory_Enh.ForecastSnapshotWeekly`:
  - `23` final Silver targets have raw/seed ancestry.
  - `29` unique raw/seed sources if `ProcessingSeed` is counted.
  - `27` unique Enterprise_Lakehouse raw sources if `ProcessingSeed` is excluded.
- Two scanned final targets are not B2S/raw-first; they are downstream S2S:
  - `InventoryHistory_Enh.SafetyStockHelper <= InventoryHistory_Enh.InventorySnapshotWeekly`
  - `InventoryHistory_Enh.LastInvoiceWeekly <= InventoryHistory_Enh.InventorySnapshotWeekly; SalesHistory_Enh.InvoiceDetailLineLevel`

**DQ implication:**
- For Inventory BRZ->first Silver DQ, wave number is not the correct boundary.
- The correct B2S scope is every final Silver target with direct or traced raw/seed ancestry, regardless of W01/W02/W03 wrapper.
- `SafetyStockHelper` and `LastInvoiceWeekly` should be handled as S2S checks, not B2S checks.

**Next concrete step:**
- Keep polling until either a new `DQRunId` appears or SQL activity clearly moves into inventory wrappers, then read the latest forecast DQ batch immediately.

## 2026-07-06 14:28:00 ICT — Forecast mart layer mapping for live pipeline step

**Scope lock:**
- Read-only repo mapping + live DMV progress check.

**User instruction:**
- Clarify which forecast layer the live pipeline has reached and whether forecast mart is close to finishing.

**Actions executed:**
- Re-polled live Fabric job instances and `sys.dm_exec_requests`.
- Read repo procedure definitions for:
  - `Usp_Refresh_ForecastAccuracy_Silver_W02`
  - `Usp_Refresh_ForecastAccuracy_Silver_W03`
- Mapped the active live object `ForecastHistory_Enh.ForecastDemandMonthly` to the canonical forecast wave order in repo.

**Key findings:**
- Current run `d276499a-e2fe-4a9d-b28c-82cf170c9509` is still `InProgress`.
- Active pipeline SQL step is:
  - `INSERT INTO SupplyChain_Processing_Warehouse.ForecastHistory_Enh.ForecastDemandMonthly_LOAD SELECT * FROM SupplyChain_Processing_Warehouse.ForecastHistory_Enh_Wrk.v_ForecastDemandMonthly`
- Repo mapping proves `ForecastHistory_Enh.ForecastDemandMonthly` belongs to `Usp_Refresh_ForecastAccuracy_Silver_W02`.
- Inside `W02`, the object order is:
  1. `SalesHistory_Enh.ActualDemandMonthly`
  2. `SalesHistory_Enh.ActualDemandWeekly`
  3. `SalesHistory_Enh.InvoiceWeekly`
  4. `ForecastHistory_Enh.ForecastDemandMonthly`
  5. `OpenOrderHistory_Enh.OpenOrderMonthly`
- Therefore the live run is already past forecast `W01` and well into forecast `W02`, but still has these forecast steps remaining before forecast mart is fully done:
  - finish current `W02.ForecastDemandMonthly`
  - `W02.OpenOrderMonthly`
  - `W03.NaiveForecastMonthly`
  - `ForecastAccuracy_Gold` including final DQ insert into `ForecastAccuracy_DW.DQForecastAccuracy`

**Conclusion:**
- Forecast mart is **not finished yet**, but it is already beyond the early half of the forecast path.
- It is closer to the end than the start, but still not at the point where a new forecast DQ batch should exist.

## 2026-07-06 14:32:00 ICT — Forecast mart has entered Gold phase in live pipeline

**Scope lock:**
- Read-only live Fabric REST + warehouse DMV check with repo procedure confirmation.

**User instruction:**
- Recheck progress and say whether forecast mart is near completion.

**Actions executed:**
- Polled live pipeline run `d276499a-e2fe-4a9d-b28c-82cf170c9509`.
- Queried `sys.dm_exec_requests` for the currently executing SQL step.
- Read `03_operations/orchestration/forecast_accuracy/sql/SupplyChain_Gold_Warehouse.dbo.Usp_Refresh_ForecastAccuracy_Gold.sql` to map the active object to the forecast gold procedure.
- Rechecked latest physical `ForecastAccuracy_DW.DQForecastAccuracy` batch timestamp.

**Key findings:**
- Pipeline is still `InProgress` at `2026-07-06 14:31 ICT`.
- Current active SQL step is:
  - `INSERT INTO SupplyChain_Gold_Warehouse.Shared_DW.DimProduct_LOAD SELECT * FROM SupplyChain_Gold_Warehouse.Shared_DW_Wrk.v_DimProduct`
- Repo confirmation proves this object is inside `Usp_Refresh_ForecastAccuracy_Gold`, specifically the early shared-dim portion of forecast gold:
  - `Shared_DW.DimCalendar`
  - `Shared_DW.DimProduct`
  - `Shared_DW.DimWarehouse`
  - then forecast dims
  - then forecast facts
  - then terminal DQ insert
- Latest physical forecast DQ batch is still unchanged:
  - `DQRunId = EA441173-6047-4304-90DD-FE98A14ED5D7`
  - `DQRunAtICT = 2026-07-03 15:54:30.776756`

**Conclusion:**
- Forecast mart has now **entered Gold**, so it is materially closer to completion.
- However it is still only in the early shared-dim portion of forecast gold, so it is **not done yet** and no new forecast DQ batch exists yet.

## 2026-07-06 14:36:00 ICT — Forecast mart still inside Gold procedure, DQ batch not emitted yet

**Scope lock:**
- Read-only live Fabric + SQL progress poll.

**User instruction:**
- Continue checking progress.

**Actions executed:**
- Polled Fabric job instances for `pl_backup_full_refresh`.
- Queried live `sys.dm_exec_requests`.
- Rechecked latest physical `ForecastAccuracy_DW.DQForecastAccuracy` batch.

**Key findings:**
- Run `d276499a-e2fe-4a9d-b28c-82cf170c9509` remains `InProgress` at `2026-07-06 14:35 ICT`.
- The active workload is still inside `SupplyChain_Gold_Warehouse.dbo.Usp_Refresh_ForecastAccuracy_Gold`; DMV shows the full procedure text under active `session_id = 226`.
- There is still no new forecast DQ batch:
  - `DQRunId = EA441173-6047-4304-90DD-FE98A14ED5D7`
  - `DQRunAtICT = 2026-07-03 15:54:30.776756`
- Because the terminal `INSERT INTO ForecastAccuracy_DW.DQForecastAccuracy ... FROM ForecastAccuracy_DW_Wrk.v_DQForecastAccuracy` has not emitted a newer batch yet, forecast mart has **not** fully completed.

**Conclusion:**
- Forecast is very near the end relative to earlier checks because it is still inside Gold, but it is not finished yet.
- Inventory has not started yet.

## 2026-07-06 14:43:00 ICT — Forecast Gold facts completed; terminal DQ insert still running/no batch yet

**Scope lock:**
- Read-only live Fabric + SQL progress poll.

**User instruction:**
- Check progress again.

**Actions executed:**
- Re-polled live Fabric job instances for `pl_backup_full_refresh`.
- Queried `sys.dm_exec_requests` for active warehouse requests.
- Queried `DW_Developer.TableDictionary_UpdateLog` for latest completed curated table updates.
- Queried latest `ForecastAccuracy_DW.DQForecastAccuracy` batch timestamp.

**Key findings:**
- Pipeline run `d276499a-e2fe-4a9d-b28c-82cf170c9509` remains `InProgress`.
- `TableDictionary_UpdateLog` shows forecast Gold curated objects have completed through:
  - `ForecastAccuracy_DW.FactForecastActual` at `2026-07-06T02:33:00.216667`
  - `ForecastAccuracy_DW.FactForecastKpi` at `2026-07-06T02:33:33.633333`
- Active DMV session `226` is still an `INSERT` inside `SupplyChain_Gold_Warehouse.dbo.Usp_Refresh_ForecastAccuracy_Gold`.
- Latest physical forecast DQ batch still has not changed:
  - `DQRunId = EA441173-6047-4304-90DD-FE98A14ED5D7`
  - `DQRunAtICT = 2026-07-03 15:54:30.776756`

**Conclusion:**
- Forecast mart is at the terminal part of Gold: main Gold tables are complete, but the final DQ insert has not finished/emitted a new batch yet.
- Inventory has not started yet.

## 2026-07-06 14:47:00 ICT — Forecast terminal DQ insert still running, no block detected

**Scope lock:**
- Read-only live Fabric + SQL progress poll.

**User instruction:**
- Check current pipeline progress.

**Actions executed:**
- Polled Fabric job instances for `pl_backup_full_refresh`.
- Queried live `sys.dm_exec_requests`.
- Queried latest physical `ForecastAccuracy_DW.DQForecastAccuracy` batch.
- Queried latest `DW_Developer.TableDictionary_UpdateLog` rows.

**Key findings:**
- Pipeline run `d276499a-e2fe-4a9d-b28c-82cf170c9509` remains `InProgress` at `2026-07-06 14:47 ICT`.
- Active SQL session `226` is still an `INSERT` inside `SupplyChain_Gold_Warehouse.dbo.Usp_Refresh_ForecastAccuracy_Gold`.
- Active request shows `blocking_session_id = 0`, so there is no SQL blocking session currently detected.
- Gold forecast curated objects remain completed through `ForecastAccuracy_DW.FactForecastKpi` (`LastUpdated = 2026-07-06T02:33:33.633333`).
- Latest physical DQ batch still has not changed:
  - `DQRunId = EA441173-6047-4304-90DD-FE98A14ED5D7`
  - `DQRunAtICT = 2026-07-03 15:54:30.776756`

**Conclusion:**
- Forecast is still at the final Gold/DQ insert phase.
- It has not emitted a new DQ batch yet, so inventory has not started yet.

## 2026-07-06 14:53:00 ICT — Forecast mart completed; pipeline advanced into Inventory W01

**Scope lock:**
- Read-only live Fabric + warehouse SQL progress and DQ check.

**User instruction:**
- Check current progress.

**Actions executed:**
- Polled Fabric job instances for `pl_backup_full_refresh`.
- Queried `sys.dm_exec_requests` for active SQL workload.
- Queried latest `ForecastAccuracy_DW.DQForecastAccuracy` batch and fail/pass split.
- Queried `DW_Developer.TableDictionary_UpdateLog` for latest completed table updates.

**Key findings:**
- Pipeline run `d276499a-e2fe-4a9d-b28c-82cf170c9509` remains `InProgress`.
- Forecast has completed and emitted a new DQ batch:
  - `DQRunId = 20B600BD-2F6B-4354-85BC-6A93131B3911`
  - `DQRunAtICT = 2026-07-06 14:34:01.828489`
  - result split: `31 PASS`, `1 FAIL` out of `32` rules.
- The only failed forecast DQ rule in the latest batch is:
  - `DQ_Bronze_Grain_InvoiceHeader` — `(InvoiceNumber, OrderNumber) must be unique`
- Live active SQL workload moved into inventory:
  - `INSERT INTO SupplyChain_Processing_Warehouse.InventoryHistory_Enh.InventorySnapshotWeekly_LOAD SELECT * FROM SupplyChain_Processing_Warehouse.InventoryHistory_Enh_Wrk.v_InventorySnapshotWeekly`
- `TableDictionary_UpdateLog` confirms latest completed inventory table:
  - `SupplyChain_Processing_Warehouse.InventoryHistory_Enh.InventorySnapshotWeekly` at `2026-07-06T02:52:48.986667`.

**Conclusion:**
- Forecast mart is complete.
- Forecast DQ improved to `31 PASS / 1 FAIL`; only `DQ_Bronze_Grain_InvoiceHeader` remains failed.
- Pipeline has advanced into `InventoryHealth_Silver_W01`.

## 2026-07-03 14:45:00 ICT — Live check of latest `pl_backup_full_refresh` failure via Fabric REST + pyodbc

**Scope lock:**
- Read-only live Fabric REST and warehouse SQL diagnostics.
- No live mutation.

**User instruction:**
- Ignore older context and check the latest run today using Fabric REST API and `pyodbc`.

**Actions executed:**
- Queried live Fabric pipeline job instances for `pl_backup_full_refresh` item `41948342-d7e7-4166-8638-9af0633e6a49`.
- Queried specific failed job instance `8397b46a-c12b-46a9-a428-6e9c3468b640`.
- Pulled live pipeline definition via `getDefinition`.
- Queried live `ETL_Framework.DW_Developer.AuditLog`, `OBJECT_DEFINITION`, `INFORMATION_SCHEMA.COLUMNS`, and live procedure lists via `pyodbc`.

**Key findings:**
- Latest run today is `8397b46a-c12b-46a9-a428-6e9c3468b640`, status `Failed`, window `2026-07-03T06:52:22Z` to `2026-07-03T07:31:53Z` (`13:52:22` to `14:31:53 ICT`).
- Fabric REST returns only generic pipeline-level failure (`Pipeline run Failed.`); no activity-level message was exposed by the endpoint used.
- `AuditLog` has no rows at or after `2026-07-03 06:40:00` UTC, so the latest failed run did not reach the point where `usp_RefreshCuratedTableFromView` writes `Process Start`.
- Live `Shared_DW_Wrk.v_DimWarehouse` has an extra column `WarehouseLocationOrg` not present in live `Shared_DW.DimWarehouse` final table.
- Live `usp_RefreshCuratedTableFromView` uses `INSERT INTO <load_table> SELECT * FROM <view>` with no explicit column list, so this live shape drift causes `Column name or number of supplied values does not match table definition.` when `DimWarehouse` is loaded.
- Repo file `02_marts/inventory_health/03_gold/Shared_DW_Wrk/v_DimWarehouse.sql` does not contain `WarehouseLocationOrg`; the extra column exists only in the live view definition, so this is live drift vs repo.
- Live pipeline definition also still reflects the older activity naming/order (`03_Inventory_Silver_W00`, etc.), so there is live-vs-repo pipeline drift as well.

**Conclusion:**
- Proven live SQL defect: `Shared_DW_Wrk.v_DimWarehouse` and `Shared_DW.DimWarehouse` are out of contract in live.
- Proven latest-run fact: the newest failed pipeline run did not write ETL audit rows, so its immediate failure point is above the ETL proc body (pipeline/service/invocation layer), not yet proven to be the `DimWarehouse` SQL mismatch.
- The `DimWarehouse` contract drift remains a real blocker/risk that can break Gold execution when that path is reached.

**Next concrete step:**
- If requested, inspect Fabric monitoring/activity detail by alternative API/UI path or run a targeted manual SQL smoke for `Shared_DW.DimWarehouse` to prove and fix the exact Gold failure path.

## 2026-07-03 15:25:00 ICT — Live fix for `DimWarehouse` contract drift + manual rerun from failed path

**Scope lock:**
- Live warehouse fix and manual rerun of failed-path wrapper procedures.
- No delete/drop beyond framework-controlled transient loader behavior inside existing ETL procedures.

**User instruction:**
- Find detailed error if possible, fix it, then rerun pipeline items from the failed point onward and skip what already passed.

**Actions executed:**
- Rechecked public Fabric REST job-instance endpoints for `pl_backup_full_refresh`; public API still exposed only generic `Pipeline run Failed`.
- Pulled live DataPipeline definition and confirmed live pipeline still has older W00/W01/W02 naming/order drift vs repo.
- Verified live SQL drift in `SupplyChain_Gold_Warehouse.Shared_DW_Wrk.v_DimWarehouse`: live view had extra column `WarehouseLocationOrg` while final table `Shared_DW.DimWarehouse` had 21-column contract.
- Applied live `CREATE OR ALTER VIEW` for `Shared_DW_Wrk.v_DimWarehouse` using the repo SQL from `02_marts/inventory_health/03_gold/Shared_DW_Wrk/v_DimWarehouse.sql`, removing the extra live-only column and restoring 21-column alignment.
- Verified live view column list now matches final table column count and order.
- Verified via `AuditLog` that `usp_RefreshCuratedTableFromView: SupplyChain_Gold_Warehouse.Shared_DW.DimWarehouse` changed from prior shape-mismatch errors to `Process Complete`.
- Manually reran the failed-path wrapper chain via `pyodbc`:
  - `07_Forecast_Gold` — completed in SQL; client-side result handling had a hanging/readback quirk, but AuditLog confirmed successful completion through `FactForecastKpi`.
  - `08_Inventory_Silver_W01` — `ok` (`37.46s`)
  - `09_Inventory_Silver_W02` — `ok` (`67.58s`)
  - `10_Inventory_Gold` — `ok` (`169.77s`)
- Verified latest shared-dim Gold audit rows now show `Shared_DW.DimCalendar` complete at `2026-07-03 02:59:35` UTC.
- Verified no user workload remains active on warehouse; only internal XE event stream request was present.

**Key findings:**
- Proven SQL root cause on live: `Shared_DW_Wrk.v_DimWarehouse` drifted from repo/final-table contract and broke the generic loader because `usp_RefreshCuratedTableFromView` uses `INSERT ... SELECT *`.
- Public Fabric REST still did not provide activity-level error detail for failed run `8397b46a-c12b-46a9-a428-6e9c3468b640`; only pipeline-level failure remained visible.
- Despite that API limitation, the actual data-path blocker was fixed and the downstream failed-path wrappers were rerun successfully.

**Verification evidence:**
- Gold shared dim counts/serving tables readable after rerun:
  - `Shared_DW.DimWarehouse` = `53`
  - `ForecastAccuracy_DW.FactForecastActual` = `236678381`
  - `ForecastAccuracy_DW.FactForecastKpi` = `154664337`
  - `InventoryHealth_DW.FactInventoryHealthFutureWeekEnding` = `3859396`
  - `InventoryHealth_DW.FactInventoryHealthSnapshot` = `3221743`

**Live changes:**
- `SupplyChain_Gold_Warehouse.Shared_DW_Wrk.v_DimWarehouse` altered live to match repo contract.
- Manual wrapper reruns executed live for steps 07 through 10 equivalent path.

**Conclusion:**
- `DimWarehouse` live drift is fixed.
- The failed path from Gold onward has been rerun successfully outside the pipeline.
- The Fabric pipeline run history still shows the original failed run as failed; only the underlying data path has been repaired and completed manually.

## 2026-07-03 15:11:00 ICT — Live rerun of DQ view and new DQ batch status

**Scope lock:**
- Live DQ rerun only for warehouse-backed DQ view(s) currently discoverable in active path.
- No structural schema change.

**User instruction:**
- Rerun each DQ view to generate a fresh DQ table batch and report fail/pass status.

**Actions executed:**
- Queried live metadata for `v_DQ%` views and `DQ%` tables in `SupplyChain_Gold_Warehouse`.
- Confirmed active discoverable DQ path is `ForecastAccuracy_DW_Wrk.v_DQForecastAccuracy` -> `ForecastAccuracy_DW.DQForecastAccuracy`.
- Executed live insert:
  `INSERT INTO ForecastAccuracy_DW.DQForecastAccuracy (...) SELECT ... FROM ForecastAccuracy_DW_Wrk.v_DQForecastAccuracy`.
- Waited for batch completion and queried the latest `DQRunId` summary from the destination DQ table.

**Key findings:**
- New DQ batch completed with `DQRunId = 9732C3CB-3C30-4144-B013-BAB5291E4D01`.
- `DQRunAtUTC = 2026-07-03T08:04:07.964177` (`15:04:07 ICT`).
- Total rows inserted: `47`.
- Result split: `42 PASS`, `5 FAIL`.

**Failed rules:**
- `DQ_B2S2_Forecast_Qty`
- `DQ_B2S2_Invoice_Qty`
- `DQ_B2S2_OpenOrder_Qty`
- `DQ_Bronze_Grain_DemandForecastSnapshotDaily`
- `DQ_Bronze_Grain_InvoiceHeader`

**Conclusion:**
- Fresh DQ output has been generated successfully.
- Current live DQ status is stable enough to classify: 5 active failures remain and 42 checks pass.

**Next concrete step:**
- If needed later, align the live `pl_backup_full_refresh` definition to the repo’s current 10-step ordering/naming so pipeline history and manual runbook are consistent again.

## 2026-07-03 15:33:30 ICT — Root-cause audit of `DQ_B2S2_OpenOrder_Qty` and validation reruns

**Scope lock:**
- Live SQL audit of Forecast Accuracy DQ open-order rule.
- Minimal live validation reruns only for affected Forecast Accuracy Silver waves and DQ append.

**User instruction:**
- Audit `DQ_B2S2_OpenOrder_Qty` deeply, including DQ SQL, source data, and ETL code; explain the result and fix path.

**Actions executed:**
- Read repo SQL for:
  - `ForecastAccuracy_DW_Wrk.v_DQForecastAccuracy`
  - `OpenOrderHistory_Enh_Wrk.v_OpenOrderLineLevel`
  - `OpenOrderHistory_Enh_Wrk.v_OpenOrderMonthly`
  - `SalesHistory_Enh_Wrk.v_ActualDemandMonthly`
  - `Staging_Wrk.v_{Codatan,Extorit,Comast,Extord}`
- Queried live sums and key-level diffs between:
  - bronze raw open order logic (`Codatan` + `Comast` + `Extord` + `Extorit`)
  - live `_Wrk.v_OpenOrderLineLevel`
  - persisted `OpenOrderHistory_Enh.OpenOrderLineLevel`
  - `ActualDemandMonthly` open-order slice
- Verified live duplicate/join-multiplier checks:
  - `Extorit` duplicate `(IORD, ISEQ)` keys = `0`
  - `Comast` duplicate `ORDNO` keys = `0`
  - `Extord` duplicate `XORDNO` keys = `0`
  - no multi-row join explosion found in open-order base join
- Ran validation rerun:
  - `dbo.Usp_Refresh_ForecastAccuracy_Silver_W01`
  - then checked DQ view live
  - then `dbo.Usp_Refresh_ForecastAccuracy_Silver_W02`
  - then checked DQ view live again

**Key findings:**
- `DQ_B2S2_OpenOrder_Qty` fail was **not** caused by duplicate joins or bad transform logic in `v_OpenOrderLineLevel`.
- Proven totals before validation rerun:
  - bronze raw = `410992`
  - `_Wrk.v_OpenOrderLineLevel` = `410992`
  - persisted `OpenOrderHistory_Enh.OpenOrderLineLevel` = `410657`
- Therefore the transform view matched raw source exactly; only the persisted Silver W01 table was stale versus the current source at DQ-runtime.
- Key-level diffs showed whole-order churn between current source/view and persisted table (examples: `C686435` present in current view but absent in persisted table; `C402372`/`C921427` present in persisted table but absent in current view), which is consistent with mutable open orders changing after the earlier W01 load.
- `DQ_S2S1_OpenOrder_Qty` was `PASS` before the validation rerun, proving W01 -> W02 business logic was internally consistent on the earlier shared snapshot.
- After rerunning only W01, `DQ_B2S2_OpenOrder_Qty` flipped to `PASS` immediately, while `DQ_S2S1_OpenOrder_Qty` temporarily flipped to `FAIL`; this proved the mismatch moved from Bronze->W01 to W01->W02 because W02 was now stale.
- After rerunning W02, the live DQ view again showed both open-order rules as `PASS`.

**Conclusion:**
- Root cause is **snapshot drift / timing design**, not a coding bug in the open-order transform.
- `DQ_B2S2_OpenOrder_Qty` is architecturally unstable because it compares mutable live bronze raw data to a persisted W01 table later in the run or on-demand reruns.

**Next concrete step:**
- If code change is approved later, fix the DQ contract rather than the open-order transform:
  - either compare bronze raw to `_Wrk.v_OpenOrderLineLevel` for a deterministic transform check
  - or introduce a run-consistent source snapshot/watermark so Bronze->Silver comparisons use the same cut of data.

## 2026-07-03 16:05:00 ICT — Applied Forecast Accuracy DQ contract fixes for false Bronze->Silver mismatches

**Scope lock:**
- Repo + live DQ view contract fix only for Forecast Accuracy DQ logic.
- No business-table schema mutation.

**User instruction:**
- If the remaining DQ failures are the same type of contract/snapshot issue, fix them so false fails are removed.

**Actions executed:**
- Audited remaining rules by code path and targeted live evidence.
- Verified `InvoiceHeader` is a true source-quality issue:
  - current rule grain `(InvoiceNumber, OrderNumber)` duplicates exist
  - even full join key `(InvoiceNumber, InvoiceDate, OrderDate, OrderNumber)` still has `82` duplicate groups
- Confirmed live existence of `SupplyChain_Processing_Warehouse.Staging_Wrk.v_DemandForecastSnapshotDaily`.
- Updated repo file `02_marts/forecast_accuracy/03_gold/ForecastAccuracy_DW_Wrk/v_DQForecastAccuracy.sql` and applied the same logic live with `CREATE OR ALTER VIEW`.

**DQ contract changes applied:**
- `DQ_B2S2_Invoice_Qty` now compares bronze raw invoice quantity to `SalesHistory_Enh_Wrk.v_InvoiceDetailLineLevel` instead of persisted `SalesHistory_Enh.InvoiceDetailLineLevel`.
- `DQ_B2S2_OpenOrder_Qty` now compares bronze raw open-order quantity to `OpenOrderHistory_Enh_Wrk.v_OpenOrderLineLevel` instead of persisted `OpenOrderHistory_Enh.OpenOrderLineLevel`.
- `DQ_B2S2_Forecast_Qty` now compares bronze raw canonical-dedup forecast quantity to `Staging_Wrk.v_DemandForecastSnapshotDaily` instead of persisted `Staging.DemandForecastSnapshotDaily`.
- `DQ_Bronze_Grain_DemandForecastSnapshotDaily` grain was widened from 5-key to the canonical 7-key used by staging dedupe:
  `(dfcItem, dfcWarehouse, dfcFiscalMonth, dfcSnapshot, DfcCustomerGroups, dfcFCSTTypeCode, dfcMgmtCode)`.

**Key findings:**
- `DQ_B2S2_OpenOrder_Qty` is confirmed false-fail-by-snapshot and was fixed by contract.
- `DQ_B2S2_Forecast_Qty` followed the same structural problem: raw canonical-dedup was being compared to a persisted staging table instead of the same-time `_Wrk` transform surface.
- `DQ_B2S2_Invoice_Qty` is not yet proven to be false-fail-only; because `InvoiceHeader` has true duplicate groups even on the full join key, the invoice transform can still multiply rows and remain a real fail after the contract fix.
- `DQ_Bronze_Grain_InvoiceHeader` remains a true source-quality rule and should not be relaxed.

**Verification status:**
- Live `ForecastAccuracy_DW_Wrk.v_DQForecastAccuracy` was altered successfully.
- A fresh DQ history insert was triggered after the live change; warehouse-side batch was still computing at context time, so final post-fix history-row statuses were not yet captured in this entry.

**Conclusion:**
- False Bronze->Silver comparison rules for open order and forecast were fixed at the DQ-contract level.
- Invoice-related failures still require source-quality remediation if they continue after the contract update.

## 2026-07-02 17:05:00 ICT — Fixed Inventory Health Silver wave catalog mismatch and rebuilt lineage snapshot

**Scope lock:**
- Repo/catalog/lineage alignment only.
- No live Fabric SQL procedure mutation.

**User instruction:**
- Recheck the Inventory Health Silver wave renumbering from `W00/W01/W02` to `W01/W02/W03`.
- Fix the issue where the two old `W00` tables appeared to be merged into later waves in lineage.

**Actions executed:**
- Re-read active wrapper SQL for:
  - `Usp_Refresh_InventoryHealth_Silver_W01`
  - `Usp_Refresh_InventoryHealth_Silver_W02`
  - `Usp_Refresh_InventoryHealth_Silver_W03`
- Re-read `03_operations/orchestration/inventory_health/manifest.json`.
- Re-read `02_marts/inventory_health/05_catalog/run_order.json`.
- Found mismatch: wrapper SPs already had W01 with only:
  - `InventorySnapshotWeekly`
  - `AtpWeekEnding`
  but `run_order.json` still labeled the old W01 body as `wave: 1`.
- Updated `02_marts/inventory_health/05_catalog/run_order.json` so:
  - W01 = only `InventorySnapshotWeekly`, `AtpWeekEnding`
  - W02 = `PurchaseOrderSnapshotHistorical`, `ManufacturingOrderSnapshotDaily`, `HoldingTransferSnapshotDaily`, `ForecastSnapshotWeekly`, `SupplyPlanDetail`, `ItemBalanceHistorical_WithInTransit`, `SafetyStockHelper`, `InvoiceDetailLineLevel`
  - W03 = `AFIStatusSnapshotWeekly`, `AwdHelper`, `LastInvoiceWeekly`, `Cogs52WWeekly`
- Rebuilt lineage snapshot using Azure CLI auth mode:
  - `FABRIC_USE_AZ_CLI=1 PYTHONPATH=. python3 -m scanner.cli --out site/public/lineage_snapshot.json`
- Mirrored rebuilt snapshot to:
  - `05_tools/06_lineage_portal/site/out/lineage_snapshot.json`
  - `05_tools/06_lineage_portal/site/dist/lineage_snapshot.json`
- Verified rebuilt snapshot now places:
  - `ManufacturingOrderSnapshotDaily` in lane `02 Silver W02`
  - old W00 tables remain in W01

**Files changed:**
- `02_marts/inventory_health/05_catalog/run_order.json`
- `05_tools/06_lineage_portal/site/public/lineage_snapshot.json`
- `05_tools/06_lineage_portal/site/out/lineage_snapshot.json`
- `05_tools/06_lineage_portal/site/dist/lineage_snapshot.json`
- `00_CONTEXT/current.md`

**Conclusion:**
- Inventory Health Silver wave numbering is now internally consistent across wrapper SPs, mart catalog, and lineage snapshot.

**Next concrete step:**
- If needed, refresh/publish the lineage portal static site so the UI picks up the rebuilt snapshot.

## 2026-07-02 16:40:00 ICT — ETL framework live sync, pattern audit, and repo documentation refresh

**Scope lock:**
- Live `ETL_Framework` sync/audit in DEV workspaces.
- Repo documentation refresh to match live state.

**User instruction:**
- Sync local `Enterprise SupplyChain-Dev.ETL_Framework` from `EnterpriseData-Dev`.
- Audit framework patterns step by step.
- Fix what is truly broken, then update repo docs to reflect the final state.

**Actions executed:**
- Connected to both live `ETL_Framework` warehouses via `pyodbc` + Entra token.
- Compared live schemas, tables, procedures, functions, and views between source and target.
- Applied additive sync from source live to target live.
- Removed `DW_Developer.Usp_TableFromParquet_RowADF` from target after confirming the source object is internally broken.
- Patched live `DW_Developer.Usp_SnapshotLoad` in target to:
  - accept both full `abfss://...` and relative paths
  - avoid appending `/` to `.parquet` file paths
  - write `AuditLog`, `TableDictionary`, and `TableDictionary_UpdateLog`
- Audited runtime patterns:
  - `Snapshot`
  - `Append`
  - `Upsert/Insert`
  - `DateKey/DateRange`
  - `CDC`
- Confirmed Forecast Accuracy DQ should remain on direct insert, not generic framework loader.
- Updated repo docs and context.

**Key findings:**
- `Enterprise SupplyChain-Dev.ETL_Framework` is now synchronized to the usable runtime surface from `EnterpriseData-Dev`.
- `Usp_TableFromParquet_RowADF` was not a valid runtime candidate because it referenced non-existent `FabricLoad` columns and used a framework table as scratch staging.
- `Usp_SnapshotLoad` was not usable as-is because live `Snapshot` metadata commonly stores full `abfss://...` paths while the source proc hardcoded a prefix and assumed relative paths.
- `Append` engine is usable after sync; the remaining local problem is a business metadata row with missing configuration.
- `Upsert/Insert` and `CDC` currently have no active rows in the SupplyChain target.
- `DateKey/DateRange` rows in SupplyChain target have the minimum required metadata.
- Generic framework loading is still not the right fit for Forecast Accuracy DQ history append.

**Files changed:**
- `00_CONTEXT/current.md`
- `01_docs/enterprise-etl-framework/README.md`
- `01_docs/enterprise-etl-framework/2026-07-02_live_sync_and_pattern_audit.md`
- `README.md`
- `CLAUDE.md`

**Live changes:**
- `Enterprise SupplyChain-Dev.ETL_Framework.DW_Developer.Usp_SnapshotLoad` patched live.
- `Enterprise SupplyChain-Dev.ETL_Framework.DW_Developer.Usp_TableFromParquet_RowADF` dropped live.
- Additive framework object sync applied from `EnterpriseData-Dev.ETL_Framework`.

**Conclusion:**
- Local framework and repo documentation are now aligned enough to treat the current DEV runtime as the approved baseline.

**Next concrete step:**
- If needed later, introduce a dedicated framework pattern for history-style DQ append instead of forcing DQ through `usp_IncrementalTableLoad`.

## 2026-07-01 14:55:00 ICT — `pl_backup_full_refresh` completed successfully

**Scope lock:**
- Read-only Fabric verification + summary.
- No live mutation.

**User instruction:**
- Check latest status, then if complete summarize total runtime, per-SP runtime, and table-level evidence.

**Actions executed:**
- Polled Fabric pipeline run `d9776bab-a6aa-48ec-b498-5ca13b61b9ae`.
- Queried `ETL_Framework.DW_Developer.AuditLog`.
- Queried final Gold fact row counts.

**Key findings:**
- Pipeline status is `Completed`.
- Start: `2026-07-01T06:28:18.6343822Z`
- End: `2026-07-01T07:21:40.2133333Z`
- End-to-end wall clock runtime: `53m21.6s`
- Sum of wrapper activity durations: `52m52.6s`
- The new 10-step flow completed successfully in the expected order.

**Wrapper activity durations:**
- `01_Shared_ReferenceMaster` `59.721s`
- `02_Shared_Staging` `801.943s`
- `03_Inventory_Silver_W00` `65.190s`
- `04_Forecast_Silver_W01` `76.507s`
- `05_Forecast_Silver_W02` `327.522s`
- `06_Forecast_Silver_W03` `44.682s`
- `07_Forecast_Gold` `112.224s`
- `08_Inventory_Silver_W01` `626.103s`
- `09_Inventory_Silver_W02` `288.971s`
- `10_Inventory_Gold` `769.689s`

**Table-level evidence from AuditLog:**
- `ReferenceMaster_Enh` 11 tables loaded in step 01.
- `Staging.DemandForecastSnapshotDaily` loaded in step 02.
- `InventoryHistory_Enh` W00/W01/W02 tables loaded in steps 03/08/09.
- `ForecastAccuracy` Silver and Gold tables loaded in steps 04/05/06/07.
- `InventoryHealth` Gold tables loaded in step 10, ending with `FactInventoryHealthSnapshot`.

**Naming convention update:**
- InventoryHealth silver waves are now standardized as W01→W03 in repo docs and manifests.
- The July 1 run log below keeps the old W00 labels for historical accuracy.
- Live Fabric inventory stored procedures have now been aligned to W01→W03.
- `05_tools/06_lineage_portal/site/public/lineage_snapshot.json` was rebuilt from live Fabric after the sync.

**Final fact row counts:**
- `ForecastAccuracy_DW.FactForecastActual` = `236,740,098`
- `ForecastAccuracy_DW.FactForecastKpi` = `154,664,289`
- `InventoryHealth_DW.FactInventoryHealthFutureWeekEnding` = `3,856,954`
- `InventoryHealth_DW.FactInventoryHealthSnapshot` = `3,327,510`

**Files changed:**
- `00_CONTEXT/current.md` — updated with completion evidence and timings.

**Conclusion:**
- The new `pl_backup_full_refresh` 10-step overwrite flow is working end-to-end.
- No failure observed in the latest run.

**Next concrete step:**
- If needed, capture the final pipeline definition and keep this as the approved overwrite baseline.

## 2026-07-01 14:35:00 ICT — Latest `pl_backup_full_refresh` checkpoint

**Scope lock:**
- Read-only Fabric run-status monitoring.
- No live mutation.

**User instruction:**
- Check latest progress.

**Actions executed:**
- Polled Fabric pipeline run `d9776bab-a6aa-48ec-b498-5ca13b61b9ae`.
- Queried latest `ETL_Framework.DW_Developer.AuditLog` rows.

**Key findings:**
- Pipeline is still `InProgress`.
- Latest Gold table progress:
  - `InventoryHealth_DW.ProjectedInventoryHealthSubStatus` `Process Complete`
  - `InventoryHealth_DW.InventoryHealthSubStatusWeekly` `Process Complete`
  - `InventoryHealth_DW.InventoryClassificationQtyWeekly` `Process Complete`
  - `InventoryHealth_DW.FactInventoryHealthFutureWeekEnding` `Process Start`
- The run has moved into the final Gold fact stage and has not failed yet.

**Next concrete step:**
- Continue polling until step 10 completes or fails.

## 2026-07-01 14:20:00 ICT — Latest `pl_backup_full_refresh` checkpoint

**Scope lock:**
- Read-only Fabric run-status monitoring.
- No live mutation.

**User instruction:**
- Check latest progress.

**Actions executed:**
- Polled Fabric pipeline run `d9776bab-a6aa-48ec-b498-5ca13b61b9ae`.
- Queried latest `ETL_Framework.DW_Developer.AuditLog` rows.

**Key findings:**
- Pipeline is still `InProgress`.
- Latest wrapper activity is now in the Gold section.
- AuditLog latest rows show:
  - `InventoryHealth_DW.Cogs52WWeekly` `Process Complete`
  - `InventoryHealth_DW.InventoryHealthSubStatusWeekly` `Process Complete`
  - `InventoryHealth_DW.InventoryClassificationQtyWeekly` likely completed earlier in step 10 flow
  - `Shared_DW.DimCalendar`, `DimProduct`, `DimWarehouse` completed
  - `InventoryHealth_DW.DimVendor` completed
  - `InventoryHealth_DW.ProjectedInventoryHealthSubStatus` is the latest `Process Start`
- Interpretation: step `09_Inventory_Silver_W02` is complete and step `10_Inventory_Gold` is actively loading.

**Next concrete step:**
- Continue polling until step 10 finishes or the run fails.

## 2026-07-01 14:05:00 ICT — Latest `pl_backup_full_refresh` progress

**Scope lock:**
- Read-only Fabric run-status monitoring.
- No live mutation.

**User instruction:**
- Check latest progress and, if done, summarize timings and flow health.

**Actions executed:**
- Polled Fabric pipeline run `d9776bab-a6aa-48ec-b498-5ca13b61b9ae`.
- Queried `ETL_Framework.DW_Developer.AuditLog` for latest table-level activity.

**Key findings:**
- Pipeline is still `InProgress`.
- Completed wrapper activities: 01 through 08.
- Current wrapper activity: `09_Inventory_Silver_W02` is `InProgress`.
- Table-level evidence inside step 09:
  - `InventoryHistory_Enh.AFIStatusSnapshotWeekly` `Process Complete`
  - `InventoryHistory_Enh.AwdHelper` `Process Complete`
  - `InventoryHistory_Enh.LastInvoiceWeekly` `Process Start`
  - `InventoryHistory_Enh.Cogs52WWeekly` not seen yet
- No new error surfaced in the latest poll.

**Current interpretation:**
- New 10-step flow is executing in the expected sequence.
- It has not finished, so final full-run timing and table-level totals are not yet available.

**Next concrete step:**
- Continue monitoring until `09_Inventory_Silver_W02` finishes and step 10 starts or the run fails.

## 2026-07-01 13:45:00 ICT — `pl_backup_full_refresh` progress checkpoint

**Scope lock:**
- Read-only Fabric run-status monitoring.
- No live mutation.

**User instruction:**
- Check current progress of the rerun.

**Actions executed:**
- Polled Fabric pipeline run `d9776bab-a6aa-48ec-b498-5ca13b61b9ae`.
- Queried latest activity runs for the same run id.

**Key findings:**
- Pipeline is still `InProgress`.
- Completed successfully:
  - `01_Shared_ReferenceMaster`
  - `02_Shared_Staging`
  - `03_Inventory_Silver_W00`
  - `04_Forecast_Silver_W01`
  - `05_Forecast_Silver_W02`
  - `06_Forecast_Silver_W03`
  - `07_Forecast_Gold`
- Current step: `08_Inventory_Silver_W01` is `InProgress`.
- No new failure on the current poll.

**Next concrete step:**
- Continue polling until step 08 finishes or the run fails.

## 2026-07-01 13:00:00 ICT — Fixed Fabric DataPipeline binding and reran `pl_backup_full_refresh`

**Scope lock:**
- Live Fabric DataPipeline definition update + read-only run monitoring.
- No SP body edits.

**User instruction:**
- Fix the pipeline bug, rerun full pipeline, and check whether it still fails or is now running.

**Actions executed:**
- Updated live Fabric item `pl_backup_full_refresh` definition to add `linkedService` bindings to every `SqlServerStoredProcedure` activity.
- Removed empty `storedProcedureParameters` from the live activity contract to match Fabric’s expected schema.
- Triggered a fresh manual run on the same pipeline item.
- Polled run status and activity runs.

**Key findings:**
- The original failure was definition-level, not SP timeout.
- After the fix, the new run advanced successfully:
  - `01_Shared_ReferenceMaster` completed `Succeeded` in `59.7s`.
  - `02_Shared_Staging` started and is currently `InProgress`.
- Current run id: `d9776bab-a6aa-48ec-b498-5ca13b61b9ae`.
- Current pipeline status: `InProgress`.
- This confirms the linked-service bug is fixed. The remaining work is normal pipeline execution monitoring, not definition repair.

**Files changed:**
- `03_operations/orchestration/backup_pipeline/pl_backup_full_refresh.json` — updated repo copy to reflect linked-service bindings.
- `00_CONTEXT/current.md` — updated with fix + live run status.

**Blocker/risk:**
- Full pipeline has not completed yet, so downstream runtime issues may still appear later in the run.

**Next concrete step:**
- Continue monitoring run `d9776bab-a6aa-48ec-b498-5ca13b61b9ae` until completion or first downstream failure.

## 2026-07-01 13:20:00 ICT — Verified `pl_backup_full_refresh` failure root cause

**Scope lock:**
- Read-only Fabric job status check + repo definition comparison.
- No live Fabric/SQL/Power BI mutation.

**User instruction:**
- Check whether the run is still active.
- Distinguish Fabric pipeline failure vs local `pyodbc` execution vs timeout on heavy SPs.

**Actions executed:**
- Queried Fabric job instance `ee842ea2-445b-4317-81ab-6ad54dbef870` for pipeline item `pl_backup_full_refresh`.
- Queried pipeline job instance list for the item to confirm there is only one recent run.
- Pulled live pipeline definition via Fabric `getDefinition`.

**Key findings:**
- Run is not still running. Fabric reports status `Failed`.
- Run window: `2026-07-01T05:41:46.8833333Z` to `2026-07-01T05:42:43.73Z` (`2026-07-01 12:41:46` to `12:42:43 ICT`).
- Failure happened on activity `01_Shared_ReferenceMaster`, with error `2109`.
- Error text: `Cannot find linked service linkedServiceName in the activity or the linked service has the wrong definition.`
- The pipeline failed before reaching the heavier downstream SPs, so there is no evidence this was a timeout caused by SP weight.
- Repo `pl_backup_full_refresh.json` contains only SP activity metadata; the live Fabric runtime is the component complaining about linked service binding.

**Files changed:**
- `00_CONTEXT/current.md` — updated with verified run status and root cause.

**Blocker/risk:**
- Need to inspect the live Fabric pipeline activity binding / linked service configuration, not the SP bodies, to fix this failure.

**Next concrete step:**
- Check the live `pl_backup_full_refresh` activity connection binding in Fabric UI/API and compare with any known working `SqlServerStoredProcedure` pipeline item.

## 2026-06-30 11:30:00 ICT — Bronze DQ fix plan for 6 tables + live downstream impact verification

**Scope lock:**
- Read-only live Fabric/SQL diagnostic queries + plan file creation.
- No live Fabric/SQL/Power BI mutation.
- No wrapper SP execution.

**User instruction:**
- Verify Bronze source DQ cho 6 bảng đầu (có US feedback) trên Fabric live.
- Check downstream impact: Silver/Gold output uniqueness, measure impact, SUM double-count risk.
- Tạo plan file cho fix 6 bảng + 5 bảng còn lại (tables 7-11).

**Actions executed:**
- Ran `audit_bronze_source_freshness_range.py` — 33 tables freshness range audit (MIN/MAX date span check, pass window 2023-01-01 → 2026-06-01).
- Ran `check_bronze_dq_downstream_impact.py` — live diagnostic for 6 tables: Silver output uniqueness, blank key measure impact, dedup determinism, Silver SUM double-count risk.
- Verified via Fabric REST + MCP OneLake: `Enterprise_Lakehouse` confirmed live in `Enterprise SupplyChain-Dev`.
- Combined analysis with US team feedback (Rakesh/DE) + live evidence.

**Key findings:**
- #1 ItemBalance: Silver ROW_NUMBER ORDER BY OnHandQty DESC = arbitrary tie-break, cần business confirm.
- #2 ITBEXT: Gold DimProduct 782,125 unique / 0 dup — GROUP BY+MAX self-protects. No code change.
- #3 ITMRVA: Silver 607,714 unique / 0 dup — ROW_NUMBER+STID filter works. Need verify Gold consumer.
- #4 TFRDTL: Silver 1,669 rows / 0 blank / 0 dup — JOIN ngầm filter blank. 41 blank rows có DTFRQT=32,756 cần DE confirm.
- #5 InvoiceDetail: DQ grain sai (OriginalSequenceNumber NULL = expected cho regular sales). Silver IH 0 dup at correct 5-col grain. FA variant cần align.
- #6 DemandForecast: Staging CÓ dedup (7-col partition, 0 dup at correct grain). Risk: Silver GROUP BY 5-col có thể double-count SUM.

**Files changed:**
- `05_tools/01_dq/audit_bronze_source_freshness_range.py` — NEW: freshness range audit script.
- `05_tools/01_dq/check_bronze_dq_downstream_impact.py` — NEW: downstream impact diagnostic script.
- `01_docs/runbook/artifacts/20260629_bronze_source_freshness_range_audit/` — NEW: freshness range audit results (JSON/CSV/MD).
- `01_docs/runbook/artifacts/20260629_bronze_dq_downstream_impact_check/` — NEW: downstream impact results (JSON/MD).
- `01_docs/plans/2026-06-30_bronze_dq_fix_plan_6_tables.md` — NEW: final fix plan with 6-table audit table + step-by-step execution.

**Plan summary:**
- Bucket A (document only): 3 tables (#1, #3, #4)
- Bucket C (grain mismatch doc): 1 table (#2)
- Bucket B-low (fix DQ grain + align view): 1 table (#5) — only confirmed code change
- Bucket A + verify SUM: 1 table (#6) — potential code change pending verify
- Open tickets: 2 (#1 OnHandQty tie-break, #4 32K pending transfers)

**Next concrete step:**
- Execute Phase 0 verify for #6 DemandForecast Silver SUM double-count.
- Verify #3 ITMRVA Gold consumer filter pattern.
- Execute #5 InvoiceDetail DQ grain fix + FA view align (after US confirm OriginalSequenceNumber semantics).
- Create follow-up plan for tables 7-11.

## 2026-06-27 00:10:00 ICT — Fixed lineage portal client error: removed motion + cmdk incompatible with static export

**Scope lock:**
- Lineage portal frontend only.
- No live Fabric/SQL/Power BI mutation.

**User symptom:**
- "Application error: a client-side exception has occurred while loading" on deployed GitHub Pages.

**Root cause:**
- `motion` (Motion v12.42.0) and/or `cmdk` (v1.1.1) incompatible with Next.js 15 static export on GitHub Pages.
- `motion/react` caused a client-side React exception during hydration.
- Bundle went from 119 kB to 62.6 kB after removal.

**Fix applied:**
- Removed all `motion/react` imports from App.tsx, Sidebar.tsx, DetailPanel.tsx, LineageTableNode.tsx.
- Removed `cmdk` import and CommandPalette component usage.
- Replaced motion components with plain HTML elements (`<div>`, `<header>`, `<section>`, `<aside>`).
- Added ErrorBoundary component wrapping the app to surface future client errors with full stack trace.
- Kept all non-motion UX enhancements:
  - Sidebar with layer chips, badge counts, collapse toggle (Cmd+B)
  - Lane column headers above graph
  - Color Legend (inline HTML)
  - Loading skeleton (CSS-only)
  - Empty state with reset filters button
  - Keyboard shortcuts (Cmd+B, Escape)
  - Enhanced CSS (select wrapper, layer chips, lane headers, legend, etc.)

**Verification:**
- `npm run build` passed (62.6 kB).
- `npm run typecheck` passed (0 errors).
- GitHub Actions `Build Lineage Portal` run succeeded: commit `43588da3`.
- Pages URL returned HTTP 200.
- Snapshot: 85 nodes, 117 edges.

**Lost temporarily:**
- Motion animations (fade-in, slide-in, pulse) — can replace with CSS keyframe animations.
- Cmd+K Command Palette — can replace with custom search modal or wait for cmdk compatibility fix.

**Next concrete step:**
- If page is stable, re-add animations using CSS keyframes (no motion dependency).
- Re-add command palette using a lighter custom implementation.

## 2026-06-26 18:00:00 ICT — Full UX upgrade for lineage portal

**Scope lock:**
- Lineage portal frontend only (`05_tools/06_lineage_portal/site/`).
- No live Fabric/SQL/Power BI mutation.
- No scanner/backend changes.

**User instruction:**
- Nâng cấp full UX lineage portal vì "UX chưa được xịn xò với thân thiện lắm".

**Changes implemented:**

1. **Cmd+K Command Palette** (`panels/CommandPalette.tsx` — NEW):
   - `cmdk`-based search with Cmd+K / Ctrl+K toggle.
   - Search all tables, switch mart/layer, toggle support nodes, download snapshot.
   - Dark glass-morphism styling with layer badges on each result.
   - Escape to close.

2. **Sidebar nâng cấp** (`panels/Sidebar.tsx` — NEW, extracted from App.tsx):
   - Collapse/expand toggle with `motion` animation (Cmd+B shortcut).
   - Layer chips instead of plain select (clickable badges with counts).
   - Custom select wrapper with chevron.
   - Search badge showing match count (e.g., "12/88").
   - Sidebar footer showing Cmd+K hint.

3. **Motion animations across all components:**
   - `motion/react` imports in all components.
   - DetailPanel slides in from right, slides out on close.
   - Sidebar collapses/expands with smooth width animation.
   - Loading skeleton with pulse animation.
   - Empty state fades in.
   - Topbar fades in on load.
   - Warning band animates open.
   - Node cards scale in on mount.
   - Legend fades in with delay.

4. **Lane column headers** — computed from layout positions, showing "Bronze", "Silver W00", "Gold W30", "Semantic" above each column with left-border color coding.

5. **Color Legend** (`panels/Legend.tsx` — NEW):
   - Bottom-left overlay showing Bronze/Silver/Gold/Semantic with colors and descriptions.

6. **Keyboard shortcuts:**
   - `Cmd+K` → Command palette
   - `Cmd+B` → Toggle sidebar
   - `Escape` → Close panel / clear search

7. **Loading skeleton** — Animated pulse skeleton with title, subtitle, and 4 cards.

8. **Empty state** — When filters return 0 nodes, shows search icon + message + "Reset all filters" button.

9. **Node hover tooltip** — `title` attribute on table node showing layer, wave, schema.

10. **Enhanced CSS** — Smooth transitions on hover states, edge glow effects, polished typography, layer chip active states, command palette dark theme.

**Files changed:**
- `05_tools/06_lineage_portal/site/src/App.tsx` — rewritten with all new components
- `05_tools/06_lineage_portal/site/src/styles/app.css` — full rewrite with ~200 new lines
- `05_tools/06_lineage_portal/site/src/graph/LineageTableNode.tsx` — motion animation + tooltip
- `05_tools/06_lineage_portal/site/src/panels/DetailPanel.tsx` — motion slide-in
- `05_tools/06_lineage_portal/site/src/panels/CommandPalette.tsx` — NEW
- `05_tools/06_lineage_portal/site/src/panels/Sidebar.tsx` — NEW
- `05_tools/06_lineage_portal/site/src/panels/Legend.tsx` — NEW

**Verification:**
- `npm run build` passed (Next.js 15.5.19, static export).
- `npm run typecheck` passed (0 errors).
- `npm audit --omit=dev` returned `found 0 vulnerabilities`.
- Python scanner tests: `10 tests, OK`.
- Python compile: passed.

**Current handoff:**
- UX upgrade is complete and ready for deploy.
- Commit/push + trigger `Build Lineage Portal` with `scan_mode=live` to deploy.
- Deployed URL: `https://ankinguyen-engineer-2002.github.io/data-architecture-microsoft-medallion-vietnam-data-hub/`

## 2026-06-26 17:15:00 ICT — Renamed AGENTS.md to CLAUDE.md for Claude Code compatibility

**Scope lock:**
- Repo file rename and reference update only.
- No live Fabric/SQL/Power BI mutation.

**User instruction:**
- Đọc và scan toàn bộ repo, tập trung `00_CONTEXT/`, đọc `AGENTS.md` sau đó sửa thành `CLAUDE.md`.

**Actions executed:**
- Read all files in `00_CONTEXT/` (current.md, all dated chunks, README.md).
- Read `AGENTS.md` complete (renamed to `CLAUDE.md`).
- Scanned repo structure and key architecture docs.
- Renamed `AGENTS.md` → `CLAUDE.md`.
- Updated self-reference inside `CLAUDE.md`: title + context logging rule.
- Updated references in active operating files:
  - `README.md` (source-of-truth order)
  - `00_CONTEXT/README.md` (sync rule)
  - `01_docs/runbook/connectivity_playbook.md`
  - `01_docs/decisions/ADR-009-repo-operating-model.md`
  - `01_docs/onboarding/de_onboarding.md`
  - `00_CONTEXT/current.md` (forward-looking resume instructions)
- Left historical references in dated context chunks and plan documents as-is (accurate historical record).

**Current handoff:**
- `CLAUDE.md` is now the canonical agent instruction file.
- All active docs reference `CLAUDE.md`.
- Historical context chunks correctly document the era when the file was named `AGENTS.md`.

## 2026-06-26 16:33:03 ICT — Configured Claude Code with AI Box fallback model

**Scope lock:**
- Local Claude Code / VS Code / shell configuration only.
- No repo business logic, Fabric, SQL, Power BI, or cloud mutation.
- No API key persisted into repo context.

**User instruction:**
- Configure Claude Code to use existing AI Box API because current setup returned `403`.

**Root cause evidence:**
- AI Box `/v1/models` listed authorized models: `deepseek-v4-pro[1m]`, `deepseek-v4-flash[1m]`, `kimi-k2.6`.
- Direct AI Box `/v1/messages` probe returned `200` for `deepseek-v4-pro[1m]` and `403` for `deepseek-v4-pro`.
- Claude Code 2.1.181 stripped `[1m]` from explicit `--model deepseek-v4-pro[1m]` and `deepseek-v4-flash[1m]`, causing the same `403`.
- Claude Code `--bare -p --model kimi-k2.6` returned `pong`.

**Changes implemented:**
- Backed up and updated local user config files outside repo:
  - `~/.zshrc`
  - `~/.claude/settings.json`
  - VS Code/Cursor User `settings.json` where present
- Removed generic `ANTHROPIC_BASE_URL` / `ANTHROPIC_AUTH_TOKEN` shell routing for this Foundry setup.
- Set Claude Code default primary/subagent model to `kimi-k2.6`.

**Verification:**
- New interactive `zsh` env showed Foundry vars set and generic Anthropic gateway vars unset.
- VS Code `claudeCode.environmentVariables` contained AI Box Foundry vars and `kimi-k2.6` defaults.
- `zsh -ic 'claude --bare -p --no-session-persistence "Reply with exactly: pong"'` returned `pong`.

**Risk / next concrete step:**
- DeepSeek models still require AI Box to provide a Claude-Code-compatible alias/base-model without bracket stripping, or Claude Code/AI Box gateway support for preserving `[1m]`.
- Reload VS Code / Claude Code extension to pick up updated user settings.

## 2026-06-26 00:00:00 ICT — Upgraded lineage portal automation and dark lane UI

**Scope lock:**
- Repo/GitHub Pages lineage portal automation and UI.
- No local Fabric/SQL/Power BI mutation.
- Live scan to be executed through GitHub Actions only.

**User instruction:**
- Fix the tool so future `02_marts/<mart>` additions auto-map/auto-render; run full automation, not a one-off preview.

**Changes implemented:**
- Added `scanner/mart_catalog.py`:
  - discovers marts from `02_marts/*/05_catalog`;
  - reads `assets.json` and `run_order.json`;
  - classifies business mart vs shared/support objects;
  - maps future marts without frontend hard-coding.
- Snapshot builder now emits:
  - `mart_registry` with business marts only;
  - `role` (`business`, `support`, `semantic`, `unclassified`);
  - `lane_order` and `lane_label` for deterministic lineage lanes.
- `_Wrk.v_<Table>` nodes inherit mart/wave from final tables via `DW_Developer.TableDictionary`.
- Wave inference preserves catalog/run-order waves such as `gold_shared`, `gold_dim`, `gold_helper`, `gold_fact`.
- Frontend now:
  - uses `mart_registry`, so dropdown excludes `shared` and `unresolved`;
  - shows dark lineage canvas;
  - lays nodes by deterministic lanes instead of ELK;
  - keeps upstream/downstream closure when filtering one mart.

**Verification:**
- Python unit tests passed (`9` tests).
- Fixture snapshot generation passed.
- Fixture snapshot `mart_registry` contained `forecast_accuracy,inventory_health` only.
- Frontend `npm run typecheck && npm run build` passed.
- `npm audit --omit=dev` returned `found 0 vulnerabilities`.
- `git diff --check` passed.

**Next concrete step:**
- Commit/push changes, run `Build Lineage Portal` with `scan_mode=live`, inspect generated live snapshot and production Pages UI.

## 2026-06-26 00:00:00 ICT — Re-scoped lineage portal to mart catalog graphs

**Scope lock:**
- Lineage portal scanner/UI only.
- Live deployment through GitHub Actions.

**User correction:**
- Lineage should match `02_marts` mart contracts, not scan/render the whole workspace inventory.
- Flow should be mart-scoped, modern, wider, and use soft curved lineage edges.

**Changes implemented:**
- `scanner/mart_catalog.py` now loads `assets.json`, `lineage_edges.json`, and `run_order.json` from every `02_marts/*/05_catalog`.
- `scanner/builder.py` now builds graph nodes/edges from mart catalog first and only enriches from live Fabric/SQL metadata.
- Full workspace `sys.objects` remains scan evidence only; it is no longer rendered wholesale as lineage.
- UI graph uses wider spacing, larger nodes, bezier edges, modern dark/glass styling, and floating detail panel.

**Verification:**
- Python tests passed (`9` tests).
- Fixture snapshot now emits mart-scoped graph: `138` nodes / `197` edges from current `02_marts` catalogs.
- Frontend `npm run typecheck && npm run build` passed.
- `npm audit --omit=dev` returned `found 0 vulnerabilities`.
- `git diff --check` passed.

**Next concrete step:**
- Push and redeploy live through `Build Lineage Portal` with `scan_mode=live`, then screenshot production.

## 2026-06-26 00:00:00 ICT — Collapsed `_Wrk` views out of lineage graph

**Scope lock:**
- Lineage portal scanner/UI only.
- Live deployment through GitHub Actions.

**User correction:**
- Business lineage should show table/entity -> table/entity flow.
- `_Wrk` views are implementation detail and made the graph too dense, laggy, and hard to read.

**Changes implemented:**
- Added scanner simplification step:
  - hides nodes where schema ends `_Wrk`, object starts `v_`, or catalog object_type is `wrk_view`;
  - collapses paths through hidden view nodes into direct `transforms_to` edges between visible tables/entities.
- Added regression test ensuring catalog snapshots do not emit work view nodes.
- UI edges remain curved `bezier`; graph styling kept modern dark/glass.

**Verification:**
- Python tests passed (`10` tests).
- Fixture mart-scoped snapshot now emits `88` nodes / `124` edges / `0` view nodes.
- Frontend `npm run typecheck && npm run build` passed.
- `npm audit --omit=dev` returned `found 0 vulnerabilities`.
- `git diff --check` passed.

**Next concrete step:**
- Commit/push and redeploy live; verify production snapshot has no `_Wrk/v_*` nodes.

## 2026-06-26 00:00:00 ICT — Fixed blank lineage graph after preview deploy

**Scope lock:**
- GitHub Pages UI fix only.
- Fixture preview snapshot; no live Fabric/SQL/Power BI mutation.
- No credentials persisted.

**User symptom:**
- Pages deployed successfully, but the UI showed no lineage graph.

**Root cause evidence:**
- Production screenshot showed summary cards loaded `13` nodes and `16` edges, but graph canvas was blank.
- Project-path `lineage_snapshot.json` returned `HTTP 200`; root-path snapshot returned `404`.
- Direct ELK reproduction failed with:
  - `UnsupportedConfigurationException`
  - `layer constraint set to FIRST_SEPARATE, but has at least one incoming edge`
- The graph layout code incorrectly passed numeric layer ranks as `elk.layered.layering.layerConstraint`, which ELK interpreted as special constraints.

**Fix:**
- Removed invalid per-node ELK layer constraint in `site/src/graph/layout.ts`.
- Added deterministic Bronze/Silver/Gold/Semantic fallback layout if ELK rejects a graph.
- Added React Flow provider-driven `fitView` after async layout and raised `minZoom` so deployed lineage is visible/readable instead of tiny at the bottom of the canvas.

**Verification:**
- Direct ELK fixture layout returned `ok 13 nodes positioned`.
- Frontend `npm run typecheck && npm run build` passed.
- `git diff --check` passed.

**Next concrete step:**
- Push the UI fix and rerun `Build Lineage Portal` with `scan_mode=fixture`, then screenshot production again.

## 2026-06-26 00:00:00 ICT — Deployed lineage portal preview to GitHub Pages

**Scope lock:**
- GitHub Pages preview deployment only.
- Used fixture snapshot, not live Fabric scan.
- No live Fabric/SQL/Power BI mutation.
- No credentials persisted.

**User instruction:**
- Continue next step and show the deployed UI.

**Actions executed:**
- Pushed lineage portal commits to `origin/main`.
- Enabled GitHub Pages with `build_type=workflow`.
- Triggered `Build Lineage Portal` workflow manually with `scan_mode=fixture`.
- Workflow run `28214683199` completed successfully.
- Opened the deployed Pages URL in the local default browser.

**Evidence:**
- Pages URL:
  - `https://ankinguyen-engineer-2002.github.io/data-architecture-microsoft-medallion-vietnam-data-hub/`
- `curl -I` returned `HTTP/2 200`.
- `lineage_snapshot.json` loaded from Pages and returned fixture lineage JSON.
- Pages API reports:
  - `build_type=workflow`
  - `https_enforced=true`
  - `public=true`

**Risk / next concrete step:**
- Repo/Pages are public. Do not run `scan_mode=live` until Aric confirms live metadata/SQL definitions are safe to publish and rotated/current secrets are set.

## 2026-06-26 00:00:00 ICT — Prepared GitHub Pages preview deployment mode

**Scope lock:**
- Repo/GitHub deployment preparation only.
- No live Fabric/SQL/Power BI mutation.
- No credentials persisted.

**User instruction:**
- Continue next step and deploy/show the lineage portal UI.

**Actions executed:**
- Checked GitHub auth, remote, repo visibility, existing secrets, and Pages state.
- Repo is public; GitHub Pages was not enabled yet (`GET /pages` returned `404`).
- Existing repo secrets use older names: `AZURE_TENANT_ID`, `AZURE_CLIENT_ID`, `AZURE_CLIENT_SECRET`, `FABRIC_SERVER`.
- Updated `.github/workflows/lineage-portal.yml`:
  - manual `scan_mode=fixture` for safe UI preview without live credentials;
  - manual/scheduled `scan_mode=live` for Fabric scan;
  - fallback support for older secret names.
- Updated `05_tools/06_lineage_portal/README.md` with preview/live secret behavior.

**Verification:**
- `git diff --check` passed.
- Python unit tests passed (`7` tests).
- Fixture snapshot generation passed.
- Frontend `npm run typecheck && npm run build` passed.

**Next concrete step:**
- Commit/push workflow changes, enable GitHub Pages with Actions build type, trigger fixture deployment, then trigger live deployment only after confirming public metadata exposure and rotated/current secrets.

## 2026-06-26 00:00:00 ICT — Implemented GitHub Actions + GitHub Pages lineage portal MVP

**Scope lock:**
- Repo implementation only.
- No live Fabric/SQL/Power BI mutation.
- No live GitHub Pages deployment executed from local session.
- No credentials persisted.

**User instruction:**
- Implement approved Option A: scanner runs in GitHub Actions; UI/UX hosted on GitHub Pages; no Streamlit and no local-host operating model.

**Files added/updated:**
- Added implementation plan:
  - `01_docs/plans/2026-06-26-github-pages-lineage-portal-implementation.md`
- Added scanner + tests + fixture:
  - `05_tools/06_lineage_portal/scanner/`
  - `05_tools/06_lineage_portal/tests/`
  - `05_tools/06_lineage_portal/tests/fixtures/minimal_live_input.json`
- Added static site:
  - `05_tools/06_lineage_portal/site/`
  - Vite/React/TypeScript + React Flow + ELK layout.
  - fixture-generated `site/public/lineage_snapshot.json`.
- Added workflow:
  - `.github/workflows/lineage-portal.yml`
- Updated docs:
  - `05_tools/README.md`
  - `05_tools/06_lineage_portal/README.md`

**Implemented behavior:**
- Scanner supports:
  - live mode via Service Principal env vars / GitHub secrets;
  - fixture mode for tests and static sample build;
  - deterministic fixture timestamp for repeatable sample snapshot generation;
  - Fabric REST item inventory;
  - Fabric SQL endpoint reads via `pyodbc` token;
  - `DW_Developer.TableDictionary`;
  - Processing/Gold objects and `_Wrk` view SQL modules;
  - `sc_control_tower` semantic TMDL source extraction;
  - deterministic layer/mart classification and wave inference.
- GitHub Pages UI supports:
  - Bronze/Silver/Gold/Semantic lineage map;
  - ELK layered graph layout;
  - mart/layer/search/unresolved filters;
  - node detail drawer with SQL/evidence/upstream/downstream;
  - snapshot JSON download.
- GitHub Actions workflow supports:
  - manual/scheduled runs;
  - ODBC driver setup;
  - scanner snapshot generation;
  - snapshot secret grep;
  - frontend typecheck/build;
  - Pages artifact deploy.

**Verification:**
- Python unit tests passed:
  - `PYTHONPATH=05_tools/06_lineage_portal python3 -m unittest discover -s 05_tools/06_lineage_portal/tests -v`
  - `7` tests passed.
- Fixture snapshot generation passed:
  - `cd 05_tools/06_lineage_portal && PYTHONPATH=. python3 -m scanner.cli --fixture tests/fixtures/minimal_live_input.json --out site/public/lineage_snapshot.json`
- Frontend checks passed:
  - `npm run typecheck`
  - `npm run build`
  - `npm audit --omit=dev` returned `found 0 vulnerabilities`.
- Secret grep for the pasted Fabric SP secret and Azure OpenAI key returned no repo hits.

**Current handoff / required setup:**
- Before running the workflow live:
  - rotate the pasted Service Principal secret and Azure OpenAI key;
  - configure GitHub Pages source as GitHub Actions;
  - add repo secrets listed in `05_tools/06_lineage_portal/README.md`;
  - consider whether repo/Pages visibility can expose live SQL definitions and lineage metadata.
- First live workflow run may reveal whether the Service Principal needs additional metadata visibility for wrapper stored procedures.

## 2026-06-26 00:00:00 ICT — Chose GitHub Actions + GitHub Pages lineage portal architecture

**Scope lock:**
- Planning/design only.
- No live Fabric/SQL/Power BI mutation.
- No GitHub Pages deployment yet.
- No credential persisted to repo.

**User instruction:**
- Build a beautiful, professional lineage tool for GitHub Pages, not Streamlit and not localhost.
- Scanner must read current live Fabric/Enterprise ETL infrastructure rather than stale repo-local `02_marts`.
- UI should classify and render Bronze -> Silver waves -> Gold waves -> single semantic model `sc_control_tower`.
- Optional Azure OpenAI/API providers may help classification/enrichment later, but credentials must be switchable and protected.

**Decision:**
- Option A approved:
  - GitHub Actions runs the live scanner.
  - GitHub Pages hosts the static UI/UX.
  - Browser reads only sanitized JSON snapshot artifacts.
  - Browser never receives Fabric SQL/Fabric REST/Power BI/OpenAI credentials.

**Design artifact added:**
- `01_docs/plans/2026-06-26-github-pages-lineage-portal-design.md`

**Key design constraints captured:**
- Primary live scan sources:
  - Fabric REST workspace item inventory.
  - `ETL_Framework.DW_Developer.TableDictionary`.
  - Processing/Gold final tables and `_Wrk` views.
  - `Enterprise_Lakehouse` table inventory.
  - `sc_control_tower` semantic model definition.
- Legacy `Meta.AssetRegistry` / `Meta.LineageEdge` are explicitly non-goals for current runtime lineage.
- Azure OpenAI is optional enrichment only, not authoritative lineage classification.
- The Azure OpenAI key shared in chat must be rotated and stored only as GitHub Actions secret before implementation.

**Next concrete step:**
- Review/approve the design spec, then create implementation plan for `05_tools/06_lineage_portal/` and `.github/workflows/lineage-portal.yml`.

## 2026-06-26 00:00:00 ICT — Tested Fabric Pipeline Alert Service Principal read access

**Scope lock:**
- Read-only Service Principal connectivity probe.
- No Fabric/SQL/Power BI mutation.
- No secret persisted to repo.

**User instruction:**
- Use the app registration/secret for `Fabric Pipeline Alert` to see whether it can read the current `Enterprise SupplyChain-Dev` infrastructure.
- User corrected scope: current runtime is Enterprise ETL / `DW_Developer.TableDictionary` + `_Wrk` views, not legacy `Meta.*`.

**Actions executed:**
- Ran a temporary read-only probe from `/private/tmp/fabric_sp_probe.py`.
- Requested Service Principal tokens for:
  - `https://database.windows.net/.default`
  - `https://api.fabric.microsoft.com/.default`
- Queried Fabric REST workspace items for `Enterprise SupplyChain-Dev`.
- Queried SQL endpoint read-only for:
  - `ETL_Framework`
  - `SupplyChain_Processing_Warehouse`
  - `SupplyChain_Gold_Warehouse`
  - `Enterprise_Lakehouse`

**Evidence:**
- Token acquisition succeeded for both database and Fabric REST.
- Fabric REST workspace item listing succeeded:
  - `151` items visible.
  - Counts include `6` Warehouses, `4` Lakehouses, `4` SQL endpoints, `6` semantic models, `17` data pipelines, `83` notebooks.
- SQL endpoint read access succeeded:
  - `ETL_Framework`: `9` tables, `1` view, `0` visible procs.
  - `SupplyChain_Processing_Warehouse`: `58` tables, `43` views, `0` visible procs.
  - `SupplyChain_Gold_Warehouse`: `15` tables, `13` views, `0` visible procs.
  - `Enterprise_Lakehouse`: `419` tables.
- `ETL_Framework.DW_Developer.TableDictionary` read succeeded:
  - `66` rows total.
  - `50` rows with `_Wrk.v_*` references.
- `_Wrk` view discovery succeeded in Processing and Gold.
- `DW_Developer.AuditLog` table is visible, but the quick probe used a stale column assumption (`ProcedureName`) and hit `Invalid column name 'ProcedureName'`.

**Risk / interpretation:**
- The Service Principal can read current workspace inventory and core warehouse/table/view metadata.
- `sys.procedures` returned `0` visible procedures for Processing/Gold under this Service Principal; do not conclude wrapper procs are absent without checking with owner/user identity or explicit proc visibility grants.
- The provided client secret appeared in interactive tool output during an earlier TTY attempt; rotate the secret in Azure Portal before treating it as clean.

**Next concrete step:**
- If this app will power a current Enterprise ETL lineage/status reader, grant/verify least-privilege read visibility for wrapper proc definitions if needed, and update the reader to use `DW_Developer.TableDictionary`, `_Wrk` views, and workspace items instead of legacy `Meta.*`.

## 2026-06-24 08:35:35 (ICT) — Removed repo-native Lineage Workbench visual experiment

**Scope lock:**
- Repo cleanup only; no live Fabric/Power BI/SQL mutation.

**User instruction:**
- Delete the repo-native Lineage Workbench visual experiment because the generated graph/UI was too visually cluttered and not useful enough.

**Actions executed:**
- Uninstalled local VS Code extension:
  - `aric-nguyen-local.supplychain-lineage-workbench`
- Deleted active experiment artifacts:
  - `05_tools/lineage_workbench/`
  - `02_marts/forecast_accuracy/05_lineage/`
  - `02_marts/inventory_health/05_lineage/`
  - `.vscode/tasks.json`
  - `01_docs/plans/2026-06-23-lineage-workbench-compiler.md`
  - `01_docs/decisions/ADR-010-lineage-workbench.md`
- Kept mart DQ evidence:
  - `02_marts/*/04_dq/`
  - `05_tools/audit_bronze_source_dq.py`
  - `05_tools/audit_all_bronze_source_dq_final.py`
- Updated active docs to remove Lineage Workbench references:
  - `README.md`
  - `02_marts/README.md`
  - `03_operations/README.md`
  - `05_tools/README.md`
  - `02_marts/*/04_dq/README.md`

**Verification:**
- Active grep across `README.md`, `AGENTS.md`, `01_docs`, `02_marts`, `03_operations`, `04_semantic`, `05_tools`, `.vscode` found no references to:
  - `lineage_workbench`
  - `SupplyChain Lineage`
  - `05_lineage`
  - `ADR-010`
  - `global_catalog`
  - `aric-nguyen-local.supplychain-lineage-workbench`
- Active mart folder surface is back to:
  - `00_source_wrk/`
  - `01_bronze/`
  - `02_silver/`
  - `03_gold/`
  - `04_dq/`
  - `99_history/`

**Next step:**
- If lineage is revisited later, use a simpler non-visual source-of-truth approach first, likely manifest/table-level dependency metadata, before attempting another graph UI.
## 2026-06-24 08:46:57 (ICT) — Cleaned `05_tools` into functional hubs

**Scope lock:**
- Repo cleanup only; no live Fabric/Power BI/SQL mutation.

**User instruction:**
- Clean up `05_tools` because the flat script list looked cluttered.

**Actions executed:**
- Reorganized root `05_tools` from flat scripts into numbered functional hubs:
  - `05_tools/01_dq/`
  - `05_tools/02_repo_maintenance/`
  - `05_tools/03_mart_sync/`
- Moved scripts:
  - `audit_bronze_source_dq.py` -> `05_tools/01_dq/`
  - `audit_all_bronze_source_dq_final.py` -> `05_tools/01_dq/`
  - `restructure_mart_layer_sql.py` -> `05_tools/02_repo_maintenance/`
  - `split_context.py` -> `05_tools/02_repo_maintenance/`
  - `sync_live_mart_layers.py` -> `05_tools/03_mart_sync/`
- Added README files for each tool hub and updated DQ README command references.
- Patched script root-path resolution after the move.
- Added `--help`/`--out-dir` CLI handling to `audit_all_bronze_source_dq_final.py` so help no longer starts a live read-only audit accidentally.

**Verification:**
- `python3 -m py_compile` passed for all five moved scripts.
- `python3 05_tools/01_dq/audit_bronze_source_dq.py --help` passed.
- `python3 05_tools/01_dq/audit_all_bronze_source_dq_final.py --help` passed and did not run live audit.
- `05_tools` root now contains only:
  - `README.md`
  - `01_dq/`
  - `02_repo_maintenance/`
  - `03_mart_sync/`
## 2026-06-24 09:07:07 (ICT) — Built DQ and catalog operating packages

**Scope lock:**
- Repo-only operating metadata; no live Fabric/Power BI/SQL mutation.
- Phase 2 remains deferred.

**User instruction:**
- Improve the repo-as-docs-and-operations system by packaging Bronze DQ and lineage/catalog properly after the visual Lineage Workbench experiment was rejected.

**Actions executed:**
- Added repeatable generator:
  - `05_tools/04_operating_package/build_operating_package.py`
  - `05_tools/04_operating_package/README.md`
- Generated Bronze DQ operating packs for both active marts:
  - `02_marts/<mart>/04_dq/contracts/bronze_sources.json`
  - `02_marts/<mart>/04_dq/contracts/rules.json`
  - `02_marts/<mart>/04_dq/contracts/exceptions.json`
  - `02_marts/<mart>/04_dq/runs/latest.json`
- Generated mart catalog/lineage registries:
  - `02_marts/<mart>/05_catalog/assets.json`
  - `02_marts/<mart>/05_catalog/lineage_edges.json`
  - `02_marts/<mart>/05_catalog/run_order.json`
  - `02_marts/<mart>/05_catalog/semantic_bindings.json`
- Generated all-mart operating rollup:
  - `03_operations/operating_registry/summary.json`
  - `03_operations/operating_registry/assets.json`
  - `03_operations/operating_registry/lineage_edges.json`
  - `03_operations/operating_registry/dq_summary.json`
  - `03_operations/operating_registry/run_order.json`
- Updated active docs:
  - `README.md`
  - `02_marts/README.md`
  - `02_marts/forecast_accuracy/README.md`
  - `02_marts/inventory_health/README.md`
  - `02_marts/*/04_dq/README.md`
  - `03_operations/README.md`
  - `05_tools/README.md`

**Generated package summary:**
- Marts packaged: `2`
- Bronze DQ sources packaged: `42`
- Repo catalog assets: `161`
- Catalog/lineage edges: `183`
- Forecast Accuracy:
  - DQ sources: `17`
  - DQ pass: `14`
  - DQ review: `3`
  - catalog assets: `73`
  - lineage edges: `74`
  - run-order steps: `13`
- Inventory Health:
  - DQ sources: `25`
  - DQ pass: `16`
  - DQ review: `9`
  - catalog assets: `88`
  - lineage edges: `109`
  - run-order steps: `18`

**Notable DQ exceptions now machine-readable:**
- Forecast Accuracy: `SalesHistory_AFI_Enh.InvoiceDetail`, `Wholesale_Codis_AFI.codatan`, `Wholesale_Codis_AFI.EXTORD`.
- Inventory Health: `Inventory_Enh_History.ItemBalance`, `ItemMaster_AFI.ITBEXT`, `ItemMaster_AFI.ITMRVA`, `Manufacturing_Inventory_AFI.TFRDTL`, `SalesHistory_AFI_Enh.InvoiceDetail`, `SupplyChain_Enh.DemandForecastSnapshotDaily`, `SupplyChain_Enh.DemandFulfillmentCommonContainer_Logility`, `SupplyChain_Enh.DemandInventorySnapshotDaily`, `SupplyChain_Enh.PurchaseOrderSnapshot`.

**Verification:**
- `python3 -m py_compile 05_tools/04_operating_package/build_operating_package.py` passed.
- `python3 05_tools/04_operating_package/build_operating_package.py --repo-root .` passed.
- JSON validation passed for generated DQ contracts/runs, mart catalogs, and all-mart operating registry.
- Active grep found no stale `lineage_workbench`, `SupplyChain Lineage`, `05_lineage`, or old flat `05_tools/*.py` command paths.

**Next step:**
- Use `03_operations/operating_registry/summary.json` and `02_marts/*/04_dq/contracts/exceptions.json` as the default machine-readable audit handoff before any new mart onboarding or ad-hoc refresh work.
## 2026-06-24 09:57:36 ICT — Researched US/Enterprise ETL stored-procedure orchestration pattern

**Scope lock:**
- Read-only live Fabric/SQL scan plus repo/context review.
- No live SQL DDL/DML, Fabric mutation, or repo architecture change beyond this context note.

**User question:**
- How does US/Enterprise ETL orchestration likely run when SQL Server Agent is the scheduler?
- Does the flow use final-schema stored procedures that call ETL framework operations against `_Wrk.v_<TableName>` views in ordered groups/waves?

**Evidence checked:**
- Re-read `AGENTS.md` and `00_CONTEXT/current.md`.
- Queried live workspace/warehouse metadata and stored procedure definitions via `az` token + `pyodbc`.
- Cross-checked Microsoft Learn SQL Server Agent docs: T-SQL job steps can call stored procedures; SQL Agent jobs/steps/schedules are managed in `msdb`.
- Scanned:
  - `Enterprise SupplyChain-Dev.SupplyChain_Warehouse`
  - `Enterprise SupplyChain-Dev.ETL_Framework`
  - `EnterpriseData-Dev.SupplyChain_Warehouse`
  - `EnterpriseData-Dev.Retail_Warehouse`
  - `EnterpriseData-Dev.Wholesale_Warehouse`
  - `EnterpriseData-Dev.MasterData_Warehouse`
  - `EnterpriseData-Dev.Quality_Warehouse`
  - corresponding `EnterpriseData` prod warehouses where visible.

**Key findings:**
- [Verified] `ETL_Framework.DW_Developer.usp_RefreshCuratedTableFromView` derives:
  - work table: `<DestinationDatabase>.<DestinationSchema>.<DestinationTable>_LOAD`
  - source view: `<DestinationDatabase>.<DestinationSchema>_Wrk.v_<DestinationTable>`
  - final table: `<DestinationDatabase>.<DestinationSchema>.<DestinationTable>`
- [Verified] `Enterprise SupplyChain-Dev.SupplyChain_Warehouse` legacy `SCP_Core` pattern has physical final tables in `SCP_Core`, matching source views in `SCP_Core_Wrk`, and wrapper procs in `SCP_Core`:
  - `usp_Update_Dimensions`
  - `usp_Update_AFISalesFacts`
  - `usp_Update_FcstAccuracy`
  - `usp_Update_LogilityData`
- [Verified] `SCP_Core.usp_Update_Dimensions` calls `ETL_Framework.DW_Developer.usp_RefreshCuratedTableFromView` for multiple dimension tables in explicit top-down order.
- [Verified] `SCP_Core.usp_Update_FcstAccuracy` calls `ETL_Framework.DW_Developer.usp_IncrementalTableLoad 'SupplyChain_Warehouse','SCP_Core','FactFcstErrorCalc','Append'`.
- [Verified] `EnterpriseData-Dev.Retail_Warehouse.dbo.Usp_Refresh_Retail_Warehouse` and `EnterpriseData-Dev.Wholesale_Warehouse.dbo.Usp_Refresh_Wholesale_Warehouse` are broad wrapper procedures that call many `ETL_Framework.DW_Developer` load procedures in explicit sequence.
- [Verified] Current new Phase 1 warehouses do not yet have equivalent mart/domain wrapper procs:
  - `SupplyChain_Processing_Warehouse`: procs only in `Meta` plus old `Staging_Wrk`; no active domain `usp_Update_*` wrapper found.
  - `SupplyChain_Gold_Warehouse`: no stored procedures found.
  - `ETL_Framework`: generic Enterprise ETL loader procs exist.

**Interpretation:**
- US/Enterprise ETL runtime pattern is not strictly "one stored procedure per table".
- It is usually a layered pattern:
  1. final schema physical table;
  2. `_Wrk.v_<TableName>` source/work view;
  3. domain/table-group wrapper stored procedure defining ordered refresh sequence;
  4. generic ETL framework stored procedure executing the load pattern and audit/metadata logging.
- The wrapper procedure order is effectively the procedural wave/order surface when no separate DAG metadata is visible.

**Next concrete step if Aric wants stricter US parity:**
- Generate non-destructive draft SQL wrappers from `03_operations/orchestration/*/manifest.yaml`.
- Proposed target shape:
  - `SupplyChain_Processing_Warehouse.<DomainSchema>.usp_Update_<DomainOrMart>`
  - `SupplyChain_Gold_Warehouse.<DomainSchema>.usp_Update_<DomainOrMart>`
  - optional top-level `dbo.Usp_Refresh_<Mart>` wrapper calling domain wrappers.
- Do not apply live `CREATE/ALTER PROCEDURE` until Aric explicitly approves exact generated DDL.
## 2026-06-24 10:18:29 ICT — Verified Enterprise ETL wrapper flow against EnterpriseData and SCP_Core

**Scope lock:**
- Read-only Fabric Warehouse metadata/procedure scan.
- No live SQL DDL/DML or Fabric mutation.

**User instruction:**
- Scan `EnterpriseData` and `Enterprise SupplyChain-Dev.SupplyChain_Warehouse` to confirm whether the inferred flow is actually the standard Enterprise ETL/US pattern.

**Live evidence:**
- `Enterprise SupplyChain-Dev.SupplyChain_Warehouse`:
  - totals: `28` tables, `25` views, `13` procs.
  - `SCP_Core`: `13` physical tables, `0` views, `4` procs.
  - `SCP_Core_Wrk`: `12` views.
  - `SCP_Core` wrapper procs found:
    - `usp_Update_Dimensions`
    - `usp_Update_AFISalesFacts`
    - `usp_Update_FcstAccuracy`
    - `usp_Update_LogilityData`
  - framework call counts in wrappers: `usp_RefreshCuratedTableFromView=9`, `usp_IncrementalTableLoad=1`.
  - examples:
    - `SCP_Core.usp_Update_Dimensions` calls `ETL_Framework.DW_Developer.usp_RefreshCuratedTableFromView` for dimensions in explicit order.
    - `SCP_Core.usp_Update_FcstAccuracy` calls `ETL_Framework.DW_Developer.usp_IncrementalTableLoad 'SupplyChain_Warehouse','SCP_Core','FactFcstErrorCalc','Append'`.
- `EnterpriseData-Dev.Retail_Warehouse`:
  - totals: `220` tables, `42` views, `145` procs.
  - framework calls found: `usp_RefreshCuratedTableFromView=44`, `usp_UpdateTableDictionary_ModifiedDate=94`.
  - examples:
    - `dbo.Usp_Refresh_MasterData_Ent` calls framework loader for `MasterData_Ent` tables.
    - `dbo.Usp_Refresh_MasterData_Product` calls framework loader for `ProductGroup`, `ProductSeries`, `ProductInfo`.
    - `dbo.Usp_Refresh_Retail_Sales` calls framework loader for multiple `Retail_Sales` tables in explicit order.
    - `dbo.Usp_Refresh_Retail_Enh` calls schema-local `Retail_Sales_Enh.usp_Update_*` procs, which then perform custom logic and update TableDictionary.
- `EnterpriseData-Dev.Wholesale_Warehouse`:
  - totals: `209` tables, `126` views, `8` procs.
  - framework calls found: `usp_RefreshCuratedTableFromView=160`, `usp_UpdateTableDictionary_ModifiedDate=2`.
  - examples:
    - `dbo.Usp_Refresh_Wholesale_Warehouse` has `117` ordered EXEC lines calling `ETL_Framework.DW_Developer.usp_RefreshCuratedTableFromView`.
    - `dbo.Usp_RefreshCustomers`, `dbo.usp_RefreshCustomerOrders_AFI`, and `dbo.usp_RefreshSalesHistory_AFI` call framework loaders by schema/table in explicit order.
- `EnterpriseData-Dev.SupplyChain_Warehouse`:
  - smaller/current dev surface: `1` table, `12` views, `1` proc.
  - `SupplyChain_Enh.usp_Refresh_ContainerPerDiem` updates TableDictionary but does not represent the broader SCP_Core wrapper pattern.
- `EnterpriseData-Dev.ETL_Framework`:
  - `TableDictionary` rows: `832`.
  - framework procs include `usp_RefreshCuratedTableFromView`, `usp_IncrementalTableLoad`, `usp_IncrementalTableLoad_CDC`, `usp_SCD2_TableLoad`, `usp_UpdateCuratedTableFromView_DateRange`, alert/audit/table-dictionary utilities.
- `EnterpriseData` prod visibility check:
  - `ETL_Framework`: `21` tables, `2` views, `0` visible procs, `TableDictionary=1079`.
  - `Retail_Warehouse`: `224` tables, `26` views, `0` visible procs.
  - `Wholesale_Warehouse`: `143` tables, `124` views, `0` visible procs.
  - `SupplyChain_Warehouse`: `20` tables, `3` views, `0` visible procs.
  - Treat prod proc absence as visibility/environment evidence only; do not use it to disprove the dev/US wrapper pattern.

**Confirmed interpretation:**
- [Verified] The Enterprise ETL/US curated pattern is:
  1. final schema physical tables;
  2. `_Wrk.v_<TableName>` views for source/business SQL;
  3. wrapper stored procedures as ordered orchestration entrypoints;
  4. `ETL_Framework.DW_Developer` generic loaders for load pattern, audit, and TableDictionary updates.
- [Verified] Some EnterpriseData domains mix this with schema-local `usp_Update_*` custom procs. The broad standard is wrapper proc order plus framework calls, not necessarily one procedure per table.
- [Verified] The new Phase 1 warehouses are aligned on final table + `_Wrk` view + framework metadata, but still lack US-style wrapper procedure entrypoints.
## 2026-06-24 10:26:07 ICT — Clarified dependency/order control for future wrapper SPs

**Scope lock:**
- Repo/context review only; no live SQL/Fabric mutation.

**User question:**
- If SQL Agent / wrapper stored procedures are used for execution, how should dependency order be controlled, especially for Silver waves and Gold dependencies?

**Current repo state checked:**
- `03_operations/orchestration/main/manifest.yaml` has project-level order:
  - shared -> forecast_accuracy -> inventory_health -> smoke.
- Mart-level `manifest.yaml` files currently declare pipeline/project metadata and Enterprise ETL `_Wrk` contract, but do not carry the full table-level sequence.
- Generated operating packages currently hold table-level order:
  - `02_marts/forecast_accuracy/05_catalog/run_order.json`
  - `02_marts/inventory_health/05_catalog/run_order.json`
  - `03_operations/operating_registry/run_order.json`

**Interpretation:**
- Ordered `EXEC` lines inside wrapper SPs are valid as an execution artifact, but should not become the only source of truth.
- Safer target pattern:
  1. maintain mart run DAG/order in metadata (`manifest.yaml`/run registry);
  2. validate the DAG by SQL dependency scan and topological sorting;
  3. generate wrapper stored procedures from metadata;
  4. deploy wrapper SPs only after dry-run/review;
  5. SQL Agent calls only the stable top-level wrapper entrypoint.

**Design implication:**
- Do not require one SP per table as the primary model.
- Recommended hierarchy:
  - table-level load step in metadata;
  - generated schema/wave wrapper procs;
  - generated mart wrapper proc;
  - optional all-mart wrapper proc.
- This preserves Enterprise ETL compatibility while keeping dependency order machine-checkable.
## 2026-06-24 10:36:41 ICT — Forecast Accuracy wrapper-flow example researched

**Scope lock:**
- Read-only repo + live `ETL_Framework.TableDictionary` query.
- No live SQL DDL/DML or Fabric mutation.

**User question:**
- What would the Forecast Accuracy flow look like top-down if converted to Enterprise ETL/US wrapper stored procedures, and would each step call the framework loader and update `TableDictionary`/audit?

**Evidence checked:**
- `02_marts/forecast_accuracy/05_catalog/run_order.json` has `13` ordered steps:
  - shared `DimCalendar`, `DimProduct`, `DimWarehouse`
  - wave `0`: `ReferenceMaster_Enh.*`
  - wave `1`: `SalesHistory_Enh.InvoiceDetailLineLevel`, `OpenOrderHistory_Enh.OpenOrderLineLevel`
  - wave `2`: `SalesHistory_Enh.ActualDemandMonthly`, `ForecastHistory_Enh.ForecastDemandMonthly`
  - `gold_dim`: `ForecastAccuracy_DW.DimCustomerGrouping`, `ForecastAccuracy_DW.DimForecastHorizon`
  - `gold_fact`: `ForecastAccuracy_DW.FactForecastActual`, `ForecastAccuracy_DW.FactForecastKpi`
  - `smoke`: semantic/row-count/freshness checks
- Live `ETL_Framework.DW_Developer.TableDictionary` lookup:
  - forecast/shared/gold objects checked are present.
  - `UpdateMethod=overwrite` for the forecast objects checked.
  - `ReferenceMaster_Enh` has `11` table rows; all checked rows use `UpdateMethod=overwrite`.

**Interpretation:**
- Forecast wrapper procs can call `ETL_Framework.DW_Developer.usp_RefreshCuratedTableFromView` for the current overwrite objects.
- Framework will resolve `<Schema>_Wrk.v_<Table>` from schema/table, load `<Schema>.<Table>`, write `AuditLog`, and update table metadata/modified status through the framework proc path.
- Smoke/semantic validation remains outside the loader and should be a post-run validation step, not a curated-table load step.
## 2026-06-24 10:48:42 ICT — Checked whether `ETL_Framework.Orchestration` exists elsewhere

**Scope lock:**
- Read-only metadata scan of `ETL_Framework` warehouses.
- No live SQL DDL/DML or Fabric mutation.

**User concern:**
- Whether adding an `Orchestration` schema inside `ETL_Framework` is already a US/Enterprise ETL pattern, or would be an unsupported custom addition.

**Evidence checked:**
- `Enterprise SupplyChain-Dev.ETL_Framework`:
  - active object schemas: `DW_Developer`, `queryinsights`, `sys`.
  - procedures: `10`, all in `DW_Developer`.
  - no `Orchestration` schema found.
- `EnterpriseData-Dev.ETL_Framework`:
  - active object schemas include `DW_Developer`, `Performance_Logs`, some data schemas, `queryinsights`, `sys`.
  - procedures: `35`, mostly `DW_Developer`, one `Performance_Logs`.
  - no `Orchestration` schema found.
- `EnterpriseData.ETL_Framework` prod:
  - visible object schemas include `DW_Developer`, `Performance_Logs`, `ProductKnowledge`, `sys`.
  - visible procedures: `0`.
  - no `Orchestration` schema found.

**Decision implication:**
- Do not add `ETL_Framework.Orchestration` as the default Enterprise ETL-aligned design without explicit approval.
- Safer parity pattern is to keep `ETL_Framework.DW_Developer` as pure generic loader framework, and place wrapper/orchestration procedures in the target/domain warehouses (`dbo` and/or relevant business schema), matching `SCP_Core`, Retail, and Wholesale evidence.
## 2026-06-24 11:18:00 ICT — Enterprise ETL-style wrapper stored procedures applied for all active marts

**Scope lock:**
- Live Fabric SQL mutation already executed before context cleanup; no full curated refresh/proc execution was run in this checkpoint.
- Business Bronze/Silver/Gold object surface preserved; operational wrapper layer added around existing Enterprise ETL loader procedures.

**User instruction:**
- Apply the US/Enterprise ETL stored-procedure orchestration pattern to all active marts, not just Forecast Accuracy.
- Audit ETL framework log/metadata tables afterward for stale object names.

**Enterprise ETL/US pattern verified:**
- Wrapper procedures are schema-local/top-level operational entrypoints in target warehouses, commonly `dbo.Usp_Refresh_*` or schema-local `usp_Update_*`.
- No separate `ETL_Framework.Orchestration` schema was found in scanned EnterpriseData / SCP_Core patterns.
- Target standard for this repo: keep `ETL_Framework.DW_Developer` as pure loader framework; keep mart wrapper procedures in `dbo` of the relevant Processing/Gold warehouse.

**Live wrapper procedures applied:**
- `SupplyChain_Gold_Warehouse.dbo.Usp_Refresh_SupplyChain_Shared`
- `SupplyChain_Processing_Warehouse.dbo.Usp_Refresh_SupplyChain_ReferenceMaster`
- `SupplyChain_Processing_Warehouse.dbo.Usp_Refresh_ForecastAccuracy_Silver`
- `SupplyChain_Gold_Warehouse.dbo.Usp_Refresh_ForecastAccuracy_Gold`
- `SupplyChain_Processing_Warehouse.dbo.Usp_Refresh_InventoryHealth_Silver`
- `SupplyChain_Gold_Warehouse.dbo.Usp_Refresh_InventoryHealth_Gold`

**Wrapper flow contract:**
- SQL Agent / external scheduler should run cross-warehouse order explicitly:
  1. `EXEC SupplyChain_Gold_Warehouse.dbo.Usp_Refresh_SupplyChain_Shared;`
  2. `EXEC SupplyChain_Processing_Warehouse.dbo.Usp_Refresh_SupplyChain_ReferenceMaster;`
  3. `EXEC SupplyChain_Processing_Warehouse.dbo.Usp_Refresh_ForecastAccuracy_Silver;`
  4. `EXEC SupplyChain_Gold_Warehouse.dbo.Usp_Refresh_ForecastAccuracy_Gold;`
  5. `EXEC SupplyChain_Processing_Warehouse.dbo.Usp_Refresh_InventoryHealth_Silver;`
  6. `EXEC SupplyChain_Gold_Warehouse.dbo.Usp_Refresh_InventoryHealth_Gold;`
  7. run smoke/DQ/semantic checks.
- Inside each wrapper, table calls are sequential and follow current manifest/wave order.

**ETL framework metadata update:**
- Updated `ETL_Framework.DW_Developer.TableDictionary` for `41` wrapper-managed objects.
- `ReplicatedSource` now maps to canonical `_Wrk.v_<TableName>` for each final table.
- `UpdateQuery` maps to `[DW_Developer].[usp_RefreshCuratedTableFromView]` for overwrite objects and `[DW_Developer].[usp_IncrementalTableLoad]` for the two incremental Inventory snapshots.
- `JobName`/`JobServer` were not fabricated because the real US SQL Agent job/server names are not known yet.

**Audit evidence captured:**
- Processing table/view/top0 audit: `28` objects, `0` failures.
- Gold table/view/top0 audit: `13` objects, `0` failures.
- `TableDictionary` mismatch audit: `0` mismatches.
- Stale active-name audit for `PurchaseOrderSnapshotDaily`, `InventorySnapshotWeeklyFactBase`, `LastInvoiceHelper`, `MovementFlagHelper`, `CogsRollingHelper`, `FactInventoryRiskForward`: `0` rows in current `TableDictionary`, `0` recent rows in `AuditLog`, `0` recent rows in `TableDictionary_UpdateLog` since `2026-06-23`.

**Repo updates:**
- Added wrapper SQL files under `03_operations/orchestration/*/sql/`.
- Added `wrapper_procedures` metadata to `forecast_accuracy`, `inventory_health`, and `main` orchestration manifests.
- Updated Inventory Health manifest to current live object names: `PurchaseOrderSnapshotHistorical`, `LastInvoiceWeekly`, `Cogs52WWeekly`, `ProjectedInventoryHealthSubStatus`, `FactInventoryHealthFutureWeekEnding`, etc.
- Regenerated operating package: `mart_count=2`, `dq_source_count=42`, `forecast run_step_count=13`, `inventory run_step_count=24`.

**Verification:**
- `python3 05_tools/04_operating_package/build_operating_package.py --repo-root .` passed after manifest updates.
- Active generated package JSON parse passed except two pre-existing empty semantic artifact response files under `01_docs/runbook/artifacts/2026-06-15_sc_control_tower/`, unrelated to orchestration/DQ/catalog.
- Active grep found no stale Inventory object names in `03_operations/orchestration`, `03_operations/operating_registry`, `02_marts/*/05_catalog`, or `02_marts/*/04_dq`.

**Next step:**
- When ready to validate runtime behavior, execute wrapper procedures in the SQL Agent order above or dry-run/ad-hoc equivalent. Do not trigger a full curated refresh unless Aric explicitly asks.
## 2026-06-24 11:31:00 ICT — Normalized context chunks after wrapper work

**Scope lock:**
- Repo context cleanup only; no live Fabric/Power BI/SQL mutation.

**User instruction:**
- Stop further live work for now; log and organize context files in the right order because the handoff history looked messy.

**Actions executed:**
- Preserved pre-cleanup active context at `00_CONTEXT/_source/current_before_reorder_20260624.md`.
- Recovered missing `2026-06-23` entries from the old active `current.md` into `00_CONTEXT/2026-06-21_to_2026-06-23.md` under a clearly labeled recovered section.
- Created/updated `00_CONTEXT/2026-06-24_to_2026-06-24.md` as the clean day-specific active chunk.
- Rewrote `00_CONTEXT/current.md` to mirror only the `2026-06-24` chunk.
- Updated `00_CONTEXT/README.md` chunk index.

**Next step:**
- Resume from wrapper orchestration checkpoint; use wave order from `03_operations/orchestration/*/manifest.yaml` and wrapper procedures from `03_operations/orchestration/*/sql/`.

## 2026-06-24 12:14:32 ICT — Surfaced wrapper procedure order in runner + docs

**Scope lock:**
- Repo-only docs/tooling alignment; no live Fabric/Power BI/SQL mutation.

**User instruction:**
- Read `AGENTS.md` + scan repo + resume from latest `00_CONTEXT` checkpoint.

**Actions executed:**
- Updated `03_operations/tools/run_refresh.py` to print `wrapper_procedures` (database context + `EXEC [schema].[procedure]`).
- Added `wrapper_procedures` to `03_operations/orchestration/main/manifest.yaml` and `03_operations/orchestration/main/manifest.json` so the full SQL Agent order is machine-readable.
- Updated docs:
  - `03_operations/README.md`
  - `03_operations/orchestration/*/README.md`

**Verification:**
- `python3 -m py_compile 03_operations/tools/run_refresh.py` passed.
- Dry-run prints show wrapper procedure order for:
  - `03_operations/orchestration/main/manifest.json`
  - `03_operations/orchestration/forecast_accuracy/manifest.json`
  - `03_operations/orchestration/inventory_health/manifest.json`

**Repo state note:**
- Local `main` is behind `origin/main` by `1` commit (`1e82342c`), and `git status` is still large due to the ongoing repo restructure checkpoint.

**Next step:**
- If we want a runtime validation checkpoint, decide whether to:
  1) execute wrapper procedures (live), or
  2) smoke-test the parameterized `pl_sc_mart(project_name)` REST trigger first.
- Live execution requires explicit approval.

## 2026-06-24 12:58:41 ICT — Re-aligned orchestration manifests to wave-first (Silver -> Gold)

**Scope lock:**
- Repo-only manifest/docs/package alignment; no live Fabric/Power BI/SQL mutation.

**User instruction:**
- “Lấy đúng thứ tự wave: Silver wave 0,1,2… rồi mới tới Gold; scan lại cái nào trước/sau và apply setup.”

**Actions executed:**
- Updated mart orchestration manifests to be wave-first:
  - `03_operations/orchestration/forecast_accuracy/manifest.json`
  - `03_operations/orchestration/inventory_health/manifest.json`
  - moved shared dims into `wave=gold_shared` and placed after Silver waves.
- Added missing Silver prerequisite into Inventory flow:
  - `ReferenceMaster_Enh.*` added as `wave=0` in Inventory manifest sequence (required by multiple Inventory Silver views).
- Re-ordered SQL wrapper procedure order to match wave model:
  - `03_operations/orchestration/main/manifest.json`
  - `03_operations/orchestration/*/manifest.json`
- Made YAML manifests mirror JSON sequences for both marts:
  - `03_operations/orchestration/forecast_accuracy/manifest.yaml`
  - `03_operations/orchestration/inventory_health/manifest.yaml`
- Updated orchestration READMEs to describe “Silver waves then Gold waves”:
  - `03_operations/orchestration/*/README.md`
- Regenerated operating packages (DQ/catalog/run-order) from updated manifests:
  - `python3 05_tools/04_operating_package/build_operating_package.py --repo-root .`

**Verification:**
- Dry-run printer shows wave-first ordering:
  - `python3 03_operations/tools/run_refresh.py --manifest 03_operations/orchestration/forecast_accuracy/manifest.json`
  - `python3 03_operations/tools/run_refresh.py --manifest 03_operations/orchestration/inventory_health/manifest.json`
- Generated run-order registry updated accordingly:
  - `02_marts/*/05_catalog/run_order.json`
  - `03_operations/operating_registry/run_order.json`

**Next step:**
- If Aric wants a runtime validation checkpoint, choose:
  1) wrapper SP execution (SQL Agent surface), or
  2) `pl_sc_mart(project_name)` REST smoke-test.
- Live execution requires explicit approval.

## 2026-06-24 14:40:00 ICT — Enterprise ETL wrapper runtime validation completed and mart-local wrapper contract finalized

**Scope lock:**
- Live Fabric SQL wrapper execution + repo orchestration metadata cleanup.
- No business SQL/view/table contract redesign.
- No destructive operations.

**User instruction:**
- Continue and finish the apply/run.
- Keep only the two active marts in the operational mental model.
- Silver and Gold wrappers must show the correct wave/table order; shared/reference dependencies should not look like a third mart.

**Live execution completed:**
- Ran SQL wrapper refresh path against `Enterprise SupplyChain-Dev` in order:
  1. `SupplyChain_Gold_Warehouse.dbo.Usp_Refresh_SupplyChain_Shared`
  2. `SupplyChain_Processing_Warehouse.dbo.Usp_Refresh_SupplyChain_ReferenceMaster`
  3. `SupplyChain_Processing_Warehouse.dbo.Usp_Refresh_ForecastAccuracy_Silver`
  4. `SupplyChain_Gold_Warehouse.dbo.Usp_Refresh_ForecastAccuracy_Gold`
  5. `SupplyChain_Processing_Warehouse.dbo.Usp_Refresh_InventoryHealth_Silver`
  6. `SupplyChain_Gold_Warehouse.dbo.Usp_Refresh_InventoryHealth_Gold`
- Result: `6/6` wrapper steps completed, `0` wrapper failures.
- Runtime:
  - Shared: `25.34s`
  - ReferenceMaster: `46.87s`
  - Forecast Silver: `332.02s`
  - Forecast Gold: `88.78s`
  - Inventory Silver: `1133.11s`
  - Inventory Gold: `438.12s`

**Post-run audit:**
- Processing warehouse compile check: `28` objects, `56` table/view `SELECT TOP 0` checks, `0` failures.
- Gold warehouse compile check: `13` objects, `26` table/view `SELECT TOP 0` checks, `0` failures.
- `ETL_Framework.DW_Developer.TableDictionary` wrapper scope: `41` rows, `41` `_Wrk.v_*` refs, `39` overwrite loader refs, `2` incremental loader refs.
- Stale active Inventory names are absent from `TableDictionary`:
  - `PurchaseOrderSnapshotDaily`
  - `InventorySnapshotWeeklyFactBase`
  - `LastInvoiceHelper`
  - `MovementFlagHelper`
  - `CogsRollingHelper`
  - `FactInventoryRiskForward`
- Recent non-succeeded query history contained one earlier canceled diagnostic/select-style Inventory query, not a wrapper step failure.

**Final wrapper contract after user correction:**
- Active operational surface is two marts only:
  - `forecast_accuracy`
  - `inventory_health`
- Each mart has exactly two active wrapper procedures:
  - `Usp_Refresh_<Mart>_Silver`
  - `Usp_Refresh_<Mart>_Gold`
- Mart Silver wrappers are self-contained and include `ReferenceMaster_Enh` prerequisite Wave 00.
- Mart Gold wrappers are self-contained and include `Shared_DW` prerequisite Wave 00.
- Shared/reference helper procedures may remain available, but they are not modeled as a third active mart.

**Live wrapper definitions redeployed after runtime validation:**
- `SupplyChain_Processing_Warehouse.dbo.Usp_Refresh_ForecastAccuracy_Silver`
  - `15` refresh calls, `0` incremental calls, `11` ReferenceMaster calls.
- `SupplyChain_Processing_Warehouse.dbo.Usp_Refresh_InventoryHealth_Silver`
  - `23` refresh calls, `2` incremental calls, `11` ReferenceMaster calls.
- `SupplyChain_Gold_Warehouse.dbo.Usp_Refresh_ForecastAccuracy_Gold`
  - `7` refresh calls, `3` Shared_DW calls.
- `SupplyChain_Gold_Warehouse.dbo.Usp_Refresh_InventoryHealth_Gold`
  - `9` refresh calls, `3` Shared_DW calls.

**Repo updates:**
- Updated mart SQL wrapper files under:
  - `03_operations/orchestration/forecast_accuracy/sql/`
  - `03_operations/orchestration/inventory_health/sql/`
- Updated wrapper procedure lists in:
  - `03_operations/orchestration/main/manifest.json`
  - `03_operations/orchestration/main/manifest.yaml`
  - `03_operations/orchestration/forecast_accuracy/manifest.json`
  - `03_operations/orchestration/forecast_accuracy/manifest.yaml`
  - `03_operations/orchestration/inventory_health/manifest.json`
  - `03_operations/orchestration/inventory_health/manifest.yaml`
- Updated orchestration READMEs so `main` means all-mart runner, not a `shared` project.
- Regenerated operating package:
  - `mart_count=2`
  - `dq_source_count=42`
  - `forecast_accuracy.run_step_count=13`
  - `inventory_health.run_step_count=25`

**Verification:**
- `python3 05_tools/04_operating_package/build_operating_package.py --repo-root .` passed.
- JSON parse passed for active orchestration manifests and operating registry.
- `python3 -m py_compile` passed for operating package and DQ tools.

**Next step:**
- Treat the wrapper procedure model as the current SQL Agent handoff:
  - all-mart: `Forecast Silver -> Forecast Gold -> Inventory Silver -> Inventory Gold`
  - single mart: run that mart's Silver wrapper, then Gold wrapper.

## 2026-06-24 14:58:00 ICT — Removed shared/reference helper wrapper procs from active operating surface

**Scope lock:**
- Live Fabric SQL cleanup + repo operating docs cleanup.
- Destructive operation explicitly approved by Aric in this conversation: clean up the lingering `ReferenceMaster` and `Shared` helper wrapper procs so only the two mart surfaces remain.

**Live changes:**
- Dropped helper procedures:
  - `SupplyChain_Processing_Warehouse.dbo.Usp_Refresh_SupplyChain_ReferenceMaster`
  - `SupplyChain_Gold_Warehouse.dbo.Usp_Refresh_SupplyChain_Shared`
- Live verification now shows only:
  - Processing `dbo`: `Usp_Refresh_ForecastAccuracy_Silver`, `Usp_Refresh_InventoryHealth_Silver`
  - Gold `dbo`: `Usp_Refresh_ForecastAccuracy_Gold`, `Usp_Refresh_InventoryHealth_Gold`

**Repo changes:**
- Removed helper SQL files:
  - `03_operations/orchestration/main/sql/SupplyChain_Processing_Warehouse.dbo.Usp_Refresh_SupplyChain_ReferenceMaster.sql`
  - `03_operations/orchestration/main/sql/SupplyChain_Gold_Warehouse.dbo.Usp_Refresh_SupplyChain_Shared.sql`
- Removed now-empty `03_operations/orchestration/main/sql/` folder.
- Updated active operation docs/rules:
  - `AGENTS.md`
  - `README.md`
  - `03_operations/orchestration/main/README.md`
- Regenerated operating package after cleanup.

**Verification:**
- Active grep across `AGENTS.md`, `README.md`, `03_operations/orchestration`, `03_operations/operating_registry`, and mart catalogs found no stale `Usp_Refresh_SupplyChain_ReferenceMaster`, `Usp_Refresh_SupplyChain_Shared`, `project: shared`, or `shared/reference first`.
- `python3 05_tools/04_operating_package/build_operating_package.py --repo-root .` passed.
- `python3 -m py_compile 05_tools/04_operating_package/build_operating_package.py 03_operations/tools/run_refresh.py` passed.
- `python3 03_operations/tools/run_refresh.py --manifest 03_operations/orchestration/main/manifest.json` now prints exactly four wrapper procs:
  1. `Usp_Refresh_ForecastAccuracy_Silver`
  2. `Usp_Refresh_ForecastAccuracy_Gold`
  3. `Usp_Refresh_InventoryHealth_Silver`
  4. `Usp_Refresh_InventoryHealth_Gold`

**Current handoff:**
- SQL Agent all-mart flow is now exactly four steps:
  - Forecast Silver -> Forecast Gold -> Inventory Silver -> Inventory Gold.
- Shared/reference dependencies exist only as Wave 00 calls inside the mart wrappers.

## 2026-06-24 15:43:30 ICT — Full 4-wrapper Enterprise ETL runtime rerun passed after DA live-code sync

**Scope lock:**
- Live Fabric SQL runtime validation and full all-mart refresh.
- No business layer redesign.
- Follow DA's latest live SQL contract where they reduced/changed columns.

**Preflight findings/fixes before run:**
- Initial strict preflight blocked the run because live Fabric differed from local for:
  - `SupplyChain_Processing_Warehouse.InventoryHistory_Enh_Wrk.v_AwdHelper`
  - `SupplyChain_Gold_Warehouse.Shared_DW_Wrk.v_DimProduct`
  - `SupplyChain_Gold_Warehouse.Shared_DW_Wrk.v_DimWarehouse`
- Aric confirmed DA intentionally changed these live definitions, so local repo SQL was synced to the live Fabric definitions.
- `ETL_Framework.DW_Developer.TableDictionary` active rows were cleaned:
  - 4 stale `ReplicatedSource` refs changed from old `*_ENH.vw_*` names to `_Wrk.v_*`
  - 8 stale active `ErrorMsg` values cleared after verifying current `_Wrk` contracts.

**Preflight verification after cleanup:**
- Live/local SQL modules matched: `49/49`.
- Missing live modules: `0`.
- Live/local drift: `0`.
- Active wrapper proc surface:
  - Processing `dbo`: `Usp_Refresh_ForecastAccuracy_Silver`, `Usp_Refresh_InventoryHealth_Silver`
  - Gold `dbo`: `Usp_Refresh_ForecastAccuracy_Gold`, `Usp_Refresh_InventoryHealth_Gold`
- Active `TableDictionary` curated rows: `46`.
- Active `TableDictionary` `_Wrk.v_*` refs: `46/46`.
- Active `TableDictionary` error rows: `0`.
- Compile check: `92/92` table/view `SELECT TOP 0` checks passed.

**Full flow executed in SQL-Agent-equivalent order:**
1. `SupplyChain_Processing_Warehouse.dbo.Usp_Refresh_ForecastAccuracy_Silver` — succeeded, `382.81s`.
2. `SupplyChain_Gold_Warehouse.dbo.Usp_Refresh_ForecastAccuracy_Gold` — succeeded, `94.07s`.
3. `SupplyChain_Processing_Warehouse.dbo.Usp_Refresh_InventoryHealth_Silver` — succeeded, `804.16s`.
4. `SupplyChain_Gold_Warehouse.dbo.Usp_Refresh_InventoryHealth_Gold` — succeeded, `439.97s`.

**Post-run verification:**
- Full flow result: `4/4` succeeded.
- Post-run live/local SQL modules: `49/49` matched, no missing, no drift.
- Post-run compile: `92/92` passed.
- Post-run active `TableDictionary`: `46` rows, `46` `_Wrk.v_*` refs, `0` error rows, `43` refresh loader refs, `3` incremental loader refs.
- `AuditLog` since run start: `56` `Process Start` + `56` `Process Complete`, `0` error rows.
- `queryinsights` since run start: no non-success entries.
- Semantic model read-only smoke: `sc_control_tower` (`f06a2361-15fd-4f91-9d37-941fefe62aaf`) exists in `Enterprise SupplyChain-Dev`; description remains Direct Lake on `SupplyChain_Gold_Warehouse`.
- Representative post-run direct rowcounts:
  - `ForecastHistory_Enh.ForecastDemandMonthly`: `156,160,392`
  - `SalesHistory_Enh.InvoiceDetailLineLevel`: `288,031,871`
  - `InventoryHistory_Enh.AwdHelper`: `2,409,242`
  - `InventoryHistory_Enh.ItemBalanceHistorical_WithInTransit`: `30,166,450`
  - `Shared_DW.DimProduct`: `780,848`
  - `InventoryHealth_DW.FactInventoryHealthSnapshot`: `3,220,912`
  - `ForecastAccuracy_DW.FactForecastKpi`: `122,773,185`

**Current handoff:**
- The Enterprise ETL-aligned runtime is validated for the two active marts.
- Final run order remains:
  - Forecast Silver -> Forecast Gold -> Inventory Silver -> Inventory Gold.
- Shared/reference dependencies remain embedded inside mart wrappers as Wave 00.

## 2026-06-24 20:34:30 ICT — Final closeout audit passed and repo docs updated

**Scope lock:**
- Final read-only live Fabric/SQL audit + repo documentation updates.
- No live data mutation.
- No business SQL redesign.

**User instruction:**
- Audit one last time, confirm whether data + operations are complete, then update repo/docs/README carefully.

**Final live audit result:**
- Overall: `final_pass=true`.
- Wrapper proc surface:
  - `SupplyChain_Processing_Warehouse.dbo.Usp_Refresh_ForecastAccuracy_Silver`
  - `SupplyChain_Processing_Warehouse.dbo.Usp_Refresh_InventoryHealth_Silver`
  - `SupplyChain_Gold_Warehouse.dbo.Usp_Refresh_ForecastAccuracy_Gold`
  - `SupplyChain_Gold_Warehouse.dbo.Usp_Refresh_InventoryHealth_Gold`
- Live/local SQL modules: `49/49` matched, `0` missing, `0` drift.
- Active `TableDictionary`: `46` curated rows, `46` `_Wrk.v_*` refs, `0` active bad/error rows.
- Compile smoke: `92/92` active target/source checks, `0` failures.
- `AuditLog` since full run start: `56 Process Start`, `56 Process Complete`, `0` errors; `56` paired object durations.
- `queryinsights`: `0` non-success entries since full run start.
- Semantic smoke: `sc_control_tower` exists and remains Direct Lake on `SupplyChain_Gold_Warehouse`.

**Slowest object durations from AuditLog:**
- `ForecastHistory_Enh.ForecastDemandMonthly`: `225s`
- `InventoryHealth_DW.ProjectedInventoryHealthSubStatus`: `209s`
- `InventoryHistory_Enh.SupplyPlanDetail`: `163s`
- `InventoryHistory_Enh.LastInvoiceWeekly`: `84s`
- `InventoryHistory_Enh.ItemBalanceHistorical_WithInTransit`: `83s`

**Docs updated:**
- `README.md`
  - added final runtime closeout table
  - added SQL Agent 4-step handoff
  - added Enterprise ETL view-to-table mapping contract
  - added wave detail for all four wrapper procs
  - added AuditLog duration query
- `03_operations/orchestration/main/README.md`
  - added current status and SQL Agent handoff
  - added monitoring query and `TableDictionary` usage notes
- `01_docs/README.md`
  - added current verified operating state and handoff pointers
- `01_docs/architecture/current/README.md`
  - added 2026-06-24 full wrapper validation status
- `01_docs/architecture/current/final_enterprise_etl_runtime_architecture.md`
  - updated final runtime architecture, mart map, execution order, and Phase 1 evidence
- `01_docs/Enterprise_Framework_Migration_Master_Plan.md`
  - added 2026-06-24 closeout block
  - converted Phase 1 acceptance checklist from `[Need-verify]` to verified/deferred status based on final audit

**Current handoff:**
- Phase 1 runtime is operationally complete and validated.
- DE orchestration should call only the four wrapper procedures in this order:
  1. Forecast Accuracy Silver
  2. Forecast Accuracy Gold
  3. Inventory Health Silver
  4. Inventory Health Gold
- Phase 2 remains deferred.

## 2026-06-24 20:47:00 ICT — Final repo/doc verification after closeout edits

**Scope lock:**
- Repo docs/readme cleanup only.
- No live Fabric/SQL mutation.

**Actions/evidence:**
- Clarified `01_docs/Enterprise_Framework_Migration_Master_Plan.md` so 2026-06-21/2026-06-22 baseline notes are explicitly historical and superseded by the 2026-06-24 closeout.
- Clarified `01_docs/architecture/current/final_enterprise_etl_runtime_architecture.md` mart map wording from `Current hub` to `Current folder`.
- Markdown fence sanity passed for `README.md`, `03_operations/orchestration/main/README.md`, `01_docs/README.md`, `01_docs/architecture/current/README.md`, `01_docs/architecture/current/final_enterprise_etl_runtime_architecture.md`, `01_docs/Enterprise_Framework_Migration_Master_Plan.md`, and `00_CONTEXT/current.md`.
- Python compile verification passed for current operation tools under `03_operations/tools/` and `05_tools/`.
- Stale proc grep found only historical entries in context and baseline history, not active handoff docs.

**Current handoff:**
- Final user-facing docs/readme are aligned with the 4-wrapper Enterprise ETL runtime closeout.

## 2026-06-24 21:12:00 ICT — ADR-010 persisted and SQLPROJ/CI-CD research started

**Scope lock:**
- Documentation/research only.
- No `.sqlproj` created.
- No CI/CD workflow created.
- No live Fabric/SQL mutation.

**User instruction:**
- Persist the Phase 1 closeout/runtime handoff decision into docs/context, then research Enterprise ETL's `sqlproj` docs and CI/CD model.

**Actions/evidence:**
- Added `01_docs/decisions/ADR-010-enterprise-etl-wrapper-runtime-handoff.md`.
- Added `01_docs/runbook/guides/sqlproj_cicd_research.md`.
- Updated `README.md`, `01_docs/README.md`, and `01_docs/enterprise-etl-framework/README.md` with links to ADR-010 and the SQLPROJ/CI-CD research guide.
- Reviewed Enterprise ETL docs:
  - `01_docs/enterprise-etl-framework/source/SQLPROJ_BEST_PRACTICES.md`
  - `01_docs/enterprise-etl-framework/source/FABRIC_ARCHITECTURE_AND_STANDARDS.md`
  - `99_archive/reverse-engineering/enterprise_data_architect/30_runbook/02_domain_team_workflow.md`
- Reviewed Microsoft Learn official docs:
  - Fabric Warehouse projects in VS Code
  - SQL projects automation
  - target platform overview

**Current finding:**
- `.sqlproj` / `.dacpac` should own schema/object deployment, not daily refresh execution.
- Daily refresh execution remains SQL Agent calling the four Phase 1 wrapper procedures.
- Enterprise ETL guide version note `Microsoft.Build.Sql 0.1.12-preview` conflicts with current Microsoft Fabric docs examples using `Microsoft.Build.Sql 2.0.0` plus `Microsoft.SqlServer.Dacpacs.FabricDw 170.0.2`; package versions must be verified against EnterpriseData actual repo or NuGet before implementation.
- Recommended next path is local build-only `.sqlproj` packaging first, not automated publish.

## 2026-06-24 21:46:48 ICT — Implemented build-only SQLPROJ package and docs cleanup

**Scope lock:**
- Repo/local files only.
- Read-only live SQL metadata was used by the generator.
- No `SqlPackage /Action:Publish`, no CI/CD workflow, no live Fabric/SQL mutation, no destructive cleanup.

**User instruction:**
- Proceed with the SQLPROJ handoff work, write full docs, and clean the repo structure as much as safely possible.

**Actions/evidence:**
- Added build-only SQLPROJ generator:
  - `05_tools/05_sqlproj/build_sqlproj_package.py`
  - `05_tools/05_sqlproj/README.md`
- Generated package:
  - `03_operations/deployment/sqlproj/ETL_Framework/`
  - `03_operations/deployment/sqlproj/Enterprise_Lakehouse_Reference/`
  - `03_operations/deployment/sqlproj/SupplyChain_Processing_Warehouse/`
  - `03_operations/deployment/sqlproj/SupplyChain_Gold_Warehouse/`
- Added SQLPROJ implementation plan:
  - `01_docs/plans/2026-06-24-sqlproj-build-only-package.md`
- Updated docs:
  - `README.md`
  - `03_operations/README.md`
  - `03_operations/deployment/sqlproj/README.md`
  - `01_docs/runbook/guides/sqlproj_cicd_research.md`
  - `05_tools/05_sqlproj/README.md`
- Added generated package evidence:
  - `03_operations/deployment/sqlproj/package_summary.json`
  - `03_operations/deployment/sqlproj/_package/build_summary.json`
  - `03_operations/deployment/sqlproj/_package/build_logs/*.log`
- Added `.gitignore` coverage for SQL project `bin/` and `obj/` local outputs.

**Build verification:**
- `python3 -m py_compile 05_tools/05_sqlproj/build_sqlproj_package.py` passed.
- `dotnet build` passed for all four generated projects:
  - `ETL_Framework`: 0 warnings, 0 errors
  - `Enterprise_Lakehouse_Reference`: 0 warnings, 0 errors
  - `SupplyChain_Processing_Warehouse`: 0 warnings, 0 errors
  - `SupplyChain_Gold_Warehouse`: 0 warnings, 0 errors

**Current handoff:**
- Repo now has a Enterprise ETL-compatible build-only `.sqlproj`/`.dacpac` handoff package.
- The package is safe for local validation and US/Enterprise ETL review.
- It must not be used for live publish until deployment ownership, publish profiles, service connection, and destructive-change gates are explicitly approved.

## 2026-06-24 22:29:38 ICT — Added DA-facing SQLPROJ CI/CD operating guide

**Scope lock:**
- Documentation only.
- No live Fabric/SQL mutation.
- No CI/CD publish workflow created.

**User instruction:**
- Write a detailed, easy-to-understand guide for SQLPROJ CI/CD with definitions, data-specific CI/CD terms, real operating logic, and a practical example.

**Actions/evidence:**
- Added `01_docs/runbook/guides/sqlproj_cicd_operating_guide_for_da.md`.
- Linked the guide from:
  - `README.md`
  - `01_docs/README.md`
  - `01_docs/runbook/guides/sqlproj_cicd_research.md`
  - `03_operations/deployment/sqlproj/README.md`
- Guide covers:
  - CI, CD, CI/CD, branch, commit, PR, merge
  - build, compile, `.sqlproj`, `.dacpac`, artifact, DacFx, SqlPackage
  - DeployReport, deploy script, publish, environment, gate/approval
  - data-loss guard, smoke test, wrapper procedure, `_Wrk` view, final table
  - `AuditLog`, `TableDictionary`, semantic smoke
  - practical `ForecastBiasPct` / `FactForecastKpi` end-to-end example
  - distinction between SQL object deployment and Enterprise ETL ETL runtime execution

**Verification:**
- Markdown fence sanity passed for the new guide and linked docs.
- Grep confirmed the new guide is discoverable from main SQLPROJ and docs entrypoints.

## 2026-06-24 22:40:40 ICT — Rebuilt root README as the single operating entrypoint

**Scope lock:**
- Repo documentation and local verification only.
- No live Fabric/SQL mutation.
- No destructive cleanup.

**User instruction:**
- Make the root `README.md` the single polished master index for repo knowledge, architecture, operations, CI/CD, and current Enterprise ETL runtime.
- Add generated Mermaid/SVG diagrams for the current operating flow.
- Keep the README useful as a template-style handoff while still documenting the current wrapper contract.
- Keep the repo lean without unsafe deletion.

**Actions executed:**
- Rebuilt root `README.md` as the main repo handbook and link hub.
- Added and linked generated diagram sources/assets:
  - `01_docs/architecture/current/readme_operating_map.mmd`
  - `01_docs/architecture/current/readme_operating_map.svg`
  - `01_docs/architecture/current/readme_cicd_to_runtime_flow.mmd`
  - `01_docs/architecture/current/readme_cicd_to_runtime_flow.svg`
  - `01_docs/architecture/current/readme_enterprise_etl_loader_contract.mmd`
  - `01_docs/architecture/current/readme_enterprise_etl_loader_contract.svg`
- Updated `01_docs/architecture/current/README.md` to index the new root README support diagrams.
- Root README now links the current docs system:
  - context, architecture, master plan, Enterprise ETL guide, mart packages, operations, SQLPROJ CI/CD, semantic, tools, and archive.
- Root README now documents the template CI/CD-to-runtime flow:
  - PR/commit -> `.sqlproj` build -> `.dacpac` -> DeployReport/Script -> approval -> publish -> scheduler/wrapper -> Enterprise ETL loader -> `_Wrk` view -> final table -> AuditLog/TableDictionary/DQ/semantic smoke.
- Root README keeps the current operational wrapper handoff:
  - Forecast Accuracy Silver
  - Forecast Accuracy Gold
  - Inventory Health Silver
  - Inventory Health Gold

**Verification:**
- Markdown fence sanity passed:
  - `README.md`
  - `01_docs/architecture/current/README.md`
  - `00_CONTEXT/current.md`
- Root README local link check passed:
  - `50` local links checked
  - `0` missing links
- Mermaid render verification passed for all three root README support diagrams using `mmdc`.
- Diagram asset existence check passed:
  - `readme_operating_map.svg`: `31620` bytes
  - `readme_cicd_to_runtime_flow.svg`: `31089` bytes
  - `readme_enterprise_etl_loader_contract.svg`: `23502` bytes
- SQLPROJ build verification passed via `03_operations/deployment/sqlproj/build_all.sh`:
  - `ETL_Framework`: `0` warnings, `0` errors
  - `Enterprise_Lakehouse_Reference`: `0` warnings, `0` errors
  - `SupplyChain_Processing_Warehouse`: `0` warnings, `0` errors
  - `SupplyChain_Gold_Warehouse`: `0` warnings, `0` errors

**Lean cleanup note:**
- Active top-level repo surface remains numbered and compact:
  - `00_CONTEXT`, `01_docs`, `02_marts`, `03_operations`, `04_semantic`, `05_tools`, `99_archive`.
- Physical generated/cache folders found but not deleted because deletion needs explicit approval:
  - SQLPROJ `bin/` and `obj/`
  - Python `__pycache__/`
- These are already covered by `.gitignore`, so they should not pollute commits.

**Current handoff:**
- Use root `README.md` as the only start page for repo onboarding and operations.
- Use `01_docs/runbook/guides/sqlproj_cicd_operating_guide_for_da.md` for full CI/CD definitions and operating explanation.
- Use `03_operations/orchestration/main/manifest.json` and wrapper procedures for runtime handoff.

## 2026-06-24 23:08:31 ICT — Converted root README into visual template handbook and added role onboarding

**Scope lock:**
- Repo documentation and local verification only.
- No live Fabric/SQL mutation.
- No destructive cleanup.

**User instruction:**
- Remove report-style closeout metrics from the root README because it should be a reusable knowledge/setup guide, not an evidence report.
- Make README more visual and easier for DA/DE readers.
- Add step-by-step onboarding guides for DA and DE.
- Show architecture, repo structure, CI/CD, runtime, and combined CI/CD-to-runtime workflow with diagrams.

**Actions executed:**
- Rewrote root `README.md` as a visual template handbook.
  - Metrics and one-time run numbers now point to context/artifacts instead of being embedded in the root guide.
  - README now emphasizes role navigation, architecture, mart package anatomy, Enterprise ETL loader contract, CI/CD workflow, ETL runtime workflow, full lifecycle, DA onboarding, DE onboarding, DQ/catalog, source-of-truth order, and safety.
- Added onboarding hub:
  - `01_docs/onboarding/README.md`
  - `01_docs/onboarding/da_onboarding.md`
  - `01_docs/onboarding/de_onboarding.md`
- Added new Mermaid/SVG diagrams:
  - `01_docs/architecture/current/readme_mart_package_anatomy.mmd`
  - `01_docs/architecture/current/readme_mart_package_anatomy.svg`
  - `01_docs/architecture/current/readme_full_lifecycle.mmd`
  - `01_docs/architecture/current/readme_full_lifecycle.svg`
  - `01_docs/onboarding/da_onboarding_flow.mmd`
  - `01_docs/onboarding/da_onboarding_flow.svg`
  - `01_docs/onboarding/de_operating_cycle.mmd`
  - `01_docs/onboarding/de_operating_cycle.svg`
- Updated doc indexes:
  - `01_docs/README.md`
  - `01_docs/architecture/current/README.md`
  - `02_marts/README.md`
  - `03_operations/README.md`

**Verification:**
- Markdown fence sanity passed for:
  - `README.md`
  - `01_docs/README.md`
  - `01_docs/architecture/current/README.md`
  - `01_docs/onboarding/README.md`
  - `01_docs/onboarding/da_onboarding.md`
  - `01_docs/onboarding/de_onboarding.md`
  - `02_marts/README.md`
  - `03_operations/README.md`
- Local link check passed:
  - `93` local links checked
  - `0` missing links
- Mermaid render verification passed for `8` diagrams:
  - `readme_operating_map`
  - `final_enterprise_etl_runtime_architecture`
  - `readme_mart_package_anatomy`
  - `readme_enterprise_etl_loader_contract`
  - `readme_cicd_to_runtime_flow`
  - `readme_full_lifecycle`
  - `da_onboarding_flow`
  - `de_operating_cycle`
- New SVG existence check passed:
  - `readme_mart_package_anatomy.svg`: `25910` bytes
  - `readme_full_lifecycle.svg`: `32917` bytes
  - `da_onboarding_flow.svg`: `21826` bytes
  - `de_operating_cycle.svg`: `20745` bytes

**Current handoff:**
- Root `README.md` is now the learning/operating map.
- Detailed numeric evidence remains in context, runbook artifacts, generated JSON packages, and live framework tables.
- DA onboarding is the default entry for business SQL/mart changes.
- DE onboarding is the default entry for live scan, repo sync, SQLPROJ, orchestration, DQ/catalog, semantic smoke, and context logging.

## 2026-06-25 00:00:00 ICT — Rewrote front-door docs in Vietnamese for cross-functional onboarding

**Scope lock:**
- Repo documentation and local verification only.
- No live Fabric/SQL mutation.
- No destructive cleanup.

**User instruction:**
- Assess whether the repo feels senior/professional enough.
- Make the root README more professional and easier for non-technical readers.
- Rewrite README in Vietnamese.
- Make README-linked front-door docs Vietnamese as well.
- Explain the story top-down instead of overwhelming users with unexplained technical terms.

**Actions executed:**
- Rewrote root `README.md` in Vietnamese with a narrative flow:
  - why the repo exists
  - how roles should read it
  - how data flows from source to semantic/report
  - how mart packages are structured
  - how Enterprise ETL runtime maps `_Wrk` view to final table
  - how CI/CD differs from ETL runtime
  - how DA and DE should work with the repo
  - where DQ/catalog evidence lives
  - source-of-truth and safety rules
- Added `01_docs/glossary.md` to explain common terms for DA and non-platform readers.
- Rewrote front-door docs in Vietnamese:
  - `01_docs/README.md`
  - `01_docs/onboarding/README.md`
  - `01_docs/onboarding/da_onboarding.md`
  - `01_docs/onboarding/de_onboarding.md`
  - `01_docs/architecture/current/README.md`
  - `01_docs/enterprise-etl-framework/README.md`
  - `02_marts/README.md`
  - `03_operations/README.md`
  - `03_operations/deployment/sqlproj/README.md`
  - `04_semantic/README.md`
  - `05_tools/README.md`
  - `99_archive/README.md`
  - `01_docs/runbook/guides/sqlproj_cicd_operating_guide_for_da.md`
- Updated Mermaid diagram labels to be more Vietnamese/user-friendly while keeping object names intact:
  - `readme_operating_map`
  - `final_enterprise_etl_runtime_architecture`
  - `readme_mart_package_anatomy`
  - `readme_enterprise_etl_loader_contract`
  - `readme_cicd_to_runtime_flow`
  - `readme_full_lifecycle`
  - `da_onboarding_flow`
  - `de_operating_cycle`

**Verification:**
- Local link check passed:
  - `87` local links checked
  - `0` missing links
- Mermaid render verification passed:
  - `8` diagrams rendered successfully.
- Markdown fence sanity passed for front-door docs before context update.
- Grep for major English onboarding headings returned no active hits in front-door docs.

**Current handoff:**
- Root README and front-door docs now target DA/DE/cross-functional readers first.
- Deep technical object names remain in English for grep/live Fabric alignment.
- Detailed numeric evidence remains in context/artifacts, not in the root handbook.

## 2026-06-25 09:46:30 ICT — Pushed operating repo to GitHub and made it private

**Scope lock:**
- Git/GitHub repository operation only.
- No live Fabric/SQL/Power BI mutation.

**User instruction:**
- Push the current repo to GitHub and close the repo as private.

**Actions executed:**
- Verified GitHub remote:
  - `origin`: `https://github.com/ankinguyen-engineer-2002/data-architecture-microsoft-medallion-vietnam-data-hub.git`
- Checked staged payload before commit:
  - staged existing files: `5450`
  - files over `100MB`: `0`
  - largest staged file: about `4.9MB`
  - common secret pattern scan over staged content returned no hits.
- Created local commit:
  - `37da41f2 docs: restructure fabric operating repo`
- Rebasing against `origin/main` completed without conflicts.
- Pushed `main` to GitHub:
  - `1e82342c..37da41f2 main -> main`
- Changed GitHub repository visibility to private.

**Verification:**
- `gh repo view` returned:
  - `visibility`: `PRIVATE`
  - `isPrivate`: `true`
  - default branch: `main`

**Current handoff:**
- Remote GitHub repo is private and contains the current operating-repo restructure commit.
- Final local clean/sync verification should be checked after this context note is committed and pushed.

## 2026-06-25 09:57:12 ICT — Reopened GitHub repo visibility to public

**Scope lock:**
- GitHub repository visibility operation only.
- No live Fabric/SQL/Power BI mutation.

**User instruction:**
- Temporarily make the GitHub repo public again; switch it back to private later only when explicitly requested.

**Actions executed:**
- Changed repository visibility from private to public:
  - `ankinguyen-engineer-2002/data-architecture-microsoft-medallion-vietnam-data-hub`

**Verification:**
- `gh repo view` returned:
  - `visibility`: `PUBLIC`
  - `isPrivate`: `false`
  - default branch: `main`

**Current handoff:**
- Repo is currently public.
- Do not change back to private until Aric explicitly asks.

## 2026-06-25 10:31:38 ICT — Removed generated `__generated_source_wrapper` wrappers from active views

**Scope lock:**
- View-definition cleanup only.
- No physical table DDL/DML.
- No ETL wrapper/proc execution.
- No semantic model/report refresh.

**User instruction:**
- Clean both marts because DA/DE flagged generated `Generated_Source_Wrapper` / `__generated_source_wrapper` CTE wrappers as confusing and not part of their original ETL SQL.
- Preserve old ETL business logic and do not affect current physical tables or full flow.

**Actions executed:**
- Added cleanup utility:
  - `05_tools/02_repo_maintenance/remove_generated_source_wrapper_cte.py`
- Regenerated active mart SQL from `HEAD` definitions and unwrapped generated `__generated_source_wrapper` CTEs.
- Updated active SQL in:
  - `02_marts/forecast_accuracy/`
  - `02_marts/inventory_health/`
  - `03_operations/deployment/sqlproj/SupplyChain_Processing_Warehouse/`
  - `03_operations/deployment/sqlproj/SupplyChain_Gold_Warehouse/`
- Patched old migration generator so it no longer generates `__generated_source_wrapper`:
  - `03_operations/tools/enterprise_contract/build_full_wrk_inline_rewrite.py`
- Applied live `CREATE OR ALTER VIEW` cleanup to:
  - `SupplyChain_Processing_Warehouse`: `31` `_Wrk` views
  - `SupplyChain_Gold_Warehouse`: `11` `_Wrk` views

**Verification:**
- Live Fabric metadata after cleanup:
  - `SupplyChain_Processing_Warehouse` modules with `__generated_source_wrapper`: `0`
  - `SupplyChain_Gold_Warehouse` modules with `__generated_source_wrapper`: `0`
- `SELECT TOP 0` compile check passed for:
  - `31` Processing views
  - `11` Gold views
- View-vs-final-table column contract matched for all `42` checked views.
- Local active SQL grep found no `__generated_source_wrapper` / `Generated_Source_Wrapper` references in:
  - `02_marts`
  - `03_operations/deployment/sqlproj`
- One first-pass live apply failure occurred on `ForecastAccuracy_DW_Wrk.v_FactForecastActual` due UNION column count; it was rolled back immediately from backup, transformer was fixed, and the single view was reapplied successfully.
- Evidence artifacts:
  - `01_docs/runbook/artifacts/20260625_102602_remove_generated_source_wrapper_cte_live/`
  - `01_docs/runbook/artifacts/20260625_103111_remove_generated_source_wrapper_cte_final_verification/`

**Current handoff:**
- Active repo SQL and live Fabric `_Wrk` views no longer contain generated `__generated_source_wrapper` wrappers.
- Physical tables, loaded data, ETL wrappers, AuditLog/TableDictionary, and semantic model were not refreshed or mutated by this cleanup.

## 2026-06-25 11:00:33 ICT — Canonicalized Enterprise ETL naming across repo

**Scope lock:**
- Repo text/path cleanup only.
- No live Fabric/SQL/Power BI mutation.
- No ETL refresh, data DDL/DML, or semantic model change.

**User instruction:**
- Remove the old external-name label from all repo documentation and path names.
- Treat the current runtime pattern as Aric's fixed `Enterprise ETL` standard.

**Actions executed:**
- Replaced old label references across text files with neutral `Enterprise ETL` / `enterprise_etl` wording.
- Renamed documentation/source folders and files to canonical names, including:
  - `01_docs/enterprise-etl-framework/`
  - `01_docs/architecture/current/final_enterprise_etl_runtime_architecture.*`
  - `01_docs/architecture/current/readme_enterprise_etl_loader_contract.*`
  - `01_docs/decisions/ADR-003-enterprise-etl-standards-compliance-audit.md`
  - `01_docs/decisions/ADR-008-enterprise-etl-alignment-naming-and-integration.md`
  - `01_docs/decisions/ADR-010-enterprise-etl-wrapper-runtime-handoff.md`
  - `05_tools/02_repo_maintenance/remove_enterprise_etl_source_cte.py`
- Fixed two stale links in `01_docs/enterprise-etl-framework/source/FABRIC_ARCHITECTURE_AND_STANDARDS.md`.

**Verification:**
- Case-insensitive repo content scan for the old label returned zero hits.
- Case-insensitive repo path scan for the old label returned zero paths.
- Active Markdown link check across `README.md`, `AGENTS.md`, `01_docs`, `02_marts`, `03_operations`, `04_semantic`, and `05_tools` returned:
  - `checked_files`: `96`
  - `missing_links`: `0`
- Python compile check passed for renamed/related tools:
  - `05_tools/02_repo_maintenance/remove_enterprise_etl_source_cte.py`
  - `03_operations/tools/enterprise_contract/build_full_wrk_inline_rewrite.py`
  - `05_tools/04_operating_package/build_operating_package.py`
  - `05_tools/05_sqlproj/build_sqlproj_package.py`

**Current handoff:**
- Repo docs, active operating files, and archived knowledge paths now use `Enterprise ETL` naming only.
- Git commit/push is the next step after final status review.

## 2026-06-25 14:29:13 ICT — Tightened DA onboarding for table edits and ETL wave handoff

**Scope lock:**
- Documentation-only update.
- No live Fabric/SQL/Power BI mutation.
- No orchestration manifest/runtime change.

**User question:**
- Check whether DA onboarding is clear enough for a DA to edit SQL for a table or add a table into the ETL wave/run order.

**Finding:**
- Existing DA onboarding covered ownership, source contract, grain/key, DQ, semantic impact, and high-level handoff.
- It did not yet give DA a concrete enough path for:
  - which SQL file to edit for an existing table;
  - which file pair to create for a new table;
  - how to propose `manifest.yaml` wave/step/load_type/purpose;
  - how wrapper procedures map final tables to `_Wrk.v_<TableName>` views.

**Actions executed:**
- Updated `01_docs/onboarding/da_onboarding.md` with:
  - `Step 5A - Sửa Logic Cho Một Bảng Đang Có`;
  - `Step 5B - Thêm Một Bảng Mới Vào Mart Hiện Có`;
  - `Cách Đưa Bảng Vào ETL Wave`;
  - manifest entry examples for Silver and Gold;
  - wrapper-procedure mapping explanation;
  - expanded pre-review checklist.

**Verification:**
- DA onboarding link check passed.
- Case-insensitive repo content scan for the old external label returned zero hits.

**Current handoff:**
- DA onboarding now explains the practical table-edit and wave-registration workflow.
- Next step is commit/push after final doc verification.

## 2026-06-26 13:39:30 ICT — Lineage portal rebuild context and governance correction

**Scope lock:**
- Repo/UI/automation work for `05_tools/06_lineage_portal/`.
- Target hosting remains GitHub Pages through GitHub Actions.
- No live Fabric SQL DDL/DML, no ETL refresh, no Power BI semantic/report mutation.
- Repo is public unless Aric explicitly asks to make it private again; Pages output is public.

**User instructions captured from chat:**
- Build a lineage tool on GitHub Pages, not Streamlit and not localhost.
- Automation must be durable: when Aric asks to scan/update marts later, GitHub Actions should rescan/remap/redraw, not be a one-off local artifact.
- Source of truth for mart-scoped lineage must be `02_marts/*/05_catalog`, not full workspace inventory.
- Lineage should follow each mart only; current marts are `forecast_accuracy` and `inventory_health`.
- Graph must show `table/entity -> table/entity`, not `_Wrk` view nodes or layer-view nodes.
- `_Wrk`/`v_*` work views must be collapsed out because they make lineage too noisy.
- UI should be dark, modern, spacious, with soft curved flow lines similar to data lineage/mindmap examples.
- User explicitly requested applying this stack as the new target:
  - Next.js 15 static export for GitHub Pages
  - React Flow as the core canvas
  - ELKJS auto-layout
  - Tailwind CSS v4 / shadcn-style components
  - Lucide icons
  - Motion/Framer Motion-ready stack
  - cmdk/TanStack Table dependencies available for future command palette/table views
  - Linear/Vercel/Raycast/Atlan-style dark design language
  - palette: `#09090B`, `#111113`, `#18181B`, `#27272A`, `#4F8CFF`, `#22C55E`, `#F59E0B`, `#EF4444`

**Governance correction / assistant deviation noted:**
- Aric flagged that the assistant was not following `AGENTS.md`/context tightly enough.
- Required behavior from here:
  - Always read `CLAUDE.md` and `00_CONTEXT/current.md` at the start of technical turns.
  - Keep `00_CONTEXT/current.md` updated after meaningful changes, not only at the end.
  - Do not delete generated folders/files or old Vite files without explicit approval.
  - For technical claims, use repo evidence or official docs; call out [Verified] / [Likely] / [Need-verify] when summarizing decisions.
  - For destructive operations, ask explicit same-conversation approval.

**Secrets/security note:**
- Aric pasted an app/client secret in chat during lineage setup.
- The secret value must not be written into repo/context/logs.
- Recommendation remains: rotate the Service Principal secret in Entra ID and update GitHub secret `FABRIC_CLIENT_SECRET`.

**Implemented lineage scanner/automation state before UI rebuild:**
- `05_tools/06_lineage_portal/scanner/` contains the lineage snapshot builder/scanner.
- The scanner can build fixture or live snapshots.
- GitHub workflow: `.github/workflows/lineage-portal.yml`
  - supports `workflow_dispatch` input `scan_mode=fixture|live`;
  - scheduled every two hours;
  - builds snapshot into `site/public/lineage_snapshot.json`;
  - runs secret scan against generated snapshot;
  - builds the static site;
  - deploys to GitHub Pages.
- GitHub Actions secrets configured earlier:
  - `FABRIC_TENANT_ID`
  - `FABRIC_CLIENT_ID`
  - `FABRIC_CLIENT_SECRET`
  - `FABRIC_WORKSPACE_ID`
  - `FABRIC_WORKSPACE_NAME`
  - `FABRIC_SQL_SERVER`
  - `FABRIC_SEMANTIC_MODEL_ID`
  - `FABRIC_SEMANTIC_MODEL_NAME`
- Live scan had succeeded in prior runs after SQL alias quoting fixes.
- Public snapshot after view-collapse showed:
  - `nodes`: `85`
  - `edges`: `117`
  - `views`: `0`
  - `_Wrk/v_*`: `0`
  - layers: Bronze/Silver/Gold/Semantic
  - marts: `forecast_accuracy`, `inventory_health`, `shared`

**Implemented UI rebuild in current working tree:**
- Migrated the frontend direction from Vite-style build to Next.js static export:
  - added `05_tools/06_lineage_portal/site/next.config.mjs`
  - added `05_tools/06_lineage_portal/site/postcss.config.mjs`
  - added `05_tools/06_lineage_portal/site/app/layout.tsx`
  - added `05_tools/06_lineage_portal/site/app/page.tsx`
  - added `05_tools/06_lineage_portal/site/app/globals.css`
  - updated `package.json`, `package-lock.json`, `tsconfig.json`
- Updated GitHub Pages workflow to upload `05_tools/06_lineage_portal/site/out` instead of Vite `dist`.
- Added `NEXT_PUBLIC_BASE_PATH=/data-architecture-microsoft-medallion-vietnam-data-hub` to the GitHub Actions build step for Pages path compatibility.
- Added custom React Flow table node:
  - `05_tools/06_lineage_portal/site/src/graph/LineageTableNode.tsx`
  - node style shows layer badge, schema, table/display name, wave, row count when available.
- Updated `05_tools/06_lineage_portal/site/src/graph/layout.ts`:
  - uses React Flow custom node type `lineageTable`;
  - uses Bezier curved edges with arrow markers;
  - uses ELKJS layered `RIGHT` layout as primary auto-layout;
  - keeps lane layout fallback only if ELKJS fails.
- Updated `05_tools/06_lineage_portal/site/src/App.tsx`:
  - `use client` for Next app router;
  - fetches snapshot from `NEXT_PUBLIC_BASE_PATH`;
  - default graph is mart-scoped clean path;
  - support/shared/unclassified nodes are hidden by default;
  - hidden support paths are collapsed into direct visible table flows;
  - clicking a table highlights upstream/downstream neighborhood and dims unrelated nodes;
  - removed MiniMap because it was blocking/covering useful semantic nodes in the current layout.
- Updated `05_tools/06_lineage_portal/site/src/styles/app.css`:
  - Linear-style dark palette;
  - sidebar + large React Flow canvas + bottom properties panel;
  - modern data-asset nodes;
  - subdued grid background;
  - curved/highlighted flow lines;
  - visible counters reflect currently visible graph, not the full workspace.

**Verification already executed locally:**
- Python scanner/unit tests:
  - `PYTHONPATH=05_tools/06_lineage_portal python3 -m unittest discover -s 05_tools/06_lineage_portal/tests -v`
  - result: `10` tests, `OK`
- Next static build:
  - `npm run build`
  - result: Next.js `15.5.19`, static export succeeded, `out/` produced.
- TypeScript:
  - `npm run typecheck`
  - result: passed after running build first so `.next/types` exists.
- npm audit:
  - initial audit found moderate `postcss <8.5.10` advisory through Next transitive dependency;
  - added `overrides.postcss=^8.5.10`;
  - final `npm audit --omit=dev` returned `found 0 vulnerabilities`.
- Playwright screenshot from static export:
  - `/tmp/lineage_next_final.png`
  - verified visually: dark modern UI, left sidebar, large React Flow canvas, table-to-table lineage, no `_Wrk` view nodes, ELK left-to-right layout, bottom properties panel.

**Current working tree / handoff risks:**
- Modified files:
  - `.github/workflows/lineage-portal.yml`
  - `05_tools/06_lineage_portal/site/package-lock.json`
  - `05_tools/06_lineage_portal/site/package.json`
  - `05_tools/06_lineage_portal/site/src/App.tsx`
  - `05_tools/06_lineage_portal/site/src/graph/layout.ts`
  - `05_tools/06_lineage_portal/site/src/styles/app.css`
  - `05_tools/06_lineage_portal/site/tsconfig.json`
- New intended source files:
  - `05_tools/06_lineage_portal/site/app/`
  - `05_tools/06_lineage_portal/site/next-env.d.ts`
  - `05_tools/06_lineage_portal/site/next.config.mjs`
  - `05_tools/06_lineage_portal/site/postcss.config.mjs`
  - `05_tools/06_lineage_portal/site/src/graph/LineageTableNode.tsx`
- Generated/untracked build artifacts currently present:
  - `05_tools/06_lineage_portal/site/.next/`
  - `05_tools/06_lineage_portal/site/out/`
  - `05_tools/06_lineage_portal/site/tsconfig.tsbuildinfo`
- Do not delete the generated artifacts without explicit Aric approval because destructive operations require same-conversation approval.
- Next step after this context entry:
  1. Check `.gitignore` and decide whether to ignore `.next/`, `out/`, `tsconfig.tsbuildinfo` without deleting existing files.
  2. Commit only source/workflow/package/context changes.
  3. Push to GitHub.
  4. Trigger `Build Lineage Portal` with `scan_mode=live`.
  5. Verify Pages snapshot and screenshot from the deployed URL.

## 2026-06-26 13:48:00 ICT — Full chat-history note for lineage portal request

**Purpose of this entry:**
- Aric explicitly asked to save the full chat history/prompt context into the latest context note and not miss anything.
- This is a detailed reconstruction of the lineage-portal conversation and decisions so a future assistant can resume without relying on hidden chat state.
- Secret values are intentionally redacted. Do not write plaintext credentials/secrets/API keys into repo files.

**Initial connection/Fabric app prompt:**
- Aric asked whether the assistant remembered the app connection added into Fabric workspace `Enterprise Supply Chain Dev`.
- Aric described the old goal as reading warehouses and bringing data back to make a web lineage tool, previously Streamlit-oriented.
- Aric shared an image of the Entra app registration:
  - Display name: `Fabric Pipeline Alert`
  - Application/client ID shown in the image: `616bb922-8969-4ff8-8dcf-3667c0ae8e19`
  - Object ID shown in the image: `99c8e68c-cc19-404f-a300-2a77f442a198`
  - Directory/tenant ID shown in the image: `5a9d9cfd-c32e-4ac1-a9ed-fe83df4f9e4d`
  - Supported account types: `My organization only`
- Aric pasted a client secret value and secret id:
  - secret value: `[REDACTED_SECRET_VALUE]`
  - secret id: `16332087-c1bd-4059-86e3-32c8f903367d`
- Aric asked to try connecting and see whether data in that workspace could be read.
- Security handling required:
  - Do not persist the secret value in repo/context.
  - Rotate the pasted secret in Entra ID.
  - Update GitHub Actions secret `FABRIC_CLIENT_SECRET` after rotation.

**Context correction prompt from Aric:**
- Aric said the repo now uses the new infrastructure and told the assistant to read the latest `00_CONTEXT` and `AGENTS.md` carefully.
- Aric explicitly said there is no old `meta` anymore.
- This meant the assistant must stop assuming old metadata tables/patterns and follow the current Phase 1 Enterprise ETL runtime/context.

**Original lineage tool goal prompt from Aric:**
- Goal: build a beautiful, standard lineage tool hosted on GitHub Pages.
- Explicitly do not use Streamlit even though Streamlit supports nice visualization, because it is hard to manage.
- Requirement 1:
  - Build an automatic mart scanner.
  - The scanner output should present and organize full scanned content similar to `02_marts`, but realtime/live instead of relying only on local repo files that may be stale.
  - It should include layer, ETL code, full table names, and similar mart catalog detail.
  - Store the tool somewhere under `05_tools`.
- Requirement 2:
  - After scanning, build a classification/pre-lineage tool based on the `02_marts` structure.
  - It must classify into layers:
    - Bronze
    - Silver waves: `wave 1, 2, 3, 4...`; waves need to be inferred automatically because more marts may be added later.
    - Gold waves: `wave 1, 2, 3, 4...`
    - one semantic model: `sc_control_tower`
- Requirement 3:
  - Host on GitHub Pages.
  - Use the Fabric app/connection to scan.
  - UI/UX should use a proper framework and beautiful Python/design-oriented libraries if needed.
  - The result should look like a solution architect/data architect textbook-quality lineage.
- Requirement 4:
  - Aric provided an Azure OpenAI Python snippet for future tool assistance/switchable APIs.
  - Endpoint in snippet: `https://agr-dev-openai.openai.azure.com/`
  - API version: `2024-02-01`
  - model: `gpt-5`
  - API key: `[REDACTED_API_KEY]`
  - Do not persist the plaintext API key in repo/context.
  - Aric said later more APIs may be added and switched between to help tools process/classify more accurately.
- Aric asked for a plan.

**Plan/hosting decision prompts from Aric:**
- Aric selected `option A`.
- Aric said he did not want localhost.
- Aric wanted GitHub Actions plus GitHub Pages for UI/UX.
- Aric said if this was OK then finalize that direction.
- Aric then said to implement.
- Aric later asked what the next step was and asked to see the deployed UI.
- Aric reported the deploy succeeded but he could not see data or lineage.
- Aric then said to continue.

**First UI/lineage feedback with screenshots from Aric:**
- Aric shared screenshots showing current portal problems:
  - Mart filter had too many categories such as `All marts`, `forecast_accuracy`, `shared`, `unresolved`.
  - Layer filter showed `All layers`, `Bronze`, `Gold`, `Semantic`, `Silver`; Aric said layer order/numbering was not right.
  - The lineage graph was very hard to read.
  - The graph had not enough data.
  - Aric provided reference screenshots showing desired lineage styles:
    - soft lineage flow like metadata/data catalog products;
    - curved lines;
    - open spacing;
    - dark/modern look;
    - user-friendly lineage similar to DataHub/OpenMetadata/Purview-style examples.
- Aric said the mart classification was wrong and affected the UI.
- Aric said there were only two marts, so filters/classification should not create misleading buckets.
- Aric said layers need correct ordered numbering.
- Aric said the current lineage looked extremely hard to read.
- Aric said the interface should be dark and more beautiful/friendly.

**Automation durability prompt from Aric:**
- Aric told the assistant to run the full flow and fix all automation.
- Aric said that in the future he wants to simply say to scan/update new marts, and the system should automatically run, map, and draw the new mart.
- Aric emphasized the tool must not be a one-time run.
- Aric told the assistant to finish and report; he wanted a full final answer before giving feedback.

**Lineage scope correction prompts from Aric:**
- Aric said the lineage was too hard to see, cramped, and did not look like his examples, which had soft curved and spacious lines.
- Aric said the assistant misunderstood scanning:
  - There are three layers, but the lineage should follow only the two marts.
  - If more marts are added later, it should follow marts.
  - Nobody asked to scan all Bronze.
- Aric repeated:
  - scan result should be like `02_marts`;
  - 3 layers;
  - only contain what is in that mart;
  - automatically classify layer and related metadata.
- Aric said lineage needs soft curved mindmap-like lines, not rigid lines.
- Aric said UX was not good and hard to use.
- Aric said the website colors/features still looked old/ancient and not modern/trendy.

**React Flow prompt from Aric:**
- Aric said he thought the system should apply React Flow to build a beautiful automated lineage platform.
- Aric explicitly recommended:
  - React Flow as the number one choice.
  - Website: `https://reactflow.dev`
  - Demo: `https://reactflow.dev/examples`
  - GitHub: `https://github.com/xyflow/xyflow`
- Aric said if building a Data Lineage Platform manually, React Flow is the top choice.
- Important implementation note:
  - The portal already had `@xyflow/react`, but it was initially used too primitively.
  - The correct direction is custom React Flow nodes, curved edges, focus/highlight mode, and clean viewport.

**Major design stack prompt from Aric:**
- Aric then asked to apply this stack to change the whole UI/system:
  - If choosing only one stack, choose:
    - `Linear Design System + shadcn/ui + React Flow + Tailwind + Framer Motion`
  - Aric described this as the 2026 top design stack for a Data Platform.
- Theme:
  - Dark First
  - Background: `#09090B`
  - Surface: `#111113`
  - Card: `#18181B`
  - Border: `rgba(255,255,255,.06)`
  - Primary: `#4F8CFF`
  - Accent: `#22C55E`
  - Warning: `#F59E0B`
  - Error: `#EF4444`
- Typography:
  - `Geist` or `Inter`
- Component library:
  - `shadcn/ui`
  - URL: `https://ui.shadcn.com/`
  - Components expected later: Sidebar, Dialog, Popover, Sheet, Command, Table, Dropdown, Tabs, Toast.
- Icons:
  - Lucide icons
  - URL: `https://lucide.dev/`
  - Do not use Heroicons.
- Styling:
  - Tailwind CSS
  - URL: `https://tailwindcss.com/`
- Animation:
  - Framer Motion / Motion
  - URL: `https://motion.dev/`
  - desired effects: fade, scale, hover, slide, spring.
- React Flow:
  - central UI/canvas.
  - URL: `https://reactflow.dev/`
  - Demos: `https://reactflow.dev/examples`
- Layout requested by Aric:
  - Header
  - Sidebar
  - React Flow Canvas
  - Details
  - Properties
  - ASCII layout:
    - top Header
    - left Sidebar
    - right React Flow Canvas
    - bottom Details / Properties area
- Auto layout:
  - ELKJS
  - URL: `https://eclipse.dev/elk/`
  - React Flow + ELKJS should be used for beautiful auto layout so nodes do not need manual dragging.
- Data table:
  - TanStack Table
  - URL: `https://tanstack.com/table`
  - desired because it is enterprise-grade and fast.
- Command palette:
  - `cmdk`
  - URL: `https://cmdk.paco.me/`
  - should feel like Cmd+K in Linear/Raycast/Cursor.
- Font:
  - Geist: `https://vercel.com/font`
  - or Inter: `https://rsms.me/inter/`
- Additional color style:
  - Background: `#09090B`
  - Card: `#18181B`
  - Border: `#27272A`
  - Hover: `#2A2A2E`
  - Blue: `#4F8CFF`
  - Green: `#22C55E`
  - Yellow: `#EAB308`
  - Red: `#EF4444`
- Layout inspiration:
  - Linear: `https://linear.app/`
  - Vercel: `https://vercel.com/`
  - Atlan: `https://atlan.com/`
  - DataHub demo: `https://demo.datahubproject.io/`
  - OpenMetadata sandbox: `https://sandbox.open-metadata.org/`
- UI inspiration:
  - Mobbin: `https://mobbin.com/`
  - Godly: `https://godly.website/`
  - Landbook: `https://land-book.com/`
  - Awwwards: `https://www.awwwards.com/`
- Desired React Flow node style:
  - Instead of default nodes, use data-asset cards like:
    - ItemBalance title with icon
    - divider
    - system/source
    - columns count
    - last updated info
  - Hover behavior:
    - light glow
    - shadow
    - brighter border
    - scale `1.02`
    - transition around `150ms`
  - Effects should be restrained and enterprise-friendly.
- Desired edge style:
  - Not straight rigid line.
  - SmoothStep/curved edge.
  - Animated when filtering.
  - Highlight upstream/downstream when selecting a node.
  - Edge colors should represent status such as active/warning/stale later.
- Full target stack table:
  - Framework: Next.js 15
  - UI: shadcn/ui
  - Styling: Tailwind CSS v4
  - Flow: React Flow
  - Auto Layout: ELKJS
  - Animation: Motion / Framer Motion
  - Icons: Lucide
  - Table: TanStack Table
  - Command Palette: cmdk
  - Charts: Tremor or Recharts
  - Fonts: Geist
  - Theme: next-themes
- Desired final product:
  - UX should feel like Linear.
  - Functionality should feel like Atlan/DataHub.
  - Graphical lineage experience should be React Flow.
  - Should feel like a modern enterprise Data Lineage platform, comparable in professionalism to Microsoft Purview, Databricks Unity Catalog, Atlan, or DataHub, but smoother and more visual through React Flow.

**Assistant implementation state after design-stack prompt:**
- Assistant acknowledged and decided to migrate the frontend target to Next.js static export because GitHub Pages needs static hosting.
- Assistant noted that scanner/live process remains GitHub Actions; UI consumes `lineage_snapshot.json`.
- Assistant checked official docs/internet briefly for:
  - Next static export / GitHub Pages compatibility.
  - React Flow custom node/layout capabilities.
  - Tailwind/Next compatibility.
- Files changed/added in working tree:
  - `.github/workflows/lineage-portal.yml`
  - `05_tools/06_lineage_portal/site/package.json`
  - `05_tools/06_lineage_portal/site/package-lock.json`
  - `05_tools/06_lineage_portal/site/tsconfig.json`
  - `05_tools/06_lineage_portal/site/next.config.mjs`
  - `05_tools/06_lineage_portal/site/postcss.config.mjs`
  - `05_tools/06_lineage_portal/site/app/layout.tsx`
  - `05_tools/06_lineage_portal/site/app/page.tsx`
  - `05_tools/06_lineage_portal/site/app/globals.css`
  - `05_tools/06_lineage_portal/site/src/App.tsx`
  - `05_tools/06_lineage_portal/site/src/graph/layout.ts`
  - `05_tools/06_lineage_portal/site/src/graph/LineageTableNode.tsx`
  - `05_tools/06_lineage_portal/site/src/styles/app.css`
- Packages installed/updated:
  - `next@15`
  - `tailwindcss@^4`
  - `@tailwindcss/postcss`
  - `motion`
  - `cmdk`
  - `@tanstack/react-table`
  - `next-themes`
  - `class-variance-authority`
  - `clsx`
  - `tailwind-merge`
  - `@types/node`
  - existing `@xyflow/react`, `elkjs`, `lucide-react`, `react`, `react-dom` retained.
- Vite packages were removed from dependencies, but old Vite files were not deleted yet:
  - `index.html`
  - `vite-env.d.ts`
  - `vite.config.ts`
  - This is intentional until Aric approves cleanup/deletion.

**Current UI behavior in working tree:**
- Next.js app router static export.
- `App.tsx` is a client component.
- Snapshot is fetched from `NEXT_PUBLIC_BASE_PATH/lineage_snapshot.json`.
- GitHub Actions sets `NEXT_PUBLIC_BASE_PATH=/data-architecture-microsoft-medallion-vietnam-data-hub`.
- Default mart is the first mart from `mart_registry`.
- Default graph hides `support` and `unclassified` nodes.
- Hidden support paths are collapsed into direct visible edges.
- Work views `_Wrk` and `v_*` are already removed by scanner snapshot simplification before UI.
- React Flow node type: `lineageTable`.
- ELKJS layered layout direction: left-to-right.
- Bezier curved edges with arrow markers.
- Click a node to highlight connected upstream/downstream neighborhood and dim unrelated nodes.
- Sidebar contains search, mart filter, layer filter, show shared/support toggle, and visible counters.
- Canvas is large and dark.
- Properties panel is at the bottom.

**Verification evidence from this chat segment:**
- Local scanner tests passed:
  - `10` tests, `OK`.
- Next build passed:
  - Next.js `15.5.19`.
  - static export produced `out/index.html`, `out/404.html`, `out/lineage_snapshot.json`.
- Typecheck passed after build:
  - `npm run typecheck`.
- npm audit:
  - initial moderate vulnerability came from `postcss <8.5.10` via Next transitive dependency.
  - Added package override for `postcss`.
  - final audit returned `found 0 vulnerabilities`.
- Playwright screenshot from static export:
  - `/tmp/lineage_next_final.png`.
  - visual state: dark Linear-style UI, left sidebar, large React Flow canvas, ELK left-to-right graph, table-to-table path, no visible `_Wrk` view nodes, bottom properties panel.

**Latest user correction prompt:**
- Aric said: "lưu hết lịch sử chat này vfo context mới nhất, tôi thấy bro đang ko tuân theo context vs agents.md"
- Assistant appended a governance/context correction entry.
- Aric then clarified: "note đầy đủ lịch sử chat cả prompt của tôi nhé, ko được sót 1 tí gì"
- This current entry is the expanded detailed chat-history note.

**Important resume instructions for next assistant turn:**
- Do not continue implementation before reading `CLAUDE.md` and this `00_CONTEXT/current.md` section.
- Do not claim deployment is complete until:
  - source changes are committed and pushed;
  - GitHub Action live run succeeds;
  - deployed Pages URL is checked;
  - deployed `lineage_snapshot.json` is checked;
  - screenshot from deployed URL is checked.
- Do not delete `.next/`, `out/`, `tsconfig.tsbuildinfo`, or old Vite files without explicit Aric approval.
- Do not write plaintext secrets/API keys into repo.

## 2026-06-26 14:05:57 ICT — Pre-deploy lineage portal CI hygiene and verification

**Scope lock:**
- Repo/source hygiene and local verification only.
- No live Fabric SQL DDL/DML, no ETL refresh, no Power BI/Fabric mutation.
- No deletion of generated artifacts.

**User instruction:**
- Continue building the unfinished lineage portal based on `AGENTS.md` and latest context.

**Actions executed:**
- Re-read `AGENTS.md` and latest `00_CONTEXT/current.md`.
- Added `.gitignore` entries for generated Next artifacts without deleting local files:
  - `05_tools/06_lineage_portal/site/.next/`
  - `05_tools/06_lineage_portal/site/out/`
  - `05_tools/06_lineage_portal/site/tsconfig.tsbuildinfo`
- Fixed GitHub Actions order for Next static export:
  - `npm run build` now runs before `npm run typecheck`;
  - this is required because `next-env.d.ts` references generated `.next/types`.
- Kept old Vite files untouched because deletion requires explicit Aric approval.

**Verification executed after the CI hygiene fix:**
- Scanner tests:
  - `PYTHONPATH=05_tools/06_lineage_portal python3 -m unittest discover -s 05_tools/06_lineage_portal/tests -v`
  - result: `10` tests, `OK`.
- Frontend static build:
  - `npm run build`
  - result: Next.js `15.5.19` static export succeeded.
- Frontend typecheck:
  - `npm run typecheck`
  - result: passed.
- npm audit:
  - `npm audit --omit=dev`
  - result: `found 0 vulnerabilities`.
- Static UI screenshot:
  - served `05_tools/06_lineage_portal/site/out` locally on port `4180`;
  - screenshot captured to `/tmp/lineage_next_predeploy.png`;
  - visual check: dark Linear-style UI, sidebar, React Flow canvas, table-to-table graph, bottom Properties panel.

**Current handoff:**
- Next step is commit/push, then trigger GitHub Actions `Build Lineage Portal` with `scan_mode=live`, then verify deployed Pages URL and snapshot.

## 2026-06-26 14:14:52 ICT — Removed canvas overlay clutter before redeploy

**Scope lock:**
- Lineage portal frontend UX cleanup only.
- No live Fabric SQL DDL/DML, no ETL refresh, no Power BI/Fabric mutation.

**Finding from deployed screenshot:**
- The first deployed Next/React Flow build worked, but canvas caption/lane markers overlapped top-row nodes.
- This also conflicted with Aric's earlier instruction that he does not need layer-view UI in the graph.

**Actions executed:**
- Removed the visible canvas caption from `App.tsx`.
- Removed lane ruler/lane marker rendering from `App.tsx`.
- Removed corresponding CSS from `app.css`.
- Adjusted ELK/fallback layout offsets in `layout.ts` to reserve simpler canvas padding without overlay labels.

**Verification:**
- Scanner tests passed: `10` tests, `OK`.
- `npm run build` passed with Next.js `15.5.19`.
- `npm run typecheck` passed.
- `npm audit --omit=dev` returned `found 0 vulnerabilities`.
- Static export screenshot captured to `/tmp/lineage_next_predeploy_clean.png`; visual check shows no caption/lane label overlap.

**Current handoff:**
- Commit/push this small UX patch, trigger live GitHub Actions deploy again, then verify deployed Pages URL/snapshot/screenshot.

## 2026-06-26 14:33:21 ICT — Applied second UI feedback pass for readability and focus

**Scope lock:**
- Lineage portal frontend UX only.
- No live Fabric SQL DDL/DML, no ETL refresh, no Power BI/Fabric mutation.

**User feedback captured:**
- UI/UX is better than before but still not excellent/modern enough compared with the framework/library references.
- It was not clear which table belongs to which layer or wave.
- Lineage was okay but still too cramped.
- Theme/font still felt outdated.
- Properties panel at the bottom was hard to read and was hidden/covered too much.
- When clicking a table, related upstream/downstream lineage and boxes should change color strongly to emphasize the selected lineage path.

**Actions executed:**
- Node cards now show explicit layer label and wave badge:
  - layer short code + full layer text;
  - `Wave n` / `Wave n/a` badge.
- Increased node width for readability.
- Removed forced full-graph fit on initial load; default viewport now opens at a more readable zoom and lets users pan horizontally.
- Moved selected-table Properties from bottom panel to a right-side sheet that only appears after selecting a node.
- Added click-on-canvas behavior to close the Properties sheet.
- Reworked selection highlighting:
  - selected node: blue focus ring;
  - upstream nodes/edges: amber highlight;
  - downstream nodes/edges: green highlight;
  - unrelated nodes/edges: much stronger dimming.
- Updated detail panel upstream/downstream lists to show readable table display names plus layer/wave, instead of raw node ids only.
- Updated font stack to prefer `Geist` then `Inter`.

**Verification:**
- Scanner tests passed: `10` tests, `OK`.
- `npm run build` passed with Next.js `15.5.19`.
- `npm run typecheck` passed.
- `npm audit --omit=dev` returned `found 0 vulnerabilities`.
- Static export screenshot captured to `/tmp/lineage_feedback_zoom_readable.png`; visual check shows readable node cards with layer/wave and no left clipping.

**Current handoff:**
- Commit/push the UX patch, trigger live GitHub Actions deploy, then verify deployed Pages URL/snapshot/screenshot.

## 2026-06-26 14:41:12 ICT — Switched lineage layout to deterministic layer/wave columns

**Scope lock:**
- Lineage portal frontend layout only.
- No live Fabric SQL DDL/DML, no ETL refresh, no Power BI/Fabric mutation.

**User feedback captured:**
- When the graph has invisible layer columns, each layer/wave must be one clear vertical column.
- If there is a wave, each `Layer + Wave` should be its own vertical column.
- If there is no wave, the layer should be a single vertical column.
- Boxes inside the same layer/wave column must share the same x-axis and stack vertically; they must not split into 2-3 uneven sub-columns.

**Actions executed:**
- Replaced ELK primary layout with deterministic architecture layout:
  - `Bronze` column;
  - `Silver W00`, `Silver W01`, `Silver W02`, ... columns;
  - `Gold W00`, `Gold W10`, `Gold W30`, ... columns;
  - `Semantic` column.
- Every table in the same lane now uses the same x position and increments only on y.
- Kept animated Bezier edges.
- Resulting bundle became smaller because ELK is no longer imported into the runtime bundle.

**Verification:**
- Scanner tests passed: `10` tests, `OK`.
- `npm run build` passed with Next.js `15.5.19`.
- `npm run typecheck` passed.
- `npm audit --omit=dev` returned `found 0 vulnerabilities`.
- Static screenshot captured to `/tmp/lineage_lane_columns.png`; visual check shows table cards aligned in single vertical columns per layer/wave.

**Current handoff:**
- Commit/push this deterministic lane layout and trigger live GitHub Actions deployment.

## 2026-06-26 14:49:42 ICT — Deployed deterministic layer/wave column lineage layout

**Scope lock:**
- GitHub Actions/Pages deploy verification only.
- Live scan reads Fabric metadata; no Fabric SQL DDL/DML, no ETL refresh, no Power BI/Fabric mutation.

**Actions executed:**
- Committed deterministic layer/wave layout:
  - commit `8bf7e6ec fix: align lineage nodes by layer wave columns`
- Pushed `main` to GitHub.
- Triggered GitHub Actions workflow:
  - workflow: `Build Lineage Portal`
  - run id: `28224485185`
  - mode: `scan_mode=live`

**Verification:**
- GitHub Actions completed successfully:
  - head SHA: `8bf7e6ec490f81f71132f3699841a78f0af46ab3`
  - job duration: about `5m14s`
  - steps passed: live scan, secret scan, Node install, Next build, typecheck, Pages upload/deploy.
- Pages URL returned `HTTP 200`:
  - `https://ankinguyen-engineer-2002.github.io/data-architecture-microsoft-medallion-vietnam-data-hub/?v=8bf7e6ec`
- Public snapshot check:
  - nodes: `85`
  - edges: `117`
  - views: `0`
  - `_Wrk/v_*`: `0`
  - marts: `forecast_accuracy`, `inventory_health`, `shared`
  - warning remains: `Semantic model definition was not available; semantic edges are incomplete.`
- Deployed screenshot captured:
  - `/tmp/lineage_pages_8bf7e6ec.png`
  - visual check: table boxes align into deterministic vertical layer/wave columns, with animated curved edges and modern dark theme.

**Current handoff:**
- Deployed UI is live at the Pages URL above.
- Remaining known issue: semantic model definition REST access still unavailable, so semantic edges are incomplete until that endpoint/permission path is fixed.

## 2026-06-28 11:27:35 ICT — Fixed semantic reader, synced DA changes, rebuilt lineage snapshot

**Scope lock:**
- Scanner code fix, repo SQL sync from live Fabric, lineage snapshot rebuild.
- No live Fabric/SQL mutation (read-only scan + repo write).

**User instruction:**
- Fix tool đọc semantic trên live Fabric để update lineage.
- Scan lại 3 layer 2 mart, sync DA changes về repo.
- Dùng Fabric REST API, Python, MCP.

**Semantic reader root cause & fix:**
- `fabric_rest.get_semantic_definition` polled PBI redirect URL (`wabi-us-north-central-c-primary-redirect.analysis.windows.net`) which is unreachable from GitHub Actions.
- Fix: always poll Fabric API operation endpoint (`https://api.fabric.microsoft.com/v1/operations/{op_id}`) and result endpoint.
- Added `az` CLI token support (`FABRIC_USE_AZ_CLI=true`) for local development.
- Added `sourceLineageTag` fallback parser in `semantic_reader.py` for TMDL tables without Direct Lake partition source.

**Scanner changes:**
- `scanner/fabric_rest.py` — LRO polling: always use Fabric API endpoint, drop PBI Location URL dependency.
- `scanner/auth.py` — added `az_cli_token()` function.
- `scanner/config.py` — added `use_az_cli` flag.
- `scanner/cli.py` — dual auth path (SP credentials or az CLI).
- `scanner/semantic_reader.py` — added `extract_lineage_tag_source()` fallback.

**Live scan result (post-fix):**
- 911 nodes, 1127 edges, 12 semantic bindings, 0 warnings.
- Semantic model `sc_control_tower` fully parsed: 12 Gold tables → semantic bindings.
- 17 semantic nodes total (12 business tables + 1 model + 4 artifacts).

**DA changes synced (live Fabric → repo):**
- 44 `_Wrk` view SQL files updated.
- 5 new view files created (previously missing from repo).
- 2 files unchanged (already in sync).
- 1 new source table discovered: `Staging_Wrk.v_DemandForecastSnapshotDaily`.
- Key DA logic changes (real business logic, not just headers):
  - `OpenOrderHistory_Enh_Wrk.v_OpenOrderLineLevel`: +1,127 chars (rewritten)
  - `SalesHistory_Enh_Wrk.v_InvoiceDetailLineLevel`: +1,626 chars (columns added/removed)
  - `InventoryHealth_DW_Wrk.v_FactInventoryHealthFutureWeekEnding`: +823 chars
  - `ForecastHistory_Enh_Wrk.v_ForecastDemandMonthly`: +292 chars
  - `InventoryHealth_DW_Wrk.v_FactInventoryHealthSnapshot`: -115 chars
  - `InventoryHistory_Enh_Wrk.v_Cogs52WWeekly`: -104 chars
  - `InventoryHistory_Enh_Wrk.v_LastInvoiceWeekly`: -104 chars
  - `InventoryHistory_Enh_Wrk.v_PurchaseOrderSnapshotHistorical`: +115 chars
  - `Shared_DW_Wrk.v_DimWarehouse`: +1,456 chars (new file, full view SQL)

**Deploy:**
- Commit `3f92d4b8`: fix semantic reader + sync 44 DA SQL views.
- Push to `origin/main`.
- Workflow `Build Lineage Portal` triggered with `scan_mode=fixture` (snapshot already embedded).
- Workflow run: `28311545405` (queued).

**Verification:**
- Python: 10/10 tests pass.
- TypeScript: 0 type errors.
- Next.js build: OK (62.6 kB).
- Semantic edges: 12 bindings, 0 warnings (previously had incomplete warning).

**Current handoff:**
- Semantic reader is fixed and verified with live Fabric data.
- Repo SQL is synced with live Fabric as of 2026-06-28.
- Lineage portal is deploying with complete semantic edges.
- Next: monitor workflow run `28311545405` for deployment completion.

## 2026-06-28 12:15:00 ICT — Topological wave ordering fix + wrapper SP redeploy + full refresh

**Scope lock:**
- Algorithm fix, live Fabric SP redeploy, full 4-wrapper refresh, repo catalog/manifest/tool update.
- No destructive operations.

**User instruction:**
- Fix wave assignment so B never shares wave with A if B depends on A.
- Redeploy wrapper SPs on live Fabric with corrected EXEC order.
- Update repo mart folders, catalog, manifests, tools, docs.

**Problem:**
- 224 same-layer same-wave dependency violations: e.g. InvoiceDetailLineLevel (W1)
  → AwdHelper (W1) — B depends on A but same wave, lineage crosses backwards.
- Root cause in `wave_builder.py`:
  1. Catalog explicit waves used as absolute override (not floor).
  2. Explicit-wave nodes pre-loaded into initial queue before dependency resolution.

**Fix — `wave_builder.py` rewritten:**
- Pure Kahn's topological sort within each layer (Silver, Gold).
- Catalog wave = floor (minimum), never an override.
- Actual wave = max(catalog_floor, 1 + highest_dependency_wave).
- Nodes wait in queue until ALL dependencies resolved.
- Result: 0 same-wave violations.

**Wrapper SPs redeployed to live Fabric:**
- `Usp_Refresh_ForecastAccuracy_Silver` — W00→W01→W02→W03
- `Usp_Refresh_ForecastAccuracy_Gold` — W01→W10→W30
- `Usp_Refresh_InventoryHealth_Silver` — W00→W01→W02 (key: AwdHelper/Cogs52WWeekly/LastInvoiceWeekly → W02)
- `Usp_Refresh_InventoryHealth_Gold` — W01→W10→W20→W21→W30 (key: InventoryClassificationQtyWeekly → W21)

**Full 4-wrapper refresh executed on live Fabric:**
- 4/4 OK, 33.1s total (data already fresh).
- Forecast Silver: 10.1s, Forecast Gold: 9.1s
- Inventory Silver: 6.2s, Inventory Gold: 7.7s

**Repo updates:**
- `02_marts/*/05_catalog/run_order.json` — corrected wave sequence + added missing tables.
- `03_operations/orchestration/main/manifest.json` — switched to wrapper_sp API.
- `03_operations/tools/run_refresh.py` — full rewrite with --execute for direct SP execution via pyodbc.
- `03_operations/orchestration/*/sql/*.sql` — 4 wrapper SPs updated with corrected EXEC order.
- `05_tools/06_lineage_portal/scanner/wave_builder.py` — Kahn's algorithm.

**Corrected wave lanes:**
```
01 Bronze Sources              33 nodes
02 Silver W00                 530 nodes
02 Silver W01                  15 nodes
02 Silver W02                   9 nodes
02 Silver W03                   1 node
03 Gold W00                   293 nodes
03 Gold W00 Shared              3 nodes  (DimCalendar, DimProduct, DimWarehouse)
03 Gold W10 Dimensions           3 nodes  (DimCustomerGrouping, DimForecastHorizon, DimVendor)
03 Gold W20 Helpers              3 nodes  (IHSubStatusWeekly, ProjectedIHSubStatus, +ICQtyWeekly at W21)
03 Gold W30 Facts                4 nodes  (FactForecastActual, FactForecastKpi, FactIHFuture, FactIHSnapshot)
04 Semantic sc_control_tower    17 nodes
```

**Verification:**
- Python: 10/10 tests pass.
- TypeScript: 0 type errors.
- Next.js build: 62.6 kB.
- Semantic edges: 12 bindings, 0 warnings.
- Same-wave violations: 0 (down from 224).
- Live Fabric: 4/4 SPs deployed and executed successfully.

**Current handoff:**
- Wave ordering is topologically correct across all 3 layers.
- Wrapper SPs on live Fabric match the corrected order.
- Lineage portal renders clean forward-flowing graph with 11 lanes.
- All repo catalog/manifest/tool/docs updated.

## 2026-06-29 10 (1)
00 ICT — Reinstalled Claude MCP user config to official commands where verifiable
- Scope lock: Claude user MCP config only; no Fabric live mutations.
- User instruction: reinstall MCPs for Claude, skip already-present by effectively replacing broken entries.
- Actions/evidence:
  - Verified official/npm install targets for `@microsoft/fabric-mcp`, `@azure/mcp`, `@microsoft/powerbi-modeling-mcp`, Fabric Core remote URL, and current `fabric-dynamic`/`fabric-rti`/`microsoft-learn`.
  - Reinstalled user-scope MCP entries via `claude mcp add/remove`: `fabric-official`, `azure`, `powerbi-modeling`, `fabric-core`, `microsoft-learn`, `datafactory`.
  - Health check after reinstall: `fabric-official` ✔, `azure` ✔, `microsoft-learn` ✔, existing `fabric-dynamic` ✔, `fabric-rti` ✔; `powerbi-modeling` ✘, `fabric-core` ✘, `datafactory` ✘.
  - Direct startup probe: `@microsoft/powerbi-modeling-mcp --start` exits 0 standalone; Claude health check still fails. `dnx Microsoft.DataFactory.MCP --yes` fails because package not found on nuget.org.
- Files changed/live changes: user MCP config in `/Users/MAC/.claude.json`.
- Blocker/risk: `fabric-core` likely needs OAuth/interactive auth not completed in headless health check; `powerbi-modeling` likely requires first semantic-model connection/auth flow; `datafactory` published package/command appears unavailable from current feed.
- Next concrete step: report installed/healthy vs blocked servers; if needed, debug OAuth/interactive setup for failed MCPs or add org-specific MCPs with user-provided IDs/URLs.

## 2026-06-29 10:30:00 ICT — Bronze source 2023 coverage DQ check executed

**Scope lock:**
- Read-only DQ coverage audit for 33 Enterprise_Lakehouse Bronze source tables supporting Inventory Health and Forecast Accuracy.
- No Fabric/SQL mutation and no repo object deployment.

**User instruction:**
- Read and remember prior Bronze DQ report, then add missing coverage check: whether required source data covers from `2023-01-01` or whether data starts later.
- Combine MCP with Fabric REST/API where appropriate.

**Actions/evidence:**
- MCP `fabric-dynamic.health_check`: ready, workspace `c8d9fc83-18b6-4e1d-8264-0b49eed36fe0`.
- Fabric REST via `az rest --resource https://api.fabric.microsoft.com`: verified Lakehouse item `Enterprise_Lakehouse` / `584e7d2c-46ca-49dc-bb6c-68df6ef4f424` and workspace Lakehouse list.
- Repo contracts checked: `02_marts/*/04_dq/contracts/bronze_sources.json`; no existing coverage-from-2023 rule found in the Bronze DQ rule set.
- SQL endpoint pyodbc read-only audit executed against `Enterprise_Lakehouse` through Fabric SQL endpoint.

**Key finding:**
- Coverage DQ is not equivalent to freshness: several snapshot/current-state sources are fresh but start in 2024/2025/2026, so they fail if the business rule is strict historical coverage from `2023-01-01`.
- Tables with clear post-2023 starts include `SupplyChain_Enh.ATPWeekEnding`, `SupplyChain_Enh.DemandInventorySnapshotDaily`, `SupplyChain_Enh.SupplyPlanDetailSnapshotDaily`, `SupplyChain_Enh.SupplyPlanDetailSnapshotWeekly`, `Wholesale_Codis_AFI.EXTORIT`, `Wholesale_Codis_AFI.codatan`; `SupplyChain_Enh.DemandForecastSnapshotDaily` min `dfcSnapshot` = 2020-01-01 and has rows after cutoff, but exact row-before aggregation hit Fabric integer overflow on combined aggregate and was probed separately.
- Static/master tables without selected date columns need explicit N/A decision, not automatic failure.

**Files changed/live changes:**
- Context only: `00_CONTEXT/current.md`.

**Blocker/risk:**
- Need Aric/business owner to define which sources truly require full historical coverage from `2023-01-01` vs source-system valid-from/current-state semantics.

**Next concrete step:**
- Add a formal Bronze DQ rule such as `history_coverage_min_date` with per-table `required_start_date` / `coverage_column` / `not_applicable_reason`, then regenerate DQ contracts after approval.

## 2026-06-29 10:45:00 ICT — Project opencode skills installed with non-overlap boundaries

**Scope lock:**
- opencode project skill files only.
- No Fabric/SQL/Power BI/cloud mutation.
- No global opencode config mutation because external directory access to `/Users/MAC/.config/opencode` is denied by current permissions.

**User instruction:**
- Continue installing a selected skill list and ensure their responsibilities do not overlap: SuperPower, UI UX Pro Max, Prompt Master, Security Expert, Testing Expert, Database Expert, DevOps Expert, Documentation Expert.

**Actions/evidence:**
- Loaded `customize-opencode` guidance and verified opencode config schema from `https://opencode.ai/config.json`.
- Confirmed project initially had no `opencode.json*` and no `.opencode/skills/**/SKILL.md`.
- Created 8 project-scope skills under `.opencode/skills/*/SKILL.md` with explicit `description` trigger boundaries and `Do not use...` exclusions.
- Clarified with user that the created `superpower` is a lightweight adapter/router, not an official SuperPower Claude Code package with bundled subskills/slash commands.

**Files changed/live changes:**
- Added `.opencode/skills/superpower/SKILL.md`.
- Added `.opencode/skills/ui-ux-pro-max/SKILL.md`.
- Added `.opencode/skills/prompt-master/SKILL.md`.
- Added `.opencode/skills/security-expert/SKILL.md`.
- Added `.opencode/skills/testing-expert/SKILL.md`.
- Added `.opencode/skills/database-expert/SKILL.md`.
- Added `.opencode/skills/devops-expert/SKILL.md`.
- Added `.opencode/skills/documentation-expert/SKILL.md`.
- Updated `00_CONTEXT/current.md`.

**Blocker/risk:**
- If user wants official SuperPower framework rather than lightweight adapter, need source URL/package/repo or approval to research/install. Full official SuperPower may overlap with the 7 specialist skills unless installed as workflow-only umbrella.
- opencode must be restarted before new skills are loaded.

**Next concrete step:**
- Decide whether to keep lightweight `superpower` router or replace/augment it with the official SuperPower Claude Code framework after verifying the source.

## 2026-06-29 10:55:00 ICT — Reduced opencode skills to 4 selected packs

**Scope lock:**
- opencode project skill files only.
- No Fabric/SQL/Power BI/cloud mutation.
- No global opencode config mutation.

**User instruction:**
- Reduce skill set to exactly 4 packs to avoid overlap: Superpowers, UI UX Pro Max, Awesome Agent Toolkit, Awesome Goal Prompts.
- User noted official SuperPower is a known Claude Code workflow/skills/slash-command framework covering brainstorming, planning, implementation, and verification.

**Actions/evidence:**
- Removed previously created expert skill files for `prompt-master`, `security-expert`, `testing-expert`, `database-expert`, `devops-expert`, and `documentation-expert`.
- Replaced singular `.opencode/skills/superpower/SKILL.md` with `.opencode/skills/superpowers/SKILL.md`.
- Added `.opencode/skills/awesome-agent-toolkit/SKILL.md`.
- Added `.opencode/skills/awesome-goal-prompts/SKILL.md`.
- Updated `.opencode/skills/ui-ux-pro-max/SKILL.md` boundaries to reference only the 4 selected skills.
- Removed now-empty old skill directories with `rmdir`.
- Verified `.opencode/skills` contains exactly 4 directories: `awesome-agent-toolkit`, `awesome-goal-prompts`, `superpowers`, `ui-ux-pro-max`.

**Files changed/live changes:**
- Added/updated project-scope opencode skill wrappers under `.opencode/skills/*/SKILL.md`.
- Updated `00_CONTEXT/current.md`.

**Blocker/risk:**
- These are opencode wrapper/adaptation skill files, not verified official SuperPower/Awesome pack contents. Need source repo/package/URL before claiming official installation.
- opencode must be restarted before new project skills are loaded.

**Next concrete step:**
- If user wants official pack parity, provide source URLs or approve web research/install, then replace wrappers with verified official content where compatible with opencode skill format.

## 2026-06-29 11:25:00 ICT — Installed verified Superpowers and UI UX Pro Max skills

**Scope lock:**
- AI coding assistant skill installation only.
- No Fabric/SQL/Power BI/cloud mutation.
- Repo mutation limited to `.opencode/skills/*` and context log.
- Global user-tooling mutation occurred via official installer bootstrap; no secrets handled.

**User instruction:**
- Install only the two verified/popular packs first: Superpowers and UI UX Pro Max.
- Check repo popularity/star signal before installing.

**Actions/evidence:**
- Verified `Superpowers` Cursor Directory plugin points to `https://github.com/obra/superpowers`.
- GitHub API evidence: upstream `obra/superpowers` has ~241k stars and ~21k forks; `complexthings/superpowers` is a 6-star fork/extension that supports OpenCode and packages `@complexthings/superpowers-agent`.
- Verified `UI UX Pro Max` official source `nextlevelbuilder/ui-ux-pro-max-skill` has ~97.8k stars and ~10.3k forks; CLI package `ui-ux-pro-max-cli` version 2.9.0 exposes `uipro init --ai opencode`.
- Determined `itgoyo/awesome-agent-skills` (~142 stars curated list) and `convertscout/awesome-ai-prompts` (~4 stars prompt/webapp repo) do not meet the same popularity/installer criteria; not installed.
- Ran `npx -y @complexthings/superpowers-agent@latest --help`; package warns Node engine requires `^20 || ^22 || ^24` while current Node is `v26.0.0`.
- Note: `superpowers-agent bootstrap --help` actually executed bootstrap instead of printing help, mutating global user config.
- Installed `@complexthings/superpowers-agent@latest` globally via npm, then ran `superpowers-agent bootstrap --no-update --force-opencode` to repoint skill symlinks from `_npx` temp cache to `/opt/homebrew/lib/node_modules/@complexthings/superpowers-agent`.
- Ran `npx -y ui-ux-pro-max-cli@latest init --ai opencode --force` in project root.
- Removed earlier local wrapper skill files for `awesome-agent-toolkit`, `awesome-goal-prompts`, and `superpowers` to avoid confusion with official/global Superpowers and unverified packs.
- Verified `superpowers-agent version` returns `9.2.1`.
- Verified `superpowers-agent find-skills` lists Superpowers skills including `brainstorming`, `writing-plans`, `systematic-debugging`, `test-driven-development`, `verification-before-completion`, etc.
- Verified project `.opencode/skills` now contains UI UX Pro Max-generated skills only: `banner-design`, `brand`, `design-system`, `design`, `slides`, `ui-styling`, `ui-ux-pro-max`.

**Files changed/live changes:**
- Repo: `.opencode/skills/` generated/updated by UI UX Pro Max installer.
- Repo: removed unverified wrapper skill files/directories for `awesome-agent-toolkit`, `awesome-goal-prompts`, `superpowers`.
- Repo: updated `00_CONTEXT/current.md`.
- Global user tooling: installed npm package `@complexthings/superpowers-agent@9.2.1` globally.
- Global user tooling: Superpowers bootstrap created/updated `~/.agents/skills/*`, `~/.agents/AGENTS.md`, `~/.claude/settings.json` (with backup), `~/.copilot/hooks/superpowers.json`, and `~/.local/bin/superpowers*` symlinks. OpenCode plugin symlink was skipped because package expected plugin file was not present.

**Blocker/risk:**
- Node v26 is outside `@complexthings/superpowers-agent` declared engine range (`^20 || ^22 || ^24`), though commands executed successfully.
- Superpowers OpenCode plugin symlink was skipped because `/opt/homebrew/lib/node_modules/@complexthings/superpowers-agent/.opencode/plugins/superpowers-agent.js` was not found; skills still sync to `~/.agents/skills` and opencode can discover external skills from `~/.agents/skills` per opencode behavior.
- Must restart opencode for new project/global skills to load.

**Next concrete step:**
- Restart opencode, then test skill loading by asking for UI work and a Superpowers workflow task; if Superpowers does not auto-load in opencode, add explicit `skills.paths` for `~/.agents/skills` in opencode config after approval.

## 2026-06-29 11:55:00 ICT — Installed claude-mem and Caveman for OpenCode; Taste blocked by missing repo

**Scope lock:**
- AI coding assistant plugin/skill installation only.
- No Fabric/SQL/Power BI/cloud mutation.
- No repo source-code mutation beyond context log; global OpenCode/user-tooling config mutated by installers.

**User instruction:**
- Install additional packs: `claude-mem`, `Taste Skill`, and `Caveman`.
- Use supplied GitHub/source links and verify before installing.

**Actions/evidence:**
- Verified `thedotmack/claude-mem` via GitHub API: ~85k stars, ~7.3k forks, Apache-2.0, README supports `npx claude-mem install --ide opencode`.
- Verified `JuliusBrussee/caveman` via GitHub API: ~77.9k stars, ~4.4k forks, MIT, README/INSTALL supports OpenCode via `npx -y github:JuliusBrussee/caveman -- --only opencode`.
- `papercliplabs/taste` returned GitHub API/web 404; user then provided correct repo `leonxlnx/taste-skill`.
- Verified `Leonxlnx/taste-skill` via GitHub API: ~53k stars, ~3.7k forks, MIT, README supports `npx skills add https://github.com/Leonxlnx/taste-skill`.
- Installed Taste Skill `design-taste-frontend` for OpenCode: `npx -y skills@latest add https://github.com/Leonxlnx/taste-skill --agent opencode --skill design-taste-frontend -y`.
- Skill copied to `.agents/skills/design-taste-frontend/SKILL.md` (project scope). Security assessment: Safe/0 alerts/Low Risk.
- Verified via `npx skills list --agent opencode --json`: skill `design-taste-frontend` registered, scope=project, agent=OpenCode.
- Read Caveman installer shim and INSTALL.md; ran dry-run first: `npx -y github:JuliusBrussee/caveman -- --dry-run --only opencode --no-mcp-shrink --non-interactive`.
- Installed Caveman for OpenCode only: `npx -y github:JuliusBrussee/caveman -- --only opencode --no-mcp-shrink --non-interactive`.
- `claude-mem install --ide opencode --runtime worker --no-auto-start` initially failed with npm peer dependency conflict (`tree-sitter` 0.21 vs 0.22.4 optional peer); retried with `npm_config_legacy_peer_deps=true` and install succeeded.
- Installed claude-mem for OpenCode with worker runtime and no auto-start: `npm_config_legacy_peer_deps=true npx -y claude-mem@latest install --ide opencode --runtime worker --no-auto-start`.
- Verified `npx claude-mem version` returns `13.8.1` and `npx claude-mem status` reports `Worker is not running`.

**Files changed/live changes:**
- Global OpenCode config: Caveman installed plugin/commands/agents/skills under `/Users/MAC/.config/opencode/` and patched `/Users/MAC/.config/opencode/opencode.json`; appended Caveman rules to `/Users/MAC/.config/opencode/AGENTS.md`.
- Global OpenCode config: claude-mem installed plugin at `/Users/MAC/.config/opencode/plugins/claude-mem.js`, registered it in `/Users/MAC/.config/opencode/opencode.json`, and created placeholder context in `/Users/MAC/.config/opencode/AGENTS.md`.
- Global Claude-mem cache/config: installer copied plugin files under `/Users/MAC/.claude/plugins/marketplaces/thedotmack`; data/settings live under `/Users/MAC/.claude-mem` when used.
- Repo: updated `00_CONTEXT/current.md` only.

**Blocker/risk:**
- `claude-mem` stores session observations/memory locally when worker is running; user should use `<private>` tags for sensitive content per README.
- `claude-mem` worker is intentionally not running after install; start manually with `npx claude-mem start` if desired.
- Restart OpenCode required for new plugins/skills to load.

**Next concrete step:**
- Restart OpenCode to load all newly installed plugins/skills: Superpowers, UI UX Pro Max, claude-mem, Caveman, Taste Skill. Optionally start claude-mem worker with `npx claude-mem start`.

## 2026-06-29 12:15:00 ICT — Installed all 5 skills for Claude Code and moved all to global scope

**Scope lock:**
- AI coding assistant skill/plugin installation only.
- No Fabric/SQL/Power BI/cloud mutation.
- Global user-tooling config mutation only; no repo source code changes.

**User instruction:**
- Install all 5 skill packs for Claude Code (not just OpenCode).
- Move everything to global scope so all projects benefit.

**Actions/evidence:**
- Superpowers: already installed for Claude Code via earlier `superpowers-agent bootstrap` which patched `~/.claude/settings.json` with SessionStart hook. Skills sync to `~/.agents/skills/` which Claude Code discovers.
- claude-mem: already installed for Claude Code via earlier `npx claude-mem install` which registered marketplace at `~/.claude/plugins/marketplaces/thedotmack/`.
- Caveman: installed for Claude Code via `npx -y github:JuliusBrussee/caveman -- --only claude --no-mcp-shrink --non-interactive`. Claude Code plugin marketplace added and plugin installed with SessionStart + UserPromptSubmit hooks.
- UI UX Pro Max: installed global for Claude Code via `npx -y ui-ux-pro-max-cli@latest init --ai claude --global --force`. Skills at `~/.claude/skills/`.
- UI UX Pro Max: re-installed global for OpenCode via `npx -y ui-ux-pro-max-cli@latest init --ai opencode --global --force`. Skills at `~/.config/opencode/skills/`.
- Taste Skill: installed global for Claude Code via `npx -y skills@latest add https://github.com/Leonxlnx/taste-skill --agent claude-code --skill design-taste-frontend -g -y`. Skill at `~/.claude/skills/design-taste-frontend/`.
- Taste Skill: re-installed global for OpenCode via `npx -y skills@latest add https://github.com/Leonxlnx/taste-skill --agent opencode --skill design-taste-frontend -g -y`. Skill at `~/.agents/skills/design-taste-frontend/`.

**Files changed/live changes:**
- `~/.claude/settings.json` — Superpowers SessionStart hook (earlier) + Caveman plugin hooks (this run).
- `~/.claude/plugins/marketplaces/thedotmack/` — claude-mem marketplace (earlier).
- `~/.claude/skills/` — UI UX Pro Max skills + Taste Skill `design-taste-frontend`.
- `~/.config/opencode/skills/` — UI UX Pro Max skills (global now, not project).
- `~/.agents/skills/design-taste-frontend/` — Taste Skill (global, shared by both OpenCode and Claude Code).
- `~/.claude/plugins/` — Caveman plugin registered.
- Repo: updated `00_CONTEXT/current.md` only.

**Blocker/risk:**
- Restart both OpenCode and Claude Code to load all new global skills/plugins.
- claude-mem worker still not running; start with `npx claude-mem start` if desired.
- Project-level copies of UI UX Pro Max (`.opencode/skills/`) and Taste Skill (`.agents/skills/`) still exist in repo; global copies now override via priority. Can clean project copies later if desired.

**Next concrete step:**
- Restart OpenCode and Claude Code. Optionally clean up project-level skill duplicates if global scope is sufficient.

## 2026-06-30 13:15:21 ICT — Ran forecast_accuracy + inventory_health table-by-table refresh

**Scope lock:**
- Live Fabric Warehouse ETL Framework refresh for exactly two marts: `forecast_accuracy` then `inventory_health`.
- No Fabric DataPipeline `pl_*` run. No mart wrapper procedures `Usp_Refresh_*` used.
- Execution used local TDS/pyodbc against Warehouse endpoint, one inner ETL Framework procedure per table.

**User instruction:**
- Run full two-mart flow from repo lineage order, table-by-table, no Fabric pipeline, no wrapper USP; ensure clean logs.

**Actions/evidence:**
- Added runner `03_operations/tools/run_mart_tables.py` for manifest-driven table-by-table execution with `nextset()` drain and stop-on-first-error.
- Dry-run order confirmed 60 table calls: `forecast_accuracy` 26, `inventory_health` 34.
- Live command completed exit code 0: `python3 03_operations/tools/run_mart_tables.py --manifest 03_operations/orchestration/forecast_accuracy/manifest.json --manifest 03_operations/orchestration/inventory_health/manifest.json --execute`.
- `forecast_accuracy`: 26/26 OK in manifest order: Silver W00→W03, Gold shared→dim→fact.
- `inventory_health`: 34/34 OK in manifest order: Silver W00→W02, Gold shared→dim→helper→helper_w21→fact.
- Last completed target: `SupplyChain_Gold_Warehouse.InventoryHealth_DW.FactInventoryHealthSnapshot`, audit complete `2026-06-30 01:13:46.686667`.
- ETL audit error rows since run start `2026-06-30 00:30:00`: 0.
- Row-count smoke:
  - `ForecastAccuracy_DW.FactForecastActual`: 163,034,308
  - `ForecastAccuracy_DW.FactForecastKpi`: 122,773,233
  - `InventoryHealth_DW.FactInventoryHealthFutureWeekEnding`: 3,849,998
  - `InventoryHealth_DW.FactInventoryHealthSnapshot`: 3,327,322

**Files changed/live changes:**
- Added `03_operations/tools/run_mart_tables.py`.
- Updated `00_CONTEXT/current.md`.
- Live Warehouse table refresh completed through ETL Framework inner procedures: `usp_RefreshCuratedTableFromView` and `usp_IncrementalTableLoad` where manifest load type was incremental.

**Blocker/risk:**
- `run_mart_tables.py` is newly added operational tooling; keep dry-run-first + explicit approval for future live use.
- `run_refresh.py` wrapper execution path remains unsafe for long wrapper SPs because it does not drain result sets before closing connection.

**Next concrete step:**
- If desired, validate semantic/report layer freshness after the two mart facts refreshed; otherwise persist runner usage rule into runbook/ADR after approval.

## 2026-06-30 13:15:21 ICT — Persisted Manifest Table Runner as default approved mart refresh method

**Scope lock:**
- Persistence/documentation only after successful two-mart refresh.
- No Fabric/SQL/Power BI live mutation during persistence.

**User instruction:**
- Save the refresh method to context, claude-mem, and operations folder so future "run" requests use this method by default.

**Actions/evidence:**
- Confirmed `claude-mem` worker is running: PID `39182`, port `37701`, version `13.9.1`.
- Defined method name: **Manifest Table Runner** / manifest-driven table-by-table ETL Framework refresh.
- Persisted operating runbook: `03_operations/operating_registry/manifest_table_runner.md`.
- Updated `03_operations/README.md` to make Manifest Table Runner the default approved ad-hoc mart refresh method.
- Added file-based memory: `memory/manifest_table_runner_default.md`.
- Updated `memory/MEMORY.md` index.

**Files changed/live changes:**
- Added `03_operations/operating_registry/manifest_table_runner.md`.
- Updated `03_operations/README.md`.
- Updated `/Users/MAC/.claude/projects/-Users-MAC-Documents-20260413-Fabric-Refactor-Architect/memory/MEMORY.md`.
- Added `/Users/MAC/.claude/projects/-Users-MAC-Documents-20260413-Fabric-Refactor-Architect/memory/manifest_table_runner_default.md`.
- Updated `00_CONTEXT/current.md`.

**Blocker/risk:**
- Future live refresh still requires dry-run first and same-conversation approval before `--execute`.
- Do not use Fabric DataPipeline `pl_*` or mart wrapper `Usp_Refresh_*` by default unless explicitly requested.

**Next concrete step:**
- For future approved mart refresh, run `python3 03_operations/tools/run_mart_tables.py --manifest <mart manifest> [--manifest ...]` dry-run first, then `--execute` after approval.


## 2026-07-01 12:42:24 ICT — Split Silver wave SPs + Staging lineage fix deployed

- Scope lock: `Enterprise SupplyChain-Dev`; Processing/Gold/ETL Framework only.
- User instruction: execute approved 10-SP Option A, fix lineage to match live Fabric, keep overwrite-only until incremental keys verified.
- Actions/evidence:
  - Updated lineage scanner `05_tools/06_lineage_portal/scanner/builder.py` so `Staging_Wrk.v_*` remains visible.
  - Regenerated live lineage snapshot via `FABRIC_USE_AZ_CLI=1 PYTHONPATH=. python3 -m scanner.cli --out site/public/lineage_snapshot.json`; mirrored to `site/out` and `site/dist`.
  - Live snapshot evidence: generated_at_utc `2026-07-01T03:44:20Z`, `workspace_item_count=35`, `table_dictionary_rows=66`, Staging nodes/edges present.
  - Created 8 new wave/shared SP SQL files; all new wave SP calls use `usp_RefreshCuratedTableFromView`, no `usp_IncrementalTableLoad`.
  - Deployed 8 Processing SPs live and dropped old Silver wrappers: `Usp_Refresh_ForecastAccuracy_Silver`, `Usp_Refresh_InventoryHealth_Silver`.
  - Verified Processing live procs: 2 shared + 6 Silver wave procs. Verified Gold procs still present: `Usp_Refresh_ForecastAccuracy_Gold`, `Usp_Refresh_InventoryHealth_Gold`.
  - Updated live Fabric `pl_backup_full_refresh` definition from 4 activities to 10 activities; MCP readback confirms 10 activities.
  - Triggered live pipeline run `ee842ea2-445b-4317-81ab-6ad54dbef870`; initial status `NotStarted` at `2026-07-01T05:41:46Z`.
- Files changed/live changed:
  - Repo: manifests, SP SQLs, lineage scanner/snapshots, backup pipeline JSON, docs.
  - Live: Processing dbo SP surface updated; `pl_backup_full_refresh` definition updated; pipeline run triggered.
- Blocker/risk: pipeline run still in progress/not-started at context time; final activity status and row-count smoke pending.
- Next concrete step: check run `ee842ea2-445b-4317-81ab-6ad54dbef870`, then verify AuditLog/TableDictionary/fact row counts and report final result.


## 2026-07-06 10:36:08 ICT — Read-only Fabric/repo/lineage refresh-order audit

- Scope lock: read-only audit for Enterprise SupplyChain-Dev (`c8d9fc83-18b6-4e1d-8264-0b49eed36fe0`); no Fabric/SQL mutations and no repo business-object changes.
- User instruction: scan live Fabric, repo lineage, and refresh order across all marts/layers for clear synchronization.
- Actions/evidence: used Fabric MCP/REST to scan workspace and pipeline definitions/history; used pyodbc read-only against `SupplyChain_Processing_Warehouse`, `SupplyChain_Gold_Warehouse`, and `ETL_Framework`; compared `03_operations/orchestration/*`, `02_marts/*/05_catalog/run_order.json`, SQL wrapper bodies, live proc definitions, TableDictionary, and lineage snapshot.
- Files/live changed: appended this context only; live objects were read-only. Temporary scripts under `/tmp/fabric_readonly_audit.py`, `/tmp/fabric_proc_defs.py`, `/tmp/fabric_recent_auditlog.py`.
- Findings/risk: live workspace only has backup pipelines `pl_backup_full_refresh` and `pl_backup_per_table`; checked-in `CLAUDE.md` still lists old `pl_sc_*` IDs. Live full refresh pipeline uses `Usp_Refresh_InventoryHealth_Silver_W00`, but main/manifest says Inventory W01/W02/W03 only; repo search found no W00 SQL file. `pl_backup_full_refresh` also omits `Usp_Refresh_InventoryHealth_Silver_W03`, so live 10-step description is stale/misleading. Lineage snapshot does not include `DQForecastAccuracy`.
- Next concrete step: present ranked reconciliation plan; if approved, patch repo docs/manifests/lineage artifacts to reflect live pipeline/proc reality and decide whether to update live pipeline definition separately.


## 2026-07-06 11:40:38 ICT — Repo/lineage sync to canonical 10-step refresh order

- Scope lock: repo + lineage patch only; live Fabric pipeline mutation deferred to explicit Aric approval per LIVE_SYNC_RUNBOOK.
- User instruction: chuẩn hoá thứ tự refresh về đúng 10 bước và đồng bộ repo/lineage/live.
- Actions/evidence:
  - Branched to `sync-refresh-order-lineage` from `main`.
  - Registered `ForecastAccuracy_DW.DQForecastAccuracy` and `ForecastAccuracy_DW_Wrk.v_DQForecastAccuracy` in `02_marts/forecast_accuracy/05_catalog/{assets,run_order,lineage_edges}.json` as gold_dq (wave 40) with a `direct_sql_insert_materializes_final_table` edge from `_Wrk.v_DQForecastAccuracy`.
  - Added `gold_dq` wave to `05_tools/06_lineage_portal/scanner/mart_catalog.py` WAVE_MAP.
  - Tightened `dependency_parser.KNOWN_SCHEMAS` so `AliasName.Column` refs (e.g., `cal.Date`, `oo.QtyOpenOrder`) no longer pollute the lineage graph.
  - Updated `test_forecast_dq_contract.py` to assert DQForecastAccuracy IS in catalog + has direct-insert edge (previous assertion was `assertNotIn`).
  - Regenerated `05_tools/06_lineage_portal/site/public/lineage_snapshot.json` via live Fabric REST + pyodbc scan; DQ node now has 31 upstream edges, layer=Gold, mart=forecast_accuracy, wave=40.
  - CLAUDE.md Manual Refresh Rule now enumerates the exact 10 wrappers; Live Pipeline IDs table replaced legacy `pl_sc_*` with live `pl_backup_full_refresh` (`41948342-d7e7-4166-8638-9af0633e6a49`) and `pl_backup_per_table` (`ba5fb8be-9d35-46dc-baf4-13c0c6035bab`).
  - `03_operations/orchestration/main/README.md` and `forecast_accuracy/README.md` updated to reference `pl_backup_full_refresh` instead of legacy `pl_sc_master`/`pl_sc_mart`.
  - Generated Fabric REST payload `03_operations/orchestration/backup_pipeline/pl_backup_full_refresh.fabric_payload.json` from repo canonical JSON.
  - Wrote `03_operations/orchestration/backup_pipeline/LIVE_SYNC_RUNBOOK.md` documenting exact `updateDefinition` + optional W00 cleanup steps; awaiting approval before execution.
- Tests: `python3 -m unittest` for `test_dependency_parser.py`, `test_forecast_dq_contract.py`, `test_builder.py`, `test_mart_catalog.py`, `test_classifier.py`, `test_wave_builder.py` — 13/13 OK.
- Live changes: none. Live `pl_backup_full_refresh` still has `Usp_Refresh_InventoryHealth_Silver_W00` and no `_W03`; live SP `Usp_Refresh_InventoryHealth_Silver_W00` remains until approval.
- Blocker/risk: current live pipeline still skips `InventoryHealth_Silver_W03`, so `AFIStatusSnapshotWeekly/AwdHelper/LastInvoiceWeekly/Cogs52WWeekly` continue to depend on manual refresh for freshness before Gold.
- Next concrete step: obtain Aric approval to POST the new Fabric pipeline definition (Step A of LIVE_SYNC_RUNBOOK), then optionally drop live `Usp_Refresh_InventoryHealth_Silver_W00` (Step B).


## 2026-07-06 11:58:59 ICT — Live Fabric mutation: pl_backup_full_refresh definition synced to canonical 10-step

- Scope lock: LIVE MUTATION — Fabric pipeline updateDefinition on `41948342-d7e7-4166-8638-9af0633e6a49`.
- User instruction: "fix fabric live" (Step A of LIVE_SYNC_RUNBOOK).
- Actions/evidence:
  - Verified no in-progress job before mutation (latest run 2026-07-03 Failed, no active pipeline).
  - Base64-encoded `03_operations/orchestration/backup_pipeline/pl_backup_full_refresh.fabric_payload.json` (11,296 bytes).
  - POST `/workspaces/c8d9fc83-18b6-4e1d-8264-0b49eed36fe0/items/41948342-d7e7-4166-8638-9af0633e6a49/updateDefinition` → HTTP 200 sync, RequestId `d6138633-e4be-4aac-9f2c-ac8b718bc239`.
  - Re-fetched live definition via Fabric REST getDefinition and confirmed 10 activities in exact canonical order.
- Live changes:
  - `pl_backup_full_refresh` definition rewritten. Removed `03_Inventory_Silver_W00` calling `Usp_Refresh_InventoryHealth_Silver_W00`. Added `09_Inventory_Silver_W03` calling `Usp_Refresh_InventoryHealth_Silver_W03`. Renumbered/renamed activities 03–10 to Forecast-first ordering (03/04/05 Forecast W01–W03, 06 Forecast Gold, 07/08/09 Inventory W01–W03, 10 Inventory Gold).
- Verification: getDefinition shows exact 10 activities matching repo canonical:
  01_Shared_ReferenceMaster → 02_Shared_Staging → 03_Forecast_Silver_W01 → 04_Forecast_Silver_W02 → 05_Forecast_Silver_W03 → 06_Forecast_Gold → 07_Inventory_Silver_W01 → 08_Inventory_Silver_W02 → 09_Inventory_Silver_W03 → 10_Inventory_Gold.
- Blocker/risk: Live SP `Usp_Refresh_InventoryHealth_Silver_W00` still exists in `SupplyChain_Processing_Warehouse` (Step B optional cleanup). It is now orphaned — no longer referenced by any live pipeline.
- Next concrete step: (optional) Step B `DROP PROCEDURE dbo.Usp_Refresh_InventoryHealth_Silver_W00` if Aric confirms nothing else references it. Otherwise, trigger a smoke run of `pl_backup_full_refresh` to validate the new W03 step end-to-end.


## 2026-07-06 12:18:55 ICT — Step B executed: dropped orphan Usp_Refresh_InventoryHealth_Silver_W00 + lineage resynced

- Scope lock: LIVE MUTATION — SP drop in SupplyChain_Processing_Warehouse, then lineage snapshot regeneration.
- User instruction: "bạn tự xóa đi cho tôi, à lineage đã đồng bộ chưa"
- Root-cause evidence gathered before DROP:
  - W00 body was byte-identical to W01 (both refresh InventorySnapshotWeekly + AtpWeekEnding via usp_RefreshCuratedTableFromView).
  - sys.sql_modules: 0 objects referenced W00 (verified by LIKE '%Usp_Refresh_InventoryHealth_Silver_W00%').
  - Repo generate_wave_sps.py has no spec for W00, only W01/W02/W03.
  - Timeline: W00 was created 2026-07-01 05:36 (early wave design), W01 created 2026-07-01 08:48 (post-refactor with same body). W00 became orphaned when live pipeline was updated to call W01.
  - AuditLog confirms InventorySnapshotWeekly + AtpWeekEnding continued to refresh (2026-07-02 22:06, 2026-07-03 02:05, 2026-07-03 02:54) — verified W01 is functionally taking over.
- Live changes:
  - DROP PROCEDURE [SupplyChain_Processing_Warehouse].[dbo].[Usp_Refresh_InventoryHealth_Silver_W00]. Pre-check found 1 row, post-check 0.
- Lineage sync:
  - Regenerated `05_tools/06_lineage_portal/site/public/lineage_snapshot.json` via live Fabric REST + pyodbc.
  - Snapshot generated_at_utc = 2026-07-06T05:17:54Z.
  - 97 nodes, 163 edges. W00 refs: 0. W03 refs: 0 (W03 is proc-level, not object-level, so absence is expected — W03 tables like AFIStatusSnapshotWeekly appear individually with wave=3).
  - DQForecastAccuracy node present with 31 inbound edges, layer=Gold, mart=forecast_accuracy, wave=40.
  - Portal deploy: `.github/workflows/lineage-portal.yml` cron `17 */2 * * *` (every 2h) auto-rebuilds live from Fabric secrets + deploys to GitHub Pages. Repo commit of the new snapshot is not required for portal to pick up the change; scheduled workflow will regenerate.
- Verification:
  - Live Fabric pipeline `pl_backup_full_refresh` definition: 10 activities canonical (no W00, includes W03).
  - Live SQL: no orphan `Usp_Refresh_InventoryHealth_Silver_W00` procedure.
  - Lineage snapshot: no W00 leakage, DQ node fully connected.
- Next concrete step: optional smoke run of `pl_backup_full_refresh` to end-to-end verify the new W03 step; and commit branch `sync-refresh-order-lineage` if repo state should be preserved in git.

## 2026-07-06 15:06:36 ICT — Root cause check for latest single DQ fail and DemandForecastSnapshot status

**Scope lock:**
- Read-only live SQL investigation after current full forecast refresh emitted DQ batch.
- No live mutation.

**User instruction:**
- Determine whether the only current fail is ETL-code-caused or source-caused, and clarify the `DemandForecastSnapshotDaily` DQ situation.

**Actions/evidence:**
- Re-read `CLAUDE.md` and `00_CONTEXT/current.md`.
- Confirmed latest DQ batch `20B600BD-2F6B-4354-85BC-6A93131B3911` at `2026-07-06 14:34:01 ICT` has one fail only: `DQ_Bronze_Grain_InvoiceHeader`.
- Repo rule evidence: `DQ_Bronze_Grain_InvoiceHeader` checks `Enterprise_Lakehouse.SalesHistory_AFI_Enh.InvoiceHeader` grouped by `(InvoiceNumber, OrderNumber)`.
- Live source check: `InvoiceHeader` has `82` duplicate `(InvoiceNumber, OrderNumber)` groups, `164` rows in those groups, each duplicated exactly twice.
- Full ETL join-key check: the same `82` groups are also duplicated by `(InvoiceNumber, OrderNumber, InvoiceDate, OrderDate)`; this is source duplicate at the join key, not only a too-narrow DQ grain.
- Silver impact check: `SupplyChain_Processing_Warehouse.SalesHistory_Enh.InvoiceDetailLineLevel` has `0` duplicate detail-grain keys by `(InvoiceID, OrderID, ItemSKU, ItemSequenceNum)`.
- Bad-header related rows: `82` affected invoice/order headers, `164` duplicate header rows, `271` raw detail rows under those headers, and `271` Silver rows under those headers.
- DemandForecast latest DQ check: all demand/forecast-related rules in the latest batch are `PASS`, including `DQ_Bronze_Grain_DemandForecastSnapshotDaily` and `DQ_B2S2_Forecast_Qty`.
- DemandForecast history: both `DQ_Bronze_Grain_DemandForecastSnapshotDaily` and `DQ_B2S2_Forecast_Qty` failed in all `9` visible runs on `2026-07-03`, then passed in the `2026-07-06 14:34 ICT` batch.
- Raw DemandForecast source remains dirty: `Enterprise_Lakehouse.SupplyChain_Enh.DemandForecastSnapshotDaily` has `6,275,609` duplicate canonical 7-key groups and `22,268,517` rows in duplicate groups (`min=2`, `max=8` rows/key).

**Conclusion:**
- Latest single fail `DQ_Bronze_Grain_InvoiceHeader` is source/bronze data quality failure, not ETL-generated duplicate. Current ETL does not show downstream Silver detail grain duplication from it.
- DemandForecast raw source is still duplicated, but current live DQ passes because the canonical staging/dedup contract now handles it and B2S quantity reconciliation passes.

**Next concrete step:**
- If needed, export the 82 duplicate `InvoiceHeader` keys as source remediation evidence; do not patch ETL unless business decides to dedupe `InvoiceHeader` in a canonical source wrapper.

## 2026-07-06 15:30:25 ICT — Corrected DemandForecast bronze DQ rule to raw source and reran DQ snapshot

**Scope lock:**
- Repo DQ view patch + live Gold Warehouse view deployment + direct DQ history insert.
- No mart/fact rerun.

**User instruction:**
- `DQ_Bronze_Grain_DemandForecastSnapshotDaily` was wrongly checking the deduped staging view; correct it to raw source `Enterprise_Lakehouse` and rerun DQ. Expected at least two fails if correct.

**Actions/evidence:**
- Patched `02_marts/forecast_accuracy/03_gold/ForecastAccuracy_DW_Wrk/v_DQForecastAccuracy.sql`.
- Patched mirror `03_operations/deployment/sqlproj/SupplyChain_Gold_Warehouse/ForecastAccuracy_DW_Wrk/Views/v_DQForecastAccuracy.sql`.
- Changed `DQ_Bronze_Grain_DemandForecastSnapshotDaily` to check raw `Enterprise_Lakehouse.SupplyChain_Enh.DemandForecastSnapshotDaily` grouped by canonical 7-key:
  - `dfcItem`
  - `dfcWarehouse`
  - `dfcFiscalMonth`
  - `dfcSnapshot`
  - `DfcCustomerGroups`
  - `dfcFCSTTypeCode`
  - `dfcMgmtCode`
- Deployed live `CREATE OR ALTER VIEW [ForecastAccuracy_DW_Wrk].[v_DQForecastAccuracy]` to `SupplyChain_Gold_Warehouse`.
- Inserted a new DQ snapshot with the same terminal insert shape used by `dbo.Usp_Refresh_ForecastAccuracy_Gold`.
- Insert duration was `680.0s` because the rule now scans raw DemandForecast source plus the full DQ suite.

**Latest DQ result after correction:**
- `DQRunId = 2729EFD2-BFCA-45F8-97E5-31BAD1A1CB95`
- `DQRunAtICT = 2026-07-06 15:17:33.506511`
- Summary: `29 PASS / 3 FAIL / 32 total rules`
- Fails:
  - `DQ_Bronze_Grain_DemandForecastSnapshotDaily`
  - `DQ_Bronze_Grain_InvoiceHeader`
  - `DQ_S2S1_Invoice_Qty`

**Important nuance:**
- The two expected raw-source fails are now present:
  - `DemandForecastSnapshotDaily` raw source duplicate
  - `InvoiceHeader` raw source duplicate
- The third fail is a timing/desync issue, not caused by the DemandForecast rule change:
  - `DQ_S2S1_Invoice_Qty` diff: `S1 ActualDemandMonthly Invoice = 94,029,283`; `S2 InvoiceDetailLineLevel = 94,082,892`; diff = `53,609`.
  - UpdateLog shows `InvoiceDetailLineLevel` refreshed later than `ActualDemandMonthly`:
    - `ActualDemandMonthly = 2026-07-06 02:25:23.120000`
    - `InvoiceDetailLineLevel = 2026-07-06 03:03:32.166667`
  - This matches full pipeline behavior: Inventory later refreshes shared `SalesHistory_Enh.InvoiceDetailLineLevel` after the Forecast DQ snapshot at `14:34 ICT`, causing cross-layer mismatch if DQ is run again after Inventory.
- Full pipeline run `d276499a-e2fe-4a9d-b28c-82cf170c9509` completed at `2026-07-06T08:24:38Z` (`15:24:38 ICT`).

**Next concrete step:**
- To get a clean post-correction forecast DQ with only durable raw-source failures, rerun the forecast layer that rebuilds `ActualDemandMonthly` from the current `InvoiceDetailLineLevel` before inserting DQ again, e.g. Forecast Silver W02 followed by Forecast Gold/DQ.

## 2026-07-06 15:47:44 ICT — Targeted `ActualDemandMonthly` refresh and cancelled follow-up DQ insert

**Scope lock:**
- Live targeted table refresh + read-only verification + cancelled DQ insert.
- No DQ history overwrite.

**User instruction:**
- Fix only the desynced table/rule, rerun just enough DQ logic to prove pass, then stop after user decided tomorrow's full run is sufficient.

**Actions/evidence:**
- Refreshed only `SupplyChain_Processing_Warehouse.SalesHistory_Enh.ActualDemandMonthly` via:
  - `ETL_Framework.DW_Developer.usp_RefreshCuratedTableFromView('SupplyChain_Processing_Warehouse', 'SalesHistory_Enh', 'ActualDemandMonthly')`
- Refresh completed successfully in `32.5s`.
- Targeted `DQ_S2S1_Invoice_Qty` SQL check after refresh:
  - `S1 ActualDemandMonthly Invoice = 94,082,892`
  - `S2 InvoiceDetailLineLevel = 94,082,892`
  - `diff = 0`
  - `dq_result = PASS`
- `TableDictionary_UpdateLog` confirms:
  - `ActualDemandMonthly = 2026-07-06 03:38:19.990000`
  - `InvoiceDetailLineLevel = 2026-07-06 03:03:32.166667`
- Started appending a full DQ snapshot so latest history would reflect the pass, but user said stop because tomorrow's full run is acceptable.
- Interrupted the DQ insert client, checked `sys.dm_exec_requests`, and confirmed no lingering `ForecastAccuracy_DW.DQForecastAccuracy` insert session remained.
- Latest DQ history remains unchanged:
  - `DQRunId = 2729EFD2-BFCA-45F8-97E5-31BAD1A1CB95`
  - `DQRunAtICT = 2026-07-06 15:17:33.506511`
  - `29 PASS / 3 FAIL`

**Conclusion:**
- The desync root cause has been corrected in the live Silver table state; targeted rule now passes.
- DQ history was not overwritten or corrected retroactively; latest stored DQ batch still shows the old 3-fail snapshot until the next full DQ run.

**Next concrete step:**
- Tomorrow's normal full mart run should emit a fresh DQ snapshot. Expected durable fails after correction remain the two raw-source duplicate rules unless source data changes:
  - `DQ_Bronze_Grain_DemandForecastSnapshotDaily`
  - `DQ_Bronze_Grain_InvoiceHeader`

## 2026-07-06 16:00 ICT — Inventory Health BRZ→Silver DQ design analysis

**Scope lock:**
- Read-only repo analysis only.
- No live Fabric/SQL mutation.

**User instruction:**
- Analyze how to apply the DQ view/template approach to Inventory Health for BRZ→Silver checks only.

**Actions/evidence:**
- Read Inventory Health run order, lineage edges, `04_dq` contracts, Bronze DQ generated artifacts, and W01 Silver views.
- Confirmed Inventory existing generated Bronze DQ artifacts already cover source-level rules:
  - `table_exists`
  - `schema_snapshot`
  - `freshness_observed`
  - `latest_partition_null_blank_key`
  - `latest_partition_grain_duplicate`
  - `full_row_duplicate`
  - selected `all_history_grain_duplicate`
- Confirmed Silver W01 targets are:
  - `ReferenceMaster_Enh.*`
  - `InventoryHistory_Enh.InventorySnapshotWeekly`
  - `InventoryHistory_Enh.AtpWeekEnding`
- Noted many Inventory raw sources intentionally contain duplicates and are deduped/latest-effective in Silver views, so DQ must separate raw-source quality from canonical Silver output quality.

**Next concrete step:**
- If implementing, create an Inventory mart DQ view/table that emits BRZ source checks, BRZ→Silver reconciliation checks, and Silver grain checks, but does not include Gold checks.

## 2026-07-06 16:33:25 ICT — Inventory Health W01 BRZ→Silver DQ draft and live SELECT-only validation

**Scope lock:**
- Repo draft SQL template + read-only live warehouse validation.
- No live DQ view/table creation and no physical DQ insert.

**User instruction:**
- Build the three DQ families for the user's Inventory W01 BRZ→Silver scope following Forecast DQ view style, but avoid Forecast mistakes and do not create live objects yet.

**Actions/evidence:**
- Added draft template:
  - `02_marts/inventory_health/04_dq/drafts/v_DQInventoryHealth_BrzToSilver_W01.template.sql`
- Template emits 21 rules across 7 W01 targets:
  - `DQ_Bronze_*`: raw `Enterprise_Lakehouse` source quality only.
  - `DQ_B2S_*`: `_Wrk.v_*` expected Silver output compared to physical Silver table.
  - `DQ_Silver_Grain_*`: final Silver table grain/key contract.
- Ran equivalent SELECT-only DQ logic live against `SupplyChain_Processing_Warehouse`; no insert.
- SELECT-only run metadata:
  - `DQRunId = 2F204319-8E0A-49D7-82F5-ACC80EB7D5C9`
  - `DQRunAtUTC = 2026-07-06 09:19:43.196007`

**Live validation result:**
- Summary: `18 PASS / 3 FAIL / 21 total`.
- All `DQ_B2S_*` rules passed.
- All `DQ_Silver_Grain_*` rules passed.
- Failing rules are raw-source-only checks:
  - `DQ_Bronze_Grain_ATPWeekEnding`
  - `DQ_Bronze_Grain_DemandInventorySnapshotDaily`
  - `DQ_Bronze_Grain_Warehouse`

**Fail diagnostics:**
- `WarehouseMaster`: 1 raw blank/null `Warehouse` row; no duplicate warehouse groups; Silver filters it out (`raw_rows = 54`, `silver_rows = 53`).
- `ATPWeekEnding`: 18 raw duplicate source-grain groups overall; only 1 relevant duplicate group before Silver dedupe; final Silver output passes B2S and Silver grain.
- `DemandInventorySnapshotDaily`: raw source is heavily duplicated (`132,240,024` duplicate source-grain groups overall); Silver W01 latest/weekly dedupe produces valid output and passes B2S/Silver grain.

**Guardrail against Forecast DQ mistakes:**
- Raw Bronze rules explicitly say they read raw source and may fail before Silver dedupe.
- B2S rules do not compare raw source directly to persisted Silver; they compare `_Wrk.v_*` expected output to physical final Silver.
- The draft is not deployed live and should be reviewed before promotion to `InventoryHealth_DW_Wrk.v_DQInventoryHealth` or a physical DQ history table.

**Next concrete step:**
- If approved later, promote the draft into the Inventory DQ view/table pattern and wire insertion after W01 Silver completion, or keep it as a reviewable SELECT-only validation script.

## 2026-07-07 10:49:44 ICT — Reworked Inventory W01 `DQ_B2S_*` contract to true Bronze-to-Silver checks

**Scope lock:**
- Repo SQL template edit + read-only Fabric compile validation.
- No live DQ view/table creation and no physical DQ insert.

**User instruction:**
- Apply the corrected three-rule-family design to all tables in the user's Inventory W01 scope and update the full SQL file.

**Actions/evidence:**
- Replaced `02_marts/inventory_health/04_dq/drafts/v_DQInventoryHealth_BrzToSilver_W01.template.sql`.
- Removed `_Wrk` usage from `DQ_B2S_*`.
- New `DQ_B2S_*` pattern:
  - Build expected output from raw `Enterprise_Lakehouse` source.
  - Apply the same business filters/dedupe/latest-snapshot logic needed for Silver W01.
  - Compare expected output to physical Silver tables.
- Kept 21 total rules across 7 W01 targets:
  - `DQ_Bronze_*`
  - `DQ_B2S_*`
  - `DQ_Silver_Grain_*`
- Tightened Bronze rules for obvious null/blank key cases:
  - `Calendar`
  - `DemandInventorySnapshotDaily`
  - `ATPWeekEnding`

**Verification:**
- Static check: no `_Wrk` references remain in the template.
- Static check: `21` DQ rules remain.
- Fabric SQL endpoint compile/read-only check:
  - Rewrote final SELECT as `SELECT TOP (0)` in-memory only.
  - Executed against `SupplyChain_Processing_Warehouse`.
  - Result: `0` rows returned in `3.58s`; syntax/binding passed.

**Risk / note:**
- Full live DQ SELECT was not rerun after this edit because the new true-B2S expected CTEs scan large raw source tables and may be heavy. Current validation proves compile/binding, not latest pass/fail distribution.

**Next concrete step:**
- If pass/fail output is needed for the revised true-B2S template, run a SELECT-only full DQ check during an acceptable Fabric window and compare against the prior `18 PASS / 3 FAIL / 21` baseline.

## 2026-07-07 10:53:50 ICT — Added Vietnamese explanatory comments to Inventory W01 DQ template

**Scope lock:**
- Repo SQL comment/documentation edit + read-only Fabric compile validation.
- No live DQ view/table creation and no physical DQ insert.

**User instruction:**
- Add detailed Vietnamese explanation comments inside the SQL file, grouped by the three DQ families.

**Actions/evidence:**
- Updated `02_marts/inventory_health/04_dq/drafts/v_DQInventoryHealth_BrzToSilver_W01.template.sql`.
- Added Vietnamese comments for:
  - how to read the file;
  - expected-output CTEs used by true `DQ_B2S_*`;
  - B2S metric CTEs;
  - `DQ_Bronze_*` section;
  - `DQ_B2S_*` section;
  - `DQ_Silver_Grain_*` section;
  - final SELECT/run metadata output.
- Logic was not intentionally changed; comments only.

**Verification:**
- Static check: `21` DQ rules remain.
- Static check: no `ReferenceMaster_Enh_Wrk` or `InventoryHistory_Enh_Wrk` references remain.
- Fabric SQL endpoint compile/read-only check:
  - Rewrote final SELECT as `SELECT TOP (0)` in-memory only.
  - Executed against `SupplyChain_Processing_Warehouse`.
  - Result: `0` rows returned in `3.09s`; syntax/binding passed.

**Next concrete step:**
- If the annotated template is approved, next step is either run full SELECT-only DQ output in an acceptable Fabric window or promote to a reviewed Inventory DQ view/table pattern later.

## 2026-07-07 13:16:40 ICT — SELECT-only run of revised Inventory W01 true-B2S DQ template

**Scope lock:**
- Read-only Fabric SQL execution of draft template.
- No live DQ view/table creation and no physical DQ insert.

**User instruction:**
- Summarize the tables/rule types in the user's Bronze-to-Silver W01 scope and run the revised three-rule DQ template to get actual pass/fail.

**Actions/evidence:**
- Executed full SELECT-only SQL from:
  - `02_marts/inventory_health/04_dq/drafts/v_DQInventoryHealth_BrzToSilver_W01.template.sql`
- Runtime:
  - `174.25s`
  - `DQRunId = 23260C09-40F6-4436-B49B-EA61468AF2FB`
  - `DQRunAtUTC = 2026-07-07 06:10:31.197882`
  - `DQRunAtICT = 2026-07-07 13:10:31.197882`

**Result:**
- Summary: `18 PASS / 3 FAIL / 21 total`.
- All revised true `DQ_B2S_*` rules passed.
- All `DQ_Silver_Grain_*` rules passed.
- Failing rules remain raw-source-only:
  - `DQ_Bronze_Grain_Warehouse`
  - `DQ_Bronze_Grain_DemandInventorySnapshotDaily`
  - `DQ_Bronze_Grain_ATPWeekEnding`

**Fail diagnostics:**
- `WarehouseMaster`: `blank_or_null_key_rows = 1`, `duplicate_groups = 0`.
- `DemandInventorySnapshotDaily`: `blank_or_null_key_rows = 0`, `duplicate_groups = 135,977,040`.
- `ATPWeekEnding`: `blank_or_null_key_rows = 0`, `duplicate_groups = 18`.

**Conclusion:**
- Revised DQ contract validates that Inventory W01 Silver final output currently matches raw Bronze-derived expected output and final Silver grain is clean.
- Current failures are raw Bronze source quality failures only, not Silver transform/load/final grain failures.

**Next concrete step:**
- If this template is approved, promote it to the reviewed Inventory DQ view/table implementation path; otherwise keep it as a SELECT-only validation artifact.

## 2026-07-07 13:56:43 ICT — Inventory W01 DQ scope correction: live ReferenceMaster has 11 tables, draft DQ covers only 5

**Scope lock:**
- Read-only repo + live Fabric SQL catalog/definition audit.
- No live mutation and no DQ insert.

**User instruction:**
- User questioned why Inventory Bronze-to-Silver DQ has so few Bronze/source tables compared with lineage screenshot.

**Actions/evidence:**
- Attempted to read screenshot from `CoreSpotlight/PasteboardHistory`; blocked by macOS permission.
- Queried repo W01 files:
  - local `02_marts/inventory_health/02_silver/ReferenceMaster_Enh_Wrk` currently has only 5 files.
- Queried live Fabric catalog in `SupplyChain_Processing_Warehouse`:
  - `ReferenceMaster_Enh` physical tables = 11.
  - `ReferenceMaster_Enh_Wrk` views = 11.
- Live ReferenceMaster W01 physical tables:
  - `Calendar`
  - `CustomerAccount`
  - `CustomerAccountGroup`
  - `CustomerGrouping`
  - `CustomerShippingLocation`
  - `ForecastCycle`
  - `ForecastHorizon`
  - `ItemMaster`
  - `OrderType`
  - `Vendor`
  - `Warehouse`
- Live W01 inventory tables still:
  - `InventoryHistory_Enh.InventorySnapshotWeekly`
  - `InventoryHistory_Enh.AtpWeekEnding`

**Finding:**
- The current draft DQ template covers 7 targets:
  - 5 ReferenceMaster tables: `Calendar`, `Warehouse`, `Vendor`, `CustomerAccountGroup`, `ItemMaster`
  - 2 InventoryHistory tables: `InventorySnapshotWeekly`, `AtpWeekEnding`
- If the intended scope is full live Inventory Silver W01, the DQ draft is incomplete and missing 6 ReferenceMaster tables:
  - `CustomerAccount`
  - `CustomerGrouping`
  - `CustomerShippingLocation`
  - `ForecastCycle`
  - `ForecastHorizon`
  - `OrderType`

**Source refs for missing tables:**
- `CustomerAccount` <- `Enterprise_Lakehouse.Customers.AccountMaster`
- `CustomerGrouping` <- `Enterprise_Lakehouse.Wholesale_ProductSourcing_AFI.CustomerGrouping`
- `CustomerShippingLocation` <- `Enterprise_Lakehouse.Customers.ShippingLocations`
- `ForecastCycle` <- `ProcessingSeed.ForecastCycle`
- `ForecastHorizon` <- `ProcessingSeed.ForecastHorizon`
- `OrderType` <- `Enterprise_Lakehouse.Wholesale_Codis_AFI.AAORDTYP`

**Conclusion:**
- Lineage is not the root issue; it correctly shows more live ReferenceMaster dependencies.
- The draft DQ scope was under-selected relative to full live W01 ReferenceMaster scope.

**Next concrete step:**
- Expand the Inventory W01 DQ template from 21 rules to 39 rules if full W01 scope is required: 13 W01 targets x 3 rule families.

## 2026-07-07 14:08:00 ICT — Source-of-truth decision for Inventory DQ scope

**Scope lock:**
- No live mutation.
- Decision/context update only.

**User instruction:**
- User clarified that current live Fabric is the most accurate source of truth.

**Decision:**
- For Inventory DQ scope and lineage validation, use live Fabric runtime/catalog as primary source of truth.
- Treat repo files and lineage portal snapshots as derived artifacts that may be stale until proven synced with live Fabric.
- If repo/lineage conflict with live Fabric, mark repo/lineage as stale and derive DQ coverage from live objects/wrapper procedures/TableDictionary.

**Next concrete step:**
- Live-check current `SupplyChain_Processing_Warehouse` wrapper procedures and `ETL_Framework.DW_Developer.TableDictionary` before expanding the Inventory Bronze-to-Silver DQ template.

## 2026-07-07 14:22:00 ICT — Inventory super scan: live Fabric vs lineage vs repo

**Scope lock:**
- Read-only live Fabric REST + SQL catalog scan.
- No live mutation and no DQ insert.

**User instruction:**
- Run a "super scan" and evaluate which source is most accurate among repo, lineage, and live Fabric.

**Actions/evidence:**
- Read live pipeline `pl_backup_full_refresh` definition via Fabric REST.
- Read live `SupplyChain_Processing_Warehouse` wrapper procedure definitions:
  - `dbo.Usp_Refresh_Shared_ReferenceMaster`
  - `dbo.Usp_Refresh_InventoryHealth_Silver_W01`
  - `dbo.Usp_Refresh_InventoryHealth_Silver_W02`
  - `dbo.Usp_Refresh_InventoryHealth_Silver_W03`
- Queried live processing catalog for `ReferenceMaster_Enh`, `InventoryHistory_Enh`, `SalesHistory_Enh`, `Staging` and their `_Wrk` views.
- Queried live `ETL_Framework.DW_Developer.TableDictionary` and `TableDictionary_UpdateLog`.
- Compared with local `05_tools/06_lineage_portal/site/public/lineage_snapshot.json` generated at `2026-07-06T05:17:54Z`.
- Compared with local `02_marts/inventory_health/05_catalog/run_order.json` generated at `2026-06-28T05:30:00Z`.

**Live Fabric findings:**
- Live pipeline order is correct and current:
  1. `Usp_Refresh_Shared_ReferenceMaster`
  2. `Usp_Refresh_Shared_Staging`
  3. `Usp_Refresh_ForecastAccuracy_Silver_W01`
  4. `Usp_Refresh_ForecastAccuracy_Silver_W02`
  5. `Usp_Refresh_ForecastAccuracy_Silver_W03`
  6. `Usp_Refresh_ForecastAccuracy_Gold`
  7. `Usp_Refresh_InventoryHealth_Silver_W01`
  8. `Usp_Refresh_InventoryHealth_Silver_W02`
  9. `Usp_Refresh_InventoryHealth_Silver_W03`
  10. `Usp_Refresh_InventoryHealth_Gold`
- Live `Usp_Refresh_Shared_ReferenceMaster` targets 11 tables:
  - `Calendar`, `CustomerAccount`, `CustomerAccountGroup`, `CustomerGrouping`, `CustomerShippingLocation`, `ForecastCycle`, `ForecastHorizon`, `ItemMaster`, `OrderType`, `Vendor`, `Warehouse`
- Live Inventory Silver W01 targets only 2 tables:
  - `InventoryHistory_Enh.InventorySnapshotWeekly`
  - `InventoryHistory_Enh.AtpWeekEnding`
- Live Inventory Silver W02 targets 8 tables:
  - `InventoryHistory_Enh.PurchaseOrderSnapshotHistorical`
  - `InventoryHistory_Enh.ManufacturingOrderSnapshotDaily`
  - `InventoryHistory_Enh.HoldingTransferSnapshotDaily`
  - `InventoryHistory_Enh.ForecastSnapshotWeekly`
  - `InventoryHistory_Enh.SupplyPlanDetail`
  - `InventoryHistory_Enh.ItemBalanceHistorical_WithInTransit`
  - `InventoryHistory_Enh.SafetyStockHelper`
  - `SalesHistory_Enh.InvoiceDetailLineLevel`
- Live Inventory Silver W03 targets 4 tables:
  - `InventoryHistory_Enh.AFIStatusSnapshotWeekly`
  - `InventoryHistory_Enh.AwdHelper`
  - `InventoryHistory_Enh.LastInvoiceWeekly`
  - `InventoryHistory_Enh.Cogs52WWeekly`
- Live catalog has 13 `InventoryHistory_Enh` physical tables and 13 matching `_Wrk` views.
- Latest `TableDictionary_UpdateLog` confirms the same run order/freshness sequence on `2026-07-06 22:29` to `23:21` UTC.

**Repo/lineage status:**
- Repo `run_order.json` is mostly aligned with live SP order for W01/W02/W03.
- Local lineage snapshot is useful for object surface/row counts but not authoritative for runtime wave labels.
- The uploaded UI screenshot showing multiple Inventory tables as `Wave 1` should not be used as runtime truth if it conflicts with live SP.
- Current draft DQ template is under-scoped relative to full live Bronze-to-Silver first-wave/shared scope because it covers only 5 of 11 live ReferenceMaster tables and only the 2 live W01 Inventory tables.

**Conclusion:**
- Source-of-truth ranking for DQ implementation: live Fabric pipeline + live SP + live TableDictionary first, repo second, lineage snapshot/UI third.
- For the user's Bronze-to-Silver wave đầu task, DQ scope must be derived from the live SP targets, not from the screenshot wave label alone.

## 2026-07-07 14:35:00 ICT — Lineage portal wave fix and live snapshot regeneration

**Scope lock:**
- Repo code edit + read-only live Fabric scan.
- No Fabric data mutation.

**User instruction:**
- Fix lineage and deploy the portal so it reflects live Fabric as source of truth.

**Actions/evidence:**
- Updated lineage scanner wave behavior:
  - `scanner.mart_catalog` now applies wildcard run-order entries such as `ReferenceMaster_Enh.*` to matching catalog assets.
  - `scanner.wave_builder` now treats runtime/catalog waves as authoritative; topology only fills missing waves.
- Added regression tests:
  - wildcard run-order wave mapping
  - runtime wave not being pushed by dependency topology
- Regenerated `site/public/lineage_snapshot.json` from live Fabric using `FABRIC_USE_AZ_CLI=1`.
- Verified generated snapshot:
  - all 11 `ReferenceMaster_Enh` tables are `W01`
  - `InventorySnapshotWeekly` and `AtpWeekEnding` are `W01`
  - `ForecastSnapshotWeekly` is `W02`
  - `AwdHelper` is `W03`
- Secret scan of generated snapshot returned no matches.
- Validation passed:
  - `PYTHONPATH=. python3 -m unittest discover -s tests -v` -> 15 tests OK
  - `npm run typecheck` -> OK
  - `NEXT_PUBLIC_BASE_PATH=/data-architecture-microsoft-medallion-vietnam-data-hub npm run build` -> OK

**Deploy status:**
- Completed.
- Pushed lineage scanner fix to feature branch commit `febe98b9`.
- GitHub Pages environment only allowed `main`, so cherry-picked to clean main worktree and pushed:
  - `57454f88` — scanner wildcard/runtime-wave fix
  - `0ed4194e` — `inventory_health/05_catalog/run_order.json` aligned with live Fabric W01/W02/W03 plus regenerated snapshot
- Triggered GitHub Actions workflow `Build Lineage Portal` with `scan_mode=live`.
- Final successful run:
  - run id `28849018935`
  - head SHA `0ed4194eea143d8f03deba833f2fe721cf6d66e6`
  - Pages URL `https://ankinguyen-engineer-2002.github.io/data-architecture-microsoft-medallion-vietnam-data-hub/`
- Public snapshot verification passed:
  - `generated_at_utc = 2026-07-07T07:24:14Z`
  - `InventorySnapshotWeekly = W01`
  - `AtpWeekEnding = W01`
  - `ForecastSnapshotWeekly = W02`
  - `AwdHelper = W03`

## 2026-07-07 14:40:00 ICT — Inventory BRZ-to-SLV W01 DQ scope recap and missing ReferenceMaster check

**Scope lock:**
- Read-only live SQL checks.
- No DQ view/table creation and no physical DQ insert.

**User instruction:**
- Re-summarize the user's Inventory Bronze-to-Silver wave đầu scope and pass/fail after lineage correction; explain why Bronze lineage shows many sources.

**Scope decision:**
- User scope `Inventory BRZ -> SLV wave đầu` = live shared `ReferenceMaster` prerequisite + live `InventoryHealth_Silver_W01`.
- Target count = 13:
  - `ReferenceMaster_Enh`: 11 tables
  - `InventoryHistory_Enh`: `InventorySnapshotWeekly`, `AtpWeekEnding`
- Rule count = 39 = 13 targets x 3 rule families.
- Do not include Inventory W02/W03 Bronze sources in this wave đầu DQ scope.

**Evidence already available:**
- Earlier full SELECT-only run for 7 targets:
  - 5 ReferenceMaster already in draft + 2 Inventory W01 targets
  - result `18 PASS / 3 FAIL / 21`
  - all `DQ_B2S_*` and all `DQ_Silver_Grain_*` passed
  - fails were raw Bronze only:
    - `Warehouse`: `blank_or_null_key_rows = 1`
    - `DemandInventorySnapshotDaily`: `duplicate_groups = 135,977,040`
    - `ATPWeekEnding`: `duplicate_groups = 18`

**New live check for 6 missing ReferenceMaster targets:**
- Targets checked:
  - `CustomerAccount`
  - `CustomerGrouping`
  - `CustomerShippingLocation`
  - `ForecastCycle`
  - `ForecastHorizon`
  - `OrderType`
- Result: `14 PASS / 4 FAIL / 18`
- All 6 `DQ_B2S_KeyParity_*` passed.
- Fails:
  - `DQ_Bronze_Grain_CustomerShippingLocation`: `blank_key_rows = 35,716`, `duplicate_groups = 0`
  - `DQ_Silver_Grain_CustomerShippingLocation`: `blank_or_null_key_rows = 35,716`, `duplicate_groups = 0`
  - `DQ_Bronze_Grain_OrderType`: `blank_key_rows = 1`, `duplicate_groups = 0`
  - `DQ_Silver_Grain_OrderType`: `blank_or_null_key_rows = 1`, `duplicate_groups = 0`

**Combined wave đầu result:**
- `32 PASS / 7 FAIL / 39`
- By family:
  - Bronze source grain: `9 PASS / 4 FAIL`
  - B2S parity: `13 PASS / 0 FAIL`
  - Silver final grain: `10 PASS / 3 FAIL`

**Interpretation:**
- Transform/load from BRZ/Wrk to physical Silver is clean for all 13 targets checked.
- Failures are source/key cleanliness propagated to final Silver for specific raw key issues, plus source duplicate issues in the two Inventory W01 raw feeds.
- Lineage shows many Bronze nodes because it displays full upstream graph for Inventory W02/W03/Gold and shared dependencies, not only the user's W01 BRZ-to-SLV DQ assignment.

## 2026-07-09 — Session history extraction and context consolidation (from OpenCode/Codex sessions)

**Scope lock:**
- Read-only extraction from `~/.codex/state_5.sqlite`, `~/.codex/memories_1.sqlite`, and `~/.codex/sessions/` JSONL files.
- Write to `00_CONTEXT/current.md` only.
- No live Fabric/SQL mutation.

**Source:**
- OpenCode/Codex sessions stored in:
  - `~/.codex/state_5.sqlite` → `threads` table (26 threads in this repo's CWD)
  - `~/.codex/memories_1.sqlite` → `stage1_outputs` table (25 memory slugs)
  - `~/.codex/sessions/2026/06/` and `~/.codex/sessions/2026/07/` → 155 JSONL rollout files total
  - `~/.codex/session_index.jsonl` → 7 named sessions (not repo-specific)

**Key session findings consolidated (July 6-8, 2026):**

### Session `019f35e4` (2026-07-06) — Full pipeline audit + DQ snapshot analysis

- User asked to check whether full 10-step mart chain ran after 18:00 ICT on 2026-07-03.
- Conclusion: **NO** evidence of evening run. All pipeline runs completed before 15:00 ICT.
- DQ duplicate snapshots were caused by:
  1. Multiple manual DQ reruns on the same day
  2. Mutable bronze source comparison against stale Silver
  3. DQ rule inventory changing mid-day (32 vs 47 rules)
- Active pipeline `pl_backup_full_refresh` was triggered on 2026-07-06 at 14:01 ICT and completed successfully.
- Forecast DQ recheck passed after new pipeline run.
- Inventory DQ BRZ-to-SLV wave đầu result: `32 PASS / 7 FAIL / 39` (fails are source cleanliness, not transform issues).

### Session `019f3f69` (2026-07-08 to 2026-07-09) — PR feedback from DE US + Git repo strategy

- User committed Fabric workspace changes to `data-fabric-enterprise-supply-chain` (PR #6).
- DE US (Bob) feedback:
  - **Database objects** (stored procedures, tables, functions) should go to `data-edw-fabric` repo for future PRs.
  - Current PR will be accepted this time; Bob will backfill `data-edw-fabric` later.
  - **Multiple-source contamination**: PR contained schemas from `Retail_DW`, `Wholesale_ProductSourcing_Afi`, `WholeSale_Quality_AFI_wr` — user must remove non-Supply Chain objects.
- Root cause of contamination: `ETL_Framework` warehouse had schemas synced from Enterprise `ETL_Framework` (Bob's) that included other domains. Those were cleaned up during the session.
- **Dual-repo strategy established:**
  - **Repo A** (`data-fabric-enterprise-supply-chain`): Fabric workspace items (lakehouse, semantic models, reports, notebooks, non-SQL objects) — commit via Fabric git integration.
  - **Repo B** (`data-edw-fabric`): Database objects (stored procedures, tables, views, functions in warehouses) — commit manually via VS Code, PR via GitHub.
- Git conflict resolved on `ETL_Framework` after cleaning stale schemas.
- Model used: `gpt-5.5`, total tokens: `134,178,286`

### Session `019f1c4d` (2026-07-01) — Pipeline orchestration re-verification + live sync

- User asked to verify current orchestration/pipeline configuration from repo.
- Confirmed wave-first ETL order is operational.
- `ETL_Framework` sync from `EnterpriseData-Dev.ETL_Framework` was verified additive-only on 2026-07-02.
- Documented intentional exceptions:
  - `Usp_TableFromParquet_RowADF` removed (broken source object)
  - `Usp_SnapshotLoad` patched minimally for live path handling

### Session `019f26e5` (2026-07-03) — Pipeline failure investigation

- `pl_backup_full_refresh` failed on 2026-07-03 at 14:31 ICT.
- Root cause investigated: `ForecastHistory_Enh_Wrk.v_ForecastDemandMonthly` duplicate issue in Silver view.
- Calendar join logic producing duplicates was the underlying cause.

### Earlier key sessions (June 2026 — from memories DB):

| Date | Slug | Summary |
|------|------|---------|
| 2026-06-22 | `phase1-migration-context-logging-and-plan-checkpoints` | Phase 1 execution started; `usp_IncrementalTableLoad` hit SQL 3930 |
| 2026-06-22 | `phase1-resume-fix-incrementaltableload-3930-and-validate-smokes` | Fixed 3930 masking bug; validated smokes |
| 2026-06-22 | `forecast_accuracy_affi_enh_source_fix_mart_a_only_rerun` | Source fix: `SalesHistory_AFI` → `SalesHistory_AFI_Enh` |
| 2026-06-22 | `mart-a-complete-v10-refresh-v8-registry-maintenance` | Mart A verified complete; v8 registry forced due |
| 2026-06-23 | Phase 1 handoff | Phase 1 officially complete (see `01_docs/runbook/artifacts/.../phase1_done_handoff_20260623.md`) |
| 2026-06-24 | `wave-first-etl-framework-orchestration` | Orchestration re-aligned to wave-first model |
| 2026-06-25 | `da-onboarding-table-edit-and-wave-clarification` | DA onboarding doc improved for ETL wave self-service |
| 2026-06-26 | `codex-cli-aibox-deepseek-default-profile-setup` | Codex CLI configured for API AI Box/DeepSeek |
| 2026-06-26 | `read-context-and-chat-history-before-continuing` | Lineage portal work remaining (commit/push/redeploy) |

**Codex session storage architecture (for future reference):**
- `~/.codex/state_5.sqlite` → all thread metadata (`threads` table), including `cwd`, `title`, `model`, `tokens_used`, `first_user_message`
- `~/.codex/memories_1.sqlite` → distilled learnings per thread (`stage1_outputs` table with `raw_memory`, `rollout_summary`, `rollout_slug`)
- `~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl` → full conversation transcripts (7586 lines for last session alone)
- `~/.codex/history.jsonl` → 705KB chronological command history
- `~/.codex/session_index.jsonl` → 7 named session bookmarks
- Thread filtering: `SELECT * FROM threads WHERE cwd LIKE '%20260413_Fabric%'` returns all 26 sessions for this repo

## 2026-07-09 — Phase 0 freeze/audit for DemandForecast historical backfill plan (read-only)

**Scope lock:**
- Read-only Fabric REST + warehouse SQL audit.
- No DELETE/INSERT, no view repoint, no pipeline trigger.

**User instruction:**
- Proceed with plan sequentially; report each step; audit carefully.

**Phase 0.1 — runtime freeze check:**
- `pl_backup_full_refresh` recent instances: latest `Completed` 2026-07-08 06:36–08:31 UTC; no Running instance.
- Query Insights last 6h: ETL_Framework / Processing / Gold = all `Succeeded` only; non-success = 0.
- AuditLog latest (2026-07-09 ~02:09 UTC): DateRange live validation on `ForecastDemandMonthly`, `ForecastSnapshotWeekly`, `FactForecastKpi` + LoadPatternBench cleanup.

**Phase 0.2 — EL 5-key readiness:**
- Dry-run window `2026-06-24`–`<2026-07-09`: DuplicateGroups=`0`; rows=`161,221,968`; snapshot_days=`13`.
- Chunk 2.1 window `2023-05-01`–`<2023-07-01`: DuplicateGroups=`0`.
- Staging view partition keys now match 5-key (ROW_NUMBER over 5-key); physical Staging max snapshot `2026-07-06`, ~10.9B rows.

**Phase 0.3 — source path still staging-backed:**
- Live `v_ForecastDemandMonthly` still `FROM Staging.DemandForecastSnapshotDaily`.
- Live `v_ForecastSnapshotWeekly` still `FROM Staging.DemandForecastSnapshotDaily`.
- TableDictionary PK for Staging/view = 5-key; `ForecastDemandMonthly` UpdateMethod still `overwrite` (metadata lag vs DateRange test).

**Phase 0.4 — critical dry-run window mismatch:**
- `ForecastDemandMonthly` / `FactForecastKpi` are **monthly cycle** snapshots (latest physical `2026-06-15`), not daily.
- `ReferenceMaster_Enh.ForecastCycle` rows in `2026-06-24`–`<2026-07-09` = **0** (join kills FDM output in that window).
- Physical dry-run window: FDM rows_inside=`0`; KPI rows_inside=`0`; FSW rows_inside=`5,522,472` (Saturdays 06-27, 07-04).
- Outside window preserved: FDM ~230M (min 2023-01-16); FSW ~1.07B; KPI ~111M.
- `FactForecastActual` exists but **no Snapshot column** (grain: ItemSKU/WH/CustomerGroup/FSCMonth/Horizon/Status/Version) — rebuild pattern ≠ date-window Snapshot.
- IH lineage from `ForecastSnapshotWeekly`: `v_AwdHelper` → physical `InventoryHistory_Enh.AwdHelper` (AsOfDate 2023-07-15..2026-07-07). W03 loads AwdHelper. Gold IH facts may cascade.

**Gate / next:**
- Do **not** start live dry-run with plan window `2026-06-24`–`2026-07-09` for FDM/KPI (empty by ForecastCycle design).
- Need Aric confirm: (1) dry-run window realigned to a ForecastCycle date e.g. include `2026-06-15`; (2) start history `2023-05-01` vs `2023-01-01`; (3) include `AwdHelper` (+ IH gold?) after FSW; (4) `FactForecastActual` in/out of scope; (5) repoint views to EL/thin before rebuild vs rebuild-from-staging-as-is.

**Next concrete step:**
- Phase 0 gate: confirm dry-run window realignment + open decisions before any live DELETE/INSERT.

## 2026-07-09 — Path A authorized; deep parity audit; history rebuild re-scoped (read-only)

**Scope lock:**
- Read-only SQL parity audits only.
- No live DELETE/INSERT, no view repoint, no full PL.

**User authorization:**
- Proceed with best path that audits carefully and does not damage final goal:
  change load method, keep results as good as correct full load, eventually drop unnecessary staging if EL 5-key is clean.

**Parity evidence (cycle probes):**

| Snapshot | EL rows | Staging rows | EL=Stg sums | EL 5-key dups | FDM view=phys rows/sums |
|---|---:|---:|---|---|---|
| 2026-06-15 | 12,381,120 | 12,381,120 | YES | 0 | 6,878,400 / 43,771,712 YES |
| 2023-05-15 | 2,601,144 | 2,601,144 | YES | 0 | YES |
| 2024-01-15 | 2,566,008 | 2,566,008 | YES | 0 | YES |
| 2024-10-14 | 3,139,416 | 3,139,416 | YES | 0 | YES |
| 2025-06-09 | 12,308,184 | 12,308,184 | YES | 0 | YES (view=phys; EL raw > FDM due to transform/cycle filter) |

Also for 2026-06-15:
- Staging_Wrk view rows/sums = EL
- FSW view=phys on 2026-06-13 and 2026-06-20
- KPI view=phys on 2026-06-15

**Framework DateRange constraint (live definition):**
- `usp_UpdateCuratedTableFromView_DateRange` only supports relative window:
  `@MinDate = DATEADD(DAY, @NumberofDays, GETDATE())` then DELETE/INSERT where date >= @MinDate.
- It does **not** accept arbitrary historical `[Start, End)` for 2023 chunks.
- Historical arbitrary windows require adhoc parameterized DELETE+INSERT scripts.

**Re-scoped decision (protect goal):**
1. Do **not** run multi-year historical rebuild now — no mismatch found on spread probes; rebuild would burn CU and risk without correctness gain.
2. Treat historical rebuild as **conditional** only if a future probe finds EL≠Staging or view≠physical on a cycle date.
3. Primary safe path = daily/relative DateRange method with pre-checks (empty window, 5-key dups) + parity DQ after load.
4. Staging removal / thin EL wrapper = later optimization after more full-range spot checks, not a blind cutover today.
5. FDM/KPI are ForecastCycle monthly snapshots, not daily continuum — DateRange `@NumberofDays` must cover last cycle date (e.g. include 2026-06-15).

**Next concrete step:**
- Prepare production-safe DateRange operating checklist (NumberofDays guidance, pre-check SQL, post parity SQL).
- Optional controlled re-validation DateRange on FDM/FSW/KPI only if Aric wants another live prove-out.
- Defer historical chunk scripts unless mismatch appears.

## 2026-07-09 — DemandForecast staging-drop code cutover prepared (no live deploy)

**Scope lock:**
- Code/docs only in `data-edw-fabric` + architecture repo.
- No live CREATE/ALTER/DELETE/INSERT on Fabric warehouses.
- No full PL trigger.

**Decision locked by Aric:**
- Drop staging hop for DemandForecast path.
- Keep transform formulas.
- Results must remain as good as correct full load.
- DateRange is the daily method after cutover.
- Historical multi-year rebuild only if parity fails.

**Code prepared:**

1. NEW `Source_Wrk` schema + thin `Source_Wrk.v_DemandForecastSnapshotDaily`
   - direct EL via `[$(Databricks)].SupplyChain_Enh.DemandForecastSnapshotDaily`
   - no ROW_NUMBER dedupe
2. REPOINT `ForecastHistory_Enh_Wrk.v_ForecastDemandMonthly` -> `Source_Wrk...`
3. REPOINT `InventoryHistory_Enh_Wrk.v_ForecastSnapshotWeekly` -> `Source_Wrk...`
4. `Usp_Refresh_Shared_Staging` -> no-op (stops Staging DemandForecast DateRange load)
5. Mirrored to architecture `02_marts` + `03_operations/deployment/sqlproj`
6. Checklist: `01_docs/plans/2026-07-09-demandforecast-staging-drop-cutover-checklist.md`

**Not done (next live gate):**
- Deploy objects to Fabric Dev warehouse
- Parity gate on cycle `2026-06-15` + FSW Saturdays
- DateRange prove-out after parity PASS
- DQ rule retirement for Staging physical compares
- Drop physical Staging table

**Next concrete step:**
- Aric approve live deploy of Source_Wrk + 2 silver views + Shared_Staging no-op
- Then run parity gate before any load

## 2026-07-09 — Cutover chốt direct EL (bỏ Source_Wrk)

**Decision:**
- Aric rejected optional Source_Wrk wrapper.
- Final path: silver views read EL directly via `[$(Databricks)].SupplyChain_Enh.DemandForecastSnapshotDaily`.
- No extra hop. Staging physical load remains no-op via `Usp_Refresh_Shared_Staging`.

**Code state:**
- `Source_Wrk` files removed from data-edw-fabric + architecture mirrors.
- `v_ForecastDemandMonthly` / `v_ForecastSnapshotWeekly` updated to direct EL.
- Checklist updated: `01_docs/plans/2026-07-09-demandforecast-staging-drop-cutover-checklist.md`.
- Still **not live deployed**.

**Next concrete step:**
- Live deploy Dev: 2 silver views + Shared_Staging no-op → parity gate → DateRange prove-out.

## 2026-07-09 — Handoff status: plan ticks + context synced (ready for next session)

**Purpose:** close documentation loop so next execution continues from a single clear board.

### Goal (unchanged)
- Drop Staging hop for DemandForecast
- Keep transform formulas
- Results as good as correct full load
- Daily method = DateRange after cutover
- Historical multi-year rebuild only if parity fails

### DONE [x]
1. Phase 0 freeze/runtime audit (no full PL running; QI clean sample)
2. EL 5-key clean on ops window + historical probes (Apr 2023 exception documented)
3. Deep parity: EL ≈ Staging ≈ FDM/FSW/KPI view/physical on cycles:
   - 2023-05-15, 2024-01-15, 2024-10-14, 2025-06-09, 2026-06-15
4. DateRange framework constraint documented (relative GETDATE only)
5. Historical rebuild re-scoped to **conditional**
6. Path chốt: **direct EL** (`[$(Databricks)].SupplyChain_Enh.DemandForecastSnapshotDaily`)
7. `Source_Wrk` drafted then **removed** (rejected)
8. Repo code prepared (not live):
   - `v_ForecastDemandMonthly` → direct EL
   - `v_ForecastSnapshotWeekly` → direct EL
   - `Usp_Refresh_Shared_Staging` → no-op
9. Mirrors updated in architecture `02_marts` + `03_operations/deployment/sqlproj`
10. Plans updated with status boards:
    - `01_docs/plans/2026-07-09-demandforecast-staging-drop-cutover-checklist.md`
    - `01_docs/plans/2026-07-09-demandforecast-historical-backfill-and-load-reset-plan.md`

### NOT DONE [ ] — next execution order
1. **NEXT:** Live deploy Dev
   - ALTER `ForecastHistory_Enh_Wrk.v_ForecastDemandMonthly`
   - ALTER `InventoryHistory_Enh_Wrk.v_ForecastSnapshotWeekly`
   - ALTER `dbo.Usp_Refresh_Shared_Staging` (no-op)
2. Parity gate (must PASS before load):
   - cycle `2026-06-15` (FDM/KPI)
   - FSW Saturdays `2026-06-13`, `2026-06-20`
   - criteria: EL 5-key dups=0; view rows/sums = physical rows/sums
3. DateRange prove-out: FDM / FSW / FactForecastKpi (pre-check empty window + dups)
4. After stable: retire DemandForecast Staging DQ compares
5. Later: drop/archive `Staging.DemandForecastSnapshotDaily`; deprecate Staging_Wrk view
6. Conditional only: historical window rebuild if parity FAIL

### Do not
- Full PL between deploy and parity PASS
- Historical 6-month chunk rebuild by default
- Dry-run FDM/KPI on `2026-06-24`–`2026-07-09` (no ForecastCycle)
- Reintroduce Source_Wrk unless Aric re-opens that decision

### Canonical code locations
- `data-edw-fabric/SupplyChain_Processing_Warehouse/ForecastHistory_Enh_Wrk/Views/v_ForecastDemandMonthly.sql`
- `data-edw-fabric/SupplyChain_Processing_Warehouse/InventoryHistory_Enh_Wrk/Views/v_ForecastSnapshotWeekly.sql`
- `data-edw-fabric/SupplyChain_Processing_Warehouse/dbo/StoredProcedures/Usp_Refresh_Shared_Staging.sql`

### Next concrete step
- Resume from cutover checklist item **#11 Live deploy Dev** when Aric approves live ALTER.

## 2026-07-10 — Resume cutover plan: pre-flight read-only (ready for live deploy #11)

**Scope lock:**
- Read-only live Fabric REST + warehouse SQL pre-flight.
- Deploy SQL prepared offline only.
- No live ALTER/CREATE/DELETE/INSERT yet.

**User instruction:**
- Read latest context + plans; report done/not done; continue plan.

**Plan source of truth:**
- Primary: `01_docs/plans/2026-07-09-demandforecast-staging-drop-cutover-checklist.md`
- Secondary (re-scoped): `01_docs/plans/2026-07-09-demandforecast-historical-backfill-and-load-reset-plan.md`
- Resume point confirmed: checklist item **#11 Live deploy Dev**

### DONE [x] (unchanged from 2026-07-09 handoff)
1. Phase 0 freeze/runtime audit
2. EL 5-key clean (ops + hist probes; Apr 2023 exception documented)
3. Deep parity multi-cycle EL ≈ Staging ≈ view ≈ physical
4. DateRange relative-GETDATE constraint documented
5. Historical rebuild re-scoped = conditional only
6. Path chốt direct EL (no Source_Wrk)
7. Repo code + architecture mirrors prepared (not live)
8. Plans/context status boards ticked

### NOT DONE [ ] next order
1. **#11 NEXT** Live deploy Dev: 2 silver views + Shared_Staging no-op
2. **#12** Parity gate `2026-06-15` + FSW `2026-06-13`/`2026-06-20`
3. **#13** DateRange prove-out FDM/FSW/KPI
4. **#14–16** DQ retire / drop Staging later
5. **#17** Historical rebuild only if parity FAIL

### Pre-flight evidence (2026-07-10)
- `pl_backup_full_refresh` running/pending = **0**
- Latest full PL: Completed `2026-07-08T06:36Z`–`08:31Z`
- Live still **Staging path**:
  - `ForecastHistory_Enh_Wrk.v_ForecastDemandMonthly` → `FROM Staging.DemandForecastSnapshotDaily`
  - `InventoryHistory_Enh_Wrk.v_ForecastSnapshotWeekly` → `FROM Staging.DemandForecastSnapshotDaily`
  - `dbo.Usp_Refresh_Shared_Staging` still DateRange load Staging `-15`
- Live EL 3-part name verified via `Staging_Wrk.v_DemandForecastSnapshotDaily`:
  - `FROM [Enterprise_Lakehouse].[SupplyChain_Enh].[DemandForecastSnapshotDaily]`
  - `sys.databases` includes `Enterprise_Lakehouse`; no external_data_sources needed
- Deploy package prepared (offline, not executed):
  - `/var/folders/.../T/opencode/cutover_20260710/00_deploy_all_direct_el_cutover.sql`
  - `$(Databricks)` resolved to `Enterprise_Lakehouse`
  - `CREATE OR ALTER` for 2 views + Shared_Staging no-op

### Do not
- Full PL between deploy and parity PASS
- Historical multi-year rebuild by default
- Dry-run FDM/KPI window `2026-06-24`–`2026-07-09`
- Reintroduce Source_Wrk

**Next concrete step:**
- Await Aric explicit approve for live ALTER on Processing Warehouse (#11), then deploy → parity gate (#12).

## 2026-07-10 — Live deploy #11 + parity gate #12 PASS (direct-EL cutover)

**Scope lock:**
- Live ALTER on `SupplyChain_Processing_Warehouse` only (2 views + Shared_Staging).
- Read-only parity queries on Processing + Gold.
- No full PL; no DateRange load yet; no Staging drop.

**User instruction:**
- `oke approve` live deploy #11.

### Deploy executed (all OK)
1. `CREATE OR ALTER VIEW ForecastHistory_Enh_Wrk.v_ForecastDemandMonthly` → direct EL
2. `CREATE OR ALTER VIEW InventoryHistory_Enh_Wrk.v_ForecastSnapshotWeekly` → direct EL
3. `CREATE OR ALTER PROCEDURE dbo.Usp_Refresh_Shared_Staging` → no-op

Live path verified:
- FDM/FSW: `FROM [Enterprise_Lakehouse].[SupplyChain_Enh].[DemandForecastSnapshotDaily]`
- Shared_Staging: PRINT no-op only (no DateRange EXEC)

### Parity gate #12 — PASS
| Check | Result |
|---|---|
| EL 5-key dups @ 2026-06-15 | 0 |
| FDM view vs phys @ 2026-06-15 | rows 6,878,400 / sum 43,771,712 MATCH |
| FSW view vs phys @ 2026-06-13 | rows 2,763,036 / sum 75,590,621 MATCH |
| FSW view vs phys @ 2026-06-20 | rows 2,770,344 / sum 75,528,125 MATCH |
| KPI view vs phys @ 2026-06-15 | rows 1,535,020 / sum 43,771,712 MATCH |

### Status board after this run
- #11 Live deploy: DONE
- #12 Parity gate: PASS
- #13 DateRange prove-out FDM/FSW/KPI: NEXT
- #14–16 Staging DQ retire / drop: LATER
- #17 Historical rebuild: CONDITIONAL (not needed — parity PASS)

### Do not
- Full PL unless Aric requests
- Drop Staging table yet
- Historical multi-year rebuild (parity passed)

**Next concrete step:**
- #13 DateRange prove-out with pre-check empty window + 5-key dups for FDM / FSW / FactForecastKpi (need Aric approve live DateRange if not already covered by earlier 2026-07-09 validation).

## 2026-07-10 — #13 DateRange prove-out PASS (post direct-EL cutover)

**Scope lock:**
- Live DateRange DELETE+INSERT only on:
  - `ForecastHistory_Enh.ForecastDemandMonthly` (-30)
  - `InventoryHistory_Enh.ForecastSnapshotWeekly` (-15)
  - `ForecastAccuracy_DW.FactForecastKpi` (-30)
- No full PL; no Staging drop; no historical multi-year rebuild.

**User instruction:**
- `oke do it` for #13 DateRange prove-out.

### Pre-check gate
- Server date: `2026-07-10`
- Windows: FDM/KPI `>= 2026-06-10` (-30); FSW `>= 2026-06-25` (-15)
- ForecastCycle in window: includes `2026-06-15` (also future 07-13, 08-08)
- EL 5-key dups in -30d: **0**
- View window non-empty:
  - FDM: 6,878,400 rows / sum 43,771,712 (only cycle 2026-06-15)
  - FSW: 5,522,472 rows / sum 151,711,916 (Saturdays 06-27, 07-04)
  - KPI: 1,535,020 rows / sum 43,771,712

### Loads (framework DateRange)
| Table | Days | Window lower | Status | Sec |
|---|---:|---|---|---:|
| ForecastDemandMonthly | -30 | 2026-06-10 | OK | 28.1 |
| ForecastSnapshotWeekly | -15 | 2026-06-25 | OK | 14.0 |
| FactForecastKpi | -30 | 2026-06-10 | OK | 26.2 |

### Post-check — PASS
| Check | Result |
|---|---|
| FDM view vs phys in-window | 6,878,400 / 43,771,712 MATCH |
| FDM outside-window preserved | 222,864,296 / 2,876,676,295 (unchanged vs before) |
| FSW view vs phys in-window | 5,522,472 / 151,711,916 MATCH |
| FSW outside-window preserved | 1,072,974,394 / 31,212,263,338 (unchanged) |
| FDM cycle 2026-06-15 | MATCH |
| KPI view vs phys in-window | 1,535,020 / 43,771,712 MATCH |
| KPI outside-window preserved | 109,334,721 / 2,876,676,295 (unchanged) |

### Status board after this run
- #11 Live deploy direct EL: DONE
- #12 Parity gate: PASS
- #13 DateRange prove-out: **PASS**
- #14 Retire DemandForecast Staging DQ compares: NEXT (docs/DQ only when ready)
- #15–16 Drop/archive Staging table + deprecate Staging_Wrk: LATER (1–2 stable weeks)
- #17 Historical rebuild: NOT NEEDED (parity + DateRange PASS)

**Next concrete step:**
- Optional #14 retire Staging-vs-Staging_Wrk DQ rules for DemandForecast when Aric wants.
- Do **not** drop physical Staging yet.
- Production daily can use DateRange on FDM/FSW/KPI; Shared_Staging remains no-op.

## 2026-07-10 — Historical rebuild C1–C8 COMPLETE (no Staging, no full PL)

**Scope lock:**
- Absolute window DELETE+INSERT only on:
  - `ForecastHistory_Enh.ForecastDemandMonthly`
  - `InventoryHistory_Enh.ForecastSnapshotWeekly`
  - `ForecastAccuracy_DW.FactForecastKpi`
- Source = existing Wrk views (direct EL path already live).
- **No** Staging load, **no** Staging drop in this step, **no** full PL, **no** ETL formula change.

**User instruction:**
- Rebuild for certainty in ~5-month chunks (or smaller if needed); do not load 10B Staging; logic unchanged.
- Continue until plan done; rerun C5; continue C6–C8.

### Chunk schedule & results (all PASS)
| Chunk | Window | FDM rows | FSW rows | KPI rows | Status |
|---|---|---:|---:|---:|---|
| C1 | 2023-05-01 → 2023-10-01 | 12,937,500 | 56,839,248 | 12,937,500 | PASS |
| C2 | 2023-10-01 → 2024-03-01 | 13,086,108 | 55,018,188 | 13,086,108 | PASS |
| C3 | 2024-03-01 → 2024-08-01 | 13,861,116 | 60,651,396 | 13,770,504 | PASS |
| C4 | 2024-08-01 → 2025-01-01 | 15,919,092 | 66,991,140 | 15,161,256 | PASS |
| C5 | 2025-01-01 → 2025-06-01 | 41,683,761 | 67,677,048 | 14,921,803 | PASS (rerun clean) |
| C6 | 2025-06-01 → 2025-11-01 | 52,928,954 | 62,183,242 | 12,361,136 | PASS |
| C7 | 2025-11-01 → 2026-04-01 | 44,020,312 | 62,589,780 | 9,864,330 | PASS |
| C8 | 2026-04-01 → 2026-07-11 | 21,304,464 | 37,987,452 | 4,765,715 | PASS |

Gate per chunk:
- EL 5-key dups in window = 0
- view_rows = phys_rows after INSERT
- outside-window row count + sum preserved

### What this means
- Physical silver/gold snapshot tables for DemandForecast path are rebuilt from direct-EL views across 2023-05 → 2026-07-11.
- Staging 10B never loaded.
- Full PL never used for backfill.
- Start date 2023-05-01 intentionally skips Apr 2023 5-key exception.

### Remaining (not part of rebuild)
- #14 Retire Staging DQ compares (optional cleanup)
- #15–16 Drop/archive Staging physical + deprecate Staging_Wrk (later, after stable daily)
- Daily ops = DateRange on FDM/FSW/KPI; Shared_Staging remains no-op

**Evidence file:**
- `/var/folders/.../T/opencode/cutover_20260710/history_rebuild_results.json`

**Next concrete step:**
- Optional #14 DQ cleanup; do not drop Staging yet unless Aric requests.

## 2026-07-10 — PurchaseOrder DateRange migration prepared; InventorySnapshotWeekly deferred

**Scope lock:**
- `InventoryHistory_Enh.InventorySnapshotWeekly`: no code/load/TableDictionary change while US confirms duplicate/source semantics.
- PurchaseOrder work is repository + read-only live SQL only. No live ALTER/DELETE/INSERT and no TableDictionary mutation.

**User instruction:**
- Keep InventorySnapshotWeekly full overwrite temporarily; prioritize the larger PurchaseOrder table.

### Decision
- `InventorySnapshotWeekly` stays **full overwrite** pending US decision on its duplicate grain/tie-break rule.
- `InventoryHistory_Enh.PurchaseOrderSnapshotHistorical` is the next DateRange candidate: `SnapshotDate`, **-30 days**.

### Read-only PO preflight — PASS (2026-07-10)
- Candidate window: `2026-06-10` through `2026-07-09` (30 dates).
- Source `InventoryHistory_Enh_Wrk.v_PurchaseOrderSnapshotHistorical`: **40,733,444** rows.
- Proposed safety key has **0 duplicate groups**:
  `SnapshotDate, ItemSku, WarehouseCode, VendorNumber, StatusCode, DueDate, UnitCost`.
- Current target in-window: **38,089,965** rows; outside-window: **2,028,324,751** rows (total **2,066,414,716**).
- Source-vs-target mismatch only on current dates `2026-07-08` and `2026-07-09`, which are absent from target; DateRange is expected to catch them up.

### Repo prepared (not deployed)
- `data-edw-fabric/.../Usp_Refresh_InventoryHealth_Silver_W02.sql`: PO switches from overwrite to DateRange -30.
- Before delete/insert, W02 blocks if the PO source window is empty or if the proposed safety key duplicates; guard failure `THROW`s before target mutation.
- Architecture W02 mirror, inventory manifest/catalog/operating registry, and generator updated.
- Detailed plan: `01_docs/plans/2026-07-10-purchaseorder-daterange-cutover-plan.md`.

### Next concrete step
1. Re-run PO read-only preflight immediately before deploy.
2. Obtain Aric explicit approval for live `ALTER PROCEDURE dbo.Usp_Refresh_InventoryHealth_Silver_W02` plus one controlled W02 run.
3. Post-run verify PO view=target in-window metrics and unchanged outside-window metrics; do not fallback to overwrite automatically.

## 2026-07-10 — PurchaseOrder DateRange live deployment + prove-out PASS

**Authorized scope executed:**
- `ALTER PROCEDURE dbo.Usp_Refresh_InventoryHealth_Silver_W02` only.
- One **isolated guarded PO DateRange** call only; the remaining W02 tables were not executed.
- No InventorySnapshotWeekly change; it remains full overwrite pending US source-grain clarification.

### Preflight (immediately before mutation)
- Server date/window: `2026-07-10` / `SnapshotDate >= 2026-06-10`.
- PO source: **40,733,444 rows**, 30 dates (`2026-06-10`–`2026-07-09`).
- Proposed safety-key duplicate groups: **0**.
- Target baseline:
  - In-window: 38,089,965 rows; Ordered 16,928,070,070.5860; OnOrder 3,063,058,989.4880; InTransit 1,666,491,216.6290.
  - Outside-window: 2,028,324,751 rows; Ordered 1,689,895,830,143.8390; OnOrder 261,542,995,364.0750; InTransit 143,790,020,740.6810.

### Deployment + load
- Live W02 definition now has source-nonempty + proposed-key-unique guards before PO target mutation; deployment verification PASS.
- Guarded `usp_UpdateCuratedTableFromView_DateRange` PO `SnapshotDate`, `-30` completed **OK in 33.8 seconds**.

### Post-load validation — PASS
- In-window source vs target: **40,733,444 = 40,733,444 rows**.
- OrderedQty / POOnOrderQty / POInTransitQty deltas: **0.0000 / 0.0000 / 0.0000**.
- Per-date source-vs-target mismatch dates: **0**.
- Outside-window baseline exactly preserved:
  - 2,028,324,751 rows
  - Ordered 1,689,895,830,143.8390
  - OnOrder 261,542,995,364.0750
  - InTransit 143,790,020,740.6810

### Operating state / next
- PO DateRange -30 is live and validated.
- Do not automatically fallback to PO full overwrite if a guard fails.
- Observe the next normal W02 and downstream DQ/Gold checks before any PO TableDictionary metadata change.
- InventorySnapshotWeekly remains full overwrite while Aric works with the US team on duplicate semantics.

## 2026-07-10 — Chốt DateRange -30 + TD sync + DQ Staging retire (#14)

**Scope lock:**
- Live metadata + DQ definition updates.
- Repo/docs sync for production standard.
- No Staging drop. No full PL. No ETL business formula change.

**User instruction:**
- Chốt 1 DateRange cho FDM/FSW/KPI; update TableDictionary if needed; update context/repo/live; finish remaining adhoc steps.

### Decision
Unified production DateRange for all three:
- **FDM** `Snapshot` **-30**
- **FSW** `SnapshotDate` **-30**
- **KPI** `Snapshot` **-30**

Rationale: one ops rule; must follow FDM/KPI monthly-cycle coverage (not FSW-only -15).

### Live executed
1. **TableDictionary** (`ETL_Framework.DW_Developer.TableDictionary`)
   - `ForecastDemandMonthly`: overwrite → **DateRange**, DateKey=`Snapshot`, DateRangeDays=**30**
   - `ForecastSnapshotWeekly`: overwrite → **DateRange**, DateKey=`SnapshotDate`, DateRangeDays=**30**
   - `FactForecastKpi`: overwrite → **DateRange**, DateKey=`Snapshot`, DateRangeDays=**30**
2. **Wrappers already live at -30** (no body change required):
   - `Usp_Refresh_ForecastAccuracy_Silver_W02` (FDM)
   - `Usp_Refresh_InventoryHealth_Silver_W02` (FSW)
   - `Usp_Refresh_ForecastAccuracy_Gold` (KPI)
   - `Usp_Refresh_Shared_Staging` remains **no-op**
3. **#14 DQ retire** on `DataQuality.v_DQForecastAccuracy` (Processing):
   - `DQ_LoadParity_StagingDemandForecastSnapshotDaily_RowCount` → RETIRED / forced PASS
   - `DQ_LoadParity_StagingDemandForecastSnapshotDaily_Qty` → RETIRED / forced PASS
   - Kept bronze grain + other rules; only Staging load-parity retired after Shared_Staging no-op

### Repo / docs synced
- `data-edw-fabric` DQ view + wrapper header notes
- architecture `02_marts/.../run_order.json` load_type DateRange -30 for FDM/FSW/KPI
- orchestration manifests FA/IH
- cutover checklist + history plan notes
- this context entry

### Status board after this run
- #11–#13 cutover + parity + DateRange prove-out: DONE
- #17 history rebuild C1–C8: DONE
- #14 Staging DQ load-parity retire: **DONE**
- Unified DateRange -30 + TableDictionary: **DONE**
- #15–16 Staging drop/deprecate: still **LATER** (not in this adhoc)

### Do not
- Drop Staging physical yet
- Reintroduce Shared_Staging DemandForecast load
- Use DateRange -15 for FDM/KPI

**Next (optional, not blocking daily):**
- #15–16 after 1–2 stable daily weeks, only with explicit approve
- Spot-check first scheduled full PL after this metadata change (DateRange path already live in wrappers)

## 2026-07-10 — Staging DemandForecast DROPPED + post-drop tests

**Scope lock:**
- Dropped physical Staging DF + Staging_Wrk wrapper view.
- DQ cleaned of physical Staging dependency first.
- No full PL; no ETL formula change on FDM/FSW/KPI.

**User instruction:** `no cứ drop staging đi, r check test tiếp`

### Pre-drop
- `Staging.DemandForecastSnapshotDaily` existed (~10,876,685,631 rows)
- `Staging_Wrk.v_DemandForecastSnapshotDaily` existed (read EL)
- Silver FDM/FSW already direct EL; Shared_Staging no-op
- DQ still had `FROM Staging.DemandForecastSnapshotDaily` in load-parity CTEs → fixed before drop

### Live actions
1. Redeploy `DataQuality.v_DQForecastAccuracy`:
   - S2_Forecast* sources → EL direct
   - LP_StagingDemand_* CTEs → zero stubs (legacy rule names kept, already retired PASS)
   - No `FROM Staging.DemandForecastSnapshotDaily`
2. `DROP TABLE Staging.DemandForecastSnapshotDaily` — OK (~0.4s metadata drop)
3. `DROP VIEW Staging_Wrk.v_DemandForecastSnapshotDaily` — OK
4. TableDictionary Staging row → `UpdateMethod=Retired` + note dropped

### Post-drop tests
| Check | Result |
|---|---|
| Objects remaining | 0 |
| `Usp_Refresh_Shared_Staging` | OK no-op |
| FDM view vs phys `2026-06-15` | 6,878,400 / 43,771,712 MATCH |
| FSW view vs phys `2026-06-13` | 2,763,036 / 75,590,621 MATCH |
| FDM/FSW path | direct EL |
| DQ defn physical FROM Staging | 0 |

### Status board
- #11–#14, #17, unified DateRange -30: DONE
- #15 Staging physical drop: **DONE**
- #16 Staging_Wrk view drop: **DONE**

**Rollback note:** Staging physical gone. Rollback = keep direct EL path (current primary). Rebuilding 10B Staging is not the rollback path.

## 2026-07-10 — New active snapshot load-pattern migration plan (planning only)

**Scope lock:**
- Read-only audit plus documentation only; no wrapper, TableDictionary, pipeline, or warehouse mutation was made in this step.
- New candidates: `InventoryHistory_Enh.PurchaseOrderSnapshotHistorical` (P1) and `InventoryHistory_Enh.InventorySnapshotWeekly` (P2).
- DemandForecast plans are complete and superseded as active plans; they remain evidence.

**Completed audit evidence:**
- PO TableDictionary grain = `SnapshotDate, ItemSku, WarehouseCode, VendorNumber, StatusCode, DueDate, UnitCost`.
  - no hidden view dedupe;
  - zero duplicate groups in full 2.066B-row physical target;
  - 2,368 all-history view ↔ physical snapshot-date row/sum comparisons match.
- Inventory Snapshot TableDictionary grain = `ItemSku, WarehouseCode, SnapshotWeekEndingDate, FiscalMonth`.
  - view `ROW_NUMBER PARTITION BY` matches this exact grain and selects newest technical version;
  - zero duplicate groups in full 695M-row physical target;
  - 185 all-history output-date view ↔ physical row/key-sum comparisons match.
- Therefore: **no historical backfill planned** for either candidate. Migrate load pattern only after controlled proof.

**Plan / controls:**
- Active document: `01_docs/plans/2026-07-10-snapshot-load-pattern-migration-plan.md`.
- P1 PO candidate: guarded DateRange on `SnapshotDate`, `-30` candidate pending late-arrival audit.
- P2 Inventory Snapshot candidate: guarded DateRange on `SnapshotWeekEndingDate`, `-42` candidate pending semantic and Query Insights approval.
- Mandatory wrapper-local prechecks before DELETE+INSERT: non-empty source window and zero duplicate groups at TableDictionary grain; `THROW` on failure.
- Do not modify the global framework DateRange SP.

**Next:**
- Await Aric approval for Phase 0 / P1 only; then reconcile repo-generated wrapper versus live, baseline Query Insights, and develop repo-only PO guard/DateRange change.
## 2026-07-10 — InventorySnapshotWeekly DA proposed `dtea` grain re-opened (read-only audit; BLOCKED pending DA rule)

**User/DA hypothesis:**
- Current view/TableDictionary grain may be wrong.
- Candidate replacement: `ItemSku + WarehouseCode + dtea + FiscalMonth` instead of `ItemSku + WarehouseCode + SnapshotWeekEndingDate + FiscalMonth`.
- If raw EL key clean, user considered DemandForecast-style historical backfill + load-pattern migration + TableDictionary correction.

**Read-only full EL audit executed (no Fabric mutation):**
- Source: `Enterprise_Lakehouse.SupplyChain_Enh.DemandInventorySnapshotDaily`.
- Total raw rows: `4,232,005,200`.
- Proposed raw `dtea` grain is **not unique**: `8,604` duplicate groups / `8,604` extra rows.
- Collision dates:
  - `2025-04-10`: `7,200` groups.
  - `2026-02-25`: `1,404` groups.
- Each collision group has two rows; sampled payloads differ while sharing proposed key and `dtec`. No safe winner can be inferred without DA business rule.
- `dtea` is non-null. `13,619,592` rows have `CAST(dtea AS date) = CAST(dinSnapshot AS date) - 1`; this occurs on three historical source snapshot dates.
- Current Saturday + latest view output has 181 output dates, each mapped to exactly one `dtea`; output rows with `SnapshotDate <> CAST(dtea AS date)` = 0. The two collision dates are Wednesday/Thursday and are not selected by the present weekly/latest contract.
- Current physical Silver table does **not** contain a persisted `dtea` column. Replacing TD's key with `dtea` alone would reference a non-existent target column.

**Decision / do not:**
- **Do not update live TableDictionary.**
- **Do not remove/change current `ROW_NUMBER()` dedupe.**
- **Do not start a historical backfill** or treat P2 as DemandForecast-like solely from the proposed grain.
- Current contract remains valid only as the current contract: physical target matches its Wrk view and has zero duplicates at its declared snapshot-date grain.

**Required DA clarification before any design change:**
1. Is `dtea` a business as-of/snapshot date or a technical extract timestamp?
2. For same-`dtea` key collisions with differing payload, what is the deterministic business winner?
3. Should non-Saturday snapshots be included in historical weekly output, or does Saturday + latest remain the intended output contract?
4. If `dtea` must become persisted grain: approve target DDL, exact mapping, downstream impact, full historical rebuild and parity gates.

**Documentation:**
- Updated active plan: `01_docs/plans/2026-07-10-snapshot-load-pattern-migration-plan.md`, §3.2A.
## 2026-07-10 — Canonical full-refresh pipeline sync, monitored run, and CU/query-insights audit

**Approval and scope:**
- Aric explicitly approved live sync of `pl_backup_full_refresh` then a full pipeline run.
- Live mutation performed only for Fabric pipeline `updateDefinition`; all subsequent investigation was read-only Fabric REST/warehouse SQL.

**Pipeline drift found and fixed:**
- Before sync, live `pl_backup_full_refresh` was an obsolete 4-wrapper path: referenced W00, made Forecast depend on it, and skipped Inventory Silver W03.
- Synced `03_operations/orchestration/backup_pipeline/pl_backup_full_refresh.fabric_payload.json` to live item `41948342-d7e7-4166-8638-9af0633e6a49` in workspace `c8d9fc83-18b6-4e1d-8264-0b49eed36fe0`.
- Post-sync `getDefinition` verified exact canonical match: 10 serial activities, `01 Shared ReferenceMaster` → `02 Shared Staging` → Forecast W01/W02/W03 → Forecast Gold → Inventory W01/W02/W03 → Inventory Gold. `W00` absent.

**Full run result:**
- Run ID: `731d4761-cd94-4427-a521-d81da67570ef`.
- Started `2026-07-10 08:02:04.830896 UTC`; completed successfully `09:22:19.290 UTC`; runtime **80m 14s**.
- Previous successful full run `fcac7e40-60b4-47bd-a84d-06fef6fbbc53`: `2026-07-08 06:36:56.143016` → `08:31:42.590 UTC`; **114m 46s**.
- Improvement: **34m 32s faster** (about **30.1% lower runtime**), despite the new canonical pipeline now executing Inventory W03 that the prior live pipeline skipped.

**Inventory Gold bottleneck / Query Insights evidence:**
- All pipeline operations succeeded. Query Insights had one 6.337-second *Canceled* ad-hoc `TOP 100` read of `v_SupplyPlanOutageClassHelper`, unrelated to pipeline; no pipeline error.
- Gold warehouse capacity was F256; `is_pool_under_pressure` was true only 2/80 SELECT and 5/80 NONSELECT samples, so no sustained CU/capacity-pressure explanation.
- `Usp_Refresh_InventoryHealth_Gold` sequentially refreshes 9 objects. Current vs prior max elapsed times:
  - `FactInventoryHealthSnapshot`: **47m55s** vs 31m57s; 19.50M vs 19.21M target rows; scan 26.04GB vs 6.78GB. Primary bottleneck.
  - `FactInventoryHealthFutureWeekEnding`: **45m55s** vs 30m39s; 3.785M vs 3.785M rows. Secondary bottleneck.
  - `InventoryClassificationQtyWeekly`: **21m49s** vs 15m40s.
  - `InventoryHealthSubStatusWeekly`: **19m42s** vs 13m57s.
  - `ProjectedInventoryHealthSubStatus`: **17m26s** vs 11m59s.
- These Gold tables are still full refreshes; the DateRange improvements were applied upstream to DemandForecast/PO paths, not to these Inventory Gold target loads. Therefore the longer Inventory Gold stage is not regression evidence from the changed snapshot load patterns.

**Changed/backfilled data audit after the run:**
- `ForecastHistory_Enh.ForecastDemandMonthly`: 229,742,696 rows; history `2023-01-16` to `2026-06-15`; latest load `2026-07-10 08:09:39 UTC`; duplicate business-key groups = 0.
- `InventoryHistory_Enh.ForecastSnapshotWeekly`: 1,078,496,866 rows; history `2020-01-04` to `2026-07-04`; latest load `2026-07-10 08:15:56 UTC`.
- `InventoryHistory_Enh.PurchaseOrderSnapshotHistorical`: 40,733,444 rows inside the rolling 30-day window, latest load `2026-07-10 08:15:30 UTC`; 2,028,324,751 historical rows outside the window, whose last-load timestamp remained `2026-07-08 07:36:15 UTC` as intended (not rewritten). Outside-window quantity sums remained unchanged across this run; rolling-window duplicate business-key groups = 0.

**CU conclusion:**
- No sustained warehouse pool pressure, no Fabric pipeline failure, and no evidence that the new DemandForecast/PO patterns created CU instability.
- The large work remains the pre-existing full-overwrite Inventory Gold facts and their upstream views. Do not alter their pattern ad hoc; use the approved snapshot-load-pattern migration plan with semantic/late-arrival validation and Query Insights baseline before any DateRange change.

## 2026-07-10 21:56:48 ICT — Inventory Health Gold optimization scope redefined: business-parity audit system first

**User instruction / non-negotiable requirement:**
- Focus active work only on optimizing the Inventory Health Gold serving chain; PO DateRange is complete/live/validated and `InventorySnapshotWeekly` remains blocked/deferred until US/DA resolves its source-grain and duplicate tie-break semantics.
- Before proposing any Gold optimization, establish a thorough audit and check/test system for all Inventory Health Gold facts/helpers.
- Existing Gold logic may be complex because it satisfies the complete real business need. Any optimized implementation B must retain every business outcome presently delivered by implementation A; runtime reduction never justifies missing, approximated, or silently changed behavior.

**Decision / active plan:**
- Created `01_docs/plans/2026-07-10-inventory-gold-business-parity-optimization-plan.md` as the active source of truth for Gold performance work.
- The plan requires per-object business contracts, multi-run performance baselines, source/target integrity checks, full-versus-candidate row/value/metric/temporal parity, late-arrival and latest/as-of scenarios, downstream Direct Lake/`sc_control_tower` smoke checks, failure-path guards, performance proof, rollback, and explicit approval gates.
- Matching totals alone is insufficient; proof must include two-way business-key comparison, duplicate checks, row-level required business value comparison, reconciliation at several business grains, distribution/null checks, and unchanged historical areas when immutability is claimed.
- Candidate order is evidence-led: first read/map all nine Inventory Gold targets, then audit the known hotspots and only build a shadow candidate once a contract-preserving direction is proven. No blanket DateRange conversion, global framework SP change, semantic/report contract change, or unapproved live mutation.

**Evidence / risk status:**
- The 2026-07-10 canonical full run established Inventory Gold full-overwrite/query-shape work as the active bottleneck; it did not establish that Direct Lake semantic refresh itself is slow. Gold completion is confirmed as data-ready latency; semantic reframe/report-query duration must be separately measured before making a claim.
- No live mutation was made for this planning/context update.

**Next concrete step:**
- Sequentially catalogue every target in `dbo.Usp_Refresh_InventoryHealth_Gold`, extract business contracts and test specifications, then build/run the read-only baseline audit pack before proposing an optimization candidate.
