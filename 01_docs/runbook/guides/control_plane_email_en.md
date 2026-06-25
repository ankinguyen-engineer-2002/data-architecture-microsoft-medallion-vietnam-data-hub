# Email draft (EN) — to Enterprise ETL (US DE) for thanks + alignment recap + request for review

**Subject:** Follow-up — VN SupplyChain Control Plane (built on Enterprise ETL Framework) + request for your review

Hi Enterprise ETL,

Thank you again for the recent discussion and for sharing your perspective.

To make coordination easier going forward, I’m adding **Aric Nguyen** (VN SupplyChain Data Engineering) to this email thread. Aric is directly involved in building and operating the VN-side solution and can provide additional technical context, track follow-ups, and coordinate directly with your team when needed.

Below is a short recap of the key points to ensure we have the same understanding.

## 1) Confirmed alignments

1) **Deprecate v8 (Notebook/Spark)**  
   - We are working on deprecating the Notebook/Spark-based architecture (internally referred to as v8).  
   - The remaining v8 components are kept temporarily only for comparison/validation while finalizing business logic for Control Tower; this is not the long-term operating direction.

2) **Coordinate with Rakesh’s squad on Enterprise_Lakehouse (RadarSync)**  
   - As discussed, we will work closely with Rakesh’s squad (including DE) for datasets ingested into `Enterprise_Lakehouse` in `Enterprise SupplyChain-Dev` via **RadarSync**.  
   - If any decision is architectural or has long-term impact, we will proactively sync with you early to align before implementation.

3) **VN operations documentation (Control Plane)**  
   - We understand you are interested in parts of the VN Supply Chain workspace, especially the operational platform we call the **Control Plane**, built on top of the Enterprise ETL Framework patterns.  
   - We’re sharing a document that explains:
     - how we operate the platform today (end-to-end), and
     - how we interpret the differences between the two operational patterns.

**Document link (GitHub public/accessible):** `<PASTE LINK HERE>`

## 2) Note on current “alignment” level

- Based on our assessment, the VN platform aligns ~**90%** with the Enterprise patterns used in `EnterpriseData` / `EnterpriseData-Dev` (overall approach + operational setup).  
- The remaining differences are primarily runtime-driven adaptations for the value stream, plus additions learned from Microsoft Fabric best practices to improve operational robustness.

## 3) Request for your feedback after reviewing the document

After you review the document, we’d really appreciate your guidance in two areas:

### (A) Depth: what should we expand further?

The document describes the VN operating model end-to-end, including:
- **one generic stored procedure** supporting multiple **load patterns** (metadata-driven)  
- **waves** (dependency-safe execution)  
- **lineage** (direct + semantic edges)  
- **data quality (DQ)** by layer (and it can be placed by wave/run if required)  
- **observability** (run-level logs: duration/rows/error)  
- practical **setup templates** for onboarding/operating/triage

If there are areas you want us to go deeper on (e.g., strict TableDictionary parity, correlation/id strategy, or enterprise monitoring expectations), please let us know.

### (B) Adoption level: TableDictionary + working/swap pattern

We understand the two areas you care most about are:
1) **Dictionary / metadata contract** (TableDictionary posture)  
2) **Working publish pattern** (`_Wrk` → `_LOAD` → swap) to avoid partial-state exposure

In the document we outlined multiple implementation options (from light integration to higher alignment). We would like your input on which option best matches your long-term expectations and direction.

## 4) Proposed next step

We do not think an additional dedicated session is necessary because the document is intentionally detailed. If anything needs clarification, a quick Teams sync should be sufficient.

When convenient, could you reply by email (or via a quick Teams discussion) with guidance on:
- TableDictionary requirement (adapter/export vs physical sync)
- working/swap scope (Silver/Gold/both)
- ops metrics level + pairing/correlation requirement
- ownership/placement if additional runtime controls are needed

Thanks again, Enterprise ETL.

Best regards,  
Aric Nguyen  
VN SupplyChain Data Engineering

