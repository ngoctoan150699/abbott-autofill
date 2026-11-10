import re
from datetime import datetime, timedelta
from typing import Optional, Tuple, Dict, Any
from urllib.parse import urlparse, parse_qs
import cv2
import numpy as np


def read_qr_from_file(file_path: str) -> Optional[str]:
    """
    Quét và giải mã QR Code từ file ảnh sử dụng OpenCV QRCodeDetector.
    Áp dụng nhiều bộ lọc tăng cường độ tương phản nếu ảnh chụp màn hình bị tối/lóa.
    """
    try:
        img = cv2.imread(file_path)
        if img is None:
            return None

        detector = cv2.QRCodeDetector()

        # 1. Thử giải mã ảnh gốc
        data, bbox, _ = detector.detectAndDecode(img)
        if data and data.strip():
            return data.strip()

        # 2. Thử ảnh grayscale
        gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
        data, bbox, _ = detector.detectAndDecode(gray)
        if data and data.strip():
            return data.strip()

        # 3. Thử ngưỡng nhị phân Otsu
        _, thresh = cv2.threshold(gray, 0, 255, cv2.THRESH_BINARY + cv2.THRESH_OTSU)
        data, bbox, _ = detector.detectAndDecode(thresh)
        if data and data.strip():
            return data.strip()

        # 4. Thử tăng kích thước ảnh nếu QR nhỏ
        h, w = img.shape[:2]
        if w < 600 or h < 600:
            scale = 2.0
            resized = cv2.resize(gray, (int(w * scale), int(h * scale)), interpolation=cv2.INTER_CUBIC)
            data, bbox, _ = detector.detectAndDecode(resized)
            if data and data.strip():
                return data.strip()

        # 5. Thử thư viện pyzbar nếu có cài
        try:
            from pyzbar.pyzbar import decode
            from PIL import Image
            pil_img = Image.open(file_path)
            decoded = decode(pil_img)
            if decoded:
                return decoded[0].data.decode("utf-8").strip()
        except Exception:
            pass

        return None
    except Exception as e:
        print(f"[!] Lỗi quét QR: {e}")
        return None


def parse_abbott_event_url(raw_url: str) -> Dict[str, Any]:
    """
    Phân tích chi tiết URL sự kiện của Abbott:
    Ví dụ: https://spot.abbott.com/vn/api/activity/sign/checkScanSource?eventRecordNumber=104142&overTime=20261109143336&country=VIE
    """
    clean_url = raw_url.strip()
    parsed = urlparse(clean_url)
    qs = parse_qs(parsed.query)

    event_id = qs.get("eventRecordNumber", [""])[0] or qs.get("id", [""])[0] or qs.get("eventId", [""])[0]
    country = qs.get("country", ["VIE"])[0]
    raw_overtime = qs.get("overTime", [""])[0]

    over_dt = None
    time_str = "Không rõ"
    remaining_str = "Không xác định"
    is_expired = False

    if raw_overtime:
        # Chuẩn định dạng YYYYMMDDHHMMSS ví dụ: 20261109143336
        digits = re.sub(r"\D", "", raw_overtime)
        if len(digits) >= 14:
            try:
                over_dt = datetime.strptime(digits[:14], "%Y%m%d%H%M%S")
                time_str = over_dt.strftime("%H:%M:%S ngày %d/%m/%Y")
                now = datetime.now()
                if over_dt > now:
                    delta = over_dt - now
                    hours, rem = divmod(int(delta.total_seconds()), 3600)
                    minutes, seconds = divmod(rem, 60)
                    if hours > 0:
                        remaining_str = f"Còn {hours} giờ {minutes} phút"
                    elif minutes > 0:
                        remaining_str = f"Còn {minutes} phút {seconds} giây"
                    else:
                        remaining_str = f"Chỉ còn {seconds} giây!"
                    is_expired = False
                else:
                    passed = now - over_dt
                    hours, rem = divmod(int(passed.total_seconds()), 3600)
                    minutes, _ = divmod(rem, 60)
                    remaining_str = f"Đã quá hạn {hours} giờ {minutes} phút"
                    is_expired = True
            except Exception as e:
                print(f"[!] Lỗi parse overTime: {e}")

    return {
        "url": clean_url,
        "is_abbott": "spot.abbott.com" in clean_url or "abbott.com" in clean_url or "checkScanSource" in clean_url,
        "event_id": event_id,
        "country": country,
        "over_time_raw": raw_overtime,
        "over_dt": over_dt,
        "expire_time_str": time_str,
        "remaining_str": remaining_str,
        "is_expired": is_expired,
    }
