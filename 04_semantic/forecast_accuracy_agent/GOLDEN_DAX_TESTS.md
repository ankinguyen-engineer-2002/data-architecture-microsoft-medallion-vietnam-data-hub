# Golden DAX Tests

## Valid single horizon

```dax
EVALUATE
CALCULATETABLE(
    ROW(
        "Message", [KPI Context Message],
        "Valid", [KPI Context Valid],
        "Accuracy", [Forecast Accuracy],
        "wMAPE", [wMAPE]
    ),
    TREATAS({"Lag-0"}, 'Forecast Horizon'[Forecast Horizon]),
    TREATAS({DATE(2026, 7, 25)}, 'Fiscal Calendar'[Fiscal Month End])
)
```

Expected: `Message = Ready`, `Valid = 1`, and KPI values are nonblank.

## Missing horizon

```dax
EVALUATE ROW("Message", [KPI Context Message], "Accuracy", [Forecast Accuracy])
```

Expected: `Select one forecast horizon` and blank accuracy.

## Unsupported horizon

```dax
EVALUATE
CALCULATETABLE(
    ROW("Message", [KPI Context Message], "Accuracy", [Forecast Accuracy]),
    TREATAS({">Lag-4"}, 'Forecast Horizon'[Forecast Horizon])
)
```

Expected: `Unsupported >Lag-4 horizon` and blank accuracy.

## Ambiguous snapshot cohort

```dax
EVALUATE
CALCULATETABLE(
    ROW("Message", [KPI Context Message], "Accuracy", [Forecast Accuracy]),
    TREATAS({"Lag-0"}, 'Forecast Horizon'[Forecast Horizon]),
    TREATAS({DATE(2023, 7, 1)}, 'Fiscal Calendar'[Fiscal Month End])
)
```

Expected: `Multiple snapshots exist for a month/horizon` and blank accuracy.

## Sensitive-field absence

Metadata validation must confirm no column named `CurrentUnitCost`, `FOBArcPrice`, or any load timestamp exists.
