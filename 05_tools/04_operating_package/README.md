# Operating Package Tools

Builds machine-readable operating metadata for each mart from repo-local source of truth.

## Script

| Script | Purpose |
|---|---|
| `build_operating_package.py` | Generate Bronze DQ contracts/runs and mart catalog/lineage registries without live Fabric mutation. |

## Example

```bash
python3 05_tools/04_operating_package/build_operating_package.py --repo-root .
```
