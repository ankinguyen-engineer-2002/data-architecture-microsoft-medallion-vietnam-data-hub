-- Source: SupplyChain_Warehouse.bronze.ref_order_type
-- Generated from INFORMATION_SCHEMA.COLUMNS.
-- This is a logical schema snapshot; review Fabric physical options before execution.
CREATE TABLE [bronze].[ref_order_type] (
    [code_order_type] varchar(8000) NULL,
    [name_order_type] varchar(8000) NULL,
    [name_order_type_short] varchar(8000) NULL,
    [code_order_class] varchar(8000) NULL,
    [num_order_category] int NULL,
    [is_route_eligible] int NOT NULL,
    [is_additional_charge] int NOT NULL,
    [is_auto_replenish] int NOT NULL,
    [is_will_notify_expedite] int NOT NULL,
    [is_minimum_exception] int NOT NULL,
    [code_requirement_type] varchar(8000) NULL,
    [is_force_delivery_schedule] int NOT NULL,
    [is_force_delivery_rims] int NOT NULL,
    [code_transport_type] varchar(8000) NULL,
    [num_zone_lead_time_days] int NULL,
    [is_special_handling] int NOT NULL,
    [is_auto_reschedule] int NOT NULL,
    [is_user_defined] int NOT NULL,
    [name_modified_by] varchar(8000) NULL,
    [dt_modified] date NULL,
    [_load_dt] datetime2(6) NULL
);
