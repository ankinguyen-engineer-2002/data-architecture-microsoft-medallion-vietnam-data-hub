import {
  Badge,
  Button,
  FluentProvider,
  Input,
  Switch,
  Textarea,
  webDarkTheme,
  webLightTheme,
} from "@fluentui/react-components";
import { useCallback, useMemo, useRef, useState } from "react";
import type { PresentationEnvelope } from "../contracts/types.js";
import { InteractionLedger } from "../resolver/interaction-ledger.js";
import { resolvePresentation } from "../resolver/presentation-resolver.js";
import { evidenceFor, flashcards, profiles, requestFor } from "./demo-data.js";

type Scenario = "kpi" | "trend" | "table" | "flashcard" | "form";
type MessageRole = "user" | "assistant";

interface ChatMessage {
  id: string;
  role: MessageRole;
  text: string;
  presentation?: PresentationEnvelope;
}

const SCENARIOS: Array<{ id: Scenario; label: string; prompt: string; description: string }> = [
  { id: "kpi", label: "KPI answer", prompt: "What was Forecast Accuracy for Lag-0 in fiscal July 2026?", description: "One validated scalar" },
  { id: "trend", label: "Trend view", prompt: "Show the Forecast Accuracy trend for fiscal year 2026.", description: "Six ordered points" },
  { id: "table", label: "Breakdown table", prompt: "Break down Forecast Accuracy by warehouse group.", description: "Three bounded groups" },
  { id: "flashcard", label: "Study card", prompt: "Help me study Forecast Accuracy basics.", description: "Curated learning" },
  { id: "form", label: "Governance draft", prompt: "I want to submit a governance question about the metric.", description: "Draft only" },
];

function nextId(prefix: string): string {
  return `${prefix}-${Date.now()}-${Math.random().toString(16).slice(2)}`;
}

function scenarioFromText(text: string): Scenario {
  const normalized = text.toLowerCase();
  if (normalized.includes("study") || normalized.includes("flashcard")) return "flashcard";
  if (normalized.includes("draft") || normalized.includes("governance")) return "form";
  if (normalized.includes("trend") || normalized.includes("history")) return "trend";
  if (normalized.includes("breakdown") || normalized.includes("warehouse group")) return "table";
  return "kpi";
}

function formatTimestamp(value: string): string {
  return new Intl.DateTimeFormat("en-US", { hour: "2-digit", minute: "2-digit" }).format(new Date(value));
}

function TrendGraphic({ presentation }: { presentation: PresentationEnvelope }) {
  const series = presentation.data.series;
  const width = 720;
  const height = 240;
  const padding = 24;
  const values = series.map((point) => point.value);
  const min = Math.min(...values);
  const max = Math.max(...values);
  const span = max - min || 1;
  const points = series.map((point, index) => {
    const x = padding + (index / Math.max(series.length - 1, 1)) * (width - padding * 2);
    const y = height - padding - ((point.value - min) / span) * (height - padding * 2);
    return { ...point, x, y };
  });
  const path = points.map((point, index) => `${index === 0 ? "M" : "L"}${point.x.toFixed(1)} ${point.y.toFixed(1)}`).join(" ");

  return (
    <div className="trend-stack">
      <div className="trend-chart-shell">
        <svg className="trend-chart" viewBox={`0 0 ${width} ${height}`} role="img" aria-label={presentation.accessibility.summary}>
          <path className="trend-gridline" d={`M${padding} ${padding}H${width - padding}`} />
          <path className="trend-gridline" d={`M${padding} ${height / 2}H${width - padding}`} />
          <path className="trend-gridline" d={`M${padding} ${height - padding}H${width - padding}`} />
          <path className="trend-line" d={path} />
          {points.map((point) => (
            <circle key={point.sortKey} className="trend-point" cx={point.x} cy={point.y} r="4" />
          ))}
        </svg>
        <div className="trend-axis" aria-hidden="true">
          {series.map((point) => <span key={point.sortKey}>{point.label}</span>)}
        </div>
      </div>
      <details className="data-details">
        <summary>Accessible data table</summary>
        <table>
          <caption>Trend values for {presentation.subtitle}</caption>
          <thead><tr><th scope="col">Period</th><th scope="col">Value</th></tr></thead>
          <tbody>{series.map((point) => <tr key={point.sortKey}><th scope="row">{point.label}</th><td>{point.displayValue}</td></tr>)}</tbody>
        </table>
      </details>
    </div>
  );
}

function EvidenceLink({ onOpen }: { onOpen: () => void }) {
  return <Button appearance="subtle" size="small" onClick={onOpen}>View evidence trail</Button>;
}

function PresentationBlock({
  presentation,
  onEvidence,
}: {
  presentation: PresentationEnvelope;
  onEvidence: (presentation: PresentationEnvelope) => void;
}) {
  const [revealed, setRevealed] = useState(false);
  const [reviewMessage, setReviewMessage] = useState<string | null>(null);
  const [formSubmitted, setFormSubmitted] = useState(false);
  const localLedger = useRef(new InteractionLedger());
  const flashcardInstanceId = useMemo(() => "21212121-2121-4121-8121-212121212121", []);

  const rateFlashcard = useCallback((rating: "AGAIN" | "HARD" | "KNOWN") => {
    if (!presentation.data.flashcard) return;
    if (!localLedger.current.getState("demo-user", flashcardInstanceId)) {
      localLedger.current.seedFlashcard({
        cardInstanceId: flashcardInstanceId,
        conceptId: presentation.data.flashcard.conceptId,
        actorKey: "demo-user",
        stateVersion: 0,
        reviewCount: 0,
        nextReviewAt: null,
      });
    }
    const receipt = localLedger.current.submit("demo-user", {
      contractVersion: "1.0.0",
      interactionId: globalThis.crypto?.randomUUID?.() ?? "20202020-2020-4020-8020-202020202020",
      cardInstanceId: flashcardInstanceId,
      templateId: "forecast.flashcard.v1",
      actionId: "flashcard.rate",
      evidenceId: null,
      stateVersion: localLedger.current.getState("demo-user", flashcardInstanceId)?.stateVersion ?? 0,
      issuedAt: new Date().toISOString(),
      expiresAt: new Date(Date.now() + 900_000).toISOString(),
      payload: { rating },
    }, new Date());
    setReviewMessage(receipt.message);
  }, [flashcardInstanceId, presentation.data.flashcard]);

  if (presentation.presentationType === "KPI_CARD") {
    return (
      <section className="rich-block kpi-block" aria-label={presentation.accessibility.summary}>
        <div className="block-kicker">Governed KPI</div>
        <div className="block-heading"><h3>{presentation.title}</h3><Badge appearance="tint" color="success">Evidence OK</Badge></div>
        <p className="block-subtitle">{presentation.subtitle}</p>
        <div className="kpi-value">{presentation.data.metrics[0]?.displayValue ?? "No value"}</div>
        <div className="metric-strip">{presentation.data.metrics.map((metric) => <span key={metric.metricId}><strong>{metric.label}</strong><span>{metric.displayValue}</span></span>)}</div>
        <div className="block-actions"><EvidenceLink onOpen={() => onEvidence(presentation)} /><Button appearance="primary" size="small" onClick={() => onEvidence(presentation)}>Inspect context</Button></div>
      </section>
    );
  }

  if (presentation.presentationType === "TREND") {
    return (
      <section className="rich-block trend-block" aria-label={presentation.accessibility.summary}>
        <div className="block-kicker">Ordered trend</div>
        <div className="block-heading"><h3>{presentation.title}</h3><Badge appearance="tint" color="informative">{presentation.data.series.length} points</Badge></div>
        <p className="block-subtitle">{presentation.subtitle}</p>
        <TrendGraphic presentation={presentation} />
        <div className="block-actions"><EvidenceLink onOpen={() => onEvidence(presentation)} /></div>
      </section>
    );
  }

  if (presentation.presentationType === "TABLE") {
    return (
      <section className="rich-block table-block" aria-label={presentation.accessibility.summary}>
        <div className="block-kicker">Bounded breakdown</div>
        <div className="block-heading"><h3>{presentation.title}</h3><Badge appearance="tint" color="informative">{presentation.data.rows.length} rows</Badge></div>
        <p className="block-subtitle">{presentation.subtitle}</p>
        <div className="table-wrap"><table><caption>Governed result table for {presentation.subtitle}</caption><thead><tr><th scope="col">Group</th><th scope="col">Value</th><th scope="col">Metric</th></tr></thead><tbody>{presentation.data.rows.map((row) => <tr key={`${row.label}-${row.metricId}`}><th scope="row">{row.label}</th><td>{row.displayValue}</td><td>{row.metricId}</td></tr>)}</tbody></table></div>
        <div className="block-actions"><EvidenceLink onOpen={() => onEvidence(presentation)} /></div>
      </section>
    );
  }

  if (presentation.presentationType === "FLASHCARD" && presentation.data.flashcard) {
    const card = presentation.data.flashcard;
    return (
      <section className="rich-block flashcard-block" aria-label={presentation.accessibility.summary}>
        <div className="block-kicker">Curated learning</div>
        <div className="block-heading"><h3>Study card</h3><Badge appearance="tint" color="informative">{card.sourceLabel}</Badge></div>
        <p className="flashcard-front">{card.front}</p>
        {revealed ? <div className="flashcard-answer"><div className="answer-label">Answer</div><p>{card.answer}</p><p className="answer-explanation">{card.explanation}</p></div> : <div className="flashcard-hidden">Answer stays hidden until reveal.</div>}
        <div className="block-actions"><Button appearance="primary" size="small" onClick={() => setRevealed(true)} disabled={revealed}>Reveal answer</Button><Button size="small" onClick={() => rateFlashcard("AGAIN")}>Again</Button><Button size="small" onClick={() => rateFlashcard("HARD")}>Hard</Button><Button size="small" onClick={() => rateFlashcard("KNOWN")}>Known</Button></div>
        {reviewMessage && <p className="inline-status" role="status">{reviewMessage}</p>}
      </section>
    );
  }

  if (presentation.presentationType === "FORM" && presentation.data.form) {
    return (
      <section className="rich-block form-block" aria-label={presentation.accessibility.summary}>
        <div className="block-kicker">Governance draft</div>
        <div className="block-heading"><h3>{presentation.data.form.title}</h3><Badge appearance="tint" color="warning">Draft only</Badge></div>
        <p className="block-subtitle">{presentation.data.form.notice}</p>
        {formSubmitted ? <div className="form-success" role="status"><strong>Draft created.</strong><span>No approval, notification, or metric change was performed.</span></div> : <form onSubmit={(event) => { event.preventDefault(); setFormSubmitted(true); }}><label>Subject<Input required name="subject" placeholder="Short request subject" /></label><label>Request type<select defaultValue="metric_definition_review" name="requestType"><option value="metric_definition_review">Metric definition review</option><option value="data_quality_investigation">Data quality investigation</option><option value="access_scope_question">Access or scope question</option></select></label><label>Business reason<Textarea required name="businessReason" resize="vertical" placeholder="What should a reviewer understand?" /></label><Button appearance="primary" type="submit">Create draft</Button></form>}
      </section>
    );
  }

  return (
    <section className="rich-block fallback-block" aria-label={presentation.accessibility.summary}>
      <div className="block-kicker">Text fallback</div>
      <h3>{presentation.title}</h3>
      <p>{presentation.fallback.text}</p>
    </section>
  );
}

function Message({ message, onEvidence }: { message: ChatMessage; onEvidence: (presentation: PresentationEnvelope) => void }) {
  return (
    <article className={`message ${message.role === "user" ? "message-user" : "message-assistant"}`}>
      <div className="message-meta"><span>{message.role === "user" ? "You" : "SupplyChainAgent"}</span><span>{message.role === "assistant" ? "governed response" : "request"}</span></div>
      {message.text && <p className="message-copy">{message.text}</p>}
      {message.presentation && <PresentationBlock presentation={message.presentation} onEvidence={onEvidence} />}
    </article>
  );
}

export function App() {
  const [dark, setDark] = useState(true);
  const [composer, setComposer] = useState("");
  const [busy, setBusy] = useState(false);
  const [evidencePanel, setEvidencePanel] = useState<PresentationEnvelope | null>(null);
  const [messages, setMessages] = useState<ChatMessage[]>([
    {
      id: "welcome",
      role: "assistant",
      text: "Ask a governed Forecast question, inspect a trend, study a curated concept, or create a governance draft. Every number comes from a validated evidence envelope.",
    },
  ]);

  const runScenario = useCallback(async (scenario: Scenario, prompt: string) => {
    setBusy(true);
    setMessages((current) => [...current, { id: nextId("user"), role: "user", text: prompt }]);
    try {
      const request = requestFor(scenario);
      const evidence = scenario === "flashcard" || scenario === "form" ? null : evidenceFor(scenario);
      const presentation = await resolvePresentation(request, evidence, profiles.WEB_RICH_V1, {
        flashcards,
        trustedChannelProfile: "WEB_RICH_V1",
      });
      setMessages((current) => [...current, { id: nextId("assistant"), role: "assistant", text: scenario === "form" ? "I prepared a draft-only governance form." : scenario === "flashcard" ? "Here is a curated study card." : "The result is rendered from validated governed evidence.", presentation }]);
    } catch (error) {
      setMessages((current) => [...current, { id: nextId("assistant"), role: "assistant", text: `The local demo could not render this response: ${String(error)}` }]);
    } finally {
      setBusy(false);
    }
  }, []);

  const submitComposer = useCallback(() => {
    const prompt = composer.trim();
    if (!prompt || busy) return;
    setComposer("");
    void runScenario(scenarioFromText(prompt), prompt);
  }, [busy, composer, runScenario]);

  return (
    <FluentProvider theme={dark ? webDarkTheme : webLightTheme}>
      <div className={`app-shell ${dark ? "theme-dark" : "theme-light"}`}>
        <aside className="conversation-rail">
          <div className="brand-lockup"><div className="brand-mark">SC</div><div><strong>SupplyChainAgent</strong><span>Forecast control room</span></div></div>
          <Button appearance="primary" className="new-chat" onClick={() => setMessages([{ id: "welcome-reset", role: "assistant", text: "New governed conversation ready. Choose a starting point below." }])}>New conversation</Button>
          <div className="rail-section"><div className="rail-label">Workspace</div><button className="rail-item active">Forecast Accuracy <span>live</span></button><button className="rail-item">Saved learning <span>3</span></button><button className="rail-item">Governance drafts <span>0</span></button></div>
          <div className="rail-footer"><div className="account-chip"><span className="avatar">AN</span><span><strong>Planner workspace</strong><small>Authenticated session</small></span></div><div className="theme-row"><span>Dark canvas</span><Switch checked={dark} onChange={(_, data) => setDark(data.checked)} /></div></div>
        </aside>

        <main className="conversation-main">
          <header className="main-header"><div><div className="eyebrow">GOVERNED FORECAST INTELLIGENCE</div><h1>Forecast Accuracy</h1><p>Intent-aware presentation with deterministic evidence binding.</p></div><div className="header-status"><span className="status-dot" />Evidence-first runtime<small>Web rich profile</small></div></header>
          <div className="conversation-scroll" aria-live="polite">
            <div className="conversation-intro"><span className="intro-line" /><p>Today in the control room</p><span className="intro-line" /></div>
            {messages.map((message) => <Message key={message.id} message={message} onEvidence={setEvidencePanel} />)}
            {busy && <div className="agent-progress" role="status"><span className="progress-pulse" /><span>Validating request and checking governed evidence</span></div>}
          </div>
          <div className="composer-zone">
            <div className="suggestion-row">{SCENARIOS.map((scenario) => <button key={scenario.id} className="suggestion" onClick={() => void runScenario(scenario.id, scenario.prompt)}><span>{scenario.label}</span><small>{scenario.description}</small></button>)}</div>
            <div className="composer"><Textarea value={composer} onChange={(_, data) => setComposer(data.value)} onKeyDown={(event) => { if (event.key === "Enter" && (event.metaKey || event.ctrlKey)) { event.preventDefault(); submitComposer(); } }} placeholder="Ask about a governed metric or choose a path above" resize="none" aria-label="Message SupplyChainAgent" /><Button appearance="primary" onClick={submitComposer} disabled={!composer.trim() || busy}>Send</Button></div>
            <div className="composer-note">Enter sends with Cmd or Ctrl + Enter. Unsupported shapes return a clear text fallback.</div>
          </div>
        </main>

        {evidencePanel && <aside className="evidence-panel" aria-label="Evidence trail">
          <div className="panel-top"><div><div className="eyebrow">TRACE VIEW</div><h2>Evidence trail</h2></div><Button appearance="subtle" onClick={() => setEvidencePanel(null)} aria-label="Close evidence trail">Close</Button></div>
          <p className="panel-copy">This panel shows safe reconstruction metadata. Raw DAX, SQL, identity and role fields never enter the presentation envelope.</p>
          <dl className="evidence-list">
            <div><dt>Status</dt><dd><Badge appearance="tint" color="success">OK</Badge></dd></div>
            <div><dt>Evidence ID</dt><dd className="mono">{evidencePanel.evidenceId}</dd></div>
            <div><dt>Template</dt><dd className="mono">{evidencePanel.templateId}</dd></div>
            <div><dt>Decision</dt><dd>{evidencePanel.reasonCode}</dd></div>
            <div><dt>Why this presentation</dt><dd>{evidencePanel.decision.checks.map((check) => `${check.check}: ${check.outcome}`).join(" · ")}</dd></div>
            {evidencePanel.resourceReference && <div><dt>Resource pointer</dt><dd className="mono">{evidencePanel.resourceReference.uri}</dd></div>}
            <div><dt>Status events</dt><dd>{evidencePanel.events.map((event) => event.name).join(" -> ")}</dd></div>
            <div><dt>Expires</dt><dd>{formatTimestamp(evidencePanel.expiresAt)}</dd></div>
          </dl>
          <div className="panel-foot"><span className="status-dot" />Bound to the validated evidence envelope</div>
        </aside>}
      </div>
    </FluentProvider>
  );
}
