import os
import time
import re
from typing import Dict, Any, Optional, Callable, Tuple
from playwright.sync_api import sync_playwright, Page, BrowserContext, TimeoutError as PlaywrightTimeoutError

from otp_service import OtpService
from config import SCREENSHOTS_DIR


class AbbottAutomationRunner:
    def __init__(
        self,
        event_url: str,
        provider: str,
        token: str,
        service_id: int,
        delay_ms: int = 700,
        otp_timeout: int = 60,
        on_status_callback: Optional[Callable[[str], None]] = None,
        on_screenshot_callback: Optional[Callable[[str, str], bool]] = None,
        on_review_callback: Optional[Callable[[], bool]] = None,
    ):
        self.event_url = event_url
        self.provider = provider
        self.token = token
        self.service_id = service_id
        self.delay_ms = delay_ms
        self.otp_timeout = otp_timeout
        self.on_status = on_status_callback or (lambda msg: print(f"[*] {msg}"))
        self.on_screenshot = on_screenshot_callback or (lambda path, caption: False)
        self.on_review = on_review_callback
        self._is_stopped = False

    def stop(self):
        self._is_stopped = True

    def _sleep_delay(self, factor: float = 1.0):
        ms = max(300, int(self.delay_ms * factor))
        time.sleep(ms / 1000.0)

    def process_person(self, person: Dict[str, str], index: int, total: int) -> Tuple[bool, str, Optional[str]]:
        """
        Thực hiện toàn bộ quy trình cho 1 người tham gia:
        1. Mở web
        2. Thuê SĐT
        3. Điền SĐT & Bấm gửi mã
        4. Polling OTP 60s
        5. Điền OTP & Bấm xác thực
        6. Điền thông tin cá nhân (Tên, Khoa, Chức danh, BV, Checkbox)
        7. Chụp ảnh thẻ form đã điền & Gửi qua Telegram
        8. Bấm Gửi form
        """
        name = person.get("name", "Người tham dự")
        hosp = person.get("hospital", "")
        dept = person.get("department", "")
        other_dept = person.get("otherDepartment", "")
        role = person.get("role", "Y ta/ Dieu duong")
        role_participant = "Nguoi tham du"

        self.on_status(f"🔄 <b>[{index}/{total}] Bắt đầu:</b> {name}")

        with sync_playwright() as p:
            # Khởi tạo browser Chromium headless với mobile viewport
            browser = p.chromium.launch(
                headless=True,
                args=[
                    "--no-sandbox",
                    "--disable-setuid-sandbox",
                    "--disable-dev-shm-usage",
                    "--disable-gpu",
                ]
            )
            context = browser.new_context(
                viewport={"width": 390, "height": 844},
                user_agent="Mozilla/5.0 (iPhone; CPU iPhone OS 16_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.6 Mobile/15E148 Safari/604.1",
                is_mobile=True,
                has_touch=True,
                geolocation={"latitude": 15.114757, "longitude": 108.791015},
                permissions=["geolocation"],
            )

            page = context.new_page()

            try:
                # BƯỚC 1: Mở URL sự kiện Abbott
                self.on_status(f"🌐 <b>[{index}/{total}]</b> Đang tải trang sự kiện Abbott...")
                page.goto(self.event_url, wait_until="domcontentloaded", timeout=45000)
                self._sleep_delay(1.5)

                if self._is_stopped:
                    return False, "Đã hủy bởi người dùng", None

                # BƯỚC 2: Thuê số điện thoại
                self.on_status(f"📱 <b>[{index}/{total}]</b> Đang gọi API thuê số điện thoại ({self.provider.upper()})...")
                ok_rent, phone, order_id, bal, rent_msg = OtpService.rent_phone(
                    provider=self.provider,
                    token=self.token,
                    service_id=self.service_id
                )

                if not ok_rent or not phone or not order_id:
                    return False, f"Lỗi thuê số: {rent_msg}", None

                def cancel_order(reason):
                    ok_cancel, cancel_message = OtpService.cancel_rental(self.provider, self.token, order_id)
                    return False, f"{reason}. {'Hủy đơn: ' if ok_cancel else '⚠️ Chưa xác nhận hủy: '}{cancel_message}", None

                if self._is_stopped:
                    return cancel_order("Đã dừng theo yêu cầu")
                self.on_status(f"📞 <b>[{index}/{total}]</b> Đã lấy số: <code>{phone}</code> (Order: {order_id})")

                # BƯỚC 3: Điền SĐT vào trang web
                phone_input = self._find_phone_input(page)
                if not phone_input:
                    return cancel_order("Không tìm thấy ô nhập Số điện thoại trên web")

                phone_input.fill(phone)
                self._sleep_delay(1.0)

                # Bấm nút "Gửi mã" / "Nhận OTP"
                send_code_btn = self._find_send_code_button(page)
                if not send_code_btn:
                    return cancel_order("Không tìm thấy nút 'Gửi mã' trên trang web")
                if self._is_stopped:
                    return cancel_order("Đã dừng theo yêu cầu")

                send_code_btn.click()
                self.on_status(f"⏳ <b>[{index}/{total}]</b> Đã bấm gửi mã trên web! Bắt đầu đếm ngược 60s chờ OTP...")

                # BƯỚC 4: Polling OTP trong 60 giây
                otp_code = None
                deadline = time.monotonic() + self.otp_timeout
                errors = 0
                checks = 0
                while time.monotonic() < deadline:
                    if self._is_stopped:
                        return cancel_order("Đã dừng theo yêu cầu")

                    st, code, sms = OtpService.check_otp(self.provider, self.token, order_id)
                    checks += 1
                    if st == "success" and code:
                        otp_code = code
                        break
                    if st in ("cancelled", "expired"):
                        return False, f"Đơn {order_id}: {sms}; hãy kiểm tra trạng thái và hoàn tiền tại nhà cung cấp", None
                    if st == "error":
                        errors += 1
                        if errors >= 3:
                            return cancel_order(f"Lỗi kiểm tra OTP liên tiếp: {sms}")
                    else:
                        errors = 0
                    time.sleep(min(2.5, max(0, deadline - time.monotonic())))

                if not otp_code:
                    self.on_status(f"⚠️ <b>[{index}/{total}]</b> Quá {self.otp_timeout}s không nhận được OTP; đang yêu cầu hủy đơn...")
                    return cancel_order(f"Quá {self.otp_timeout}s không nhận OTP cho số {phone} (đã kiểm tra {checks} lần)")

                if self._is_stopped:
                    return False, "Đã dừng sau khi nhận OTP; kiểm tra trạng thái đơn tại nhà cung cấp", None
                self.on_status(f"🔑 <b>[{index}/{total}]</b> Nhận OTP thành công: <code>{otp_code}</code>")

                # BƯỚC 5: Điền OTP & Bấm Xác thực
                otp_input = self._find_otp_input(page)
                if not otp_input:
                    return False, "Không tìm thấy ô nhập mã OTP trên web!", None

                otp_input.fill(otp_code)
                self._sleep_delay(1.0)

                verify_btn = self._find_verify_button(page)
                if verify_btn:
                    verify_btn.click()
                    self.on_status(f"🚀 <b>[{index}/{total}]</b> Đã bấm Xác thực OTP, đang chuyển sang form thông tin...")
                    self._sleep_delay(2.5)

                # BƯỚC 6: Điền form thông tin cá nhân
                # Đợi form thông tin cá nhân xuất hiện
                page.wait_for_selector("input, .el-form", timeout=15000)
                self._sleep_delay(1.5)

                self.on_status(f"📝 <b>[{index}/{total}]</b> Đang tự động điền form thông tin cho: <b>{name}</b>...")

                # 6.1 Điền Họ và Tên
                name_filled = page.evaluate("""(val) => {
                    const inputs = Array.from(document.querySelectorAll('input, textarea'));
                    const inp = inputs.find(i => {
                        const txt = (i.placeholder || '') + ' ' + (i.name || '') + ' ' + (i.id || '') + ' ' + (i.closest('.el-form-item')?.innerText || '');
                        const n = txt.toLowerCase().normalize('NFD').replace(/[\\u0300-\\u036f]/g, '');
                        return n.includes('ho va ten') || n.includes('ho ten') || n.includes('name');
                    });
                    if (inp) {
                        inp.focus();
                        inp.value = val;
                        inp.dispatchEvent(new Event('input', {bubbles: true}));
                        inp.dispatchEvent(new Event('change', {bubbles: true}));
                        return true;
                    }
                    return false;
                }""", name)

                self._sleep_delay(1.0)

                # 6.2 Điền Dropdowns (Vai trò, Bệnh viện, Khoa, Chức danh)
                # Dùng script JS chuyên xử lý Element UI Select
                fill_js = """async (data) => {
                    const delay = ms => new Promise(r => setTimeout(r, ms));
                    const norm = s => (s || '').toLowerCase().normalize('NFD').replace(/[\\u0300-\\u036f]/g, '').replace(/đ/g, 'd').replace(/\\s+/g, ' ').trim();

                    async function fillSelect(keywords, targetVal, fallbackIdx, excluded = []) {
                        if (!targetVal) return false;
                        const selects = Array.from(document.querySelectorAll('.el-select input, input[role="combobox"]'));
                        const inp = selects.find(el => {
                            const parentTxt = el.closest('.el-form-item, .form-group')?.innerText || '';
                            const txt = (el.placeholder || '') + ' ' + parentTxt;
                            const n = norm(txt);
                            return keywords.some(k => n.includes(k)) && !excluded.some(ex => n.includes(ex));
                        }) || selects[fallbackIdx];

                        if (!inp) return false;
                        inp.scrollIntoView({block: 'center'});
                        inp.click();
                        await delay(700);

                        let options = Array.from(document.querySelectorAll('.el-select-dropdown__item, [role="option"]')).filter(o => o.offsetParent !== null);
                        const t = norm(targetVal);
                        const matchOption = () => options.find(o => norm(o.innerText) === t) ||
                            (t === 'khac' ? null : options.find(o => {
                                const value = norm(o.innerText);
                                return value && (value.includes(t) || t.includes(value));
                            }));
                        let best = matchOption();

                        if (!best && t !== 'khac') {
                            inp.value = targetVal;
                            inp.dispatchEvent(new Event('input', {bubbles: true}));
                            await delay(1000);
                            options = Array.from(document.querySelectorAll('.el-select-dropdown__item, [role="option"]')).filter(o => o.offsetParent !== null);
                            best = matchOption();
                        }

                        if (best) {
                            best.click();
                            await delay(600);
                            return true;
                        }
                        inp.dispatchEvent(new KeyboardEvent('keydown', {key: 'Escape', bubbles: true}));
                        return false;
                    }

                    // 1. Vai trò
                    await fillSelect(['vai tro', 'role'], data.roleParticipant, 0);
                    // 2. Bệnh viện
                    await fillSelect(['benh vien', 'hospital'], data.hospital, 1);
                    // 3. Chỉ chọn Khac và nhập ô riêng khi phòng ban là Khac.
                    if (norm(data.department) !== 'khac' && data.otherDepartment) throw new Error('Dữ liệu khoa không nhất quán; kiểm tra lại danh sách');
                    const selectedDepartment = await fillSelect(['phong ban', 'khoa', 'department'], data.department, 2, ['khac', 'other']);
                    if (!selectedDepartment) throw new Error('Không chọn được Khoa trên form');
                    let otherFilled = true;
                    if (data.department === 'Khac' && !data.otherDepartment) throw new Error('Thiếu tên Khoa Khác');
                    if (data.otherDepartment) {
                        otherFilled = false;
                        await delay(500);
                        for (let attempt = 0; attempt < 8; attempt++) {
                            const otherInp = Array.from(document.querySelectorAll('input, textarea')).find(i => {
                                if (i.closest('.el-select') || i.getAttribute('role') === 'combobox' || i.readOnly || i.disabled || !i.getClientRects().length) return false;
                                const field = i.closest('.el-form-item, .form-group');
                                const txt = (i.placeholder || '') + ' ' + (field?.querySelector('label, .el-form-item__label')?.innerText || '');
                                const label = norm(txt);
                                return (label.includes('khac') || label.includes('other')) &&
                                    (label.includes('phong ban') || label.includes('khoa') || label.includes('department'));
                            });
                            if (otherInp) {
                                otherInp.focus();
                                const setter = Object.getOwnPropertyDescriptor(
                                    otherInp.tagName === 'TEXTAREA' ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype, 'value'
                                ).set;
                                setter.call(otherInp, data.otherDepartment);
                                otherInp.dispatchEvent(new Event('input', {bubbles: true}));
                                otherInp.dispatchEvent(new Event('change', {bubbles: true}));
                                otherInp.blur();
                                await delay(150);
                                otherFilled = otherInp.value === data.otherDepartment;
                                break;
                            }
                            await delay(150);
                        }
                    }
                    if (!selectedDepartment || !otherFilled) throw new Error('Không chọn/điền được Khoa trên form');

                    // 4. Chức danh
                    await fillSelect(['chuc danh', 'title'], data.role, 3);

                    // 5. Tích checkbox Đồng ý
                    const cbs = Array.from(document.querySelectorAll('input[type="checkbox"], .el-checkbox__original'));
                    for (const cb of cbs) {
                        const pTxt = cb.closest('.el-checkbox, label')?.innerText || '';
                        if (norm(pTxt).includes('dong y') || norm(pTxt).includes('chinh sach') || norm(pTxt).includes('quyen rieng tu')) {
                            if (!cb.checked) {
                                cb.click();
                            }
                        }
                    }
                    return true;
                }"""

                page.evaluate(fill_js, {
                    "roleParticipant": role_participant,
                    "hospital": hosp,
                    "department": dept,
                    "otherDepartment": other_dept,
                    "role": role,
                })

                self._sleep_delay(2.0)

                # BƯỚC 7: CHỤP ẢNH MÀN HÌNH (SCREENSHOT) THẺ FORM ĐÃ ĐIỀN ĐẦY ĐỦ
                timestamp = int(time.time())
                screenshot_filename = f"form_{index}_{timestamp}.png"
                screenshot_path = os.path.join(SCREENSHOTS_DIR, screenshot_filename)

                # Chụp toàn trang để có đúng khung hình thẻ form như 3 ảnh mẫu
                page.screenshot(path=screenshot_path, full_page=True)

                caption = (
                    f"📸 <b>[Queue {index}/{total}] Thẻ thông tin đã điền:</b>\n"
                    f"👤 <b>Họ và Tên:</b> {name}\n"
                    f"📱 <b>SĐT:</b> <code>{phone}</code>\n"
                    f"🏥 <b>Bệnh viện:</b> {hosp}\n"
                    f"🏢 <b>Phòng ban:</b> {other_dept if dept == 'Khac' else dept}\n"
                    f"💼 <b>Chức danh:</b> {role}\n"
                    f"⏳ <i>{'Chờ xác nhận trước khi gửi.' if self.on_review else 'Chế độ tự động gửi.'}</i>"
                )
                # Ảnh không gửi được hoặc không có xác nhận: tuyệt đối không submit.
                if not self.on_screenshot(screenshot_path, caption):
                    return False, "Không gửi được ảnh kiểm tra; chưa gửi form", screenshot_path
                if self.on_review and not self.on_review():
                    return False, "Không được duyệt / hết thời gian chờ; chưa gửi form", screenshot_path
                if self._is_stopped:
                    return False, "Đã dừng; chưa gửi form", screenshot_path
                self._sleep_delay(1.5)
                if self._is_stopped:
                    return False, "Đã dừng; chưa gửi form", screenshot_path

                # BƯỚC 8: Bấm nút Gửi / Submit form
                submit_btn = self._find_submit_button(page)
                if not submit_btn:
                    return False, "Không tìm thấy nút 'Gửi' form trên web!", screenshot_path

                submit_btn.click()
                self.on_status(f"📤 <b>[{index}/{total}]</b> Đã bấm nút 'Gửi' form, chờ máy chủ Abbott xác nhận...")
                self._sleep_delay(3.5)

                # Kiểm tra kết quả
                success_detected = page.evaluate("""() => {
                    const txt = document.body.innerText || '';
                    const n = txt.toLowerCase().normalize('NFD').replace(/[\\u0300-\\u036f]/g, '');
                    return n.includes('thanh cong') || n.includes('cam on') || n.includes('hoan tat') || n.includes('success');
                }""")

                return True, f"Đăng ký thành công cho {name} (SĐT: {phone})", screenshot_path

            except Exception as e:
                import traceback
                traceback.print_exc()
                return False, f"Lỗi thực thi: {str(e)}", None
            finally:
                context.close()
                browser.close()

    def _find_phone_input(self, page: Page):
        selectors = [
            'input[type="tel"]',
            'input[placeholder*="thoại"]',
            'input[placeholder*="phone"]',
            'input[placeholder*="điện thoại"]',
            'input[name*="phone"]',
            'input[name*="mobile"]',
            '.el-input__inner[type="text"]',
        ]
        for sel in selectors:
            try:
                el = page.locator(sel).first
                if el.is_visible(timeout=1000):
                    return el
            except Exception:
                pass
        return None

    def _find_send_code_button(self, page: Page):
        texts = ["Gửi mã", "Nhận mã", "Lấy mã", "Lấy OTP", "Gửi mã xác nhận", "Nhận OTP"]
        for txt in texts:
            try:
                btn = page.locator(f"button:has-text('{txt}'), a:has-text('{txt}'), div[role='button']:has-text('{txt}')").first
                if btn.is_visible(timeout=1000):
                    return btn
            except Exception:
                pass
        return None

    def _find_otp_input(self, page: Page):
        selectors = [
            'input[placeholder*="OTP"]',
            'input[placeholder*="mã"]',
            'input[placeholder*="xác thực"]',
            'input[name*="otp"]',
            'input[name*="code"]',
        ]
        for sel in selectors:
            try:
                el = page.locator(sel).first
                if el.is_visible(timeout=1000):
                    return el
            except Exception:
                pass
        return None

    def _find_verify_button(self, page: Page):
        texts = ["Xác thực", "Tiếp tục", "Đăng nhập", "Xác nhận", "Tiếp theo"]
        for txt in texts:
            try:
                btn = page.locator(f"button:has-text('{txt}'), a:has-text('{txt}'), div[role='button']:has-text('{txt}')").first
                if btn.is_visible(timeout=1000):
                    return btn
            except Exception:
                pass
        return None

    def _find_submit_button(self, page: Page):
        texts = ["Gửi", "Đăng ký", "Hoàn tất", "Xác nhận", "Submit"]
        for txt in texts:
            try:
                btn = page.locator(f"button:has-text('{txt}'), a:has-text('{txt}'), input[type='submit']").first
                if btn.is_visible(timeout=1500):
                    return btn
            except Exception:
                pass
        return None
