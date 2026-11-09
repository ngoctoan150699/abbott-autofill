# Abbott Event Helper 🏥⚡

> **Ứng dụng trợ lý chuyên nghiệp hỗ trợ điền form đăng ký sự kiện & hội thảo Abbott dành cho Windows Desktop và Android.**

[![Flutter](https://img.shields.io/badge/Flutter-v3.0+-02569B?logo=flutter)](https://flutter.dev)
[![Platform](https://img.shields.io/badge/Platform-Windows%20|%20Android-green.svg)](https://github.com/ngoctoan150699/abbott-autofill/releases)
[![Release](https://img.shields.io/github/v/release/ngoctoan150699/abbott-autofill?color=teal)](https://github.com/ngoctoan150699/abbott-autofill/releases/latest)
[![License](https://img.shields.io/badge/License-Proprietary-blue.svg)](#)

---

## 📖 Tài liệu liên quan
- 👉 **[Xem Hướng dẫn sử dụng & Quy trình vận hành chuẩn (SOP Chi tiết)](USER_GUIDE.md)**
- 📘 **[Đặc tả kỹ thuật kiến trúc hệ thống (PROJECT_DOC.md)](PROJECT_DOC.md)**

---

## 🌟 Tính năng nổi bật

### 1. 📲 Đa nguồn SIM & OTP (ViOTP + HupSMS)
- Chuyển đổi linh hoạt **1-chạm** giữa **ViOTP** (`api.viotp.net`) và **HupSMS** (`hupsms.com`).
- **Hỗ trợ đa Server (HupSMS)**: Nhận diện và cho phép chọn nhanh các Server với mức giá khác nhau (Server 247 giá 1.500đ rẻ nhất ⭐, Server 3 giá 1.800đ, Server 2 giá 3.500đ).
- **Tự động hủy đơn & Hoàn tiền thông minh**: Đếm ngược thời gian thực 60s. Sau 60s nếu không nhận được mã OTP, hệ thống tự hủy đơn để hoàn lại 100% tiền vào tài khoản HupSMS.
- **Hiển thị số dư thời gian thực**: Trực tiếp trên thanh trạng thái với chức năng bấm làm mới tức thì.

### 2. 🪄 Tự động điền dữ liệu (Auto-fill thông minh)
- Chuẩn hóa thông tin tự động: Họ tên, Chức danh, Khoa/Phòng ban chuẩn danh mục Abbott.
- Hỗ trợ trường **Phòng ban (Khác)** khi khoa được chọn là Khác.
- Tự động tích chọn checkbox Đồng ý điều khoản.
- Tùy chỉnh bật/tắt từng trường điền và độ trễ (`delay ms`) để tương thích tối đa với trang web.

### 3. 👥 Quản lý danh sách người & Profile Bệnh viện
- Tab Cài đặt 3 ngăn rộng rãi: Quản lý danh sách người tham dự, Profile danh sách Bệnh viện, và Cấu hình hệ thống.
- Tính năng **Gán Bệnh viện cho tất cả** chỉ với 1 click.
- Tự động lưu cấu hình và danh sách vào bộ nhớ máy (`%APPDATA%` trên Windows).

### 4. 💻 Giao diện Split-View tối ưu cho Windows Desktop
- Tích hợp trình duyệt nhúng **Microsoft Edge WebView2** hiện đại.
- Sidebar điều khiển 400px bên trái: Xem thông tin người hiện tại, lấy số, lấy OTP, điền form.
- Khung hiển thị trang sự kiện bên phải với thanh điều hướng (Back, Forward, Reload).
- Hỗ trợ đầy đủ phím tắt thao tác nhanh:
  - `Alt + F`: Điền thông tin người hiện tại.
  - `Alt + N` / `Alt + P`: Chuyển người tiếp theo / trước đó.
  - `Alt + ←` / `Alt + →`: Điều hướng trang web.
  - `F5`: Tải lại trang web.

---

## 🚀 Tải về & Cài đặt

Truy cập trang [Releases mới nhất](https://github.com/ngoctoan150699/abbott-autofill/releases/latest) để tải về:

| Nền tảng | Tệp tải về | Hướng dẫn sử dụng |
|---|---|---|
| **Windows Desktop** | `abbott_helper-windows-x64.zip` | Tải về, giải nén ra thư mục và nhấp đúp chạy file `abbott_helper.exe` |
| **Android** | `abbott_helper-v1.4.0.apk` | Tải về điện thoại và cài đặt trực tiếp file APK |

---

## 📋 Tóm tắt luồng quy trình vận hành (SOP)

1. **Mở link**: Dán link sự kiện Abbott vào thanh địa chỉ trên ứng dụng.
2. **Thuê số**: Bấm `[ Lấy Số ]` -> SĐT tự động copy -> Dán vào web.
3. **Gửi mã**: Bấm gửi mã trên web -> Ứng dụng tự đếm ngược 60s & polling lấy OTP. *(Nếu quá 60s không có mã, tự hủy hoàn tiền và bấm lấy số khác)*.
4. **Xác thực**: Nhận mã OTP (tự copy) -> Dán vào web và bấm xác thực để vào form thông tin.
5. **Điền form**: Bấm `[ Điền Thông Tin ]` (hoặc nhấn `Alt + F`) -> Tự động điền Họ tên, Khoa, Chức danh, BV, Checkbox.
6. **Gửi form**: Kiểm tra lại thông tin và bấm gửi form trên web.
7. **Người tiếp theo**: Bấm Back quay lại trang đầu -> Bấm `>` (hoặc nhấn `Alt + N`) để sang người tiếp theo -> Lặp lại bước 2!

*(Xem hướng dẫn chi tiết từng bước tại [USER_GUIDE.md](USER_GUIDE.md))*
