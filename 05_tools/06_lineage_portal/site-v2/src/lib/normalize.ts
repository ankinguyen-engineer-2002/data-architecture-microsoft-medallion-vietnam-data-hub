import type { LineageEdge, LineageNode, Snapshot } from "./types";

const SEMANTIC_MODEL_TYPE = "SEMANTIC_MODEL";

/**
 * Collapse the semantic layer into a single canonical model node and
 * synthesize edges from every report-facing Gold table into it.
 *
 * Why: there is exactly ONE semantic model (`sc_control_tower`) no matter how
 * many marts exist. The scanner currently emits it as up to 5 disconnected
 * fragments (1 `SEMANTIC_MODEL` item + N `semantic_artifact` files) with zero
 * edges, because the CI service principal cannot read the model definition
 * (getDefinition 404). We normalize that into one node that always shows and
 * always connects to each mart's Gold serving outputs — so every mart view,
 * and the full view, terminates in the same single semantic model.
 */
export function normalizeSnapshot(raw: Snapshot): Snapshot {
  const artifactIds = new Set(
    raw.nodes
      .filter((n) => n.object_type.toLowerCase() === "semantic_artifact")
      .map((n) => n.id)
  );

  // 1. Pick the canonical model node (prefer the real SEMANTIC_MODEL item).
  const modelNode =
    raw.nodes.find((n) => n.object_type === SEMANTIC_MODEL_TYPE && !artifactIds.has(n.id)) ??
    raw.nodes.find((n) => n.layer === "Semantic" && !artifactIds.has(n.id));
  if (!modelNode) {
    return {
      ...raw,
      nodes: raw.nodes.filter((n) => !artifactIds.has(n.id)),
      edges: raw.edges.filter(
        (edge) => !artifactIds.has(edge.source) && !artifactIds.has(edge.target)
      ),
    };
  }

  const modelId = modelNode.id;

  // 2. Drop the artifact fragments; keep the single model node + everything else.
  const droppedIds = new Set([
    ...artifactIds,
    ...raw.nodes
      .filter((n) => n.layer === "Semantic" && n.id !== modelId)
      .map((n) => n.id),
  ]);

  const nodes = raw.nodes
    .filter((n) => !droppedIds.has(n.id))
    .map((n) =>
      n.id === modelId
        ? {
            ...n,
            role: "semantic",
            display_name: n.display_name || n.schema || "sc_control_tower",
          }
        : n
    );

  // 3. Rebuild edges: drop any edge touching a dropped fragment.
  const baseEdges = raw.edges.filter(
    (e) => !droppedIds.has(e.source) && !droppedIds.has(e.target)
  );

  // 4. Synthesize Gold -> semantic edges for every report-facing Gold table
  //    (terminal Gold nodes — those that don't feed another curated table).
  const outDeg = new Map<string, number>();
  for (const e of baseEdges) {
    outDeg.set(e.source, (outDeg.get(e.source) ?? 0) + 1);
  }

  const servingGold = nodes.filter(
    (n) => n.layer === "Gold" && (outDeg.get(n.id) ?? 0) === 0
  );

  const existing = new Set(baseEdges.map((e) => `${e.source}->${e.target}`));
  const synthEdges: LineageEdge[] = [];
  for (const g of servingGold) {
    const key = `${g.id}->${modelId}`;
    if (existing.has(key)) continue;
    synthEdges.push({
      id: `synthetic:${g.id}->${modelId}`,
      source: g.id,
      target: modelId,
      relationship_type: "feeds_semantic",
      confidence: "inferred",
      evidence:
        "Report-facing Gold table bound to the single sc_control_tower semantic model.",
    });
  }

  return { ...raw, nodes, edges: [...baseEdges, ...synthEdges] };
}

/** True when a node is the single canonical semantic model. */
export function isSemanticModel(node: LineageNode): boolean {
  return node.layer === "Semantic";
}
