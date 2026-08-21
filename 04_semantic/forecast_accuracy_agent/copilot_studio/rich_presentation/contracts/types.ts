export const PRESENTATION_TYPES = [
  "KPI_CARD",
  "TABLE",
  "TREND",
  "FLASHCARD",
  "FORM",
  "TEXT_FALLBACK",
] as const;

export type PresentationType = (typeof PRESENTATION_TYPES)[number];
export type PresentationHint = "AUTO" | PresentationType;
export type ChannelProfileId =
  | "WEB_RICH_V1"
  | "TEAMS_AC15"
  | "M365_LIMITED"
  | "COPILOT_TEST";
export type InteractionMode =
  | "READ_ONLY"
  | "FLASHCARD_REVIEW"
  | "GOVERNANCE_DRAFT";
export type EvidenceStatus =
  | "OK"
  | "NO_GOVERNED_EVIDENCE"
  | "INVALID_QUERY"
  | "UNAUTHORIZED"
  | "ERROR"
  | "STALE";
export type MetricUnit = "percent" | "quantity";
export type ReasonCode =
  | "SCALAR_MATCH"
  | "SERIES_MATCH"
  | "SMALL_TABLE_MATCH"
  | "LEARNING_INTENT"
  | "GOVERNANCE_DRAFT_INTENT"
  | "HOST_CAPABILITY_FALLBACK"
  | "ROW_LIMIT_BLOCK"
  | "INVALID_EVIDENCE"
  | "NO_REGISTERED_TEMPLATE";

export interface PresentationRequest {
  contractVersion: "1.0.0";
  requestId: string;
  querySpecHash: string;
  presentationHint: PresentationHint;
  channelProfile: ChannelProfileId;
  locale: "en-US" | "vi-VN";
  interactionMode: InteractionMode;
  conceptId?: string;
  workflowId?: "forecast_governance_draft";
}

export interface EvidenceContext {
  periodLabel: string;
  horizonLabel: string;
  scopeLabel: string;
  filters?: string[];
}

export interface EvidenceMetric {
  metricId: string;
  value: number | null;
  unit: MetricUnit;
}

export interface EvidenceRow {
  label: string;
  value: number | null;
  metricId: string;
  secondaryLabel?: string;
}

export interface EvidenceSeriesPoint {
  label: string;
  value: number | null;
  metricId: string;
  sortKey: string;
}

export interface EvidenceEnvelope {
  status: EvidenceStatus;
  evidenceId: string;
  querySpecHash: string;
  daxHash: string;
  templateId: string;
  governanceVersion: string;
  semanticModelId: string;
  queryId: string;
  executedAt: string;
  rowCount: number;
  metrics: EvidenceMetric[];
  context: EvidenceContext;
  rows?: EvidenceRow[];
  series?: EvidenceSeriesPoint[];
}

export interface BoundMetric {
  metricId: string;
  label: string;
  value: number;
  displayValue: string;
  unit: MetricUnit;
}

export interface BoundRow {
  label: string;
  displayValue: string;
  metricId: string;
  secondaryLabel?: string;
}

export interface BoundSeriesPoint {
  label: string;
  displayValue: string;
  value: number;
  metricId: string;
  sortKey: string;
}

export interface FlashcardData {
  conceptId: string;
  front: string;
  answer: string;
  explanation: string;
  sourceLabel: string;
}

export interface FormField {
  id: "subject" | "requestType" | "businessReason";
  label: string;
  inputType: "text" | "choice";
  required: boolean;
  options?: string[];
}

export interface FormData {
  workflowId: "forecast_governance_draft";
  title: string;
  fields: FormField[];
  notice: string;
}

export interface PresentationAction {
  actionId:
    | "evidence.open"
    | "followup.compare"
    | "followup.trend"
    | "flashcard.reveal"
    | "flashcard.rate"
    | "governance.draft.submit";
  label: string;
  style: "primary" | "secondary" | "subtle";
  payload: Record<string, string | number | boolean>;
}

export interface PresentationEnvelope {
  contractVersion: "1.0.0";
  requestId: string;
  evidenceId: string | null;
  evidenceHash: string | null;
  presentationType: PresentationType;
  templateId: string;
  channelProfile: ChannelProfileId;
  locale: "en-US" | "vi-VN";
  title: string;
  subtitle: string;
  data: {
    metrics: BoundMetric[];
    rows: BoundRow[];
    series: BoundSeriesPoint[];
    flashcard?: FlashcardData;
    form?: FormData;
  };
  actions: PresentationAction[];
  accessibility: {
    summary: string;
    readingOrder: string[];
  };
  fallback: {
    templateId: "forecast.text.v1";
    text: string;
  };
  expiresAt: string;
  reasonCode: ReasonCode;
}

export interface ChannelProfile {
  profileId: ChannelProfileId;
  displayName: string;
  adaptiveCardVersion: "1.5" | "1.6";
  supportsActionSubmit: boolean;
  supportsToggleVisibility: boolean;
  supportsShowCard: boolean;
  supportsActionExecute: false;
  supportsRichTrend: boolean;
  supportsCustomClientEvents: boolean;
  maxRows: number;
  maxSeriesPoints: number;
  fallbacks: Partial<Record<PresentationType, PresentationType>>;
}

export interface PresentationRegistryEntry {
  templateId: string;
  presentationType: PresentationType;
  schemaVersion: "1.5";
  registryVersion: "1.0.0";
  supportedProfiles: ChannelProfileId[];
  requiredPaths: string[];
  optionalPaths?: string[];
  limits: {
    metricCount?: number;
    rowCount?: number;
    seriesPointCount?: number;
  };
  allowedActions: PresentationAction["actionId"][];
  fallbackTemplateId: string;
}

export interface FlashcardDefinition extends FlashcardData {
  tags: string[];
}

export interface InteractionEnvelope {
  contractVersion: "1.0.0";
  interactionId: string;
  cardInstanceId: string;
  templateId: "forecast.flashcard.v1" | "forecast.governance-form.v1";
  actionId: "flashcard.reveal" | "flashcard.rate" | "governance.draft.submit";
  evidenceId: string | null;
  stateVersion: number;
  issuedAt: string;
  expiresAt: string;
  payload:
    | { action: "REVEAL" }
    | { rating: "AGAIN" | "HARD" | "KNOWN" }
    | {
        action: "CREATE_DRAFT";
        subject: string;
        requestType: string;
        businessReason: string;
      };
}

export interface FlashcardReviewState {
  cardInstanceId: string;
  conceptId: string;
  actorKey: string;
  stateVersion: number;
  reviewCount: number;
  nextReviewAt: string | null;
}

export interface InteractionReceipt {
  interactionId: string;
  status: "ACCEPTED" | "DUPLICATE" | "STALE" | "EXPIRED" | "INVALID";
  actionId: InteractionEnvelope["actionId"];
  stateVersion: number;
  nextReviewAt: string | null;
  draftStatus?: "DRAFT_CREATED";
  message: string;
}
