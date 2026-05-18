import sys
import os
import json
import urllib.request
import urllib.parse
from PyQt5.QtWidgets import (QApplication, QMainWindow, QWidget, QVBoxLayout, QHBoxLayout,
                             QLineEdit, QPushButton, QLabel, QTextEdit, QMessageBox, QFrame)
from PyQt5.QtWebEngineWidgets import QWebEngineView, QWebEngineProfile, QWebEngineScript, QWebEnginePage, QWebEngineSettings
from PyQt5.QtCore import QUrl, Qt, QThread, pyqtSignal

class ApiWorker(QThread):
    result = pyqtSignal(dict)
    error = pyqtSignal(str)

    def __init__(self, url):
        super().__init__()
        self.url = url

    def run(self):
        try:
            req = urllib.request.Request(self.url, headers={'User-Agent': 'Mozilla/5.0'})
            with urllib.request.urlopen(req, timeout=10) as response:
                data = json.loads(response.read().decode('utf-8'))
                self.result.emit(data)
        except Exception as e:
            self.error.emit(str(e))

class AbbottHelperApp(QMainWindow):
    def __init__(self):
        super().__init__()
        self.setWindowTitle("Abbott Event Helper - PC Tool")
        self.setGeometry(100, 100, 1000, 800)

        self.viotp_token = "de6faac93d8d4f3294070fe48a11224b"
        self.abbott_service_id = None
        self.current_request_id = None
        self.people = []
        self.current_person_index = 0

        self.init_ui()
        self.load_people_data()

    def init_ui(self):
        central_widget = QWidget()
        self.setCentralWidget(central_widget)
        main_layout = QVBoxLayout(central_widget)

        # URL Bar
        url_layout = QHBoxLayout()
        self.url_input = QLineEdit()
        self.url_input.setPlaceholderText("Dán link trang đăng nhập Abbott vào đây và nhấn Mở...")
        self.url_input.returnPressed.connect(self.load_url)
        btn_load = QPushButton("Mở Web")
        btn_load.clicked.connect(self.load_url)
        url_layout.addWidget(self.url_input)
        url_layout.addWidget(btn_load)
        main_layout.addLayout(url_layout)

        # WebView
        self.webview = QWebEngineView()
        profile = self.webview.page().profile()
        profile.setHttpUserAgent(
            "Mozilla/5.0 (Linux; Android 13; SM-G991B) "
            "AppleWebKit/537.36 (KHTML, like Gecko) "
            "Chrome/124.0.0.0 Mobile Safari/537.36"
        )
        settings = self.webview.settings()
        settings.setAttribute(QWebEngineSettings.JavascriptEnabled, True)
        settings.setAttribute(QWebEngineSettings.LocalStorageEnabled, True)
        settings.setAttribute(QWebEngineSettings.WebGLEnabled, True)
        settings.setAttribute(QWebEngineSettings.Accelerated2dCanvasEnabled, True)
        self.webview.loadStarted.connect(lambda: self.statusBar().showMessage("Đang tải trang..."))
        self.webview.loadFinished.connect(self.on_load_finished)
        self.webview.titleChanged.connect(lambda title: self.statusBar().showMessage(f"Trang: {title}", 3000))
        
        # Inject JavaScript to Mock Geolocation
        mock_geo_js = """
        (function() {
            navigator.geolocation.getCurrentPosition = function(success, error, options) {
                var position = {
                    coords: { latitude: 15.114757, longitude: 108.791015, accuracy: 10 },
                    timestamp: Date.now()
                };
                success(position);
            };
            navigator.geolocation.watchPosition = function(success, error, options) {
                navigator.geolocation.getCurrentPosition(success, error, options);
                return Math.floor(Math.random() * 10000);
            };
        })();
        """
        script = QWebEngineScript()
        script.setSourceCode(mock_geo_js)
        script.setInjectionPoint(QWebEngineScript.DocumentCreation)
        script.setWorldId(QWebEngineScript.MainWorld)
        self.webview.page().profile().scripts().insert(script)
        
        # Auto-grant permissions (like Geolocation)
        self.webview.page().featurePermissionRequested.connect(self.grant_permissions)

        main_layout.addWidget(self.webview, stretch=1)

        # Control Panel
        control_frame = QFrame()
        control_frame.setFrameShape(QFrame.StyledPanel)
        control_layout = QVBoxLayout(control_frame)

        # ViOTP actions
        viotp_layout = QHBoxLayout()
        
        btn_get_phone = QPushButton("1. Lấy SĐT Mới")
        btn_get_phone.clicked.connect(self.get_phone_number)
        btn_get_phone.setStyleSheet("background-color: #4CAF50; color: white; font-weight: bold;")
        self.phone_input = QLineEdit()
        self.phone_input.setReadOnly(True)
        self.phone_input.setPlaceholderText("SĐT sẽ hiện ở đây...")
        btn_copy_phone = QPushButton("Copy SĐT")
        btn_copy_phone.clicked.connect(lambda: self.copy_to_clipboard(self.phone_input.text(), "Số điện thoại"))
        
        btn_get_otp = QPushButton("2. Lấy OTP")
        btn_get_otp.clicked.connect(self.get_otp)
        btn_get_otp.setStyleSheet("background-color: #2196F3; color: white; font-weight: bold;")
        self.otp_input = QLineEdit()
        self.otp_input.setReadOnly(True)
        self.otp_input.setPlaceholderText("Mã OTP...")
        btn_copy_otp = QPushButton("Copy OTP")
        btn_copy_otp.clicked.connect(lambda: self.copy_to_clipboard(self.otp_input.text(), "Mã OTP"))

        viotp_layout.addWidget(btn_get_phone)
        viotp_layout.addWidget(self.phone_input)
        viotp_layout.addWidget(btn_copy_phone)
        viotp_layout.addSpacing(20)
        viotp_layout.addWidget(btn_get_otp)
        viotp_layout.addWidget(self.otp_input)
        viotp_layout.addWidget(btn_copy_otp)
        control_layout.addLayout(viotp_layout)

        # Data filler
        data_layout = QHBoxLayout()
        self.lbl_person = QLabel("Chưa có dữ liệu người dùng")
        self.lbl_person.setStyleSheet("font-weight: bold; color: #D32F2F;")
        
        btn_prev = QPushButton("<< Trở lại")
        btn_prev.clicked.connect(self.prev_person)
        btn_next = QPushButton("Tiếp theo >>")
        btn_next.clicked.connect(self.next_person)

        data_layout.addWidget(self.lbl_person)
        data_layout.addStretch()
        data_layout.addWidget(btn_prev)
        data_layout.addWidget(btn_next)
        control_layout.addLayout(data_layout)

        # Copy buttons for data
        copy_layout = QHBoxLayout()
        btn_copy_name = QPushButton("Copy Tên")
        btn_copy_name.clicked.connect(lambda: self.copy_person_field('name', 'Họ Tên'))
        
        btn_copy_dept = QPushButton("Copy Phòng Ban")
        btn_copy_dept.clicked.connect(lambda: self.copy_person_field('department', 'Phòng Ban'))
        
        btn_copy_role = QPushButton("Copy Chức Danh")
        btn_copy_role.clicked.connect(lambda: self.copy_person_field('role', 'Chức Danh'))

        btn_copy_static_role = QPushButton("Copy Vai Trò (Người tham dự)")
        btn_copy_static_role.clicked.connect(lambda: self.copy_to_clipboard("Người tham dự", "Vai trò"))
        
        btn_copy_hospital = QPushButton("Copy Bệnh Viện")
        btn_copy_hospital.clicked.connect(lambda: self.copy_to_clipboard("BENH VIEN DA KHOA TINH QUANG NGAI", "Bệnh Viện"))

        copy_layout.addWidget(btn_copy_name)
        copy_layout.addWidget(btn_copy_dept)
        copy_layout.addWidget(btn_copy_role)
        copy_layout.addWidget(btn_copy_static_role)
        copy_layout.addWidget(btn_copy_hospital)
        control_layout.addLayout(copy_layout)

        main_layout.addWidget(control_frame)

    def grant_permissions(self, url, feature):
        if feature == QWebEnginePage.Geolocation:
            self.webview.page().setFeaturePermission(url, feature, QWebEnginePage.PermissionGrantedByUser)

    def load_url(self):
        url = self.url_input.text().strip()
        if url:
            if not url.startswith('http'):
                url = 'https://' + url
            qurl = QUrl.fromUserInput(url)
            self.statusBar().showMessage(f"Đang tải: {qurl.toString()} ...")
            self.webview.setHtml("<html><body style='font-family:Arial;text-align:center;padding-top:80px;background:#071b33;color:white'><h2>Đang mở trang...</h2><p>Vui lòng chờ vài giây</p></body></html>")
            self.webview.load(qurl)
            
    def on_load_finished(self, ok):
        current_url = self.webview.url().toString()
        if ok:
            self.statusBar().showMessage(f"Tải trang thành công: {current_url}", 5000)
            self.webview.page().runJavaScript("document.body ? document.body.innerText.slice(0,120) : 'NO_BODY'", self.debug_page_text)
        else:
            self.statusBar().showMessage("Lỗi: Không thể tải trang!", 5000)
            QMessageBox.warning(self, "Lỗi Tải Trang", "Trang web không thể tải được. Hãy kiểm tra lại link hoặc mạng.")

    def debug_page_text(self, text):
        if not text or text == 'NO_BODY':
            self.statusBar().showMessage("Trang đã load nhưng nội dung trống - có thể web chặn WebView/Chromium cũ.", 8000)

    def clean_no_accent(self, text):
        table = str.maketrans(
            "àáạảãâầấậẩẫăằắặẳẵèéẹẻẽêềếệểễìíịỉĩòóọỏõôồốộổỗơờớợởỡùúụủũưừứựửữỳýỵỷỹđ"
            "ÀÁẠẢÃÂẦẤẬẨẪĂẰẮẶẲẴÈÉẸẺẼÊỀẾỆỂỄÌÍỊỈĨÒÓỌỎÕÔỒỐỘỔỖƠỜỚỢỞỠÙÚỤỦŨƯỪỨỰỬỮỲÝỴỶỸĐ",
            "aaaaaaaaaaaaaaaaaeeeeeeeeeeeiiiiiooooooooooooooooouuuuuuuuuuuyyyyyd"
            "AAAAAAAAAAAAAAAAAEEEEEEEEEEEIIIIIOOOOOOOOOOOOOOOOOUUUUUUUUUUUYYYYYD"
        )
        return " ".join(text.strip().translate(table).split())

    def title_case(self, text):
        return " ".join(w[:1].upper() + w[1:].lower() for w in text.split() if w)

    def format_department(self, raw):
        s = self.clean_no_accent(raw).lower()
        if "gay me" in s:
            return "Khoa Gay Me Hoi Suc"
        if "ngoai than kinh" in s:
            return "Khoa Ngoai Than Kinh"
        if "chan thuong" in s or "chinh hinh" in s or "bong" in s:
            return "Khoa Chan Thuong Chinh Hinh - Bong"
        return self.title_case(self.clean_no_accent(raw))

    def format_title(self, raw):
        s = self.clean_no_accent(raw).lower().replace('.', '').strip()
        if s == "bs" or "bac si" in s or "bac sy" in s:
            return "Bac Sy Dieu Tri"
        if "truong" in s:
            return "Dieu Duong Truong"
        if s == "dd" or "dieu duong" in s:
            return "Dieu Duong"
        return self.title_case(self.clean_no_accent(raw))

    def load_people_data(self):
        file_path = os.path.join(os.path.dirname(__file__), 'NOIDUNGDIEN.TXT')
        if not os.path.exists(file_path):
            self.lbl_person.setText("Không tìm thấy NOIDUNGDIEN.TXT")
            return
            
        try:
            with open(file_path, 'r', encoding='utf-8') as f:
                lines = f.readlines()
                
            self.people = []
            for line in lines:
                parts = line.strip().split('-')
                if len(parts) >= 2:
                    raw_department = parts[1].strip()
                    raw_role = parts[2].strip() if len(parts) > 2 else ''
                    self.people.append({
                        'name': parts[0].strip(),
                        'department': self.format_department(raw_department),
                        'role': self.format_title(raw_role),
                        'raw_department': raw_department,
                        'raw_role': raw_role
                    })
            self.update_person_display()
        except Exception as e:
            self.lbl_person.setText(f"Lỗi đọc file: {e}")

    def update_person_display(self):
        if self.people:
            p = self.people[self.current_person_index]
            self.lbl_person.setText(f"Người {self.current_person_index + 1}/{len(self.people)}: {p['name']} | {p['department']} | {p['role']}")
        else:
            self.lbl_person.setText("Danh sách rỗng!")

    def next_person(self):
        if self.people:
            self.current_person_index = (self.current_person_index + 1) % len(self.people)
            self.update_person_display()

    def prev_person(self):
        if self.people:
            self.current_person_index = (self.current_person_index - 1) % len(self.people)
            self.update_person_display()

    def copy_person_field(self, field, label):
        if self.people:
            val = self.people[self.current_person_index].get(field, '')
            self.copy_to_clipboard(val, label)

    def copy_to_clipboard(self, text, label=""):
        if text:
            QApplication.clipboard().setText(text)
            self.statusBar().showMessage(f"Đã copy {label}: {text}", 3000)

    def fetch_service_id(self, callback):
        url = f"https://api.viotp.com/service/getv2?token={self.viotp_token}&country=vn"
        self.statusBar().showMessage("Đang tìm dịch vụ Abbott trên ViOTP...")
        self.worker = ApiWorker(url)
        self.worker.result.connect(lambda data: self.handle_service_id(data, callback))
        self.worker.error.connect(lambda err: self.statusBar().showMessage(f"Lỗi kết nối: {err}"))
        self.worker.start()

    def handle_service_id(self, data, callback):
        if data.get('status_code') == 200:
            services = data.get('data', [])
            for s in services:
                if 'abbott' in str(s.get('name', '')).lower():
                    self.abbott_service_id = s.get('id')
                    self.statusBar().showMessage(f"Đã tìm thấy dịch vụ Abbott (ID: {self.abbott_service_id})")
                    callback()
                    return
            QMessageBox.warning(self, "Lỗi", "Không tìm thấy dịch vụ Abbott trên ViOTP.")
        else:
            QMessageBox.warning(self, "Lỗi API", data.get('message', 'Unknown Error'))

    def get_phone_number(self):
        if not self.abbott_service_id:
            self.fetch_service_id(self.get_phone_number)
            return

        self.phone_input.setText("Đang lấy số...")
        self.otp_input.clear()
        self.current_request_id = None
        
        url = f"https://api.viotp.com/request/getv2?token={self.viotp_token}&serviceId={self.abbott_service_id}"
        self.worker = ApiWorker(url)
        self.worker.result.connect(self.handle_get_phone)
        self.worker.error.connect(lambda err: self.phone_input.setText("Lỗi mạng"))
        self.worker.start()

    def handle_get_phone(self, data):
        if data.get('status_code') == 200:
            phone = str(data['data']['phone_number'])
            if not phone.startswith('0'):
                phone = '0' + phone
            self.current_request_id = str(data['data']['request_id'])
            self.phone_input.setText(phone)
            self.copy_to_clipboard(phone, "Số điện thoại")
            self.statusBar().showMessage(f"Đã lấy số ĐT: {phone} (RequestID: {self.current_request_id})", 5000)
        else:
            msg = data.get('message', 'Unknown Error')
            self.phone_input.setText(f"Lỗi: {msg}")
            QMessageBox.warning(self, "Lỗi API", msg)

    def get_otp(self):
        if not self.current_request_id:
            QMessageBox.warning(self, "Thiếu dữ liệu", "Vui lòng lấy số điện thoại trước.")
            return

        self.otp_input.setText("Đang chờ OTP...")
        url = f"https://api.viotp.com/session/getv2?requestId={self.current_request_id}&token={self.viotp_token}"
        self.worker = ApiWorker(url)
        self.worker.result.connect(self.handle_get_otp)
        self.worker.error.connect(lambda err: self.otp_input.setText("Lỗi mạng"))
        self.worker.start()

    def handle_get_otp(self, data):
        if data.get('status_code') == 200:
            status = data['data']['Status']
            if status == 1:
                otp = str(data['data']['Code'])
                self.otp_input.setText(otp)
                self.copy_to_clipboard(otp, "OTP")
                self.statusBar().showMessage("Đã nhận OTP!", 5000)
            elif status == 0:
                self.otp_input.setText("Vẫn đang chờ... Bấm Lấy OTP lại")
                self.statusBar().showMessage("Đang chờ OTP... Thử bấm lại sau vài giây", 3000)
            else:
                self.otp_input.setText("Phiên hết hạn hoặc lỗi")
        else:
            msg = data.get('message', 'Unknown Error')
            self.otp_input.setText(f"Lỗi: {msg}")

if __name__ == "__main__":
    app = QApplication(sys.argv)
    window = AbbottHelperApp()
    window.show()
    sys.exit(app.exec_())
