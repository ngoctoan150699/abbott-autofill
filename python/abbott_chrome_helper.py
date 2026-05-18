import json
import os
import re
import threading
import time
import urllib.request
import tkinter as tk
from tkinter import messagebox, scrolledtext
from playwright.sync_api import sync_playwright

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
PEOPLE_FILE = os.path.join(BASE_DIR, "NOIDUNGDIEN.TXT")
STATE_FILE = os.path.join(BASE_DIR, "browser_helper_state.json")
VIOTP_TOKEN = "de6faac93d8d4f3294070fe48a11224b"
HOSPITAL = "BENH VIEN DA KHOA TINH QUANG NGAI"
LATITUDE = 15.114757
LONGITUDE = 108.791015


def clean_no_accent(text):
    table = str.maketrans(
        "àáạảãâầấậẩẫăằắặẳẵèéẹẻẽêềếệểễìíịỉĩòóọỏõôồốộổỗơờớợởỡùúụủũưừứựửữỳýỵỷỹđ"
        "ÀÁẠẢÃÂẦẤẬẨẪĂẰẮẶẲẴÈÉẸẺẼÊỀẾỆỂỄÌÍỊỈĨÒÓỌỎÕÔỒỐỘỔỖƠỜỚỢỞỠÙÚỤỦŨƯỪỨỰỬỮỲÝỴỶỸĐ",
        "aaaaaaaaaaaaaaaaaeeeeeeeeeeeiiiiiooooooooooooooooouuuuuuuuuuuyyyyyd"
        "AAAAAAAAAAAAAAAAAEEEEEEEEEEEIIIIIOOOOOOOOOOOOOOOOOUUUUUUUUUUUYYYYYD",
    )
    return " ".join(text.strip().translate(table).split())


def title_case(text):
    return " ".join(w[:1].upper() + w[1:].lower() for w in text.split() if w)


def format_department(raw):
    s = clean_no_accent(raw).lower()
    if "gay me" in s:
        return "Khoa Gay Me Hoi Suc"
    if "ngoai than kinh" in s:
        return "Khoa Ngoai Than Kinh"
    if "chan thuong" in s or "chinh hinh" in s or "bong" in s:
        return "Khoa Chan Thuong Chinh Hinh - Bong"
    return title_case(clean_no_accent(raw))


def format_title(raw):
    s = clean_no_accent(raw).lower().replace(".", "").strip()
    if s == "bs" or "bac si" in s or "bac sy" in s:
        return "Bac Sy Dieu Tri"
    if "truong" in s:
        return "Dieu Duong Truong"
    if s == "dd" or "dieu duong" in s:
        return "Dieu Duong"
    return title_case(clean_no_accent(raw))


def convert_people_text(raw_text):
    people = []
    for line in raw_text.splitlines():
        line = line.strip().rstrip(',')
        if not line or " là " in line.lower():
            continue
        # Hỗ trợ cả dạng "ngoại thần kinh-dd" không có khoảng trắng quanh dấu gạch.
        parts = [p.strip() for p in line.split("-")]
        if len(parts) >= 2:
            raw_dept = parts[1]
            raw_role = parts[2] if len(parts) > 2 else ""
            people.append({
                "name": parts[0],
                "department": format_department(raw_dept),
                "role": format_title(raw_role),
            })
    return people


def load_people():
    if not os.path.exists(PEOPLE_FILE):
        return []
    with open(PEOPLE_FILE, "r", encoding="utf-8") as f:
        return convert_people_text(f.read())


def api_get(url):
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
    with urllib.request.urlopen(req, timeout=15) as r:
        return json.loads(r.read().decode("utf-8"))


class ChromeHelper:
    def __init__(self, log):
        self.log = log
        self.playwright = None
        self.browser = None
        self.context = None
        self.page = None
        self.abbott_service_id = None
        self.request_id = None
        self.phone = ""
        self.otp = ""

    def start(self):
        if self.browser:
            return
        self.log("Đang mở Chrome bằng Playwright...")
        self.playwright = sync_playwright().start()
        user_data_dir = os.path.join(BASE_DIR, "chrome_profile")
        self.context = self.playwright.chromium.launch_persistent_context(
            user_data_dir=user_data_dir,
            headless=False,
            channel="chrome",
            viewport={"width": 430, "height": 860},
            is_mobile=True,
            has_touch=True,
            locale="vi-VN",
            timezone_id="Asia/Ho_Chi_Minh",
            geolocation={"latitude": LATITUDE, "longitude": LONGITUDE, "accuracy": 10},
            permissions=["geolocation"],
            args=[
                "--disable-blink-features=AutomationControlled",
                "--use-fake-ui-for-media-stream",
            ],
        )
        self.page = self.context.pages[0] if self.context.pages else self.context.new_page()
        self.context.grant_permissions(["geolocation"], origin="https://*/*")
        self.log("Chrome đã mở. Vị trí GPS đã set Nghĩa Lộ, Quảng Ngãi.")

    def open_url(self, url):
        self.start()
        if not url.startswith("http"):
            url = "https://" + url
        self.log(f"Đang mở: {url}")
        self.page.goto(url, wait_until="domcontentloaded", timeout=60000)
        self.page.wait_for_timeout(1500)
        self.log(f"Đã mở trang: {self.page.title()}")

    def get_service_id(self):
        if self.abbott_service_id:
            return self.abbott_service_id
        data = api_get(f"https://api.viotp.com/service/getv2?token={VIOTP_TOKEN}&country=vn")
        if data.get("status_code") != 200:
            raise RuntimeError(data.get("message", "Lỗi lấy service"))
        for s in data.get("data", []):
            if "abbott" in str(s.get("name", "")).lower():
                self.abbott_service_id = s["id"]
                return self.abbott_service_id
        raise RuntimeError("Không tìm thấy dịch vụ Abbott trên ViOTP")

    def rent_phone(self):
        sid = self.get_service_id()
        data = api_get(f"https://api.viotp.com/request/getv2?token={VIOTP_TOKEN}&serviceId={sid}")
        if data.get("status_code") != 200:
            raise RuntimeError(data.get("message", "Lỗi thuê số"))
        phone = str(data["data"]["phone_number"])
        if not phone.startswith("0"):
            phone = "0" + phone
        self.phone = phone
        self.request_id = str(data["data"]["request_id"])
        self.log(f"Đã lấy SĐT: {phone} | request_id={self.request_id}")
        return phone

    def get_otp(self):
        if not self.request_id:
            raise RuntimeError("Chưa thuê số")
        data = api_get(f"https://api.viotp.com/session/getv2?requestId={self.request_id}&token={VIOTP_TOKEN}")
        if data.get("status_code") != 200:
            raise RuntimeError(data.get("message", "Lỗi lấy OTP"))
        status = data["data"].get("Status")
        if status == 1:
            self.otp = str(data["data"].get("Code", ""))
            self.log(f"Đã nhận OTP: {self.otp}")
            return self.otp
        if status == 0:
            self.log("OTP chưa về, bấm lại sau vài giây.")
            return ""
        raise RuntimeError("Phiên OTP hết hạn hoặc lỗi")

    def close(self):
        try:
            if self.context:
                self.context.close()
            if self.playwright:
                self.playwright.stop()
        except Exception:
            pass


class App:
    def __init__(self):
        self.people = load_people()
        self.index = 0
        self.helper = ChromeHelper(self.log)

        self.root = tk.Tk()
        self.root.title("Abbott Chrome Helper - dùng Chrome thật")
        self.root.geometry("720x520")
        self.root.protocol("WM_DELETE_WINDOW", self.on_close)

        self.url_var = tk.StringVar()
        self.phone_var = tk.StringVar()
        self.otp_var = tk.StringVar()
        self.person_var = tk.StringVar()
        self.otp_polling = False
        self.otp_btn = None

        top = tk.Frame(self.root)
        top.pack(fill="x", padx=8, pady=8)
        tk.Entry(top, textvariable=self.url_var).pack(side="left", fill="x", expand=True)
        tk.Button(top, text="Mở bằng Chrome", command=self.open_url).pack(side="left", padx=5)

        row1 = tk.Frame(self.root)
        row1.pack(fill="x", padx=8, pady=5)
        tk.Button(row1, text="1. Lấy SĐT", command=self.rent_phone).pack(side="left")
        tk.Entry(row1, textvariable=self.phone_var, width=20).pack(side="left", padx=5)
        tk.Button(row1, text="Copy SĐT", command=lambda: self.copy(self.phone_var.get(), "SĐT")).pack(side="left")
        self.otp_btn = tk.Button(row1, text="2. Lấy OTP tự động 60s", command=self.get_otp)
        self.otp_btn.pack(side="left", padx=15)
        tk.Entry(row1, textvariable=self.otp_var, width=18).pack(side="left", padx=5)
        tk.Button(row1, text="Copy OTP", command=lambda: self.copy(self.otp_var.get(), "OTP")).pack(side="left")

        row2 = tk.Frame(self.root)
        row2.pack(fill="x", padx=8, pady=5)
        tk.Label(row2, textvariable=self.person_var, fg="red", font=("Arial", 10, "bold")).pack(side="left", fill="x", expand=True)
        tk.Button(row2, text="<<", command=self.prev_person).pack(side="left")
        tk.Button(row2, text="Tiếp theo >>", command=self.next_person).pack(side="left")

        row3 = tk.Frame(self.root)
        row3.pack(fill="x", padx=8, pady=5)
        tk.Button(row3, text="Copy Tên", command=lambda: self.copy_field("name", "Tên")).pack(side="left", padx=2)
        tk.Button(row3, text="Copy Phòng Ban", command=lambda: self.copy_field("department", "Phòng ban")).pack(side="left", padx=2)
        tk.Button(row3, text="Copy Chức Danh", command=lambda: self.copy_field("role", "Chức danh")).pack(side="left", padx=2)
        tk.Button(row3, text="Copy Vai trò", command=lambda: self.copy("Người tham dự", "Vai trò")).pack(side="left", padx=2)
        tk.Button(row3, text="Copy Bệnh viện", command=lambda: self.copy(HOSPITAL, "Bệnh viện")).pack(side="left", padx=2)

        row4 = tk.Frame(self.root)
        row4.pack(fill="x", padx=8, pady=5)
        tk.Button(row4, text="Nhập/Sửa danh sách", command=self.open_people_editor, bg="#fff3cd").pack(side="left", padx=2)
        tk.Button(row4, text="Reload danh sách từ TXT", command=self.reload_people).pack(side="left", padx=2)
        tk.Button(row4, text="Copy tất cả đã chuẩn hóa", command=self.copy_all_converted).pack(side="left", padx=2)

        self.logs = scrolledtext.ScrolledText(self.root, height=15)
        self.logs.pack(fill="both", expand=True, padx=8, pady=8)
        self.update_person()
        self.log("Tool này mở Chrome thật bằng Python Playwright, load web giống Chrome hơn PyQt WebEngine.")

    def run_thread(self, fn):
        def wrapper():
            try:
                fn()
            except Exception as e:
                self.log(f"LỖI: {e}")
                messagebox.showerror("Lỗi", str(e))
        threading.Thread(target=wrapper, daemon=True).start()

    def open_url(self):
        self.run_thread(lambda: self.helper.open_url(self.url_var.get().strip()))

    def rent_phone(self):
        def job():
            phone = self.helper.rent_phone()
            self.root.after(0, lambda: self.phone_var.set(phone))
            self.root.after(0, lambda: self.copy(phone, "SĐT"))
        self.run_thread(job)

    def get_otp(self):
        if self.otp_polling:
            self.log("Đang tự động chờ OTP, vui lòng đợi...")
            return

        def job():
            self.otp_polling = True
            self.root.after(0, lambda: self.otp_var.set("Đang chờ 60s..."))
            if self.otp_btn:
                self.root.after(0, lambda: self.otp_btn.config(state="disabled", text="Đang chờ OTP..."))
            start_time = time.time()
            try:
                attempt = 0
                while time.time() - start_time < 60:
                    attempt += 1
                    remaining = max(0, 60 - int(time.time() - start_time))
                    self.log(f"Đang kiểm tra OTP lần {attempt}, còn {remaining}s...")
                    self.root.after(0, lambda r=remaining: self.otp_var.set(f"Chờ OTP... {r}s"))
                    otp = self.helper.get_otp()
                    if otp:
                        self.root.after(0, lambda: self.otp_var.set(otp))
                        self.root.after(0, lambda: self.copy(otp, "OTP"))
                        self.log("Đã dừng chờ vì nhận được OTP.")
                        return
                    time.sleep(1)
                self.root.after(0, lambda: self.otp_var.set("Không lấy được OTP"))
                self.log("Sau 60s không có mã OTP. Đã dừng.")
                self.root.after(0, lambda: messagebox.showwarning("Không có OTP", "Không lấy mã OTP được sau 60 giây."))
            finally:
                self.otp_polling = False
                if self.otp_btn:
                    self.root.after(0, lambda: self.otp_btn.config(state="normal", text="2. Lấy OTP tự động 60s"))

        self.run_thread(job)

    def copy(self, text, label):
        if not text:
            return
        self.root.clipboard_clear()
        self.root.clipboard_append(text)
        self.log(f"Đã copy {label}: {text}")

    def current_person(self):
        if not self.people:
            return {}
        return self.people[self.index]

    def copy_field(self, field, label):
        self.copy(self.current_person().get(field, ""), label)

    def reload_people(self):
        self.people = load_people()
        if self.index >= len(self.people):
            self.index = 0
        self.update_person()
        self.log(f"Đã reload {len(self.people)} người từ NOIDUNGDIEN.TXT")

    def open_people_editor(self):
        win = tk.Toplevel(self.root)
        win.title("Nhập/Sửa danh sách người tham dự")
        win.geometry("820x560")
        tk.Label(
            win,
            text="Dán danh sách theo dạng: Họ tên - phòng ban - chức danh. Không giới hạn số dòng.",
            font=("Arial", 10, "bold"),
        ).pack(anchor="w", padx=8, pady=6)
        text = scrolledtext.ScrolledText(win, height=22)
        text.pack(fill="both", expand=True, padx=8, pady=5)
        current = ""
        if os.path.exists(PEOPLE_FILE):
            with open(PEOPLE_FILE, "r", encoding="utf-8") as f:
                current = f.read()
        text.insert("1.0", current)

        preview = scrolledtext.ScrolledText(win, height=8)
        preview.pack(fill="both", expand=False, padx=8, pady=5)

        def make_preview():
            raw = text.get("1.0", "end").strip()
            rows = convert_people_text(raw)
            preview.delete("1.0", "end")
            for i, p in enumerate(rows, 1):
                preview.insert("end", f"{i}. {p['name']} | {p['department']} | {p['role']}\n")
            self.log(f"Preview: {len(rows)} người hợp lệ")

        def save_and_reload():
            raw = text.get("1.0", "end").strip()
            with open(PEOPLE_FILE, "w", encoding="utf-8") as f:
                f.write(raw + "\n")
            self.reload_people()
            win.destroy()

        btns = tk.Frame(win)
        btns.pack(fill="x", padx=8, pady=8)
        tk.Button(btns, text="Xem trước chuẩn hóa", command=make_preview).pack(side="left", padx=4)
        tk.Button(btns, text="Lưu vào NOIDUNGDIEN.TXT và dùng ngay", command=save_and_reload, bg="#d4edda").pack(side="left", padx=4)
        tk.Button(btns, text="Đóng", command=win.destroy).pack(side="right", padx=4)

    def copy_all_converted(self):
        rows = []
        for p in self.people:
            rows.append(f"{p['name']} | {p['department']} | {p['role']}")
        self.copy("\n".join(rows), "toàn bộ danh sách chuẩn hóa")

    def update_person(self):
        if not self.people:
            self.person_var.set("Không có dữ liệu NOIDUNGDIEN.TXT")
            return
        p = self.current_person()
        self.person_var.set(f"Người {self.index + 1}/{len(self.people)}: {p['name']} | {p['department']} | {p['role']}")

    def next_person(self):
        if self.people:
            self.index = (self.index + 1) % len(self.people)
            self.update_person()

    def prev_person(self):
        if self.people:
            self.index = (self.index - 1) % len(self.people)
            self.update_person()

    def log(self, msg):
        def write():
            self.logs.insert("end", f"[{time.strftime('%H:%M:%S')}] {msg}\n")
            self.logs.see("end")
        if hasattr(self, "root"):
            self.root.after(0, write)
        else:
            print(msg)

    def on_close(self):
        self.helper.close()
        self.root.destroy()

    def run(self):
        self.root.mainloop()


if __name__ == "__main__":
    App().run()
