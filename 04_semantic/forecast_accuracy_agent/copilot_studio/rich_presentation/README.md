# SupplyChainAgent Rich Presentation MVP

This package is the source-controlled presentation control plane for the
`SupplyChainAgent` Forecast MVP.

It contains:

- versioned request, evidence, presentation and interaction contracts;
- explicit channel capabilities and a finite card registry;
- Adaptive Cards 1.5 templates with a text fallback;
- a deterministic TypeScript resolver used by the custom web client and local
  conformance tests;
- an in-memory interaction ledger that models the Dataverse idempotency and
  stale-state boundary; and
- a runnable React + Fluent UI demo shell backed by local governed fixtures.

The package does not publish Copilot Studio assets, create Dataverse tables,
change Entra registrations, call Fabric, or store credentials. Those actions
remain deployment work behind the contracts in this directory.

## Runtime boundary

```text
SupplyChainAgent
  -> bounded QuerySpec + presentation hint
  -> finite governed Agent Flow
  -> validated Evidence Envelope
  -> deterministic resolver
  -> registered card or web renderer
  -> complete text fallback
```

The model can suggest `AUTO`, `KPI_CARD`, `TABLE`, `TREND`, `FLASHCARD`, or
`FORM`. It cannot provide raw Adaptive Card JSON, DAX, SQL, identity, role,
approval, or evidence fields. The resolver ignores an incompatible hint and
never turns an invalid or stale evidence object into a number.

## Local commands

```bash
npm install
npm run check
npm run dev
```

`npm run check` validates the JSON artifacts, compiles the TypeScript resolver,
and runs the resolver plus interaction tests. `npm run dev` starts the local
demo at the Vite address shown by the command. The demo uses fixtures only and
does not represent authenticated Copilot Studio connectivity.

## Integration work still required

1. Map the finite resolver branches to the three Copilot Studio Agent Flows.
2. Replace the in-memory interaction ledger with Dataverse tables and
   user-scoped server validation.
3. Put the Microsoft 365 Agents SDK connection behind an authenticated BFF.
4. Run the real two-user identity/RLS, Teams, M365, accessibility and browser
   release gates from the implementation plan.

These are explicit external gates, not hidden assumptions in the local demo.
