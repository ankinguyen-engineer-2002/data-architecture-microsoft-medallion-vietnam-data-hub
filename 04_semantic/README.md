# Semantic Layer

Folder này dành cho semantic/report contract.

Nói đơn giản:

```text
Gold table là dữ liệu phục vụ báo cáo.
Semantic model là lớp Power BI dùng để hiểu table, relationship và measure.
```

Định hướng hiện tại là shared SupplyChain semantic layer, thay vì giữ vĩnh viễn một semantic model riêng cho từng mart.

## Quy Tắc Hiện Tại

- Mart folders ghi table/view logic.
- `04_semantic/` ghi semantic contract, smoke tests và model artifacts.
- Không update live semantic/report definition nếu chưa có approval rõ và rollback export.

## Khi Warehouse Object Thay Đổi

Nếu Gold table hoặc shared table thay đổi, cần nghĩ tới:

```text
table binding còn đúng không
column có bị rename/drop không
relationship có còn hợp lệ không
measure có còn chạy không
report visual có bị ảnh hưởng không
```

## Smoke Gate Khuyến Nghị

1. Export TMDL/PBIR trước khi mutate live semantic/report.
2. Validate table bindings.
3. Run DAX row-count smoke nếu phù hợp.
4. Validate critical measures.
5. Chỉ update live definition khi có approval và rollback path.

## Folder Chính Cần Đọc

- [shared_supplychain_model/](shared_supplychain_model/)
