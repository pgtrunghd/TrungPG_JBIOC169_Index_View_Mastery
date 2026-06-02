CREATE VIEW v_bao_cao_diem AS
SELECT
    sv.ma_sv,
    sv.ho_ten,
    sv.email,
    l.ten_lop,
    COUNT(bd.id) as so_mon_hoc,
    AVG(bd.diem_so) as diem_trung_binh
FROM
    SinhVien sv
    JOIN LopHoc l ON sv.lop_id = l.id
    JOIN BangDiem bd ON sv.id = bd.sinh_vien_id
GROUP BY
    sv.id,
    sv.ma_sv,
    sv.ho_ten,
    sv.email,
    l.ten_lop;

-- Tạo View cho thống kê lớp học
CREATE VIEW v_thong_ke_lop_hoc AS
SELECT
    l.ma_lop,
    l.ten_lop,
    COUNT(DISTINCT sv.id) AS si_so,
    ROUND(AVG(bd.diem_so), 2) AS diem_trung_binh_lop,
    CASE
        WHEN AVG(bd.diem_so) >= 8.0 THEN 'Giỏi'
        WHEN AVG(bd.diem_so) >= 6.5 THEN 'Khá'
        WHEN AVG(bd.diem_so) >= 5.0 THEN 'Trung Bình'
        ELSE 'Yếu'
    END AS phan_loai_hoc_luc_lop
FROM
    LopHoc l
    LEFT JOIN SinhVien sv ON l.id = sv.lop_id
    LEFT JOIN BangDiem bd ON sv.id = bd.sinh_vien_id
GROUP BY
    l.id,
    l.ma_lop,
    l.ten_lop;

-- Tạo Materialized View cho báo cáo tổng hợp toàn trường
CREATE MATERIALIZED VIEW mv_thong_ke_toan_truong AS
SELECT
    que_quan,
    gioi_tinh,
    COUNT(*) as so_luong,
    AVG(diem_trung_binh) as diem_tb_tinh
FROM
    v_bao_cao_diem
GROUP BY
    que_quan,
    gioi_tinh;

-- Định kỳ làm mới dữ liệu khi có sự thay đổi ở bảng gốc:
-- REFRESH MATERIALIZED VIEW mv_thong_ke_toan_truong;