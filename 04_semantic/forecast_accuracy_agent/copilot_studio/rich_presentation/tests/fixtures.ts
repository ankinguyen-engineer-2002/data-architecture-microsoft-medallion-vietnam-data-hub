import type {
  ChannelProfile,
  EvidenceEnvelope,
  FlashcardDefinition,
  PresentationRequest,
} from "../contracts/types.js";

export const FIXED_NOW = new Date("2026-08-21T08:00:00.000Z");
export const QUERY_HASH = "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855";
export const MODEL_ID = "2fbc4dfc-96d1-4af6-9987-4c14639435e6";

export const profiles: Record<string, ChannelProfile> = {
  WEB_RICH_V1: {
    profileId: "WEB_RICH_V1",
    displayName: "Authenticated custom Web Chat",
    adaptiveCardVersion: "1.5",
    supportsActionSubmit: true,
    supportsToggleVisibility: true,
    supportsShowCard: true,
    supportsActionExecute: false,
    supportsRichTrend: true,
    supportsCustomClientEvents: true,
    maxRows: 25,
    maxSeriesPoints: 24,
    fallbacks: { TREND: "TABLE", FLASHCARD: "TEXT_FALLBACK", FORM: "TEXT_FALLBACK" },
  },
  TEAMS_AC15: {
    profileId: "TEAMS_AC15",
    displayName: "Microsoft Teams Adaptive Card 1.5",
    adaptiveCardVersion: "1.5",
    supportsActionSubmit: true,
    supportsToggleVisibility: true,
    supportsShowCard: true,
    supportsActionExecute: false,
    supportsRichTrend: false,
    supportsCustomClientEvents: false,
    maxRows: 8,
    maxSeriesPoints: 24,
    fallbacks: { TREND: "TABLE" },
  },
  M365_LIMITED: {
    profileId: "M365_LIMITED",
    displayName: "Microsoft 365 Copilot conservative card",
    adaptiveCardVersion: "1.5",
    supportsActionSubmit: true,
    supportsToggleVisibility: false,
    supportsShowCard: false,
    supportsActionExecute: false,
    supportsRichTrend: false,
    supportsCustomClientEvents: false,
    maxRows: 8,
    maxSeriesPoints: 24,
    fallbacks: { TREND: "TABLE", FLASHCARD: "TEXT_FALLBACK", FORM: "TEXT_FALLBACK" },
  },
  COPILOT_TEST: {
    profileId: "COPILOT_TEST",
    displayName: "Copilot Studio test canvas",
    adaptiveCardVersion: "1.5",
    supportsActionSubmit: true,
    supportsToggleVisibility: true,
    supportsShowCard: true,
    supportsActionExecute: false,
    supportsRichTrend: false,
    supportsCustomClientEvents: false,
    maxRows: 8,
    maxSeriesPoints: 24,
    fallbacks: { TREND: "TABLE" },
  },
};

export const flashcards: FlashcardDefinition[] = [
  {
    conceptId: "forecast_accuracy_basics",
    front: "What does Forecast Accuracy represent in the governed KPI profile?",
    answer: "Forecast Accuracy is one minus the approved weighted MAPE in the current fiscal context.",
    explanation: "It is a semantic-model measure with a positive governed Actual Demand guard.",
    sourceLabel: "Forecast metric registry",
    tags: ["forecast", "accuracy"],
  },
];

export function request(overrides: Partial<PresentationRequest> = {}): PresentationRequest {
  return {
    contractVersion: "1.0.0",
    requestId: "11111111-1111-4111-8111-111111111111",
    querySpecHash: QUERY_HASH,
    presentationHint: "AUTO",
    channelProfile: "WEB_RICH_V1",
    locale: "en-US",
    interactionMode: "READ_ONLY",
    ...overrides,
  };
}

function baseEvidence(partial: Partial<EvidenceEnvelope>): EvidenceEnvelope {
  return {
    status: "OK",
    evidenceId: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
    querySpecHash: QUERY_HASH,
    daxHash: "sha256:0000000000000000000000000000000000000000000000000000000000000000",
    templateId: "KPI_SCALAR_V1",
    governanceVersion: "forecast-metrics-1.0.0",
    semanticModelId: MODEL_ID,
    queryId: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb",
    executedAt: "2026-08-21T08:00:00.000Z",
    rowCount: 1,
    metrics: [{ metricId: "forecast_accuracy", value: 0.3959006542885988, unit: "percent" }],
    context: {
      periodLabel: "Fiscal July 2026",
      horizonLabel: "Lag-0",
      scopeLabel: "Total scope",
      filters: ["Fiscal July 2026", "Lag-0"],
    },
    ...partial,
  };
}

export function scalarEvidence(): EvidenceEnvelope {
  return baseEvidence({
    rows: [{ label: "Total scope", value: 0.3959006542885988, metricId: "forecast_accuracy" }],
  });
}

export function tableEvidence(): EvidenceEnvelope {
  return baseEvidence({
    templateId: "KPI_BREAKDOWN_V1",
    rowCount: 3,
    metrics: [],
    rows: [
      { label: "AFI", value: 0.44, metricId: "forecast_accuracy" },
      { label: "ASH", value: 0.39, metricId: "forecast_accuracy" },
      { label: "West", value: 0.36, metricId: "forecast_accuracy" },
    ],
  });
}

export function trendEvidence(pointCount = 6): EvidenceEnvelope {
  const series = Array.from({ length: pointCount }, (_, index) => ({
    label: `M${index + 1}`,
    value: 0.4 + index / 100,
    metricId: "forecast_accuracy",
    sortKey: `2026-${String(index + 1).padStart(2, "0")}`,
  }));
  return baseEvidence({
    templateId: "KPI_TREND_V1",
    rowCount: pointCount,
    series,
  });
}

export function noEvidence(): EvidenceEnvelope {
  return baseEvidence({
    status: "NO_GOVERNED_EVIDENCE",
    rowCount: 0,
    metrics: [],
    rows: [],
  });
}
