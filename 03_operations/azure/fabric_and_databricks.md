# Fabric tenant and Azure Databricks — both registered in Azure

Same Entra tenant. Two products. Admin is **not** one checkbox.

## Fabric

Fabric capacity is an Azure resource bound to Entra. Workspaces are
security boundaries (Microsoft CAF). Git on hub:
`ashleyfurniture` / `Enterprise Data Services` / `Fabric-EnterpriseData`.

**[Verified] workspaces** (2026-06-21 unless noted):

| Workspace | Role |
|---|---|
| `EnterpriseData` | Hub PROD |
| `EnterpriseData-Dev` | Hub DEV (`5360a935-…`), 11 warehouses, `Source_Data`, mirror `edw_dev` |
| `Enterprise SupplyChain-Dev` | This repo’s runtime (`c8d9fc83-…`) |
| `Enterprise SupplyChain` | SCM prod |
| `Supply Chain Analytics-Premium` | Reports (Aric **Member**, 2026-08-12) |
| `Enterprise_Retail_Dev` | Other value stream; out of slice |

**Tenant admin (Fabric Administrator)** — PIM: tenant switches, capacity,
allow **Azure Databricks Unity Catalog mirroring**, new workspace, domain
settings. This is the “admin Fabric tenant” work. It is **not** the same
as Workspace Admin on SCM-Dev.

**Workspace** — items, git, lakehouse, warehouse. Snapshot 2026-08-12:
Aric = **Contributor** on SCM-Dev, **not** Admin. Item work (SQL, DQ,
semantic) does not require Workspace Admin. Sharing Gold Read/ReadAll and
workspace-identity lifecycle **does**. If that was granted later, replace
the snapshot with a new export; do not silently upgrade this file.

SCM lakehouse shortcuts into hub. VN does not write hub warehouses
(scan). That is why Azure/Databricks must land **before** Fabric: Fabric
SCM drinks shortcuts.

## Azure Databricks

Not Fabric Spark. Not Databricks on AWS.

| Piece | This estate |
|---|---|
| Product | **Azure Databricks** (ADLS `abfss://`, UC mirror into OneLake) |
| Azure resource | `Microsoft.Databricks/workspaces` in subscription DATAWAREHOUSE PROD |
| Catalog | `edw_dev` **[Verified]** autoSync to OneLake |
| Compute | Jobs clusters, then **exit** (seven slice jobs) |
| Identity | Entra SSO into the workspace; UC grants on groups |

Portal: Azure → Databricks workspace → Manage account / UC. Fabric admin
portal does **not** create clusters.

Creating the workspace, VNet injection, access connector to
`ashleydevlake`, and the mirror **enablement** are Azure + Fabric tenant
work. Nightly `replaceWhere` on the forecast snapshot is Databricks job
work (`03_operations/databricks/`).

## Order of registration (senior)

1. Entra groups.
2. Subscription / RG / ADLS / Key Vault / SQL + Agent.
3. Azure Databricks workspace + UC `edw_dev` + storage credential.
4. Fabric capacity + tenant switch “mirror Azure Databricks.”
5. Hub workspace shortcuts.
6. SCM workspace lakehouse shortcuts + warehouses + Agent job.

Skip a step and you get a warehouse with no Bronze, or a Spark job nobody
in Fabric can see.
