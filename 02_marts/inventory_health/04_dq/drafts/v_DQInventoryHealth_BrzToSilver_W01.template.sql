-- InventoryHealth BRZ-to-Silver W01 DQ template
-- Scope: SELECT-only draft. Do not deploy as a live view/table until reviewed.
-- Pattern follows ForecastAccuracy DQ view style:
--   run_meta -> supporting CTEs -> DQ UNION ALL rules -> final select.
--
-- Rule families:
--   DQ_Bronze_*      : raw Enterprise_Lakehouse source quality.
--   DQ_B2S_*         : eligible Bronze source after business filter/dedupe vs physical Silver table.
--   DQ_Silver_Grain_*: final Silver table grain/key contract.
--
-- Important: DQ_B2S_* intentionally does not read Silver work views. Work-view-to-table
-- load parity is an operational smoke check, not the Bronze-to-Silver DQ contract.
--
-- Cách đọc file này:
--   1) run_meta: tạo DQRunId/DQRunAtUTC chung cho toàn bộ batch DQ.
--   2) *_Expected: dựng expected output từ raw Bronze source sau khi apply filter/dedupe/business rule.
--   3) *_B2S: gom metric so sánh expected Bronze-derived output với bảng Silver physical.
--   4) DQ CTE: emit từng rule PASS/FAIL theo 3 cụm:
--      - DQ_Bronze_*: kiểm tra raw source có bẩn không.
--      - DQ_B2S_*: kiểm tra Bronze sau business transform có khớp Silver không.
--      - DQ_Silver_Grain_*: kiểm tra bảng Silver final đúng grain/key không.
--   5) Final SELECT: gắn metadata run vào từng rule result.

WITH
-- run_meta: chỉ tạo metadata của lần chạy DQ; không đụng tới dữ liệu business.
run_meta AS (
    SELECT
        -- DQRunId: gom 21 rule result vào cùng một batch.
        CAST(NEWID() AS uniqueidentifier) AS DQRunId,
        -- DQRunAtUTC: timestamp UTC chuẩn để lưu lịch sử DQ.
        CAST(SYSUTCDATETIME() AS datetime2(6)) AS DQRunAtUTC
),

-- =====================================================================
-- CỤM EXPECTED OUTPUT CHO DQ_B2S_*
-- Mục tiêu: không dùng work view; tự dựng expected output từ raw Bronze.
-- Các CTE này là "đáp án kỳ vọng" của Silver nếu Bronze -> Silver logic đúng.
-- =====================================================================

-- Calendar_Expected:
--   Source raw: Enterprise_Lakehouse.MasterData_DW.DimDate.
--   Business rule: chỉ giữ dòng có DateKey, cast DateKey/DateID đúng kiểu Silver.
--   Grain kỳ vọng: 1 dòng cho mỗi SKDate/Date.
Calendar_Expected AS (
    SELECT
        CAST(DateKey AS INT) AS SKDate,
        CAST(DateID AS DATE) AS Date
    FROM Enterprise_Lakehouse.MasterData_DW.DimDate
    WHERE DateKey IS NOT NULL
),

-- Warehouse_Expected:
--   Source raw: CustomerOrders_AFI.WarehouseMaster.
--   Business rule: bỏ Warehouse null/blank, trim và cast thành WarehouseCode.
--   DISTINCT dùng để expected key set không bị phình bởi duplicate raw source.
Warehouse_Expected AS (
    SELECT DISTINCT
        CAST(RTRIM(Warehouse) AS VARCHAR(50)) AS WarehouseCode
    FROM Enterprise_Lakehouse.CustomerOrders_AFI.WarehouseMaster
    WHERE NULLIF(TRIM(Warehouse), '') IS NOT NULL
),

-- Vendor_Expected:
--   Source raw: Purchasing_AFI.VendorMaster.
--   Business rule: bỏ VendorNumber null/blank, trim/cast thành key Silver.
--   Grain kỳ vọng: 1 dòng cho mỗi VendorNumber.
Vendor_Expected AS (
    SELECT DISTINCT
        CAST(TRIM(VendorNumber) AS VARCHAR(50)) AS VendorNumber
    FROM Enterprise_Lakehouse.Purchasing_AFI.VendorMaster
    WHERE NULLIF(TRIM(VendorNumber), '') IS NOT NULL
),

-- CustomerAccountGroup_Expected:
--   Source raw: Wholesale_ProductSourcing_AFI.CustomerGrouping.
--   Business rule: CustomerNumber/CustomerGroup phải có giá trị,
--                  CustomerGroup được upper-case giống Silver transform.
--   Grain kỳ vọng: 1 dòng cho mỗi (Customer, CustomerGroupCode).
CustomerAccountGroup_Expected AS (
    SELECT DISTINCT
        CAST(TRIM(CustomerNumber) AS VARCHAR(8000)) AS Customer,
        CAST(UPPER(TRIM(CustomerGroup)) AS VARCHAR(8000)) AS CustomerGroupCode
    FROM Enterprise_Lakehouse.Wholesale_ProductSourcing_AFI.CustomerGrouping
    WHERE NULLIF(TRIM(CustomerNumber), '') IS NOT NULL
      AND NULLIF(TRIM(CustomerGroup), '') IS NOT NULL
),

-- ItemMaster_Expected:
--   Source raw: MasterData_DW.DimItemMaster + ItemMaster_AFI.ITMEXT.
--   Business rule: lấy tập item key hợp lệ từ cả 2 source, UNION để dedupe key.
--   Lưu ý: DQ_B2S ở đây check key coverage, không check toàn bộ attribute item.
ItemMaster_Expected AS (
    SELECT ItemSKU
    FROM (
        SELECT CAST(TRIM(CAST(ItemSKU AS VARCHAR(8000))) AS VARCHAR(50)) AS ItemSKU
        FROM Enterprise_Lakehouse.MasterData_DW.DimItemMaster
        WHERE NULLIF(TRIM(CAST(ItemSKU AS VARCHAR(8000))), '') IS NOT NULL
        UNION
        SELECT CAST(TRIM(CAST(ITNBR AS VARCHAR(8000))) AS VARCHAR(50)) AS ItemSKU
        FROM Enterprise_Lakehouse.ItemMaster_AFI.ITMEXT
        WHERE NULLIF(TRIM(CAST(ITNBR AS VARCHAR(8000))), '') IS NOT NULL
    ) src
),

-- InventorySnapshot_Latest:
--   Tìm latest inventory snapshot hợp lệ <= D-1 UTC.
--   CTE này mirror rule của Silver W01: giữ historical Saturday snapshots
--   và giữ latest effective snapshot.
InventorySnapshot_Latest AS (
    SELECT MAX(CAST(dinSnapshot AS DATE)) AS LatestInventorySnapshotDate
    FROM Enterprise_Lakehouse.SupplyChain_Enh.DemandInventorySnapshotDaily
    WHERE CAST(dinSnapshot AS DATE) <= DATEADD(day, -1, CAST(SYSUTCDATETIME() AS DATE))
),

-- InventorySnapshot_SourceRows:
--   Dựng tập raw rows đủ điều kiện để đi vào Silver InventorySnapshotWeekly.
--   Filter chính:
--     - item/warehouse/fiscal month usable.
--     - snapshot là Saturday hoặc là latest effective snapshot.
--   dtec/dtea được giữ lại để dedupe chọn bản mới nhất trong CTE sau.
InventorySnapshot_SourceRows AS (
    SELECT
        CAST(TRIM(dinItem) AS VARCHAR(50)) AS ItemSku,
        CAST(TRIM(dinWarehouse) AS VARCHAR(50)) AS WarehouseCode,
        CAST(dinSnapshot AS DATE) AS SnapshotDate,
        CAST(dinSnapshot AS DATE) AS SnapshotWeekEndingDate,
        CAST(dinFiscalMonth AS INT) AS FiscalMonth,
        CAST(dinOnHandQuantity AS DECIMAL(18,4)) AS OnHandQty,
        CAST(dinSafetyStock AS DECIMAL(18,4)) AS SafetyStockTarget,
        CAST(dinOrderQuantity AS DECIMAL(18,4)) AS OrderQty,
        dtec,
        dtea
    FROM Enterprise_Lakehouse.SupplyChain_Enh.DemandInventorySnapshotDaily
    CROSS JOIN InventorySnapshot_Latest
    WHERE NULLIF(TRIM(dinItem), '') IS NOT NULL
      AND NULLIF(TRIM(dinWarehouse), '') IS NOT NULL
      AND dinFiscalMonth IS NOT NULL
      AND (
            ((DATEDIFF(day, CAST('19000101' AS DATE), CAST(dinSnapshot AS DATE)) % 7) + 1) = 6
         OR CAST(dinSnapshot AS DATE) = LatestInventorySnapshotDate
      )
),

-- InventorySnapshot_Expected:
--   Dedupe raw eligible rows theo grain Silver:
--     (ItemSku, WarehouseCode, SnapshotWeekEndingDate, FiscalMonth).
--   Nếu source có nhiều dòng cùng grain, chọn dòng mới nhất theo dtec/dtea.
InventorySnapshot_Expected AS (
    SELECT
        ItemSku,
        WarehouseCode,
        SnapshotDate,
        SnapshotWeekEndingDate,
        FiscalMonth,
        OnHandQty,
        SafetyStockTarget,
        OrderQty
    FROM (
        SELECT
            *,
            ROW_NUMBER() OVER (
                PARTITION BY ItemSku, WarehouseCode, SnapshotWeekEndingDate, FiscalMonth
                ORDER BY dtec DESC, dtea DESC
            ) AS rn
        FROM InventorySnapshot_SourceRows
    ) ranked
    WHERE rn = 1
),

-- Atp_Latest:
--   Tìm latest ATP snapshot hợp lệ <= D-1 UTC, chỉ cho InsertedVersion = 2.
--   Đây là rule source chính của Silver AtpWeekEnding.
Atp_Latest AS (
    SELECT MAX(CAST(InsertedDate AS DATE)) AS LatestAtpSnapshotDate
    FROM Enterprise_Lakehouse.SupplyChain_Enh.ATPWeekEnding
    WHERE InsertedDate IS NOT NULL
      AND CAST(InsertedVersion AS INT) = 2
      AND CAST(InsertedDate AS DATE) <= DATEADD(day, -1, CAST(SYSUTCDATETIME() AS DATE))
),

-- Atp_SourceRows:
--   Dựng tập raw ATP rows đủ điều kiện để đi vào Silver:
--     - key bắt buộc usable.
--     - InsertedVersion = 2.
--     - giữ Week2 Saturday historical snapshots hoặc latest effective snapshot.
--   InsertedDateTime/SourceRunDate dùng để chọn bản mới nhất khi dedupe.
Atp_SourceRows AS (
    SELECT
        CAST(TRIM(ItemSKU) AS VARCHAR(50)) AS ItemSku,
        CAST(TRIM(Warehouse) AS VARCHAR(50)) AS WarehouseCode,
        CAST(InsertedDate AS DATE) AS SnapshotDate,
        CAST(TRIM(ATPWeek) AS VARCHAR(20)) AS ATPWeek,
        CAST(WeekEnding AS DATE) AS WeekEndingDate,
        CAST(ATPQty AS DECIMAL(18,4)) AS AtpQty,
        CAST(APNQ AS DECIMAL(18,4)) AS APNQ,
        CAST(InsertedDate AS DATETIME2(6)) AS InsertedDateTime,
        CAST(InsertedVersion AS INT) AS InsertedVersion,
        CAST(RunDate AS DATE) AS SourceRunDate
    FROM Enterprise_Lakehouse.SupplyChain_Enh.ATPWeekEnding
    CROSS JOIN Atp_Latest
    WHERE NULLIF(TRIM(ItemSKU), '') IS NOT NULL
      AND NULLIF(TRIM(Warehouse), '') IS NOT NULL
      AND InsertedDate IS NOT NULL
      AND WeekEnding IS NOT NULL
      AND ATPWeek IS NOT NULL
      AND InsertedVersion IS NOT NULL
      AND CAST(InsertedVersion AS INT) = 2
      AND (
            (
                TRIM(ATPWeek) = 'Week2'
                AND ((DATEDIFF(day, CAST('19000101' AS DATE), CAST(InsertedDate AS DATE)) % 7) + 1) = 6
            )
         OR CAST(InsertedDate AS DATE) = LatestAtpSnapshotDate
      )
),

-- Atp_Expected:
--   Dedupe raw eligible rows theo grain Silver ATP:
--     (ItemSku, WarehouseCode, SnapshotDate, ATPWeek, WeekEndingDate, InsertedVersion).
--   Nếu nhiều dòng cùng grain, chọn dòng mới nhất theo InsertedDateTime/RunDate/AtpQty.
Atp_Expected AS (
    SELECT
        ItemSku,
        WarehouseCode,
        SnapshotDate,
        ATPWeek,
        WeekEndingDate,
        InsertedVersion,
        AtpQty,
        APNQ
    FROM (
        SELECT
            *,
            ROW_NUMBER() OVER (
                PARTITION BY ItemSku, WarehouseCode, SnapshotDate, ATPWeek, WeekEndingDate, InsertedVersion
                ORDER BY InsertedDateTime DESC, SourceRunDate DESC, AtpQty DESC
            ) AS rn
        FROM Atp_SourceRows
    ) ranked
    WHERE rn = 1
),

-- =====================================================================
-- CỤM METRIC SO SÁNH CHO DQ_B2S_*
-- Mục tiêu: chuẩn bị row count, missing/extra key, và aggregate qty
-- để DQ_B2S_* chỉ cần đọc metric và trả PASS/FAIL.
-- =====================================================================

-- Calendar_B2S:
--   So expected raw-derived SKDate/Date với Silver Calendar.
--   MissingInSilver > 0: raw-derived key có nhưng Silver thiếu.
--   ExtraInSilver > 0: Silver có key không nằm trong raw-derived expected set.
Calendar_B2S AS (
    SELECT
        (SELECT COUNT_BIG(*) FROM Calendar_Expected) AS ExpectedRows,
        (SELECT COUNT_BIG(*) FROM ReferenceMaster_Enh.Calendar) AS ActualRows,
        (SELECT COUNT_BIG(*) FROM (
            SELECT SKDate, Date FROM Calendar_Expected
            EXCEPT
            SELECT SKDate, Date FROM ReferenceMaster_Enh.Calendar
        ) x) AS MissingInSilver,
        (SELECT COUNT_BIG(*) FROM (
            SELECT SKDate, Date FROM ReferenceMaster_Enh.Calendar
            EXCEPT
            SELECT SKDate, Date FROM Calendar_Expected
        ) x) AS ExtraInSilver
),

-- Warehouse_B2S:
--   So expected WarehouseCode từ raw WarehouseMaster với Silver Warehouse.
Warehouse_B2S AS (
    SELECT
        (SELECT COUNT_BIG(*) FROM Warehouse_Expected) AS ExpectedRows,
        (SELECT COUNT_BIG(*) FROM ReferenceMaster_Enh.Warehouse) AS ActualRows,
        (SELECT COUNT_BIG(*) FROM (
            SELECT WarehouseCode FROM Warehouse_Expected
            EXCEPT
            SELECT WarehouseCode FROM ReferenceMaster_Enh.Warehouse
        ) x) AS MissingInSilver,
        (SELECT COUNT_BIG(*) FROM (
            SELECT WarehouseCode FROM ReferenceMaster_Enh.Warehouse
            EXCEPT
            SELECT WarehouseCode FROM Warehouse_Expected
        ) x) AS ExtraInSilver
),

-- Vendor_B2S:
--   So expected VendorNumber từ raw VendorMaster với Silver Vendor.
Vendor_B2S AS (
    SELECT
        (SELECT COUNT_BIG(*) FROM Vendor_Expected) AS ExpectedRows,
        (SELECT COUNT_BIG(*) FROM ReferenceMaster_Enh.Vendor) AS ActualRows,
        (SELECT COUNT_BIG(*) FROM (
            SELECT VendorNumber FROM Vendor_Expected
            EXCEPT
            SELECT VendorNumber FROM ReferenceMaster_Enh.Vendor
        ) x) AS MissingInSilver,
        (SELECT COUNT_BIG(*) FROM (
            SELECT VendorNumber FROM ReferenceMaster_Enh.Vendor
            EXCEPT
            SELECT VendorNumber FROM Vendor_Expected
        ) x) AS ExtraInSilver
),

-- CustomerAccountGroup_B2S:
--   So expected (Customer, CustomerGroupCode) từ raw CustomerGrouping với Silver.
CustomerAccountGroup_B2S AS (
    SELECT
        (SELECT COUNT_BIG(*) FROM CustomerAccountGroup_Expected) AS ExpectedRows,
        (SELECT COUNT_BIG(*) FROM ReferenceMaster_Enh.CustomerAccountGroup) AS ActualRows,
        (SELECT COUNT_BIG(*) FROM (
            SELECT Customer, CustomerGroupCode FROM CustomerAccountGroup_Expected
            EXCEPT
            SELECT Customer, CustomerGroupCode FROM ReferenceMaster_Enh.CustomerAccountGroup
        ) x) AS MissingInSilver,
        (SELECT COUNT_BIG(*) FROM (
            SELECT Customer, CustomerGroupCode FROM ReferenceMaster_Enh.CustomerAccountGroup
            EXCEPT
            SELECT Customer, CustomerGroupCode FROM CustomerAccountGroup_Expected
        ) x) AS ExtraInSilver
),

-- ItemMaster_B2S:
--   So expected ItemSKU coverage từ 2 raw item sources với Silver ItemMaster.
ItemMaster_B2S AS (
    SELECT
        (SELECT COUNT_BIG(*) FROM ItemMaster_Expected) AS ExpectedRows,
        (SELECT COUNT_BIG(*) FROM ReferenceMaster_Enh.ItemMaster) AS ActualRows,
        (SELECT COUNT_BIG(*) FROM (
            SELECT ItemSKU FROM ItemMaster_Expected
            EXCEPT
            SELECT ItemSKU FROM ReferenceMaster_Enh.ItemMaster
        ) x) AS MissingInSilver,
        (SELECT COUNT_BIG(*) FROM (
            SELECT ItemSKU FROM ReferenceMaster_Enh.ItemMaster
            EXCEPT
            SELECT ItemSKU FROM ItemMaster_Expected
        ) x) AS ExtraInSilver
),

-- InventorySnapshot_B2S:
--   So expected deduped inventory snapshot với Silver InventorySnapshotWeekly.
--   Check gồm:
--     - row count.
--     - key grain missing/extra.
--     - tổng các quantity chính.
--     - max SnapshotDate.
InventorySnapshot_B2S AS (
    SELECT
        (SELECT COUNT_BIG(*) FROM InventorySnapshot_Expected) AS ExpectedRows,
        (SELECT COUNT_BIG(*) FROM InventoryHistory_Enh.InventorySnapshotWeekly) AS ActualRows,
        (SELECT COUNT_BIG(*) FROM (
            SELECT ItemSku, WarehouseCode, SnapshotWeekEndingDate, FiscalMonth FROM InventorySnapshot_Expected
            EXCEPT
            SELECT ItemSku, WarehouseCode, SnapshotWeekEndingDate, FiscalMonth FROM InventoryHistory_Enh.InventorySnapshotWeekly
        ) x) AS MissingInSilver,
        (SELECT COUNT_BIG(*) FROM (
            SELECT ItemSku, WarehouseCode, SnapshotWeekEndingDate, FiscalMonth FROM InventoryHistory_Enh.InventorySnapshotWeekly
            EXCEPT
            SELECT ItemSku, WarehouseCode, SnapshotWeekEndingDate, FiscalMonth FROM InventorySnapshot_Expected
        ) x) AS ExtraInSilver,
        (SELECT COALESCE(SUM(CAST(OnHandQty AS decimal(38,4))), 0) FROM InventorySnapshot_Expected) AS ExpectedOnHandQty,
        (SELECT COALESCE(SUM(CAST(OnHandQty AS decimal(38,4))), 0) FROM InventoryHistory_Enh.InventorySnapshotWeekly) AS ActualOnHandQty,
        (SELECT COALESCE(SUM(CAST(SafetyStockTarget AS decimal(38,4))), 0) FROM InventorySnapshot_Expected) AS ExpectedSafetyStock,
        (SELECT COALESCE(SUM(CAST(SafetyStockTarget AS decimal(38,4))), 0) FROM InventoryHistory_Enh.InventorySnapshotWeekly) AS ActualSafetyStock,
        (SELECT COALESCE(SUM(CAST(OrderQty AS decimal(38,4))), 0) FROM InventorySnapshot_Expected) AS ExpectedOrderQty,
        (SELECT COALESCE(SUM(CAST(OrderQty AS decimal(38,4))), 0) FROM InventoryHistory_Enh.InventorySnapshotWeekly) AS ActualOrderQty,
        (SELECT MAX(SnapshotDate) FROM InventorySnapshot_Expected) AS ExpectedMaxSnapshotDate,
        (SELECT MAX(SnapshotDate) FROM InventoryHistory_Enh.InventorySnapshotWeekly) AS ActualMaxSnapshotDate
),

-- Atp_B2S:
--   So expected deduped ATP với Silver AtpWeekEnding.
--   Check gồm row count, key grain missing/extra, AtpQty/APNQ totals, max SnapshotDate.
Atp_B2S AS (
    SELECT
        (SELECT COUNT_BIG(*) FROM Atp_Expected) AS ExpectedRows,
        (SELECT COUNT_BIG(*) FROM InventoryHistory_Enh.AtpWeekEnding) AS ActualRows,
        (SELECT COUNT_BIG(*) FROM (
            SELECT ItemSku, WarehouseCode, SnapshotDate, ATPWeek, WeekEndingDate, InsertedVersion FROM Atp_Expected
            EXCEPT
            SELECT ItemSku, WarehouseCode, SnapshotDate, ATPWeek, WeekEndingDate, InsertedVersion FROM InventoryHistory_Enh.AtpWeekEnding
        ) x) AS MissingInSilver,
        (SELECT COUNT_BIG(*) FROM (
            SELECT ItemSku, WarehouseCode, SnapshotDate, ATPWeek, WeekEndingDate, InsertedVersion FROM InventoryHistory_Enh.AtpWeekEnding
            EXCEPT
            SELECT ItemSku, WarehouseCode, SnapshotDate, ATPWeek, WeekEndingDate, InsertedVersion FROM Atp_Expected
        ) x) AS ExtraInSilver,
        (SELECT COALESCE(SUM(CAST(AtpQty AS decimal(38,4))), 0) FROM Atp_Expected) AS ExpectedAtpQty,
        (SELECT COALESCE(SUM(CAST(AtpQty AS decimal(38,4))), 0) FROM InventoryHistory_Enh.AtpWeekEnding) AS ActualAtpQty,
        (SELECT COALESCE(SUM(CAST(APNQ AS decimal(38,4))), 0) FROM Atp_Expected) AS ExpectedAPNQ,
        (SELECT COALESCE(SUM(CAST(APNQ AS decimal(38,4))), 0) FROM InventoryHistory_Enh.AtpWeekEnding) AS ActualAPNQ,
        (SELECT MAX(SnapshotDate) FROM Atp_Expected) AS ExpectedMaxSnapshotDate,
        (SELECT MAX(SnapshotDate) FROM InventoryHistory_Enh.AtpWeekEnding) AS ActualMaxSnapshotDate
),

DQ AS (
    -- =================================================================
    -- CỤM 1: DQ_Bronze_*
    -- Ý nghĩa: kiểm tra raw Enterprise_Lakehouse source có dirty không.
    -- Đây không kết luận Silver sai; nó chỉ nói source gốc có vấn đề.
    -- =================================================================

    -- DQ_Bronze_Grain_Calendar:
    --   FAIL nếu raw DimDate có DateKey/CalendarDate null hoặc duplicate key/date.
    SELECT
        'DQ_Bronze_Grain_Calendar' AS RuleName,
        'Raw DimDate must have non-null DateKey/CalendarDate and be unique by DateKey and CalendarDate' AS RuleDescription,
        CASE WHEN EXISTS (
                    SELECT 1 FROM Enterprise_Lakehouse.MasterData_DW.DimDate
                    WHERE DateKey IS NULL OR CalendarDate IS NULL
                )
               OR EXISTS (
                    SELECT DateKey FROM Enterprise_Lakehouse.MasterData_DW.DimDate
                    GROUP BY DateKey
                    HAVING COUNT_BIG(*) > 1
                )
               OR EXISTS (
                    SELECT CalendarDate FROM Enterprise_Lakehouse.MasterData_DW.DimDate
                    GROUP BY CalendarDate
                    HAVING COUNT_BIG(*) > 1
                )
             THEN 'FAIL' ELSE 'PASS' END AS Result
    UNION ALL

    -- DQ_Bronze_Grain_Warehouse:
    --   FAIL nếu raw WarehouseMaster có Warehouse blank/null hoặc duplicate Warehouse.
    --   Đây là nơi hôm trước fail vì source có 1 dòng Warehouse blank/null.
    SELECT
        'DQ_Bronze_Grain_Warehouse',
        'Raw WarehouseMaster must be unique by Warehouse and key not blank',
        CASE WHEN EXISTS (
                    SELECT 1 FROM Enterprise_Lakehouse.CustomerOrders_AFI.WarehouseMaster
                    WHERE NULLIF(TRIM(Warehouse), '') IS NULL
                )
               OR EXISTS (
                    SELECT Warehouse FROM Enterprise_Lakehouse.CustomerOrders_AFI.WarehouseMaster
                    GROUP BY Warehouse
                    HAVING COUNT_BIG(*) > 1
                )
             THEN 'FAIL' ELSE 'PASS' END
    UNION ALL

    -- DQ_Bronze_Grain_Vendor:
    --   FAIL nếu raw VendorMaster có VendorNumber blank/null hoặc duplicate.
    SELECT
        'DQ_Bronze_Grain_Vendor',
        'Raw VendorMaster must be unique by VendorNumber and key not blank',
        CASE WHEN EXISTS (
                    SELECT 1 FROM Enterprise_Lakehouse.Purchasing_AFI.VendorMaster
                    WHERE NULLIF(TRIM(VendorNumber), '') IS NULL
                )
               OR EXISTS (
                    SELECT VendorNumber FROM Enterprise_Lakehouse.Purchasing_AFI.VendorMaster
                    GROUP BY VendorNumber
                    HAVING COUNT_BIG(*) > 1
                )
             THEN 'FAIL' ELSE 'PASS' END
    UNION ALL

    -- DQ_Bronze_Grain_CustomerAccountGroup:
    --   FAIL nếu CustomerNumber/CustomerGroup blank/null hoặc duplicate source grain.
    SELECT
        'DQ_Bronze_Grain_CustomerAccountGroup',
        'Raw CustomerGrouping must be unique by (CustomerNumber, CustomerGroup) and keys not blank',
        CASE WHEN EXISTS (
                    SELECT 1 FROM Enterprise_Lakehouse.Wholesale_ProductSourcing_AFI.CustomerGrouping
                    WHERE NULLIF(TRIM(CustomerNumber), '') IS NULL
                       OR NULLIF(TRIM(CustomerGroup), '') IS NULL
                )
               OR EXISTS (
                    SELECT CustomerNumber, CustomerGroup
                    FROM Enterprise_Lakehouse.Wholesale_ProductSourcing_AFI.CustomerGrouping
                    GROUP BY CustomerNumber, CustomerGroup
                    HAVING COUNT_BIG(*) > 1
                )
             THEN 'FAIL' ELSE 'PASS' END
    UNION ALL

    -- DQ_Bronze_Grain_ItemMaster_SourceKeys:
    --   FAIL nếu raw item key không usable.
    --   DimItemMaster được check duplicate ItemSKU vì đây là primary source priority.
    --   ITMEXT hiện check null/blank key để đảm bảo source phụ có key usable.
    SELECT
        'DQ_Bronze_Grain_ItemMaster_SourceKeys',
        'Raw item master sources must have usable item keys; primary DimItemMaster ItemSKU must be unique',
        CASE WHEN EXISTS (
                    SELECT 1 FROM Enterprise_Lakehouse.MasterData_DW.DimItemMaster
                    WHERE NULLIF(TRIM(ItemSKU), '') IS NULL
                )
               OR EXISTS (
                    SELECT ItemSKU FROM Enterprise_Lakehouse.MasterData_DW.DimItemMaster
                    GROUP BY ItemSKU
                    HAVING COUNT_BIG(*) > 1
                )
               OR EXISTS (
                    SELECT 1 FROM Enterprise_Lakehouse.ItemMaster_AFI.ITMEXT
                    WHERE ITNBR IS NULL OR TRIM(CAST(ITNBR AS varchar(8000))) = ''
                )
             THEN 'FAIL' ELSE 'PASS' END
    UNION ALL

    -- DQ_Bronze_Grain_DemandInventorySnapshotDaily:
    --   FAIL nếu raw inventory snapshot thiếu key bắt buộc hoặc duplicate source grain.
    --   Duplicate ở raw có thể vẫn được Silver dedupe; rule này chỉ ghi nhận source dirty.
    SELECT
        'DQ_Bronze_Grain_DemandInventorySnapshotDaily',
        'Raw DemandInventorySnapshotDaily must have usable snapshot/item/warehouse/fiscal month keys and no duplicate source grain before Silver dedupe',
        CASE WHEN EXISTS (
                    SELECT 1 FROM Enterprise_Lakehouse.SupplyChain_Enh.DemandInventorySnapshotDaily
                    WHERE dinSnapshot IS NULL
                       OR NULLIF(TRIM(dinItem), '') IS NULL
                       OR NULLIF(TRIM(dinWarehouse), '') IS NULL
                       OR dinFiscalMonth IS NULL
                )
               OR EXISTS (
                    SELECT dinSnapshot, dinItem, dinWarehouse, dinFiscalMonth
                    FROM Enterprise_Lakehouse.SupplyChain_Enh.DemandInventorySnapshotDaily
                    WHERE dinSnapshot IS NOT NULL
                      AND NULLIF(TRIM(dinItem), '') IS NOT NULL
                      AND NULLIF(TRIM(dinWarehouse), '') IS NOT NULL
                      AND dinFiscalMonth IS NOT NULL
                    GROUP BY dinSnapshot, dinItem, dinWarehouse, dinFiscalMonth
                    HAVING COUNT_BIG(*) > 1
                )
             THEN 'FAIL' ELSE 'PASS' END
    UNION ALL

    -- DQ_Bronze_Grain_ATPWeekEnding:
    --   FAIL nếu raw ATP thiếu key bắt buộc hoặc duplicate source grain.
    --   Silver có filter version/week/latest và dedupe riêng ở B2S/Silver Grain.
    SELECT
        'DQ_Bronze_Grain_ATPWeekEnding',
        'Raw ATPWeekEnding must have usable item/warehouse/snapshot/week/version keys and no duplicate source grain before Silver dedupe',
        CASE WHEN EXISTS (
                    SELECT 1 FROM Enterprise_Lakehouse.SupplyChain_Enh.ATPWeekEnding
                    WHERE NULLIF(TRIM(ItemSKU), '') IS NULL
                       OR NULLIF(TRIM(Warehouse), '') IS NULL
                       OR InsertedDate IS NULL
                       OR WeekEnding IS NULL
                       OR ATPWeek IS NULL
                       OR InsertedVersion IS NULL
                )
               OR EXISTS (
                    SELECT WeekEnding, RunDate, InsertedDate, ItemSKU, Warehouse, AFIFinanceDivision, ATPWeek, InsertedVersion
                    FROM Enterprise_Lakehouse.SupplyChain_Enh.ATPWeekEnding
                    WHERE NULLIF(TRIM(ItemSKU), '') IS NOT NULL
                      AND NULLIF(TRIM(Warehouse), '') IS NOT NULL
                      AND InsertedDate IS NOT NULL
                      AND WeekEnding IS NOT NULL
                      AND ATPWeek IS NOT NULL
                      AND InsertedVersion IS NOT NULL
                    GROUP BY WeekEnding, RunDate, InsertedDate, ItemSKU, Warehouse, AFIFinanceDivision, ATPWeek, InsertedVersion
                    HAVING COUNT_BIG(*) > 1
                )
             THEN 'FAIL' ELSE 'PASS' END

    UNION ALL

    -- =================================================================
    -- CỤM 2: DQ_B2S_*
    -- Ý nghĩa: kiểm tra Bronze sau business transform có khớp Silver không.
    -- Quan trọng: không dùng Silver work view; expected được dựng từ raw Bronze.
    -- PASS nghĩa là physical Silver khớp expected output từ raw source + rule.
    -- =================================================================

    -- DQ_B2S_Calendar_KeySet:
    --   PASS nếu expected SKDate/Date từ raw DimDate khớp Silver Calendar.
    SELECT
        'DQ_B2S_Calendar_KeySet',
        'Eligible raw DimDate SKDate/Date keys must match Silver Calendar',
        CASE WHEN (SELECT ExpectedRows FROM Calendar_B2S) = (SELECT ActualRows FROM Calendar_B2S)
               AND (SELECT MissingInSilver FROM Calendar_B2S) = 0
               AND (SELECT ExtraInSilver FROM Calendar_B2S) = 0
             THEN 'PASS' ELSE 'FAIL' END
    UNION ALL

    -- DQ_B2S_Warehouse_KeySet:
    --   PASS nếu non-blank Warehouse keys từ raw WarehouseMaster khớp Silver Warehouse.
    SELECT
        'DQ_B2S_Warehouse_KeySet',
        'Eligible raw WarehouseMaster non-blank Warehouse keys must match Silver Warehouse',
        CASE WHEN (SELECT ExpectedRows FROM Warehouse_B2S) = (SELECT ActualRows FROM Warehouse_B2S)
               AND (SELECT MissingInSilver FROM Warehouse_B2S) = 0
               AND (SELECT ExtraInSilver FROM Warehouse_B2S) = 0
             THEN 'PASS' ELSE 'FAIL' END
    UNION ALL

    -- DQ_B2S_Vendor_KeySet:
    --   PASS nếu VendorNumber keys từ raw VendorMaster khớp Silver Vendor.
    SELECT
        'DQ_B2S_Vendor_KeySet',
        'Eligible raw VendorMaster non-blank VendorNumber keys must match Silver Vendor',
        CASE WHEN (SELECT ExpectedRows FROM Vendor_B2S) = (SELECT ActualRows FROM Vendor_B2S)
               AND (SELECT MissingInSilver FROM Vendor_B2S) = 0
               AND (SELECT ExtraInSilver FROM Vendor_B2S) = 0
             THEN 'PASS' ELSE 'FAIL' END
    UNION ALL

    -- DQ_B2S_CustomerAccountGroup_KeySet:
    --   PASS nếu customer/group keys từ raw CustomerGrouping khớp Silver CAG.
    SELECT
        'DQ_B2S_CustomerAccountGroup_KeySet',
        'Eligible raw CustomerGrouping customer/group keys must match Silver CustomerAccountGroup',
        CASE WHEN (SELECT ExpectedRows FROM CustomerAccountGroup_B2S) = (SELECT ActualRows FROM CustomerAccountGroup_B2S)
               AND (SELECT MissingInSilver FROM CustomerAccountGroup_B2S) = 0
               AND (SELECT ExtraInSilver FROM CustomerAccountGroup_B2S) = 0
             THEN 'PASS' ELSE 'FAIL' END
    UNION ALL

    -- DQ_B2S_ItemMaster_KeySet:
    --   PASS nếu item key coverage từ DimItemMaster + ITMEXT khớp Silver ItemMaster.
    SELECT
        'DQ_B2S_ItemMaster_KeySet',
        'Eligible raw DimItemMaster plus ITMEXT item keys must match Silver ItemMaster',
        CASE WHEN (SELECT ExpectedRows FROM ItemMaster_B2S) = (SELECT ActualRows FROM ItemMaster_B2S)
               AND (SELECT MissingInSilver FROM ItemMaster_B2S) = 0
               AND (SELECT ExtraInSilver FROM ItemMaster_B2S) = 0
             THEN 'PASS' ELSE 'FAIL' END
    UNION ALL

    -- DQ_B2S_InventorySnapshotWeekly_Qty:
    --   PASS nếu raw DemandInventory sau filter Saturday/latest + dedupe khớp Silver:
    --     row count, grain keyset, max snapshot, và các quantity chính.
    SELECT
        'DQ_B2S_InventorySnapshotWeekly_Qty',
        'Eligible raw DemandInventory weekly/latest deduped grain, max snapshot, and key quantities must match Silver InventorySnapshotWeekly',
        CASE WHEN (SELECT ExpectedRows FROM InventorySnapshot_B2S) = (SELECT ActualRows FROM InventorySnapshot_B2S)
               AND (SELECT MissingInSilver FROM InventorySnapshot_B2S) = 0
               AND (SELECT ExtraInSilver FROM InventorySnapshot_B2S) = 0
               AND (SELECT ExpectedMaxSnapshotDate FROM InventorySnapshot_B2S) = (SELECT ActualMaxSnapshotDate FROM InventorySnapshot_B2S)
               AND ABS((SELECT ExpectedOnHandQty FROM InventorySnapshot_B2S) - (SELECT ActualOnHandQty FROM InventorySnapshot_B2S)) < 0.0001
               AND ABS((SELECT ExpectedSafetyStock FROM InventorySnapshot_B2S) - (SELECT ActualSafetyStock FROM InventorySnapshot_B2S)) < 0.0001
               AND ABS((SELECT ExpectedOrderQty FROM InventorySnapshot_B2S) - (SELECT ActualOrderQty FROM InventorySnapshot_B2S)) < 0.0001
             THEN 'PASS' ELSE 'FAIL' END
    UNION ALL

    -- DQ_B2S_ATPWeekEnding_Qty:
    --   PASS nếu raw ATP sau filter InsertedVersion/week/latest + dedupe khớp Silver:
    --     row count, grain keyset, max snapshot, AtpQty và APNQ totals.
    SELECT
        'DQ_B2S_ATPWeekEnding_Qty',
        'Eligible raw ATP version/week/latest deduped grain, max snapshot, and key quantities must match Silver AtpWeekEnding',
        CASE WHEN (SELECT ExpectedRows FROM Atp_B2S) = (SELECT ActualRows FROM Atp_B2S)
               AND (SELECT MissingInSilver FROM Atp_B2S) = 0
               AND (SELECT ExtraInSilver FROM Atp_B2S) = 0
               AND (SELECT ExpectedMaxSnapshotDate FROM Atp_B2S) = (SELECT ActualMaxSnapshotDate FROM Atp_B2S)
               AND ABS((SELECT ExpectedAtpQty FROM Atp_B2S) - (SELECT ActualAtpQty FROM Atp_B2S)) < 0.0001
               AND ABS((SELECT ExpectedAPNQ FROM Atp_B2S) - (SELECT ActualAPNQ FROM Atp_B2S)) < 0.0001
             THEN 'PASS' ELSE 'FAIL' END

    UNION ALL

    -- =================================================================
    -- CỤM 3: DQ_Silver_Grain_*
    -- Ý nghĩa: kiểm tra bảng Silver final có đúng grain/key contract không.
    -- PASS nghĩa là output cuối của Silver không còn null/blank key hoặc duplicate grain.
    -- =================================================================

    -- DQ_Silver_Grain_Calendar:
    --   PASS nếu Silver Calendar không null Date/SKDate và unique theo Date/SKDate.
    SELECT
        'DQ_Silver_Grain_Calendar',
        'Silver Calendar must be unique by Date and SKDate; keys not null',
        CASE WHEN EXISTS (SELECT 1 FROM ReferenceMaster_Enh.Calendar WHERE Date IS NULL OR SKDate IS NULL)
               OR EXISTS (SELECT Date FROM ReferenceMaster_Enh.Calendar GROUP BY Date HAVING COUNT_BIG(*) > 1)
               OR EXISTS (SELECT SKDate FROM ReferenceMaster_Enh.Calendar GROUP BY SKDate HAVING COUNT_BIG(*) > 1)
             THEN 'FAIL' ELSE 'PASS' END
    UNION ALL

    -- DQ_Silver_Grain_Warehouse:
    --   PASS nếu Silver Warehouse có WarehouseCode usable và không duplicate.
    SELECT
        'DQ_Silver_Grain_Warehouse',
        'Silver Warehouse must be unique by WarehouseCode; key not null',
        CASE WHEN EXISTS (SELECT 1 FROM ReferenceMaster_Enh.Warehouse WHERE NULLIF(TRIM(WarehouseCode), '') IS NULL)
               OR EXISTS (SELECT WarehouseCode FROM ReferenceMaster_Enh.Warehouse GROUP BY WarehouseCode HAVING COUNT_BIG(*) > 1)
             THEN 'FAIL' ELSE 'PASS' END
    UNION ALL

    -- DQ_Silver_Grain_Vendor:
    --   PASS nếu Silver Vendor có VendorNumber usable và không duplicate.
    SELECT
        'DQ_Silver_Grain_Vendor',
        'Silver Vendor must be unique by VendorNumber; key not null',
        CASE WHEN EXISTS (SELECT 1 FROM ReferenceMaster_Enh.Vendor WHERE NULLIF(TRIM(VendorNumber), '') IS NULL)
               OR EXISTS (SELECT VendorNumber FROM ReferenceMaster_Enh.Vendor GROUP BY VendorNumber HAVING COUNT_BIG(*) > 1)
             THEN 'FAIL' ELSE 'PASS' END
    UNION ALL

    -- DQ_Silver_Grain_CustomerAccountGroup:
    --   PASS nếu Silver CAG unique theo (Customer, CustomerGroupCode) và key usable.
    SELECT
        'DQ_Silver_Grain_CustomerAccountGroup',
        'Silver CustomerAccountGroup must be unique by (Customer, CustomerGroupCode); keys not null',
        CASE WHEN EXISTS (
                    SELECT 1 FROM ReferenceMaster_Enh.CustomerAccountGroup
                    WHERE NULLIF(TRIM(Customer), '') IS NULL
                       OR NULLIF(TRIM(CustomerGroupCode), '') IS NULL
                )
               OR EXISTS (
                    SELECT Customer, CustomerGroupCode
                    FROM ReferenceMaster_Enh.CustomerAccountGroup
                    GROUP BY Customer, CustomerGroupCode
                    HAVING COUNT_BIG(*) > 1
                )
             THEN 'FAIL' ELSE 'PASS' END
    UNION ALL

    -- DQ_Silver_Grain_ItemMaster:
    --   PASS nếu Silver ItemMaster có ItemSKU usable và không duplicate.
    SELECT
        'DQ_Silver_Grain_ItemMaster',
        'Silver ItemMaster must be unique by ItemSKU; key not null',
        CASE WHEN EXISTS (SELECT 1 FROM ReferenceMaster_Enh.ItemMaster WHERE NULLIF(TRIM(ItemSKU), '') IS NULL)
               OR EXISTS (SELECT ItemSKU FROM ReferenceMaster_Enh.ItemMaster GROUP BY ItemSKU HAVING COUNT_BIG(*) > 1)
             THEN 'FAIL' ELSE 'PASS' END
    UNION ALL

    -- DQ_Silver_Grain_InventorySnapshotWeekly:
    --   PASS nếu Silver InventorySnapshotWeekly unique đúng grain:
    --     (ItemSku, WarehouseCode, SnapshotWeekEndingDate, FiscalMonth).
    SELECT
        'DQ_Silver_Grain_InventorySnapshotWeekly',
        'Silver InventorySnapshotWeekly must be unique by (ItemSku, WarehouseCode, SnapshotWeekEndingDate, FiscalMonth)',
        CASE WHEN EXISTS (
                    SELECT 1 FROM InventoryHistory_Enh.InventorySnapshotWeekly
                    WHERE NULLIF(TRIM(ItemSku), '') IS NULL
                       OR NULLIF(TRIM(WarehouseCode), '') IS NULL
                       OR SnapshotWeekEndingDate IS NULL
                       OR FiscalMonth IS NULL
                )
               OR EXISTS (
                    SELECT ItemSku, WarehouseCode, SnapshotWeekEndingDate, FiscalMonth
                    FROM InventoryHistory_Enh.InventorySnapshotWeekly
                    GROUP BY ItemSku, WarehouseCode, SnapshotWeekEndingDate, FiscalMonth
                    HAVING COUNT_BIG(*) > 1
                )
             THEN 'FAIL' ELSE 'PASS' END
    UNION ALL

    -- DQ_Silver_Grain_ATPWeekEnding:
    --   PASS nếu Silver AtpWeekEnding unique đúng grain:
    --     (ItemSku, WarehouseCode, SnapshotDate, ATPWeek, WeekEndingDate, InsertedVersion).
    SELECT
        'DQ_Silver_Grain_ATPWeekEnding',
        'Silver AtpWeekEnding must be unique by (ItemSku, WarehouseCode, SnapshotDate, ATPWeek, WeekEndingDate, InsertedVersion)',
        CASE WHEN EXISTS (
                    SELECT 1 FROM InventoryHistory_Enh.AtpWeekEnding
                    WHERE NULLIF(TRIM(ItemSku), '') IS NULL
                       OR NULLIF(TRIM(WarehouseCode), '') IS NULL
                       OR SnapshotDate IS NULL
                       OR ATPWeek IS NULL
                       OR WeekEndingDate IS NULL
                       OR InsertedVersion IS NULL
                )
               OR EXISTS (
                    SELECT ItemSku, WarehouseCode, SnapshotDate, ATPWeek, WeekEndingDate, InsertedVersion
                    FROM InventoryHistory_Enh.AtpWeekEnding
                    GROUP BY ItemSku, WarehouseCode, SnapshotDate, ATPWeek, WeekEndingDate, InsertedVersion
                    HAVING COUNT_BIG(*) > 1
                )
             THEN 'FAIL' ELSE 'PASS' END
)

-- Final SELECT:
--   Trả 21 dòng DQ result.
--   CROSS JOIN run_meta để tất cả rule trong cùng một lần chạy dùng chung DQRunId/DQRunAtUTC.
SELECT
    dq.RuleName,
    dq.RuleDescription,
    dq.Result,
    rm.DQRunId,
    rm.DQRunAtUTC,
    rm.DQRunAtUTC AS LoadDT
FROM DQ AS dq
CROSS JOIN run_meta AS rm;
