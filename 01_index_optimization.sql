-- =====================================================================
-- Trade-off chung của Index:
--   + Lợi ích: ĐỌC (SELECT/JOIN) nhanh hơn nhiều.
--   - Trade-off: GHI (INSERT/UPDATE/DELETE) chậm hơn + tốn thêm dung lượng đĩa.
-- =====================================================================

-- 1. Index cho email (Tối ưu truy vấn tìm kiếm đơn lẻ theo tài khoản)
-- Trade-off:
--   + Lợi ích: tìm theo email rất nhanh (email là duy nhất -> lọc ra đúng 1 dòng).
--   - Trade-off: là index lớn nhất (email là chuỗi dài) nên tốn dung lượng,
--              và làm INSERT chậm hơn.
CREATE INDEX idx_sinhvien_email ON SinhVien(email);

EXPLAIN ANALYZE
SELECT
    *
FROM
    SinhVien
WHERE
    email = 'nam.nguyen@techmaster.edu.vn';

-- 2. Index cho khóa ngoại lop_id (Tối ưu hóa các câu lệnh JOIN giữa SinhVien và LopHoc)
-- Trade-off:
--   + Lợi ích: JOIN giữa SinhVien và LopHoc nhanh hơn.
--   - Trade-off: tốn thêm dung lượng (index nhỏ nên chi phí ghi không đáng kể).
CREATE INDEX idx_sinhvien_lop_id ON SinhVien(lop_id);

EXPLAIN ANALYZE
SELECT
    sv.id,
    sv.ma_sv,
    sv.ho_ten,
    l.ten_lop
FROM
    SinhVien sv
    JOIN LopHoc l ON sv.lop_id = l.id
WHERE
    sv.lop_id = 1;

-- 3. Index cho que_quan (Phục vụ truy vấn, thống kê lọc theo địa phương)
-- Trade-off:
--   + Lợi ích: lọc/đếm theo que_quan nhanh hơn (COUNT dùng được Index Only Scan).
--   - Trade-off: que_quan chỉ có vài giá trị (mỗi giá trị ~20% số dòng) nên lợi ích
--              vừa phải; vẫn tốn dung lượng và làm INSERT/UPDATE chậm hơn.
CREATE INDEX idx_sinhvien_que_quan ON SinhVien(que_quan);

EXPLAIN ANALYZE
SELECT
    COUNT(*)
FROM
    SinhVien
WHERE
    que_quan = 'Hà Nội';

-- 4. Index composite cho (gioi_tinh, que_quan) (Tối ưu báo cáo tổng hợp kết hợp đồng thời cả 2 điều kiện)
-- Trade-off:
--   + Lợi ích: lọc đồng thời cả gioi_tinh và que_quan trong 1 lần quét index.
--   - Trade-off: là index thứ 4 -> tốn thêm dung lượng + chi phí ghi; gioi_tinh chỉ
--              có 2 giá trị nên lọc ra rất nhiều dòng, lợi ích ít nhất trong nhóm.
CREATE INDEX idx_sinhvien_gioitinh_quequan ON SinhVien(gioi_tinh, que_quan);

EXPLAIN ANALYZE
SELECT
    ma_sv,
    ho_ten,
    email
FROM
    SinhVien
WHERE
    gioi_tinh = 'Nam'
    AND que_quan = 'Hà Nội';