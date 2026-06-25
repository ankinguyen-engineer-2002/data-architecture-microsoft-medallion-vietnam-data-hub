-- 08_update_asset_registry.sql
-- Update Meta.AssetRegistry, DQRule, LineageEdge with new schema names.

UPDATE Meta.AssetRegistry SET physical_schema = 'Staging_Wrk' WHERE physical_schema = 'Staging_WRK';
UPDATE Meta.AssetRegistry SET physical_schema = 'ReferenceMaster_Enh' WHERE physical_schema = 'ReferenceMaster_ENH';
UPDATE Meta.AssetRegistry SET physical_schema = 'SalesHistory_Enh' WHERE physical_schema = 'SalesHistory_ENH';
UPDATE Meta.AssetRegistry SET physical_schema = 'ForecastHistory_Enh' WHERE physical_schema = 'ForecastHistory_ENH';
UPDATE Meta.AssetRegistry SET physical_schema = 'OpenOrderHistory_Enh' WHERE physical_schema = 'OpenOrderHistory_ENH';

UPDATE Meta.DQRule SET target_schema = 'Staging_Wrk' WHERE target_schema = 'Staging_WRK';
UPDATE Meta.DQRule SET target_schema = 'ReferenceMaster_Enh' WHERE target_schema = 'ReferenceMaster_ENH';
UPDATE Meta.DQRule SET target_schema = 'SalesHistory_Enh' WHERE target_schema = 'SalesHistory_ENH';
UPDATE Meta.DQRule SET target_schema = 'ForecastHistory_Enh' WHERE target_schema = 'ForecastHistory_ENH';
UPDATE Meta.DQRule SET target_schema = 'OpenOrderHistory_Enh' WHERE target_schema = 'OpenOrderHistory_ENH';

UPDATE Meta.LineageEdge SET source_schema = 'Staging_Wrk' WHERE source_schema = 'Staging_WRK';
UPDATE Meta.LineageEdge SET target_schema = 'Staging_Wrk' WHERE target_schema = 'Staging_WRK';
UPDATE Meta.LineageEdge SET source_schema = 'ReferenceMaster_Enh' WHERE source_schema = 'ReferenceMaster_ENH';
UPDATE Meta.LineageEdge SET target_schema = 'ReferenceMaster_Enh' WHERE target_schema = 'ReferenceMaster_ENH';
UPDATE Meta.LineageEdge SET source_schema = 'SalesHistory_Enh' WHERE source_schema = 'SalesHistory_ENH';
UPDATE Meta.LineageEdge SET target_schema = 'SalesHistory_Enh' WHERE target_schema = 'SalesHistory_ENH';
UPDATE Meta.LineageEdge SET source_schema = 'ForecastHistory_Enh' WHERE source_schema = 'ForecastHistory_ENH';
UPDATE Meta.LineageEdge SET target_schema = 'ForecastHistory_Enh' WHERE target_schema = 'ForecastHistory_ENH';
UPDATE Meta.LineageEdge SET source_schema = 'OpenOrderHistory_Enh' WHERE source_schema = 'OpenOrderHistory_ENH';
UPDATE Meta.LineageEdge SET target_schema = 'OpenOrderHistory_Enh' WHERE target_schema = 'OpenOrderHistory_ENH';

UPDATE Meta.SourceContract SET target_schema = 'Staging_Wrk' WHERE target_schema = 'Staging_WRK';
UPDATE Meta.SourceContract SET target_schema = 'ReferenceMaster_Enh' WHERE target_schema = 'ReferenceMaster_ENH';
UPDATE Meta.SourceContract SET target_schema = 'SalesHistory_Enh' WHERE target_schema = 'SalesHistory_ENH';
UPDATE Meta.SourceContract SET target_schema = 'ForecastHistory_Enh' WHERE target_schema = 'ForecastHistory_ENH';
UPDATE Meta.SourceContract SET target_schema = 'OpenOrderHistory_Enh' WHERE target_schema = 'OpenOrderHistory_ENH';
