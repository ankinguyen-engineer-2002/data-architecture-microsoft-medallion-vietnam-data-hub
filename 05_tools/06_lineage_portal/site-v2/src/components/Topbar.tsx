import {
  AlertTriangle,
  Download,
  Focus,
  Layers,
  Minus,
  Network,
  Plus,
  Search,
} from "lucide-react";
import { cn, formatUtc, relativeTime } from "@/lib/util";
import type { LineageNode, Snapshot } from "@/lib/types";
import type { ViewMode } from "@/lib/view";

type MartOption = { id: string; label: string };

type Props = {
  snapshot: Snapshot;
  mode: ViewMode;
  marts: MartOption[];
  martId: string | null;
  focusNode: LineageNode | null;
  hops: number;
  showSupport: boolean;
  onHome: () => void;
  onModeFocus: () => void;
  onModeMart: (id: string) => void;
  onModeFull: () => void;
  onHopsChange: (hops: number) => void;
  onToggleSupport: () => void;
  onOpenSearch: () => void;
  onDownload: () => void;
  nodeCount: number;
  edgeCount: number;
};

export function Topbar({
  snapshot,
  mode,
  marts,
  martId,
  focusNode,
  hops,
  showSupport,
  onHome,
  onModeFocus,
  onModeMart,
  onModeFull,
  onHopsChange,
  onToggleSupport,
  onOpenSearch,
  onDownload,
  nodeCount,
  edgeCount,
}: Props) {
  return (
    <header className="flex items-center gap-3 border-b border-ink-800 bg-ink-975/85 px-5 py-2.5 backdrop-blur">
      <button
        onClick={onHome}
        title="Back to home"
        className="group flex items-center gap-2 rounded-md px-1.5 py-1 transition hover:bg-ink-850/60"
      >
        <Layers size={14} className="text-ink-500 group-hover:text-ink-300" />
        <span className="text-[13px] font-medium tracking-tight text-ink-100">
          Supply Chain Lineage
        </span>
      </button>

      {/* View-mode segmented control */}
      <div className="flex items-center gap-0.5 rounded-lg border border-ink-800 bg-ink-900/60 p-0.5">
        <ModeButton
          active={mode === "focus"}
          icon={<Focus size={12} />}
          label="Focus"
          onClick={onModeFocus}
        />
        <MartMenu marts={marts} active={mode === "mart"} martId={martId} onSelect={onModeMart} />
        <ModeButton
          active={mode === "full"}
          icon={<Network size={12} />}
          label="Full"
          onClick={onModeFull}
        />
      </div>

      {/* Contextual controls per mode */}
      {mode === "focus" && focusNode && <HopsPicker hops={hops} onChange={onHopsChange} />}
      {mode === "full" && (
        <label className="flex cursor-pointer items-center gap-1.5 text-[11.5px] text-ink-400">
          <input
            type="checkbox"
            checked={showSupport}
            onChange={onToggleSupport}
            className="h-3 w-3 accent-[var(--color-silver)]"
          />
          Shared / support
        </label>
      )}

      <div className="flex-1" />

      {/* Live counts */}
      <div className="hidden items-center gap-3 font-mono text-[10.5px] text-ink-500 md:flex">
        <span>{nodeCount} nodes</span>
        <span className="text-ink-700">·</span>
        <span>{edgeCount} edges</span>
      </div>

      <button
        onClick={onOpenSearch}
        className="flex items-center gap-2 rounded-md border border-ink-800 bg-ink-900/70 px-2.5 py-1.5 text-[12px] text-ink-400 hover:border-ink-700 hover:text-ink-100"
      >
        <Search size={13} />
        <span className="hidden sm:inline">Search</span>
        <kbd className="ml-0.5 rounded border border-ink-700 bg-ink-850 px-1 py-0.5 font-mono text-[9.5px] text-ink-500">
          ⌘K
        </kbd>
      </button>

      {snapshot.warnings.length > 0 && (
        <button
          title={snapshot.warnings.join("\n")}
          className="flex items-center gap-1.5 rounded-md border border-[var(--color-signal-warn)]/40 bg-[var(--color-signal-warn)]/10 px-2 py-1.5 text-[11.5px] text-[var(--color-signal-warn)]"
        >
          <AlertTriangle size={12} />
          <span>{snapshot.warnings.length}</span>
        </button>
      )}

      <button
        onClick={onDownload}
        title={`${snapshot.workspace.name} · ${formatUtc(snapshot.generated_at_utc)} (${relativeTime(snapshot.generated_at_utc)})`}
        className="flex items-center gap-1.5 rounded-md border border-ink-800 bg-ink-900/70 px-2 py-1.5 text-[12px] text-ink-400 hover:border-ink-700 hover:text-ink-100"
      >
        <Download size={12} />
        <span className="hidden lg:inline">JSON</span>
      </button>
    </header>
  );
}

function ModeButton({
  active,
  icon,
  label,
  onClick,
}: {
  active: boolean;
  icon: React.ReactNode;
  label: string;
  onClick: () => void;
}) {
  return (
    <button
      onClick={onClick}
      className={cn(
        "flex items-center gap-1.5 rounded-md px-2.5 py-1.5 text-[12px] transition",
        active
          ? "bg-ink-800 text-ink-50"
          : "text-ink-400 hover:bg-ink-850/60 hover:text-ink-200"
      )}
    >
      {icon}
      {label}
    </button>
  );
}

function MartMenu({
  marts,
  active,
  martId,
  onSelect,
}: {
  marts: MartOption[];
  active: boolean;
  martId: string | null;
  onSelect: (id: string) => void;
}) {
  const current = marts.find((m) => m.id === martId);
  return (
    <div className="relative">
      <select
        value={active && martId ? martId : ""}
        onChange={(e) => e.target.value && onSelect(e.target.value)}
        className={cn(
          "cursor-pointer appearance-none rounded-md bg-transparent py-1.5 pl-2.5 pr-7 text-[12px] transition outline-none",
          active
            ? "bg-ink-800 text-ink-50"
            : "text-ink-400 hover:bg-ink-850/60 hover:text-ink-200"
        )}
      >
        <option value="" disabled>
          Mart{current ? `: ${current.label}` : ""}
        </option>
        {marts.map((m) => (
          <option key={m.id} value={m.id}>
            {m.label}
          </option>
        ))}
      </select>
      <svg
        className="pointer-events-none absolute right-2 top-1/2 -translate-y-1/2 text-ink-500"
        width="10"
        height="10"
        viewBox="0 0 24 24"
        fill="none"
        stroke="currentColor"
        strokeWidth="2.5"
        strokeLinecap="round"
        strokeLinejoin="round"
      >
        <path d="m6 9 6 6 6-6" />
      </svg>
    </div>
  );
}

function HopsPicker({ hops, onChange }: { hops: number; onChange: (h: number) => void }) {
  return (
    <div className="flex items-center gap-0.5 rounded-md border border-ink-800 bg-ink-900/70 px-1 py-0.5">
      <button
        onClick={() => onChange(Math.max(1, hops - 1))}
        disabled={hops <= 1}
        className="rounded p-1 text-ink-500 hover:bg-ink-800 hover:text-ink-200 disabled:opacity-40"
        aria-label="Fewer hops"
      >
        <Minus size={11} />
      </button>
      <span className="min-w-[42px] px-1 text-center font-mono text-[11px] text-ink-300">
        {hops} hop{hops === 1 ? "" : "s"}
      </span>
      <button
        onClick={() => onChange(Math.min(6, hops + 1))}
        disabled={hops >= 6}
        className="rounded p-1 text-ink-500 hover:bg-ink-800 hover:text-ink-200 disabled:opacity-40"
        aria-label="More hops"
      >
        <Plus size={11} />
      </button>
    </div>
  );
}
