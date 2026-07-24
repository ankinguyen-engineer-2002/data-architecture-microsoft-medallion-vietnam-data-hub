import type { LineageEdge, LineageNode, Snapshot } from "./types";

/** Nodes with in-degree 0 that live in Gold or Semantic — canonical serving entrypoints. */
export function pickEntrypoints(snapshot: Snapshot, limit = 8): LineageNode[] {
  const inDeg = new Map<string, number>();
  const outDeg = new Map<string, number>();
  for (const edge of snapshot.edges) {
    inDeg.set(edge.target, (inDeg.get(edge.target) ?? 0) + 1);
    outDeg.set(edge.source, (outDeg.get(edge.source) ?? 0) + 1);
  }
  const scored = snapshot.nodes
    .filter((n) => n.layer === "Gold" || n.layer === "Semantic")
    .map((n) => ({
      node: n,
      fanIn: inDeg.get(n.id) ?? 0,
      fanOut: outDeg.get(n.id) ?? 0,
    }))
    // Serving assets with heavy upstream fan-in are the useful "start here" list
    .sort((a, b) => b.fanIn - a.fanIn || b.fanOut - a.fanOut);

  return scored.slice(0, limit).map((s) => s.node);
}

export type Neighborhood = {
  selected: string;
  nodes: Set<string>;
  upstream: Set<string>;
  downstream: Set<string>;
  edges: Set<string>;
  upstreamEdges: Set<string>;
  downstreamEdges: Set<string>;
};

/** BFS both directions from `startId`, respecting `hops`. */
export function neighborhood(
  startId: string,
  edges: LineageEdge[],
  hops = 2
): Neighborhood {
  const forward = new Map<string, LineageEdge[]>();
  const backward = new Map<string, LineageEdge[]>();
  for (const edge of edges) {
    forward.set(edge.source, [...(forward.get(edge.source) ?? []), edge]);
    backward.set(edge.target, [...(backward.get(edge.target) ?? []), edge]);
  }
  const upstream = new Set<string>();
  const downstream = new Set<string>();
  const upstreamEdges = new Set<string>();
  const downstreamEdges = new Set<string>();
  walk(startId, backward, "source", hops, upstream, upstreamEdges);
  walk(startId, forward, "target", hops, downstream, downstreamEdges);

  const nodes = new Set<string>([startId, ...upstream, ...downstream]);
  return {
    selected: startId,
    nodes,
    upstream,
    downstream,
    edges: new Set([...upstreamEdges, ...downstreamEdges]),
    upstreamEdges,
    downstreamEdges,
  };
}

function walk(
  startId: string,
  graph: Map<string, LineageEdge[]>,
  nextKey: "source" | "target",
  hops: number,
  nodeAcc: Set<string>,
  edgeAcc: Set<string>
): void {
  const queue: Array<[string, number]> = [[startId, 0]];
  const visited = new Set<string>([startId]);
  while (queue.length > 0) {
    const [nodeId, depth] = queue.shift()!;
    if (depth >= hops) continue;
    for (const edge of graph.get(nodeId) ?? []) {
      const next = edge[nextKey];
      edgeAcc.add(edge.id);
      nodeAcc.add(next);
      if (!visited.has(next)) {
        visited.add(next);
        queue.push([next, depth + 1]);
      }
    }
  }
}

/** Score nodes for global search — display name > full name > schema. */
export function searchNodes(nodes: LineageNode[], query: string, limit = 40): LineageNode[] {
  const needle = query.trim().toLowerCase();
  if (!needle) return [];
  const scored: Array<{ node: LineageNode; score: number }> = [];
  for (const node of nodes) {
    const name = node.display_name.toLowerCase();
    const full = node.full_name.toLowerCase();
    let score = 0;
    if (name === needle) score = 100;
    else if (name.startsWith(needle)) score = 80;
    else if (name.includes(needle)) score = 60;
    else if (full.includes(needle)) score = 40;
    else if (node.schema.toLowerCase().includes(needle)) score = 20;
    if (score > 0) scored.push({ node, score });
  }
  scored.sort((a, b) => b.score - a.score);
  return scored.slice(0, limit).map((s) => s.node);
}
