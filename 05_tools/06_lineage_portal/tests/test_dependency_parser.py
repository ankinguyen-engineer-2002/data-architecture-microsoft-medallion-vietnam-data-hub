from __future__ import annotations

import unittest

from scanner.dependency_parser import ObjectRef, extract_object_refs


class DependencyParserTests(unittest.TestCase):
    def test_extracts_bracketed_and_plain_three_part_refs(self) -> None:
        sql = """
        SELECT *
        FROM [Enterprise_Lakehouse].[ItemMaster_AFI].[ITMRVA] AS i
        JOIN SupplyChain_Processing_Warehouse.ReferenceMaster_Enh.ItemMaster AS p
          ON i.ItemNumber = p.ItemSKU
        """
        refs = extract_object_refs(sql, default_database="SupplyChain_Gold_Warehouse")
        self.assertIn(ObjectRef("Enterprise_Lakehouse", "ItemMaster_AFI", "ITMRVA"), refs)
        self.assertIn(ObjectRef("SupplyChain_Processing_Warehouse", "ReferenceMaster_Enh", "ItemMaster"), refs)

    def test_ignores_comments(self) -> None:
        sql = """
        -- FROM Enterprise_Lakehouse.Bad.Schema
        SELECT * FROM Enterprise_Lakehouse.Good.TableA
        """
        refs = extract_object_refs(sql)
        self.assertEqual(refs, [ObjectRef("Enterprise_Lakehouse", "Good", "TableA")])

    def test_handles_sqlcmd_database_and_ignores_alias_columns_and_literals(self) -> None:
        sql = """
        SELECT s.ItemSKU, inv.OnHandQty,
               'Enterprise_Lakehouse.ItemMaster_AFI.ITMRVA.UCDEF' AS evidence
        FROM [$(Source_Data)].[MasterData_ItemMaster_AFI].[ITMRVA] s
        JOIN [InventoryHistory_Enh].[InventorySnapshotWeekly] inv
          ON inv.ItemSKU = s.ITNBR
        """
        refs = extract_object_refs(sql, default_database="SupplyChain_Processing_Warehouse")
        self.assertEqual(
            refs,
            [
                ObjectRef("Source_Data", "MasterData_ItemMaster_AFI", "ITMRVA"),
                ObjectRef(
                    "SupplyChain_Processing_Warehouse",
                    "InventoryHistory_Enh",
                    "InventorySnapshotWeekly",
                ),
            ],
        )


if __name__ == "__main__":
    unittest.main()
