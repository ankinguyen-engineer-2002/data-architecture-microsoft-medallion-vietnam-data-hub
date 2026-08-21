# Agent Flow Branch Spec

This file is the finite Copilot Studio implementation companion to
`registry/flow-presentation-branches.json`.

The Flow must receive a validated `Evidence Envelope` and bounded presentation
fields. It does not call local TypeScript, accept raw JSON from the model, or
compile DAX. The TypeScript resolver is the client/reference implementation and
conformance oracle; the Flow mirrors the same nine ordered branches.

## Inputs from the governed evidence route

The Flow may read only:

- `evidenceStatus`;
- `interactionMode` and the allowlisted `workflowId` or reviewed `conceptId`;
- `resultShape`, `metricCount`, `rowCount`, and `seriesPointCount`;
- `channelProfile` and its registered `supportsRichTrend` capability; and
- the bounded `presentationHint`.

The Flow must reject or ignore `dax`, `sql`, raw card JSON, user identity,
roles, approval state and next-review dates supplied by conversation content.
Identity and authorization come from the connector execution context.

## Ordered Power Automate decision table

Implement a single `Switch` or equivalent ordered conditions:

1. If evidence is not `OK`, return `forecast.text.v1` with no number.
2. If the request is the approved governance draft workflow, return
   `forecast.governance-form.v1`.
3. If the request is a reviewed learning concept, return
   `forecast.flashcard.v1`.
4. If the result is scalar with one to three metrics, return
   `forecast.kpi.v1`.
5. If a series has three to 24 points and the channel supports a rich trend,
   return `forecast.trend.v1`.
6. If a series is valid but the channel does not support a rich trend, return
   `forecast.table.v1` with the ordered series as rows.
7. If a table has two to eight rows, return `forecast.table.v1`.
8. If a result exceeds the published limit, return `forecast.text.v1` and do
   not silently claim a complete result.
9. Otherwise return `forecast.text.v1` with `NO_REGISTERED_TEMPLATE`.

Every branch returns the same `Presentation Envelope` shape. The response must
include `requestId`, `evidenceId`, `templateId`, `channelProfile`,
`reasonCode`, `expiresAt`, accessibility metadata and a complete text fallback.

## Flow response contract

The `Respond to the agent` action should expose one structured object with:

```text
status
presentationEnvelope
trace.requestId
trace.evidenceId
trace.reasonCode
```

`status` is `OK` only when the evidence branch is valid or the interaction is a
safe non-numeric form/flashcard branch. A failed validation returns
`NO_GOVERNED_EVIDENCE` and a text envelope; it never returns an error number.

## Release comparison

For every fixture in `tests/resolver.test.ts`, capture the Flow response and
compare `presentationType`, `templateId`, `reasonCode`, bound row/series counts,
and `fallback.text` policy with the TypeScript resolver output. A mismatch is a
release failure. Do not use a broad natural-language answer as conformance
evidence.
