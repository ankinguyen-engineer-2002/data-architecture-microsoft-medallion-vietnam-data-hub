"use client";

import { Code2, Database, GitBranch, Layers3, X } from "lucide-react";
import type { LineageEdge, LineageNode } from "../types";

type Props = {
  node: LineageNode | null;
  nodes: LineageNode[];
  edges: LineageEdge[];
  onClose: () => void;
};

export function DetailPanel({ node, nodes, edges, onClose }: Props) {
  if (!node) return null;

  const nodeById = new Map(nodes.map((item) => [item.id, item]));
  const upstream = edges.filter((edge) => edge.target === node.id);
  const downstream = edges.filter((edge) => edge.source === node.id);

  return (
    <aside className="properties-panel">
      <div className="detail-panel">
        <button className="icon-button close" onClick={onClose} aria-label="Close detail panel">
          <X size={18} />
        </button>
        <div className="detail-heading">
          <span className={`layer-pill ${node.layer.toLowerCase()}`}>{node.layer}</span>
          <h2>{node.display_name}</h2>
          <p>{node.full_name}</p>
        </div>

        <div className="metric-grid">
          <div>
            <Layers3 size={16} />
            <span>Mart</span>
            <strong>{node.mart}</strong>
          </div>
          <div>
            <GitBranch size={16} />
            <span>Wave</span>
            <strong>{node.wave ?? "n/a"}</strong>
          </div>
          <div>
            <Database size={16} />
            <span>Load</span>
            <strong>{node.load_method || "metadata"}</strong>
          </div>
        </div>

        <section className="lineage-columns">
          <div>
            <h3><span className="upstream-dot" /> Upstream</h3>
            <div className="edge-list upstream-list">
              {upstream.length ? upstream.map((edge) => <EdgeItem key={edge.id} node={nodeById.get(edge.source)} fallback={edge.source} />) : <p className="muted">None detected</p>}
            </div>
          </div>
          <div>
            <h3><span className="downstream-dot" /> Downstream</h3>
            <div className="edge-list downstream-list">
              {downstream.length ? downstream.map((edge) => <EdgeItem key={edge.id} node={nodeById.get(edge.target)} fallback={edge.target} />) : <p className="muted">None detected</p>}
            </div>
          </div>
        </section>

        <section>
          <h3><Code2 size={16} /> ETL SQL / Evidence</h3>
          {node.source_sql ? (
            <pre className="sql-block">{node.source_sql}</pre>
          ) : (
            <p className="muted">No SQL definition captured for this node.</p>
          )}
        </section>

        <section>
          <h3>Evidence</h3>
          <ul className="evidence-list">
            {(node.evidence ?? ["snapshot"]).map((item) => <li key={item}>{item}</li>)}
          </ul>
        </section>
      </div>
    </aside>
  );
}

function EdgeItem({ node, fallback }: { node?: LineageNode; fallback: string }) {
  return (
    <p className={`edge-item layer-${node?.layer.toLowerCase() ?? "unknown"}`}>
      <strong>{node?.display_name ?? fallback}</strong>
      {node && <span>{node.layer} · {node.wave == null ? "Wave n/a" : `Wave ${node.wave}`}</span>}
    </p>
  );
}
