# Query Governor - Ad-hoc Query Watchdog

Tự động monitor và kill các ad-hoc test queries chạy quá lâu trong Fabric Warehouse để tránh đốt CU không cần thiết.

## Cơ Chế Hoạt Động

```
GitHub Actions (mỗi 5 phút)
  ↓
  Chạy 9 iterations × 30 giây = 4.5 phút
    ↓
    Mỗi iteration:
      - Query sys.dm_exec_requests trong Processing + Gold warehouses
      - Check queries chạy > 10 phút
      - Loại trừ stored procedures, ETL, blocked queries
      - KILL queries còn lại
      - Log vào Meta.QueryGovernorLog
      - Sleep 30 giây
  ↓
  Kết thúc, chờ 5 phút → chạy lại
```

## Logic Kill

Query sẽ bị KILL nếu:
- ✅ Chạy > 10 phút (configurable trong `config.yaml`)
- ✅ KHÔNG phải stored procedure (`Usp_*`)
- ✅ KHÔNG phải ETL (`INSERT`, `UPDATE`, `DELETE`, `MERGE`)
- ✅ KHÔNG bị blocking bởi query khác
- ✅ KHÔNG đang wait (lock/I/O wait)

## Files

```
03_operations/tools/query_governor/
├── config.yaml           # Thresholds và exclusion rules
├── query_watchdog.py     # Script chính
├── requirements.txt      # Python dependencies
├── setup.sql            # Tạo audit log table (chạy 1 lần)
└── README.md            # File này
```

## Setup (Chạy 1 Lần)

### 1. Tạo Audit Log Table

Chạy `setup.sql` trong **SupplyChain_Processing_Warehouse**:

```sql
-- Copy nội dung setup.sql và execute
```

Hoặc dùng Python:

```bash
cd 03_operations/tools/query_governor
python -c "
import pyodbc
# ... (cần credentials)
cursor.execute(open('setup.sql').read())
"
```

### 2. Verify GitHub Secrets

GitHub repo cần có secrets sau (đã có từ lineage portal):

- `FABRIC_TENANT_ID`
- `FABRIC_CLIENT_ID`
- `FABRIC_CLIENT_SECRET`
- `FABRIC_SQL_SERVER`

Check tại: https://github.com/[your-org]/[your-repo]/settings/secrets/actions

### 3. Enable GitHub Actions

Workflow `.github/workflows/query-watchdog.yml` sẽ tự động chạy sau khi commit.

## Test Local (Optional)

```bash
cd 03_operations/tools/query_governor

# Export credentials
export FABRIC_TENANT_ID="5a9d9cfd-c32e-4ac1-a9ed-fe83df4f9e4d"
export FABRIC_CLIENT_ID="..."
export FABRIC_CLIENT_SECRET="..."
export FABRIC_SQL_SERVER="7woj2wroypauvkpn72b56t46ju-qp6ntsfwdaou5atebne65u3p4a.datawarehouse.fabric.microsoft.com"

# Install dependencies
pip install -r requirements.txt

# Run (requires ODBC Driver 18 for SQL Server)
python query_watchdog.py
```

## Configuration

Edit `config.yaml` để điều chỉnh:

```yaml
# Threshold (giây)
kill_threshold_seconds: 600  # 10 phút

# Exclusion patterns
exclusions:
  procedure_patterns:
    - "Usp_"  # Thêm patterns khác nếu cần
  
  etl_keywords:
    - "INSERT"
    - "COPY INTO"  # Thêm keywords khác
  
  login_names:
    - "PowerBIService"
    - "NAric@ashleyfurniture.com"  # Whitelist user nếu cần
```

## Monitoring

### View Recent Kills

```sql
-- Top 100 queries bị kill gần đây
SELECT TOP 100 
    LogTimestamp,
    WarehouseName,
    SessionId,
    LoginName,
    ElapsedSeconds,
    KillSuccess,
    LEFT(QueryText, 200) AS QueryPreview
FROM Meta.QueryGovernorLog
WHERE Action = 'KILL'
ORDER BY LogTimestamp DESC;
```

### Check GitHub Actions Logs

1. Vào repo → Actions tab
2. Click workflow "Query Watchdog"
3. Xem logs của mỗi run

### Stats by User

```sql
-- Người nào bị kill nhiều nhất?
SELECT 
    LoginName,
    COUNT(*) AS TimesKilled,
    AVG(ElapsedSeconds) AS AvgElapsedSeconds,
    MAX(ElapsedSeconds) AS MaxElapsedSeconds
FROM Meta.QueryGovernorLog
WHERE Action = 'KILL'
  AND LogTimestamp >= DATEADD(DAY, -7, GETDATE())
GROUP BY LoginName
ORDER BY TimesKilled DESC;
```

## Troubleshooting

### GitHub Actions Failed: "ODBC Driver not found"

→ Đã fix trong workflow, install ODBC Driver 18 automatically

### "Missing FABRIC_CLIENT_ID"

→ Check GitHub secrets đã setup chưa

### Query không bị kill dù chạy > 10 phút

→ Check exclusion rules trong config.yaml, có thể query match 1 trong các patterns

### False positive: Query hợp lệ bị kill

→ Thêm exclusion rule:
- Nếu là stored procedure: thêm prefix vào `procedure_patterns`
- Nếu là user đặc biệt: thêm vào `login_names`
- Tăng `kill_threshold_seconds`

## Cost

- **GitHub Actions free tier**: 2000 phút/tháng
- **Usage**: ~720 phút/tháng (4.5 phút × 288 runs/ngày × 30 ngày)
- **→ Hoàn toàn FREE**

## Safety

- Watchdog chỉ **KILL** queries, không modify data
- Stored procedures và ETL workloads được bảo vệ
- Blocked queries không bị kill (không đốt CU)
- Có audit log đầy đủ

## Disable Tạm Thời

Nếu cần tắt watchdog:

1. Vào repo → Actions
2. Click workflow "Query Watchdog"
3. Click "..." → Disable workflow

Hoặc comment dòng `schedule:` trong `.github/workflows/query-watchdog.yml`

## Support

Contact: NAric@ashleyfurniture.com
