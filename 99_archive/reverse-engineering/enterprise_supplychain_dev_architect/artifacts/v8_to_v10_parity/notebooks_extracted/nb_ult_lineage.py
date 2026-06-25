# ─── Cell 1 ───
# ── Table Lineage ──
df = spark.sql("""
    SELECT table_name, layer, source_tables, load_type, status, last_load_date
    FROM SupplyChain_Lakehouse.dbo.utl_pipeline_metadata
    WHERE source_tables IS NOT NULL
    ORDER BY layer, table_name
""")
print(f"Tables with lineage: {df.count()}")
df.show(100, truncate=False)

# ─── Cell 2 ───
# ── Cross-Table Links (producer → consumer) ──
df_links = spark.sql("""
    SELECT
        expanded.source_tbl   AS source_table,
        p.layer               AS source_layer,
        expanded.table_name   AS target_table,
        expanded.layer        AS target_layer,
        expanded.load_type
    FROM (
        SELECT c.table_name, c.layer, c.load_type, src.source_tbl
        FROM SupplyChain_Lakehouse.dbo.utl_pipeline_metadata c
        LATERAL VIEW EXPLODE(SPLIT(c.source_tables, ',')) src AS source_tbl
        WHERE c.source_tables IS NOT NULL
          AND src.source_tbl NOT LIKE '[external]%'
    ) expanded
    LEFT JOIN SupplyChain_Lakehouse.dbo.utl_pipeline_metadata p
        ON p.table_name = expanded.source_tbl
    ORDER BY source_table, target_table
""")
print(f"Cross-table links: {df_links.count()}")
df_links.show(100, truncate=False)

# ─── Cell 3 ───
# ── Lineage Summary by Layer ──
spark.sql("""
    SELECT
        layer,
        COUNT(*) AS notebook_count,
        SUM(CASE WHEN source_tables IS NOT NULL THEN 1 ELSE 0 END) AS with_lineage,
        SUM(CASE WHEN status = 'success' THEN 1 ELSE 0 END) AS healthy
    FROM SupplyChain_Lakehouse.dbo.utl_pipeline_metadata
    GROUP BY layer
    ORDER BY layer
""").show()

# ─── Cell 4 ───
# ── Orphan Tables (source referenced but no producer registered) ──
spark.sql("""
    SELECT DISTINCT expanded.source_tbl AS orphan_table
    FROM (
        SELECT src.source_tbl
        FROM SupplyChain_Lakehouse.dbo.utl_pipeline_metadata c
        LATERAL VIEW EXPLODE(SPLIT(c.source_tables, ',')) src AS source_tbl
        WHERE c.source_tables IS NOT NULL
          AND src.source_tbl NOT LIKE '[external]%'
    ) expanded
    LEFT JOIN SupplyChain_Lakehouse.dbo.utl_pipeline_metadata p
        ON p.table_name = expanded.source_tbl
    WHERE p.table_name IS NULL
    ORDER BY orphan_table
""").show(50, truncate=False)

