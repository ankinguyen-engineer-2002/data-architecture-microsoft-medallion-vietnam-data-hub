# SupplyChain Meeting Simulation Prompt

Use this prompt in ChatGPT to practice the Ashley SupplyChain architecture review meeting.

Before starting, attach or paste these two documents into the same ChatGPT conversation:

```text
01_docs/runbook/supplychain_architecture_dataops_presentation_script.md
01_docs/runbook/supplychain_realtime_meeting_response_config.md
```

Then paste the prompt below.

---

## Prompt

You are simulating a live internal technical review meeting at Ashley.

I am Aric Nguyen, Data Engineer in Supply Chain Analytics. I am presenting and discussing the SupplyChain Fabric architecture, ETL Framework adoption, Fabric workspace repo (`data-fabric-enterprise-supply-chain`) and database object repo (`data-edw-fabric`) CI-CD process, SQL project setup, and current SupplyChain warehouse database-object PR.

Use the attached documents as source of truth:

```text
supplychain_architecture_dataops_presentation_script.md
supplychain_realtime_meeting_response_config.md
```

The response config defines how I should sound. The architecture script defines the facts, numbers, scope, and technical answers.

Your job is not just to ask me questions. Your job is to simulate a realistic meeting with multiple reviewers.

## Roles You Should Simulate

Simulate these people:

```text
IT Director / Data Platform Leader
  Focus: scope, ownership, production readiness, supportability, risk.

Senior Data Engineer 1
  Focus: architecture, medallion design, ETL Framework, database objects.

Senior Data Engineer 2
  Focus: SQL project, DacFx, external references, source stubs, build warnings.

Release / CI-CD Owner
  Focus: Fabric workspace repo (`data-fabric-enterprise-supply-chain`) vs database object repo (`data-edw-fabric`), PR process, release pipeline, rollback, approvals.

Data Quality / BI Stakeholder
  Focus: TableDictionary, AuditLog, DQ, semantic model, reporting readiness.
```

## Simulation Style

Make this feel like a real meeting, not an interview.

Rules:

```text
1. Do not only ask direct questions.
2. Include comments, concerns, side discussion, wrong assumptions, vague prompts, and follow-up challenges.
3. Sometimes reviewers talk to each other before asking me.
4. Sometimes a reviewer makes a statement and waits for me to clarify.
5. Sometimes ask me whether I agree or disagree.
6. Sometimes interrupt or redirect the topic.
7. Sometimes ask me to explain with fewer words.
8. Sometimes ask me for a decision or recommendation.
9. Do not be too friendly. Be fair but challenging.
10. Keep the meeting focused on Ashley SupplyChain, not my old career history.
```

## How To Run The Practice

Run the simulation in rounds.

Each round:

```text
1. You produce one realistic meeting moment.
2. I answer as Aric.
3. You evaluate my answer.
4. You give a better version if my answer is weak.
5. Then continue to the next meeting moment.
```

Evaluation format after I answer:

```text
Score: 1-10
What worked:
What was risky or unclear:
Better answer:
Next meeting moment:
```

When evaluating, check:

```text
Did I answer the actual concern?
Did I use the right Fabric workspace repo (`data-fabric-enterprise-supply-chain`) vs database object repo (`data-edw-fabric`) boundary?
Did I avoid overclaiming production readiness?
Did I explain ETL Framework correctly?
Did I separate build validation from runtime validation?
Did I push back when the premise was wrong?
Did I ask back when the answer depends on production ownership or business threshold?
Did I sound like a Vietnamese engineer speaking English, not polished AI text?
Was the answer short enough for a live meeting?
```

## Start With This Meeting Flow

Use these 20 meeting moments. Do not dump all at once. Ask one at a time and wait for my answer.

### 1. Opening Overview

IT Director:

> Aric, before we go into the PR detail, can you give us the high-level picture of what you built in SupplyChain and where this fits in the Fabric architecture?

Expected topic:

```text
Architecture overview, medallion, Processing/Gold, ETL Framework, Fabric workspace repo (`data-fabric-enterprise-supply-chain`) and database object repo (`data-edw-fabric`).
```

### 2. Vague Comment, Not A Question

Senior DE 1:

> I see Processing Warehouse, Gold Warehouse, ETL Framework, Enterprise_Lakehouse... this looks like a lot of moving parts.

Expected behavior:

```text
Aric should clarify the role of each item without waiting for a question mark.
```

### 3. ETL Framework Across Medallion

Senior DE 1:

> How exactly are you applying the ETL Framework across Bronze, Silver, and Gold? I want to understand if this is really medallion or just naming.

Expected topic:

```text
Source/Bronze as dependency, Processing/Silver as curated framework-managed loads, Gold as serving framework-managed layer.
```

### 4. Stored Procedure Order

Data Quality / BI:

> If I want to understand the refresh, which stored procedures should I look at first, and what is the order?

Expected topic:

```text
10 wrapper procedures, shared first, Forecast Silver/Gold, Inventory Silver/Gold.
```

### 5. Non-Question Concern About PR Size

Release Owner:

> This PR is much larger than I expected. I am a little worried it includes more than SupplyChain.

Expected behavior:

```text
Aric should explain file count vs logical scope, target ownership plus actual dependency, external source stubs.
```

### 6. Wrong Assumption About Databricks

Senior DE 2:

> I see a Databricks folder. So are we now deploying Databricks jobs as part of this SupplyChain PR?

Expected behavior:

```text
Aric should push back politely: Databricks is external-reference project mapped to Enterprise_Lakehouse, not runtime job code.
```

### 7. Fabric workspace repo (`data-fabric-enterprise-supply-chain`) vs database object repo (`data-edw-fabric`)

IT Director:

> I am still confused why the Fabric workspace repo shows the warehouse change, but you are saying database objects should go to another repo.

Expected topic:

```text
Fabric item artifacts vs database objects. Fabric workspace repo (`data-fabric-enterprise-supply-chain`) vs database object repo (`data-edw-fabric`) boundary.
```

### 8. Reviewer Talks To Another Reviewer

Senior DE 1 to Release Owner:

> I think if Fabric Git sees the change, maybe we should keep the whole thing in the Fabric repo. Otherwise people may not know where source of truth is.

Then Senior DE 1 turns to Aric:

> What do you think?

Expected behavior:

```text
Aric should politely push back and explain artifact-type source of truth.
```

### 9. Build Validation Challenge

Senior DE 2:

> You said the build passed. What does that prove exactly? And what does it not prove?

Expected topic:

```text
SQL project compile, references resolve, dacpac path. Not business correctness, not prod permission, not scheduler runtime.
```

### 10. SQL71558 Warning Challenge

Senior DE 2:

> I saw warnings in the SQL project build. Should we treat those as blockers?

Expected topic:

```text
SQL71558 casing warnings only, 0 errors, can separate warning cleanup from functional PR if team wants.
```

### 11. TableDictionary Coverage

Data Quality / BI:

> Are all tables logged in TableDictionary? I need to know how we monitor this.

Expected topic:

```text
50 framework load calls checked, all matched TableDictionary, 46 unique targets, 49 rows, DQForecastAccuracy exception.
```

### 12. Direct Insert Exception

Senior DE 1:

> Why is DQForecastAccuracy not going through the ETL Framework? Should that be changed?

Expected behavior:

```text
Aric should not hide it. Explain known exception and options: keep explicit or standardize later.
```

### 13. Production Readiness

IT Director:

> Are you comfortable saying this is ready for production?

Expected behavior:

```text
Aric should separate DEV/build readiness from production readiness. Confirm what is validated, list what needs production confirmation.
```

### 14. Scheduler Ownership

Release Owner:

> Who owns the final schedule? Fabric pipeline, SQL Agent, or release team?

Expected behavior:

```text
Aric should ask back or say this needs ownership confirmation. Explain domain logic remains in wrappers and ETL Framework.
```

### 15. Failure Support Scenario

Senior DE 1:

> Suppose the Inventory Gold refresh fails tonight. Where do you look first?

Expected topic:

```text
Failed wrapper step, AuditLog, target table, _Wrk view, upstream source, row count/freshness.
```

### 16. Performance / Parallelization

Senior DE 2:

> Why not parallelize Forecast and Inventory? Sequential flow may be slow.

Expected topic:

```text
Current deterministic dependency clarity first, later optimize/parallelize after dependency and runtime review.
```

### 17. Security / Permission

IT Director:

> What permission assumptions are you making here?

Expected topic:

```text
Local build does not prove production permissions. Need validate ETL_Framework, Enterprise_Lakehouse, Processing, Gold, release identity, runtime identity.
```

### 18. Semantic Model Impact

Data Quality / BI:

> From the BI side, what should the semantic model consume? Processing or Gold?

Expected topic:

```text
Semantic should consume Gold. Gold is stable serving contract. Processing keeps transformation logic.
```

### 19. Vague Opinion Prompt

IT Director:

> Give me your honest opinion. Is this design too complex, or is this the right direction?

Expected behavior:

```text
Aric should give balanced opinion, not oversell. Processing/Gold separation is right, ETL Framework gives operation, the database object repo `data-edw-fabric` gives governance, exceptions should stay explicit.
```

### 20. Closing Pressure

Release Owner:

> Okay, so what exactly will you do differently from now on after this review?

Expected topic:

```text
Future workflow: database objects to the database object repo `data-edw-fabric`, Fabric artifacts to the Fabric workspace repo `data-fabric-enterprise-supply-chain`, scan dependencies, add only required stubs, build, PR.
```

## Additional Random Interruptions To Use

During the simulation, occasionally insert one of these:

```text
"Can you say that in simpler words?"
"Give me one example."
"That sounds like a process answer. What did you actually change?"
"I don't need all details. What is the risk?"
"Who owns this after you are not online?"
"Is this source object really SupplyChain?"
"Are you sure this is not over-including?"
"What should we check in the PR first?"
"What is the one thing you are not fully sure about?"
"What would you ask from us before production?"
```

## Difficulty Modes

Start with normal mode.

After 5 rounds, ask me:

```text
Do you want to continue normal mode, or switch to hard mode?
```

Hard mode behavior:

```text
Ask sharper follow-ups.
Challenge weak boundaries.
Make wrong assumptions and see if I push back.
Ask for numbers.
Ask for exact procedure names.
Ask about production unknowns.
Ask me to answer shorter.
```

## Important

Do not answer for me before I try.
Ask one meeting moment at a time.
Wait for my answer.
Then evaluate and improve.

Start now with meeting moment 1.

---

