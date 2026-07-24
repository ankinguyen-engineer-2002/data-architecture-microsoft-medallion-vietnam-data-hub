import { MarkerType, Position, type Edge, type Node } from "@xyflow/react";
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
    animated: true,
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

export async function layoutGraph(nodes: LineageNode[], _edges: LineageEdge[]): Promise<Node[]> {
  const flowNodes = toFlowNodes(nodes);
  return architecturalLaneLayout(flowNodes);
}

function architecturalLaneLayout(flowNodes: Node[]): Node[] {
  const orderedNodes = flowNodes.slice().sort(compareNodes);
  const laneGroups = groupByLane(flowNodes);
  const laneIndex = new Map(laneGroups.map((lane, index) => [lane.key, index]));
  const laneRow = new Map<string, number>();

  return orderedNodes.map((node) => {
      const lineage = node.data.lineage as LineageNode;
      const laneKey = laneKeyFor(lineage);
      const row = laneRow.get(laneKey) ?? 0;
      laneRow.set(laneKey, row + 1);
      return {
        ...node,
        position: {
          x: 48 + (laneIndex.get(laneKey) ?? 0) * 450,
          y: 56 + row * 122
        },
        style: { width: widthFor(lineage), height: 92 }
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
        label: laneLabelFor(lineage),
        order: laneOrderFor(lineage),
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
    laneOrderFor(a) - laneOrderFor(b) ||
    (roleRank[a.role ?? "business"] ?? 9) - (roleRank[b.role ?? "business"] ?? 9) ||
    a.schema.localeCompare(b.schema) ||
    a.display_name.localeCompare(b.display_name)
  );
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

function widthFor(node: LineageNode): number {
  if (node.layer === "Semantic") return 330;
  if ((node.role ?? "") === "support") return 320;
  if (node.display_name.length > 34) return 380;
  return 330;
}
