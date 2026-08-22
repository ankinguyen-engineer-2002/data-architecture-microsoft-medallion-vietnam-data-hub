import assert from "node:assert/strict";
import { test } from "node:test";
import type { InteractionEnvelope } from "../contracts/types.js";
import { toFlowResponse } from "../resolver/flow-response.js";
import { deriveFlowRouterInput } from "../resolver/flow-router-input.js";
import { InteractionLedger } from "../resolver/interaction-ledger.js";
import { resolvePresentation } from "../resolver/presentation-resolver.js";
import { toMcpResourceLink } from "../resolver/resource-links.js";
import {
  FIXED_NOW,
  flashcards,
  noEvidence,
  profiles,
  request,
  scalarEvidence,
  tableEvidence,
  trendEvidence,
} from "./fixtures.js";

const resolverOptions = { now: () => FIXED_NOW, flashcards };

test("scalar evidence resolves to a KPI card", async () => {
  const result = await resolvePresentation(request(), scalarEvidence(), profiles.WEB_RICH_V1, resolverOptions);
  assert.equal(result.presentationType, "KPI_CARD");
  assert.equal(result.templateId, "forecast.kpi.v1");
  assert.equal(result.reasonCode, "SCALAR_MATCH");
  assert.equal(result.data.metrics[0]?.displayValue, "39.6%");
  assert.match(result.fallback.text, /39\.6%/);
  assert.equal(result.decision.selectedType, "KPI_CARD");
  assert.deepEqual(result.events.map((event) => event.name), [
    "VALIDATING_REQUEST",
    "CHECKING_EVIDENCE",
    "SELECTING_PRESENTATION",
    "RENDERING",
    "READY",
  ]);
  assert.equal(result.resourceReference?.uri, "evidence://aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa");
});

test("a conflicting trend hint cannot override scalar evidence shape", async () => {
  const result = await resolvePresentation(
    request({ presentationHint: "TREND" }),
    scalarEvidence(),
    profiles.WEB_RICH_V1,
    resolverOptions,
  );
  assert.equal(result.presentationType, "KPI_CARD");
  assert.equal(result.reasonCode, "SCALAR_MATCH");
});

test("series resolves to a rich web trend", async () => {
  const result = await resolvePresentation(request(), trendEvidence(), profiles.WEB_RICH_V1, resolverOptions);
  assert.equal(result.presentationType, "TREND");
  assert.equal(result.templateId, "forecast.trend.v1");
  assert.equal(result.data.series.length, 6);
  assert.equal(result.reasonCode, "SERIES_MATCH");
});

test("the same series falls back to a bounded table in Teams", async () => {
  const result = await resolvePresentation(
    request({ channelProfile: "TEAMS_AC15", presentationHint: "TREND" }),
    trendEvidence(),
    profiles.TEAMS_AC15,
    resolverOptions,
  );
  assert.equal(result.presentationType, "TABLE");
  assert.equal(result.templateId, "forecast.table.v1");
  assert.equal(result.reasonCode, "HOST_CAPABILITY_FALLBACK");
  assert.equal(result.data.rows.length, 6);
});

test("router input derives shape and channel from trusted runtime facts", () => {
  const input = deriveFlowRouterInput(
    request({ channelProfile: "TEAMS_AC15", presentationHint: "TREND" }),
    trendEvidence(),
    profiles.TEAMS_AC15,
  );
  assert.equal(input.resultShape, "SERIES");
  assert.equal(input.seriesPointCount, 6);
  assert.equal(input.channelProfile, "TEAMS_AC15");
  assert.equal(input.supportsRichTrend, false);
  assert.equal(input.presentationHint, "TREND");
});

test("router input removes numeric shape from failed evidence", () => {
  const input = deriveFlowRouterInput(request(), noEvidence(), profiles.WEB_RICH_V1);
  assert.equal(input.evidenceStatus, "NO_GOVERNED_EVIDENCE");
  assert.equal(input.resultShape, "NONE");
  assert.equal(input.metricCount, 0);
  assert.equal(input.rowCount, 0);
  assert.equal(input.seriesPointCount, 0);
});

test("small breakdown resolves to a table", async () => {
  const result = await resolvePresentation(request({ presentationHint: "TABLE" }), tableEvidence(), profiles.WEB_RICH_V1, resolverOptions);
  assert.equal(result.presentationType, "TABLE");
  assert.equal(result.reasonCode, "SMALL_TABLE_MATCH");
  assert.deepEqual(result.data.rows.map((row) => row.label), ["AFI", "ASH", "West"]);
});

test("duplicate table rows fail closed", async () => {
  const result = await resolvePresentation(
    request(),
    { ...tableEvidence(), rows: [
      { label: "AFI", value: 0.44, metricId: "forecast_accuracy" },
      { label: "AFI", value: 0.39, metricId: "forecast_accuracy" },
    ], rowCount: 2 },
    profiles.WEB_RICH_V1,
    resolverOptions,
  );
  assert.equal(result.presentationType, "TEXT_FALLBACK");
  assert.equal(result.reasonCode, "INVALID_EVIDENCE");
});

test("out-of-order trend points fail closed instead of being silently sorted", async () => {
  const evidence = trendEvidence();
  const result = await resolvePresentation(
    request(),
    { ...evidence, series: [...evidence.series!].reverse() },
    profiles.WEB_RICH_V1,
    resolverOptions,
  );
  assert.equal(result.presentationType, "TEXT_FALLBACK");
  assert.equal(result.reasonCode, "INVALID_EVIDENCE");
});

test("non-OK evidence fails closed without a number", async () => {
  const result = await resolvePresentation(request(), noEvidence(), profiles.WEB_RICH_V1, resolverOptions);
  assert.equal(result.presentationType, "TEXT_FALLBACK");
  assert.equal(result.evidenceId, null);
  assert.equal(result.data.metrics.length, 0);
  assert.doesNotMatch(result.fallback.text, /39\.6%|0\.3959/);
});

test("query hash mismatch fails closed", async () => {
  const result = await resolvePresentation(
    request(),
    { ...scalarEvidence(), querySpecHash: "sha256:ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff" },
    profiles.WEB_RICH_V1,
    resolverOptions,
  );
  assert.equal(result.presentationType, "TEXT_FALLBACK");
  assert.equal(result.reasonCode, "INVALID_EVIDENCE");
  assert.equal(result.events.at(-1)?.name, "FALLBACK");
});

test("trusted channel context rejects a client-supplied profile mismatch", async () => {
  const result = await resolvePresentation(
    request({ channelProfile: "TEAMS_AC15" }),
    scalarEvidence(),
    profiles.TEAMS_AC15,
    { ...resolverOptions, trustedChannelProfile: "WEB_RICH_V1" },
  );
  assert.equal(result.presentationType, "TEXT_FALLBACK");
  assert.equal(result.decision.checks[0]?.outcome, "BLOCK");
  assert.match(result.fallback.text, /trusted channel context/i);
});

test("series at 24 points is accepted and 25 points is rejected", async () => {
  const accepted = await resolvePresentation(request(), trendEvidence(24), profiles.WEB_RICH_V1, resolverOptions);
  const rejected = await resolvePresentation(request(), trendEvidence(25), profiles.WEB_RICH_V1, resolverOptions);
  assert.equal(accepted.presentationType, "TREND");
  assert.equal(accepted.data.series.length, 24);
  assert.equal(rejected.presentationType, "TEXT_FALLBACK");
  assert.equal(rejected.reasonCode, "ROW_LIMIT_BLOCK");
});

test("learning mode can only resolve a registered flashcard", async () => {
  const result = await resolvePresentation(
    request({
      interactionMode: "FLASHCARD_REVIEW",
      presentationHint: "FLASHCARD",
      conceptId: "forecast_accuracy_basics",
    }),
    null,
    profiles.WEB_RICH_V1,
    resolverOptions,
  );
  assert.equal(result.presentationType, "FLASHCARD");
  assert.equal(result.data.flashcard?.conceptId, "forecast_accuracy_basics");

  const unknown = await resolvePresentation(
    request({ interactionMode: "FLASHCARD_REVIEW", presentationHint: "FLASHCARD", conceptId: "not_registered" }),
    null,
    profiles.WEB_RICH_V1,
    resolverOptions,
  );
  assert.equal(unknown.presentationType, "TEXT_FALLBACK");
});

test("governance mode produces a draft-only form", async () => {
  const result = await resolvePresentation(
    request({ interactionMode: "GOVERNANCE_DRAFT", presentationHint: "FORM", workflowId: "forecast_governance_draft" }),
    null,
    profiles.WEB_RICH_V1,
    resolverOptions,
  );
  assert.equal(result.presentationType, "FORM");
  assert.match(result.fallback.text, /will not approve/);
});

test("unknown request fields fail closed", async () => {
  const result = await resolvePresentation(
    { ...request(), sql: "SELECT 1" } as never,
    scalarEvidence(),
    profiles.WEB_RICH_V1,
    resolverOptions,
  );
  assert.equal(result.presentationType, "TEXT_FALLBACK");
  assert.doesNotMatch(result.fallback.text, /SELECT|1/);
});

test("resolver output is byte-stable for the same fixed inputs", async () => {
  const first = await resolvePresentation(request(), scalarEvidence(), profiles.WEB_RICH_V1, resolverOptions);
  const second = await resolvePresentation(request(), scalarEvidence(), profiles.WEB_RICH_V1, resolverOptions);
  assert.deepEqual(first, second);
});

test("interaction ledger records ratings, rejects stale state and is idempotent", () => {
  const ledger = new InteractionLedger();
  const cardInstanceId = "21212121-2121-4121-8121-212121212121";
  ledger.seedFlashcard({
    cardInstanceId,
    conceptId: "forecast_accuracy_basics",
    actorKey: "actor-a",
    stateVersion: 0,
    reviewCount: 0,
    nextReviewAt: null,
  });
  const envelope: InteractionEnvelope = {
    contractVersion: "1.0.0",
    interactionId: "20202020-2020-4020-8020-202020202020",
    cardInstanceId,
    templateId: "forecast.flashcard.v1",
    actionId: "flashcard.rate",
    evidenceId: null,
    stateVersion: 0,
    issuedAt: "2026-08-21T08:00:00.000Z",
    expiresAt: "2026-08-21T08:15:00.000Z",
    payload: { rating: "KNOWN" },
  };
  const accepted = ledger.submit("actor-a", envelope, FIXED_NOW);
  assert.equal(accepted.status, "ACCEPTED");
  assert.equal(accepted.stateVersion, 1);
  assert.equal(accepted.nextReviewAt, "2026-08-28T08:00:00.000Z");

  const duplicate = ledger.submit("actor-a", envelope, FIXED_NOW);
  assert.equal(duplicate.status, "ACCEPTED");
  assert.deepEqual(duplicate, accepted);
  assert.equal(duplicate.nextReviewAt, accepted.nextReviewAt);

  const stale = ledger.submit(
    "actor-a",
    { ...envelope, interactionId: "30303030-3030-4030-8030-303030303030" },
    FIXED_NOW,
  );
  assert.equal(stale.status, "STALE");
  assert.equal(stale.stateVersion, 1);
});

test("interaction ledger creates a draft but never an approval", () => {
  const ledger = new InteractionLedger();
  const envelope: InteractionEnvelope = {
    contractVersion: "1.0.0",
    interactionId: "40404040-4040-4040-8040-404040404040",
    cardInstanceId: "41414141-4141-4141-8141-414141414141",
    templateId: "forecast.governance-form.v1",
    actionId: "governance.draft.submit",
    evidenceId: null,
    stateVersion: 0,
    issuedAt: "2026-08-21T08:00:00.000Z",
    expiresAt: "2026-08-21T08:15:00.000Z",
    payload: {
      action: "CREATE_DRAFT",
      subject: "Review a metric",
      requestType: "metric_definition_review",
      businessReason: "The definition needs a governed review.",
    },
  };
  const receipt = ledger.submit("actor-a", envelope, FIXED_NOW);
  assert.equal(receipt.status, "ACCEPTED");
  assert.equal(receipt.draftStatus, "DRAFT_CREATED");
  assert.doesNotMatch(receipt.message, /approved|approval completed/i);
});

test("Flow wrapper keeps one response contract and MCP uses a resource pointer", async () => {
  const presentation = await resolvePresentation(request(), scalarEvidence(), profiles.WEB_RICH_V1, resolverOptions);
  const flow = toFlowResponse(presentation);
  assert.equal(flow.status, "OK");
  assert.equal(flow.trace.reasonCode, "SCALAR_MATCH");
  assert.deepEqual(flow.events, presentation.events);

  const link = toMcpResourceLink(presentation.resourceReference!);
  assert.equal(link.type, "resource_link");
  assert.equal(link.uri, "evidence://aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa");
  assert.deepEqual(link.annotations.audience, ["assistant"]);
});
