import type { LineageEdge, LineageNode, Snapshot } from "./types";

export type ViewMode = "focus" | "mart" | "full";

export type ViewResult = {
  nodes: LineageNode[];
  edges: LineageEdge[];
};

// Support / plumbing roles that clutter business lineage: ETL loader work views
// (`Staging_Wrk.v_*`), seed→reference duplicates, unclassified helpers. Hidden by
// default; edges are collapsed THROUGH them so the business path stays connected.
const SUPPORT_ROLES = new Set(["support", "unclassified"]);

function isSupport(node: LineageNode): boolean {
  return SUPPORT_ROLES.has(node.role ?? "business");
}

/**
 * Remove support/plumbing nodes and collapse edges through them, so a hidden
 * work view like `COMAST → v_Comast → OpenOrderLineLevel` reads as the direct
 * business edge `COMAST → OpenOrderLineLevel`. The single semantic model is
 * never treated as support. Ported from the original portal's behavior.
 */
function hideSupport(result: ViewResult, showSupport: boolean): ViewResult {
  if (showSupport) return result;
  const visible = result.nodes.filter((n) => !isSupport(n));
  const visibleIds = new Set(visible.map((n) => n.id));
  const edges = collapseThroughHidden(result.edges, visibleIds);
  return { nodes: visible, edges };
}

/** Full graph — business nodes only by default; support/plumbing collapsed away. */
export function fullView(snapshot: Snapshot, showSupport: boolean): ViewResult {
  const ids = new Set(snapshot.nodes.map((n) => n.id));
  const edges = snapshot.edges.filter((e) => ids.has(e.source) && ids.has(e.target));
  return hideSupport({ nodes: snapshot.nodes, edges }, showSupport);
}

/** Everything up/downstream from a single mart's assets; support collapsed by default. */
export function martView(snapshot: Snapshot, mart: string, showSupport: boolean): ViewResult {
  const included = lineageClosure(snapshot, mart);
  const nodes = snapshot.nodes.filter((n) => included.has(n.id));
  const ids = new Set(nodes.map((n) => n.id));
  const edges = snapshot.edges.filter((e) => ids.has(e.source) && ids.has(e.target));
  return hideSupport({ nodes, edges }, showSupport);
}

/** Focus neighborhood — BFS both directions from a node up to `hops`; support collapsed. */
export function focusView(
  snapshot: Snapshot,
  focusId: string,
  hops: number,
  showSupport: boolean
): ViewResult {
  const forward = new Map<string, LineageEdge[]>();
  const backward = new Map<string, LineageEdge[]>();
  for (const edge of snapshot.edges) {
    forward.set(edge.source, [...(forward.get(edge.source) ?? []), edge]);
    backward.set(edge.target, [...(backward.get(edge.target) ?? []), edge]);
  }
  const upstream = new Set<string>();
  const downstream = new Set<string>();
  const upstreamEdges = new Set<string>();
  const downstreamEdges = new Set<string>();
  walk(focusId, backward, "source", hops, upstream, upstreamEdges);
  walk(focusId, forward, "target", hops, downstream, downstreamEdges);

  const idSet = new Set<string>([focusId, ...upstream, ...downstream]);
  const edgeSet = new Set<string>([...upstreamEdges, ...downstreamEdges]);
  const nodes = snapshot.nodes.filter((n) => idSet.has(n.id));
  const edges = snapshot.edges.filter((e) => edgeSet.has(e.id));
  // Keep the focused node itself even if it happens to be a support node.
  return hideSupportKeeping({ nodes, edges }, showSupport, focusId);
}

/** Like hideSupport but never drops `keepId` (the user's focus target). */
function hideSupportKeeping(result: ViewResult, showSupport: boolean, keepId: string): ViewResult {
  if (showSupport) return result;
  const visible = result.nodes.filter((n) => !isSupport(n) || n.id === keepId);
  const visibleIds = new Set(visible.map((n) => n.id));
  const edges = collapseThroughHidden(result.edges, visibleIds);
  return { nodes: visible, edges };
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

/**
 * Rebuild edges so hidden nodes are bypassed: for each edge whose source is
 * visible, connect it to the nearest visible downstream node(s), tunneling
 * through any hidden support nodes in between. De-dupes collapsed edges.
 */
function collapseThroughHidden(edges: LineageEdge[], visibleIds: Set<string>): LineageEdge[] {
  const outgoing = new Map<string, LineageEdge[]>();
  for (const edge of edges) {
    outgoing.set(edge.source, [...(outgoing.get(edge.source) ?? []), edge]);
  }
  const result = new Map<string, LineageEdge>();
  for (const edge of edges) {
    if (!visibleIds.has(edge.source)) continue;
    if (visibleIds.has(edge.target)) {
      result.set(
        `${edge.source}|${edge.target}|${edge.relationship_type}|${edge.provenance ?? "live"}`,
        edge
      );
      continue;
    }
    for (const target of downstreamVisibleTargets(edge.target, outgoing, visibleIds)) {
      if (target === edge.source) continue;
      const relationship =
        target.startsWith("SemanticModel.") || edge.relationship_type === "feeds_semantic"
          ? "feeds_semantic"
          : "transforms_to";
      const id = `collapse:${edge.source}->${target}:${relationship}`;
      result.set(`${edge.source}|${target}|${relationship}|${edge.provenance ?? "live"}`, {
        ...edge,
        id,
        source: edge.source,
        target,
        relationship_type: relationship,
        evidence: `Collapsed plumbing path through ${edge.target}`,
      });
    }
  }
  return [...result.values()];
}

function downstreamVisibleTargets(
  start: string,
  outgoing: Map<string, LineageEdge[]>,
  visibleIds: Set<string>
): string[] {
  const targets: string[] = [];
  const queue = [start];
  const visited = new Set<string>();
  while (queue.length > 0) {
    const nodeId = queue.shift();
    if (!nodeId || visited.has(nodeId)) continue;
    visited.add(nodeId);
    if (visibleIds.has(nodeId)) {
      targets.push(nodeId);
      continue;
    }
    for (const edge of outgoing.get(nodeId) ?? []) {
      if (!visited.has(edge.target)) queue.push(edge.target);
    }
  }
  return targets;
}

/**
 * A mart plus its complete upstream lineage and connected semantic endpoint.
 *
 * Mart ownership is intentionally not used as an upstream traversal filter:
 * shared reference tables and sources can legitimately feed more than one mart.
 * Traversing upstream only prevents a shared node from pulling sibling mart
 * consumers into the selected mart view.
 */
function lineageClosure(snapshot: Snapshot, mart: string): Set<string> {
  const included = new Set<string>();
  const nodeById = new Map(snapshot.nodes.map((node) => [node.id, node]));
  const forward = new Map<string, LineageEdge[]>();
  const backward = new Map<string, LineageEdge[]>();
  for (const edge of snapshot.edges) {
    forward.set(edge.source, [...(forward.get(edge.source) ?? []), edge]);
    backward.set(edge.target, [...(backward.get(edge.target) ?? []), edge]);
  }

  const upstreamQueue = snapshot.nodes
    .filter((node) => node.mart === mart && node.layer !== "Semantic")
    .map((node) => node.id);
  for (const nodeId of upstreamQueue) included.add(nodeId);

  while (upstreamQueue.length > 0) {
    const nodeId = upstreamQueue.shift();
    if (!nodeId) continue;
    for (const edge of backward.get(nodeId) ?? []) {
      if (!nodeById.has(edge.source) || included.has(edge.source)) continue;
      included.add(edge.source);
      upstreamQueue.push(edge.source);
    }
  }

  // Downstream expansion is restricted to Semantic so shared upstream nodes do
  // not pull consumers from sibling marts into this projection.
  const semanticQueue = [...included];
  while (semanticQueue.length > 0) {
    const nodeId = semanticQueue.shift();
    if (!nodeId) continue;
    for (const edge of forward.get(nodeId) ?? []) {
      const target = nodeById.get(edge.target);
      if (target?.layer !== "Semantic" || included.has(edge.target)) continue;
      included.add(edge.target);
      semanticQueue.push(edge.target);
    }
  }

  return included;
}
