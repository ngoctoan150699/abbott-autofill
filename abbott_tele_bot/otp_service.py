import requests
import json
import time
from typing import Dict, Any, List, Optional, Tuple

VIOTP_BASE = "https://api.viotp.net/v1"
HUPSMS_BASE = "https://hupsms.com/api/v1"


class OtpService:
    @staticmethod
    def _headers(token: str) -> dict:
        return {
            "Authorization": f"Bearer {token.strip()}",
            "Content-Type": "application/json",
            "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36",
        }

    @staticmethod
    def fetch_balance(provider: str, token: str) -> Tuple[bool, int, str]:
        """
        Lấy số dư tài khoản.
        Trả về: (thành_công, số_dư, thông_báo_lỗi)
        """
        clean_token = token.strip()
        if not clean_token:
            return False, 0, "Chưa nhập Token/API Key!"

        try:
            if provider == "hupsms":
                url = f"{HUPSMS_BASE}/balance?api_key={clean_token}"
                res = requests.get(url, headers=OtpService._headers(clean_token), timeout=10)
            else:
                url = f"{VIOTP_BASE}/balance"
                res = requests.get(url, headers=OtpService._headers(clean_token), timeout=10)

            if res.status_code == 200:
                data = res.json()
                bal = None
                if isinstance(data, dict):
                    bal = data.get("balance")
                    if bal is None and isinstance(data.get("data"), dict):
                        bal = data["data"].get("balance")
                if bal is not None:
                    return True, int(bal), ""
                return False, 0, "Không phân tích được trường số dư."
            else:
                err_text = res.text
                try:
                    j = res.json()
                    err_text = j.get("message") or j.get("detail") or j.get("error") or res.text
                except Exception:
                    pass
                return False, 0, f"Lỗi HTTP {res.status_code}: {err_text}"
        except Exception as e:
            return False, 0, f"Lỗi kết nối: {str(e)}"

    @staticmethod
    def fetch_services(provider: str, token: str) -> Tuple[bool, List[Dict[str, Any]], str]:
        """
        Lấy danh sách dịch vụ OTP.
        Trả về: (thành_công, danh_sách_dịch_vụ, thông_báo)
        """
        clean_token = token.strip()
        if not clean_token:
            return False, [], "Chưa nhập Token/API Key!"

        try:
            if provider == "hupsms":
                url = f"{HUPSMS_BASE}/services?api_key={clean_token}"
                res = requests.get(url, headers=OtpService._headers(clean_token), timeout=12)
            else:
                url = f"{VIOTP_BASE}/services"
                res = requests.get(url, headers=OtpService._headers(clean_token), timeout=12)

            if res.status_code == 200:
                data = res.json()
                raw_list = []
                if isinstance(data, list):
                    raw_list = data
                elif isinstance(data, dict) and isinstance(data.get("data"), list):
                    raw_list = data["data"]

                services = []
                for item in raw_list:
                    if isinstance(item, dict):
                        raw_id = item.get("id") or item.get("serviceId") or item.get("service_id")
                        try:
                            s_id = int(raw_id)
                        except (TypeError, ValueError):
                            continue
                        name = str(item.get("name") or item.get("service_name") or f"Dịch vụ {s_id}")
                        raw_price = item.get("price") or item.get("cost") or 0
                        try:
                            price = int(raw_price)
                        except (TypeError, ValueError):
                            price = 0
                        server = str(item.get("server") or "").strip()
                        services.append({
                            "id": s_id,
                            "name": name,
                            "price": price,
                            "server": server,
                            "displayName": f"{name} [{server}]" if server else name,
                        })
                return True, services, "Thành công"
            else:
                return False, [], f"Lỗi HTTP {res.status_code}: {res.text}"
        except Exception as e:
            return False, [], f"Lỗi kết nối: {str(e)}"

    @staticmethod
    def find_abbott_services(provider: str, token: str) -> List[Dict[str, Any]]:
        """
        Tìm tất cả dịch vụ có chữ 'Abbott', sắp xếp theo giá từ rẻ nhất đến đắt nhất.
        """
        ok, services, _ = OtpService.fetch_services(provider, token)
        if not ok:
            return []
        matches = [s for s in services if "abbott" in s["name"].lower()]
        matches.sort(key=lambda x: x["price"])
        return matches

    @staticmethod
    def rent_phone(provider: str, token: str, service_id: int) -> Tuple[bool, Optional[str], Optional[str], Optional[int], str]:
        """
        Thuê số điện thoại.
        Trả về: (thành_công, phone, order_id, balance, thông_báo)
        """
        clean_token = token.strip()
        if not clean_token:
            return False, None, None, None, "Chưa nhập Token/API Key!"

        try:
            if provider == "hupsms":
                url = f"{HUPSMS_BASE}/rent?api_key={clean_token}&serviceId={service_id}"
                res = requests.get(url, headers=OtpService._headers(clean_token), timeout=15)
            else:
                url = f"{VIOTP_BASE}/rentals"
                res = requests.post(url, headers=OtpService._headers(clean_token), json={"serviceId": service_id}, timeout=15)

            if res.status_code in (200, 201):
                j = res.json()
                data = j.get("data") if (isinstance(j, dict) and isinstance(j.get("data"), dict)) else j
                phone = str(data.get("phone") or data.get("phoneLocal") or data.get("re_phone") or "")
                if phone and not phone.startswith("0"):
                    phone = "0" + phone

                order_id = str(data.get("orderId") or data.get("id") or data.get("request_id") or "")
                bal = data.get("balance")
                balance_int = int(bal) if bal is not None else None

                if phone and order_id:
                    return True, phone, order_id, balance_int, "Thuê số thành công"
                return False, None, None, None, f"Dữ liệu trả về thiếu SĐT/ID: {res.text}"
            else:
                err_text = res.text
                try:
                    j = res.json()
                    err_text = j.get("message") or j.get("detail") or j.get("error") or res.text
                except Exception:
                    pass
                return False, None, None, None, f"Lỗi thuê số ({res.status_code}): {err_text}"
        except Exception as e:
            return False, None, None, None, f"Lỗi kết nối khi thuê số: {str(e)}"

    @staticmethod
    def check_otp(provider: str, token: str, order_id: str) -> Tuple[str, Optional[str], str]:
        """
        Kiểm tra trạng thái OTP.
        Trả về: (status ['pending', 'success', 'expired', 'cancelled', 'error'], otp, message)
        """
        clean_token = token.strip()
        try:
            if provider == "hupsms":
                url = f"{HUPSMS_BASE}/check/{order_id}?api_key={clean_token}"
                res = requests.get(url, headers=OtpService._headers(clean_token), timeout=10)
                if res.status_code == 200:
                    j = res.json()
                    if not isinstance(j, dict) or j.get("success") is False:
                        return "error", None, "HupSMS từ chối kiểm tra đơn hoặc trả dữ liệu không hợp lệ"
                    data = j.get("data") if isinstance(j.get("data"), dict) else j
                    st = str(data.get("status") or "").lower()
                    otp = data.get("otp") or ""
                    sms = data.get("smsContent") or ""

                    if st in ("cancelled", "canceled"):
                        return "cancelled", None, "Đơn đã bị hủy"
                    if st == "expired":
                        return "expired", None, "Đơn đã hết hạn"
                    if st == "success" or otp or sms:
                        import re
                        clean_otp = str(otp).strip() if otp else ""
                        if not clean_otp and sms:
                            m = re.search(r'\b\d{4,8}\b', str(sms))
                            if m:
                                clean_otp = m.group(0)
                        if clean_otp:
                            return "success", clean_otp, sms
                        if st == "success":
                            return "error", None, "HupSMS báo thành công nhưng không có mã OTP"
                    return "pending", None, "Đang chờ OTP..."
                elif res.status_code == 404:
                    return "expired", None, "Không tìm thấy đơn hàng (có thể đã hủy/hết hạn)"
                return "error", None, f"HupSMS trả HTTP {res.status_code} khi kiểm tra OTP"
            else:
                url = f"{VIOTP_BASE}/rentals/{order_id}"
                res = requests.get(url, headers=OtpService._headers(clean_token), timeout=10)
                if res.status_code == 200:
                    j = res.json()
                    data = j.get("data") if (isinstance(j, dict) and isinstance(j.get("data"), dict)) else j
                    st = data.get("status")
                    if st == 1:
                        code = str(data.get("code") or "")
                        content = str(data.get("content") or "")
                        return "success", code, content
                    elif st == 2:
                        return "expired", None, "Hết hạn thuê số (Đã hoàn tiền)"
                    return "pending", None, "Đang chờ OTP..."
                return "error", None, f"ViOTP trả HTTP {res.status_code} khi kiểm tra OTP"
        except Exception as e:
            return "error", None, f"Lỗi kết nối hoặc dữ liệu khi kiểm tra OTP ({type(e).__name__})"

    @staticmethod
    def cancel_rental(provider: str, token: str, order_id: str) -> Tuple[bool, str]:
        """
        Hủy đơn thuê số nhận OTP và hoàn tiền (HupSMS hỗ trợ qua GET /cancel/:id).
        """
        clean_token = token.strip()
        if provider != "hupsms":
            return True, "ViOTP tự động hoàn tiền khi hết hạn."

        try:
            url = f"{HUPSMS_BASE}/cancel/{order_id}?api_key={clean_token}"
            res = requests.get(url, headers=OtpService._headers(clean_token), timeout=10)
            if res.status_code == 200:
                j = res.json()
                if not isinstance(j, dict) or j.get("success") is False:
                    return False, "Nhà cung cấp từ chối hủy đơn; kiểm tra trạng thái trên HupSMS."
                refund = j.get("data", {}).get("refund") if isinstance(j.get("data"), dict) else None
                if refund is not None:
                    return True, f"Nhà cung cấp xác nhận hủy; hoàn tiền: {refund} đ"
                return True, "Nhà cung cấp phản hồi hủy; chưa xác minh số tiền hoàn."
            return False, f"Không hủy được (HTTP {res.status_code}); kiểm tra trạng thái trên HupSMS."
        except Exception:
            return False, "Không liên hệ được nhà cung cấp; kiểm tra trạng thái đơn và hoàn tiền."
