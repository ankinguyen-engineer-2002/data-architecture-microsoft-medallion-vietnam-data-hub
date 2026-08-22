import type {
  ChannelProfile,
  EvidenceEnvelope,
  FlowRouterInput,
  PresentationRequest,
} from "../contracts/types.js";

/**
 * Derive the only facts the finite Power Automate router needs.
 * Call this after request/evidence validation; the profile is trusted runtime context.
 */
export function deriveFlowRouterInput(
  request: PresentationRequest,
  evidence: EvidenceEnvelope | null,
  profile: ChannelProfile,
): FlowRouterInput {
  const evidenceStatus = evidence?.status ?? "NO_GOVERNED_EVIDENCE";
  const isValid = evidenceStatus === "OK";
  const metricCount = isValid ? evidence?.metrics.length ?? 0 : 0;
  const rowCount = isValid ? evidence?.rowCount ?? 0 : 0;
  const seriesPointCount = isValid ? evidence?.series?.length ?? 0 : 0;
  const resultShape = !isValid
    ? "NONE"
    : seriesPointCount > 0
      ? "SERIES"
      : metricCount > 0 && rowCount <= 1
        ? "SCALAR"
        : rowCount > 0
          ? "TABLE"
          : "NONE";

  return {
    contractVersion: "1.0.0",
    evidenceStatus,
    interactionMode: request.interactionMode,
    ...(request.workflowId ? { workflowId: request.workflowId } : {}),
    ...(request.conceptId ? { conceptId: request.conceptId } : {}),
    resultShape,
    metricCount,
    rowCount,
    seriesPointCount,
    // Never copy the profile from request text; use the trusted runtime object.
    channelProfile: profile.profileId,
    supportsRichTrend: profile.supportsRichTrend,
    presentationHint: request.presentationHint,
  };
}
