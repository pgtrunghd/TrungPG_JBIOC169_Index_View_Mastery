# Đánh giá Index Optimization — Phân tích thực nghiệm

> Phân tích cho [01_index_optimization.sql](01_index_optimization.sql)
> Môi trường đo: PostgreSQL (Postgres.app), database `postgres`, bảng `SinhVien` = **3.000.000 dòng**.
> Phương pháp: chạy `EXPLAIN (ANALYZE, BUFFERS)` 2 lần (lần 1 làm nóng cache, lấy lần 2). Đo write bằng `BEGIN … ROLLBACK` để không làm bẩn dữ liệu (việc bảo trì index vẫn diễn ra trong transaction nên thời gian vẫn chính xác). Raw plan lưu trong [bench_out/](bench_out/).

---

## Tóm tắt nhanh

| Hạng mục | Kết quả |
|---|---|
| Truy vấn nhanh nhất sau index | Q1 email: **928× nhanh hơn** (42.7 ms → 0.046 ms) |
| Truy vấn lợi ít nhất | Q4 composite: **2.3× nhanh hơn** (144 ms → 62 ms) |
| Chi phí INSERT | **+97%** (chậm ~2×) khi có 4 index |
| Chi phí UPDATE cột-được-index | **+278%** (chậm ~3.8×) — chi phí bảo trì thuần |
| Dung lượng 4 index | **234 MB** = 27.9% kích thước bảng, **10.9% toàn database** |
| Index đắt nhất | `idx_sinhvien_email` = **172 MB** (gấp ~8× ba index còn lại) |

---

## 3.1. Phân tích Query Plans (EXPLAIN trước/sau Index)

### Q1 — Tìm theo email ([01_index_optimization.sql:4](01_index_optimization.sql#L4))
Trả về 1 dòng (email là duy nhất trong 3M dòng).

| | Trước index | Sau index |
|---|---|---|
| Plan | **Parallel Seq Scan** (2 workers) | **Index Scan** `idx_sinhvien_email` |
| Cost (est.) | `1000.00 .. 70840.10` | `0.56 .. 8.57` |
| Execution Time | **42.684 ms** | **0.046 ms** |

**Tăng tốc ~928×**, cost giảm ~8.000×. Đây là trường hợp lý tưởng của index: lọc bằng (`=`) trên cột có tính phân biệt (cardinality) cực cao → đi thẳng đến đúng 1 dòng thay vì quét toàn bảng 442 MB.

### Q2 — JOIN qua khóa ngoại `lop_id = 1` ([01_index_optimization.sql:15](01_index_optimization.sql#L15))
Khớp ~6.000 dòng.

| | Trước index | Sau index |
|---|---|---|
| Plan | Parallel Seq Scan + Nested Loop | **Bitmap Index Scan** `idx_sinhvien_lop_id` → Bitmap Heap Scan |
| Cost (est.) | `… .. 71476.71` | `… .. 17372.11` |
| Execution Time | **44.132 ms** | **7.157 ms** |

**Tăng tốc ~6.2×.** Planner chọn *Bitmap* (không phải Index Scan thuần) vì 6.000 dòng nằm rải rác trên nhiều block — bitmap gom block lại rồi đọc tuần tự, tối ưu I/O hơn.

### Q3 — `COUNT(*)` theo `que_quan = 'Hà Nội'` ([01_index_optimization.sql:30](01_index_optimization.sql#L30))
Khớp ~600.000 dòng (20% bảng).

| | Trước index | Sau index |
|---|---|---|
| Plan | Parallel Seq Scan | **Parallel Index Only Scan** `idx_sinhvien_que_quan` (Heap Fetches: 0) |
| Cost (est.) | `… .. 71470.02` | `… .. 10760.11` |
| Execution Time | **55.128 ms** | **11.420 ms** |

**Tăng tốc ~4.8×.** Điểm hay: dùng **Index Only Scan** với `Heap Fetches: 0` — vì `COUNT(*)` chỉ cần biết "có bao nhiêu khóa trong index", **không cần chạm vào heap** (bảng) chút nào. Index 21 MB nhỏ hơn nhiều so với heap 442 MB nên quét nhanh hơn dù vẫn phải đọc toàn bộ index.

### Q4 — Composite `gioi_tinh='Nam' AND que_quan='Hà Nội'` ([01_index_optimization.sql:41](01_index_optimization.sql#L41))
Khớp ~300.000 dòng (10% bảng).

| | Trước index | Sau index |
|---|---|---|
| Plan | Seq Scan | **Bitmap Index Scan** `idx_sinhvien_gioitinh_quequan` → Bitmap Heap Scan (54.215 heap blocks) |
| Cost (est.) | `0.00 .. 99215.00` | `4176.69 .. 62957.93` |
| Execution Time | **144.330 ms** | **61.823 ms** |

**Tăng tốc chỉ ~2.3×** — thấp nhất nhóm. Lý do: phải lấy thực 300.000 dòng và để làm vậy vẫn phải đọc **54.215 block** — gần như toàn bộ block của bảng. Khi tỷ lệ khớp lớn (10–20%), lợi thế của index giảm dần vì chi phí *random heap fetch* tiệm cận chi phí quét tuần tự.

### Quy luật rút ra
Lợi ích của index **tỷ lệ nghịch với tỷ lệ dòng khớp** (selectivity):

| Query | % dòng khớp | Tăng tốc |
|---|---|---|
| Q1 email | ~0.00003% (1 dòng) | **928×** |
| Q2 lop_id | ~0.2% | 6.2× |
| Q3 que_quan | ~20% | 4.8× (nhờ Index Only Scan) |
| Q4 composite | ~10% | 2.3× |

---

## 3.2. Đánh giá Trade-off

### A. Chi phí ghi — INSERT (đo trên 50.000 dòng)

| | Thời gian | Chênh lệch |
|---|---|---|
| **Không** 4 index (chỉ pkey + ma_sv) | 277.4 ms | — |
| **Có** 4 index | 546.6 ms | **+97% (~2× chậm)** |

Mỗi dòng INSERT phải cập nhật thêm 4 cây B-tree → gần gấp đôi thời gian. Đây là phép đo **sạch** cho chi phí ghi (không có mệnh đề WHERE gây nhiễu).

### B. Chi phí ghi — UPDATE

**B1. UPDATE cột được index, tìm theo dải khóa chính (đo chi phí bảo trì thuần, 50.000 dòng):**

| | Thời gian | Chênh lệch |
|---|---|---|
| **Không** index | 269.4 ms | — |
| **Có** index | 1017.4 ms | **+278% (~3.8× chậm)** |

UPDATE cột `que_quan` chạm vào 2 index liên quan (`idx_sinhvien_que_quan` + composite). Mỗi update tạo bản ghi index mới + đánh dấu bản ghi cũ là dead → chi phí cao hơn INSERT.

**B2. UPDATE tìm theo `lop_id = 1` (~6.000 dòng) — trường hợp ngược đời:**

| | Thời gian |
|---|---|
| **Không** index | 1399.5 ms |
| **Có** index | 919.6 ms — **nhanh hơn 34%!** |

> ⚠️ **Lưu ý quan trọng:** index không phải lúc nào cũng làm UPDATE chậm. Khi mệnh đề `WHERE` của UPDATE *tận dụng được* index để **tìm** dòng (thay vì Seq Scan 3M dòng), phần tăng tốc tìm kiếm có thể **lớn hơn** chi phí bảo trì index. Phép đo B1 (tìm theo PK ở cả 2 phía) mới phản ánh đúng "chi phí bảo trì thuần".

### C. Chi phí tạo index (one-time, trên 3M dòng)

| Index | Thời gian tạo |
|---|---|
| `idx_sinhvien_email` | 3.321 ms |
| `idx_sinhvien_gioitinh_quequan` | 1.802 ms |
| `idx_sinhvien_que_quan` | 1.056 ms |
| `idx_sinhvien_lop_id` | 709 ms |

### D. Dung lượng — Index chiếm bao nhiêu % database

**Toàn database** `postgres` = **2.145 MB**. Bảng `SinhVien` (object tổng) = **838 MB** = heap 442 MB + toàn bộ index 396 MB.

| Index | Dung lượng | Ghi chú |
|---|---|---|
| `idx_sinhvien_email` | **172 MB** | Lớn nhất — chuỗi email dài & 3M giá trị duy nhất |
| `idx_sinhvien_lop_id` | 21 MB | Integer, 500 giá trị |
| `idx_sinhvien_que_quan` | 21 MB | Chuỗi ngắn, chỉ 5 giá trị |
| `idx_sinhvien_gioitinh_quequan` | 21 MB | Composite, ~10 tổ hợp |
| **Tổng 4 index tự tạo** | **234 MB** | |
| *(pkey + ma_sv_key — ràng buộc có sẵn)* | *162 MB* | *không tính vào "tự tạo"* |

**Tỷ lệ:**
- 4 index tự tạo = **27.9%** kích thước bảng `SinhVien` (234 / 838 MB)
- 4 index tự tạo = **10.9%** toàn bộ database (234 / 2.145 MB)
- *Toàn bộ index* (gồm cả ràng buộc) = **47.2%** object bảng — gần bằng cả phần heap dữ liệu!

> 💡 **Phát hiện đáng chú ý:** chỉ riêng `idx_sinhvien_email` (172 MB) đã gấp **~8 lần** mỗi index còn lại (21 MB). Index trên chuỗi dài, cardinality cao tốn bộ nhớ hơn nhiều so với index trên integer / chuỗi cardinality thấp (PostgreSQL nén/chia sẻ prefix tốt khi giá trị lặp lại).

---

## Kết luận & Khuyến nghị

| Index | Tăng tốc đọc | Dung lượng | Chi phí ghi | Đánh giá |
|---|---|---|---|---|
| `idx_sinhvien_email` | **928×** | 172 MB | cao | ✅ **Rất đáng** — lợi ích áp đảo (login/lookup), dù tốn dung lượng nhất |
| `idx_sinhvien_lop_id` | 6.2× (JOIN) | 21 MB | thấp | ✅ **Nên giữ** — rẻ, cải thiện JOIN, có thể tăng tốc cả UPDATE theo lop_id |
| `idx_sinhvien_que_quan` | 4.8× | 21 MB | thấp | ✅ **Nên giữ** nếu báo cáo theo quê quán chạy thường xuyên |
| `idx_sinhvien_gioitinh_quequan` | 2.3× | 21 MB | thấp | ⚠️ **Cân nhắc** — lợi ích thấp nhất; chỉ giữ nếu truy vấn lọc đồng thời 2 cột này là phổ biến. Nếu không, đã có `idx_sinhvien_que_quan` lo phần lớn nhu cầu. |

**Nguyên tắc trade-off rút ra từ số liệu:**
1. **Read-heavy → tạo index.** Đọc nhanh 2–900×, ghi chỉ chậm ~2–4×. Nếu tỷ lệ đọc/ghi cao (điển hình hệ thống tra cứu sinh viên), index gần như luôn có lãi.
2. **Selectivity quyết định lợi ích.** Cột lọc ra ít dòng (email, FK) → index cực hiệu quả. Cột lọc ra >10–20% bảng → lợi ích giảm mạnh, cân nhắc kỹ.
3. **Dung lượng không miễn phí.** Index ngốn 10.9% database; index trên chuỗi dài đặc biệt tốn. Đừng tạo index "cho chắc".
4. **Giám sát định kỳ:** dùng `pg_stat_user_indexes.idx_scan` để phát hiện index không bao giờ được dùng (`idx_scan = 0`) và cân nhắc `DROP`.

---

*Trạng thái database sau khi đo: cả 4 index đã được khôi phục nguyên vẹn; không có dòng dữ liệu nào bị thay đổi (mọi phép đo ghi đều ROLLBACK).*
