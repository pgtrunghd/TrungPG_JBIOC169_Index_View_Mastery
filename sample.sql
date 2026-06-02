-- Bảng sinh viên (3 triệu records)
CREATE TABLE SinhVien (
    id SERIAL PRIMARY KEY,
    ma_sv VARCHAR(20) UNIQUE,
    ho_ten VARCHAR(100) NOT NULL,
    email VARCHAR(150) NOT NULL,
    gioi_tinh VARCHAR(10),
    que_quan VARCHAR(100),
    ngay_sinh DATE,
    lop_id INTEGER,
    created_at TIMESTAMP DEFAULT NOW()
);

-- Bảng lớp học (500 records)
CREATE TABLE LopHoc (
    id SERIAL PRIMARY KEY,
    ma_lop VARCHAR(20) UNIQUE,
    ten_lop VARCHAR(100),
    khoa_id INTEGER
);

-- Bảng điểm (15 triệu records - mỗi SV có ~5 môn)
CREATE TABLE BangDiem (
    id SERIAL PRIMARY KEY,
    sinh_vien_id INTEGER,
    mon_hoc_id INTEGER,
    diem_so DECIMAL(4, 2),
    hoc_ky VARCHAR(10),
    created_at TIMESTAMP DEFAULT NOW()
);

-- Bảng môn học (200 records)
CREATE TABLE MonHoc (
    id SERIAL PRIMARY KEY,
    ma_mon VARCHAR(20) UNIQUE,
    ten_mon VARCHAR(100)
);

-- =====================================================================
-- STEP 1: Chèn dữ liệu danh mục cho bảng LopHoc (Tạo đủ 500 lớp)
-- =====================================================================
INSERT INTO
    LopHoc (ma_lop, ten_lop, khoa_id)
SELECT
    'LH' || LPAD(i :: text, 4, '0'),
    'Lớp học chuyên ngành số ' || i,
    (i % 10) + 1 -- Gán ngẫu nhiên vào 10 khoa khác nhau
FROM
    generate_series(1, 500) AS i;

-- =====================================================================
-- STEP 2: Chèn dữ liệu danh mục cho bảng MonHoc (Tạo đủ 200 môn)
-- =====================================================================
INSERT INTO
    MonHoc (ma_mon, ten_mon)
SELECT
    'MH' || LPAD(i :: text, 4, '0'),
    'Môn học lý thuyết + thực hành ' || i
FROM
    generate_series(1, 200) AS i;

-- =====================================================================
-- STEP 3: Chèn dữ liệu cho bảng SinhVien (Tạo đúng 3 triệu records)
-- =====================================================================
-- Chèn trước 1 bản ghi cụ thể theo yêu cầu đề bài để test EXPLAIN ANALYZE
INSERT INTO
    SinhVien (
        ma_sv,
        ho_ten,
        email,
        gioi_tinh,
        que_quan,
        ngay_sinh,
        lop_id
    )
VALUES
    (
        'SV0000001',
        'Nguyễn Văn Nam',
        'nam.nguyen@techmaster.edu.vn',
        'Nam',
        'Hà Nội',
        '2004-05-15',
        1
    );

-- Chèn 2,999,999 bản ghi ngẫu nhiên còn lại bằng Bulk Insert
INSERT INTO
    SinhVien (
        ma_sv,
        ho_ten,
        email,
        gioi_tinh,
        que_quan,
        ngay_sinh,
        lop_id
    )
SELECT
    'SV' || LPAD(i :: text, 7, '0'),
    'Sinh Viên Toàn Trường ' || i,
    'sinhvien_' || i || '@techmaster.edu.vn',
    CASE
        WHEN i % 2 = 0 THEN 'Nam'
        ELSE 'Nữ'
    END,
    CASE
        WHEN i % 5 = 0 THEN 'Hà Nội'
        WHEN i % 5 = 1 THEN 'Hải Phòng'
        WHEN i % 5 = 2 THEN 'Đà Nẵng'
        WHEN i % 5 = 3 THEN 'TP HCM'
        ELSE 'Quảng Ninh'
    END,
    '2003-01-01' :: date + (i % 730) * '1 day' :: interval,
    -- Ngày sinh ngẫu nhiên từ 2003-2004
    (i % 500) + 1 -- Phân bổ đều vào 500 lớp đã tạo ở trên
FROM
    generate_series(2, 3000000) AS i;

-- =====================================================================
-- STEP 4: Chèn dữ liệu cho bảng BangDiem (Tạo đúng 15 triệu records)
-- =====================================================================
-- Tạo vòng lặp cross-join có giới hạn: mỗi sinh viên lấy ngẫu nhiên 5 môn học khác nhau
INSERT INTO
    BangDiem (sinh_vien_id, mon_hoc_id, diem_so, hoc_ky)
SELECT
    sv_id,
    mh_id,
    ROUND((RANDOM() * 10) :: numeric, 2),
    -- Sinh điểm số ngẫu nhiên từ 0.00 đến 10.00
    'HK1-2026'
FROM
    (
        -- Sử dụng subquery để sinh cặp liên kết (1 sinh viên x 5 môn học liên tiếp)
        SELECT
            s.id AS sv_id,
            ((s.id * 5 + m) % 200) + 1 AS mh_id
        FROM
            SinhVien s
            CROSS JOIN generate_series(1, 5) AS m
    ) AS temp_data;
