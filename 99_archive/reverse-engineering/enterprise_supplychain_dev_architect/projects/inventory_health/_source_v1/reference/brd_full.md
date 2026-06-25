
# Business Requirements Document (BRD)


## Control Tower – Inventory Health

Issue Date: 0//26
Last Revised: 0//26
Reference Example Linked: Example BRD.docx

## 1. Purpose & Background

The Supply Chain Planning team requires a centralized, standardized tool to track inventory health across all nodes of the network, enabling proactive identification of risk, excess/aging inventory, and working capital inefficiencies.
This BRD defines the business requirements for designing and building the datasets and Power BI reporting that will provide real-time visibility, standardized KPIs, and actionable insights to support data-driven inventory decisions across the enterprise.

## 2. Business Objectives

The Inventory Health dataset must enable the Supply Chain Planning organization to:
Track inventory costs and trends over time (by channel, DC, category, SKU)
Monitor key inventory health KPIs (DOH, Turns, Weeks of Supply, Aging, Excess & Obsolete, Service Risk)
Quantify working capital impact and financial exposure
Enable root cause analysis (demand variance, supply disruption, MOQ constraints, lifecycle transitions)
Support proactive rebalancing and mitigation actions
Provide drill-down capability from enterprise → node → SKU level
Standardize definitions of inventory health metrics across the organization
Improve S&OP / IBP decision quality with real-time inventory intelligence

## 3. Intended Users & Downstream Use

Primary Users – Supply Chain Planning Team
Secondary / Future Users – Sales Operations
Use Cases - Ad-hoc analytical queries, BI dashboards, and recurring reporting; Future uses: Agentic planning input

## 4. Scope, Assumptions & Exclusions


### 4.1 In Scope

Gold Layer calculations within Microsoft Fabric
All required Silver Layer dependencies to support Gold metrics
Power BI report replacing existing inventory health reporting
Daily snapshot dataset at SKU–Location grain
Standardized KPI definitions are governed in the semantic model

### 4.2 Assumptions

Master data (SKU, Location, Vendor, Lifecycle) is accurate and governed upstream
Safety Stock Targets are system-calculated and approved by Planning
Forecast data represents the latest approved consensus plan
Historical transaction data required for AWD and Turns is available for the required lookback windows
Warehouse capacity data is maintained and updated by Operations
No changes to upstream ERP inventory logic are required

### 4.3 Out of Scope (Initial Phase)

Automated inventory rebalancing recommendations
Operational process changes
Creation of synthetic data
Purchase order creation or planning system automation
Real-time (intra-day) inventory updates
Advanced predictive modeling or ML scoring
Financial ledger reconciliation beyond inventory valuation inputs
Changes to ERP inventory transaction processes
High Jump Warehouse Management System data is not available in the initial phase

## 5. Data Model Overview

The dataset will follow a current-state + audit-history design pattern, separating the authoritative view from historical changes.

### 5.1 Recommended Table Structures


#### A. ItemBalanceHistory

Purpose: Provides a Saturday night weekending snapshot of the inventory on hand for all finished good and raw materials at the Item-Warehouse level
Grain: Item-Warehouse, Weekending
Characteristics: - Reflects the latest known values for …. - Overwritten or updated as corrections occur - Primary source for analytics and reporting

#### B. Table 2

Purpose:
Grain:
Characteristics:

### 5.2 Entity Relationships

[ItemSKU]
[Warehouse
[WeekEnding]

## 6. Required Core Fields & Metrics


### 6.1 Core Identifiers

ItemSKU
Warehouse
WeekEnding Date

### 6.2 Variable Definitions

- Technical note on mixing units of measure:
- Make sure the order of operations goes from bottom to top (Inactive to TB) to capture the proper flow of bucketing

### 6.3 Quantities & Dates


### Calculated Metrics

ATP In-Stock Rate
Description: Percentage of active SKUs with positive quantities available to promise new customer order
Calculation:
(Count of Active Item-WH locations with Positive ATP / Count of Active Item-WH locations) × 100
$-Weighted or Volume-Weighted equivalent
Variable Definition:
Active SKU: SKU–Location combination that is in an active lifecycle state and has forecasted demand or confirmed open customer orders
Timeframe:
Forward-looking Window:
Snapshot Basis:
Revenue at Risk
Description: Revenue that is exposed due to lack of availability to cover expected sales
Calculation:
At Week Four Ending : [SINegQty] * [FOBPrice]
Timeframe:
Forward-looking Window: 30 calendar days
Snapshot Basis:
History - Week Snapshot
Current Day Supply Plan at Wk 4
Safety Stock Multiple
Description: Inventory position relative to safety stock target
Calculation: Under 6.2 Variable Definitions
Variable Definitions:
Inventory Position: On Hand Quantity (Shippable Inventory future look)
Safety Stock Target: System-calculated safety stock at SKU–Location level based on service level, demand variability, and lead time
Safety Stock Multiple: Inventory Position ÷ Safety Stock Target (if Safety Stock Target = 0, flag exception)
Timeframe:
Past : week ending snapshots of On Hand Quantity used in calculation
Forward Look : current day’s supply plan, using week ending Shippable Inventory Projection
Obsolete Ratio
Description: Percentage of total inventory value that has not moved (no sales, no transfers, no consumption) for ≥
Subset of Total Business (TB) inventory that is not selling
Calculation: (Inventory Value with No Movement ≥ / Total Inventory Value) × 100
Variable Definitions:
Inventory Value: Inventory at cost (COGS basis)
No Movement: No sales shipment, inter-warehouse transfer, production consumption, or allocation
Movement Window: ≥ without movement
Timeframe:
Rolling  lookback period
Snapshot Basis:
On-Hold Ratio %
Description: Percentage of total inventory that is currently restricted from sale or allocation (quality hold, damage, legal hold, system block, etc.)
Calculation: (Inventory Value or Units on Hold / Total Inventory Value or Units) × 100
Variable Definitions:
On-Hold Inventory: Inventory flagged with hold codes (quality, damage, legal, compliance, system block)
Total Inventory: Total On-Hand inventory (gross)
Timeframe:
Snapshot Basis:
Turns
Description: The number of times inventory is sold and replaced annually
Calculation: (Annualized COGS / Inventory Value (at Cost))
Variable Definitions:
Annualized COGS: Trailing 12 Months COGS
Average Inventory Value:  inventory at cost
Timeframe:
COGS: Trailing - 12 months
Inventory Average: Trailing - 12 months
Aged Inventory % (Serial Data)
Description: Percentage of total inventory cost exceeding defined aging thresholds (e.g., 180/270/365 days)
Calculation: Σ (Inventory Cost where Age > Threshold / Total Inventory Cost) × 100
Variable Definitions:
Inventory Age: Days since receipt date (or manufacturing completion date)
Aging Thresholds: >180 days, >270 days, >365 days
Inventory Cost: On-Hand Inventory on a cost basis
Timeframe:
Snapshot Basis: Daily
Age calculated as Reporting Date – Receipt Date
Warehouse Capacity Utilization
Description: Physical storage utilization relative to warehouse cubic capacity, including optional inbound view
Calculation: (Used Storage Cube / Total Available Cube) × 100
Variable Definitions:
Used Storage Cube: Sum of cubic feet occupied by On-Hand inventory
Total Available Cube: Total physical warehouse cubic capacity (rack + bulk storage)
Timeframe:
Snapshot Basis: Daily
Capacity values refreshed quarterly or upon layout updates
Total Inventory Commitment
Description: Total committed supply across on-hand, in-transit, and on-order inventory
Calculation: (On Hand Inventory + In Transit Inventory + On Order Inventory)
Variable Definitions:
On Hand Inventory: Physically received and system-available inventory
In Transit Inventory: Shipped but not yet received inventory with confirmed ETA
On Order Inventory: Open Firm purchase orders not yet shipped
Timeframe:
Snapshot Basis: Week ending snapshots from the past, and show current day

### 6.5 Status, Classification & Audit Fields

Status Fields
Lifecycle Status (Active, New, , Discontinued, Obsolete)
Hold Status (Quality, Damage, Legal, Compliance, System Block)
SKU Flag (Item–Location level)
Classification Fields
Inventory Classification (TB, Aggressive Excess, Excess, Over Target, Sweet Spot, At Risk, Short)
Classification Effective Date
Safety Stock Exception Flag (e.g., Safety Stock = 0)
Audit Fields
Record Created Timestamp
Record Updated Timestamp
Source System Identifier
Data Quality Flag (Nulls, negative inventory, missing cost, etc.)

### 6.6 UI/UX Requirements

Export
Audit Trail
Default View Dates

## 7. Data Retention & Historical Integrity

The Current State table reflects the most up-to-date values
History should be maintained for 3 years
Historical records must not be physically deleted within the retention window

## 8. Refresh Cadence & Data Availability

Data refresh frequency:
Daily
Data availability SLA: Available by the start of business on the following day

## 9. Data Quality & Validation Considerations

Key validation checks include:
Lifecycle state consistency with quantity and shipment dates
Exception handling and data quality flags are recommended for downstream analytics.

## 10. Access, Governance & Security

Dataset classified as internal operational data
Read access granted to Supply Chain Planning, Analytics, and Data Science roles
Write access restricted to Data Engineering pipelines
Data definitions governed via the enterprise data catalog

## 11. Open Questions, Risks & Dependencies


### 11.1 Open Questions

To what degree can we track aged inventory through receipt dates across products – certain products may not be serialized and are not able to be tracked
Should an “Expected Excess” bucket be
MOQ  romo

### 11.2 Risks


### 11.3 Dependencies

Master data governance for locations and SKUs
“Statistical Forecast” to be determined by business logic selected in Streamline implementation
Financial data

### 11.4 Currently Out-of-Scope

Addition of HighJump data – to get storage in the yard and rack; serialized age of inventory

## 12. Success Criteria

Backend data engineered in Microsoft Fabric
Metrics or Calculations created and maintained in the semantic model “SupplyChain_Gold”
Power BI report created and reaching “Stable Release”
Adoption by Supply Chain Planning Team Members for reporting and analytics
Extensible design for future ML and AI use cases
End of Document


---

## EMBEDDED TABLES


### Table 0

 | Name | Job Title
--- | --- | ---
Business Owner | Matthew Jeffries | Senior Director – Supply Chain Strategy
Technical Lead | Robert Font Perez | Senior Manager – Supply Chain Strategy

### Table 1

Inventory Classifications | Definition
--- | ---
TB Inventory 
(Trash & Burn) | Inventory > (104 × Average Weekly Demand)
Aggressive Excess | Inventory > (52 × Average Weekly Demand) 
and ≤ (104 × Average Weekly Demand)
Excess | Inventory > (17 × Average Weekly Demand) 
and ≤ (52 × Average Weekly Demand)
Over Target | Inventory > (1.5 × Safety Stock Target) 
and ≤ (17 × Average Weekly Demand)
Sweet Spot | Inventory ≥ (0.5 × Safety Stock Target) 
and ≤ (1.5 × Safety Stock Target)
Below Target | Inventory ≤ (0.5 * Safety Stock Target)
 | 
Inactive | AFI Item Status  ‘’ AND []

### Table 2

Bucket | Classifications | Definition
--- | --- | ---
Base Supply / Demand Quantities | On Hand Quantity | Total inventory On Hand at a Warehouse, expressed in units, $ at COGS, $ at Revenue, Volume (Cubic Ft), and in Weeks of Supply; ability to segment by location
Base Supply / Demand Quantities | In Transit Quantity | Total inventory In Transit, expressed in units, $ at COGS, $ at Revenue, Volume (Cubic Ft), Weeks of Supply, and Containers
Base Supply / Demand Quantities | On Order Quantity | Total inventory actively on order
Firm Purchase Order
Firm Manufacturing Order
Base Supply / Demand Quantities | Allocated Demand Quantity | Quantity of on-hand inventory reserved against confirmed customer orders within ATP window but not yet shipped
Base Supply / Demand Quantities | Forecast Demand Quantity | Projected unit demand at the SKU–Location level for a defined forward-looking time horizon based on the approved forecast
Base Supply / Demand Quantities | Average Weekly Demand (AWD) | Average 13-week forecasted demand at the SKU–Location level used for inventory classification and coverage analysis
(If the forecast is zero, the 13-week historical average)
Financial Quantities | Inventory Value 
(at Cost) | Monetary value of on-hand inventory calculated using standard cost
Financial Quantities | Standard Cost | Predefined per-unit cost used for inventory valuation and financial reporting purposes
Financial Quantities | Standard Selling Price | Approved per-unit sales price used to estimate revenue exposure and forecasted revenue
(FOBARC)
Financial Quantities | Cost of Goods Sold (COGS) | Recognized cost associated with inventory units shipped during a defined reporting period
([UCDEF] at [STID] =000)
Physical Quantities | Used Storage Cube | Total cubic volume occupied by on-hand inventory within a warehouse location
Physical Quantities | Total Available Warehouse Cube | Total usable cubic storage capacity of a warehouse location, including rack and bulk storage areas
Physical Quantities | Container Count (for in-transit) | Number of shipping containers associated with inventory currently in transit and not yet received
Safety Stock Quantities | [TB Quantity] | Sum of Total On Hand WHERE 
inventory classification = “TB Inventory”
Safety Stock Quantities | [Aggressive Excess Quantity] | Sum of Total On Hand WHERE 
inventory classification = “Aggressive Excess”
Safety Stock Quantities | [Excess Quantity] | Sum of Total On Hand WHERE 
inventory classification = “Excess”
Safety Stock Quantities | [Over Target Quantity] | Sum of Total On Hand WHERE 
inventory classification = “Over Target”
Safety Stock Quantities | [Sweet Spot Quantity] | Sum of Total On Hand WHERE 
inventory classification = “Sweet Spot”
Safety Stock Quantities | [Below Target Quantity] | Sum of Total On Hand WHERE 
inventory classification = “Below Target”