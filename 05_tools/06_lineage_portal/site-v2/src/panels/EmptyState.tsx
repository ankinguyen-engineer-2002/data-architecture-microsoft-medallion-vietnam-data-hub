import { ArrowUpRight, Boxes, Network } from "lucide-react";
import { motion } from "motion/react";
import { cn } from "@/lib/util";
import type { LineageNode, Snapshot } from "@/lib/types";
import { pickEntrypoints } from "@/lib/lineage";

type MartOption = { id: string; label: string };

type Props = {
  snapshot: Snapshot;
  marts: MartOption[];
  onSelect: (node: LineageNode) => void;
  onOpenMart: (id: string) => void;
  onOpenFull: () => void;
  onOpenSearch: () => void;
};

const LAYER_DOT: Record<string, string> = {
  Bronze: "bg-[var(--color-bronze)]",
  Silver: "bg-[var(--color-silver)]",
  Gold: "bg-[var(--color-gold)]",
  Semantic: "bg-[var(--color-semantic)]",
};

export function EmptyState({
  snapshot,
  marts,
  onSelect,
  onOpenMart,
  onOpenFull,
  onOpenSearch,
}: Props) {
  const entrypoints = pickEntrypoints(snapshot, 6);
  const servingTotal = snapshot.nodes.filter(
    (n) => n.layer === "Gold" || n.layer === "Semantic"
  ).length;

  const martCounts = marts.map((m) => ({
    ...m,
    count: snapshot.nodes.filter((n) => n.mart === m.id).length,
  }));

  return (
    <div className="mx-auto flex h-full max-w-4xl flex-col justify-center overflow-y-auto px-6 py-10">
      <motion.div
        initial={{ opacity: 0, y: 12 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ duration: 0.32, ease: [0.16, 1, 0.3, 1] }}
        className="w-full"
      >
        <div>
          <div className="font-mono text-[10.5px] uppercase tracking-[0.22em] text-ink-500">
            Enterprise Supply Chain · Lineage
          </div>
          <h1 className="mt-3 text-[34px] font-medium leading-[1.1] tracking-tight text-ink-50">
            Trace any table to its source.
          </h1>
          <p className="mt-3 max-w-[56ch] text-[14px] leading-relaxed text-ink-400">
            Pick a preset below — a whole mart, the full graph, or a single serving asset — then
            drill into upstream and downstream lineage. Everything renders instantly from a
            preloaded snapshot of{" "}
            <span className="font-mono text-ink-200">{snapshot.nodes.length}</span> assets.
          </p>
        </div>

        {/* Search */}
        <button
          onClick={onOpenSearch}
          className={cn(
            "mt-6 flex w-full items-center gap-3 rounded-lg border border-ink-800 bg-ink-900/60 px-4 py-3",
            "text-left text-[14px] text-ink-500 transition hover:border-ink-700 hover:bg-ink-900"
          )}
        >
          <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.75" strokeLinecap="round" strokeLinejoin="round" className="opacity-70">
            <circle cx="11" cy="11" r="7" />
            <path d="m21 21-4.3-4.3" />
          </svg>
          <span className="flex-1">Search any table, view, or semantic model…</span>
          <kbd className="rounded border border-ink-700 bg-ink-850 px-1.5 py-0.5 font-mono text-[10px] text-ink-400">
            ⌘K
          </kbd>
        </button>

        {/* Preset grid: marts + full */}
        <div className="mt-8">
          <div className="mb-3 font-mono text-[10.5px] uppercase tracking-[0.18em] text-ink-500">
            Browse by view
          </div>
          <div className="grid grid-cols-1 gap-2.5 sm:grid-cols-3">
            {martCounts.map((m) => (
              <button
                key={m.id}
                onClick={() => onOpenMart(m.id)}
                className="group flex flex-col items-start gap-3 rounded-lg border border-ink-800 bg-ink-900/40 p-4 text-left transition hover:border-ink-700 hover:bg-ink-900"
              >
                <div className="flex w-full items-center justify-between">
                  <Boxes size={16} className="text-ink-500 group-hover:text-ink-300" />
                  <span className="font-mono text-[10.5px] text-ink-600">{m.count} nodes</span>
                </div>
                <div>
                  <div className="text-[14px] font-medium capitalize text-ink-100 group-hover:text-ink-50">
                    {m.label}
                  </div>
                  <div className="mt-0.5 font-mono text-[10.5px] text-ink-500">mart lineage</div>
                </div>
              </button>
            ))}
            <button
              onClick={onOpenFull}
              className="group flex flex-col items-start gap-3 rounded-lg border border-ink-800 bg-ink-900/40 p-4 text-left transition hover:border-ink-700 hover:bg-ink-900"
            >
              <div className="flex w-full items-center justify-between">
                <Network size={16} className="text-ink-500 group-hover:text-ink-300" />
                <span className="font-mono text-[10.5px] text-ink-600">{snapshot.nodes.length} nodes</span>
              </div>
              <div>
                <div className="text-[14px] font-medium text-ink-100 group-hover:text-ink-50">
                  Full graph
                </div>
                <div className="mt-0.5 font-mono text-[10.5px] text-ink-500">everything</div>
              </div>
            </button>
          </div>
        </div>

        {/* Serving entrypoints */}
        {entrypoints.length > 0 && (
          <div className="mt-8">
            <div className="mb-3 flex items-baseline justify-between">
              <div className="font-mono text-[10.5px] uppercase tracking-[0.18em] text-ink-500">
                Serving assets — start here
              </div>
              <div className="font-mono text-[10.5px] text-ink-600">
                top {entrypoints.length} of {servingTotal}
              </div>
            </div>
            <ul className="divide-y divide-ink-850 overflow-hidden rounded-lg border border-ink-800 bg-ink-900/40">
              {entrypoints.map((node) => (
                <li key={node.id}>
                  <button
                    onClick={() => onSelect(node)}
                    className="group flex w-full items-center gap-4 px-4 py-2.5 text-left hover:bg-ink-850/60"
                  >
                    <span
                      className={cn(
                        "h-1.5 w-1.5 shrink-0 rounded-full",
                        LAYER_DOT[node.layer] ?? "bg-ink-500"
                      )}
                    />
                    <div className="min-w-0 flex-1">
                      <div className="truncate text-[13.5px] text-ink-100 group-hover:text-ink-50">
                        {node.display_name}
                      </div>
                      <div className="truncate font-mono text-[11px] text-ink-500">
                        {node.schema} · {node.layer}
                        {node.mart && node.mart !== "shared" && ` · ${node.mart.replace(/_/g, " ")}`}
                      </div>
                    </div>
                    <ArrowUpRight
                      size={13}
                      className="shrink-0 text-ink-600 transition group-hover:text-ink-300"
                    />
                  </button>
                </li>
              ))}
            </ul>
          </div>
        )}
      </motion.div>
    </div>
  );
}
