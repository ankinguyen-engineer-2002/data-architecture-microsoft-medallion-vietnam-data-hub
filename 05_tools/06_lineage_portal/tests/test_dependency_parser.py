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


if __name__ == "__main__":
    unittest.main()
