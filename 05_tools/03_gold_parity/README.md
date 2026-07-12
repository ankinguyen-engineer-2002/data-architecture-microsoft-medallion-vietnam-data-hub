# Inventory Health Gold — Business-Parity Audit & Test Harness

Read-only audit + business-parity test system for the 9-object
`SupplyChain_Gold_Warehouse.dbo.Usp_Refresh_InventoryHealth_Gold` chain.

Backs `01_docs/plans/2026-07-10-inventory-gold-business-parity-optimization-plan.md`.
Goal: any optimized system B must be provably equal to current system A on
business logic, code logic, and performance before it can replace A.

## Safety

- Every module opens a connection with `ApplicationIntent=ReadOnly` and issues
  only `SELECT` / metadata reads. No DDL/DML against production.
- Auth mirrors `05_tools/01_dq/*`: `az account get-access-token` (Entra) + pyodbc.
- Module 04 is implemented as inline read-only A-vs-B SQL. It creates no live
  compare object and never mutates a production serving object.

## Modules

| Module | Plan layer | Purpose | Output |
|---|---|---|---|
| `lib_conn.py` | — | shared read-only conn + Gold target registry | — |
| `01_contract_inventory.py` | Layer A | live view SQL + column contract + loader `SELECT *` safety + static parse | `contracts/*.contract.json` |
| `02_risk_probes.py` | Layer B | R1 join multiplicity, R2 dim uniqueness, R3 dedup tie-break materiality | `runs/*_risk_probes.json` |
| `03_baseline_capture.py` | §5.2 / Layer C | frozen oracle: rowcount, key uniqueness, date coverage, measure sums, distributions, weekly recon, Query Insights | `contracts/*.baseline.json` |
| `04_shadow_parity.py` | Layer D–E | C1 inline A-vs-B inv_base parity (read-only SELECT; no live DDL/DML) | `runs/*_shadow_parity_c1.json` |
| `05_downstream_perf.py` | Layer F–G | (planned) downstream serving + performance/rollback | — |

## Usage

```bash
# Layer A — contracts for all 9 targets
python3 05_tools/03_gold_parity/01_contract_inventory.py

# Risk probes
python3 05_tools/03_gold_parity/02_risk_probes.py

# Baseline (single heavy target)
python3 05_tools/03_gold_parity/03_baseline_capture.py --target FactInventoryHealthSnapshot
# lighter, skip Query Insights
python3 05_tools/03_gold_parity/03_baseline_capture.py --target DimVendor --skip-query-insights

# Module 04 — C1 inv_base parity (read-only SELECT; no live object created)
python3 05_tools/03_gold_parity/04_shadow_parity.py --recent-weeks 8   # smoke
python3 05_tools/03_gold_parity/04_shadow_parity.py --full            # full-history proof
```

Run outputs are timestamped in `runs/`. `contracts/` holds the current
per-target contract + frozen baseline (the comparison oracle for B).

## Notes

- `contracts/*.baseline.json` are labelled with capture UTC + max business date;
  a candidate is only compared against an equivalent data state.
- Query Insights capture is best-effort (`command LIKE '%<view>%'`) and can pick
  up harness queries; treat it as directional, not authoritative timing.
