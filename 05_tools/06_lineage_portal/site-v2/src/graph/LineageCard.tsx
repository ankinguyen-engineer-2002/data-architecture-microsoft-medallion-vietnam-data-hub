import { Handle, Position, type NodeProps } from "@xyflow/react";
import { memo } from "react";
import { cn } from "@/lib/util";
import type { LineageNode } from "@/lib/types";

const LAYER_ACCENT: Record<string, string> = {
  Bronze: "before:bg-[var(--color-bronze)]",
  Silver: "before:bg-[var(--color-silver)]",
  Gold: "before:bg-[var(--color-gold)]",
  Semantic: "before:bg-[var(--color-semantic)]",
};

const LAYER_LABEL: Record<string, string> = {
  Bronze: "Source",
  Silver: "Curated · Silver",
  Gold: "Curated · Gold",
  Semantic: "Semantic",
};

type Data = { lineage: LineageNode };

function LineageCardImpl({ data, selected }: NodeProps) {
  const node = (data as Data).lineage;
  const accent = LAYER_ACCENT[node.layer] ?? "before:bg-ink-500";
  const isSemantic = node.layer === "Semantic";

  // The single canonical semantic model — one model for every mart. Rendered
  // as a distinct, wider "model" card so it reads as a shared endpoint.
  if (isSemantic) {
    return (
      <div
        className={cn(
          "node-shell node-semantic group relative w-[268px] cursor-pointer overflow-hidden rounded-lg",
          "border border-[var(--color-semantic)]/40 bg-ink-900/80 backdrop-blur-sm",
          "before:absolute before:left-0 before:top-0 before:h-full before:w-[3px]",
          "before:bg-[var(--color-semantic)]",
          "hover:border-[var(--color-semantic)]/70",
          selected && "is-selected"
        )}
      >
        <Handle
          type="target"
          position={Position.Left}
          className="!h-2 !w-2 !border-0 !bg-[var(--color-semantic)]"
        />
        <div className="px-4 py-3">
          <div className="flex items-center gap-2 font-mono text-[10px] uppercase tracking-[0.14em] text-[var(--color-semantic)]">
            <span>Semantic model</span>
          </div>
          <div
            title={node.display_name}
            className="mt-1.5 break-words text-[13.5px] font-semibold leading-snug text-ink-100"
          >
            {node.display_name}
          </div>
          <div className="mt-0.5 truncate font-mono text-[11px] text-ink-500">
            Power BI · single shared model
          </div>
        </div>
      </div>
    );
  }

  return (
    <div
      className={cn(
        "node-shell group relative w-[268px] cursor-pointer overflow-hidden rounded-lg",
        "border border-ink-800 bg-ink-900/70 backdrop-blur-sm",
        "before:absolute before:left-0 before:top-0 before:h-full before:w-[3px]",
        accent,
        "hover:border-ink-600",
        selected && "is-selected"
      )}
    >
      <Handle
        type="target"
        position={Position.Left}
        className="!h-2 !w-2 !border-0 !bg-ink-600"
      />
      <div className="px-4 py-3">
        <div className="flex items-center gap-2 text-[10px] font-mono uppercase tracking-[0.14em] text-ink-500">
          <span>{LAYER_LABEL[node.layer] ?? node.layer}</span>
          {node.wave != null && (
            <>
              <span className="text-ink-700">·</span>
              <span>W{String(node.wave).padStart(2, "0")}</span>
            </>
          )}
        </div>
        <div
          title={node.display_name}
          className="mt-1.5 break-words text-[13.5px] font-medium leading-snug text-ink-100"
        >
          {node.display_name}
        </div>
        <div title={node.schema} className="mt-0.5 truncate font-mono text-[11px] text-ink-500">
          {node.schema}
        </div>
      </div>
      <Handle
        type="source"
        position={Position.Right}
        className="!h-2 !w-2 !border-0 !bg-ink-600"
      />
    </div>
  );
}

export const LineageCard = memo(LineageCardImpl);
