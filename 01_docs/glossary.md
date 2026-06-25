# Glossary - Giải Thích Thuật Ngữ

Tài liệu này dành cho người đọc không muốn bị ngợp bởi thuật ngữ kỹ thuật. Object names, schema names và file paths vẫn giữ nguyên tiếng Anh để dễ grep và đối chiếu với Fabric.

## Thuật Ngữ Kiến Trúc Dữ Liệu

| Thuật ngữ | Nghĩa dễ hiểu |
|---|---|
| Mart | Một nhóm bảng phục vụ một chủ đề nghiệp vụ, ví dụ forecast accuracy hoặc inventory health. |
| Bronze | Lớp source/raw contract. Trong repo này thường ghi source active và shortcut/source table. |
| Silver | Lớp xử lý/chuẩn hóa, thường chứa bảng trung gian sạch hơn để Gold dùng. |
| Gold | Lớp serving, tức bảng gần với report/semantic/downstream nhất. |
| Semantic model | Lớp model cho Power BI/report, chứa table binding, relationship, measure. |
| Grain | Ý nghĩa của một dòng dữ liệu. Ví dụ một dòng là một item-location-week hay một invoice line. |
| Natural key | Bộ cột business dùng để nhận diện một dòng ở grain đã định nghĩa. |
| DQ | Data Quality, tức kiểm tra chất lượng dữ liệu: null, duplicate, freshness, accepted values. |
| Freshness | Độ mới của dữ liệu, thường kiểm tra bằng snapshot date, load timestamp hoặc business date đáng tin. |
| Lineage | Dòng chảy dữ liệu: object nào lấy từ source nào và tạo ra object nào. |

## Thuật Ngữ Enterprise ETL Runtime

| Thuật ngữ | Nghĩa dễ hiểu |
|---|---|
| Enterprise ETL Framework | Bộ framework vận hành load dữ liệu theo pattern của team Enterprise ETL/Enterprise. |
| `ETL_Framework` | Warehouse/framework local hiện dùng để chứa loader procs, metadata, audit tables. |
| `_Wrk` schema | Schema chứa source/work view. View trong đây là nơi đặt SQL logic tạo dữ liệu cho final table. |
| `v_<TableName>` | View nguồn cho loader. Tên view phải map với final table cùng tên. |
| Final table | Bảng vật lý cuối cùng downstream sẽ dùng. |
| `_LOAD` table | Bảng tạm/working surface do loader dùng trong quá trình load. Không phải output business. |
| Wrapper procedure | Stored procedure gọi nhiều table theo đúng thứ tự dependency/wave. |
| Loader procedure | Procedure của `ETL_Framework` thực hiện load pattern: full, incremental, SCD, date-range, v.v. |
| `TableDictionary` | Bảng metadata đăng ký table, source view, load pattern, SLA/freshness fields. |
| `AuditLog` | Bảng log runtime: process start, complete, error, duration. |

## Thuật Ngữ CI/CD Và SQLPROJ

| Thuật ngữ | Nghĩa dễ hiểu |
|---|---|
| CI | Continuous Integration. Mỗi thay đổi SQL được build/validate tự động trước khi merge/deploy. |
| CD | Continuous Delivery/Deployment. Đưa object đã review lên environment theo quy trình có gate. |
| SQLPROJ | SQL project, tức project đóng gói schema/table/view/procedure thành source có thể build. |
| `.dacpac` | Artifact build từ SQLPROJ, dùng để so sánh/deploy SQL object. |
| DeployReport | Báo cáo cho reviewer biết deploy sẽ thay đổi object gì. |
| Publish | Hành động deploy object lên warehouse/environment. Không đồng nghĩa với refresh dữ liệu. |
| Smoke test | Kiểm tra nhanh để biết object/runtime/semantic có còn sống không. |
| Semantic smoke | Kiểm tra nhanh semantic model/report binding sau khi data object thay đổi. |

## Thuật Ngữ Vận Hành

| Thuật ngữ | Nghĩa dễ hiểu |
|---|---|
| Manifest | File mô tả thứ tự chạy, scope, procedure hoặc pipeline cần gọi. |
| Dry-run | Chạy thử không mutate dữ liệu, dùng để xem sẽ làm gì. |
| Approved trigger | Lệnh chạy live đã được approve rõ trong cùng conversation. |
| SQL Agent | Scheduler/runner phía enterprise có thể gọi stored procedure theo lịch. |
| Wave | Nhóm object cùng tầng dependency. Wave trước chạy xong thì wave sau mới nên chạy. |
| Context | Nhật ký làm việc của repo, giúp phiên sau resume đúng trạng thái. |
| Current truth | Trạng thái đúng mới nhất. Với live object, phải scan live nếu có nghi ngờ drift. |
