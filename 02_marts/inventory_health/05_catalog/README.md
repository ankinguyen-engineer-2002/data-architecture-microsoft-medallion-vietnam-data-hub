# inventory_health Catalog

Machine-readable operating registry for this mart.

| File | Purpose |
|---|---|
| `assets.json` | All repo-known mart assets by layer and file path. |
| `lineage_edges.json` | Table/view/source edges inferred from SQL references plus BOB `_Wrk` materialization edges. |
| `run_order.json` | Manifest-backed refresh order and post-run check contract. |
| `semantic_bindings.json` | Gold-to-semantic references inferred from local semantic artifacts. |
