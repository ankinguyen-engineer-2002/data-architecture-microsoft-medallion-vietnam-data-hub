#!/usr/bin/env python3
import struct, subprocess, pyodbc

SERVER = "7woj2wroypauvkpn72b56t46ju-qp6ntsfwdaou5atebne65u3p4a.datawarehouse.fabric.microsoft.com"
DB = "SupplyChain_Gold_Warehouse"

raw = subprocess.check_output(
    ["az","account","get-access-token","--resource","https://database.windows.net/","--query","accessToken","-o","tsv"]
).decode().strip()
token_bytes = raw.encode("UTF-16-LE")
token_struct = struct.pack(f"<I{len(token_bytes)}s", len(token_bytes), token_bytes)
conn = pyodbc.connect(
    f"DRIVER={{ODBC Driver 18 for SQL Server}};SERVER={SERVER};DATABASE={DB};Encrypt=Yes;TrustServerCertificate=No",
    attrs_before={1256: token_struct}, timeout=60
)
cur = conn.cursor()

sql = (
    "SELECT s.name AS schema_name, t.name AS table_name, c.name AS column_name, c.column_id "
    "FROM sys.columns c "
    "JOIN sys.tables  t ON t.object_id  = c.object_id "
    "JOIN sys.schemas s ON s.schema_id  = t.schema_id "
    "WHERE c.name LIKE '%[_]%' "
    "AND s.name NOT IN ("
    "'sys','INFORMATION_SCHEMA','db_owner','db_accessadmin',"
    "'db_securityadmin','db_ddladmin','db_backupoperator',"
    "'db_datareader','db_datawriter','db_denydatareader','db_denydatawriter'"
    ") "
    "ORDER BY s.name, t.name, c.column_id;"
)

cur.execute(sql)
rows = cur.fetchall()

if not rows:
    print("PASS -- no snake_case columns found.")
else:
    print(f"FAIL -- {len(rows)} snake_case column(s):")
    print(f"{'Schema':<22} {'Table':<30} {'Column'}")
    print("-" * 80)
    for r in rows:
        print(f"{r[0]:<22} {r[1]:<30} {r[2]}")
conn.close()
