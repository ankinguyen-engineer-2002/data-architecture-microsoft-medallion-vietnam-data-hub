# Archive

Folder này giữ kiến thức cũ để không mất lịch sử, nhưng không để lịch sử cạnh tranh với kiến trúc hiện tại.

Hãy xem archive như thư viện bằng chứng, không phải runbook hiện hành.

## Source Of Truth Hiện Tại

Khi cần current truth, đọc:

```text
00_CONTEXT/current.md
01_docs/architecture/current/
01_docs/Enterprise_Framework_Migration_Master_Plan.md
02_marts/
03_operations/orchestration/
```

## Archive Gồm Gì?

| Folder | Ý nghĩa |
|---|---|
| `architectures/v9_april/` | Snapshot kiến trúc v9 và scripts cũ. |
| `architectures/v10_may_pre_enterprise_etl/` | Snapshot v10 trước khi chốt Enterprise ETL runtime. |
| `reverse-engineering/enterprise_data_architect/` | Evidence reverse-engineering từ Enterprise ETL/EnterpriseData hub. |
| `reverse-engineering/enterprise_supplychain_dev_architect/` | Working set và evidence cũ của SupplyChain trước restructure. |
| `external_refs/_external_refs/` | External cloned/reference material dùng trong research. |
| `local-state/` | Local tool/cache state đã được đưa ra khỏi root. |

## Rule

```text
Không xóa archive nếu chưa có approval rõ.
Không dùng archive làm current operational truth nếu current docs không link tới artifact đó.
Khi archive mâu thuẫn với current architecture, current architecture thắng.
```
