# Next Steps — Roadmap After Track A

**Status as of 2026-05-18**: Track A complete (14 code fixes applied). Production deploy blocked on (a) Robert business sign-off + (b) DE Bronze data load. 5 tracks remain.

---

## Roadmap overview

```
[Track A: Code fix]  ✅ DONE
       │
       ├─→ [Track D: Email Robert]  ⏳ CRITICAL PATH  (30 min)
       │       └─→ unblocks 3 fixes for production
       │
       ├─→ [DE chase: 4 sources]    ⏳ CRITICAL PATH  (15 min)
       │       └─→ unblocks Track B Tier-2 + Tier-4 snapshots
       │
       ↓
[Track B: Dev exec test + cleanup]  🔒 BLOCKED on D + DE   (3-5h)
       │
       ↓
[Track C: Power BI prototype]       🔒 BLOCKED on B        (2-3h)
       │
       ↓
[Track E: Runbook + schedule]       🔒 BLOCKED on C        (1-2h)
       │
       ↓
   [Production deploy]
```

---

## Track D — Email Robert (CRITICAL PATH, 30 min)

3 sign-off questions blocking production deploy. Each fix in Track A has a `Robert sign-off pending` marker.

### Question 1 — H1: ItemAllocationFlag value

> Robert,
> Probe của bảng `Wholesale_OrderManagement_AFI.OpenOrderDetail` cho thấy `ItemAllocationFlag` chỉ có 2 giá trị thực tế:
> - `0` (16,802 rows) — không allocated
> - `2` (901,411 rows) — allocated
>
> Không có giá trị `1` nào. Code ETL trước đây filter `= 1` → sẽ trả 0 row. Tôi đã sửa thành `= 2`.
>
> Anh xác nhận giúp: `ItemAllocationFlag = 2` đúng là "Allocated" theo business rule không, hay có giá trị khác cần xét?

### Question 2 — H5: WeekFourFlag interpretation

> BRD §6.3 Revenue at Risk định nghĩa: **"At Week Four Ending: [SINegQty] × [FOBPrice]"**.
>
> Có 2 cách hiểu:
> - **(A) Exact**: chỉ tuần thứ 4 (1 tuần, week-ending date = today + 28 days, làm tròn Saturday)
> - **(B) Range**: 4 tuần forward (week 1 → week 4, tổng 4 tuần)
>
> Hiện code đang implement (A) — exact week. Anh confirm giúp cách hiểu nào đúng theo business? Khác biệt: cách (B) sẽ inflate Revenue at Risk lên ~4×.

### Question 3 — M3: COGS rolling grain

> BRD nói "**52 weeks** trailing COGS" cho KPI #22 Inventory Turns.
>
> Implementation hiện tại: monthly grain với window `ROWS BETWEEN 51 PRECEDING AND CURRENT ROW` → effectively là **52 months** (~4.3 năm), không phải 52 weeks (~1 năm).
>
> Lý do Phase 1 chọn monthly: helper join với `gold.DimDate.FiscalMonthYear` → đơn giản, nhanh.
>
> 2 lựa chọn:
> - **(A) Keep 52M** (Phase 1, current): label measure rõ "COGS 52M Trailing" — accept gross simplification
> - **(B) Rewrite 52W**: rebuild helper ở weekly grain (Saturday week-ending), thêm join column `FiscalWeekYear`, accept ~30 min extra ETL time
>
> Anh chọn (A) hay (B)? Phase 1 ship cutoff là [DATE].

→ Aric: copy 3 question vào 1 email duy nhất, gửi Robert, cc anh Trưởng nhóm.

---

## DE chase — 4 missing/stale Bronze tables (15 min)

Tin nhắn ngắn sang DE team:

> Team DE,
>
> Bên DA cần 4 bảng để hoàn thiện Inventory Health ETL — đang block dev exec test:
>
> 1. **`Enterprise_Lakehouse.PoMaster`** — đã backfill `PoDetail` (21.95M rows) chưa load `PoMaster`?
> 2. **`Enterprise_Lakehouse.Inventory_Enh_History.ItemBalance`** — cho weekly historical inventory snapshot. Hiện chưa thấy trên lake.
> 3. **`SupplyChain_Lakehouse.LogilityItemStatus`** — bronze chưa load. Cho weekly Logility status snapshot.
> 4. **`SupplyChain_Enh.PurchaseOrderSnapshot`** — đang chỉ có trên EDW, anh sếp dùng cho PO-as-of query. Cần load lên lake.
>
> Mong team load giúp + cho ETA. Inventory Health timeline gấp.
>
> Cảm ơn,
> Aric

---

## Track B — Sandbox dev exec test (3-5h, blocked on D + DE)

### Phase 1: Compile-only static validation (1h, NOT blocked)

Có thể làm ngay trong khi chờ:

```sql
-- Trong dev WH (sandbox):
SET PARSEONLY ON;
:r sql/01_setup.sql
:r sql/02_silver_dims.sql
:r sql/03_silver_base.sql
:r sql/04_silver_helpers.sql
:r sql/05_silver_snapshots.sql
:r sql/09_master.sql
GO
SET PARSEONLY OFF;
-- → catches T-SQL syntax errors before any execution
```

Repeat trên Gold WH với `06 → 09`.

### Phase 2: Paper trace 3 reference combo (2h, NOT blocked)

Plan §4. Pull 3 SKU-WH từ Bronze, hand-compute expected Gold fact:

- **Combo 1**: Top OnHand SKU-WH — verify InventoryValueAtCost = MOHTQ × UCDEF
- **Combo 2**: Inactive candidate (AfiStatus IN 'D','R') — verify Classification logic
- **Combo 3**: SLOB candidate (LastInvoice < 17 weeks) — verify SlobFlag + ObsoleteValue

→ Đây là deliverable mà chỉ Aric làm được (cần manual math + BRD cross-ref). Output: 1 markdown table 3 row, "Expected vs Code formula" column.

### Phase 3: Full exec test (3-4h, BLOCKED on D + DE)

```sql
-- Sau khi Robert sign-off + DE load đủ:
:r sql/01_setup.sql
:r sql/02_silver_dims.sql
:r sql/03_silver_base.sql
:r sql/04_silver_helpers.sql
:r sql/05_silver_snapshots.sql
:r sql/09_master.sql
EXEC silver.usp_RefreshAll;   -- ~1h cho Tier 2

-- Trong Gold WH:
CREATE SCHEMA gold AUTHORIZATION dbo;
:r sql/06_gold_dims.sql
:r sql/07_gold_helpers.sql
:r sql/08_gold_facts.sql
:r sql/09_master.sql
EXEC gold.usp_RefreshAll;     -- ~30 min

-- Verify:
:r sql/10_verify.sql
```

### Phase 4: MANDATORY cleanup (15 min)

⚠️ Bắt buộc sau exec test trong dev:

```sql
:r sql/99_cleanup_silver.sql   -- Processing WH
:r sql/99_cleanup_gold.sql     -- Gold WH
```

Verify cleanup:
```sql
SELECT COUNT(*) FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_SCHEMA IN ('silver','gold');
-- expect 0
```

---

## Track C — Power BI prototype (2-3h, blocked on B)

1. Upload `04_semantic/SemanticModel.tmdl` qua Fabric API (`POST /workspaces/{id}/items` with TMDL parts)
2. Upload `04_semantic/Measures_DAX.dax` measures (paste into model via Tabular Editor hoặc API)
3. Refresh dataset (DirectLake mode)
4. Build dashboard skeleton:
   - Page 1: Health overview (OnHand, IVC, Classification distribution, SLOB ratio)
   - Page 2: Risk forward (Revenue at Risk W4, ATP rate, Shippable rate)
5. Smoke test 30 KPI render đúng (so vs F.1-F.7 trong [sql/10_verify.sql](sql/10_verify.sql))

---

## Track E — Runbook + monitoring (1-2h, blocked on C)

1. Wrap `usp_RefreshAll` vào Fabric Pipeline:
   - Daily 5AM UTC: `EXEC silver.usp_RefreshAll;` → `EXEC gold.usp_RefreshAll;`
   - Saturday 6AM UTC: same + verify Logility weekly snapshot fires
2. Write `runbook.md`:
   - Common errors + fixes
   - Freshness SLA (Bronze → Gold ≤ 24h)
   - Escalation: DE team for source issues, Aric for logic, Robert for BRD interpretation
3. Sentinel queries (Activator alerts):
   - Row count drop > 10% in any silver table → alert
   - `usp_RefreshAll` runtime > 2× baseline → alert
   - DimItem.OnHand sum delta > 20% day-over-day → alert

---

## Open dependencies dashboard

| Dependency | Owner | Status | Blocks |
|---|---|---|---|
| Robert sign-off H1 (ItemAllocationFlag=2) | Robert | ⏳ Email pending | Production deploy |
| Robert sign-off H5 (WeekFourFlag interpretation) | Robert | ⏳ Email pending | Production deploy |
| Robert sign-off M3 (Cogs52M vs Cogs52W grain) | Robert | ⏳ Email pending | Production deploy + Track C labeling |
| DE load `PoMaster` | DE team | ⏳ Chase msg pending | Track B partial (PO header data missing) |
| DE load `ItemBalance` | DE team | ⏳ Chase msg pending | Track B Tier-2 InventorySnapshotWeekly |
| DE load `LogilityItemStatus` | DE team | ⏳ Chase msg pending | Track B Tier-4 Logility weekly snapshot |
| DE load `PurchaseOrderSnapshot` | DE team | ⏳ Chase msg pending | Phase 2 PO-as-of feature |
| Robert sign-off MOMAST OSTAT firm list `('10','40','45')` | Robert | ⏳ Defer Phase 1 | L3 bug closure |

---

## Recommended order

Parallel:
1. **Today**: Send Track D email + DE chase message — unblocks Robert + DE async
2. **Today**: Phase 1 + Phase 2 of Track B (compile-only + paper trace) — no exec needed, can do now

Then sequential (after dependencies clear):
3. **Day +2**: Track B Phase 3 (full exec test) + Phase 4 (cleanup)
4. **Day +3**: Track C (Power BI prototype)
5. **Day +4**: Track E (runbook + schedule)
6. **Day +5**: Production deploy after sign-off review meeting

Total elapsed: ~1 week assuming Robert + DE respond within 24h.
