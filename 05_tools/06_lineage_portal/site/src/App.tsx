import { useEffect, useMemo, useState } from "react";
import { Background, Controls, MiniMap, ReactFlow, ReactFlowProvider, useReactFlow, type Edge, type Node } from "@xyflow/react";
import { AlertTriangle, Boxes, Download, GitBranch, Search } from "lucide-react";
import { layoutGraph, toFlowEdges } from "./graph/layout";
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
  const [unresolvedOnly, setUnresolvedOnly] = useState(false);
  const { fitView } = useReactFlow();

  useEffect(() => {
    fetch(`${import.meta.env.BASE_URL}lineage_snapshot.json`)
      .then((response) => response.json())
      .then((data: Snapshot) => setSnapshot(data));
  }, []);

  const filteredNodes = useMemo(() => {
    if (!snapshot) return [];
    const needle = query.trim().toLowerCase();
    return snapshot.nodes.filter((node) => {
      if (mart !== "all" && node.mart !== mart) return false;
      if (layer !== "all" && node.layer !== layer) return false;
      if (unresolvedOnly && node.status !== "referenced" && node.mart !== "unresolved") return false;
      if (!needle) return true;
      return `${node.display_name} ${node.full_name} ${node.schema}`.toLowerCase().includes(needle);
    });
  }, [snapshot, query, mart, layer, unresolvedOnly]);

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
      fitView({ padding: 0.08, duration: 250, maxZoom: 0.72 });
    });
    return () => cancelAnimationFrame(frame);
  }, [flowEdges.length, flowNodes.length, fitView]);

  const marts = useMemo(() => snapshot?.marts.map((item) => item.mart).sort() ?? [], [snapshot]);
  const layers = useMemo(() => snapshot?.layers.map((item) => item.layer).sort() ?? [], [snapshot]);

  if (!snapshot) {
    return <main className="loading">Loading lineage snapshot...</main>;
  }

  return (
    <main className="app-shell">
      <header className="topbar">
        <div>
          <span className="eyebrow">Enterprise ETL</span>
          <h1>Supply Chain Lineage Portal</h1>
          <p>{snapshot.workspace.name} · generated {snapshot.generated_at_utc}</p>
        </div>
        <a className="download-button" href={`${import.meta.env.BASE_URL}lineage_snapshot.json`} download>
          <Download size={16} />
          Snapshot JSON
        </a>
      </header>

      <section className="summary-strip">
        <Summary icon={<Boxes size={18} />} label="Nodes" value={snapshot.nodes.length} />
        <Summary icon={<GitBranch size={18} />} label="Edges" value={snapshot.edges.length} />
        <Summary icon={<AlertTriangle size={18} />} label="Warnings" value={snapshot.warnings.length} />
      </section>

      <section className="toolbar">
        <label className="search-box">
          <Search size={16} />
          <input value={query} onChange={(event) => setQuery(event.target.value)} placeholder="Search table, schema, object..." />
        </label>
        <select value={mart} onChange={(event) => setMart(event.target.value)}>
          <option value="all">All marts</option>
          {marts.map((item) => <option key={item} value={item}>{item}</option>)}
        </select>
        <select value={layer} onChange={(event) => setLayer(event.target.value)}>
          <option value="all">All layers</option>
          {layers.map((item) => <option key={item} value={item}>{item}</option>)}
        </select>
        <label className="toggle">
          <input type="checkbox" checked={unresolvedOnly} onChange={(event) => setUnresolvedOnly(event.target.checked)} />
          Unresolved only
        </label>
      </section>

      {snapshot.warnings.length > 0 && (
        <section className="warning-band">
          {snapshot.warnings.map((warning) => <span key={warning}>{warning}</span>)}
        </section>
      )}

      <section className="workspace">
        <div className="graph-card">
          <ReactFlow
            nodes={flowNodes}
            edges={flowEdges}
            fitView
            minZoom={0.32}
            onNodeClick={(_: React.MouseEvent, node: Node) => setSelected((node.data.lineage as LineageNode) ?? null)}
          >
            <Background color="#d8dee9" gap={18} />
            <MiniMap pannable zoomable />
            <Controls />
          </ReactFlow>
        </div>
        <DetailPanel node={selected} edges={snapshot.edges} onClose={() => setSelected(null)} />
      </section>
    </main>
  );
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
