import { Handle, Position, type NodeProps } from "@xyflow/react";
import { motion } from "motion/react";
import { Box, Database, GitBranch } from "lucide-react";
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
    <motion.div
      initial={{ opacity: 0, scale: 0.92 }}
      animate={{ opacity: 1, scale: 1 }}
      transition={{ duration: 0.25, ease: [0.25, 0.1, 0.25, 1] }}
      className={`table-node ${selected ? "is-selected" : ""} layer-${lineage.layer.toLowerCase()} role-${role.toLowerCase()}`}
      title={`${lineage.display_name} · ${lineage.layer}${lineage.wave != null ? ` · Wave ${lineage.wave}` : ""} · ${lineage.schema || lineage.database}`}
    >
      <Handle className="table-handle" type="target" position={Position.Left} />
      <div className="node-topline">
        <span className={`node-layer layer-${lineage.layer.toLowerCase()}`}>
          {layerShort[lineage.layer] ?? lineage.layer.slice(0, 2).toUpperCase()}
          <em>{lineage.layer}</em>
        </span>
        <span className="node-schema">{lineage.schema || lineage.database}</span>
      </div>
      <div className="node-title-row">
        {lineage.layer === "Semantic" ? <Box size={17} /> : <Database size={17} />}
        <strong>{lineage.display_name}</strong>
      </div>
      <div className="node-meta">
        <span className="node-wave"><GitBranch size={13} /> {lineage.wave == null ? "Wave n/a" : `Wave ${lineage.wave}`}</span>
        {rowCount && <span>{rowCount} rows</span>}
      </div>
      <Handle className="table-handle" type="source" position={Position.Right} />
    </motion.div>
  );
}

function compactNumber(value: number): string {
  return new Intl.NumberFormat("en", {
    notation: "compact",
    maximumFractionDigits: 1
  }).format(value);
}
