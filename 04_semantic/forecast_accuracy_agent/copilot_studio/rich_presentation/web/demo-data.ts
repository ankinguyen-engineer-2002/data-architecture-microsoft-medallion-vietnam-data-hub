import type {
  ChannelProfile,
  EvidenceEnvelope,
  FlashcardDefinition,
  PresentationRequest,
} from "../contracts/types.js";
import channelProfiles from "../registry/channel-profiles.json";
import flashcardRegistry from "../registry/flashcard-registry.json";

export const QUERY_HASH = "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855";

export const profiles = Object.fromEntries(
  channelProfiles.map((profile) => [profile.profileId, profile]),
) as Record<string, ChannelProfile>;

export const flashcards = flashcardRegistry.concepts as FlashcardDefinition[];

const commonEvidence = {
  status: "OK" as const,
  evidenceId: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
  querySpecHash: QUERY_HASH,
  daxHash: "sha256:0000000000000000000000000000000000000000000000000000000000000000",
  governanceVersion: "forecast-metrics-1.0.0",
  semanticModelId: "2fbc4dfc-96d1-4af6-9987-4c14639435e6",
  queryId: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb",
  executedAt: "2026-08-21T08:00:00.000Z",
  context: {
    periodLabel: "Fiscal July 2026",
    horizonLabel: "Lag-0",
    scopeLabel: "Total scope",
    filters: ["Fiscal July 2026", "Lag-0"],
  },
};

export function evidenceFor(scenario: "kpi" | "trend" | "table"): EvidenceEnvelope {
  if (scenario === "kpi") {
    return {
      ...commonEvidence,
      templateId: "KPI_SCALAR_V1",
      rowCount: 1,
      metrics: [{ metricId: "forecast_accuracy", value: 0.3959006542885988, unit: "percent" }],
      rows: [{ label: "Total scope", value: 0.3959006542885988, metricId: "forecast_accuracy" }],
    };
  }

  if (scenario === "table") {
    return {
      ...commonEvidence,
      evidenceId: "eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee",
      templateId: "KPI_BREAKDOWN_V1",
      rowCount: 3,
      metrics: [],
      rows: [
        { label: "AFI", value: 0.44, metricId: "forecast_accuracy", secondaryLabel: "Warehouse group" },
        { label: "ASH", value: 0.39, metricId: "forecast_accuracy", secondaryLabel: "Warehouse group" },
        { label: "West", value: 0.36, metricId: "forecast_accuracy", secondaryLabel: "Warehouse group" },
      ],
    };
  }

  return {
    ...commonEvidence,
    evidenceId: "cccccccc-cccc-4ccc-8ccc-cccccccccccc",
    templateId: "KPI_TREND_V1",
    rowCount: 6,
    metrics: [{ metricId: "forecast_accuracy", value: 0.45, unit: "percent" }],
    series: [
      { label: "Jan", value: 0.42, metricId: "forecast_accuracy", sortKey: "2026-01" },
      { label: "Feb", value: 0.44, metricId: "forecast_accuracy", sortKey: "2026-02" },
      { label: "Mar", value: 0.41, metricId: "forecast_accuracy", sortKey: "2026-03" },
      { label: "Apr", value: 0.46, metricId: "forecast_accuracy", sortKey: "2026-04" },
      { label: "May", value: 0.48, metricId: "forecast_accuracy", sortKey: "2026-05" },
      { label: "Jun", value: 0.45, metricId: "forecast_accuracy", sortKey: "2026-06" },
    ],
  };
}

export function requestFor(
  scenario: "kpi" | "trend" | "table" | "flashcard" | "form",
  channelProfile: "WEB_RICH_V1" = "WEB_RICH_V1",
): PresentationRequest {
  const requestId = globalThis.crypto?.randomUUID?.() ?? "11111111-1111-4111-8111-111111111111";
  if (scenario === "flashcard") {
    return {
      contractVersion: "1.0.0",
      requestId,
      querySpecHash: QUERY_HASH,
      presentationHint: "FLASHCARD",
      channelProfile,
      locale: "en-US",
      interactionMode: "FLASHCARD_REVIEW",
      conceptId: "forecast_accuracy_basics",
    };
  }
  if (scenario === "form") {
    return {
      contractVersion: "1.0.0",
      requestId,
      querySpecHash: QUERY_HASH,
      presentationHint: "FORM",
      channelProfile,
      locale: "en-US",
      interactionMode: "GOVERNANCE_DRAFT",
      workflowId: "forecast_governance_draft",
    };
  }
  return {
    contractVersion: "1.0.0",
    requestId,
    querySpecHash: QUERY_HASH,
    presentationHint: scenario === "trend" ? "TREND" : scenario === "table" ? "TABLE" : "AUTO",
    channelProfile,
    locale: "en-US",
    interactionMode: "READ_ONLY",
  };
}
