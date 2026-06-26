import ELK from "elkjs/lib/elk.bundled.js";
import type { Edge, Node } from "@xyflow/react";
import type { LineageEdge, LineageNode } from "../types";

const elk = new ELK();

const layerRank: Record<string, number> = {
  Bronze: 0,
  Silver: 1,
  Gold: 2,
  Semantic: 3
};

export function toFlowNodes(nodes: LineageNode[]): Node[] {
  return nodes.map((node) => ({
    id: node.id,
    type: "default",
    position: { x: 0, y: 0 },
    data: {
      label: node.display_name,
      lineage: node
    },
    className: `lineage-node layer-${node.layer.toLowerCase()}`
  }));
}

export function toFlowEdges(edges: LineageEdge[]): Edge[] {
  return edges.map((edge) => ({
    id: edge.id,
    source: edge.source,
    target: edge.target,
    type: "smoothstep",
    animated: edge.relationship_type === "semantic_binding",
    label: edge.relationship_type.replaceAll("_", " "),
    className: `lineage-edge rel-${edge.relationship_type}`,
    data: edge
  }));
}

export async function layoutGraph(nodes: LineageNode[], edges: LineageEdge[]): Promise<Node[]> {
  const flowNodes = toFlowNodes(nodes);
  const graph = {
    id: "root",
    layoutOptions: {
      "elk.algorithm": "layered",
      "elk.direction": "RIGHT",
      "elk.spacing.nodeNode": "54",
      "elk.layered.spacing.nodeNodeBetweenLayers": "92",
      "elk.layered.nodePlacement.strategy": "NETWORK_SIMPLEX"
    },
    children: flowNodes.map((node) => {
      const lineage = node.data.lineage as LineageNode;
      return {
        id: node.id,
        width: widthFor(lineage),
        height: 72,
        layoutOptions: {
          "elk.layered.layering.layerConstraint": String(layerRank[lineage.layer] ?? 9)
        }
      };
    }),
    edges: edges.map((edge) => ({
      id: edge.id,
      sources: [edge.source],
      targets: [edge.target]
    }))
  };
  const result = await elk.layout(graph);
  const positions = new Map((result.children ?? []).map((child) => [child.id, child]));
  return flowNodes.map((node) => {
    const pos = positions.get(node.id);
    return {
      ...node,
      position: { x: pos?.x ?? 0, y: pos?.y ?? 0 },
      style: { width: pos?.width ?? widthFor(node.data.lineage as LineageNode), height: pos?.height ?? 72 }
    };
  });
}

function widthFor(node: LineageNode): number {
  if (node.layer === "Semantic") return 260;
  if (node.display_name.length > 34) return 280;
  return 236;
}
