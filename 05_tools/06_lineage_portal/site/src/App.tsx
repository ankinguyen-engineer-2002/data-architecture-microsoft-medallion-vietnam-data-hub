"use client";

import { useEffect, useMemo, useState } from "react";
import { Background, Controls, ReactFlow, ReactFlowProvider, useReactFlow, type Edge, type Node } from "@xyflow/react";
import { AlertTriangle, Boxes, Database, Download, GitBranch, Layers3, Search } from "lucide-react";
import { layoutGraph, toFlowEdges } from "./graph/layout";
import { LineageTableNode } from "./graph/LineageTableNode";
import { DetailPanel } from "./panels/DetailPanel";
import type { LineageEdge, LineageNode, Snapshot } from "./types";

const nodeTypes = {
  lineageTable: LineageTableNode
};

const basePath = process.env.NEXT_PUBLIC_BASE_PATH ?? "";

export function App() {
  return (
    <ReactFlowProvider>
      <LineagePortal />
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
  const { fitView } = useReactFlow();

  useEffect(() => {
    fetch(`${basePath}/lineage_snapshot.json`)
      .then((response) => response.json())
      .then((data: Snapshot) => {
        setSnapshot(data);
        const firstMart = data.mart_registry?.[0]?.id;
        if (firstMart) setMart(firstMart);
      });
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
          className: [node.className, selected && !highlighted?.nodes.has(node.id) ? "is-dim" : "", highlighted?.nodes.has(node.id) ? "is-highlight" : ""]
            .filter(Boolean)
            .join(" ")
        }))
      );
    });
    setFlowEdges(
      toFlowEdges(filteredEdges).map((edge) => ({
        ...edge,
        className: [edge.className, selected && !highlighted?.edges.has(edge.id) ? "is-dim" : "", highlighted?.edges.has(edge.id) ? "is-highlight" : ""]
          .filter(Boolean)
          .join(" ")
      }))
    );
  }, [snapshot, filteredNodes, filteredEdges, selected]);

  useEffect(() => {
    if (flowNodes.length === 0) return;
    const frame = requestAnimationFrame(() => {
      fitView({ padding: 0.08, duration: 250, maxZoom: 0.95 });
    });
    return () => cancelAnimationFrame(frame);
  }, [flowEdges.length, flowNodes.length, fitView]);

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
  const activeMartLabel = mart === "all" ? "All business marts" : marts.find((item) => item.id === mart)?.display_name ?? mart;

  if (!snapshot) {
    return <main className="loading">Loading lineage snapshot...</main>;
  }

  const visibleWarnings = snapshot.warnings.length;

  return (
    <main className="app-shell">
      <header className="topbar">
        <div>
          <span className="eyebrow">Enterprise ETL</span>
          <h1>Supply Chain Data Flow</h1>
          <p>{snapshot.workspace.name} · {activeMartLabel} · table-to-table lineage · generated {snapshot.generated_at_utc}</p>
        </div>
        <a className="download-button" href={`${basePath}/lineage_snapshot.json`} download>
          <Download size={16} />
          Snapshot JSON
        </a>
      </header>

      {snapshot.warnings.length > 0 && (
        <section className="warning-band">
          {snapshot.warnings.map((warning) => <span key={warning}>{warning}</span>)}
        </section>
      )}

      <section className="workspace">
        <aside className="sidebar">
          <label className="search-box">
            <Search size={16} />
            <input value={query} onChange={(event) => setQuery(event.target.value)} placeholder="Search table, schema, object..." />
          </label>

          <div className="sidebar-section">
            <span className="section-label">Mart</span>
            <select value={mart} onChange={(event) => setMart(event.target.value)}>
              <option value="all">All business marts</option>
              {marts.map((item) => <option key={item.id} value={item.id}>{item.display_name}</option>)}
            </select>
          </div>

          <div className="sidebar-section">
            <span className="section-label">Layer</span>
            <select value={layer} onChange={(event) => setLayer(event.target.value)}>
              <option value="all">All layers</option>
              {layers.map((item) => <option key={item} value={item}>{item}</option>)}
            </select>
          </div>

          <label className="toggle">
            <input type="checkbox" checked={showSupport} onChange={(event) => setShowSupport(event.target.checked)} />
            Show shared/support
          </label>

          <div className="summary-stack">
            <Summary icon={<Boxes size={18} />} label="Visible tables" value={filteredNodes.length} />
            <Summary icon={<GitBranch size={18} />} label="Visible flows" value={filteredEdges.length} />
            <Summary icon={<Database size={18} />} label="Marts" value={marts.length} />
            <Summary icon={<AlertTriangle size={18} />} label="Warnings" value={visibleWarnings} />
          </div>
        </aside>

        <div className={`graph-card ${selected ? "with-detail" : ""}`}>
          <ReactFlow
            nodes={flowNodes}
            edges={flowEdges}
            nodeTypes={nodeTypes}
            fitView
            minZoom={0.42}
            maxZoom={1.35}
            defaultEdgeOptions={{ type: "bezier" }}
            onNodeClick={(_: React.MouseEvent, node: Node) => setSelected((node.data.lineage as LineageNode) ?? null)}
          >
            <Background color="#1f2a44" gap={26} />
            <Controls />
          </ReactFlow>
        </div>

        <aside className="properties-panel">
          {selected ? (
            <DetailPanel node={selected} edges={filteredEdges} onClose={() => setSelected(null)} />
          ) : (
            <div className="empty-detail">
              <Layers3 size={20} />
              <h2>Properties</h2>
              <p>Select a table to inspect upstream, downstream, row count, wave, and captured SQL evidence.</p>
            </div>
          )}
        </aside>
      </section>
    </main>
  );
}

function lineageNeighborhood(startId: string, edges: LineageEdge[]): { nodes: Set<string>; edges: Set<string> } {
  const nodes = new Set<string>([startId]);
  const edgeIds = new Set<string>();
  const forward = new Map<string, LineageEdge[]>();
  const backward = new Map<string, LineageEdge[]>();
  for (const edge of edges) {
    forward.set(edge.source, [...(forward.get(edge.source) ?? []), edge]);
    backward.set(edge.target, [...(backward.get(edge.target) ?? []), edge]);
  }
  const queue = [startId];
  while (queue.length > 0) {
    const nodeId = queue.shift();
    if (!nodeId) continue;
    for (const edge of [...(forward.get(nodeId) ?? []), ...(backward.get(nodeId) ?? [])]) {
      edgeIds.add(edge.id);
      for (const next of [edge.source, edge.target]) {
        if (!nodes.has(next)) {
          nodes.add(next);
          queue.push(next);
        }
      }
    }
  }
  return { nodes, edges: edgeIds };
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

function downstreamVisibleTargets(
  start: string,
  outgoing: Map<string, LineageEdge[]>,
  visibleNodeIds: Set<string>
): string[] {
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

function Summary({ icon, label, value }: { icon: JSX.Element; label: string; value: number }) {
  return (
    <div className="summary-card">
      {icon}
      <span>{label}</span>
      <strong>{value.toLocaleString()}</strong>
    </div>
  );
}
