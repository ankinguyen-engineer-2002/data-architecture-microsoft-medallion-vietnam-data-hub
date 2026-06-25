-- ---- InventoryHistory_Enh.v_SalesShipment ----
-- REMOVED 2026-05-28: DA-first flow reads SalesHistory_Enh.v_InvoiceDetailLineLevel directly.
-- Do not recreate Mart B SalesShipment materialization or alias view.



-- ---- InventoryHistory_Enh.v_PurchaseOrder ----
-- B1 FIX (2026-05-17): switched source SupplyChain.dbo.podetail_v2 → Enterprise.PoDetail (21.95M rows).
-- B1.2 FIX (2026-05-19): Dhivya loaded Enterprise.PoMaster (5.69M rows, 75 cols) — switched LEFT JOIN from SC_LH.dbo.pomaster → Enterprise.PoMaster. SC_LH.dbo.pomaster legacy path can be deprecated.
-- DA Silver_Check 2026-05-28: keep direct-to-customer/RP warehouses in PO source.
-- DEDUPE: PoDetail has 1 verified true-dup pair (Key 'P0SM242'|'612908'|1 — all 53 cols identical); ROW_NUMBER drops safely.
