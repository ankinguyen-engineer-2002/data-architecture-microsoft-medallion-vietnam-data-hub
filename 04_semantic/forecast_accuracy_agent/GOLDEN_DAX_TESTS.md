# Golden DAX Tests

## Control Tower and Gold parity gate

Every one of the 89 measures in `_Measure_ForecastAccuracy` must equal the corresponding `sc_control_tower` measure at strict `1e-10` numeric tolerance. The parity gate runs completed, historical, and future/no-data contexts. The agent model must not add a Snapshot filter or alter any business formula from `sc_control_tower`.

## Canonical parity query

```dax
EVALUATE
CALCULATETABLE(
    ROW(
        "ForecastAccuracy", [Pct_ForecastAccuracy],
        "wMAPE", [Pct_wMAPE],
        "Actual", [Qty_Actual],
        "AbsoluteBias", [Qty_Abs_Bias]
    ),
    TREATAS({"Lag-0"}, DimForecastHorizon[HorizonCode]),
    TREATAS({DATE(2026, 7, 25)}, DimCalendar[Date])
)
```

Expected: Forecast Accuracy `0.3959006542885988`, wMAPE `0.6040993457114012`, actual `3,059,659`, and absolute bias `1,848,338`.

## Completed-period parity examples

The following expected values are the common `sc_control_tower` and Gold result, not an agent-specific calculation:

| Fiscal month | Horizon | `Pct_ForecastAccuracy` | `Pct_wMAPE` | `Qty_Actual` | `Qty_Abs_Bias` |
| --- | --- | ---: | ---: | ---: | ---: |
| `July, 2026` | `Lag-0` | `39.5901%` | `60.4099%` | `3,059,659` | `1,848,338` |
| `August, 2026` | `Lag-0` | blank while future under the Control Tower `TODAY()` rule | `64.5605%` | `2,034,633` | `1,313,570` |

## Sensitive-field absence

The semantic clone is exact for parity and consequently retains source fields in the model. The Data Agent source-schema validation, not the semantic model, must confirm that cost, price, raw fact fields, snapshots, and load timestamps are unselected for AI use.
