import type { FlowResponse, PresentationEnvelope } from "../contracts/types.js";

/**
 * Reference wrapper for the Power Automate `Respond to the agent` contract.
 * The Flow must emit this same shape from every Switch branch.
 */
export function toFlowResponse(presentationEnvelope: PresentationEnvelope): FlowResponse {
  const noGovernedEvidence = presentationEnvelope.presentationType === "TEXT_FALLBACK"
    && ["INVALID_EVIDENCE", "ROW_LIMIT_BLOCK"].includes(presentationEnvelope.reasonCode);

  return {
    contractVersion: "1.0.0",
    status: noGovernedEvidence ? "NO_GOVERNED_EVIDENCE" : "OK",
    presentationEnvelope,
    trace: {
      requestId: presentationEnvelope.requestId,
      evidenceId: presentationEnvelope.evidenceId,
      reasonCode: presentationEnvelope.reasonCode,
    },
    events: presentationEnvelope.events,
  };
}
