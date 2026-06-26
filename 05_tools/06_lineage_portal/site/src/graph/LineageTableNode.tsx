import { Handle, Position, type NodeProps } from "@xyflow/react";
import { Box, Database, Layers3 } from "lucide-react";
import type { LineageNode } from "../types";

const layerShort: Record<string, string> = {
  Bronze: "BZ",
  Silver: "SL",
  Gold: "GD",
  Semantic: "SM"
};

export function LineageTableNode({ data, selected }: NodeProps) {
  const lineage = data.lineage as LineageNode;
  const role = lineage.role ?? "business";
  const rowCount = lineage.row_count == null ? null : compactNumber(lineage.row_count);

  return (
    <div className={`table-node ${selected ? "is-selected" : ""} layer-${lineage.layer.toLowerCase()} role-${role.toLowerCase()}`}>
      <Handle className="table-handle" type="target" position={Position.Left} />
      <div className="node-topline">
        <span className="node-layer">{layerShort[lineage.layer] ?? lineage.layer.slice(0, 2).toUpperCase()}</span>
        <span className="node-schema">{lineage.schema || lineage.database}</span>
      </div>
      <div className="node-title-row">
        {lineage.layer === "Semantic" ? <Box size={17} /> : <Database size={17} />}
        <strong>{lineage.display_name}</strong>
      </div>
      <div className="node-meta">
        <span><Layers3 size={13} /> {lineage.wave == null ? "wave n/a" : `wave ${lineage.wave}`}</span>
        {rowCount && <span>{rowCount} rows</span>}
      </div>
      <Handle className="table-handle" type="source" position={Position.Right} />
    </div>
  );
}

function compactNumber(value: number): string {
  return new Intl.NumberFormat("en", {
    notation: "compact",
    maximumFractionDigits: 1
  }).format(value);
}
