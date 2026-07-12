# Inventory Health Gold — Kế hoạch tối ưu (giữ nguyên kết quả nghiệp vụ)

Ngày tạo: 2026-07-10 · Cập nhật: 2026-07-12 ICT
Trạng thái: **Wave 0 (khám bệnh + dựng bộ kiểm chứng) ĐÃ XONG. Chưa sửa gì trên production. Đang chờ duyệt để bắt đầu Wave 1.**

> Đây là tài liệu tự chứa duy nhất cho công việc tối ưu Inventory Health Gold.
> Toàn bộ bằng chứng khám bệnh (trước đây ở file evidence pack riêng) đã được gộp vào đây.
> Mọi việc đã làm tới nay đều **chỉ đọc** dữ liệu live (`ApplicationIntent=ReadOnly`, chỉ `SELECT` + đọc metadata). **Không** hề `CREATE/ALTER/DROP/INSERT/UPDATE/DELETE` trên Fabric.

---

## PHẦN A — TÓM TẮT CHO NGƯỜI BẬN (đọc 1 phút)

- **Vấn đề:** dây chuyền xử lý dữ liệu tầng Gold phục vụ báo cáo Power BI `sc_control_tower` chạy **quá lâu và tốn tài nguyên** (tối đa ~80 phút/lần; có bảng riêng ngốn 40–48 phút; mỗi lần quét ~10GB dữ liệu).
- **Nguyên nhân gốc tìm ra:** một khối dữ liệu nguồn khổng lồ **705 triệu dòng** bị **lấy về và gom/khử trùng 3 lần y hệt nhau** ở 3 bảng khác nhau. Làm lại 3 lần một việc giống hệt = lãng phí 2/3 công.
- **Giải pháp (C1):** gom/khử trùng khối 705 triệu dòng đó **đúng 1 lần**, rồi cho cả 3 bảng dùng chung kết quả.
- **Đã chứng minh gì:** chạy song song "cách cũ" vs "cách mới" trên **toàn bộ 19,6 triệu dòng thật**, so từng dòng từng giá trị → **0 dòng lệch, 0 giá trị sai**. Về logic, cách mới cho kết quả **y hệt** cách cũ.
- **Chưa chứng minh gì:** nhanh hơn **bao nhiêu %** — muốn biết phải thật sự bắt tay sửa (Wave 1), cần bạn duyệt trước.
- **Ràng buộc sống còn:** báo cáo Power BI đã dựng trên các bảng Gold hiện tại. Vì vậy **cấm** đổi tên/xóa/tạo bảng mới. Chỉ được sửa "cái bếp bên trong", giữ nguyên "cái đĩa bưng ra". Power BI không phải sửa gì.

**Mục tiêu cuối cùng của toàn bộ dự án:** làm dây chuyền Gold **chạy nhanh hơn, đỡ tốn hơn**, trong khi **số liệu ra giống hệt cũ đến từng dòng** và **báo cáo Power BI không phải sửa một chữ nào**.

---

## PHẦN B — VẤN ĐỀ CỤ THỂ GẶP PHẢI

### B.1. Bối cảnh hệ thống
Báo cáo Power BI `sc_control_tower` chạy theo cơ chế **Direct Lake** đọc thẳng từ kho `SupplyChain_Gold_Warehouse`. Nghĩa là: báo cáo nhanh hay chậm, dữ liệu mới hay cũ, phụ thuộc trực tiếp vào việc dây chuyền Gold chạy xong lúc nào.

Dây chuyền Gold = thủ tục `dbo.Usp_Refresh_InventoryHealth_Gold`, chạy **tuần tự 9 bảng** (không song song). Bảng sau chờ bảng trước.

### B.2. Triệu chứng đo được (đây là "cơn đau")
- Toàn bộ dây chuyền: lần chạy chuẩn gần nhất mất **80 phút 14 giây** (lần trước đó 114 phút — đã tự nhanh lên ~30%, nhưng vẫn chậm).
- Các bảng nặng nhất (thời gian quan sát tối đa):

| Bảng | Thời gian | Dấu hiệu |
|---|---:|---|
| `FactInventoryHealthSnapshot` | **47m 55s** | 19,50 triệu dòng đích; quét **26,04 GB**; điểm nóng số 1 |
| `FactInventoryHealthFutureWeekEnding` | **45m 55s** | logic "dự báo tương lai / as-of" phức tạp |
| `InventoryClassificationQtyWeekly` | **21m 49s** | nghi làm lại việc trùng |
| `InventoryHealthSubStatusWeekly` | **19m 42s** | nghi làm lại việc trùng |
| `ProjectedInventoryHealthSubStatus` | **17m 26s** | logic chọn bản kế hoạch mới nhất |

### B.3. Vấn đề KHÔNG phải ở đâu (đã loại trừ, tránh sửa nhầm)
- **Không phải thiếu tài nguyên (capacity):** lấy mẫu F256 chỉ thấy nghẽn 2/80 lần (SELECT) và 5/80 (non-SELECT) → không phải máy yếu.
- **Không phải bảng lịch sử PurchaseOrder:** cái này đã xong, chạy nhanh (33,8s), giữ đúng lịch sử → ngoài phạm vi.
- **Không phải semantic model tự nó chậm:** đã xác nhận `sc_control_tower` là Direct Lake. Độ trễ "dữ liệu sẵn sàng" chủ yếu do thời gian chạy Gold. (Riêng độ trễ khâu reframe/truy vấn báo cáo thì cần đo riêng, chưa quy cho model.)

→ **Kết luận triệu chứng:** thủ phạm là **quét toàn bộ lịch sử nhiều lần + hình dạng truy vấn**, không phải thiếu máy.

---

## PHẦN C — KHÁM BỆNH: ĐÃ ĐIỀU TRA ĐƯỢC GÌ

Tôi dựng một bộ công cụ kiểm tra tại `05_tools/03_gold_parity/` (chỉ đọc) và chạy 5 bước điều tra. Dưới đây là những gì tìm ra.

### C.1. Đọc hiểu hợp đồng của 9 bảng (Layer A — an toàn cấu trúc)
Đọc SQL live + metadata của cả 9 bảng đích. Kết quả: **cả 9 bảng có cột của "view" khớp 100% với cột của "bảng thật"** (đúng số lượng, đúng thứ tự). Đường nạp `INSERT ... SELECT *` hiện an toàn cho cả 9.

| Bảng | Số cột view→table | Nạp an toàn |
|---|---|---|
| DimCalendar | 75/75 | OK |
| DimProduct | 40/40 | OK |
| DimWarehouse | 21/21 | OK |
| DimVendor | 2/2 | OK |
| ProjectedInventoryHealthSubStatus | 28/28 | OK |
| InventoryHealthSubStatusWeekly | 12/12 | OK |
| InventoryClassificationQtyWeekly | 12/12 | OK |
| FactInventoryHealthFutureWeekEnding | 34/34 | OK |
| FactInventoryHealthSnapshot | 54/54 | OK |

**Ghi chú lệch repo (không chặn tiến độ):** view live có vài cột mà file `.sql` trong repo chưa sinh (`WeightedSINegScore`, `OutageClass` ở FactSnapshot; `ProjectedShortageValue` vs tên `ProjectedRevenueAtRisk` ở FutureWeekEnding). Bộ kiểm chứng dùng cột **live** (đúng). File repo nên đồng bộ lại với live sau, tách khỏi phạm vi tối ưu.

### C.2. Ba phép dò rủi ro (Layer B — quyết định tính an toàn)

**R1 — Nối bảng có làm phồng số dòng không?** KHÔNG. Cả 7 bảng phụ mà `FactSnapshot` nối vào đều có **0 nhóm trùng** tại đúng khóa nối → FactSnapshot không bị nhân dòng.

| Bảng phụ | Số dòng | Nhóm trùng tại khóa nối |
|---|---:|---:|
| SafetyStockHelper | 21,070,457 | 0 |
| Cogs52WWeekly | 19,605,162 | 0 |
| LastInvoiceWeekly | 19,605,162 | 0 |
| AFIStatusSnapshotWeekly | 19,605,162 | 0 |
| AwdHelper | 13,632,832 | 0 |
| InventoryHealthSubStatusWeekly | 19,605,162 | 0 |
| InventoryClassificationQtyWeekly | 19,605,162 | 0 |

**R2 — Bảng sản phẩm có làm phồng giá trị tiền không?** KHÔNG. `DimProduct` duy nhất theo `ItemSKU` (783,945 dòng, 0 trùng) → các số "OnHand Value", "Revenue at risk"... không bị thổi phồng.

**R3 — Việc khử trùng có làm lệch giá trị không?** KHÔNG. Đây là phát hiện quan trọng nhất:
- Nguồn `InventorySnapshotWeekly`: **705,785,832 dòng thô** → gom còn **19,605,162 nhóm** theo khóa `(ItemSku, WarehouseCode, SnapshotWeekEndingDate)` — tỷ lệ nén **~36:1**.
- Kiểm tra: khi gom nhiều dòng thành 1, **giá trị các cột cần dùng không đổi** giữa các dòng trong cùng nhóm (0 nhóm lệch OnHandQty; 0 nhóm hòa FiscalMonthDate). Nghĩa là gom kiểu nào cũng ra đúng số.

> **PHÁT HIỆN CỐT LÕI:** khối nguồn **705 triệu → 19,6 triệu dòng** này bị **quét + gom lặp lại 3 LẦN** trong nhóm 3 bảng "weekly". Đây chính là chỗ lãng phí lớn nhất và là mục tiêu tối ưu số 1.

### C.3. Chốt "chuẩn vàng" — hệ thống cũ đang cho ra cái gì (Layer C)
Đóng băng số liệu hiện tại của cả 9 bảng làm mốc so sánh. Tất cả đều **duy nhất tại khóa nghiệp vụ** (không trùng):

| Bảng | Số dòng | Khóa duy nhất |
|---|---:|---|
| DimCalendar | 21,551 | DateSK |
| DimProduct | 783,945 | ItemSKU |
| DimVendor | 87,003 | VendorNumber |
| DimWarehouse | 53 | WarehouseCode |
| ProjectedInventoryHealthSubStatus | 3,785,137 | Item,WH,FactAsOfDate,FutureWeekEnding |
| FactInventoryHealthFutureWeekEnding | 3,785,137 | Item,WH,FutureWeekEnding,SnapshotDate |
| InventoryHealthSubStatusWeekly | 19,605,162 | Item,WH,SnapshotWeekEnding |
| InventoryClassificationQtyWeekly | 19,605,162 | Item,WH,SnapshotWeekEnding |
| FactInventoryHealthSnapshot | 19,501,346 | Item,WH,SnapshotWeekEndingDate |

**Quan hệ số dòng cần giữ nguyên (bất biến bắt buộc):**
- Nhóm weekly = 19,605,162; FactSnapshot = 19,501,346; **chênh lệch Δ = 103,816**.
- Điều tra ra: Δ này **chính xác** là 103,816 dòng loại `SnapshotType='LATEST'` bị FactSnapshot lọc bỏ **sau khi** khử trùng (FactSnapshot chỉ giữ `WEEKLY`). → Giải pháp mới **bắt buộc** phải giữ đúng hành vi lọc-sau-khi-gom này.
- Nhóm tương lai (Future) = Projected = 3,785,137 (khớp 1:1), đều dựa trên `SupplyPlanDetail WHERE IsLatestSupplyPlanSnapshot = 1`.

**Tổng kiểm chứng đóng băng — FactInventoryHealthSnapshot (ngày max 2026-07-04):**
- SUM(OnHandQty) = 2,146,230,631
- SUM(OnHandValue) = 76,277,084,285.2561
- SUM(OnOrderQty) = 957,865,819
- SUM(SIQty) = 1,538,875,984
- SUM(ShortageValue) = -18,577,955,997
- Phủ ngày: 2023-01-07 → 2026-07-04.
- Phân bố trạng thái phân loại: SWEET_SPOT 6,427,701 · OVER_TARGET 6,329,621 · BELOW_TARGET 2,801,722 · INACTIVE 2,054,373 · EXCESS 850,753 · SLOB 622,709 · AGGRESSIVE_EXCESS 224,402 · TB_INVENTORY 190,065.
- Shortage/Surplus: SURPLUS 9,600,945 · IN_STOCK 6,511,664 · SHORTAGE 3,388,737.

(Chi tiết đối chiếu theo từng tuần lưu trong `05_tools/03_gold_parity/contracts/*.baseline.json` mục `weekly_recon`.)

---

## PHẦN D — GIẢI PHÁP (5 hướng, xếp hạng theo lợi ích/rủi ro)

| Hạng | Giải pháp | Lợi ích | Rủi ro | Điều kiện trước khi làm | Trạng thái |
|---|---|---|---|---|---|
| **C1** | **Gom `inv_base` dùng chung** — quét/khử trùng khối 705 triệu dòng **1 lần** thay vì 3 lần | **Cao** | Đã đóng (R3) | Giữ đúng bộ lọc NULL + chênh lệch SnapshotType Δ=103,816 | **Chứng minh logic XONG (PASS)** |
| C2 | Dùng chung phép gộp PO/MO (đơn hàng) | Vừa | Thấp (đã GROUP BY, khóa đã chứng minh) | Khớp SUM tuyệt đối | Chưa làm |
| C3 | Dùng chung `sp_latest` + as-of cho nhóm "tương lai" (bảng ngốn 45 phút) | Vừa–Cao | Cần kiểm thứ tự as-of (R4) | Việc chọn "bản mới nhất" phải không đổi | Chưa làm |
| C4 | Cắt bớt cột thừa trước các phép nối lớn ở FactSnapshot | Vừa | Thấp | Chỉ bỏ cột không dùng, giữ nguyên khóa | Chưa làm |
| C5 | Dời bộ lọc lên sớm hơn (nếu tương đương) | Thấp–Vừa | Có, nếu vượt qua khử trùng/latest | Layer A phải xanh | Chưa làm |

**Ràng buộc chung:** không giải pháp nào được đổi ngữ nghĩa của `InventorySnapshotWeekly` (đang bị khóa, chờ US/DA). Giữ nguyên "ghi đè toàn bộ" cho tới khi chứng minh được cửa sổ dữ liệu có thể thay đổi + parity thời gian.

### Giải pháp ưu tiên: C1 chi tiết
- **Cách cũ (A):** 3 bảng weekly, mỗi bảng tự quét 705 triệu dòng → tự khử trùng → tự dùng. Làm 3 lần.
- **Cách mới (B):** khử trùng 1 lần bằng `ROW_NUMBER() OVER (PARTITION BY ItemSku, WarehouseCode, SnapshotWeekEndingDate ORDER BY FiscalMonthDate ASC) = 1`, mang theo sẵn các cột cần: OnHandQty, MakeBuyCode, PrimaryVendorName, SecondaryVendorName, ReplenishmentLeadTime, SnapshotType. Cả 3 bảng dùng chung kết quả này.
  - FactSnapshot: sau khi gom chung, lọc thêm khóa không NULL + `SnapshotType IN ('WEEKLY','WEEKLY_AND_LATEST')`.
  - SubStatus/ClassQty: dùng thẳng bề mặt chung (không lọc thêm).

---

## PHẦN E — ĐÃ KIỂM CHỨNG THẾ NÀO (bằng chứng C1)

Nguyên tắc so sánh: chạy **logic cũ (A)** và **logic mới (B)** trên **cùng dữ liệu thật**, so 2 chiều từng dòng + từng giá trị. Chỉ đọc, không tạo object nào trên Fabric.

### E.1. Chạy thử phạm vi nhỏ (8 tuần gần nhất) — PASS
`runs/20260711T021117Z_shadow_parity_c1.*`

| Kiểm tra | Kết quả |
|---|---|
| Khử trùng + biến thiên cột mang theo | 833,223 nhóm; hòa FiscalMonthDate=0; cột lệch=0 |
| Đếm bề mặt chung | rn1=833,223; fact_eligible=729,407 |
| Phân bố SnapshotType | WEEKLY=729,407; LATEST=103,816 |
| FactSnapshot A-vs-B (so cả dòng) | a=b=833,223; a∉b=0; b∉a=0 |
| SubStatus A-vs-B | a=b=833,223; a∉b=0; b∉a=0 |

### E.2. Chạy trên TOÀN BỘ lịch sử (19,6 triệu dòng) — PASS
`runs/20260711T022510Z_shadow_parity_c1.*`

| Kiểm tra | Kết quả |
|---|---|
| Biến thiên trong nhóm | 19,605,162 nhóm; hòa FMD=0; TẤT CẢ cột mang theo lệch=**0** |
| Đếm bề mặt chung | rn1=19,605,162; fact_eligible=19,501,346 |
| Phân bố SnapshotType | WEEKLY=19,501,346; LATEST=103,816; loại bỏ=103,816 |
| Bất biến | shared == nhóm weekly **True**; fact_eligible == bảng FactSnapshot **True** |
| FactSnapshot A-vs-B (khóa + giá trị) | a=b=**19,605,162**; a∉b=0; b∉a=0; **value_mismatches=0** (189s) |
| SubStatus A-vs-B | a=b=**19,605,162**; a∉b=0; b∉a=0; **value_mismatches=0** (265s) |

### E.3. Kiểm chứng downstream + đo tốc độ nền (Module 05)

**Layer F — view vs bảng thật, cả 9 bảng PASS, 0 lệch** (số dòng khớp Phần C.3 chính xác):

| Bảng | bảng.n | view.n | lệch | thời gian |
|---|---:|---:|---:|---:|
| DimCalendar | 21,551 | 21,551 | 0 | 0.6s |
| DimProduct | 783,945 | 783,945 | 0 | 0.7s |
| DimWarehouse | 53 | 53 | 0 | 0.7s |
| DimVendor | 87,003 | 87,003 | 0 | 0.6s |
| InventoryHealthSubStatusWeekly | 19,605,162 | 19,605,162 | 0 | 124.3s |
| InventoryClassificationQtyWeekly | 19,605,162 | 19,605,162 | 0 | 113.0s |
| ProjectedInventoryHealthSubStatus | 3,785,137 | 3,785,137 | 0 | 325.1s |
| FactInventoryHealthFutureWeekEnding | 3,785,137 | 3,785,137 | 0 | 670.8s |
| FactInventoryHealthSnapshot | 19,501,346 | 19,501,346 | 0 | 97.6s |

**Layer D e2e — so cả dòng cho 2 bảng nhỏ, cả 2 PASS:**

| Bảng | a_rows | b_rows | a∉b | b∉a | value_mismatches | pass |
|---|---:|---:|---:|---:|---:|---|
| InventoryHealthSubStatusWeekly | 19,605,162 | 19,605,162 | 0 | 0 | 0 | ✔ |
| InventoryClassificationQtyWeekly | 19,605,162 | 19,605,162 | 0 | 0 | 0 | ✔ |

**Layer G — mốc tốc độ (Wave 1 phải vượt mốc này):** nguồn `queryinsights.exec_requests_history`, cửa sổ 30 ngày, run `20260711T084148Z`.
- Tổng thời gian trung vị của chuỗi = **643s**; tổng lượng quét từ xa trung vị = **10,150 MB**.
- Điểm nóng: `FactInventoryHealthFutureWeekEnding` p95=886s (nặng về tính toán); `FactInventoryHealthSnapshot` quét trung vị=5,154 MB (nặng về quét); `InventoryHealthSubStatusWeekly` quét trung vị=3,703 MB.

### E.4. Diễn giải kết quả kiểm chứng
1. **R3 đã đóng:** thứ tự `FiscalMonthDate ASC` là xác định (0 hòa). Các cột mang theo là hằng số trong mỗi nhóm → chọn dòng nào cũng ra đúng cho MỌI cột, không chỉ OnHandQty.
2. **Lọc-NULL-trước hay khử-trùng-trước rồi lọc-NULL đều tương đương** trên nguồn này (A-vs-B rỗng cả 2 chiều).
3. **Chênh lệch Δ=103,816 hoàn toàn do SnapshotType** (toàn bộ dòng LATEST), không do gì khác.
4. **Kết luận C1: logic PASS.** NHƯNG điều này **chưa** chứng minh: (a) parity end-to-end toàn bảng Gold (các phép JOIN/CASE của từng view vẫn chạy riêng), (b) lợi ích tốc độ thực tế (chưa materialize gì), (c) chưa cho phép deploy production.

---

## PHẦN F — RÀNG BUỘC BẢO VỆ BÁO CÁO (HARD CONSTRAINT — bắt buộc)

Báo cáo Power BI `sc_control_tower` (Direct Lake trên `SupplyChain_Gold_Warehouse`) đã bind visual/measure/relationship vào **các bảng Gold vật lý hiện tại**. Cùng mặt báo cáo đó còn dùng cả các bảng Forecast Accuracy Gold. Dựng lại lớp báo cáo là công sức người rất lớn, **không** phải cái giá chấp nhận được cho một việc tối ưu ETL.

Vì vậy mọi giải pháp phải tối ưu **tại chỗ** và tuân thủ:

1. **Giữ nguyên danh tính bảng vật lý.** Ghi vào **đúng bảng đích cũ** (cùng database, schema, tên bảng), giữ tập cột / thứ tự cột / kiểu dữ liệu / nullability / khóa **tương thích từng byte**. Không tạo bảng tên mới, không `_v2`, không đổi tên/đổi thứ tự/đổi kiểu cột.
2. **Sửa "nơi sản xuất", không sửa "hợp đồng".** Chỉ được sửa: logic view `_Wrk.v_*`, các bước trung gian dùng chung, CTE/JOIN, vị trí bộ lọc, cơ chế nạp. Hình dạng đầu ra hướng báo cáo bị đóng băng.
3. **Direct Lake phải sống sót.** Sau khi nạp bằng giải pháp mới, cột + khóa của bảng phải vẫn thỏa mọi binding hiện tại — **0 chỉnh sửa** measure/relationship/visual. Bất kỳ thay đổi nào buộc phải sửa lại báo cáo đều bị **từ chối** dù nhanh tới đâu.
4. **Áp dụng cho cả 2 mart.** Luật này phủ Inventory Health Gold bây giờ, và bất kỳ bảng Forecast Accuracy Gold nào đụng tới sau này.

Nếu một thiết kế nhanh hơn **không thể** thực hiện mà không đổi bảng vật lý → nó **không** đi theo plan này; nó trở thành một dự án di trú báo cáo riêng, có phạm vi + ước lượng công sức riêng, cần chủ sở hữu duyệt.

> **Vì sao C1 hợp lệ:** C1 chỉ đổi logic `inv_base` dùng chung đứng trước lệnh `INSERT ... SELECT *` ghi vào **đúng bảng vật lý cũ**. Không tạo/không repoint bất kỳ object nào mà báo cáo đang nhìn vào.

---

## PHẦN G — CÁC BƯỚC TRIỂN KHAI (STEP-BY-STEP)

### Wave 0 — Khám bệnh + dựng bộ kiểm chứng ✅ ĐÃ XONG
- [x] Đọc hợp đồng nghiệp vụ 9 bảng Gold (Layer A).
- [x] Dò 3 rủi ro R1/R2/R3 (Layer B) → đều an toàn; tìm ra thủ phạm quét-lặp-3-lần.
- [x] Đóng băng chuẩn vàng số liệu 9 bảng (Layer C).
- [x] Chứng minh C1 parity logic trên toàn bộ 19,6 triệu dòng (Layer D) → 0 lệch.
- [x] Kiểm chứng downstream 9 bảng (Layer F) + đo mốc tốc độ (Layer G).
- [x] Chốt ràng buộc bảo vệ báo cáo (Phần F) thành gate chặn.

### Wave 1 — Thí điểm 1 giải pháp cho điểm nóng nhất ⏳ CHỜ DUYỆT
- [ ] **Cần bạn duyệt trước** (gate ở Phần H) cho candidate C1 in-place trên chuỗi `inv_base → FactSnapshot / SubStatus / ClassQty`.
- [ ] Dựng bản shadow của C1 và chạy **toàn bộ** bộ kiểm chứng parity (Layer A→G).
- [ ] Đo tốc độ thực tế, phải **vượt mốc** 643s / 10,150 MB ở Layer G.
- [ ] Không dùng kiểu "DateRange" chỉ vì có sẵn cột ngày.

### Wave 2 — Tối ưu tiếp theo chuỗi phụ thuộc
- [ ] Xử lý candidate tiếp theo (C2/C3/C4) theo thứ tự phụ thuộc.
- [ ] Sau mỗi thay đổi, chạy lại toàn bộ downstream + smoke test báo cáo.

### Wave 3 — Rà soát toàn tầng Gold phục vụ báo cáo
- [ ] Mở rộng bộ kiểm chứng cho các bảng Gold còn lại bind vào `sc_control_tower`.
- [ ] Tách bạch tối ưu "dữ liệu sẵn sàng" (ETL) khỏi tối ưu "semantic/model/query"; không đổi ngữ nghĩa nếu chưa có bằng chứng + duyệt riêng.

---

## PHẦN H — CÁC CỔNG DUYỆT (release gates — bắt buộc trước khi deploy)

1. Hợp đồng nghiệp vụ hoàn tất, hoặc mọi điểm mơ hồ còn lại được chủ sở hữu chấp nhận rõ ràng.
2. Các test static/source/target/parity/behavioral/downstream/performance đều PASS.
3. Mọi khác biệt quan sát được đều được giải thích + duyệt + ghi lại; nếu không thì **0 khác biệt không giải thích được**.
4. Lợi ích đo được đủ lớn để bù cho độ phức tạp thêm.
5. Rollback đã test hoặc chứng minh được là làm được mà không mất dữ liệu.
6. **Aric duyệt tường minh** đúng object live / cách làm / phạm vi chạy + kiểm chứng.
7. **Chứng minh bảo vệ báo cáo (Phần F):** sau candidate, bảng vật lý giữ nguyên cột/thứ tự/kiểu/khóa; binding Direct Lake của `sc_control_tower` giải quyết không đổi; **0** measure/relationship/visual phải sửa. Kiểm bằng: diff cột/kiểu/khóa của bảng trước-vs-sau + 1 smoke query chỉ-đọc lên `sc_control_tower`.

---

## PHẦN I — MỤC TIÊU CUỐI CÙNG (nhắc lại để mọi bước bám theo)

> **Làm dây chuyền Inventory Health Gold chạy nhanh hơn và tốn ít tài nguyên hơn, với điều kiện: (1) số liệu ra GIỐNG HỆT hệ thống cũ đến từng dòng từng giá trị — có bằng chứng, không đoán; (2) báo cáo Power BI `sc_control_tower` KHÔNG phải sửa một chữ nào; (3) mỗi thay đổi phải đảo ngược được (rollback) và được Aric duyệt tường minh trước khi lên production.**

Bất kỳ giải pháp nào cải thiện tốc độ nhưng gây ra dù chỉ **một** khác biệt nghiệp vụ không giải thích được → **bị từ chối**. Số dòng ít hơn, ít JOIN hơn, lịch sử hẹp hơn... chỉ là lựa chọn kỹ thuật, **không** phải bằng chứng đúng.

---

## PHẦN J — TRẠNG THÁI & BƯỚC KẾ TIẾP

- **Trạng thái:** Wave 0 hoàn tất. C1 chứng minh logic PASS. Chưa đụng production. Bộ kiểm chứng sẵn sàng tái sử dụng.
- **Còn thiếu:** con số "nhanh hơn bao nhiêu %" thực tế (chỉ có sau khi thật sự làm Wave 1).
- **Bước kế tiếp cần bạn quyết:** duyệt mở gate Wave 1 cho C1 in-place. Chỉ sau khi duyệt tường minh mới có bất kỳ thay đổi object production nào, và luôn theo nguyên tắc in-place ở Phần F.

### Vị trí file & công cụ
- Kế hoạch (file này): `01_docs/plans/2026-07-10-inventory-gold-business-parity-optimization-plan.md`
- Bộ công cụ kiểm chứng (chỉ đọc): `05_tools/03_gold_parity/`
  - `01_contract_inventory.py`, `02_risk_probes.py`, `03_baseline_capture.py`, `04_shadow_parity.py`, `05_downstream_perf.py`, `lib_conn.py`
  - Hợp đồng + chuẩn vàng: `contracts/*.contract.json`, `contracts/*.baseline.json`
  - Log các lần chạy: `runs/`
- Các plan cũ đã hoàn thành: đã chuyển vào `99_archive/plans_archive_20260712/` (bao gồm file evidence pack gốc, snapshot-load migration, PO daterange, demandforecast, bronze DQ, load-pattern bench/validation, lineage portal, wrk-view contract, sqlproj package).
