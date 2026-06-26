import { useEffect, useMemo, useState } from "react";
import { Background, Controls, MiniMap, ReactFlow, ReactFlowProvider, useReactFlow, type Edge, type Node } from "@xyflow/react";
import { AlertTriangle, Boxes, Database, Download, GitBranch, Search } from "lucide-react";
import { graphLanes, layoutGraph, toFlowEdges } from "./graph/layout";
import { DetailPanel } from "./panels/DetailPanel";
import type { LineageNode, Snapshot } from "./types";

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
  const [showUnclassified, setShowUnclassified] = useState(false);
  const { fitView } = useReactFlow();

  useEffect(() => {
    fetch(`${import.meta.env.BASE_URL}lineage_snapshot.json`)
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
      if (!showUnclassified && role === "unclassified") return false;
      if (includedIds && !includedIds.has(node.id)) return false;
      if (!needle && node.object_type !== "SEMANTIC_MODEL" && !connectedIds.has(node.id)) return false;
      if (layer !== "all" && node.layer !== layer) return false;
      if (!needle) return true;
      return `${node.display_name} ${node.full_name} ${node.schema}`.toLowerCase().includes(needle);
    });
  }, [snapshot, query, mart, layer, showUnclassified]);

  const filteredNodeIds = useMemo(() => new Set(filteredNodes.map((node) => node.id)), [filteredNodes]);
  const filteredEdges = useMemo(() => {
    if (!snapshot) return [];
    return snapshot.edges.filter((edge) => filteredNodeIds.has(edge.source) && filteredNodeIds.has(edge.target));
  }, [snapshot, filteredNodeIds]);

  useEffect(() => {
    if (!snapshot) return;
    layoutGraph(filteredNodes, filteredEdges).then(setFlowNodes);
    setFlowEdges(toFlowEdges(filteredEdges));
  }, [snapshot, filteredNodes, filteredEdges]);

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
  const lanes = useMemo(() => graphLanes(filteredNodes), [filteredNodes]);
  const activeMartLabel = mart === "all" ? "All business marts" : marts.find((item) => item.id === mart)?.display_name ?? mart;

  if (!snapshot) {
    return <main className="loading">Loading lineage snapshot...</main>;
  }

  return (
    <main className="app-shell">
      <header className="topbar">
        <div>
          <span className="eyebrow">Enterprise ETL</span>
          <h1>Supply Chain Lineage Portal</h1>
          <p>{snapshot.workspace.name} · {activeMartLabel} · generated {snapshot.generated_at_utc}</p>
        </div>
        <a className="download-button" href={`${import.meta.env.BASE_URL}lineage_snapshot.json`} download>
          <Download size={16} />
          Snapshot JSON
        </a>
      </header>

      <section className="summary-strip">
        <Summary icon={<Boxes size={18} />} label="Nodes" value={snapshot.nodes.length} />
        <Summary icon={<GitBranch size={18} />} label="Edges" value={snapshot.edges.length} />
        <Summary icon={<Database size={18} />} label="Marts" value={marts.length} />
        <Summary icon={<AlertTriangle size={18} />} label="Warnings" value={snapshot.warnings.length} />
      </section>

      <section className="toolbar">
        <label className="search-box">
          <Search size={16} />
          <input value={query} onChange={(event) => setQuery(event.target.value)} placeholder="Search table, schema, object..." />
        </label>
        <select value={mart} onChange={(event) => setMart(event.target.value)}>
          <option value="all">All business marts</option>
          {marts.map((item) => <option key={item.id} value={item.id}>{item.display_name}</option>)}
        </select>
        <select value={layer} onChange={(event) => setLayer(event.target.value)}>
          <option value="all">All layers</option>
          {layers.map((item) => <option key={item} value={item}>{item}</option>)}
        </select>
        <label className="toggle">
          <input type="checkbox" checked={showUnclassified} onChange={(event) => setShowUnclassified(event.target.checked)} />
          Needs classification
        </label>
      </section>

      {snapshot.warnings.length > 0 && (
        <section className="warning-band">
          {snapshot.warnings.map((warning) => <span key={warning}>{warning}</span>)}
        </section>
      )}

      <section className="workspace">
        <div className={`graph-card ${selected ? "with-detail" : ""}`}>
          <div className="lane-ruler" style={{ width: `${Math.max(lanes.length * 480, 1280)}px` }}>
            {lanes.map((lane) => (
              <div className="lane-marker" key={lane.key} style={{ left: lane.x }}>
                <span>{lane.label}</span>
                <strong>{lane.count}</strong>
              </div>
            ))}
          </div>
          <ReactFlow
            nodes={flowNodes}
            edges={flowEdges}
            fitView
            minZoom={0.38}
            onNodeClick={(_: React.MouseEvent, node: Node) => setSelected((node.data.lineage as LineageNode) ?? null)}
          >
            <Background color="#23304a" gap={22} />
            <MiniMap pannable zoomable />
            <Controls />
          </ReactFlow>
          <DetailPanel node={selected} edges={snapshot.edges} onClose={() => setSelected(null)} />
        </div>
      </section>
    </main>
  );
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
