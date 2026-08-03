import { AnimatePresence, motion } from "motion/react";
import { ArrowUpRight, ChevronRight, Copy, ExternalLink, X } from "lucide-react";
import { useMemo, useState } from "react";
import { cn, formatUtc, relativeTime } from "@/lib/util";
import type { LineageEdge, LineageNode } from "@/lib/types";

type Props = {
  node: LineageNode | null;
  edges: LineageEdge[];
  nodesById: Map<string, LineageNode>;
  onClose: () => void;
  onNavigate: (node: LineageNode) => void;
  onFocus: (node: LineageNode) => void;
};

const LAYER_DOT: Record<string, string> = {
  Bronze: "bg-[var(--color-bronze)]",
  Silver: "bg-[var(--color-silver)]",
  Gold: "bg-[var(--color-gold)]",
  Semantic: "bg-[var(--color-semantic)]",
};

export function DetailSheet({ node, edges, nodesById, onClose, onNavigate, onFocus }: Props) {
  const upstream = useMemo(() => {
    if (!node) return [];
    return edges
      .filter((e) => e.target === node.id)
      .map((e) => ({ edge: e, node: nodesById.get(e.source) }))
      .filter((x): x is { edge: LineageEdge; node: LineageNode } => Boolean(x.node));
  }, [node, edges, nodesById]);

  const downstream = useMemo(() => {
    if (!node) return [];
    return edges
      .filter((e) => e.source === node.id)
      .map((e) => ({ edge: e, node: nodesById.get(e.target) }))
      .filter((x): x is { edge: LineageEdge; node: LineageNode } => Boolean(x.node));
  }, [node, edges, nodesById]);

  return (
    <AnimatePresence>
      {node && (
        <motion.aside
          key={node.id}
          initial={{ x: 32, opacity: 0 }}
          animate={{ x: 0, opacity: 1 }}
          exit={{ x: 32, opacity: 0 }}
          transition={{ duration: 0.22, ease: [0.16, 1, 0.3, 1] }}
          className="pointer-events-auto flex h-full w-[420px] shrink-0 flex-col border-l border-ink-800 bg-ink-950/95 backdrop-blur"
        >
          <header className="flex items-start justify-between gap-3 border-b border-ink-800 px-6 py-5">
            <div className="min-w-0 flex-1">
              <div className="flex items-center gap-2 font-mono text-[10.5px] uppercase tracking-[0.18em] text-ink-500">
                <span
                  className={cn(
                    "h-1.5 w-1.5 rounded-full",
                    LAYER_DOT[node.layer] ?? "bg-ink-500"
                  )}
                />
                {node.layer}
                {node.mart && node.mart !== "shared" && (
                  <>
                    <span className="text-ink-700">·</span>
                    <span>{node.mart.replace(/_/g, " ")}</span>
                  </>
                )}
              </div>
              <h2 className="mt-2 truncate text-[18px] font-medium tracking-tight text-ink-50">
                {node.display_name}
              </h2>
              <FullNameLine full={node.full_name} />
            </div>
            <button
              onClick={onClose}
              className="rounded p-1 text-ink-500 hover:bg-ink-800 hover:text-ink-200"
              aria-label="Close panel"
            >
              <X size={16} />
            </button>
          </header>

          <div className="flex-1 overflow-y-auto">
            <MetaBlock label="Object type" value={node.object_type} />
            <MetaBlock label="Schema" value={`${node.database}.${node.schema}`} mono />
            {node.workspace && <MetaBlock label="Workspace" value={node.workspace} />}
            {node.load_method && <MetaBlock label="Load method" value={node.load_method} />}
            {node.wave != null && <MetaBlock label="Wave" value={`W${String(node.wave).padStart(2, "0")}`} mono />}
            {node.last_modified && (
              <MetaBlock
                label="Last modified"
                value={formatUtc(node.last_modified)}
                suffix={relativeTime(node.last_modified)}
                mono
              />
            )}

            {upstream.length > 0 && (
              <RelSection
                title="Upstream"
                subtitle={`${upstream.length} source${upstream.length === 1 ? "" : "s"}`}
                items={upstream}
                direction="in"
                onNavigate={onNavigate}
                onFocus={() => onFocus(node)}
              />
            )}

            {downstream.length > 0 && (
              <RelSection
                title="Downstream"
                subtitle={`${downstream.length} consumer${downstream.length === 1 ? "" : "s"}`}
                items={downstream}
                direction="out"
                onNavigate={onNavigate}
                onFocus={() => onFocus(node)}
              />
            )}

            {node.evidence && node.evidence.length > 0 && (
              <div className="border-t border-ink-800 px-6 py-4">
                <SectionHeader title="Evidence" subtitle={`${node.evidence.length} file${node.evidence.length === 1 ? "" : "s"}`} />
                <ul className="mt-2 space-y-1">
                  {node.evidence.map((path) => (
                    <li key={path} className="font-mono text-[11.5px] text-ink-400">
                      {path}
                    </li>
                  ))}
                </ul>
              </div>
            )}
          </div>
        </motion.aside>
      )}
    </AnimatePresence>
  );
}

function FullNameLine({ full }: { full: string }) {
  const [copied, setCopied] = useState(false);
  return (
    <button
      className="mt-1 flex items-center gap-1.5 font-mono text-[11.5px] text-ink-500 hover:text-ink-300"
      onClick={() => {
        navigator.clipboard.writeText(full);
        setCopied(true);
        setTimeout(() => setCopied(false), 1600);
      }}
    >
      <span className="truncate">{full}</span>
      <Copy size={11} className="shrink-0" />
      {copied && <span className="text-[var(--color-semantic)]">copied</span>}
    </button>
  );
}

function MetaBlock({
  label,
  value,
  suffix,
  mono,
}: {
  label: string;
  value: string;
  suffix?: string;
  mono?: boolean;
}) {
  return (
    <div className="border-b border-ink-850 px-6 py-3">
      <div className="font-mono text-[10.5px] uppercase tracking-[0.16em] text-ink-500">
        {label}
      </div>
      <div className={cn("mt-1 text-[13.5px] text-ink-100", mono && "font-mono")}>
        {value}
        {suffix && <span className="ml-2 text-ink-500">{suffix}</span>}
      </div>
    </div>
  );
}

function SectionHeader({ title, subtitle }: { title: string; subtitle?: string }) {
  return (
    <div className="flex items-baseline justify-between">
      <div className="font-mono text-[10.5px] uppercase tracking-[0.16em] text-ink-500">
        {title}
      </div>
      {subtitle && (
        <div className="font-mono text-[10.5px] text-ink-600">{subtitle}</div>
      )}
    </div>
  );
}

function RelSection({
  title,
  subtitle,
  items,
  direction,
  onNavigate,
  onFocus,
}: {
  title: string;
  subtitle: string;
  items: Array<{ edge: LineageEdge; node: LineageNode }>;
  direction: "in" | "out";
  onNavigate: (node: LineageNode) => void;
  onFocus: () => void;
}) {
  return (
    <div className="border-t border-ink-800 px-6 py-4">
      <SectionHeader title={title} subtitle={subtitle} />
      <ul className="mt-2 divide-y divide-ink-850">
        {items.map(({ edge, node }) => (
          <li key={edge.id}>
            <button
              onClick={() => onNavigate(node)}
              className="group flex w-full items-center gap-3 py-2.5 text-left"
            >
              <span
                className={cn(
                  "h-1.5 w-1.5 shrink-0 rounded-full",
                  LAYER_DOT[node.layer] ?? "bg-ink-500"
                )}
              />
              <div className="min-w-0 flex-1">
                <div className="truncate text-[13px] text-ink-200 group-hover:text-ink-50">
                  {node.display_name}
                </div>
                <div className="truncate font-mono text-[11px] text-ink-500">
                  {node.database}.{node.schema} · {node.layer}
                </div>
                <div className="mt-1 flex items-center gap-1.5">
                  <EdgeBadge edge={edge} />
                  {edge.source_file && (
                    <span
                      title={edge.source_file}
                      className="max-w-[190px] truncate font-mono text-[9.5px] text-ink-600"
                    >
                      {edge.source_file}
                    </span>
                  )}
                </div>
              </div>
              {direction === "out" ? (
                <ArrowUpRight size={13} className="text-ink-600 group-hover:text-ink-300" />
              ) : (
                <ChevronRight size={13} className="text-ink-600 group-hover:text-ink-300" />
              )}
            </button>
          </li>
        ))}
      </ul>
      {items.length > 0 && (
        <button
          onClick={onFocus}
          className="mt-2 flex items-center gap-1 font-mono text-[10.5px] uppercase tracking-[0.14em] text-ink-500 hover:text-ink-300"
        >
          <ExternalLink size={11} />
          Focus lineage on selected
        </button>
      )}
    </div>
  );
}

function EdgeBadge({ edge }: { edge: LineageEdge }) {
  const status = edge.sync_status ?? "not_applicable";
  const label =
    edge.confidence === "inferred"
      ? "Inferred"
      : status === "aligned"
      ? "Aligned"
      : status === "drift"
        ? edge.provenance === "repository_target"
          ? "Repo target · drift"
          : "Live · drift"
        : status === "repository_only"
          ? "Repo target · no live edge"
          : status === "live_only"
            ? "Live only"
            : edge.provenance === "repository_target"
              ? "Repo target"
              : "Live";
  const style =
    edge.confidence === "inferred"
      ? "border-[var(--color-signal-warn)]/35 text-[var(--color-signal-warn)]"
      : status === "aligned"
      ? "border-[var(--color-signal-ok)]/35 text-[var(--color-signal-ok)]"
      : status === "drift" || status === "repository_only"
        ? "border-[var(--color-signal-warn)]/35 text-[var(--color-signal-warn)]"
        : "border-ink-700 text-ink-400";
  return (
    <span
      title={edge.evidence}
      className={cn("rounded border px-1.5 py-0.5 font-mono text-[9px] uppercase tracking-wide", style)}
    >
      {label}
    </span>
  );
}
