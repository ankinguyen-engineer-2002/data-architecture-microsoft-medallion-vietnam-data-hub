import type { LineageNode, Snapshot } from "./types";

const SEMANTIC_MODEL_TYPE = "SEMANTIC_MODEL";

/**
 * Collapse the semantic layer into a single canonical model node while
 * preserving only semantic bindings present in the scanned snapshot.
 *
 * Why: there is exactly ONE semantic model (`sc_control_tower`) no matter how
 * many marts exist. The scanner currently emits it as up to 5 disconnected
 * fragments (1 `SEMANTIC_MODEL` item + N `semantic_artifact` files). Catalog
 * fragments are not lineage objects, but absence of a readable model definition
 * is not evidence that every Gold table belongs to the model. Do not infer edges.
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

  // 3. Preserve only declared edges, dropping any that touch removed fragments.
  // A semantic edge has its own truth contract: without verified model evidence,
  // it must not enter the graph as an apparent model binding.
  const edges = raw.edges.filter(
    (e) =>
      !droppedIds.has(e.source) &&
      !droppedIds.has(e.target) &&
      (e.relationship_type !== "feeds_semantic" || e.confidence === "verified")
  );

  return { ...raw, nodes, edges };
}

/** True when a node is the single canonical semantic model. */
export function isSemanticModel(node: LineageNode): boolean {
  return node.layer === "Semantic";
}
