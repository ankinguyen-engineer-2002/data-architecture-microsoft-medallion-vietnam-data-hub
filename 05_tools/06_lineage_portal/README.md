# GitHub Pages Lineage Portal

Builds a static lineage portal for the current `Enterprise SupplyChain-Dev` Enterprise ETL runtime.

The operating pattern is:

```text
GitHub Actions -> live Fabric/SQL scanner + EDW target manifest -> lineage_snapshot.json -> Vite/React build -> GitHub Pages
```

The browser app never receives Fabric, SQL, Power BI, or OpenAI credentials.

## Folders

| Folder | Purpose |
|---|---|
| `scanner/` | Python scanner and snapshot builder. |
| `site-v2/` | Static Vite/React GitHub Pages app. |
| `tests/` | Fixture-based scanner tests. |
| `repository_lineage_manifest.json` | Generated target lineage from the exact `data-edw-fabric` commit/PR under review. |
| `live_lineage_baseline.json` | Timestamped read-only fallback used only when the scheduled identity cannot read current SQL dependency metadata. |

## Required GitHub Secrets For Live Scan

Manual preview runs can use `scan_mode=fixture` without Fabric credentials.
Scheduled runs and manual `scan_mode=live` runs need credentials.

| Secret | Purpose |
|---|---|
| `FABRIC_TENANT_ID` | Entra tenant id. |
| `FABRIC_CLIENT_ID` | App registration client id. |
| `FABRIC_CLIENT_SECRET` | Rotated app registration secret. |
| `FABRIC_WORKSPACE_ID` | `Enterprise SupplyChain-Dev` workspace id. |
| `FABRIC_WORKSPACE_NAME` | Display name for snapshot metadata. |
| `FABRIC_SQL_SERVER` | Fabric SQL endpoint host. |
| `FABRIC_SEMANTIC_MODEL_ID` | `sc_control_tower` semantic model id. |
| `FABRIC_SEMANTIC_MODEL_NAME` | Usually `sc_control_tower`. |

The workflow also accepts the older repo secret names as fallbacks:
`AZURE_TENANT_ID`, `AZURE_CLIENT_ID`, `AZURE_CLIENT_SECRET`, and `FABRIC_SERVER`.

Optional future enrichment secrets:

| Secret | Purpose |
|---|---|
| `AZURE_OPENAI_ENDPOINT` | Azure OpenAI endpoint for enrichment jobs only. |
| `AZURE_OPENAI_API_KEY` | Azure OpenAI key, never exposed to browser. |
| `AZURE_OPENAI_DEPLOYMENT` | Deployment name. |

## Local Fixture Verification

This does not connect to Fabric:

```bash
cd 05_tools/06_lineage_portal
PYTHONPATH=. python3 -m scanner.cli \
  --fixture tests/fixtures/minimal_live_input.json \
  --out site-v2/public/lineage_snapshot.json

PYTHONPATH=. python3 -m unittest discover -s tests -v

cd site-v2
npm ci
npm run test:views
npm run typecheck
npm run build
```

## Live Scan

Live scan should normally run through `.github/workflows/lineage-portal.yml`.

For a local read-only smoke test, export the same variables as GitHub secrets and run:

```bash
cd 05_tools/06_lineage_portal
PYTHONPATH=. python3 -m scanner.cli --out site-v2/public/lineage_snapshot.json
```

## Refresh Repository And Live Evidence

Generate the repository target manifest from a clean EDW worktree and exact SHA:

```bash
cd 05_tools/06_lineage_portal
PYTHONPATH=. python3 -m scanner.repository_manifest \
  --repo-root /path/to/data-edw-fabric-worktree \
  --expected-sha <full-sha> \
  --pull-request <number> \
  --out repository_lineage_manifest.json
```

Refresh the live fallback baseline and build the combined snapshot with delegated Azure CLI auth:

```bash
FABRIC_USE_AZ_CLI=1 PYTHONPATH=. python3 -m scanner.cli \
  --skip-semantic \
  --repository-manifest repository_lineage_manifest.json \
  --write-live-baseline live_lineage_baseline.json \
  --out site-v2/public/lineage_snapshot.json
```

The graph keeps live and repository target edges separate. Exact matches are `aligned`; differing source routes are `drift`; repository edges with no live counterpart are `repository_only`. Live runtime remains authoritative.

## Safety

- Scanner is read-only against Fabric/SQL/Power BI surfaces.
- Do not commit generated credentials, access tokens, or API keys.
- Rotate any secret pasted into chat before using this workflow long-term.
- If the repository or Pages site is public, confirm that table names, SQL definitions, semantic metadata, and lineage are acceptable to publish.
