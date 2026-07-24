import { Command } from "cmdk";
import { useEffect, useMemo, useState } from "react";
import { CornerDownLeft, Search, X } from "lucide-react";
import { searchNodes } from "@/lib/lineage";
import type { LineageNode, Snapshot } from "@/lib/types";
import { cn } from "@/lib/util";

type Props = {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  snapshot: Snapshot;
  onSelect: (node: LineageNode) => void;
};

const LAYER_COLOR: Record<string, string> = {
  Bronze: "bg-[var(--color-bronze)]",
  Silver: "bg-[var(--color-silver)]",
  Gold: "bg-[var(--color-gold)]",
  Semantic: "bg-[var(--color-semantic)]",
};

export function CommandPalette({ open, onOpenChange, snapshot, onSelect }: Props) {
  const [query, setQuery] = useState("");

  useEffect(() => {
    if (!open) setQuery("");
  }, [open]);

  const results = useMemo(
    () => searchNodes(snapshot.nodes, query, 20),
    [snapshot.nodes, query]
  );

  if (!open) return null;

  return (
    <div
      className="fixed inset-0 z-50 flex items-start justify-center bg-black/60 pt-[15vh] backdrop-blur-sm"
      onClick={() => onOpenChange(false)}
    >
      <div
        className="w-[min(640px,calc(100vw-32px))] overflow-hidden rounded-xl border border-ink-800 bg-ink-900 shadow-2xl"
        onClick={(e) => e.stopPropagation()}
      >
        <Command shouldFilter={false}>
          <div className="flex items-center gap-3 border-b border-ink-800 px-4">
            <Search size={16} className="text-ink-500" />
            <Command.Input
              autoFocus
              value={query}
              onValueChange={setQuery}
              placeholder="Search tables, schemas, marts…"
              className="flex-1 bg-transparent py-3.5 text-sm text-ink-100 outline-none placeholder:text-ink-500"
            />
            <button
              onClick={() => onOpenChange(false)}
              className="rounded p-1 text-ink-500 hover:bg-ink-800 hover:text-ink-200"
              aria-label="Close"
            >
              <X size={14} />
            </button>
          </div>
          <Command.List className="max-h-[50vh] overflow-y-auto p-1.5">
            {query.trim() === "" && (
              <Command.Empty className="px-3 py-6 text-center text-xs text-ink-500">
                Start typing to find any table, view, or semantic model.
              </Command.Empty>
            )}
            {query.trim() !== "" && results.length === 0 && (
              <Command.Empty className="px-3 py-6 text-center text-xs text-ink-500">
                No matches.
              </Command.Empty>
            )}
            {results.map((node) => (
              <Command.Item
                key={node.id}
                value={node.id}
                onSelect={() => {
                  onSelect(node);
                  onOpenChange(false);
                }}
                className={cn(
                  "group flex cursor-pointer items-center gap-3 rounded-md px-3 py-2.5",
                  "text-ink-200 aria-selected:bg-ink-800/80 aria-selected:text-ink-50"
                )}
              >
                <span
                  className={cn(
                    "h-1.5 w-1.5 shrink-0 rounded-full",
                    LAYER_COLOR[node.layer] ?? "bg-ink-500"
                  )}
                />
                <div className="min-w-0 flex-1">
                  <div className="truncate text-[13px] font-medium">
                    {node.display_name}
                  </div>
                  <div className="truncate font-mono text-[11px] text-ink-500">
                    {node.schema} · {node.layer}
                    {node.mart && node.mart !== "shared" && ` · ${node.mart.replace(/_/g, " ")}`}
                  </div>
                </div>
                <CornerDownLeft
                  size={12}
                  className="text-ink-600 opacity-0 group-aria-selected:opacity-100"
                />
              </Command.Item>
            ))}
          </Command.List>
          <div className="flex items-center justify-between border-t border-ink-800 px-3 py-2 font-mono text-[10px] uppercase tracking-wider text-ink-600">
            <span>{snapshot.nodes.length} assets indexed</span>
            <span className="flex items-center gap-2">
              <kbd className="rounded border border-ink-700 bg-ink-850 px-1.5 py-0.5">↑↓</kbd>
              <kbd className="rounded border border-ink-700 bg-ink-850 px-1.5 py-0.5">enter</kbd>
              <kbd className="rounded border border-ink-700 bg-ink-850 px-1.5 py-0.5">esc</kbd>
            </span>
          </div>
        </Command>
      </div>
    </div>
  );
}
