[StagingDefinition = [Kind = "FastCopy"]]
section Section1;
[DataDestinations = {[Definition = [Kind = "Reference", QueryName = "Wholesale_SalesHistory_AFI InvoiceDetail_DataDestination", IsNewTarget = true], Settings = [Kind = "Automatic", TypeSettings = [Kind = "Table"]]]}]
shared #"Wholesale_SalesHistory_AFI InvoiceDetail" = let
    // 1. Kết nối nguồn dữ liệu
    Source = Sql.Database("ashley-edw.database.windows.net", "ASHLEY_EDW"),

    // 2. Native SQL Query — toàn bộ SELECT, TRIM, FILTER chạy trên SQL Server
    RawQuery = Value.NativeQuery(Source, "
        SELECT
            /* ── Identifiers ── */
            RTRIM(LTRIM(CustomerNumber))         AS id_customer,
            RTRIM(LTRIM(InvoiceNumber))          AS id_invoice,
            RTRIM(LTRIM(ExtendedInvoiceNumber))  AS id_invoice_extended,
            RTRIM(LTRIM(ItemNumber))             AS id_item_sku,
            CAST(ItemSequence AS BIGINT)         AS num_item_sequence,
            RTRIM(LTRIM(OrderNumber))            AS id_order,
            RTRIM(LTRIM(ShiptoNumber))           AS code_ship_to,
            RTRIM(LTRIM(Warehouse))              AS code_warehouse,
            RTRIM(LTRIM(CurrencyCode))           AS code_currency,

            /* ── Quantities ── */
            QuantityShipped                      AS qty_shipped,
            QuantityOrdered                      AS qty_ordered,
            QuantityBackOrdered                  AS qty_backordered,

            /* ── Amounts ── */
            InvoiceAmount                        AS amt_invoice,
            Price                                AS amt_price,
            StandardPrice                        AS amt_standard_price,
            ContractPrice                        AS amt_contract_price,
            NetSales                             AS amt_net_sales,
            Discount                             AS amt_discount,
            PriceAdjustment                      AS amt_price_adjustment,
            Freight                              AS amt_freight,
            AdvertisingAccrual                   AS amt_advertising_accrual,
            DFIDiscount                          AS amt_dfi_discount,

            /* ── Dates ── */
            CAST(InvoiceDate AS DATE)            AS dt_invoice,
            CAST(OrderDate AS DATE)              AS dt_order,
            CAST(RequestDate AS DATE)            AS dt_request,
            CAST(OrderEntry AS DATE)             AS dt_order_entry,
            CAST(PromisedDelivery AS DATE)       AS dt_promised_delivery,
            CAST(OriginalRequestDate AS DATE)    AS dt_original_request,
            CAST(OriginalPromiseDate AS DATE)    AS dt_original_promise,
            CAST(CurrentRequestDate AS DATE)     AS dt_current_request,
            CAST(CurrentPromiseDate AS DATE)     AS dt_current_promise,
            CAST(DeliveryDate AS DATE)           AS dt_delivery,
            CAST(ActualDelivery AS DATE)         AS dt_actual_delivery,
            CAST(TripCloseDate AS DATE)          AS dt_trip_close,
            CAST(FirstScanDate AS DATE)          AS dt_first_scan,
            CAST(TripCreateDate AS DATE)         AS dt_trip_create,
            CAST(OriginalInvoiceDate AS DATE)    AS dt_original_invoice,
            CAST(OriginalOrderDate AS DATE)      AS dt_original_order,

            /* ── Delivery Days ── */
            RTRIM(LTRIM(DefaultDeliveryDays))                   AS code_default_delivery_days,
            RTRIM(LTRIM(DeliveryDays))                          AS val_delivery_days,
            RTRIM(LTRIM(DeliveryDaysOriginalPromiseDate))       AS val_delivery_days_original_promise,
            RTRIM(LTRIM(DeliveryDaysRaw))                       AS val_delivery_days_raw,
            RTRIM(LTRIM(DeliveryDaysOriginalPromiseDateRaw))    AS val_delivery_days_original_promise_raw,

            /* ── Sales & Trip ── */
            RTRIM(LTRIM(BilltoSalesman))         AS id_salesperson_billto,
            RTRIM(LTRIM(ShiptoSalesman))         AS id_salesperson_shipto,
            CAST(TripNumber AS BIGINT)           AS num_trip,
            CAST(DropNumber AS BIGINT)           AS num_drop,

            /* ── Item & Order Codes ── */
            RTRIM(LTRIM(ItemClass))              AS code_item_class,
            RTRIM(LTRIM(CustomerSku))            AS name_customer_sku,
            RTRIM(LTRIM(PurchaseOrder))          AS id_purchase_order,
            RTRIM(LTRIM(PostingMonth))           AS code_posting_month,
            RTRIM(LTRIM(CreditCode))             AS code_credit,
            RTRIM(LTRIM(PriorityCode))           AS code_priority,
            RTRIM(LTRIM(OrderItemStat))          AS code_order_item_status,
            CAST(OrderPriority AS BIGINT)        AS num_order_priority,
            RTRIM(LTRIM(LineReleaseNumber))       AS code_line_release,
            RTRIM(LTRIM(OrderType))              AS code_order_type,
            RTRIM(LTRIM(Ordertype3))             AS code_order_type_3,
            RTRIM(LTRIM(PriceCode))              AS code_price,
            RTRIM(LTRIM(ItemDiscountCode))       AS code_item_discount,
            RTRIM(LTRIM(commissioncode))         AS code_commission,
            RTRIM(LTRIM(FreightCode))            AS code_freight,
            RTRIM(LTRIM(DiscountSalesClass))     AS code_discount_sales_class,
            RTRIM(LTRIM(FreightSalesClass))      AS code_freight_sales_class,
            RTRIM(LTRIM(BuyGroupCode))           AS code_buy_group,

            /* ── Exception IDs ── */
            CAST(ExceptionID AS BIGINT)              AS id_exception,
            CAST(GroupPricingExceptionID AS BIGINT)   AS id_group_pricing_exception,

            /* ── Percentages ── */
            WarehouseOperationPercent             AS pct_warehouse_operation,
            PriceAdderPercent                     AS pct_price_adder,
            CalculatedAllowancePercent            AS pct_calculated_allowance,
            PackageDiscountAllocationPercent       AS pct_package_discount_allocation,

            /* ── Package ── */
            RTRIM(LTRIM(PackageDescription))     AS name_package_description,
            RTRIM(LTRIM(PackageID))              AS id_package,
            PackagePrice                         AS amt_package_price,
            PackageItemPrice                     AS amt_package_item_price,
            PackageItemDiscount                  AS val_package_item_discount,

            /* ── Original References ── */
            RTRIM(LTRIM(OriginalInvoiceNumber))      AS id_original_invoice,
            RTRIM(LTRIM(OriginalOrderNumber))        AS id_original_order,
            CAST(OriginalSequenceNumber AS BIGINT)   AS num_original_sequence,
            RTRIM(LTRIM(OriginalDeliveryMethod))     AS code_original_delivery_method

        FROM Wholesale_SalesHistory_AFI.InvoiceDetail
        WHERE InvoiceDate >= '2023-01-01'
          AND InvoiceNumber IS NOT NULL
    ")
in
    RawQuery;
shared #"Wholesale_SalesHistory_AFI InvoiceDetail_DataDestination" = let
  Pattern = Lakehouse.Contents([CreateNavigationProperties = false, EnableFolding = false, HierarchicalNavigation = null]),
  Navigation_1 = Pattern{[workspaceId = "c8d9fc83-18b6-4e1d-8264-0b49eed36fe0"]}[Data],
  Navigation_2 = Navigation_1{[lakehouseId = "62a3081e-4093-4f46-856c-f50aa58732fa"]}[Data],
  TableNavigation = Navigation_2{[Id = "brz_saleshistory_afi__invoicedetail_ver2", ItemKind = "Table"]}?[Data]?
in
  TableNavigation;
