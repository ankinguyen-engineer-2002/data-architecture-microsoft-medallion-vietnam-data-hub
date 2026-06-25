# Cross-Workspace Multi-Medallion Flow

> Mermaid diagrams showing data flow across `EnterpriseData-Dev` (hub) and `Enterprise SupplyChain-Dev` (VN value stream).

## Diagram 1 — End-to-end architecture (current state)

```mermaid
flowchart TB
    classDef hub fill:#fce7f3,stroke:#db2777,color:#831843
    classDef vs fill:#dbeafe,stroke:#2563eb,color:#1e3a8a
    classDef ext fill:#fef3c7,stroke:#d97706,color:#92400e
    classDef bronze fill:#fed7aa,stroke:#c2410c
    classDef silver fill:#e0e7ff,stroke:#4f46e5
    classDef gold fill:#fbcfe8,stroke:#be185d
    classDef bi fill:#ddd6fe,stroke:#7c3aed

    SRC[(EDW + Synapse + UKG +<br/>AFI + Maximo + GA + ServiceNow)]:::ext

    subgraph HUB ["🇺🇸 EnterpriseData-Dev (HUB · Bob's team owns)"]
        direction TB
        SRC_DATA[Source_Data WH<br/>BRONZE 64 sch / 636 tbl]:::bronze
        ETL[ETL_Framework WH<br/>CONTROL PLANE<br/>35 procs · TableDictionary 65 cols<br/>AuditLog · UpdateLog]:::hub
        WHS[Wholesale_Warehouse<br/>SILVER 28 sch / 209 tbl<br/>SalesHistory_AFI 4-stream-shared<br/>CustomerOrders_AFI etc.]:::silver
        RTL[Retail_Warehouse<br/>SILVER 25 sch / 198 tbl<br/>Retail_Sales_Enh<br/>MasterData_HR_UKG_Enh etc.]:::silver
        MDW[MasterData_Warehouse<br/>SILVER 14 sch / 46 tbl<br/>MasterData_DW.DimDate<br/>DimItemMaster etc.]:::silver
        DST[Distribution_Warehouse<br/>SILVER 7 tbl - incomplete]:::silver
        QLY[Quality_Warehouse<br/>SILVER - empty shell]:::silver
        SCW[SupplyChain_Warehouse<br/>NEW - VN team builds<br/>Forecast_Enh proposed]:::silver
        CW[Centralized_Warehouse<br/>GOLD aggregator 38 tbl]:::gold
        CL[Centralized_Lakehouse<br/>5.92B rows shortcut to PROD]:::gold
    end

    subgraph VS ["🇻🇳 Enterprise SupplyChain-Dev (VALUE STREAM · VN team owns)"]
        direction TB
        EL[Enterprise_Lakehouse<br/>shortcut aggregator<br/>5 schemas from hub]:::bronze
        SCP[SupplyChain_Processing_Warehouse<br/>SILVER SC-specific 8 tbl<br/>+ Meta control plane 23 tbl]:::silver
        SCG[SupplyChain_Gold_Warehouse<br/>ForecastAccuracy_DW<br/>5 Dim + 2 Fact star schema]:::gold
        SM[Semantic Model<br/>sc_forecast_control_tower<br/>Direct Lake · 35 DAX]:::bi
        PBI[Power BI Reports<br/>+ Streamlit lineage]:::bi
    end

    SRC --> SRC_DATA
    SRC_DATA --> WHS
    SRC_DATA --> RTL
    SRC_DATA --> MDW
    SRC_DATA --> SCW
    SRC_DATA --> DST
    ETL -.drives.-> SRC_DATA
    ETL -.drives.-> WHS
    ETL -.drives.-> RTL
    ETL -.drives.-> MDW
    ETL -.drives.-> SCW
    WHS --> CW
    RTL --> CW
    MDW --> CW
    SCW --> CW
    CW --> CL

    HUB -.18 OneLake shortcuts.-> EL
    EL --> SCP
    SCP --> SCG
    SCG --> SM
    SM --> PBI

    SCP -. cross-DB SP call .-> SCW
    SCP -. usp_LogRun v2 sync .-> ETL
```

## Diagram 2 — Daily pipeline orchestration

```mermaid
sequenceDiagram
    participant T as ⏰ Schedule 02:00 UTC
    participant M as pl_sc_master<br/>(🇻🇳 VN workspace)
    participant Reg as Meta.AssetRegistry<br/>(🇻🇳 VN)
    participant W as DAG Wave Engine<br/>(🇻🇳 VN)
    participant GL as Meta.usp_GenericLoad<br/>(🇻🇳 VN)
    participant HUB as 🇺🇸 SupplyChain_Warehouse<br/>(after Bob unblock Q3)
    participant SC as 🇻🇳 SupplyChain_Processing_Warehouse
    participant Log as Meta.usp_LogRun v2
    participant ETL as 🇺🇸 ETL_Framework<br/>TableDictionary + AuditLog<br/>(after Bob unblock Q1)

    T->>M: Trigger daily
    M->>Reg: SELECT DISTINCT project<br/>WHERE is_active=1
    M->>W: ForEach project, ForEach wave (3 waves)
    W->>Reg: Lookup assets in wave<br/>filter next_run_time

    par Asset shared (workspace=hub)
        W->>GL: usp_GenericLoad('Forecast_Enh', 'ForecastDemandMonthly')
        GL->>HUB: Cross-DB CTAS write at hub<br/>(scoped Contributor)
        HUB-->>GL: rows_loaded
        GL->>Log: usp_LogRun(success, rows)
        Log->>SC: Local: RunLog + AssetRegistry + AuditLog + UpdateLog
        Log->>ETL: Cross-DB sync: hub TableDictionary + AuditLog
    and Asset SC-specific (workspace=SC)
        W->>GL: usp_GenericLoad('SupplyChain_Enh', 'ActualDemandMonthly')
        GL->>SC: Local CTAS at VN WH
        SC-->>GL: rows_loaded
        GL->>Log: usp_LogRun(success)
        Log->>SC: Local audit chain
        Log->>ETL: Cross-DB sync (optional)
    end

    M->>Log: usp_UpdateTableDictionaryModified<br/>(deferred batch sync)
    Log->>SC: UPDATE TableDictionary.Modified
    Log->>ETL: UPDATE Modified at hub TableDictionary
```

## Diagram 3 — Engineer adding a new Silver table (decision tree)

```mermaid
flowchart TD
    Start([Engineer needs new Silver table])
    D1{Cross-team value?<br/>Will Wholesale, Retail,<br/>other VS use it?}

    Start --> D1

    D1 -->|YES — shared| Hub[🇺🇸 Build at HUB<br/>physical_workspace = 5360a935<br/>SupplyChain_Warehouse.Forecast_Enh<br/>or MasterData_DW for masters]
    D1 -->|NO — SC-only logic| VS[🇻🇳 Build at VN<br/>physical_workspace = c8d9fc83<br/>SupplyChain_Processing_Warehouse.SupplyChain_Enh]

    Hub --> Code1[Write SQL view +<br/>register Meta.AssetRegistry row]
    VS --> Code2[Write SQL view +<br/>register Meta.AssetRegistry row]

    Code1 --> PR[PR to ADO<br/>Enterprise Data Services repo]
    Code2 --> Commit[Commit VN repo<br/>auto Git sync]

    PR --> Review[Rakesh / Ankit review<br/>~24h]
    Review --> Merge[Merge → auto-deploy hub]
    Commit --> Auto[Auto-deploy VN]

    Merge --> Pipeline[Next pipeline run<br/>pl_sc_master picks up]
    Auto --> Pipeline

    Pipeline --> Dispatch[usp_GenericLoad reads<br/>physical_workspace col]
    Dispatch --> Execute[Cross-DB execute<br/>at correct WH]

    Execute --> Audit[usp_LogRun v2 chain:<br/>RunLog + AssetRegistry + AuditLog<br/>+ UpdateLog + TableDictionary]

    Audit --> Done([✅ Asset live + monitored<br/>+ lineage tracked])

    classDef hub fill:#fce7f3,stroke:#db2777
    classDef vs fill:#dbeafe,stroke:#2563eb
    classDef shared fill:#fef3c7,stroke:#d97706

    class Hub,Code1,PR,Review,Merge hub
    class VS,Code2,Commit,Auto vs
    class Pipeline,Dispatch,Execute,Audit,Done shared
```

## Diagram 4 — Domain ownership map

```mermaid
flowchart LR
    classDef hub fill:#fce7f3,stroke:#db2777
    classDef vs fill:#dbeafe,stroke:#2563eb

    subgraph TEAMS [Domain teams]
        BOB[Bob/Rakesh team<br/>US Enterprise]
        WS[Wholesale team]
        RT[Retail team]
        DI[Distribution team]
        SC[VN SC team<br/>Aric + Cherry]
    end

    subgraph HUB [🇺🇸 EnterpriseData-Dev]
        ETLF[ETL_Framework]:::hub
        SD[Source_Data]:::hub
        WHWH[Wholesale_Warehouse]:::hub
        RTWH[Retail_Warehouse]:::hub
        MDWH[MasterData_Warehouse]:::hub
        DSWH[Distribution_Warehouse]:::hub
        SCWH[SupplyChain_Warehouse<br/>NEW]:::hub
        CWH[Centralized_Warehouse]:::hub
    end

    subgraph VS [🇻🇳 Enterprise SupplyChain-Dev]
        ELake[Enterprise_Lakehouse]:::vs
        SCPWH[SupplyChain_Processing_Warehouse]:::vs
        SCGWH[SupplyChain_Gold_Warehouse]:::vs
    end

    BOB -.owns.-> ETLF
    BOB -.owns.-> SD
    BOB -.owns.-> MDWH
    BOB -.owns.-> CWH
    WS -.owns.-> WHWH
    RT -.owns.-> RTWH
    DI -.owns.-> DSWH
    SC -.owns scoped.-> SCWH

    SC ==owns full==> ELake
    SC ==owns full==> SCPWH
    SC ==owns full==> SCGWH
```

## Cross-refs

- Storage inventory: [`../10_evidence/01_storage_inventory.md`](../10_evidence/01_storage_inventory.md)
- ETL framework alignment: [`../20_proposals/01_etl_framework_alignment.md`](../20_proposals/01_etl_framework_alignment.md)
- VN architect diagrams: [`../../Enterprise_SupplyChain_Dev_architect/diagrams/`](../../Enterprise_SupplyChain_Dev_architect/diagrams/)
