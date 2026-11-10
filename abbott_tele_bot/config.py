import os
import json
import re
from datetime import datetime

CURRENT_DIR = os.path.dirname(os.path.abspath(__file__))
DATA_DIR = os.path.join(CURRENT_DIR, "data")
SCREENSHOTS_DIR = os.path.join(CURRENT_DIR, "screenshots")
CONFIG_FILE = os.path.join(DATA_DIR, "config.json")

os.makedirs(DATA_DIR, exist_ok=True)
os.makedirs(SCREENSHOTS_DIR, exist_ok=True)

DEFAULT_HOSPITALS = [
    "BENH VIEN DA KHOA TINH QUANG NGAI",
    "BENH VIEN NOI TIET TINH QUANG NGAI",
    "BENH VIEN DA KHOA PHUC HUNG",
    "BENH VIEN SAN NHI QUANG NGAI",
    "BENH VIEN SAN - NHI QUANG NAM",
]

DEFAULT_CONFIG = {
    "bot_token": os.environ.get("BOT_TOKEN", ""),
    "admin_ids": [5345379297, 6806742784],  # Admin Chat IDs mặc định
    "otp_provider": "hupsms",               # 'hupsms' hoặc 'viotp'
    "hupsms_api_key": "",
    "hupsms_service_id": None,              # Tự dò hoặc chọn thủ công
    "hupsms_server_id": "247",              # Server ưu tiên (Server 247 giá 1.500đ)
    "viotp_token": "",
    "viotp_service_id": None,
    "selected_hospital": "BENH VIEN DA KHOA TINH QUANG NGAI",
    "hospitals": DEFAULT_HOSPITALS,
    "default_role": "Nguoi tham du",
    "otp_timeout": 60,
    "delay_ms": 700,
    "people": [],
    "active_event_url": "",
    "event_info": {},
    "is_auto_running": False,
    "submit_mode": "review",  # ponytail: chỉ hai chế độ; thêm cấu hình timeout khi cần vận hành dài.
}

VIETNAMESE_ACCENTS = {
    'à': 'a', 'á': 'a', 'ạ': 'a', 'ả': 'a', 'ã': 'a', 'â': 'a', 'ầ': 'a', 'ấ': 'a', 'ậ': 'a', 'ẩ': 'a', 'ẫ': 'a',
    'ă': 'a', 'ằ': 'a', 'ắ': 'a', 'ặ': 'a', 'ẳ': 'a', 'ẵ': 'a',
    'è': 'e', 'é': 'e', 'ẹ': 'e', 'ẻ': 'e', 'ẽ': 'e', 'ê': 'e', 'ề': 'e', 'ế': 'e', 'ệ': 'e', 'ể': 'e', 'ễ': 'e',
    'ì': 'i', 'í': 'i', 'ị': 'i', 'ỉ': 'i', 'ĩ': 'i',
    'ò': 'o', 'ó': 'o', 'ọ': 'o', 'ỏ': 'o', 'õ': 'o', 'ô': 'o', 'ồ': 'o', 'ố': 'o', 'ộ': 'o', 'ổ': 'o', 'ỗ': 'o',
    'ơ': 'o', 'ờ': 'o', 'ớ': 'o', 'ợ': 'o', 'ở': 'o', 'ỡ': 'o',
    'ù': 'u', 'ú': 'u', 'ụ': 'u', 'ủ': 'u', 'ũ': 'u', 'ư': 'u', 'ừ': 'u', 'ứ': 'u', 'ự': 'u', 'ử': 'u', 'ữ': 'u',
    'ỳ': 'y', 'ý': 'y', 'ỵ': 'y', 'ỷ': 'y', 'ỹ': 'y', 'đ': 'd',
    'À': 'A', 'Á': 'A', 'Ạ': 'A', 'Ả': 'A', 'Ã': 'A', 'Â': 'A', 'Ầ': 'A', 'Ấ': 'A', 'Ậ': 'A', 'Ẩ': 'A', 'Ẫ': 'A',
    'Ă': 'A', 'Ằ': 'A', 'Ắ': 'A', 'Ặ': 'A', 'Ẳ': 'A', 'Ẵ': 'A',
    'È': 'E', 'É': 'E', 'Ẹ': 'E', 'Ẻ': 'E', 'Ẽ': 'E', 'Ê': 'E', 'Ề': 'E', 'Ế': 'E', 'Ệ': 'E', 'Ể': 'E', 'Ễ': 'E',
    'Ì': 'I', 'Í': 'I', 'Ị': 'I', 'Ỉ': 'I', 'Ĩ': 'I',
    'Ò': 'O', 'Ó': 'O', 'Ọ': 'O', 'Ỏ': 'O', 'Õ': 'O', 'Ô': 'O', 'Ồ': 'O', 'Ố': 'O', 'Ộ': 'O', 'Ổ': 'O', 'Ỗ': 'O',
    'Ơ': 'O', 'Ờ': 'O', 'Ớ': 'O', 'Ợ': 'O', 'Ở': 'O', 'Ỡ': 'O',
    'Ù': 'U', 'Ú': 'U', 'Ụ': 'U', 'Ủ': 'U', 'Ũ': 'U', 'Ư': 'U', 'Ừ': 'U', 'Ứ': 'U', 'Ự': 'U', 'Ử': 'U', 'Ữ': 'U',
    'Ỳ': 'Y', 'Ý': 'Y', 'Ỵ': 'Y', 'Ỷ': 'Y', 'Ỹ': 'Y', 'Đ': 'D'
}

STANDARD_DEPARTMENTS = [
    "Khoa Noi Tim Mach",
    "Khoa Phau Thuat Gay Me - Hoi Suc",
    "Khoa Kham Benh & Cap Cuu",
    "Khoa Noi Tong Hop",
    "Khoa Duoc",
    "Khoa Ngoai Tong Hop",
    "Khoa Ngoai Than Kinh",
    "Khoa Ngoai Tieu Hoa",
    "Khoa Hoi Suc Tich Cuc - Chong Doc",
    "Khoa Chan Thuong Chinh Hinh - Bong",
    "Khoa Chan Doan Hinh Anh",
    "Khoa Than Nhan Tao",
    "Khoa Noi Tieu Hoa",
    "Khoa Kiem Soat Nhiem Khuan",
    "Khoa Huyet Hoc",
    "Khoa Noi Than Kinh",
    "Khoa Dieu Tri Yeu Cau",
    "Khoa Benh Nhiet Doi",
    "Khoa Hoa Sinh",
    "Khoa Phuc Hoi Chuc Nang",
    "Khoa Rang Ham Mat",
    "Khoa Tai Mui Hong",
    "Khoa Mat",
    "Khoa Vi Sinh",
    "Khoa Giai Phau Benh",
    "Khoa Da Lieu",
    "Phong Dieu Duong",
    "Ban Giam Doc",
    "Khoa Dinh Duong",
    "Khoa Ung Buou",
    "Khoa San",
    "Khoa Nhi",
    "Khac",
]

STANDARD_ROLES = [
    "Y Ta Truong/ Dieu Duong Truong",
    "Giam Doc",
    "Duoc sy",
    "Pho Giam Doc",
    "Truong Khoa",
    "Pho Khoa",
    "Bac Sy Dieu Tri",
    "Y ta/ Dieu duong",
]


def clean_no_accent(text: str) -> str:
    out = text.strip()
    for k, v in VIETNAMESE_ACCENTS.items():
        out = out.replace(k, v)
    return " ".join(out.split())


def title_case(text: str) -> str:
    return " ".join(w[:1].upper() + w[1:].lower() for w in text.split() if w)


def format_department(raw: str) -> str:
    s = clean_no_accent(raw).lower()
    if s in ["khac", "khoa khac", "phong ban khac", "phong khac"]:
        return "Khac"
    for d in STANDARD_DEPARTMENTS:
        if clean_no_accent(d).lower() == s:
            return d
    if "gay me" in s:
        return "Khoa Phau Thuat Gay Me - Hoi Suc"
    if "ngoai than kinh" in s:
        return "Khoa Ngoai Than Kinh"
    if "ngoai tieu hoa" in s:
        return "Khoa Ngoai Tieu Hoa"
    if "noi tong hop" in s:
        return "Khoa Noi Tong Hop"
    if "ngoai tong hop" in s:
        return "Khoa Ngoai Tong Hop"
    if "tim mach" in s:
        return "Khoa Noi Tim Mach"
    if "cap cuu" in s or "kham benh" in s:
        return "Khoa Kham Benh & Cap Cuu"
    if "duoc" in s:
        return "Khoa Duoc"

    # Chỉ gửi lên Abbott các giá trị có trong danh mục; còn lại chọn Khác + nhập tay.
    return "Khac"


def format_role(raw: str) -> str:
    s = clean_no_accent(raw).lower().replace(".", "").strip()
    if s in ("bs", "dd") or s.startswith("bs "):
        return "Bac Sy Dieu Tri" if s.startswith("bs") else "Y ta/ Dieu duong"
    if "truong" in s and ("y ta" in s or "dieu duong" in s):
        return "Y Ta Truong/ Dieu Duong Truong"
    if "bac si" in s or "bac sy" in s:
        return "Bac Sy Dieu Tri"
    if "giam doc" in s and "pho" not in s:
        return "Giam Doc"
    if "pho giam doc" in s:
        return "Pho Giam Doc"
    if "truong khoa" in s:
        return "Truong Khoa"
    if "pho khoa" in s:
        return "Pho Khoa"
    if "duoc" in s:
        return "Duoc sy"
    if s == "dd" or "dieu duong" in s or "y ta" in s:
        return "Y ta/ Dieu duong"
    t = title_case(clean_no_accent(raw))
    if t in STANDARD_ROLES:
        return t
    raise ValueError(f"Chức danh không nhận diện được: {raw}")


def parse_people_lines(text: str, default_hospital: str = "") -> list:
    """
    Phân tích văn bản nhiều dòng thành danh sách người tham gia:
    Họ tên - Khoa/Phòng - Chức danh [- Bệnh viện]
    Họ tên - Khoa Khác - Tên khoa thực tế - Chức danh [- Bệnh viện]
    """
    people = []
    for line_number, line in enumerate(text.splitlines(), 1):
        line = line.strip()
        if not line:
            continue
        parts = [part.strip() for part in re.split(r"\s+-\s+", line)]
        if len(parts) not in (3, 4, 5) or not all(parts):
            raise ValueError(f"Dòng {line_number}: cần Tên - Khoa - Chức danh (hoặc Tên - Khoa Khác - Tên khoa - Chức danh).")
        name, first, second = parts[:3]
        explicit_other = clean_no_accent(first).lower() in ("khac", "khoa khac", "phong ban khac", "phong khac") and len(parts) >= 4
        if explicit_other:
            if len(parts) not in (4, 5):
                raise ValueError(f"Dòng {line_number}: cần Tên - Khoa Khác - Tên khoa - Chức danh [- Bệnh viện].")
            raw_dept, other_dept, raw_role = first, second, parts[3]
            hospital = parts[4] if len(parts) == 5 else default_hospital
        else:
            if len(parts) == 5:
                raise ValueError(f"Dòng {line_number}: cần Khoa Khác để nhập tên khoa riêng.")
            # ponytail: nhận diện các chức danh Abbott đã biết; thêm alias tại đây khi xuất hiện chức danh mới.
            def role_like(value):
                s = clean_no_accent(value).lower()
                return s in ("bs", "dd") or s.startswith("bs ") or any(word in s for word in
                    ("bac si", "bac sy", "dieu duong", "y ta", "duoc si", "duoc sy", "giam doc", "truong khoa", "pho khoa"))

            first_role, second_role = role_like(first), role_like(second)
            if first_role == second_role:
                raise ValueError(f"Dòng {line_number}: không phân biệt được Khoa và Chức danh: {line}")
            raw_role, raw_dept = (first, second) if first_role else (second, first)
            hospital = parts[3] if len(parts) == 4 else default_hospital
            other_dept = ""
        dept = format_department(raw_dept)
        if dept == "Khac" and not other_dept:
            if clean_no_accent(raw_dept).lower() in ("khac", "khoa khac", "phong ban khac", "phong khac"):
                raise ValueError(f"Dòng {line_number}: Khoa Khác cần tên khoa riêng (Tên - Khoa Khác - Tên khoa - Chức danh).")
            other_dept = raw_dept
        try:
            role = format_role(raw_role)
        except ValueError as e:
            raise ValueError(f"Dòng {line_number}: {e}") from e
        people.append({
            "name": name,
            "department": dept,
            "otherDepartment": other_dept,
            "role": role,
            "hospital": hospital,
        })
    return people


def normalize_people_lines(text: str, default_hospital: str = "") -> str:
    """Trả danh sách chuẩn có thể sao chép dán ngược vào bot."""
    departments = {
        "Khoa Ngoai Tong Hop": "Khoa Ngoại Tổng Hợp",
        "Khoa Ngoai Than Kinh": "Khoa Ngoại Thần Kinh",
        "Khoa Ngoai Tieu Hoa": "Khoa Ngoại Tiêu Hóa",
    }
    roles = {
        "Bac Sy Dieu Tri": "Bác Sỹ Điều Trị",
        "Y Ta Truong/ Dieu Duong Truong": "Y Tá Trưởng/Điều Dưỡng Trưởng",
        "Y ta/ Dieu duong": "Y Tá/Điều Dưỡng",
    }
    lines = []
    for p, original in zip(parse_people_lines(text, default_hospital), (l for l in text.splitlines() if l.strip())):
        parts = re.split(r"\s+-\s+", original.strip())
        explicit_other = clean_no_accent(parts[1]).lower() in ("khac", "khoa khac", "phong ban khac", "phong khac")
        has_hospital = len(parts) == (5 if explicit_other else 4)
        dept = f"Khoa Khác - {p['otherDepartment']}" if p['department'] == "Khac" else departments.get(p['department'], p['department'])
        lines.append(f"{p['name']} - {dept} - {roles.get(p['role'], p['role'])}" +
                     (f" - {p['hospital']}" if has_hospital else ""))
    return "\n".join(lines)


def load_config() -> dict:
    if os.path.exists(CONFIG_FILE):
        try:
            with open(CONFIG_FILE, "r", encoding="utf-8") as f:
                saved = json.load(f)
                merged = dict(DEFAULT_CONFIG)
                merged.update(saved)
                return merged
        except Exception as e:
            print(f"[!] Lỗi đọc config: {e}")
    return dict(DEFAULT_CONFIG)


def save_config(cfg: dict):
    try:
        with open(CONFIG_FILE, "w", encoding="utf-8") as f:
            json.dump(cfg, f, ensure_ascii=False, indent=2)
    except Exception as e:
        print(f"[!] Lỗi lưu config: {e}")
