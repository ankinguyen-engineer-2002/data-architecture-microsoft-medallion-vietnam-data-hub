import assert from "node:assert/strict";
import fs from "node:fs";
import { createServer } from "vite";

const server = await createServer({ server: { middlewareMode: true }, appType: "custom" });

try {
  const { fullView, martView } = await server.ssrLoadModule("/src/lib/view.ts");
  const { toFlowEdges } = await server.ssrLoadModule("/src/graph/layout.ts");
  const { normalizeSnapshot } = await server.ssrLoadModule("/src/lib/normalize.ts");

  const snapshot = normalizeSnapshot(
    JSON.parse(fs.readFileSync(new URL("../public/lineage_snapshot.json", import.meta.url), "utf8"))
  );
  const forecast = martView(snapshot, "forecast_accuracy", true);
  const inventory = martView(snapshot, "inventory_health", true);

  verifySemanticArtifactDefense(normalizeSnapshot);
  verifyInferredEdgesAreNotLive(normalizeSnapshot, toFlowEdges);
  verifySharedUpstreamDoesNotPullSiblingMart(martView);
  verifyMartHasDirectedClosure(snapshot, "forecast_accuracy", forecast);
  verifyMartHasDirectedClosure(snapshot, "inventory_health", inventory);
  verifyCatalogTaggedBronzeIsExcluded(martView);

  const full = fullView(snapshot, true);
  assert.ok(snapshot.nodes.length > 0, "snapshot must contain lineage nodes");
  assert.equal(full.nodes.length, snapshot.nodes.length, "Full view must preserve every node");
  assert.equal(full.edges.length, snapshot.edges.length, "Full view must preserve every verified edge");
  verifySemanticBindings(snapshot);

  assertEdge(
    forecast.edges,
    "SupplyChain_Processing_Warehouse.ReferenceMaster_Enh.ForecastHorizon",
    "SupplyChain_Gold_Warehouse.ForecastAccuracy_DW.DimForecastHorizon"
  );
  assertEdge(
    forecast.edges,
    "SupplyChain_Processing_Warehouse.ReferenceMaster_Enh.CustomerGrouping",
    "SupplyChain_Gold_Warehouse.ForecastAccuracy_DW.DimCustomerGrouping"
  );
  assertEdge(
    inventory.edges,
    "SupplyChain_Processing_Warehouse.ReferenceMaster_Enh.Vendor",
    "SupplyChain_Gold_Warehouse.InventoryHealth_DW.DimVendor"
  );
  assertEdge(
    inventory.edges,
    "SupplyChain_Gold_Warehouse.Shared_DW.DimProduct",
    "SupplyChain_Gold_Warehouse.InventoryHealth_DW.FactInventoryHealthSnapshot"
  );

  assert.equal(
    snapshot.nodes.some((node) => node.object_type.toLowerCase() === "semantic_artifact"),
    false,
    "semantic catalog files must not render as lineage objects"
  );

  console.log(
    `lineage view projections: PASS (Full ${full.nodes.length}/${full.edges.length}, ` +
      `Forecast ${forecast.nodes.length}/${forecast.edges.length}, ` +
      `Inventory ${inventory.nodes.length}/${inventory.edges.length})`
  );
} finally {
  await server.close();
}

function assertEdge(edges, source, target) {
  assert.ok(
    edges.some((edge) => edge.source === source && edge.target === target),
    `missing lineage edge: ${source} -> ${target}`
  );
}

function verifySemanticArtifactDefense(normalizeSnapshot) {
  const clean = normalizeSnapshot({
    generated_at_utc: "",
    workspace: { id: "", name: "" },
    layers: [],
    marts: [],
    warnings: [],
    scan_evidence: {},
    nodes: [
      node("Warehouse.Schema.Table", "Silver", "shared"),
      { ...node("Catalog.Semantic.README", "Bronze", "inventory_health"), object_type: "semantic_artifact" },
    ],
    edges: [edge("Catalog.Semantic.README", "Warehouse.Schema.Table")],
  });

  assert.deepEqual(
    clean.nodes.map((item) => item.id),
    ["Warehouse.Schema.Table"],
    "semantic artifacts must be removed even when the semantic model is unavailable"
  );
  assert.equal(clean.edges.length, 0, "edges touching semantic artifacts must also be removed");
}

function verifyInferredEdgesAreNotLive(normalizeSnapshot, toFlowEdges) {
  const raw = {
    generated_at_utc: "",
    workspace: { id: "", name: "" },
    layers: [],
    marts: [],
    warnings: [],
    scan_evidence: {},
    nodes: [
      node("Warehouse.Gold.Output", "Gold", "forecast_accuracy"),
      node("SemanticModel.sc_control_tower.Model", "Semantic", "shared", "semantic"),
    ],
    edges: [{ ...edge("Warehouse.Gold.Output", "SemanticModel.sc_control_tower.Model", "feeds_semantic"), confidence: "inferred" }],
  };
  const normalized = normalizeSnapshot(raw);
  assert.equal(normalized.edges.length, 0, "normalization must reject unverified semantic bindings");
  const flow = toFlowEdges([
    { ...edge("Warehouse.Gold.Output", "SemanticModel.sc_control_tower.Model", "feeds_semantic"), confidence: "inferred" },
  ]);
  assert.ok(flow[0].className?.includes("edge-inferred"), "inferred edge must never use Live styling");
}

function verifyMartHasDirectedClosure(snapshot, mart, view) {
  const ids = new Set(view.nodes.map((node) => node.id));
  const outputs = new Set(
    view.nodes
      .filter((node) => node.mart === mart && (node.layer === "Silver" || node.layer === "Gold"))
      .map((node) => node.id)
  );
  const forward = new Map();
  const degree = new Map(view.nodes.map((node) => [node.id, 0]));
  for (const edge of view.edges) {
    (forward.get(edge.source) ?? forward.set(edge.source, []).get(edge.source)).push(edge.target);
    degree.set(edge.source, (degree.get(edge.source) ?? 0) + 1);
    degree.set(edge.target, (degree.get(edge.target) ?? 0) + 1);
  }
  assert.ok(outputs.size > 0, `${mart} must retain curated outputs`);
  for (const node of view.nodes) {
    assert.ok((degree.get(node.id) ?? 0) > 0, `${mart} contains isolated node: ${node.id}`);
    if (node.layer === "Semantic") continue;
    assert.ok(
      outputs.has(node.id) || reachesAny(node.id, forward, outputs),
      `${mart} contains node without a directed path to a selected curated output: ${node.id}`
    );
    if (node.layer === "Bronze") {
      assert.ok(
        reachesAny(node.id, forward, outputs),
        `${mart} contains disconnected Bronze node: ${node.id}`
      );
    }
  }
}

function reachesAny(start, forward, targets) {
  const queue = [start];
  const visited = new Set([start]);
  while (queue.length) {
    const current = queue.shift();
    if (targets.has(current)) return true;
    for (const next of forward.get(current) ?? []) {
      if (!visited.has(next)) {
        visited.add(next);
        queue.push(next);
      }
    }
  }
  return false;
}

function verifyCatalogTaggedBronzeIsExcluded(martView) {
  const disconnected = "Bronze.CatalogOnly.Unrelated";
  const source = "Bronze.Real.Input";
  const silver = "Silver.Forecast.Transform";
  const gold = "Gold.Forecast.Output";
  const snapshot = {
    generated_at_utc: "",
    workspace: { id: "", name: "" },
    layers: [],
    marts: [],
    warnings: [],
    scan_evidence: {},
    nodes: [
      node(disconnected, "Bronze", "forecast_accuracy"),
      node(source, "Bronze", "shared"),
      node(silver, "Silver", "forecast_accuracy"),
      node(gold, "Gold", "forecast_accuracy"),
    ],
    edges: [edge(source, silver), edge(silver, gold)],
  };
  const result = martView(snapshot, "forecast_accuracy", true);
  const ids = new Set(result.nodes.map((node) => node.id));
  assert.ok(ids.has(source), "Bronze source with a real path must be retained");
  assert.equal(ids.has(disconnected), false, "catalog-tagged disconnected Bronze must be excluded");
  verifyMartHasDirectedClosure(snapshot, "forecast_accuracy", result);
}

function verifySemanticBindings(snapshot) {
  const nodesById = new Map(snapshot.nodes.map((node) => [node.id, node]));
  const bindings = snapshot.edges.filter((edge) => edge.relationship_type === "feeds_semantic");
  const expected = snapshot.semantic_validation?.binding_count;
  assert.ok(Number.isInteger(expected) && expected > 0, "semantic binding count must be declared");
  assert.equal(
    bindings.length,
    expected,
    "verified semantic edges must match the scanner's complete TMDL binding count"
  );
  for (const binding of bindings) {
    assert.equal(binding.confidence, "verified", `semantic binding must be verified: ${binding.id}`);
    assert.equal(nodesById.get(binding.source)?.layer, "Gold", `semantic source must be Gold: ${binding.id}`);
    assert.equal(nodesById.get(binding.target)?.layer, "Semantic", `semantic target must be Semantic: ${binding.id}`);
  }
}

function verifySharedUpstreamDoesNotPullSiblingMart(martView) {
  const shared = "Warehouse.Reference.Shared";
  const forecast = "Warehouse.Forecast.Fact";
  const inventory = "Warehouse.Inventory.Fact";
  const semantic = "SemanticModel.sc_control_tower.Model";
  const snapshot = {
    generated_at_utc: "",
    workspace: { id: "", name: "" },
    layers: [],
    marts: [],
    warnings: [],
    scan_evidence: {},
    nodes: [
      node("Source.Raw.Input", "Bronze", "inventory_health"),
      node(shared, "Silver", "shared"),
      node(forecast, "Gold", "forecast_accuracy"),
      node(inventory, "Gold", "inventory_health"),
      node(semantic, "Semantic", "shared", "semantic"),
    ],
    edges: [
      edge("Source.Raw.Input", shared),
      edge(shared, forecast),
      edge(shared, inventory),
      edge(forecast, semantic, "feeds_semantic"),
      edge(inventory, semantic, "feeds_semantic"),
    ],
  };

  const result = martView(snapshot, "forecast_accuracy", true);
  const ids = new Set(result.nodes.map((item) => item.id));
  assert.ok(ids.has("Source.Raw.Input"), "mart view must retain cross-owned upstream sources");
  assert.ok(ids.has(shared), "mart view must retain shared upstream tables");
  assert.ok(ids.has(semantic), "mart view must retain its connected semantic endpoint");
  assert.equal(ids.has(inventory), false, "shared upstream must not pull a sibling mart consumer");
}

function node(id, layer, mart, role = "business") {
  const parts = id.split(".");
  return {
    id,
    display_name: parts.at(-1),
    full_name: id,
    workspace: "",
    database: parts[0],
    schema: parts.at(-2) ?? "",
    object_name: parts.at(-1),
    object_type: layer === "Semantic" ? "SEMANTIC_MODEL" : "TABLE",
    layer,
    mart,
    wave: null,
    load_method: "",
    source_sql: "",
    row_count: null,
    last_modified: "",
    status: "active",
    role,
  };
}

function edge(source, target, relationship_type = "transforms_to") {
  return {
    id: `${source}->${target}`,
    source,
    target,
    relationship_type,
    confidence: "verified",
    evidence: "test",
  };
}
