import type {
  BoundMetric,
  BoundRow,
  BoundSeriesPoint,
  ChannelProfile,
  EvidenceEnvelope,
  EvidenceMetric,
  EvidenceRow,
  EvidenceSeriesPoint,
  FlashcardDefinition,
  PresentationAction,
  PresentationEnvelope,
  PresentationRequest,
  PresentationType,
  ReasonCode,
} from "../contracts/types.js";
import { formatMetricValue, METRIC_DEFINITIONS, sanitizeLabel } from "./formatters.js";
import { PRESENTATION_LIMITS } from "./limits.js";

export const GOVERNED_SEMANTIC_MODEL_ID = "2fbc4dfc-96d1-4af6-9987-4c14639435e6";
export const GOVERNED_VERSION = "forecast-metrics-1.0.0";
export const PRESENTATION_CONTRACT_VERSION = "1.0.0" as const;

const QUERY_TEMPLATE_IDS = new Set([
  "KPI_SCALAR_V1",
  "KPI_COMPARE_V1",
  "KPI_TREND_V1",
  "KPI_BREAKDOWN_V1",
  "TOP_BOTTOM_V1",
]);
const CHANNEL_PROFILE_IDS = new Set(["WEB_RICH_V1", "TEAMS_AC15", "M365_LIMITED", "COPILOT_TEST"]);
const LOCALES = new Set(["en-US", "vi-VN"]);
const INTERACTION_MODES = new Set(["READ_ONLY", "FLASHCARD_REVIEW", "GOVERNANCE_DRAFT"]);
const HASH_PATTERN = /^sha256:[a-f0-9]{64}$/;
const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const FORBIDDEN_KEYS = new Set([
  "dax",
  "sql",
  "table",
  "column",
  "measure",
  "workspaceid",
  "userid",
  "userprincipalname",
  "role",
  "rls",
  "authorization",
  "approvalstate",
]);

export interface ResolverOptions {
  flashcards?: FlashcardDefinition[];
  now?: () => Date;
}

interface ValidationFailure {
  code: string;
  detail: string;
}

interface BoundEvidence {
  metrics: BoundMetric[];
  rows: BoundRow[];
  series: BoundSeriesPoint[];
  subtitle: string;
  title: string;
}

function ownKeys(value: object): string[] {
  return Object.keys(value);
}

function hasForbiddenKey(value: unknown): string | null {
  if (Array.isArray(value)) {
    for (const item of value) {
      const found = hasForbiddenKey(item);
      if (found) return found;
    }
    return null;
  }
  if (!value || typeof value !== "object") return null;

  for (const [key, nested] of Object.entries(value)) {
    if (FORBIDDEN_KEYS.has(key.replace(/[^a-z0-9]/gi, "").toLowerCase())) {
      return key;
    }
    const found = hasForbiddenKey(nested);
    if (found) return found;
  }
  return null;
}

function unknownKey(value: object, allowed: Set<string>): string | null {
  return ownKeys(value).find((key) => !allowed.has(key)) ?? null;
}

function isString(value: unknown, max = 240): value is string {
  return typeof value === "string" && value.trim().length > 0 && value.length <= max;
}

function isFiniteNumber(value: unknown): value is number {
  return typeof value === "number" && Number.isFinite(value);
}

function makeExpiresAt(now: Date): string {
  return new Date(now.getTime() + PRESENTATION_LIMITS.ttlMinutes * 60_000).toISOString();
}

function canonicalize(value: unknown): string {
  if (value === null || typeof value !== "object") return JSON.stringify(value);
  if (Array.isArray(value)) return `[${value.map(canonicalize).join(",")}]`;
  return `{${Object.keys(value as Record<string, unknown>)
    .sort()
    .map((key) => `${JSON.stringify(key)}:${canonicalize((value as Record<string, unknown>)[key])}`)
    .join(",")}}`;
}

export async function sha256Hex(value: unknown): Promise<string> {
  const bytes = new TextEncoder().encode(canonicalize(value));
  const digest = await globalThis.crypto.subtle.digest("SHA-256", bytes);
  return `sha256:${Array.from(new Uint8Array(digest), (byte) => byte.toString(16).padStart(2, "0")).join("")}`;
}

function validateRequest(request: PresentationRequest): ValidationFailure | null {
  const unknown = unknownKey(
    request,
    new Set([
      "contractVersion",
      "requestId",
      "querySpecHash",
      "presentationHint",
      "channelProfile",
      "locale",
      "interactionMode",
      "conceptId",
      "workflowId",
    ]),
  );
  if (unknown) return { code: "UNKNOWN_REQUEST_FIELD", detail: unknown };
  if (request.contractVersion !== PRESENTATION_CONTRACT_VERSION) {
    return { code: "REQUEST_VERSION", detail: "unsupported presentation contract" };
  }
  if (!UUID_PATTERN.test(request.requestId)) return { code: "REQUEST_ID", detail: "invalid request id" };
  if (!HASH_PATTERN.test(request.querySpecHash)) return { code: "QUERY_HASH", detail: "invalid query hash" };
  if (!CHANNEL_PROFILE_IDS.has(request.channelProfile as string)) {
    return { code: "CHANNEL_PROFILE", detail: "unsupported channel profile" };
  }
  if (!LOCALES.has(request.locale as string)) return { code: "LOCALE", detail: "unsupported locale" };
  if (!INTERACTION_MODES.has(request.interactionMode as string)) {
    return { code: "INTERACTION_MODE", detail: "unsupported interaction mode" };
  }
  const hint = request.presentationHint as string;
  if (!["AUTO", "KPI_CARD", "TABLE", "TREND", "FLASHCARD", "FORM", "TEXT_FALLBACK"].includes(hint)) {
    return { code: "UNKNOWN_HINT", detail: "unsupported presentation hint" };
  }
  if (request.interactionMode === "FLASHCARD_REVIEW" && !request.conceptId) {
    return { code: "CONCEPT_REQUIRED", detail: "curated concept is required" };
  }
  if (request.interactionMode === "GOVERNANCE_DRAFT" && request.workflowId !== "forecast_governance_draft") {
    return { code: "WORKFLOW_REQUIRED", detail: "unsupported governance workflow" };
  }
  if (request.presentationHint === "FLASHCARD" && request.interactionMode !== "FLASHCARD_REVIEW") {
    return { code: "FLASHCARD_INTENT", detail: "flashcard requires learning mode" };
  }
  if (request.presentationHint === "FORM" && request.interactionMode !== "GOVERNANCE_DRAFT") {
    return { code: "FORM_INTENT", detail: "form requires governance draft mode" };
  }
  return null;
}

function validateProfile(request: PresentationRequest, profile: ChannelProfile): ValidationFailure | null {
  if (profile.profileId !== request.channelProfile) {
    return { code: "PROFILE_MISMATCH", detail: "channel profile does not match request" };
  }
  if (profile.supportsActionExecute) {
    return { code: "ACTION_EXECUTE_POLICY", detail: "Action.Execute is disabled for this MVP" };
  }
  if (profile.maxRows < 1 || profile.maxRows > PRESENTATION_LIMITS.maxEvidenceRows) {
    return { code: "PROFILE_LIMIT", detail: "invalid row limit" };
  }
  return null;
}

function validateEvidence(evidence: EvidenceEnvelope, request: PresentationRequest): ValidationFailure | null {
  const unknown = unknownKey(
    evidence,
    new Set([
      "status",
      "evidenceId",
      "querySpecHash",
      "daxHash",
      "templateId",
      "governanceVersion",
      "semanticModelId",
      "queryId",
      "executedAt",
      "rowCount",
      "metrics",
      "context",
      "rows",
      "series",
    ]),
  );
  if (unknown) return { code: "UNKNOWN_EVIDENCE_FIELD", detail: unknown };
  const forbidden = hasForbiddenKey(evidence);
  if (forbidden) return { code: "FORBIDDEN_EVIDENCE_FIELD", detail: forbidden };
  if (evidence.status !== "OK") return { code: evidence.status, detail: "evidence is not OK" };
  if (!UUID_PATTERN.test(evidence.evidenceId) || !UUID_PATTERN.test(evidence.queryId)) {
    return { code: "EVIDENCE_ID", detail: "invalid evidence or query id" };
  }
  if (evidence.querySpecHash !== request.querySpecHash) {
    return { code: "QUERY_HASH_MISMATCH", detail: "evidence does not bind to request" };
  }
  if (!HASH_PATTERN.test(evidence.daxHash)) return { code: "DAX_HASH", detail: "invalid evidence hash" };
  if (evidence.governanceVersion !== GOVERNED_VERSION) {
    return { code: "GOVERNANCE_VERSION", detail: "unsupported governance version" };
  }
  if (evidence.semanticModelId !== GOVERNED_SEMANTIC_MODEL_ID) {
    return { code: "SEMANTIC_MODEL", detail: "unexpected semantic model" };
  }
  if (!QUERY_TEMPLATE_IDS.has(evidence.templateId)) {
    return { code: "QUERY_TEMPLATE", detail: "unregistered query template" };
  }
  if (!Number.isInteger(evidence.rowCount) || evidence.rowCount < 0 || evidence.rowCount > PRESENTATION_LIMITS.maxEvidenceRows) {
    return { code: "ROW_COUNT", detail: "evidence row count is outside the contract" };
  }
  if (!evidence.context || typeof evidence.context !== "object") {
    return { code: "CONTEXT", detail: "evidence context must be an object" };
  }
  if (!isString(evidence.context.periodLabel) || !isString(evidence.context.horizonLabel) || !isString(evidence.context.scopeLabel)) {
    return { code: "CONTEXT", detail: "incomplete evidence context" };
  }
  if (Number.isNaN(Date.parse(evidence.executedAt))) {
    return { code: "EXECUTED_AT", detail: "invalid execution timestamp" };
  }
  if (!Array.isArray(evidence.metrics)) return { code: "METRICS", detail: "metrics must be an array" };
  if (evidence.rows !== undefined && !Array.isArray(evidence.rows)) {
    return { code: "ROWS", detail: "rows must be an array" };
  }
  if (evidence.series !== undefined && !Array.isArray(evidence.series)) {
    return { code: "SERIES", detail: "series must be an array" };
  }
  for (const metric of evidence.metrics) {
    const failure = validateMetric(metric);
    if (failure) return failure;
  }
  for (const row of evidence.rows ?? []) {
    const failure = validateRow(row);
    if (failure) return failure;
  }
  for (const point of evidence.series ?? []) {
    const failure = validateSeriesPoint(point);
    if (failure) return failure;
  }
  if ((evidence.rows?.length ?? 0) > PRESENTATION_LIMITS.maxEvidenceRows) {
    return { code: "ROW_COUNT", detail: "too many evidence rows" };
  }
  if ((evidence.series?.length ?? 0) > PRESENTATION_LIMITS.maxTrendPoints) {
    return { code: "SERIES_COUNT", detail: "too many trend points" };
  }
  return null;
}

function validateMetric(metric: EvidenceMetric): ValidationFailure | null {
  if (unknownKey(metric, new Set(["metricId", "value", "unit"]))) {
    return { code: "METRIC_FIELDS", detail: "unknown metric field" };
  }
  const definition = METRIC_DEFINITIONS[metric.metricId];
  if (!definition) return { code: "UNKNOWN_METRIC", detail: metric.metricId };
  if (metric.unit !== definition.unit) return { code: "METRIC_UNIT", detail: metric.metricId };
  if (!isFiniteNumber(metric.value)) return { code: "BLANK_METRIC", detail: metric.metricId };
  return null;
}

function validateRow(row: EvidenceRow): ValidationFailure | null {
  if (unknownKey(row, new Set(["label", "value", "metricId", "secondaryLabel"]))) {
    return { code: "ROW_FIELDS", detail: "unknown row field" };
  }
  if (!isString(row.label) || !isFiniteNumber(row.value)) return { code: "BLANK_ROW", detail: row.label };
  if (!METRIC_DEFINITIONS[row.metricId]) return { code: "UNKNOWN_METRIC", detail: row.metricId };
  if (row.secondaryLabel !== undefined && !isString(row.secondaryLabel)) {
    return { code: "ROW_LABEL", detail: "invalid secondary label" };
  }
  return null;
}

function validateSeriesPoint(point: EvidenceSeriesPoint): ValidationFailure | null {
  if (unknownKey(point, new Set(["label", "value", "metricId", "sortKey"]))) {
    return { code: "SERIES_FIELDS", detail: "unknown series field" };
  }
  if (!isString(point.label, 80) || !isFiniteNumber(point.value) || !isString(point.sortKey, 80)) {
    return { code: "BLANK_SERIES_POINT", detail: point.label };
  }
  if (!METRIC_DEFINITIONS[point.metricId]) return { code: "UNKNOWN_METRIC", detail: point.metricId };
  return null;
}

function boundMetric(metric: EvidenceMetric, locale: PresentationRequest["locale"]): BoundMetric {
  const definition = METRIC_DEFINITIONS[metric.metricId];
  return {
    metricId: metric.metricId,
    label: definition.label,
    value: metric.value as number,
    displayValue: formatMetricValue(metric.metricId, metric.value as number, locale),
    unit: definition.unit,
  };
}

function boundRow(row: EvidenceRow, locale: PresentationRequest["locale"]): BoundRow {
  return {
    label: sanitizeLabel(row.label),
    displayValue: formatMetricValue(row.metricId, row.value as number, locale),
    metricId: row.metricId,
    ...(row.secondaryLabel ? { secondaryLabel: sanitizeLabel(row.secondaryLabel) } : {}),
  };
}

function boundSeriesPoint(point: EvidenceSeriesPoint, locale: PresentationRequest["locale"]): BoundSeriesPoint {
  return {
    label: sanitizeLabel(point.label, 80),
    displayValue: formatMetricValue(point.metricId, point.value as number, locale),
    value: point.value as number,
    metricId: point.metricId,
    sortKey: point.sortKey,
  };
}

function makeActions(
  requestId: string,
  evidenceId: string,
  templateId: string,
  includeTrend: boolean,
): PresentationAction[] {
  const actions: PresentationAction[] = [
    {
      actionId: "evidence.open",
      label: "Open evidence",
      style: "secondary",
      payload: { requestId, evidenceId, templateId },
    },
  ];
  if (includeTrend) {
    actions.push({
      actionId: "followup.trend",
      label: "Show trend",
      style: "subtle",
      payload: { requestId, evidenceId, templateId },
    });
  }
  return actions;
}

function contextSubtitle(evidence: EvidenceEnvelope): string {
  return `${sanitizeLabel(evidence.context.periodLabel)}, ${sanitizeLabel(evidence.context.horizonLabel)}, ${sanitizeLabel(evidence.context.scopeLabel)}`;
}

function numericFallback(bound: BoundEvidence, evidenceId: string): string {
  const primary = bound.metrics[0] ?? bound.rows[0];
  if (!primary) return "A governed result is available. Open evidence for details.";
  const value = "displayValue" in primary ? primary.displayValue : "";
  return `${bound.title}: ${value}. ${bound.subtitle}. Evidence ${evidenceId}.`;
}

function invalidFallback(
  request: PresentationRequest,
  now: Date,
  reasonCode: ReasonCode,
  message: string,
): PresentationEnvelope {
  return {
    contractVersion: PRESENTATION_CONTRACT_VERSION,
    requestId: request.requestId,
    evidenceId: null,
    evidenceHash: null,
    presentationType: "TEXT_FALLBACK",
    templateId: "forecast.text.v1",
    channelProfile: request.channelProfile,
    locale: request.locale,
    title: "Governed result unavailable",
    subtitle: "",
    data: { metrics: [], rows: [], series: [] },
    actions: [],
    accessibility: {
      summary: "No governed number is available for this request.",
      readingOrder: ["title", "fallback message"],
    },
    fallback: {
      templateId: "forecast.text.v1",
      text: `${message} No governed number is available.`,
    },
    expiresAt: makeExpiresAt(now),
    reasonCode,
  };
}

function flashcardEnvelope(
  request: PresentationRequest,
  card: FlashcardDefinition,
  now: Date,
): PresentationEnvelope {
  const fallback = `${card.front} Answer: ${card.answer}`;
  return {
    contractVersion: PRESENTATION_CONTRACT_VERSION,
    requestId: request.requestId,
    evidenceId: null,
    evidenceHash: null,
    presentationType: "FLASHCARD",
    templateId: "forecast.flashcard.v1",
    channelProfile: request.channelProfile,
    locale: request.locale,
    title: "Study card",
    subtitle: "Curated concept with user-scoped review state",
    data: {
      metrics: [],
      rows: [],
      series: [],
      flashcard: {
        conceptId: card.conceptId,
        front: card.front,
        answer: card.answer,
        explanation: card.explanation,
        sourceLabel: card.sourceLabel,
      },
    },
    actions: [
      {
        actionId: "flashcard.reveal",
        label: "Reveal answer",
        style: "secondary",
        payload: { requestId: request.requestId, conceptId: card.conceptId },
      },
      {
        actionId: "flashcard.rate",
        label: "Rate review",
        style: "primary",
        payload: { requestId: request.requestId, conceptId: card.conceptId },
      },
    ],
    accessibility: {
      summary: `${card.front}. Answer hidden until reveal.`,
      readingOrder: ["front", "reveal action", "rating actions", "source"],
    },
    fallback: { templateId: "forecast.text.v1", text: fallback },
    expiresAt: makeExpiresAt(now),
    reasonCode: "LEARNING_INTENT",
  };
}

function formEnvelope(request: PresentationRequest, now: Date): PresentationEnvelope {
  const form = {
    workflowId: "forecast_governance_draft" as const,
    title: "Create a governance draft",
    notice: "This creates a draft request only. It does not approve, notify, or change a metric.",
    fields: [
      { id: "subject" as const, label: "Subject", inputType: "text" as const, required: true },
      {
        id: "requestType" as const,
        label: "Request type",
        inputType: "choice" as const,
        required: true,
        options: ["Metric definition review", "Data quality investigation", "Access or scope question"],
      },
      { id: "businessReason" as const, label: "Business reason", inputType: "text" as const, required: true },
    ],
  };
  return {
    contractVersion: PRESENTATION_CONTRACT_VERSION,
    requestId: request.requestId,
    evidenceId: null,
    evidenceHash: null,
    presentationType: "FORM",
    templateId: "forecast.governance-form.v1",
    channelProfile: request.channelProfile,
    locale: request.locale,
    title: "Governance draft request",
    subtitle: "Draft only. No approval or operational write.",
    data: { metrics: [], rows: [], series: [], form },
    actions: [
      {
        actionId: "governance.draft.submit",
        label: "Create draft",
        style: "primary",
        payload: { requestId: request.requestId, workflowId: form.workflowId },
      },
    ],
    accessibility: {
      summary: "A form that creates a governance draft only.",
      readingOrder: ["title", "notice", "subject", "request type", "business reason", "submit"],
    },
    fallback: {
      templateId: "forecast.text.v1",
      text: "A governance draft can be created. It will not approve, notify, or change a metric.",
    },
    expiresAt: makeExpiresAt(now),
    reasonCode: "GOVERNANCE_DRAFT_INTENT",
  };
}

function chooseTemplate(
  type: PresentationType,
  profile: ChannelProfile,
): { type: PresentationType; templateId: string; hostFallback: boolean } {
  if (type === "TREND" && !profile.supportsRichTrend) {
    return { type: "TABLE", templateId: "forecast.table.v1", hostFallback: true };
  }
  if (type === "FLASHCARD" && !profile.supportsToggleVisibility && !profile.supportsShowCard) {
    return { type: "TEXT_FALLBACK", templateId: "forecast.text.v1", hostFallback: true };
  }
  if (type === "FORM" && !profile.supportsActionSubmit) {
    return { type: "TEXT_FALLBACK", templateId: "forecast.text.v1", hostFallback: true };
  }
  const templateByType: Record<PresentationType, string> = {
    KPI_CARD: "forecast.kpi.v1",
    TABLE: "forecast.table.v1",
    TREND: "forecast.trend.v1",
    FLASHCARD: "forecast.flashcard.v1",
    FORM: "forecast.governance-form.v1",
    TEXT_FALLBACK: "forecast.text.v1",
  };
  return { type, templateId: templateByType[type], hostFallback: false };
}

export async function resolvePresentation(
  request: PresentationRequest,
  evidence: EvidenceEnvelope | null,
  profile: ChannelProfile,
  options: ResolverOptions = {},
): Promise<PresentationEnvelope> {
  const now = options.now?.() ?? new Date();
  const requestFailure = validateRequest(request);
  if (requestFailure) {
    return invalidFallback(request, now, "INVALID_EVIDENCE", `Request rejected: ${requestFailure.code}.`);
  }
  const profileFailure = validateProfile(request, profile);
  if (profileFailure) {
    return invalidFallback(request, now, "INVALID_EVIDENCE", `Channel rejected: ${profileFailure.code}.`);
  }

  if (request.interactionMode === "GOVERNANCE_DRAFT") {
    return formEnvelope(request, now);
  }

  if (request.interactionMode === "FLASHCARD_REVIEW") {
    const card = options.flashcards?.find((candidate) => candidate.conceptId === request.conceptId);
    if (!card) return invalidFallback(request, now, "NO_REGISTERED_TEMPLATE", "The study concept is not registered.");
    const selected = chooseTemplate("FLASHCARD", profile);
    if (selected.type === "TEXT_FALLBACK") {
      return invalidFallback(request, now, "HOST_CAPABILITY_FALLBACK", "This channel cannot render the study interaction.");
    }
    return flashcardEnvelope(request, card, now);
  }

  if (!evidence) return invalidFallback(request, now, "INVALID_EVIDENCE", "The governed evidence envelope is missing.");
  const evidenceFailure = validateEvidence(evidence, request);
  if (evidenceFailure) {
    const reason = evidenceFailure.code === "ROW_COUNT" || evidenceFailure.code === "SERIES_COUNT"
      ? "ROW_LIMIT_BLOCK"
      : "INVALID_EVIDENCE";
    return invalidFallback(request, now, reason, `Evidence rejected: ${evidenceFailure.code}.`);
  }

  const metrics = evidence.metrics.map((metric) => boundMetric(metric, request.locale));
  const rows = (evidence.rows ?? []).map((row) => boundRow(row, request.locale));
  const series = (evidence.series ?? []).map((point) => boundSeriesPoint(point, request.locale));
  const bound: BoundEvidence = {
    metrics,
    rows,
    series,
    title: metrics[0]?.label ?? METRIC_DEFINITIONS[rows[0]?.metricId ?? ""]?.label ?? "Forecast result",
    subtitle: contextSubtitle(evidence),
  };
  let selectedType: PresentationType;
  let reasonCode: ReasonCode;
  let tableRows = rows;

  if (series.length > 0) {
    if (series.length < PRESENTATION_LIMITS.minTrendPoints || series.length > PRESENTATION_LIMITS.maxTrendPoints) {
      return invalidFallback(request, now, "ROW_LIMIT_BLOCK", "The trend point count is outside the published limit.");
    }
    selectedType = request.presentationHint === "TABLE" || !profile.supportsRichTrend ? "TABLE" : "TREND";
    reasonCode = selectedType === "TREND" ? "SERIES_MATCH" : "HOST_CAPABILITY_FALLBACK";
    tableRows = series.map((point) => ({
      label: point.label,
      displayValue: point.displayValue,
      metricId: point.metricId,
    }));
  } else if (metrics.length > 0 && metrics.length <= PRESENTATION_LIMITS.maxMetrics && rows.length <= 1) {
    selectedType = "KPI_CARD";
    reasonCode = "SCALAR_MATCH";
  } else if (rows.length >= 2 && rows.length <= Math.min(profile.maxRows, PRESENTATION_LIMITS.maxTableRows)) {
    selectedType = "TABLE";
    reasonCode = "SMALL_TABLE_MATCH";
  } else if (rows.length > PRESENTATION_LIMITS.maxTableRows || evidence.rowCount > profile.maxRows) {
    return invalidFallback(request, now, "ROW_LIMIT_BLOCK", "The result is too large for a safe presentation.");
  } else {
    return invalidFallback(request, now, "NO_REGISTERED_TEMPLATE", "The evidence shape has no registered presentation.");
  }

  const selected = chooseTemplate(selectedType, profile);
  if (selected.type === "TEXT_FALLBACK") {
    return invalidFallback(request, now, "HOST_CAPABILITY_FALLBACK", "This channel cannot render the requested interaction.");
  }
  const evidenceHash = await sha256Hex(evidence);
  const actions = makeActions(request.requestId, evidence.evidenceId, selected.templateId, selectedType !== "TREND");
  if (selectedType === "KPI_CARD") {
    actions.push({
      actionId: "followup.compare",
      label: "Compare",
      style: "subtle",
      payload: { requestId: request.requestId, evidenceId: evidence.evidenceId, templateId: selected.templateId },
    });
  }
  const fallback = numericFallback(bound, evidence.evidenceId);
  return {
    contractVersion: PRESENTATION_CONTRACT_VERSION,
    requestId: request.requestId,
    evidenceId: evidence.evidenceId,
    evidenceHash,
    presentationType: selected.type,
    templateId: selected.templateId,
    channelProfile: request.channelProfile,
    locale: request.locale,
    title: bound.title,
    subtitle: bound.subtitle,
    data: {
      metrics,
      rows: selected.type === "TABLE" ? tableRows : rows,
      series,
    },
    actions,
    accessibility: {
      summary: `${bound.title} for ${bound.subtitle}. ${fallback}`,
      readingOrder: selected.type === "TREND"
        ? ["title", "subtitle", "trend chart", "data table", "evidence actions"]
        : ["title", "subtitle", "primary result", "evidence actions"],
    },
    fallback: { templateId: "forecast.text.v1", text: fallback },
    expiresAt: makeExpiresAt(now),
    reasonCode: selected.hostFallback ? "HOST_CAPABILITY_FALLBACK" : reasonCode,
  };
}
