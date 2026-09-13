# Presentation script

## Opening (60 seconds)

“I am a Supply Chain Data Engineer. Azure registers identity and resources;
Azure Databricks cooks the Forecast and Inventory source slice; Fabric serves
Gold. Copilot sits on governed Gold. I do not live as Global Admin — PIM
elevate, then revert. Databricks jobs in this git are reconstructed from
Bronze, not a workspace export.”

## Platform (3 minutes)

Show `03_operations/CLAIMS.md`, then `azure/README.md`, then
`databricks/registry/sources.yaml` and `sc_forecast_snapshot.py`.
Then 11 Agent steps. Streaming only if asked.

## DataOps (3 minutes)

Show `_Wrk` → final table → wrapper → `TableDictionary`/`AuditLog` → DQ gate.
Explain what a successful audit row proves and what it does not prove.

## Business product (3 minutes)

Choose one mart. Explain the business question, source, grain, time logic,
consumer, failure mode and verification.

## Copilot (2 minutes)

Explain that Copilot resolves language and presentation while semantic/DAX and
Gold contracts own the number. Show clarification/refusal behavior.

## AIOS (optional, last)

Only if asked: later AI-enabled workbench MVP, nested repo, not the DE
identity.

## Closing

“My strongest area is data and platform engineering. AI is how I extend a
governed data foundation into a better user experience, not a substitute for
understanding the data.”
