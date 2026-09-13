# Identity — Azure registers people, then every other plane consumes that

Entra ID is the only identity. Fabric, Azure Databricks, ADLS, and SQL
logins are assignments **on top of** Entra objects. That is the control
plane. You do not create a second user in Databricks and a third in Fabric.

## What is verified

| Fact | Evidence |
|---|---|
| Owner UPN | Live check 2026-06-21; redacted in public repo |
| Tenant identifier | Same; redacted in public repo |
| Subscription **DATAWAREHOUSE PROD** | Same |
| SCM DEV workspace role **Contributor** (2026-08-12) | `AGENTS.md` |
| Analytics-Premium role **Member** (2026-08-12) | `AGENTS.md` |
| No Workspace **Admin** on that snapshot | `AGENTS.md` |

Owner-confirmed: you are **one of** the people who can hold **Global
Administrator** and **Fabric Administrator**. This git does not contain an
Entra role export. Until that export exists, say **PIM-eligible tenant
admin**, not “I live as Global Admin.”

Living as Global Admin all day is not senior. Senior is: directory role
**eligible**, elevate for a bounded task, revert. Daily mart work uses
groups and workspace RBAC.

## Admin planes (do not mix)

| Plane | Role | What you actually do | Not this role |
|---|---|---|---|
| Entra | Global Administrator (PIM) | Users, groups, Conditional Access, PIM, app registrations | Not for editing Gold SQL |
| Fabric tenant | Fabric Administrator (PIM) | Tenant switches, capacity, allow Azure Databricks mirroring, new workspace | Not for a DAX measure |
| Fabric workspace | Admin / Member / Contributor | Items, git, lakehouse, warehouse | Contributor ≠ Admin (snapshot) |
| Azure resource | Owner / Contributor / User Access Administrator on RG or subscription | Databricks workspace, ADLS, Key Vault, SQL server | Not Fabric tenant switches |
| Databricks | Workspace admin | Jobs, clusters, UC grants on `edw_dev` | Not Fabric Agent |
| SQL | db_owner / Agent operator | Logins, Agent job that calls 11 wrappers | Not lake ACLs |

Ticket “add a DA”: Entra group → Fabric workspace Viewer/Member on
Analytics-Premium → Gold Read/ReadAll → RLS. **Not** Global Admin.

Ticket “turn on UC mirror”: Fabric Administrator + Databricks workspace
admin. **Not** a Gold wrapper change.

## Groups [Reconstructed names, real pattern]

| Group | Azure / lake | Databricks UC | Fabric |
|---|---|---|---|
| `data-sc-engineers` | read `raw/` + `curated/` SCM prefix | `MODIFY` on slice schemas | Contributor on SCM-Dev |
| `data-sc-analysts` | **no** `raw/` | **no** UC write | Member on Analytics-Premium; Gold read |
| `data-sc-oncall` | Monitor reader | job canary | Agent operator (SQL) |
| Break-glass GA | PIM only | — | — |

Do not add analysts to ADLS `raw/`. Gold is their surface.

## Portal path (weekly)

1. Entra → group membership (joiners/leavers).
2. PIM → elevate only if tenant switch or new ARM resource.
3. Azure Portal → DATAWAREHOUSE PROD → lake metrics, Databricks workspace, SQL Agent status.
4. Fabric admin portal → capacity / tenant settings **only when elevated**.
5. Fabric workspace → items as Contributor (snapshot).
6. Drop PIM.

## Secrets

Key Vault holds lake keys, SQL, Databricks PAT if any. Nothing in git.
ADF `ashleyv2datafactory` already lives in RG `IoT_Hub`; do not duplicate
secrets into notebooks.
