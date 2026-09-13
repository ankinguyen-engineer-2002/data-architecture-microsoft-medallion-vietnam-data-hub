# DataOps and operational ownership

The platform is not complete when a query runs once. It is complete when a team
can understand what should run, run it in dependency order, detect bad data,
prove what happened, and recover safely.

## Operating loop

```text
inspect live state
  -> compare source-controlled contract
  -> dry-run dependency order
  -> execute approved wrapper/load
  -> inspect AuditLog and target state
  -> run DQ and semantic smoke
  -> publish evidence / record drift / recover if needed
```

## Capabilities built

- source and target contracts across Bronze, Silver and Gold;
- metadata-driven TableDictionary registration;
- wrapper procedures and topological run order;
- overwrite, date-range, incremental and fallback load patterns;
- DQ contracts, persisted runs and blocking publish gates;
- lineage edges, source routes and live-vs-repository drift checks;
- SQLPROJ/DACPAC build-only handoff packages (Fabric objects only);
- Azure Databricks job-as-code contract for the two-mart slice (validate in git; no job publish; Dev→Prod is catalog/workspace, not table copy);
- dry-run-first operation and explicit live approval boundaries;
- sanitized public lineage portal;
- repository maintenance and context retention discipline;
- ephemeral Entra authentication and no persisted credentials.

## Operational truth rules

An audit row proves that an operation wrote an audit event. It does not alone
prove target correctness, row-count completeness, DQ PASS, semantic parity or
consumer access. Those checks remain separate and are documented as such.
