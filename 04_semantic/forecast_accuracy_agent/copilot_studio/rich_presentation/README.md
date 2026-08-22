# SupplyChainAgent Rich Presentation MVP

This package is the source-controlled presentation control plane for the
`SupplyChainAgent` Forecast MVP.

It contains:

- versioned request, evidence, presentation and interaction contracts;
- a bounded `flow-router-input` contract for the finite presentation Flow;
- explicit channel capabilities and a finite card registry;
- Adaptive Cards 1.5 templates with a text fallback;
- a deterministic TypeScript resolver used by the custom web client and local
  conformance tests;
- an in-memory interaction ledger that models the Dataverse idempotency and
  stale-state boundary; and
- a machine-readable policy trace, bounded status-event stream, MCP-compatible
  evidence resource pointer, and common Flow response wrapper; and
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

The `decision` field is an auditable policy trace, not model chain-of-thought:
it records request, evidence, shape, capability, limit, and registry checks.
The `events` field is deliberately bounded (`VALIDATING_REQUEST` through
`READY`, or `FALLBACK`) and contains no fabricated percentage progress. A
custom Web Chat adapter can map these events to client events or activity
updates.

Valid evidence also carries an opaque `evidence://...` resource reference. The
`resolver/resource-links.ts` adapter maps it to the MCP `resource_link` shape,
so large detail can be fetched on demand through a user-scoped endpoint rather
than copied into a card. The pointer is metadata only in this local fixture
demo; no endpoint or credential is created here.

## Local commands

```bash
npm install
npm run check
npm run test:e2e
npm run dev
```

`npm run check` validates the JSON contracts, parses every Adaptive Card with
the Microsoft `adaptivecards` library, compiles the TypeScript resolver, and
runs the resolver plus interaction tests. `npm run test:e2e` launches the
fixture demo in Playwright and checks desktop/mobile behavior. `npm run dev`
starts the local demo at the Vite address shown by the command. The demo uses
fixtures only and does not represent authenticated Copilot Studio connectivity.

## Current test path

The first executable integration is one finite `Rich Presentation Router` Flow.
It consumes a validated Evidence Envelope and bounded presentation fields, then
returns the common `FlowResponse` contract. The upstream numeric/evidence route
remains separate and authoritative. The current live artifact is draft-only and
must replace static branch fixtures with validated field mapping before publish.

## Later hardening work

1. Replace the in-memory interaction ledger with Dataverse tables and
   user-scoped server validation.
2. Put the Microsoft 365 Agents SDK connection behind an authenticated BFF.
3. Run the real two-user identity/RLS, Teams, M365, accessibility and browser
   release gates from the implementation plan.

These are explicit external gates, not hidden assumptions in the local demo.
