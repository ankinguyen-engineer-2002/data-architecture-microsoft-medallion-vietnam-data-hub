import type {
  FlashcardReviewState,
  InteractionEnvelope,
  InteractionReceipt,
} from "../contracts/types.js";

const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export class InteractionLedger {
  private readonly receipts = new Map<string, InteractionReceipt>();
  private readonly states = new Map<string, FlashcardReviewState>();

  seedFlashcard(state: FlashcardReviewState): void {
    this.states.set(this.stateKey(state.actorKey, state.cardInstanceId), { ...state });
  }

  getState(actorKey: string, cardInstanceId: string): FlashcardReviewState | null {
    const state = this.states.get(this.stateKey(actorKey, cardInstanceId));
    return state ? { ...state } : null;
  }

  submit(
    actorKey: string,
    envelope: InteractionEnvelope,
    now: Date,
  ): InteractionReceipt {
    const previous = this.receipts.get(envelope.interactionId);
    if (previous) return { ...previous };

    if (!UUID_PATTERN.test(envelope.interactionId) || !UUID_PATTERN.test(envelope.cardInstanceId)) {
      return this.record(envelope, {
        interactionId: envelope.interactionId,
        status: "INVALID",
        actionId: envelope.actionId,
        stateVersion: envelope.stateVersion,
        nextReviewAt: null,
        message: "Interaction identity is invalid.",
      });
    }
    const expiresAt = Date.parse(envelope.expiresAt);
    if (Number.isNaN(expiresAt) || expiresAt <= now.getTime()) {
      return this.record(envelope, {
        interactionId: envelope.interactionId,
        status: "EXPIRED",
        actionId: envelope.actionId,
        stateVersion: envelope.stateVersion,
        nextReviewAt: null,
        message: "This interaction has expired. Open a fresh card.",
      });
    }

    if (envelope.actionId === "governance.draft.submit") {
      if (envelope.templateId !== "forecast.governance-form.v1" || !this.isDraftPayload(envelope)) {
        return this.record(envelope, {
          interactionId: envelope.interactionId,
          status: "INVALID",
          actionId: envelope.actionId,
          stateVersion: envelope.stateVersion,
          nextReviewAt: null,
          message: "Draft payload is invalid.",
        });
      }
      return this.record(envelope, {
        interactionId: envelope.interactionId,
        status: "ACCEPTED",
        actionId: envelope.actionId,
        stateVersion: envelope.stateVersion,
        nextReviewAt: null,
        draftStatus: "DRAFT_CREATED",
        message: "Draft created. No approval or operational write was performed.",
      });
    }

    const state = this.states.get(this.stateKey(actorKey, envelope.cardInstanceId));
    if (!state) {
      return this.record(envelope, {
        interactionId: envelope.interactionId,
        status: "INVALID",
        actionId: envelope.actionId,
        stateVersion: envelope.stateVersion,
        nextReviewAt: null,
        message: "Review state was not found for this user and card.",
      });
    }
    if (state.stateVersion !== envelope.stateVersion) {
      return this.record(envelope, {
        interactionId: envelope.interactionId,
        status: "STALE",
        actionId: envelope.actionId,
        stateVersion: state.stateVersion,
        nextReviewAt: state.nextReviewAt,
        message: "This card is stale. Open the latest review card.",
      });
    }

    if (envelope.actionId === "flashcard.reveal" && this.isRevealPayload(envelope)) {
      return this.record(envelope, {
        interactionId: envelope.interactionId,
        status: "ACCEPTED",
        actionId: envelope.actionId,
        stateVersion: state.stateVersion,
        nextReviewAt: state.nextReviewAt,
        message: "Answer revealed. Review state is unchanged.",
      });
    }

    if (envelope.actionId !== "flashcard.rate" || !this.isRatingPayload(envelope)) {
      return this.record(envelope, {
        interactionId: envelope.interactionId,
        status: "INVALID",
        actionId: envelope.actionId,
        stateVersion: state.stateVersion,
        nextReviewAt: state.nextReviewAt,
        message: "Review action is invalid.",
      });
    }

    const nextReviewAt = this.nextReviewAt(envelope.payload.rating, now);
    const nextState: FlashcardReviewState = {
      ...state,
      stateVersion: state.stateVersion + 1,
      reviewCount: state.reviewCount + 1,
      nextReviewAt,
    };
    this.states.set(this.stateKey(actorKey, envelope.cardInstanceId), nextState);
    return this.record(envelope, {
      interactionId: envelope.interactionId,
      status: "ACCEPTED",
      actionId: envelope.actionId,
      stateVersion: nextState.stateVersion,
      nextReviewAt,
      message: `Review recorded as ${envelope.payload.rating}.`,
    });
  }

  private record(envelope: InteractionEnvelope, receipt: InteractionReceipt): InteractionReceipt {
    this.receipts.set(envelope.interactionId, { ...receipt });
    return { ...receipt };
  }

  private stateKey(actorKey: string, cardInstanceId: string): string {
    return `${actorKey}:${cardInstanceId}`;
  }

  private nextReviewAt(rating: "AGAIN" | "HARD" | "KNOWN", now: Date): string {
    const days = rating === "AGAIN" ? 1 : rating === "HARD" ? 3 : 7;
    return new Date(now.getTime() + days * 86_400_000).toISOString();
  }

  private isRatingPayload(
    envelope: InteractionEnvelope,
  ): envelope is InteractionEnvelope & { payload: { rating: "AGAIN" | "HARD" | "KNOWN" } } {
    const payload = envelope.payload;
    return (
      typeof payload === "object" &&
      payload !== null &&
      Object.keys(payload).length === 1 &&
      "rating" in payload &&
      ["AGAIN", "HARD", "KNOWN"].includes(payload.rating)
    );
  }

  private isRevealPayload(
    envelope: InteractionEnvelope,
  ): envelope is InteractionEnvelope & { payload: { action: "REVEAL" } } {
    const payload = envelope.payload;
    return (
      typeof payload === "object" &&
      payload !== null &&
      Object.keys(payload).length === 1 &&
      "action" in payload &&
      payload.action === "REVEAL"
    );
  }

  private isDraftPayload(
    envelope: InteractionEnvelope,
  ): envelope is InteractionEnvelope & {
    payload: { action: "CREATE_DRAFT"; subject: string; requestType: string; businessReason: string };
  } {
    const payload = envelope.payload;
    return (
      typeof payload === "object" &&
      payload !== null &&
      Object.keys(payload).length === 4 &&
      "action" in payload &&
      payload.action === "CREATE_DRAFT" &&
      "subject" in payload &&
      typeof payload.subject === "string" &&
      payload.subject.trim().length > 0 &&
      "requestType" in payload &&
      typeof payload.requestType === "string" &&
      payload.requestType.trim().length > 0 &&
      "businessReason" in payload &&
      typeof payload.businessReason === "string" &&
      payload.businessReason.trim().length > 0
    );
  }
}
