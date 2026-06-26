import type { Edge, Node } from "@xyflow/react";
import type { LineageEdge, LineageNode } from "../types";

const roleRank: Record<string, number> = {
  business: 0,
  semantic: 1,
  support: 2,
  unclassified: 3
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
    className: `lineage-node layer-${node.layer.toLowerCase()} role-${(node.role ?? "business").toLowerCase()}`
  }));
}

export function toFlowEdges(edges: LineageEdge[]): Edge[] {
  return edges.map((edge) => ({
    id: edge.id,
    source: edge.source,
    target: edge.target,
    type: "smoothstep",
    animated: edge.relationship_type === "semantic_binding",
    label: compactEdgeLabel(edge.relationship_type),
    className: `lineage-edge rel-${edge.relationship_type}`,
    data: edge
  }));
}

export async function layoutGraph(nodes: LineageNode[], _edges: LineageEdge[]): Promise<Node[]> {
  const flowNodes = toFlowNodes(nodes);
  const laneGroups = groupByLane(flowNodes);
  const laneIndex = new Map(laneGroups.map((lane, index) => [lane.key, index]));
  const laneOffsets = new Map<string, number>();

  return flowNodes
    .slice()
    .sort(compareNodes)
    .map((node) => {
      const lineage = node.data.lineage as LineageNode;
      const laneKey = laneKeyFor(lineage);
      const x = (laneIndex.get(laneKey) ?? 0) * 330;
      const y = laneOffsets.get(laneKey) ?? 0;
      laneOffsets.set(laneKey, y + 112);
      return {
        ...node,
        position: { x, y },
        style: { width: widthFor(lineage), height: 72 }
      };
    });
}

export function graphLanes(nodes: LineageNode[]): Array<{ key: string; label: string; x: number; count: number }> {
  return groupByLane(toFlowNodes(nodes)).map((lane, index) => ({
    key: lane.key,
    label: lane.label,
    x: index * 330,
    count: lane.nodes.length
  }));
}

function groupByLane(nodes: Node[]): Array<{ key: string; label: string; order: number; nodes: Node[] }> {
  const groups = new Map<string, { key: string; label: string; order: number; nodes: Node[] }>();
  for (const node of nodes) {
    const lineage = node.data.lineage as LineageNode;
    const key = laneKeyFor(lineage);
    if (!groups.has(key)) {
      groups.set(key, {
        key,
        label: lineage.lane_label ?? lineage.layer,
        order: lineage.lane_order ?? 900,
        nodes: []
      });
    }
    groups.get(key)?.nodes.push(node);
  }
  return [...groups.values()].sort((left, right) => left.order - right.order || left.label.localeCompare(right.label));
}

function compareNodes(left: Node, right: Node): number {
  const a = left.data.lineage as LineageNode;
  const b = right.data.lineage as LineageNode;
  return (
    (a.lane_order ?? 900) - (b.lane_order ?? 900) ||
    (roleRank[a.role ?? "business"] ?? 9) - (roleRank[b.role ?? "business"] ?? 9) ||
    (a.wave ?? 99) - (b.wave ?? 99) ||
    a.schema.localeCompare(b.schema) ||
    a.display_name.localeCompare(b.display_name)
  );
}

function laneKeyFor(node: LineageNode): string {
  return `${node.lane_order ?? 900}:${node.lane_label ?? node.layer}`;
}

function widthFor(node: LineageNode): number {
  if (node.layer === "Semantic") return 250;
  if ((node.role ?? "") === "support") return 230;
  if (node.display_name.length > 34) return 278;
  return 248;
}

function compactEdgeLabel(raw: string): string {
  if (raw === "transforms_to") return "transform";
  if (raw === "semantic_binding") return "binds";
  if (raw === "belongs_to_model") return "";
  return raw.replaceAll("_", " ");
}
