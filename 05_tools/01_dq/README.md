# DQ Tools

Read-only Bronze source DQ audit scripts for `Enterprise_Lakehouse`.

## Scripts

| Script | Purpose |
|---|---|
| `audit_bronze_source_dq.py` | Configurable Bronze DQ scanner with CLI options for scoped runs. |
| `audit_all_bronze_source_dq_final.py` | All-source final scanner used for the 2026-06-23 Bronze audit evidence. |

## Examples

```bash
python3 05_tools/01_dq/audit_bronze_source_dq.py --help
python3 05_tools/01_dq/audit_all_bronze_source_dq_final.py --help
```
