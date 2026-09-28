# PROJECT_DOC - Đặc tả dự án Abbott Event Helper

## 1. Mục tiêu dự án

Dự án cần xây dựng một ứng dụng hỗ trợ đăng ký sự kiện Abbott trên thiết bị Android.

Ứng dụng hoạt động như một công cụ trợ lý nhập liệu: người dùng mở trang đăng ký Abbott bên trong ứng dụng, chọn dữ liệu người tham dự, thuê số điện thoại nhận OTP, lấy mã OTP và điền nhanh các thông tin cần thiết vào form đăng ký.

Mục tiêu chính là giảm thao tác thủ công khi xử lý nhiều người tham dự, hạn chế sai sót trong quá trình nhập liệu và giúp quy trình đăng ký diễn ra nhanh hơn.

Ứng dụng không tự động gửi form. Người dùng luôn là người kiểm tra dữ liệu cuối cùng và tự bấm nút gửi/submit trên website.

---

## 2. Nền tảng và công nghệ đề xuất

Ứng dụng nên được xây dựng bằng Flutter để có thể phát triển giao diện nhanh, dễ đóng gói thành APK Android và có khả năng mở rộng sang nền tảng khác nếu cần.

Các thành phần công nghệ chính:

| Thành phần | Vai trò |
|---|---|
| Flutter/Dart | Xây dựng giao diện, quản lý trạng thái và xử lý logic chính |
| WebView | Hiển thị website đăng ký Abbott bên trong ứng dụng |
| HTTP Client | Gọi API thuê số và lấy OTP |
| Local Storage | Lưu cấu hình như token, URL gần nhất, danh sách người tham dự |
| Clipboard | Copy nhanh số điện thoại, OTP và thông tin người tham dự |
| JavaScript Injection | Tự động điền dữ liệu vào form trong WebView |
| Geolocation Override | Cung cấp vị trí cố định cho website nếu form yêu cầu location |

---

## 3. Các thành phần chính của ứng dụng

Ứng dụng nên được chia thành các thành phần logic sau.

### 3.1. Màn hình chính

Màn hình chính là nơi người dùng thao tác toàn bộ quy trình.

Màn hình này cần có:

- Ô nhập URL website Abbott.
- Nút mở website trong WebView.
- Khu vực hiển thị WebView.
- Panel điều khiển cho thao tác lấy số, lấy OTP, điền dữ liệu.
- Thông tin người tham dự hiện tại.
- Các nút copy nhanh dữ liệu.
- Nút chuyển sang người tiếp theo.
- Nút mở phần cài đặt.

Màn hình chính cần ưu tiên thao tác nhanh, rõ trạng thái hiện tại và dễ dùng trên điện thoại màn hình nhỏ.

### 3.2. WebView

WebView dùng để mở trang đăng ký hoặc đăng nhập Abbott.

Yêu cầu:

- Cho phép người dùng nhập và mở một URL bất kỳ của hệ thống đăng ký Abbott.
- Nếu người dùng nhập URL thiếu `https://`, ứng dụng nên tự bổ sung.
- Cho phép website chạy JavaScript.
- Cho phép inject JavaScript để điền form.
- Có thể override geolocation để website nhận vị trí cố định.
- Không tự động submit form.

WebView là khu vực thao tác chính với website thật. Mọi hành động tự động điền dữ liệu cần được thực hiện cẩn thận để người dùng vẫn có thể kiểm tra trước khi gửi.

### 3.3. Quản lý cấu hình

Ứng dụng cần có khu vực cài đặt để người dùng nhập và lưu các thông tin cấu hình.

Các cấu hình cần có:

| Cấu hình | Ý nghĩa |
|---|---|
| ViOTP token | Token dùng để gọi API thuê số và lấy OTP |
| URL gần nhất | Link Abbott đã mở gần nhất |
| Danh sách người tham dự | Dữ liệu đầu vào để app parse và xử lý |
| Profile danh sách Bệnh viện | Danh sách bệnh viện lưu trong bộ nhớ ứng dụng |
| Bệnh viện mặc định | Bệnh viện được chọn mặc định (mặc định ban đầu là Bệnh viện Đa khoa) |
| Vai trò mặc định | Giá trị điền vào trường vai trò/người tham dự |

Các cấu hình này nên được lưu cục bộ trên thiết bị để lần sau mở app không cần nhập lại.

### 3.4. Quản lý danh sách người tham dự và Profile Bệnh viện

Ứng dụng cho phép người dùng quản lý Profile Bệnh viện và nhập danh sách người tham dự:
- Quản lý danh sách Bệnh viện (thêm, xóa, dán danh sách nhiều bệnh viện cùng lúc).
- Chọn Bệnh viện chung / mặc định và có nút 1-click gán bệnh viện đã chọn cho toàn bộ người trong danh sách.
- Nhập danh sách người tham dự dạng text. Mỗi người nằm trên một dòng.

Định dạng dữ liệu chuẩn:

```text
Họ tên - Khoa/Phòng ban - Chức danh [- Bệnh viện]
```

Ví dụ:

```text
Nguyễn Văn A - Khoa Ngoại Tổng Hợp - Bác Sĩ Điều Trị
Trần Thị B - Khoa Gây Mê Hồi Sức - Điều Dưỡng - Bệnh Viện Sản Nhi Tỉnh Quảng Ngãi
Lê Văn C - Ngoại Thần Kinh - Điều Dưỡng Trưởng
```

Sau khi nhập, ứng dụng cần parse danh sách này thành các người tham dự riêng biệt. Nếu không chỉ định Bệnh viện trong dòng, trường bệnh viện sẽ lấy tự động theo Bệnh viện mặc định đang chọn.

Mỗi người tham dự cần có các trường:

| Trường | Ý nghĩa |
|---|---|
| Họ tên | Tên đầy đủ của người tham dự |
| Bệnh viện | Bệnh viện của người tham dự (có thể chọn riêng hoặc áp dụng chung) |
| Khoa/Phòng ban gốc | Dữ liệu khoa/phòng ban ban đầu |
| Khoa/Phòng ban chuẩn hóa | Dữ liệu đã xử lý để điền vào form |
| Chức danh gốc | Dữ liệu chức danh ban đầu |
| Chức danh chuẩn hóa | Dữ liệu đã xử lý để điền vào form |
| Trạng thái xử lý | Chưa làm, đã lấy số, đã có OTP, đã hoàn tất |

Nếu một dòng không đúng định dạng, ứng dụng nên bỏ qua hoặc báo lỗi rõ ràng để người dùng sửa.

### 3.5. Chuẩn hóa dữ liệu

Dữ liệu nhập vào có thể không đồng nhất về dấu tiếng Việt, chữ hoa/chữ thường hoặc cách viết tắt. Vì vậy ứng dụng cần có bước chuẩn hóa trước khi điền vào form.

#### Chuẩn hóa Khoa/Phòng ban

Yêu cầu:

- Bỏ khoảng trắng thừa.
- Có thể bỏ dấu tiếng Việt khi cần so khớp.
- Nhận diện các cách viết gần giống nhau.
- Trả về giá trị thống nhất để điền form.

Ví dụ quy tắc:

| Dữ liệu nhập | Giá trị chuẩn |
|---|---|
| Gay Me, Gây mê, gay me hoi suc | Khoa Gay Me Hoi Suc |
| Ngoai Than Kinh, Ngoại thần kinh | Khoa Ngoai Than Kinh |
| Chan Thuong, Chấn thương chỉnh hình, Bong | Khoa Chan Thuong Chinh Hinh - Bong |

Nếu không có quy tắc khớp, ứng dụng nên chuyển dữ liệu về dạng title case và giữ nội dung gần nhất với dữ liệu gốc.

#### Chuẩn hóa Chức danh

Yêu cầu:

- Nhận diện viết tắt thông dụng.
- Chuẩn hóa cách viết chức danh.
- Tránh làm mất ý nghĩa dữ liệu gốc.

Ví dụ quy tắc:

| Dữ liệu nhập | Giá trị chuẩn |
|---|---|
| BS, Bac si, Bác sĩ | Bac Sy Dieu Tri |
| DD, Dieu duong, Điều dưỡng | Dieu Duong |
| Dieu duong truong, Điều dưỡng trưởng | Dieu Duong Truong |

Nếu không có quy tắc khớp, ứng dụng nên chuyển dữ liệu về dạng title case.

### 3.6. Tích hợp thuê số điện thoại

Ứng dụng cần tích hợp với một dịch vụ cho thuê số điện thoại nhận OTP. Dịch vụ hiện dùng là ViOTP.

Chức năng cần có:

- Lưu token API.
- Kiểm tra token hợp lệ nếu cần.
- Lấy danh sách dịch vụ.
- Tìm dịch vụ Abbott hoặc dịch vụ tương ứng.
- Thuê số điện thoại cho dịch vụ đó.
- Lưu lại số điện thoại và request ID.
- Copy số điện thoại vào clipboard.
- Cho phép điền số điện thoại vào form trong WebView.

Khi thuê số thành công, ứng dụng cần hiển thị:

- Số điện thoại.
- Request ID.
- Trạng thái thuê số.
- Thông báo copy số thành công nếu có.

Nếu thuê số thất bại, ứng dụng cần hiển thị lỗi dễ hiểu, ví dụ:

- Token sai.
- Không đủ số dư.
- Dịch vụ không còn số.
- Không tìm thấy dịch vụ Abbott.
- Lỗi mạng.

### 3.7. Tích hợp lấy OTP

Sau khi website Abbott gửi OTP về số đã thuê, ứng dụng cần gọi API để kiểm tra OTP.

Chức năng cần có:

- Dùng request ID của số điện thoại đã thuê.
- Poll API theo chu kỳ ngắn, ví dụ mỗi 1 giây.
- Có giới hạn thời gian chờ, ví dụ 60 giây.
- Nếu có OTP, lưu OTP, copy OTP và điền vào form nếu tìm được field.
- Nếu hết thời gian, báo chưa nhận được OTP.
- Nếu request hết hạn, báo rõ cho người dùng.

Trạng thái OTP nên gồm:

| Trạng thái | Ý nghĩa |
|---|---|
| Đang chờ | Chưa có tin nhắn OTP |
| Đã có OTP | API đã trả về mã OTP |
| Hết hạn | Request không còn hiệu lực |
| Lỗi | Không gọi được API hoặc response không hợp lệ |

### 3.8. Auto-fill form

Auto-fill là thành phần quan trọng của ứng dụng.

Ứng dụng cần inject JavaScript vào WebView để tìm các field trên form Abbott và set giá trị tương ứng.

Các trường cần hỗ trợ:

| Trường trên form | Dữ liệu điền |
|---|---|
| Họ tên | Họ tên người tham dự hiện tại |
| Số điện thoại | Số thuê từ dịch vụ OTP |
| OTP | Mã OTP lấy từ dịch vụ OTP |
| Khoa/Phòng ban | Khoa/Phòng ban đã chuẩn hóa |
| Chức danh | Chức danh đã chuẩn hóa |
| Bệnh viện | Bệnh viện mặc định hoặc cấu hình |
| Vai trò/Người tham dự | Vai trò mặc định hoặc cấu hình |

Cách tìm field nên dựa trên nhiều nguồn:

- Label liên kết với input.
- Placeholder.
- Name attribute.
- ID attribute.
- Text gần input trong DOM.
- Các container cha gần nhất.

Trước khi so khớp, text cần được normalize:

- Chuyển về chữ thường.
- Bỏ dấu tiếng Việt.
- Chuyển `đ` thành `d`.
- Rút gọn khoảng trắng.

Ví dụ keyword cần hỗ trợ:

| Field | Keyword gợi ý |
|---|---|
| Họ tên | `ho ten`, `ho va ten`, `name`, `full name` |
| Số điện thoại | `sdt`, `so dien thoai`, `dien thoai`, `phone`, `mobile` |
| OTP | `otp`, `ma`, `ma xac thuc`, `code`, `verification` |
| Khoa/Phòng ban | `khoa`, `phong ban`, `department`, `unit` |
| Chức danh | `chuc danh`, `title`, `position`, `job title` |
| Bệnh viện | `benh vien`, `hospital`, `workplace` |
| Vai trò | `vai tro`, `role`, `nguoi tham du`, `participant` |

Khi set giá trị cho input, cần dispatch các event cần thiết để website nhận thay đổi:

- `input`
- `change`
- Có thể thêm `blur` nếu website yêu cầu validate khi rời field.

Nếu form dùng dropdown, select hoặc custom component, cần có logic riêng:

- Mở dropdown.
- Tìm option theo text đã chuẩn hóa.
- Click chọn option.
- Dispatch event nếu cần.

### 3.9. Copy nhanh dữ liệu

Ứng dụng cần có các nút copy nhanh để người dùng vẫn thao tác thủ công được khi auto-fill không hoạt động.

Các dữ liệu nên hỗ trợ copy:

- Họ tên.
- Khoa/Phòng ban.
- Chức danh.
- Bệnh viện.
- Vai trò người tham dự.
- Số điện thoại.
- OTP.

Sau khi copy, ứng dụng cần hiển thị thông báo ngắn để người dùng biết đã copy thành công.

### 3.10. Mock vị trí địa lý

Một số form có thể yêu cầu quyền vị trí hoặc lấy tọa độ người dùng. Ứng dụng cần hỗ trợ trả về một vị trí cố định trong WebView.

Yêu cầu:

- Override `navigator.geolocation.getCurrentPosition`.
- Override `navigator.geolocation.watchPosition` nếu cần.
- Trả về tọa độ cố định.
- Không làm crash website nếu website không dùng geolocation.

Tọa độ mặc định đề xuất:

```text
latitude: 15.114757
longitude: 108.791015
accuracy: 10
```

Tọa độ này nên được thiết kế để có thể đổi trong tương lai nếu cần.

---

## 4. Quy trình sử dụng đề xuất

Quy trình người dùng cuối:

1. Mở ứng dụng.
2. Nhập hoặc kiểm tra URL website Abbott.
3. Bấm mở website trong WebView.
4. Mở cài đặt.
5. Nhập ViOTP token.
6. Nhập danh sách người tham dự.
7. Lưu cài đặt.
8. Chọn người tham dự đầu tiên.
9. Bấm điền thông tin người tham dự vào form.
10. Kiểm tra các trường đã điền trên website.
11. Bấm thuê số điện thoại.
12. Điền hoặc copy số điện thoại vào form.
13. Thao tác trên website để yêu cầu gửi OTP.
14. Bấm lấy OTP trong ứng dụng.
15. Chờ ứng dụng nhận OTP.
16. Ứng dụng copy và điền OTP nếu có thể.
17. Người dùng kiểm tra lại form.
18. Người dùng tự bấm gửi/submit.
19. Đánh dấu người hiện tại là đã hoàn tất nếu cần.
20. Chuyển sang người tiếp theo.

---

## 5. Trạng thái cần quản lý

Ứng dụng cần quản lý rõ các trạng thái sau:

### 5.1. Trạng thái WebView

- Chưa mở URL.
- Đang tải trang.
- Tải thành công.
- Tải lỗi.
- Đang inject script.
- Điền form thành công.
- Điền form một phần.
- Không tìm thấy field cần điền.

### 5.2. Trạng thái người tham dự

- Chưa xử lý.
- Đã điền thông tin cơ bản.
- Đã thuê số.
- Đã có OTP.
- Đã hoàn tất.
- Lỗi cần kiểm tra.

### 5.3. Trạng thái thuê số

- Chưa thuê số.
- Đang thuê số.
- Thuê số thành công.
- Thuê số thất bại.

### 5.4. Trạng thái OTP

- Chưa yêu cầu OTP.
- Đang chờ OTP.
- Đã nhận OTP.
- Hết thời gian chờ.
- Request hết hạn.
- Lỗi API.

---

## 6. Yêu cầu giao diện

Giao diện cần tối ưu cho điện thoại Android.

Yêu cầu chung:

- Dễ đọc trong môi trường thao tác nhanh.
- Các nút chính phải rõ ràng.
- Trạng thái hiện tại phải nổi bật.
- Không để giao diện bị overflow trên màn hình nhỏ.
- Các vùng thao tác cần có khoảng cách đủ để bấm chính xác.
- WebView và panel điều khiển cần bố trí hợp lý để không che mất nội dung quan trọng.

Các hành động quan trọng cần có nút riêng:

- Mở URL.
- Điền người hiện tại.
- Thuê số.
- Điền/copy số điện thoại.
- Lấy OTP.
- Điền/copy OTP.
- Copy từng trường thông tin.
- Người tiếp theo.
- Mở cài đặt.

Thông báo trong app cần ngắn gọn, dễ hiểu, ví dụ:

- Đã lưu cài đặt.
- Đã copy số điện thoại.
- Đã thuê số thành công.
- Đang chờ OTP.
- Đã nhận OTP.
- Không tìm thấy ô OTP trên form.
- Token không hợp lệ.
- Không đủ số dư.

---

## 7. Yêu cầu lưu trữ cục bộ

Ứng dụng cần lưu các dữ liệu sau trên thiết bị:

| Dữ liệu | Mục đích |
|---|---|
| Token API | Không phải nhập lại mỗi lần mở app |
| URL gần nhất | Tiếp tục thao tác nhanh với website cũ |
| Danh sách người tham dự | Không mất dữ liệu khi đóng app |
| Bệnh viện mặc định | Tự điền form |
| Vai trò mặc định | Tự điền form |
| Cấu hình vị trí | Cho phép thay đổi tọa độ nếu phát triển thêm |

Dữ liệu nhạy cảm như token cần được lưu cẩn thận. Nếu có thể, nên dùng cơ chế lưu trữ an toàn của hệ điều hành.

---

## 8. Xử lý lỗi

Ứng dụng cần xử lý lỗi rõ ràng và không được crash khi gặp tình huống bất thường.

Các lỗi cần dự phòng:

- URL không hợp lệ.
- Website không tải được.
- WebView mất kết nối mạng.
- Token API sai hoặc hết hạn.
- API trả response không đúng định dạng.
- Không tìm thấy dịch vụ Abbott.
- Dịch vụ OTP hết số.
- Không đủ số dư thuê số.
- Không nhận được OTP trong thời gian chờ.
- Request OTP hết hạn.
- Không tìm thấy field trên form.
- Form dùng dropdown/custom component chưa hỗ trợ.
- Dữ liệu người tham dự sai định dạng.
- Clipboard không hoạt động.
- Local storage lỗi.

Mỗi lỗi cần có thông báo thân thiện để người dùng biết bước tiếp theo nên làm gì.

---

## 9. Nguyên tắc an toàn thao tác

Ứng dụng chỉ hỗ trợ nhập liệu, không thay người dùng quyết định cuối cùng.

Nguyên tắc bắt buộc:

- Không tự động submit form.
- Không tự động chuyển người nếu người dùng chưa xác nhận.
- Không xóa danh sách người tham dự nếu chưa có xác nhận.
- Không ghi đè token/cấu hình nếu người dùng chưa lưu.
- Khi auto-fill không chắc chắn, cần báo cho người dùng kiểm tra lại.
- Luôn cho phép copy thủ công để thay thế auto-fill.

---

## 10. Tiêu chí hoàn thành phiên bản đầu tiên

Phiên bản đầu tiên được xem là đạt yêu cầu khi có thể thực hiện đầy đủ quy trình sau:

- Mở được website Abbott trong WebView.
- Lưu và nạp lại URL gần nhất.
- Lưu và nạp lại token API.
- Nhập danh sách người tham dự.
- Parse đúng danh sách người tham dự.
- Hiển thị người tham dự hiện tại.
- Chuyển qua lại giữa các người tham dự.
- Chuẩn hóa được Khoa/Phòng ban và Chức danh cơ bản.
- Điền được họ tên, khoa, chức danh, bệnh viện và vai trò vào form.
- Thuê được số điện thoại qua API.
- Copy và/hoặc điền được số điện thoại.
- Lấy được OTP qua API.
- Copy và/hoặc điền được OTP.
- Mock geolocation hoạt động nếu website yêu cầu vị trí.
- Không tự submit form.
- Không crash khi API lỗi hoặc website không tải được.

---

## 11. Checklist kiểm thử

Trước khi bàn giao, cần kiểm thử:

- [ ] Mở app lần đầu không lỗi.
- [ ] Nhập URL và mở website thành công.
- [ ] URL thiếu `https://` vẫn được xử lý đúng.
- [ ] Lưu token thành công.
- [ ] Đóng mở app vẫn còn token.
- [ ] Nhập danh sách người tham dự thành công.
- [ ] Parse đúng từng dòng dữ liệu hợp lệ.
- [ ] Báo lỗi hoặc bỏ qua dòng sai định dạng.
- [ ] Hiển thị đúng người tham dự hiện tại.
- [ ] Chuyển người tiếp theo đúng.
- [ ] Copy họ tên thành công.
- [ ] Copy khoa/phòng ban thành công.
- [ ] Copy chức danh thành công.
- [ ] Copy bệnh viện thành công.
- [ ] Copy vai trò thành công.
- [ ] Thuê số điện thoại thành công.
- [ ] Copy số điện thoại thành công.
- [ ] Điền số điện thoại vào form thành công.
- [ ] Website gửi OTP về số đã thuê.
- [ ] Lấy OTP thành công.
- [ ] Copy OTP thành công.
- [ ] Điền OTP vào form thành công.
- [ ] Điền họ tên vào form thành công.
- [ ] Điền khoa/phòng ban vào form thành công.
- [ ] Điền chức danh vào form thành công.
- [ ] Điền bệnh viện vào form thành công.
- [ ] Điền vai trò vào form thành công.
- [ ] Không tự submit form.
- [ ] Giao diện không bị tràn trên màn hình nhỏ.
- [ ] App không crash khi mất mạng.
- [ ] App không crash khi API trả lỗi.
- [ ] App không crash khi website đổi form.

---

## 12. Hướng mở rộng sau này

Các tính năng có thể phát triển thêm:

- Import danh sách người tham dự từ file.
- Export danh sách người đã xử lý.
- Lưu trạng thái xử lý cho từng người.
- Thêm bộ lọc người chưa làm/đã hoàn tất.
- Cấu hình nhiều bệnh viện khác nhau.
- Cấu hình nhiều vai trò người tham dự.
- Cấu hình tọa độ geolocation trong giao diện.
- Thêm màn hình log API để debug.
- Thêm retry khi thuê số thất bại.
- Thêm chọn nhà mạng hoặc prefix số.
- Hỗ trợ dropdown/select/custom dropdown nâng cao.
- Hỗ trợ nhiều mẫu form khác nhau.
- Đồng bộ dữ liệu giữa nhiều thiết bị nếu cần.

---

## 13. Tóm tắt ngắn

Dự án cần tạo một ứng dụng Android hỗ trợ đăng ký sự kiện Abbott bằng cách mở website trong WebView, quản lý danh sách người tham dự, thuê số điện thoại nhận OTP, lấy OTP và tự động điền dữ liệu vào form.

Ứng dụng phải ưu tiên tốc độ thao tác, độ ổn định và khả năng kiểm soát của người dùng.

Điểm quan trọng nhất: **ứng dụng chỉ hỗ trợ điền thông tin, không tự động gửi form**.
