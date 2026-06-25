# Marts

Folder này là nơi đóng gói từng business mart.

Một mart không chỉ gồm SQL. Một mart đầy đủ phải có source contract, SQL theo layer, DQ, catalog/lineage, run order và ghi chú semantic impact.

## Đọc Trước

- DA: [../01_docs/onboarding/da_onboarding.md](../01_docs/onboarding/da_onboarding.md)
- DE: [../01_docs/onboarding/de_onboarding.md](../01_docs/onboarding/de_onboarding.md)
- Glossary: [../01_docs/glossary.md](../01_docs/glossary.md)

## Cấu Trúc Một Mart

```text
02_marts/<mart_name>/
  00_source_wrk/    source wrapper hoặc prep notes
  01_bronze/        source/shortcut contract đang active
  02_silver/        Silver final table contract và _Wrk view SQL
  03_gold/          Gold/shared final table contract và _Wrk view SQL
  04_dq/            Bronze DQ contract, exception, evidence JSON
  05_catalog/       assets, lineage edges, run order, semantic bindings
  99_history/       logic cũ, inactive object, pre-restructure notes
  README.md         hướng dẫn riêng của mart
```

## Mart Hiện Tại

| Mart | Project tag | Gold schema | Orchestration |
|---|---|---|---|
| [Forecast Accuracy](forecast_accuracy/README.md) | `forecast_accuracy` | `ForecastAccuracy_DW` | `03_operations/orchestration/forecast_accuracy/` |
| [Inventory Health](inventory_health/README.md) | `inventory_health` | `InventoryHealth_DW` | `03_operations/orchestration/inventory_health/` |

## Shared Layer

`Shared_DW` không phải một mart độc lập cho user cuối. Nó là lớp hỗ trợ dùng chung cho dimension và semantic relationship.

Ví dụ:

```text
Shared_DW.DimCalendar
Shared_DW.DimProduct
Shared_DW.DimWarehouse
```

Shared/reference dependencies phải chạy trước mart-specific Gold facts nếu các fact phụ thuộc vào chúng.

## Enterprise `_Wrk` Contract

Silver và Gold theo pattern curated warehouse của Enterprise ETL/Enterprise:

```text
Final table:
  <SchemaName>.<TableName>

Source/work view:
  <SchemaName>_Wrk.v_<TableName>
```

Quy tắc:

- Final schema folder chứa table contract, ví dụ `<TableName>.table.sql`.
- `_Wrk` schema folder chứa source/work view, ví dụ `v_<TableName>.sql`.
- `ETL_Framework.DW_Developer.TableDictionary` đăng ký final table.
- Loader framework suy ra source view từ `<SchemaName>_Wrk.v_<TableName>`.
- Base-schema duplicate `v_*` view là legacy compatibility artifact, không dùng cho work mới.
