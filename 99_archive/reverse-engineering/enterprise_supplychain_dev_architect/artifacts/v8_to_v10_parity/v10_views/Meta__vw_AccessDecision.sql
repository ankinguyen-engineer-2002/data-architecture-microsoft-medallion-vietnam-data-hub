CREATE VIEW [Meta].[vw_AccessDecision] AS

SELECT
    asset_id,
    canonical_layer,
    access_mode,
    physical_item,
    physical_schema,
    physical_object,
    source_contract_status,
    approval_status,
    edw_exit_status,
    CASE
        WHEN access_mode = 'EDWSupplement' THEN 'Use Staging until exit validation and Bob/Rakesh approval pass'
        WHEN access_mode = 'DirectShortcut' THEN 'Read Enterprise_Lakehouse shortcut directly after source contract validation'
        WHEN access_mode = 'WarehouseTransform' THEN 'Run Warehouse-native Domain Silver transform'
        WHEN access_mode = 'GoldPublish' THEN 'Publish physical Gold table for Direct Lake serving'
        ELSE 'Review access policy'
    END AS access_decision
FROM Meta.AssetRegistry
WHERE is_active = 1
