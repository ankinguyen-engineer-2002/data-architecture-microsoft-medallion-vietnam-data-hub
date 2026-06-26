"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { Background, Controls, ReactFlow, ReactFlowProvider, type Edge, type Node } from "@xyflow/react";
import { AlertTriangle, Boxes, Database, Download, GitBranch, Search } from "lucide-react";
import { motion } from "motion/react";
import { layoutGraph, toFlowEdges } from "./graph/layout";
import { LineageTableNode } from "./graph/LineageTableNode";
import { DetailPanel } from "./panels/DetailPanel";
import { Sidebar } from "./panels/Sidebar";
import { CommandPalette } from "./panels/CommandPalette";
import { Legend } from "./panels/Legend";
import { ErrorBoundary } from "./ErrorBoundary";
import type { LineageEdge, LineageNode, Snapshot } from "./types";

const nodeTypes = { lineageTable: LineageTableNode };
const basePath = process.env.NEXT_PUBLIC_BASE_PATH ?? "";

export function App() {
  return (
    <ReactFlowProvider>
      <ErrorBoundary>
        <LineagePortal />
      </ErrorBoundary>
    </ReactFlowProvider>
  );
}

function LineagePortal() {
  const [snapshot, setSnapshot] = useState<Snapshot | null>(null);
  const [flowNodes, setFlowNodes] = useState<Node[]>([]);
  const [flowEdges, setFlowEdges] = useState<Edge[]>([]);
  const [selected, setSelected] = useState<LineageNode | null>(null);
  const [query, setQuery] = useState("");
  const [mart, setMart] = useState("all");
  const [layer, setLayer] = useState("all");
  const [showSupport, setShowSupport] = useState(false);
  const [sidebarCollapsed, setSidebarCollapsed] = useState(false);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    fetch(`${basePath}/lineage_snapshot.json`)
      .then((response) => response.json())
      .then((data: Snapshot) => {
        setSnapshot(data);
        setLoading(false);
        const firstMart = data.mart_registry?.[0]?.id;
        if (firstMart) setMart(firstMart);
      })
      .catch(() => setLoading(false));
  }, []);

  // Keyboard shortcuts
  useEffect(() => {
    const handler = (event: KeyboardEvent) => {
      if (event.key === "Escape") {
        setSelected(null);
        setQuery("");
      }
      if ((event.metaKey || event.ctrlKey) && event.key === "b") {
        event.preventDefault();
        setSidebarCollapsed((prev) => !prev);
      }
    };
    document.addEventListener("keydown", handler);
    return () => document.removeEventListener("keydown", handler);
  }, []);

  const filteredNodes = useMemo(() => {
    if (!snapshot) return [];
    const needle = query.trim().toLowerCase();
    const includedIds = mart === "all" ? null : lineageClosure(snapshot, mart);
    const connectedIds = new Set(snapshot.edges.flatMap((edge) => [edge.source, edge.target]));
    return snapshot.nodes.filter((node) => {
      const role = node.role ?? "business";
      if (!showSupport && ["support", "unclassified"].includes(role)) return false;
      if (includedIds && !includedIds.has(node.id)) return false;
      if (!needle && node.object_type !== "SEMANTIC_MODEL" && !connectedIds.has(node.id)) return false;
      if (layer !== "all" && node.layer !== layer) return false;
      if (!needle) return true;
      return `${node.display_name} ${node.full_name} ${node.schema}`.toLowerCase().includes(needle);
    });
  }, [snapshot, query, mart, layer, showSupport]);

  const filteredNodeIds = useMemo(() => new Set(filteredNodes.map((node) => node.id)), [filteredNodes]);
  const filteredEdges = useMemo(() => {
    if (!snapshot) return [];
    return collapseEdgesThroughHiddenNodes(snapshot.edges, filteredNodeIds);
  }, [snapshot, filteredNodeIds]);

  useEffect(() => {
    if (!snapshot) return;
    const highlighted = selected ? lineageNeighborhood(selected.id, filteredEdges) : null;
    layoutGraph(filteredNodes, filteredEdges).then((nodes) => {
      setFlowNodes(
        nodes.map((node) => ({
          ...node,
          className: [
            node.className,
            selected && !highlighted?.nodes.has(node.id) ? "is-dim" : "",
            highlighted?.selected === node.id ? "is-selected-focus" : "",
            highlighted?.upstream.has(node.id) ? "is-upstream" : "",
            highlighted?.downstream.has(node.id) ? "is-downstream" : ""
          ]
            .filter(Boolean)
            .join(" ")
        }))
      );
    });
    setFlowEdges(
      toFlowEdges(filteredEdges).map((edge) => ({
        ...edge,
        className: [
          edge.className,
          selected && !highlighted?.edges.has(edge.id) ? "is-dim" : "",
          highlighted?.upstreamEdges.has(edge.id) ? "is-upstream" : "",
          highlighted?.downstreamEdges.has(edge.id) ? "is-downstream" : ""
        ]
          .filter(Boolean)
          .join(" ")
      }))
    );
  }, [snapshot, filteredNodes, filteredEdges, selected]);

  const marts = useMemo(() => {
    if (snapshot?.mart_registry?.length) return snapshot.mart_registry;
    return (snapshot?.marts ?? [])
      .filter((item) => !["shared", "unresolved"].includes(item.mart))
      .map((item) => ({ id: item.mart, display_name: item.mart.replaceAll("_", " "), catalog_path: "" }));
  }, [snapshot]);

  const layers = useMemo(() => {
    const order = ["Bronze", "Silver", "Gold", "Semantic"];
    return (snapshot?.layers.map((item) => item.layer) ?? []).sort((a, b) => order.indexOf(a) - order.indexOf(b));
  }, [snapshot]);

  const layerBadgeCounts = useMemo(() => {
    const counts: Record<string, number> = {};
    for (const node of filteredNodes) {
      counts[node.layer] = (counts[node.layer] ?? 0) + 1;
    }
    return counts;
  }, [filteredNodes]);

  const activeMartLabel = mart === "all" ? "All business marts" : marts.find((item) => item.id === mart)?.display_name ?? mart;

  const handleSelectNode = useCallback((nodeId: string) => {
    const node = snapshot?.nodes.find((n) => n.id === nodeId);
    if (node) {
      setSelected(node);
      setQuery("");
    }
  }, [snapshot]);

  const handleDownload = useCallback(() => {
    const link = document.createElement("a");
    link.href = `${basePath}/lineage_snapshot.json`;
    link.download = "lineage_snapshot.json";
    link.click();
  }, []);

  // Loading state
  if (loading) {
    return (
      <main className="app-shell">
        <div className="loading-skeleton">
          <motion.div
            className="skeleton-bar skeleton-title"
            animate={{ opacity: [0.4, 0.8, 0.4] }}
            transition={{ repeat: Infinity, duration: 2 }}
          />
          <motion.div
            className="skeleton-bar skeleton-subtitle"
            animate={{ opacity: [0.4, 0.8, 0.4] }}
            transition={{ repeat: Infinity, duration: 2, delay: 0.15 }}
          />
          <div className="skeleton-grid">
            <motion.div
              className="skeleton-card"
              animate={{ opacity: [0.3, 0.7, 0.3] }}
              transition={{ repeat: Infinity, duration: 2, delay: 0.3 }}
            />
            <motion.div
              className="skeleton-card"
              animate={{ opacity: [0.3, 0.7, 0.3] }}
              transition={{ repeat: Infinity, duration: 2, delay: 0.45 }}
            />
            <motion.div
              className="skeleton-card"
              animate={{ opacity: [0.3, 0.7, 0.3] }}
              transition={{ repeat: Infinity, duration: 2, delay: 0.6 }}
            />
            <motion.div
              className="skeleton-card"
              animate={{ opacity: [0.3, 0.7, 0.3] }}
              transition={{ repeat: Infinity, duration: 2, delay: 0.75 }}
            />
          </div>
        </div>
      </main>
    );
  }

  if (!snapshot) {
    return <main className="loading">Failed to load lineage snapshot.</main>;
  }

  const visibleWarnings = snapshot.warnings.length;
  const totalNodeCount = snapshot.nodes.filter((n) => {
    const role = n.role ?? "business";
    if (!showSupport && ["support", "unclassified"].includes(role)) return false;
    return true;
  }).length;

  // Compute lane groups for column headers
  const laneGroups = useMemo(() => {
    const groups = new Map<string, { label: string; order: number; x: number }>();
    for (const node of flowNodes) {
      const lineage = node.data.lineage as LineageNode;
      const key = laneKeyFor(lineage);
      if (!groups.has(key)) {
        groups.set(key, {
          label: laneLabelFor(lineage),
          order: laneOrderFor(lineage),
          x: node.position.x
        });
      }
    }
    return [...groups.values()].sort((a, b) => a.order - b.order);
  }, [flowNodes]);

  return (
    <main className="app-shell">
      <CommandPalette
        nodes={filteredNodes}
        marts={marts}
        onSelectNode={handleSelectNode}
        onSetMart={setMart}
        onSetLayer={setLayer}
        onToggleSupport={() => setShowSupport((prev) => !prev)}
        showSupport={showSupport}
        onDownload={handleDownload}
      />

      <motion.header
        className="topbar"
        initial={{ opacity: 0, y: -12 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ duration: 0.4, ease: [0.25, 0.1, 0.25, 1] }}
      >
        <div>
          <span className="eyebrow">Enterprise ETL</span>
          <h1>Supply Chain Data Flow</h1>
          <p>{snapshot.workspace.name} · {activeMartLabel} · table-to-table lineage · generated {snapshot.generated_at_utc}</p>
        </div>
        <div className="topbar-actions">
          <button className="download-button" onClick={handleDownload}>
            <Download size={16} />
            Snapshot JSON
          </button>
        </div>
      </motion.header>

      {snapshot.warnings.length > 0 && (
        <motion.section
          className="warning-band"
          initial={{ opacity: 0, height: 0 }}
          animate={{ opacity: 1, height: "auto" }}
          transition={{ delay: 0.2, duration: 0.3 }}
        >
          {snapshot.warnings.map((warning) => <span key={warning}>{warning}</span>)}
        </motion.section>
      )}

      <section className={`workspace ${sidebarCollapsed ? "sidebar-collapsed" : ""}`}>
        <Sidebar
          query={query}
          onQueryChange={setQuery}
          mart={mart}
          onMartChange={setMart}
          layer={layer}
          onLayerChange={setLayer}
          showSupport={showSupport}
          onToggleSupport={() => setShowSupport((prev) => !prev)}
          marts={marts}
          layers={layers}
          filteredNodeCount={filteredNodes.length}
          filteredEdgeCount={filteredEdges.length}
          totalNodeCount={totalNodeCount}
          warningCount={visibleWarnings}
          collapsed={sidebarCollapsed}
          onToggleCollapse={() => setSidebarCollapsed((prev) => !prev)}
          layerBadgeCounts={layerBadgeCounts}
        />

        <div className={`graph-card ${selected ? "with-detail" : ""}`}>
          {/* Lane column headers */}
          <div className="lane-headers">
            {laneGroups.map((group) => (
              <div
                key={group.label}
                className="lane-header"
                style={{ left: group.x + 12 }}
              >
                <span className={`lane-header-badge lane-${group.label.split(" ")[0].toLowerCase()}`}>
                  {group.label}
                </span>
              </div>
            ))}
          </div>

          {filteredNodes.length === 0 ? (
            <motion.div
              className="empty-graph"
              initial={{ opacity: 0, scale: 0.95 }}
              animate={{ opacity: 1, scale: 1 }}
              transition={{ duration: 0.3 }}
            >
              <Search size={42} />
              <h2>No tables match</h2>
              <p>Try adjusting the mart, layer, or search filters to see lineage.</p>
              <button className="download-button" onClick={() => { setQuery(""); setMart("all"); setLayer("all"); }}>
                Reset all filters
              </button>
            </motion.div>
          ) : (
            <ReactFlow
              nodes={flowNodes}
              edges={flowEdges}
              nodeTypes={nodeTypes}
              defaultViewport={{ x: 18, y: 46, zoom: 0.72 }}
              minZoom={0.22}
              maxZoom={1.35}
              defaultEdgeOptions={{ type: "bezier" }}
              onNodeClick={(_: React.MouseEvent, node: Node) => setSelected((node.data.lineage as LineageNode) ?? null)}
              onPaneClick={() => setSelected(null)}
            >
              <Background color="#1f2a44" gap={26} />
              <Controls />
            </ReactFlow>
          )}

          <Legend />
        </div>

        <DetailPanel
          node={selected}
          nodes={filteredNodes}
          edges={filteredEdges}
          onClose={() => setSelected(null)}
        />
      </section>
    </main>
  );
}

function lineageNeighborhood(startId: string, edges: LineageEdge[]) {
  const nodes = new Set<string>([startId]);
  const upstream = new Set<string>();
  const downstream = new Set<string>();
  const upstreamEdges = new Set<string>();
  const downstreamEdges = new Set<string>();
  const forward = new Map<string, LineageEdge[]>();
  const backward = new Map<string, LineageEdge[]>();
  for (const edge of edges) {
    forward.set(edge.source, [...(forward.get(edge.source) ?? []), edge]);
    backward.set(edge.target, [...(backward.get(edge.target) ?? []), edge]);
  }
  walkLineage(startId, backward, "source", upstream, upstreamEdges);
  walkLineage(startId, forward, "target", downstream, downstreamEdges);
  for (const nodeId of [...upstream, ...downstream]) nodes.add(nodeId);
  return { selected: startId, nodes, upstream, downstream, edges: new Set([...upstreamEdges, ...downstreamEdges]), upstreamEdges, downstreamEdges };
}

function walkLineage(
  startId: string,
  graph: Map<string, LineageEdge[]>,
  nextKey: "source" | "target",
  nodes: Set<string>,
  edgeIds: Set<string>
): void {
  const queue = [startId];
  const visited = new Set<string>([startId]);
  while (queue.length > 0) {
    const nodeId = queue.shift();
    if (!nodeId) continue;
    for (const edge of graph.get(nodeId) ?? []) {
      const next = edge[nextKey];
      edgeIds.add(edge.id);
      nodes.add(next);
      if (!visited.has(next)) {
        visited.add(next);
        queue.push(next);
      }
    }
  }
}

function collapseEdgesThroughHiddenNodes(edges: LineageEdge[], visibleNodeIds: Set<string>): LineageEdge[] {
  const direct = new Map<string, LineageEdge>();
  const outgoing = new Map<string, LineageEdge[]>();
  for (const edge of edges) {
    outgoing.set(edge.source, [...(outgoing.get(edge.source) ?? []), edge]);
  }
  for (const edge of edges) {
    if (!visibleNodeIds.has(edge.source)) continue;
    if (visibleNodeIds.has(edge.target)) {
      direct.set(edgeKey(edge.source, edge.target, edge.relationship_type), edge);
      continue;
    }
    for (const target of downstreamVisibleTargets(edge.target, outgoing, visibleNodeIds)) {
      if (target === edge.source) continue;
      const relationship = target.startsWith("SemanticModel.") ? "semantic_binding" : "transforms_to";
      const id = `ui-collapse:${edge.source}->${target}:${relationship}`;
      direct.set(edgeKey(edge.source, target, relationship), {
        id,
        source: edge.source,
        target,
        relationship_type: relationship,
        confidence: edge.confidence,
        evidence: `Collapsed hidden support path from ${edge.target}`
      });
    }
  }
  return [...direct.values()];
}

function downstreamVisibleTargets(start: string, outgoing: Map<string, LineageEdge[]>, visibleNodeIds: Set<string>): string[] {
  const targets: string[] = [];
  const queue = [start];
  const visited = new Set<string>();
  while (queue.length > 0) {
    const nodeId = queue.shift();
    if (!nodeId || visited.has(nodeId)) continue;
    visited.add(nodeId);
    if (visibleNodeIds.has(nodeId)) {
      targets.push(nodeId);
      continue;
    }
    for (const edge of outgoing.get(nodeId) ?? []) {
      if (!visited.has(edge.target)) queue.push(edge.target);
    }
  }
  return targets;
}

function edgeKey(source: string, target: string, relationship: string): string {
  return `${source}|${target}|${relationship}`;
}

function lineageClosure(snapshot: Snapshot, mart: string): Set<string> {
  const included = new Set<string>();
  const nodeById = new Map(snapshot.nodes.map((node) => [node.id, node]));
  const forward = new Map<string, string[]>();
  const backward = new Map<string, string[]>();
  for (const edge of snapshot.edges) {
    forward.set(edge.source, [...(forward.get(edge.source) ?? []), edge.target]);
    backward.set(edge.target, [...(backward.get(edge.target) ?? []), edge.source]);
  }
  const queue = snapshot.nodes
    .filter((node) => node.mart === mart || node.object_type === "SEMANTIC_MODEL")
    .map((node) => node.id);
  while (queue.length > 0) {
    const nodeId = queue.shift();
    if (!nodeId || included.has(nodeId)) continue;
    included.add(nodeId);
    for (const next of [...(forward.get(nodeId) ?? []), ...(backward.get(nodeId) ?? [])]) {
      const node = nodeById.get(next);
      const role = node?.role ?? "business";
      const allowed = node?.mart === mart || role === "support" || role === "semantic" || node?.object_type === "SEMANTIC_MODEL";
      if (allowed && !included.has(next)) queue.push(next);
    }
  }
  return included;
}

function laneKeyFor(node: LineageNode): string {
  return `${laneOrderFor(node)}:${laneLabelFor(node)}`;
}

function laneLabelFor(node: LineageNode): string {
  if (node.layer === "Bronze") return "Bronze";
  if (node.layer === "Semantic") return "Semantic";
  if (node.wave == null) return node.layer;
  return `${node.layer} W${String(node.wave).padStart(2, "0")}`;
}

function laneOrderFor(node: LineageNode): number {
  if (node.layer === "Bronze") return 0;
  if (node.layer === "Silver") return 100 + (node.wave ?? 0);
  if (node.layer === "Gold") return 200 + (node.wave ?? 0);
  if (node.layer === "Semantic") return 400;
  return 900 + (node.wave ?? 0);
}
