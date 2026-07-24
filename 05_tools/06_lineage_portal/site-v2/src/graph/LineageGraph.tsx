import {
  Background,
  Controls,
  ReactFlow,
  ReactFlowProvider,
  useReactFlow,
  useViewport,
  type Edge,
  type Node,
} from "@xyflow/react";
import { useEffect, useMemo } from "react";
import { LineageCard } from "./LineageCard";
import { laneLayout, toFlowEdges, type Lane } from "./layout";
import type { LineageEdge, LineageNode } from "@/lib/types";

const nodeTypes = { lineageCard: LineageCard };

export type FocusHighlight = {
  selectedId: string;
  upstream: Set<string>;
  downstream: Set<string>;
  upstreamEdges: Set<string>;
  downstreamEdges: Set<string>;
};

type Props = {
  nodes: LineageNode[];
  edges: LineageEdge[];
  highlight: FocusHighlight | null;
  selectedId: string | null;
  onSelect: (node: LineageNode) => void;
  onClear: () => void;
};

export function LineageGraph(props: Props) {
  return (
    <ReactFlowProvider>
      <GraphInner {...props} />
    </ReactFlowProvider>
  );
}

function GraphInner({ nodes, edges, highlight, selectedId, onSelect, onClear }: Props) {
  const { fitView } = useReactFlow();

  // Synchronous deterministic layout — instant, no async engine.
  const { flowNodes, flowEdges, lanes } = useMemo(() => {
    const { nodes: laid, lanes, diagnostics } = laneLayout(nodes, edges);
    if (import.meta.env.DEV) {
      const { backwardEdges, sameColumnEdges, crossBandBackward, cycleNodes } = diagnostics;
      if (backwardEdges || sameColumnEdges || crossBandBackward || cycleNodes.length) {
        // Any nonzero value means the topology engine could not fully resolve a
        // left→right ordering — surfaced so new marts/tables get caught early.
        console.warn("[lineage layout diagnostics]", {
          backwardEdges,
          sameColumnEdges,
          crossBandBackward,
          cycleNodes,
        });
      }
    }
    const accentEdgeIds = highlight
      ? new Set([...highlight.upstreamEdges, ...highlight.downstreamEdges])
      : undefined;

    const decoratedNodes: Node[] = laid.map((node) => {
      const id = node.id;
      let stateClass = "";
      if (highlight) {
        if (id === highlight.selectedId) stateClass = "is-selected";
        else if (highlight.upstream.has(id)) stateClass = "is-upstream";
        else if (highlight.downstream.has(id)) stateClass = "is-downstream";
        else stateClass = "is-dim";
      }
      return {
        ...node,
        selected: id === selectedId,
        className: `node-shell ${stateClass}`.trim(),
      };
    });

    const decoratedEdges: Edge[] = toFlowEdges(edges, accentEdgeIds).map((edge) => {
      if (!highlight) return edge;
      const isUp = highlight.upstreamEdges.has(edge.id);
      const isDown = highlight.downstreamEdges.has(edge.id);
      const cls = isUp ? "is-upstream" : isDown ? "is-downstream" : "is-dim";
      return { ...edge, className: `${edge.className ?? ""} ${cls}`.trim() };
    });

    return { flowNodes: decoratedNodes, flowEdges: decoratedEdges, lanes };
  }, [nodes, edges, highlight, selectedId]);

  // Re-fit whenever the node set changes.
  useEffect(() => {
    const t = setTimeout(() => fitView({ padding: 0.18, duration: 320, maxZoom: 1 }), 40);
    return () => clearTimeout(t);
  }, [nodes, edges, fitView]);

  return (
    <div className="relative h-full w-full">
      <ReactFlow
        nodes={flowNodes}
        edges={flowEdges}
        nodeTypes={nodeTypes}
        fitView
        fitViewOptions={{ padding: 0.18, maxZoom: 1 }}
        minZoom={0.12}
        maxZoom={1.6}
        proOptions={{ hideAttribution: true }}
        nodesDraggable={false}
        nodesConnectable={false}
        elementsSelectable
        onNodeClick={(_, node) => {
          const lineage = (node.data as { lineage: LineageNode }).lineage;
          onSelect(lineage);
        }}
        onPaneClick={onClear}
      >
        <Background
          color="color-mix(in oklch, var(--color-ink-700) 35%, transparent)"
          gap={30}
          size={1}
        />
        <Controls
          showInteractive={false}
          position="bottom-right"
          className="!bottom-6 !right-6"
        />
      </ReactFlow>
      <LaneHeaders lanes={lanes} />
    </div>
  );
}

/** Sticky band headers that track the flow's pan/zoom via useViewport (no polling).
 *  One header per medallion band, spanning all its columns, so they never overlap. */
function LaneHeaders({ lanes }: { lanes: Lane[] }) {
  const vp = useViewport();

  return (
    <div className="pointer-events-none absolute inset-x-0 top-0 z-[6] h-12 overflow-hidden">
      {lanes.map((lane) => {
        // Band spans [xStart, xEnd] in flow coords → project to screen and center.
        const left = lane.xStart * vp.zoom + vp.x;
        const width = (lane.xEnd - lane.xStart) * vp.zoom;
        return (
          <div
            key={lane.key}
            className="lane-band"
            style={{ left, width }}
          >
            <span className={`lane-header ${laneAccent(lane.layer)}`}>
              <span className="dot" style={{ background: laneDot(lane.layer) }} />
              {lane.label}
            </span>
          </div>
        );
      })}
    </div>
  );
}

function laneAccent(layer: string): string {
  switch (layer) {
    case "Bronze":
      return "!border-[var(--color-bronze)]/35 !text-[var(--color-bronze)]";
    case "Silver":
      return "!border-[var(--color-silver)]/35 !text-[var(--color-silver)]";
    case "Gold":
      return "!border-[var(--color-gold)]/35 !text-[var(--color-gold)]";
    case "Semantic":
      return "!border-[var(--color-semantic)]/35 !text-[var(--color-semantic)]";
    default:
      return "";
  }
}

function laneDot(layer: string): string {
  switch (layer) {
    case "Bronze":
      return "var(--color-bronze)";
    case "Silver":
      return "var(--color-silver)";
    case "Gold":
      return "var(--color-gold)";
    case "Semantic":
      return "var(--color-semantic)";
    default:
      return "var(--color-ink-500)";
  }
}
