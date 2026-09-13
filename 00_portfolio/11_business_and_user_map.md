# Business, user, and product map

## Users served by the platform

| User | Need | Product surface | Primary owner boundary |
|---|---|---|---|
| Data Engineer / DataOps | reliable loads, audit, DQ, drift and recovery | ETL framework, manifests, tools, runbooks | platform/runtime |
| Data Analyst | conformed tables and stable business definitions | Silver/Gold marts and semantic models | data product |
| Supply Chain planner | forecast, inventory and exception insight | Forecast Accuracy, Inventory Health, reports | domain analytics |
| SCM operations | repeatable operational visibility and guided follow-up | reports, Copilot and bounded flows | business workflow |
| Leadership | concise evidence-backed status | executive report/control-tower views | semantic/report contract |
| Developer / AI builder | reusable governed capability surface | AIOS workbench, plugins, contracts | product/runtime MVP |

## Core business products

### Forecast Accuracy

Compares forecast demand with actual demand across fiscal periods, horizons,
items, warehouses and customer grouping where the contract supports it. The
important engineering work is preserving snapshot semantics and grain while
making the result reusable for DA reports and governed conversational access.

### Inventory Health

Provides current and forward-looking inventory risk from weekly snapshots,
ATP, supply plan, purchase/manufacturing/transfer signals, safety stock and
shared dimensions. The important engineering work is keeping weekly time
semantics intact and preventing a “current inventory” question from silently
becoming a multi-week flow calculation.

### Copilot analytics

Turns a natural-language question into a governed query or clarification. The
semantic model remains the calculation authority; the response must carry
source, time context and data-quality state.

### AIOS Workbench

Explores a broader product shell for chat, research, files, artifacts and
specialist capabilities. It consumes governed data contracts but is currently
an MVP for development/high-level testing, not a replacement for production
SCM data operations.

## Adoption statement

The owner reports that the SCM data and Copilot products are used by a large
Vietnam operations audience (approximately 200 people). This is currently an
owner-confirmed business statement; public material should use a rounded phrase
until a sanitized usage evidence artifact is approved.
