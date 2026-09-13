# Azure operations

Azure is where **everything is registered**: Entra identities, subscription
**DATAWAREHOUSE PROD**, ADLS, Azure Databricks workspace, SQL/Agent, Fabric
capacity. Fabric and Databricks do not invent their own users.

This folder is the control-plane runbook for the **two-mart slice**, not an
ARM export of the company.

| File | What |
|---|---|
| [control_plane.yaml](control_plane.yaml) | Tenant, subscription, resources, role planes |
| [identity.md](identity.md) | Entra, PIM, groups, four admin planes |
| [sql.md](sql.md) | Azure SQL / EDW vs Fabric warehouse vs Agent |
| [fabric_and_databricks.md](fabric_and_databricks.md) | Tenant admin vs workspace vs Azure Databricks |
| [landing.yaml](landing.yaml) | Lake paths Spark actually reads |
| [runbook.md](runbook.md) | Tickets: missing file, access, PIM, cost |

**[Verified]** 2026-06-21: owner identity and tenant (redacted here), subscription
**DATAWAREHOUSE PROD**, workspaces
EnterpriseData / EnterpriseData-Dev / Enterprise SupplyChain-Dev /
Enterprise SupplyChain / Analytics-Premium.

**[Verified]** 2026-08-12: SCM-Dev **Contributor**, Analytics **Member**,
not Workspace Admin. Item engineering does not need Workspace Admin.
Tenant-wide **Global Administrator** / **Fabric Administrator** is
**owner-confirmed, PIM** — elevate, do the switch, revert. Git has no
Entra role export.

Lake `ashleydevlake` and ADF `ashleyv2datafactory` are **[Verified]**
names. Job SKUs, Entra group names, Databricks workspace ARM name are
**[Reconstructed]**. PIM card: [ENTRA_EXPORT.md](ENTRA_EXPORT.md).

Next: [../databricks/](../databricks/) then
[../orchestration/main/](../orchestration/main/).
Spark version/CI/CD: [../databricks/cicd_and_promotion.md](../databricks/cicd_and_promotion.md)
— not this folder, not `.dacpac`.
