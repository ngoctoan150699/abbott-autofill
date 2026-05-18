# Abbott Auto Fill Extension

Extension này hỗ trợ mở link / đọc QR và auto fill trang Abbott sau khi trình duyệt đã được fake vị trí bằng GeoSpoof.

## 1. Vị trí bắt buộc

Tọa độ cần đặt trong GeoSpoof:

```text
Latitude: 15.1151
Longitude: 108.7905
```

Địa chỉ:

```text
Bệnh viện Đa khoa tỉnh Quảng Ngãi,
Trần Tế Xương, Trần Phú,
Phường Nghĩa Lộ, Tỉnh Quảng Ngãi, Việt Nam
```

Extension sẽ kiểm tra `navigator.geolocation` trước khi fill.
Nếu vị trí hiện tại lệch quá xa tọa độ này, extension sẽ dừng và yêu cầu bật GeoSpoof trước.

## 2. Cách dùng với GeoSpoof

1. Cài / bật GeoSpoof.
2. Nhập tọa độ:
   - `15.1151`
   - `108.7905`
3. Bật **Location Protection**.
4. Reload trang Abbott.
5. Mở Abbott Auto Fill Extension.
6. Dán token ViOTP.
7. Dán link hoặc kéo ảnh QR vào popup.
8. Bấm **Mở / Reload link**.
9. Bấm **Lấy số ViOTP** để thuê số Abbott.
10. Sau khi web gửi mã, bấm **Lấy OTP** để poll OTP từ ViOTP.
11. Sau khi trang load xong, bấm **Auto fill trang hiện tại**.

> Bắt buộc phải chuyển vị trí trước rồi mới auto fill.

## 3. Trang được hỗ trợ

### Trang 1: SĐT / OTP

Extension nhận diện trang có:

- `SĐT`
- `Mã`
- `Gửi mã`
- `Xác thực`

Popup có các ô / nút ViOTP:

- `Token ViOTP`
- `Check token`
- `Lấy số ViOTP`
- `Lấy OTP`
- `Số điện thoại`
- `OTP / Mã`

Lệnh **Check token**:

1. Gọi `GET https://api.viotp.com/service/getv2?token={TOKEN}&country=vn`.
2. Nếu `status_code == 200` và `success != false` thì token hợp lệ.
3. Nếu tìm thấy service có tên chứa `abbott`, lưu luôn `serviceId` để dùng khi thuê số.
4. Nếu token lỗi, hiển thị `message` từ API.

Luồng lấy số và OTP giống ứng dụng:

1. Gọi `GET https://api.viotp.com/service/getv2?token={TOKEN}&country=vn`.
2. Tìm service có tên chứa `abbott`.
3. Gọi `GET https://api.viotp.com/request/getv2?token={TOKEN}&serviceId={SERVICE_ID}`.
4. Lấy `phone_number`, thêm `0` đầu nếu thiếu.
5. Lưu `request_id`.
6. Gọi `GET https://api.viotp.com/session/getv2?requestId={REQUEST_ID}&token={TOKEN}` mỗi giây.
7. Poll tối đa 60 giây.
8. Khi `Status == 1`, lấy `Code` làm OTP.
9. Copy số / OTP vào clipboard và lưu vào popup.

Khi bấm **Auto fill trang hiện tại**, extension sẽ:

1. Kiểm tra vị trí đã đúng BVĐK Quảng Ngãi.
2. Fill SĐT vào ô `SĐT` nếu đã lấy số.
3. Fill OTP vào ô `Mã` nếu đã lấy OTP.

OTP được nhận diện ưu tiên theo:

- `autocomplete="one-time-code"`
- `maxlength="6"`
- `type="tel"`
- label / text chứa `Mã`, `otp`, `code`, `xác thực`

### Trang 2: Form người tham dự

Extension nhận diện trang có các trường:

- Vai trò
- Bệnh viện
- Phòng ban / Khoa
- Chức danh
- Đồng ý và chấp nhận

Extension fill:

| Trường | Giá trị |
|---|---|
| Vai trò | `Nguoi tham du` |
| Bệnh viện | `BENH VIEN DA KHOA TINH QUANG NGAI` |
| Khoa | Parse từ danh sách người tham dự |
| Chức danh | Parse từ danh sách người tham dự |

## 4. Cài extension local

Mở Chrome / Edge:

```text
chrome://extensions
```

Sau đó:

1. Bật **Developer mode**.
2. Chọn **Load unpacked**.
3. Chọn thư mục `extension`.

## 5. Ghi chú

- QR được đọc bằng `BarcodeDetector`; nếu trình duyệt không hỗ trợ thì dán link thủ công.
- Extension không tự submit form, chỉ fill để người dùng kiểm tra.
- Nên reload trang sau khi bật GeoSpoof Location Protection.
