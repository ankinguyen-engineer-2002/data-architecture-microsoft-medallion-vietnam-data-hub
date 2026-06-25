# Naming Conventions Audit — `EnterpriseData-Dev`

> Evidence-based audit of Bob's actual naming patterns across all Silver WHs. Used to align VN team naming.

## Schema suffixes observed

| Suffix | Meaning | Tier | Examples |
|--------|---------|------|----------|
| `_AFI` | Source AFI/AS400 (Ashley Furniture Industries) — **canonical curated** | Silver | `Wholesale_Warehouse.SalesHistory_AFI`, `CustomerOrders_AFI`, `Pricing_AFI`, `Purchasing_AFI`, `Quality_AFI`, `ProductSourcing_AFI` |
| `_AFI_Wrk` | Working set OF `_AFI` | Silver pre-curated | `SalesHistory_AFI_Wrk`, `CustomerOrders_AFI_Wrk` |
| `_AFI_Archive` | Historical retention | Archive | `SalesHistory_AFI_Archive` |
| `_Enh` | **Enhanced tier** (incrementally loaded, enriched from raw) | Bronze→Silver | `Retail_Warehouse.Retail_Sales_Enh`, `MasterData_HR_UKG_Enh`, `Retail_OOM_Enh`, `MasterData_Product_Enh` |
| `_Enh_Wrk` | Working set OF `_Enh` | Silver staging | `MasterData_HR_UKG_Enh_Wrk`, `Retail_OOM_Wrk` |
| `_Wrk` | Generic working set | Pre-curated | `Customers_Wrk`, `Marketing_Wrk`, `ProductKnowledge_Wrk` |
| `_DW` | **Dim/Fact pattern** — only `MasterData_Warehouse` uses | Silver dim | `MasterData_DW`, `MasterData_DW_Wrk` |
| `_Ent` | Enterprise-shared subset within domain | Silver shared | `MasterData_Ent`, `MasterData_Retail_Ent` |
| `_DSG` | Design tier (HR-specific) | Pre-Silver | `MasterData_HR_UKG_DSG`, `MasterData_HR_UKG_DSG_Enh` |
| `_Archive` | Historical | Archive | `SalesHistory_AFI_Archive` |
| `_SCD` | Slowly Changing Dimension | Bronze SCD | `Source_Data.Retail_Corporate_SCD` |
| (no suffix) | Canonical curated final | Silver final | `Marketing`, `Customers`, `PartyContacts`, `Placements`, `ProductKnowledge`, `Retail_Sales`, `Retail_Traffic` |

## Table naming inside each schema

**Critical observation**: `Dim`/`Fact` prefix is used **ONLY in `_DW` schemas**. All other schemas use **plain table names**.

### Evidence

| Schema | Sample tables | Has Dim/Fact prefix? |
|--------|---------------|----------------------|
| `MasterData_Warehouse.MasterData_DW` | DimDate, DimDate_NonRetail, DimDateTool, DimItemMaster, DimRetailLocations, DimTime | ✅ YES (only here) |
| `MasterData_Warehouse.ProductKnowledge` | Item, ItemClass, ItemMaster, ItemDimensions, LifeStyleArea, ParentStyleLookup | ❌ NO |
| `Wholesale_Warehouse.SalesHistory_AFI` | InvoiceDetail, InvoiceHeader, InvoiceConsumerInformation, InvoiceValueAddedTax | ❌ NO |
| `Wholesale_Warehouse.CustomerOrders_AFI` | OpenOrderHeader, OpenOrderDetail, OrderTypeCode, CreditCodes, OrderArrivalCode | ❌ NO |
| `Retail_Warehouse.Retail_Sales_Enh` | (sample) plain names | ❌ NO |
| `Retail_Warehouse.MasterData_HR_UKG_Enh` | Employees, Jobs, PayCodes, OrgLevel, LaborCategory | ❌ NO |

→ Rule: **Dim/Fact prefix only in `_DW` schemas**.

## View naming

All views use **`v_*` prefix** (single-char, lowercase). NEVER `vw_*`.

Example from `Wholesale_Warehouse.SalesHistory_AFI_Wrk`:
- `v_InvoiceConsumerInformation`, `v_InvoiceDetail`, `v_InvoiceDetailProperties`, `v_InvoiceHeader`, `v_InvoiceValueAddedTax`

Example from `Retail_Warehouse.Retail_Sales_Wrk`:
- `v_BucketInventory`, `v_BucketOrderItem`, `v_BucketPOI`, `v_CreditApplication`, `v_CreditReview`

## Procedure naming

**Mixed casing observed** — Bob's team doesn't enforce strict consistency:

| Casing | Examples | Pattern |
|--------|----------|---------|
| `Usp_*` (Pascal) | `Usp_CreateTableFromParquet`, `Usp_CreateTableFromParquet_V2`, `Usp_Refresh_Wholesale_Warehouse`, `Usp_Refresh_EmployeeHistory`, `Usp_Refresh_MasterData_Ent` | Some refresh + parquet loaders |
| `usp_*` (lowercase prefix) | `usp_RefreshCuratedTableFromView`, `usp_DataWarehouseSLAAlert_Fabric`, `usp_IncrementalTableLoad`, `usp_SCD2_TableLoad` | Most procs |

**Recommendation for VN**: Use `usp_*` (lowercase prefix, PascalCase body) consistently — matches majority of Bob's procs. VN already does this.

## Column naming

PascalCase confirmed across all sample tables:
- `InvoiceID`, `OrderDate`, `LeadTimeDaysNum`, `CSTDateValue`, `Description`, `DateTime`, `User`, `Command`

VN already aligned per ADR-008.

## Table casing

PascalCase for tables. Confirmed across all WHs.

## Fabric-native columns NULL by convention

These cols in `TableDictionary` are intentionally NULL or auto in Fabric:

| Col | Reason NULL/auto |
|-----|------------------|
| `DistributionKey`, `IndexType`, `RowSToreClusteredKey`, `AdditionalIndexes` | Fabric auto-managed (no user control unlike Synapse Dedicated SQL Pool) |
| `PartitionKey` | Fabric auto-managed |
| `JobName`, `JobServer`, `TFSPath`, `LibraryList` | Synapse legacy, not applicable to Fabric |
| `DataBricksClusterVersion`, `DataBricksNodeType`, `DataBricksClusterRange` | Not applicable to Fabric pipelines (only for Mirror) |
| `AlternateKey` | Often unused |
| `ColumnStatsLastUpdated` | Fabric stat tracking limited |
| `SourceObjectAlias` | Convention not enforced |

## VN team naming (post ADR-008)

| VN object | Old | New (aligned to Bob) |
|-----------|-----|----------------------|
| Schema casing `_ENH`/`_WRK` | `Staging_WRK`, `*_ENH` | `Staging_Wrk`, `*_Enh` ✅ |
| View prefix `vw_*` | 35 views | `v_*` ✅ |
| Schema `_DW` | `ForecastAccuracy_DW` | `ForecastAccuracy_DW` (kept ALL CAPS — matches Bob) ✅ |
| Dim/Fact prefix in Gold (`_DW`) | `DimCalendar`, `FactForecastActual`, `FactForecastKpi` | Kept (correct per `_DW` rule) ✅ |
| Dim/Fact prefix outside `_DW` | (n/a — VN doesn't have outside _DW) | OK |
| Proc casing | `usp_*` (lowercase prefix) | OK ✅ |

## Proposed naming for new SC tables in `EnterpriseData-Dev.SupplyChain_Warehouse`

Two options for Bob's review:

### Option A (recommended — single schema, mirror Retail)
```
SupplyChain_Warehouse.Forecast_Enh
  ├─ ForecastDemandMonthly       (no prefix — matches Retail_Sales_Enh table style)
  ├─ NaiveForecastMonthly
  ├─ ForecastCycle               (reference)
  └─ ForecastHorizon             (dictionary)

SupplyChain_Warehouse.Forecast_Enh_Wrk  (working views)
  ├─ v_ForecastDemandMonthly
  ├─ v_NaiveForecastMonthly
  ├─ v_ForecastCycle
  └─ v_ForecastHorizon
```

### Option B (split fact + reference, mirror Wholesale + MasterData)
```
SupplyChain_Warehouse.Forecast_Enh
  ├─ ForecastDemandMonthly
  └─ NaiveForecastMonthly

MasterData_Warehouse.MasterData_DW (extend existing)
  ├─ DimForecastCycle           (NEW — reference dim, Dim* prefix per _DW rule)
  └─ DimForecastHorizon          (NEW — dictionary dim)
```

**VN team defers to Bob's preference.**

## Cross-refs

- Raw scan reference: `_external_refs/enterprisedata-dev-01_docs/docs/02-storage/`
- ADR-008 (VN side, executed): [`../../docs/decisions/ADR-008-bob-alignment-naming-and-integration.md`](../../docs/decisions/ADR-008-bob-alignment-naming-and-integration.md)
