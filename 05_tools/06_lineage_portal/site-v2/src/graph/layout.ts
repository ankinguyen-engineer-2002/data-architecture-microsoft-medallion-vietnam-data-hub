import { MarkerType, Position, type Edge, type Node } from "@xyflow/react";
import type { LineageEdge, LineageNode } from "@/lib/types";

export const NODE_WIDTH = 268;
const NODE_HEIGHT = 84;
const COL_GAP = 360; // horizontal distance between column left edges
const ROW_GAP = 104; // vertical distance between rows in a column
const TOP_PAD = 72;
const LEFT_PAD = 48;

/** One header per medallion band, spanning all of that band's columns. */
export type Lane = { key: string; label: string; layer: string; xStart: number; xEnd: number };

export type LayoutDiagnostics = {
  backwardEdges: number; // target column left of source column
  sameColumnEdges: number; // source & target share a column
  crossBandBackward: number; // e.g. Gold -> Silver (medallion violation)
  cycleNodes: string[]; // nodes trapped in an intra-band cycle
};

export type LayoutResult = { nodes: Node[]; lanes: Lane[]; diagnostics: LayoutDiagnostics };

/**
 * Medallion bands are the ONLY hard left→right constraint. Bronze < Silver <
 * Gold < Semantic. Within each band the horizontal column is derived from the
 * actual edge topology (longest-path layering), NOT from the scanner's static
 * `wave` number — so any dependency A→B always lands A left of B, and the
 * layout self-corrects for new marts / tables / waves without manual tuning.
 */
const BAND: Record<string, number> = { Bronze: 0, Silver: 1, Gold: 2, Semantic: 3 };
function bandOf(node: LineageNode): number {
  return BAND[node.layer] ?? 9;
}

export function laneLayout(nodes: LineageNode[], edges: LineageEdge[]): LayoutResult {
  const byId = new Map(nodes.map((n) => [n.id, n]));

  // 1. Sub-rank each node within its band by topological longest-path.
  const { subrank, cycleNodes } = computeSubranks(nodes, edges, byId);
  const colOf = (n: LineageNode) => bandOf(n) * 1000 + (subrank.get(n.id) ?? 0);

  // 2. Bucket nodes into columns.
  const colMap = new Map<number, LineageNode[]>();
  for (const n of nodes) {
    const c = colOf(n);
    (colMap.get(c) ?? colMap.set(c, []).get(c)!).push(n);
  }
  const colKeys = [...colMap.keys()].sort((a, b) => a - b);

  // 3. Order rows within columns: mart-grouped, then barycenter crossing-reduction.
  const rowOrder = orderRows(colKeys, colMap, edges, byId);

  // 4. Map each column to a screen x-position.
  const colX = new Map<number, number>();
  colKeys.forEach((c, i) => colX.set(c, LEFT_PAD + i * COL_GAP));

  const flowNodes: Node[] = [];
  for (const c of colKeys) {
    rowOrder.get(c)!.forEach((n, row) => {
      flowNodes.push({
        id: n.id,
        type: "lineageCard",
        position: { x: colX.get(c)!, y: TOP_PAD + row * ROW_GAP },
        sourcePosition: Position.Right,
        targetPosition: Position.Left,
        data: { lineage: n },
        width: NODE_WIDTH,
        height: NODE_HEIGHT,
      });
    });
  }

  // 5. One header per medallion band, spanning all its columns — so headers can
  // never overlap regardless of how many sub-rank columns a band expands into.
  const bandCols = new Map<string, number[]>();
  for (const c of colKeys) {
    const layer = colMap.get(c)![0].layer;
    (bandCols.get(layer) ?? bandCols.set(layer, []).get(layer)!).push(c);
  }
  const lanes: Lane[] = [...bandCols.entries()]
    .map(([layer, cols]) => {
      const xs = cols.map((c) => colX.get(c)!);
      return {
        key: layer,
        label: bandLabelFor(layer),
        layer,
        xStart: Math.min(...xs),
        xEnd: Math.max(...xs) + NODE_WIDTH,
      };
    })
    .sort((a, b) => a.xStart - b.xStart);

  const diagnostics = diagnose(edges, byId, colOf, cycleNodes);
  return { nodes: flowNodes, lanes, diagnostics };
}

export function toFlowEdges(edges: LineageEdge[], accentIds?: Set<string>): Edge[] {
  return edges.map((edge) => {
    const highlighted = accentIds ? accentIds.has(edge.id) : false;
    const isSemantic = edge.relationship_type === "feeds_semantic";
    const evidenceClass = edgeClass(edge, isSemantic);
    return {
      id: edge.id,
      source: edge.source,
      target: edge.target,
      type: "bezier",
      animated: highlighted,
      data: { edge },
      markerEnd: { type: MarkerType.ArrowClosed, width: 14, height: 14 },
      className: `${evidenceClass}${highlighted ? " edge-accent" : ""}`,
    };
  });
}

function edgeClass(edge: LineageEdge, isSemantic: boolean): string {
  if (edge.confidence === "inferred") return "edge-inferred";
  if (isSemantic) return "edge-semantic";
  if (edge.sync_status === "aligned") return "edge-aligned";
  if (edge.sync_status === "drift") {
    return edge.provenance === "repository_target"
      ? "edge-drift edge-repository"
      : "edge-drift edge-live";
  }
  if (edge.provenance === "repository_target") return "edge-repository";
  return "edge-live";
}

// ── topology ─────────────────────────────────────────────────

/**
 * Longest-path layering restricted to intra-band edges. Kahn's algorithm gives
 * the exact answer for a DAG; a bounded relaxation fallback keeps it terminating
 * and best-effort if the data ever contains an intra-band cycle.
 */
function computeSubranks(
  nodes: LineageNode[],
  edges: LineageEdge[],
  byId: Map<string, LineageNode>
): { subrank: Map<string, number>; cycleNodes: string[] } {
  const subrank = new Map<string, number>();
  const adj = new Map<string, string[]>();
  const indeg = new Map<string, number>();
  for (const n of nodes) {
    subrank.set(n.id, 0);
    adj.set(n.id, []);
    indeg.set(n.id, 0);
  }

  const intra: Array<[string, string]> = [];
  for (const e of edges) {
    const s = byId.get(e.source);
    const t = byId.get(e.target);
    if (!s || !t || s.id === t.id) continue;
    if (bandOf(s) === bandOf(t)) {
      adj.get(s.id)!.push(t.id);
      indeg.set(t.id, indeg.get(t.id)! + 1);
      intra.push([s.id, t.id]);
    }
  }

  const localIndeg = new Map(indeg);
  const queue = nodes.map((n) => n.id).filter((id) => localIndeg.get(id) === 0);
  let processed = 0;
  while (queue.length) {
    const u = queue.shift()!;
    processed++;
    for (const v of adj.get(u)!) {
      if (subrank.get(u)! + 1 > subrank.get(v)!) subrank.set(v, subrank.get(u)! + 1);
      localIndeg.set(v, localIndeg.get(v)! - 1);
      if (localIndeg.get(v) === 0) queue.push(v);
    }
  }

  const cycleNodes = nodes.map((n) => n.id).filter((id) => localIndeg.get(id)! > 0);
  if (cycleNodes.length > 0) {
    // Bounded relaxation so cyclic data never hangs and still trends forward.
    for (let pass = 0; pass < nodes.length; pass++) {
      let changed = false;
      for (const [u, v] of intra) {
        if (subrank.get(u)! + 1 > subrank.get(v)!) {
          subrank.set(v, subrank.get(u)! + 1);
          changed = true;
        }
      }
      if (!changed) break;
    }
  }
  return { subrank, cycleNodes };
}

/**
 * Barycenter heuristic: seed each column by (mart, schema, name), then sweep
 * left↔right ordering nodes by the average row of their neighbors in adjacent
 * columns. Reduces edge crossings without ever changing column assignment, so
 * left→right correctness is preserved.
 */
function orderRows(
  colKeys: number[],
  colMap: Map<number, LineageNode[]>,
  edges: LineageEdge[],
  byId: Map<string, LineageNode>
): Map<number, LineageNode[]> {
  const order = new Map<number, LineageNode[]>();
  for (const c of colKeys) order.set(c, colMap.get(c)!.slice().sort(rowCompare));

  const preds = new Map<string, string[]>();
  const succs = new Map<string, string[]>();
  for (const e of edges) {
    if (!byId.has(e.source) || !byId.has(e.target)) continue;
    (succs.get(e.source) ?? succs.set(e.source, []).get(e.source)!).push(e.target);
    (preds.get(e.target) ?? preds.set(e.target, []).get(e.target)!).push(e.source);
  }

  const buildIndex = () => {
    const idx = new Map<string, number>();
    for (const c of colKeys) order.get(c)!.forEach((n, i) => idx.set(n.id, i));
    return idx;
  };

  for (let sweep = 0; sweep < 4; sweep++) {
    const forward = sweep % 2 === 0;
    const keys = forward ? colKeys : [...colKeys].reverse();
    const idx = buildIndex();
    const neigh = forward ? preds : succs;
    for (const c of keys) {
      const arr = order.get(c)!;
      const bary = new Map<string, number>();
      arr.forEach((n, i) => {
        const rows = (neigh.get(n.id) ?? [])
          .map((id) => idx.get(id))
          .filter((v): v is number => v != null);
        bary.set(n.id, rows.length ? rows.reduce((a, b) => a + b, 0) / rows.length : i);
      });
      arr.sort((a, b) => bary.get(a.id)! - bary.get(b.id)! || rowCompare(a, b));
    }
  }
  return order;
}

function rowCompare(a: LineageNode, b: LineageNode): number {
  return (
    (a.mart ?? "").localeCompare(b.mart ?? "") ||
    a.schema.localeCompare(b.schema) ||
    a.display_name.localeCompare(b.display_name)
  );
}

// ── diagnostics ──────────────────────────────────────────────

function diagnose(
  edges: LineageEdge[],
  byId: Map<string, LineageNode>,
  colOf: (n: LineageNode) => number,
  cycleNodes: string[]
): LayoutDiagnostics {
  let backwardEdges = 0;
  let sameColumnEdges = 0;
  let crossBandBackward = 0;
  for (const e of edges) {
    const s = byId.get(e.source);
    const t = byId.get(e.target);
    if (!s || !t) continue;
    const cs = colOf(s);
    const ct = colOf(t);
    if (ct === cs) sameColumnEdges++;
    else if (ct < cs) backwardEdges++;
    if (bandOf(t) < bandOf(s)) crossBandBackward++;
  }
  return { backwardEdges, sameColumnEdges, crossBandBackward, cycleNodes };
}

// ── labels ───────────────────────────────────────────────────

/** One label per medallion band. */
function bandLabelFor(layer: string): string {
  switch (layer) {
    case "Bronze":
      return "Bronze · Source";
    case "Silver":
      return "Silver · Curated";
    case "Gold":
      return "Gold · Serving";
    case "Semantic":
      return "Semantic";
    default:
      return layer;
  }
}
