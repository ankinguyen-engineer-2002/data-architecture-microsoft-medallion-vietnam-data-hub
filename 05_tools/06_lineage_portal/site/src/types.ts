export type LineageNode = {
  id: string;
  display_name: string;
  full_name: string;
  workspace: string;
  database: string;
  schema: string;
  object_name: string;
  object_type: string;
  layer: "Bronze" | "Silver" | "Gold" | "Semantic" | string;
  mart: string;
  wave: number | null;
  load_method: string;
  source_sql: string;
  row_count: number | null;
  last_modified: string;
  status: string;
  evidence?: string[];
};

export type LineageEdge = {
  id: string;
  source: string;
  target: string;
  relationship_type: string;
  confidence: string;
  evidence: string;
};

export type Snapshot = {
  generated_at_utc: string;
  workspace: { id: string; name: string };
  nodes: LineageNode[];
  edges: LineageEdge[];
  layers: Array<{ layer: string; node_count: number }>;
  marts: Array<{ mart: string; node_count: number }>;
  warnings: string[];
  scan_evidence: Record<string, unknown>;
};
