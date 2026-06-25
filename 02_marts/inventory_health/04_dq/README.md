# Inventory Health DQ Logs

Generated from the Bronze DQ audit scripts:

```bash
python3 05_tools/01_dq/audit_bronze_source_dq.py --out-dir <artifact_dir>
```

Files:

- `manifest.json` — Bronze DQ status summary for this mart.
- `contracts/bronze_sources.json` — source-level DQ contract and freshness/key metadata.
- `contracts/rules.json` — rule contract per source.
- `contracts/exceptions.json` — non-pass sources requiring DE/business review.
- `runs/latest.json` — latest generated DQ operating summary.
- `bronze_sources/*.dq.json` — machine-readable DQ result per Bronze source.
- `bronze_sources/*.dq.sql` — rerun template per Bronze source.
