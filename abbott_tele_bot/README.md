# Abbott Auto Fill Telegram Bot

Bot Telegram tự động hóa đăng ký sự kiện hội nghị Abbott dành cho Nhân viên Y tế (`@abbott_fill_bot`).
Hỗ trợ đầy đủ tính năng: quét mã QR / nhận link URL sự kiện, tính giờ hết hạn, cấu hình ViOTP & HupSMS, chọn bệnh viện, nhập danh sách người cần đăng ký, hàng đợi tự động điền form, và **chụp ảnh màn hình thẻ form gửi về Telegram trước khi bấm Gửi**.

---

## 🎯 Tính Năng Chính

1. **Quét QR & Nhận URL Thông Minh:**
   - Gửi ảnh mã QR sự kiện hoặc gửi link URL trực tiếp.
   - Tự động trích xuất mã sự kiện `eventRecordNumber` và thời gian hết hạn `overTime`.
   - Tính toán và thông báo chính xác còn bao nhiêu giờ, phút trước khi link hết hạn.

2. **Hỗ Trợ 2 Nguồn OTP (ViOTP & HupSMS):**
   - Hỗ trợ đổi nguồn OTP linh hoạt ngay trên bàn phím Telegram.
   - Nhập API Key / Token qua chat trực tiếp hoặc file cấu hình.
   - Hỗ trợ chọn cụm Server HupSMS: **Server 247 (1.500đ)**, **Server 3 (1.800đ)**, **Server 2 (3.500đ)**.
   - Xem số dư tức thời bằng nút `💰 Số Dư OTP` hoặc lệnh `/balance`.

3. **Cấu Hình Bệnh Viện & Danh Sách Người:**
   - Chọn bệnh viện nhanh qua danh sách nút bấm hoặc gõ tên bệnh viện mới.
   - Nhập danh sách người tham gia theo định dạng linh hoạt:
     ```text
     Huỳnh thị việt trinh - Khoa Ngoại Tổng Hợp - Y tá/ Điều dưỡng
     Đặng Thị Bích Liễu - Khoa Ngoại Tổng Hợp - Y tá/ Điều dưỡng
     Cao Thị Huyền Trang - Khoa Ngoại Tổng Hợp - Bác Sỹ Điều Trị
     ```
   - Tự động map chuẩn danh mục Khoa/Phòng ban và Chức danh trên hệ thống Abbott.

4. **Tự Động Điền Form & Chụp Ảnh Thẻ Xác Nhận:**
   - Chạy hàng đợi hoàn toàn tự động bằng Headless Chromium (Playwright).
   - Tự động thuê số điện thoại, dán vào ô SĐT, bấm Gửi mã OTP.
   - Đếm ngược tối đa 60 giây để nhận OTP (nếu quá 60s tự hủy số hoàn tiền và lấy số mới).
   - Điền OTP, bấm Xác thực, điền Họ tên, Vai trò, Bệnh viện, Phòng ban, Chức danh, tích Checkbox điều khoản.
   - **📸 Chụp ảnh màn hình thẻ form xanh đậm hoàn chỉnh (giống mẫu trên mobile) và gửi lại về Telegram cho người dùng xem trước khi bấm nút Gửi.**
   - Thông báo chi tiết tiến độ từng người và tổng kết hàng đợi.

---

## 🚀 Cách Triển Khai Với Docker

### Bước 1: Cấu hình token
Tạo file `.env` cạnh `docker-compose.yml` với nội dung `BOT_TOKEN=<token bot Telegram>`. Không chia sẻ hoặc commit file này.

### Bước 2: Khởi động Container
Chạy script:
- Trên Windows: Click đúp vào `start_docker.bat`
- Hoặc chạy lệnh terminal:
  ```bash
  docker compose up -d --build
  ```

### Bước 2: Xem Logs của Bot
```bash
docker compose logs -f
```

### Bước 3: Dừng Container khi cần
- Trên Windows: Click đúp vào `stop_docker.bat`
- Hoặc chạy lệnh:
  ```bash
  docker compose down
  ```

---

## 💻 Cách Chạy Cục Bộ (Không Cần Docker)

Yêu cầu máy đã cài Python 3.10+:
```bash
cd D:\DuAn\18.Other\fill_event\abbott_tele_bot
pip install -r requirements.txt
playwright install chromium
python telegram_bot.py
```
Hoặc trên Windows chỉ cần click đúp vào `run_local.bat`.

---

## 📱 Hướng Dẫn Sử Dụng Bot Trên Telegram

1. Mở Telegram và tìm bot: **`@abbott_fill_bot`** (hoặc truy cập `https://t.me/abbott_fill_bot`).
2. Gửi lệnh `/start` để hiển thị menu điều khiển chính.
3. **Gửi URL hoặc Ảnh QR:**
   - Gửi ảnh chụp mã QR của sự kiện, bot sẽ tự quét và giải mã.
   - Hoặc dán trực tiếp link sự kiện, ví dụ:
     `https://spot.abbott.com/vn/api/activity/sign/checkScanSource?eventRecordNumber=104142&overTime=20261109143336&country=VIE`
   - Bot sẽ phân tích mã sự kiện, kiểm tra thời gian hết hạn và hiển thị thông tin.
4. **Cấu hình OTP & Bệnh viện:**
   - **Cách 1 (Qua nút bấm):** Bấm `🔑 Nguồn OTP & Token` -> Chọn nguồn (`ViOTP` hoặc `HupSMS`) -> Bấm nút `✏️ Nhập Token` hoặc `✏️ Nhập HupSMS Key` / `✏️ Nhập ViOTP Token` -> Dán token/API key vào tin nhắn rồi gửi.
   - **Cách 2 (Lệnh trực tiếp):**
     - Gửi `/hupsms <API_KEY>` để lưu API Key HupSMS.
     - Gửi `/viotp <TOKEN>` để lưu Token ViOTP.
     - Gửi `/token <KEY>` để lưu vào nguồn hiện tại.
   - Hệ thống sẽ tự động kiểm tra số dư ngay lập tức và tự động dò danh sách Server Abbott (Server 247 giá 1.500đ) để bạn chọn!
   - Bấm `🏥 Chọn Bệnh Viện` -> chọn bệnh viện trong danh sách hoặc bấm `➕ Thêm Bệnh Viện Mới`.
   - Bấm `📋 DS Người Tham Gia` -> gửi danh sách người cần điền.
5. **Bắt đầu chạy tự động:**
   - Bấm nút **`🚀 Chạy Tự Động`** hoặc gõ lệnh `/run`.
   - Bot sẽ tự động thực hiện lần lượt từng người, gửi ảnh thẻ chụp màn hình trước khi nộp, và báo kết quả thành công!
   - **Duyệt ảnh (mặc định):** Bot gửi ảnh thẻ và chờ bấm `✅ Gửi form` hoặc `⏭ Bỏ qua` tối đa 120 giây. Hết hạn, gửi ảnh lỗi hoặc dừng thì **không gửi form**; OTP có thể đã bị trừ phí.
   - **Tự động hoàn toàn:** Bot gửi ảnh rồi tự bấm Gửi. Chuyển chế độ bằng `/mode` hoặc nút `📸 Chế Độ Gửi`.
   - Gửi `/stop` nếu muốn hủy hàng đợi bất kỳ lúc nào.

## Chuẩn hóa danh sách

Bấm `📋 Chuẩn Hóa DS` hoặc gửi `/normalize`, rồi dán danh sách `Tên - Chức danh - Khoa` (cũng nhận `Tên - Khoa - Chức danh`). Bot trả danh sách đã chuẩn hóa **chưa lưu** để bạn sao chép, kiểm tra và dán ngược lại vào chat để lưu. Sau khi lưu, bot hiển thị thẻ người đầu tiên; cũng có thể mở `/people`. Bấm nút để chỉnh họ tên, chọn chức danh/khoa/bệnh viện từ danh sách hoặc xóa người đó; dùng nút trước/sau để chuyển người. Mỗi thay đổi được lưu ngay. **Khoa Khác:** `Tên - Khoa Khác - Tên khoa thực tế - Chức danh [- Bệnh viện]` (ví dụ `An - Khoa Khác - Khoa Lão - bs`); tên khoa sẽ được nhập vào ô Phòng ban Khác như trong app. Tên khoa không nằm trong danh mục sẽ tự chuyển sang Khác và giữ tên nhập tay. Không nhận diện được chức danh hoặc sai số trường thì bot báo lỗi dòng và không thay danh sách cũ. Ví dụ: `Phan Kim Thuỳ Linh - bs - ngoại tổng hợp` → `Phan Kim Thuỳ Linh - Khoa Ngoại Tổng Hợp - Bác Sỹ Điều Trị`.

## Lệnh nhanh Telegram

Gõ `/` trong khung chat để chọn: `/start`, `/help`, `/link` (hoặc `/link URL`), `/people`, `/normalize`, `/hospital`, `/otp`, `/token`, `/hupsms`, `/viotp`, `/balance`, `/services`, `/mode`, `/run`, `/stop`, `/cancel`.

> Để tránh lộ API key trong tin nhắn chứa lệnh, hãy gửi `/token`, `/hupsms` hoặc `/viotp` **không kèm key**, rồi nhập key khi bot yêu cầu. Telegram vẫn lưu tin nhắn chứa key trong lịch sử chat.
