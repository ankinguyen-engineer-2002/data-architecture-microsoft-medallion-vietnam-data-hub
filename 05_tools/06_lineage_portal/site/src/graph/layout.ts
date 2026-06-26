import { MarkerType, Position, type Edge, type Node } from "@xyflow/react";
import ELK from "elkjs/lib/elk.bundled.js";
import type { LineageEdge, LineageNode } from "../types";

const elk = new ELK();

const roleRank: Record<string, number> = {
  business: 0,
  semantic: 1,
  support: 2,
  unclassified: 3
};

export function toFlowNodes(nodes: LineageNode[]): Node[] {
  return nodes.map((node) => ({
    id: node.id,
    type: "lineageTable",
    position: { x: 0, y: 0 },
    sourcePosition: Position.Right,
    targetPosition: Position.Left,
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
    type: "bezier",
    animated: edge.relationship_type === "semantic_binding",
    className: `lineage-edge rel-${edge.relationship_type}`,
    data: edge,
    markerEnd: {
      type: MarkerType.ArrowClosed,
      width: 18,
      height: 18
    },
    style: {
      strokeWidth: 2.4
    }
  }));
}

export async function layoutGraph(nodes: LineageNode[], edges: LineageEdge[]): Promise<Node[]> {
  const flowNodes = toFlowNodes(nodes);
  const orderedNodes = flowNodes.slice().sort(compareNodes);
  const nodeById = new Map(orderedNodes.map((node) => [node.id, node]));
  const elkGraph = {
    id: "lineage-root",
    layoutOptions: {
      "elk.algorithm": "layered",
      "elk.direction": "RIGHT",
      "elk.spacing.nodeNode": "42",
      "elk.layered.spacing.nodeNodeBetweenLayers": "88",
      "elk.layered.nodePlacement.strategy": "NETWORK_SIMPLEX",
      "elk.layered.crossingMinimization.strategy": "LAYER_SWEEP",
      "elk.edgeRouting": "SPLINES"
    },
    children: orderedNodes.map((node) => {
      const lineage = node.data.lineage as LineageNode;
      return {
        id: node.id,
        width: widthFor(lineage),
        height: 86
      };
    }),
    edges: edges
      .filter((edge) => nodeById.has(edge.source) && nodeById.has(edge.target))
      .map((edge) => ({
        id: edge.id,
        sources: [edge.source],
        targets: [edge.target]
      }))
  };

  try {
    const layout = await elk.layout(elkGraph);
    const positions = new Map((layout.children ?? []).map((child) => [child.id, { x: child.x ?? 0, y: child.y ?? 0 }]));
    return orderedNodes.map((node) => {
      const lineage = node.data.lineage as LineageNode;
      const position = positions.get(node.id) ?? { x: 0, y: 0 };
      return {
        ...node,
        position: { x: position.x + 36, y: position.y + 36 },
        style: { width: widthFor(lineage), height: 86 }
      };
    });
  } catch {
    return fallbackLaneLayout(orderedNodes);
  }
}

function fallbackLaneLayout(flowNodes: Node[]): Node[] {
  const laneGroups = groupByLane(flowNodes);
  const laneIndex = new Map(laneGroups.map((lane, index) => [lane.key, index]));
  const laneOffsets = new Map<string, number>();

  return flowNodes
    .map((node) => {
      const lineage = node.data.lineage as LineageNode;
      const laneKey = laneKeyFor(lineage);
      const x = 36 + (laneIndex.get(laneKey) ?? 0) * 430;
      const offset = laneOffsets.get(laneKey) ?? 0;
      const y = 36 + offset;
      laneOffsets.set(laneKey, offset + 108);
      return {
        ...node,
        position: { x, y },
        style: { width: widthFor(lineage), height: 86 }
      };
    });
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
  if (node.layer === "Semantic") return 300;
  if ((node.role ?? "") === "support") return 290;
  if (node.display_name.length > 34) return 340;
  return 300;
}
