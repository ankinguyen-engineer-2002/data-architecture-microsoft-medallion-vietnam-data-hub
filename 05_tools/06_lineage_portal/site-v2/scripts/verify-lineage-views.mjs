import assert from "node:assert/strict";
import fs from "node:fs";
import { createServer } from "vite";

const server = await createServer({ server: { middlewareMode: true }, appType: "custom" });

try {
  const { martView } = await server.ssrLoadModule("/src/lib/view.ts");
  const { normalizeSnapshot } = await server.ssrLoadModule("/src/lib/normalize.ts");

  const snapshot = normalizeSnapshot(
    JSON.parse(fs.readFileSync(new URL("../public/lineage_snapshot.json", import.meta.url), "utf8"))
  );
  const forecast = martView(snapshot, "forecast_accuracy", true);
  const inventory = martView(snapshot, "inventory_health", true);

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

  verifySemanticArtifactDefense(normalizeSnapshot);
  verifySharedUpstreamDoesNotPullSiblingMart(martView);
  console.log("lineage view projections: PASS");
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
