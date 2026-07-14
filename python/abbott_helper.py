import sys
import os
import json
import urllib.request
import urllib.parse
from PyQt5.QtWidgets import (QApplication, QMainWindow, QWidget, QVBoxLayout, QHBoxLayout,
                             QLineEdit, QPushButton, QLabel, QTextEdit, QMessageBox, QFrame,
                             QSplitter, QListWidget, QListWidgetItem, QDialog, QCheckBox,
                             QScrollArea, QSizePolicy, QStatusBar, QFileDialog)
from PyQt5.QtWebEngineWidgets import QWebEngineView, QWebEngineProfile, QWebEngineScript, QWebEnginePage, QWebEngineSettings
from PyQt5.QtCore import QUrl, Qt, QThread, pyqtSignal
from PyQt5.QtGui import QFont, QColor, QPalette

# State & Configuration Persistence
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
STATE_FILE = os.path.join(BASE_DIR, "helper_state.json")
PEOPLE_FILE = os.path.join(BASE_DIR, "NOIDUNGDIEN.TXT")
DEFAULT_HOSPITAL = "BENH VIEN DA KHOA TINH QUANG NGAI"
DEFAULT_ROLE = "Nguoi tham du"

# Accent cleaner mapping
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

def clean_no_accent(text):
    out = text.strip()
    for k, v in VIETNAMESE_ACCENTS.items():
        out = out.replace(k, v)
    return " ".join(out.split())

def title_case(text):
    return " ".join(w[:1].upper() + w[1:].lower() for w in text.split() if w)

def format_department(raw):
    s = clean_no_accent(raw).lower()
    if "gay me" in s:
        return "Khoa Gay Me Hoi Suc"
    if "ngoai than kinh" in s:
        return "Khoa Ngoai Than Kinh"
    if "ngoai tieu hoa" in s:
        return "Khoa Ngoai Tieu Hoa"
    if "noi tong hop" in s:
        return "Khoa Noi Tong Hop"
    if "ngoai tong hop" in s:
        return "Khoa Ngoai Tong Hop"
    
    # Generic prepending rule for other departments
    res = title_case(clean_no_accent(raw))
    if not res.lower().startswith("khoa ") and not res.lower().startswith("phong "):
        return "Khoa " + res
    return res

def format_title(raw):
    s = clean_no_accent(raw).lower().replace(".", "").strip()
    if s == "bs" or "bac si" in s or "bac sy" in s:
        return "Bac Sy Dieu Tri"
    if "truong" in s:
        return "Y Ta Truong/ Dieu Duong Truong"
    if s == "dd" or "dieu duong" in s:
        return "Y ta/ Dieu duong"
    return title_case(clean_no_accent(raw))

class ApiWorker(QThread):
    result = pyqtSignal(dict)
    error = pyqtSignal(str)

    def __init__(self, url):
        super().__init__()
        self.url = url

    def run(self):
        try:
            req = urllib.request.Request(self.url, headers={'User-Agent': 'Mozilla/5.0'})
            with urllib.request.urlopen(req, timeout=12) as response:
                data = json.loads(response.read().decode('utf-8'))
                self.result.emit(data)
        except Exception as e:
            self.error.emit(str(e))

class PeopleEditorDialog(QDialog):
    def __init__(self, parent=None, current_text=""):
        super().__init__(parent)
        self.setWindowTitle("Chỉnh sửa danh sách người tham dự")
        self.resize(750, 500)
        self.init_ui(current_text)

    def init_ui(self, current_text):
        layout = QVBoxLayout(self)
        
        info_label = QLabel("Nhập danh sách theo định dạng: Họ Tên - Phòng Ban - Chức Danh (Ví dụ: Nguyễn Văn A - nội tổng hợp - bs)")
        info_label.setStyleSheet("color: #94a3b8; font-size: 12px; margin-bottom: 5px;")
        layout.addWidget(info_label)

        self.editor = QTextEdit()
        self.editor.setPlainText(current_text)
        self.editor.setFont(QFont("Consolas", 11))
        self.editor.setPlaceholderText("Dán danh sách vào đây...")
        layout.addWidget(self.editor)

        # Buttons
        btn_layout = QHBoxLayout()
        btn_save = QPushButton("Lưu & Tải lại")
        btn_save.setObjectName("saveButton")
        btn_save.clicked.connect(self.accept)
        
        btn_cancel = QPushButton("Đóng")
        btn_cancel.clicked.connect(self.reject)
        
        btn_layout.addStretch()
        btn_layout.addWidget(btn_cancel)
        btn_layout.addWidget(btn_save)
        layout.addLayout(btn_layout)

    def get_text(self):
        return self.editor.toPlainText()

class AbbottHelperApp(QMainWindow):
    def __init__(self):
        super().__init__()
        self.setWindowTitle("Abbott Autofill Assistant - PyQt5")
        self.setGeometry(100, 100, 1280, 850)

        # Config state
        self.viotp_token = "de6faac93d8d4f3294070fe48a11224b"
        self.abbott_service_id = None
        self.current_request_id = None
        self.current_phone = ""
        self.current_otp = ""
        
        self.people = []
        self.current_person_index = 0
        
        # Load stylesheet
        self.apply_premium_theme()
        
        # Setup UI
        self.init_ui()
        
        # Load data & states
        self.load_state()
        self.load_people_data()

    def apply_premium_theme(self):
        qss = """
        QMainWindow {
            background-color: #07111F;
        }
        
        QWidget {
            color: #E2E8F0;
            font-family: 'Segoe UI', Arial, sans-serif;
            font-size: 13px;
        }
        
        QFrame {
            border: none;
        }
        
        #SidebarFrame {
            background-color: #0f172a;
            border-right: 1px solid #1e293b;
        }
        
        QGroupBox {
            font-weight: bold;
            font-size: 14px;
            color: #5EEAD4;
            border: 1px solid #334155;
            border-radius: 12px;
            margin-top: 15px;
            padding: 10px;
            background-color: #1e293b;
        }
        
        QListWidget {
            background-color: #0b0f19;
            border: 1px solid #1e293b;
            border-radius: 8px;
            color: #cbd5e1;
            padding: 5px;
        }
        
        QListWidget::item {
            padding: 8px 10px;
            border-bottom: 1px solid #1e293b;
            border-radius: 4px;
        }
        
        QListWidget::item:hover {
            background-color: #1e293b;
            color: #ffffff;
        }
        
        QListWidget::item:selected {
            background-color: #1e293b;
            color: #5EEAD4;
            font-weight: bold;
            border-left: 3px solid #5EEAD4;
        }
        
        QLineEdit {
            background-color: #0f172a;
            border: 1px solid #334155;
            border-radius: 6px;
            padding: 6px 10px;
            color: #f8fafc;
        }
        
        QLineEdit:focus {
            border: 1.5px solid #5EEAD4;
            background-color: #0b0f19;
        }
        
        QPushButton {
            background-color: #334155;
            border: none;
            border-radius: 6px;
            color: #f8fafc;
            padding: 6px 12px;
            font-weight: 600;
        }
        
        QPushButton:hover {
            background-color: #475569;
        }
        
        QPushButton:pressed {
            background-color: #1e293b;
        }
        
        #actionButtonPrimary {
            background-color: #0ea5e9;
            color: white;
            font-size: 14px;
            padding: 10px;
            border-radius: 8px;
        }
        
        #actionButtonPrimary:hover {
            background-color: #0284c7;
        }
        
        #actionButtonGreen {
            background-color: #10b981;
            color: white;
            font-weight: bold;
        }
        
        #actionButtonGreen:hover {
            background-color: #059669;
        }
        
        #actionButtonPurple {
            background-color: #8b5cf6;
            color: white;
        }
        
        #actionButtonPurple:hover {
            background-color: #7c3aed;
        }
        
        #fillWebButton {
            background-color: #2563eb;
            color: white;
            font-weight: bold;
            font-size: 15px;
            padding: 12px;
            border-radius: 8px;
        }
        
        #fillWebButton:hover {
            background-color: #1d4ed8;
        }
        
        #saveButton {
            background-color: #10b981;
            color: white;
            font-weight: bold;
        }
        
        QLabel#lblTitle {
            font-weight: bold;
            font-size: 15px;
            color: #5EEAD4;
            margin-bottom: 2px;
        }
        
        QLabel#lblNormal {
            color: #94a3b8;
            font-size: 12px;
        }
        
        QScrollBar:vertical {
            border: none;
            background: #0f172a;
            width: 10px;
            margin: 0px;
        }
        
        QScrollBar::handle:vertical {
            background: #334155;
            min-height: 20px;
            border-radius: 5px;
        }
        
        QScrollBar::handle:vertical:hover {
            background: #475569;
        }
        
        QScrollBar::add-line:vertical, QScrollBar::sub-line:vertical {
            border: none;
            background: none;
        }
        """
        self.setStyleSheet(qss)

    def init_ui(self):
        central_widget = QWidget()
        self.setCentralWidget(central_widget)
        main_layout = QVBoxLayout(central_widget)
        main_layout.setContentsMargins(0, 0, 0, 0)
        main_layout.setSpacing(0)

        # URL and Toolbar Layout
        top_bar = QFrame()
        top_bar.setStyleSheet("background-color: #0f172a; border-bottom: 1px solid #1e293b; padding: 6px;")
        top_layout = QHBoxLayout(top_bar)
        top_layout.setContentsMargins(10, 2, 10, 2)
        top_layout.setSpacing(8)

        logo_label = QLabel("ABBOTT AUTOFILL")
        logo_label.setStyleSheet("font-weight: 800; font-size: 15px; color: #5EEAD4; letter-spacing: 0.5px;")
        top_layout.addWidget(logo_label)

        self.url_input = QLineEdit()
        self.url_input.setPlaceholderText("Dán URL trang đăng ký Abbott vào đây...")
        self.url_input.returnPressed.connect(self.load_url)
        top_layout.addWidget(self.url_input, stretch=1)

        btn_load = QPushButton("Mở Web")
        btn_load.clicked.connect(self.load_url)
        btn_load.setFixedWidth(80)
        top_layout.addWidget(btn_load)

        main_layout.addWidget(top_bar)

        # Splitter Layout (Left pane controls, Right pane web view)
        splitter = QSplitter(Qt.Horizontal)
        
        # Left Panel (Control Panel)
        left_panel = QFrame()
        left_panel.setObjectName("SidebarFrame")
        left_panel.setFixedWidth(460)
        left_layout = QVBoxLayout(left_panel)
        left_layout.setContentsMargins(12, 12, 12, 12)
        left_layout.setSpacing(14)

        # VIOTP Rent section
        viotp_frame = QFrame()
        viotp_frame.setStyleSheet("background-color: #1e293b; border-radius: 10px; border: 1px solid #334155; padding: 8px;")
        viotp_layout = QVBoxLayout(viotp_frame)
        viotp_layout.setSpacing(6)
        
        lbl_viotp_sec = QLabel("1. DỊCH VỤ VIOTP (THUÊ SIM)")
        lbl_viotp_sec.setStyleSheet("font-weight: bold; color: #5EEAD4; font-size: 13px;")
        viotp_layout.addWidget(lbl_viotp_sec)

        token_layout = QHBoxLayout()
        token_lbl = QLabel("Token:")
        token_lbl.setFixedWidth(45)
        self.token_input = QLineEdit(self.viotp_token)
        self.token_input.setPlaceholderText("Nhập ViOTP Token...")
        self.token_input.textChanged.connect(self.update_token)
        token_layout.addWidget(token_lbl)
        token_layout.addWidget(self.token_input)
        viotp_layout.addLayout(token_layout)

        phone_row = QHBoxLayout()
        btn_get_phone = QPushButton("Thuê Số ĐT")
        btn_get_phone.setObjectName("actionButtonGreen")
        btn_get_phone.setFixedWidth(110)
        btn_get_phone.clicked.connect(self.get_phone_number)
        
        self.phone_input = QLineEdit()
        self.phone_input.setReadOnly(True)
        self.phone_input.setPlaceholderText("Số điện thoại...")
        self.phone_input.setAlignment(Qt.AlignCenter)
        
        btn_copy_phone = QPushButton("Copy SĐT")
        btn_copy_phone.clicked.connect(lambda: self.copy_to_clipboard(self.phone_input.text(), "Số điện thoại"))
        btn_copy_phone.setFixedWidth(80)
        
        phone_row.addWidget(btn_get_phone)
        phone_row.addWidget(self.phone_input)
        phone_row.addWidget(btn_copy_phone)
        viotp_layout.addLayout(phone_row)

        otp_row = QHBoxLayout()
        self.btn_get_otp = QPushButton("Lấy OTP 60s")
        self.btn_get_otp.setObjectName("actionButtonPurple")
        self.btn_get_otp.setFixedWidth(110)
        self.btn_get_otp.clicked.connect(self.get_otp)
        
        self.otp_input = QLineEdit()
        self.otp_input.setReadOnly(True)
        self.otp_input.setPlaceholderText("Mã OTP...")
        self.otp_input.setAlignment(Qt.AlignCenter)
        
        btn_copy_otp = QPushButton("Copy OTP")
        btn_copy_otp.clicked.connect(lambda: self.copy_to_clipboard(self.otp_input.text(), "Mã OTP"))
        btn_copy_otp.setFixedWidth(80)
        
        otp_row.addWidget(self.btn_get_otp)
        otp_row.addWidget(self.otp_input)
        otp_row.addWidget(btn_copy_otp)
        viotp_layout.addLayout(otp_row)
        
        left_layout.addWidget(viotp_frame)

        # Participant list section
        list_frame = QFrame()
        list_frame.setStyleSheet("background-color: #1e293b; border-radius: 10px; border: 1px solid #334155; padding: 8px;")
        list_layout = QVBoxLayout(list_frame)
        list_layout.setSpacing(6)

        lbl_list_sec = QLabel("2. DANH SÁCH NGƯỜI THAM GIA")
        lbl_list_sec.setStyleSheet("font-weight: bold; color: #5EEAD4; font-size: 13px;")
        list_layout.addWidget(lbl_list_sec)

        self.list_widget = QListWidget()
        self.list_widget.setFixedHeight(130)
        self.list_widget.currentRowChanged.connect(self.on_person_selected)
        list_layout.addWidget(self.list_widget)

        # Converted Field Values layout
        fields_scroll = QScrollArea()
        fields_scroll.setWidgetResizable(True)
        fields_scroll.setStyleSheet("background-color: transparent; border: none;")
        
        fields_widget = QWidget()
        fields_widget.setStyleSheet("background-color: transparent;")
        fields_layout = QVBoxLayout(fields_widget)
        fields_layout.setContentsMargins(0, 0, 0, 0)
        fields_layout.setSpacing(8)

        # Create name field
        self.name_edit = self.create_field_row(fields_layout, "Họ và Tên:", "name")
        self.dept_edit = self.create_field_row(fields_layout, "Phòng Ban (Khoa):", "department")
        self.role_edit = self.create_field_row(fields_layout, "Chức Danh:", "role")
        self.vaitro_edit = self.create_field_row(fields_layout, "Vai trò:", "attendeeRole", DEFAULT_ROLE)
        self.hosp_edit = self.create_field_row(fields_layout, "Bệnh Viện:", "hospital", DEFAULT_HOSPITAL)
        
        fields_scroll.setWidget(fields_widget)
        list_layout.addWidget(fields_scroll)

        # Navigation row
        nav_row = QHBoxLayout()
        btn_prev = QPushButton("<< Trước")
        btn_prev.clicked.connect(self.prev_person)
        
        self.lbl_page = QLabel("0 / 0")
        self.lbl_page.setAlignment(Qt.AlignCenter)
        self.lbl_page.setStyleSheet("font-weight: bold; color: #94a3b8;")
        
        btn_next = QPushButton("Sau >>")
        btn_next.clicked.connect(self.next_person)

        nav_row.addWidget(btn_prev)
        nav_row.addWidget(self.lbl_page, stretch=1)
        nav_row.addWidget(btn_next)
        list_layout.addLayout(nav_row)

        left_layout.addWidget(list_frame)

        # Action panel (Fill Web)
        action_frame = QFrame()
        action_frame.setStyleSheet("background-color: #1e293b; border-radius: 10px; border: 1px solid #334155; padding: 8px;")
        action_layout = QVBoxLayout(action_frame)
        action_layout.setSpacing(6)

        # Auto fill options
        self.chk_auto_fill = QCheckBox("Tự động điền thông tin khi chuyển người")
        self.chk_auto_fill.setChecked(True)
        action_layout.addWidget(self.chk_auto_fill)

        btn_fill_all = QPushButton("ĐIỀN VÀO TRANG WEB")
        btn_fill_all.setObjectName("fillWebButton")
        btn_fill_all.clicked.connect(self.fill_current_to_web)
        action_layout.addWidget(btn_fill_all)

        # Edit/Reload/Export row
        edit_row = QHBoxLayout()
        btn_edit_list = QPushButton("Nhập/Sửa danh sách")
        btn_edit_list.clicked.connect(self.open_list_editor)
        
        btn_reload = QPushButton("Tải lại từ TXT")
        btn_reload.clicked.connect(self.load_people_data)
        
        btn_export = QPushButton("Xuất TXT")
        btn_export.clicked.connect(self.export_converted_list)
        btn_export.setObjectName("actionButtonGreen")
        
        edit_row.addWidget(btn_edit_list)
        edit_row.addWidget(btn_reload)
        edit_row.addWidget(btn_export)
        action_layout.addLayout(edit_row)

        left_layout.addWidget(action_frame)
        
        splitter.addWidget(left_panel)

        # Right Panel (WebEngineView)
        right_panel = QFrame()
        right_layout = QVBoxLayout(right_panel)
        right_layout.setContentsMargins(0, 0, 0, 0)
        right_layout.setSpacing(0)

        self.webview = QWebEngineView()
        
        # Profile settings for Android emulator spoofing
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
        profile.scripts().insert(script)
        
        # Auto-grant location permissions
        self.webview.page().featurePermissionRequested.connect(self.grant_permissions)

        right_layout.addWidget(self.webview)
        splitter.addWidget(right_panel)

        # Set default splitter sizes (35% left, 65% right)
        splitter.setSizes([460, 820])
        main_layout.addWidget(splitter)

        # Status Bar
        self.setStatusBar(QStatusBar(self))
        self.statusBar().setStyleSheet("background-color: #0f172a; color: #94a3b8; border-top: 1px solid #1e293b;")

    def create_field_row(self, layout, label_text, field_name, default_val=""):
        row = QHBoxLayout()
        row.setSpacing(6)
        
        lbl = QLabel(label_text)
        lbl.setFixedWidth(130)
        lbl.setStyleSheet("font-weight: 500; color: #94a3b8;")
        row.addWidget(lbl)
        
        edit = QLineEdit(default_val)
        edit.setObjectName(f"edit_{field_name}")
        row.addWidget(edit)
        
        btn_copy = QPushButton("Copy")
        btn_copy.setFixedWidth(50)
        btn_copy.clicked.connect(lambda: self.copy_to_clipboard(edit.text(), label_text.replace(":", "")))
        row.addWidget(btn_copy)
        
        layout.addLayout(row)
        return edit

    def update_token(self, text):
        self.viotp_token = text.strip()
        self.save_state()

    def grant_permissions(self, url, feature):
        if feature == QWebEnginePage.Geolocation:
            self.webview.page().setFeaturePermission(url, feature, QWebEnginePage.PermissionGrantedByUser)

    def load_url(self):
        url = self.url_input.text().strip()
        if url:
            if not url.startswith('http'):
                url = 'https://' + url
            qurl = QUrl.fromUserInput(url)
            self.statusBar().showMessage(f"Đang mở URL: {qurl.toString()} ...")
            self.webview.setHtml("<html><body style='font-family:sans-serif;text-align:center;padding-top:100px;background:#07111F;color:#E2E8F0'><h2>Đang mở trang...</h2><p>Vui lòng chờ vài giây để tải nội dung</p></body></html>")
            self.webview.load(qurl)
            self.save_state()

    def on_load_finished(self, ok):
        if ok:
            self.statusBar().showMessage(f"Đã tải thành công: {self.webview.url().toString()}", 5000)
            if self.chk_auto_fill.isChecked() and self.people:
                self.fill_current_to_web()
        else:
            self.statusBar().showMessage("Không thể load trang. Hãy thử kiểm tra lại URL.", 5000)

    def load_people_data(self):
        if not os.path.exists(PEOPLE_FILE):
            # Create a sample file if it does not exist
            sample_content = (
                "Phạm Thị Thu Vân - gây mê hồi sức - bs\n"
                "Huỳnh Thị Việt Trinh - ngoại thần kinh - điều dưỡng\n"
                "Nguyễn Thị Kim Thuỳ - ngoại thần kinh - điều dưỡng trưởng\n"
                "Nguyễn Thị Vân Kiều - ngoại tiêu hoá - điều dưỡng\n"
                "Đoàn Thị Bích Hải - nội tổng hợp - điều dưỡng\n"
                "Trần Thị Thu Thuỳ - nội tổng hợp - điều dưỡng\n"
                "Võ Thị Diệu Thanh - nội tổng hợp - bs\n"
                "Võ Hoàng Xuân Vinh - ngoại tổng hợp - điều dưỡng trưởng\n"
                "Phạm Thị Tố Loan - nội tổng hợp - bs\n"
            )
            try:
                with open(PEOPLE_FILE, 'w', encoding='utf-8') as f:
                    f.write(sample_content)
            except Exception as e:
                self.statusBar().showMessage(f"Không thể tạo NOIDUNGDIEN.TXT: {e}")

        try:
            with open(PEOPLE_FILE, 'r', encoding='utf-8') as f:
                lines = f.readlines()
            
            self.people = []
            self.list_widget.clear()
            
            for line in lines:
                line_str = line.strip().rstrip(',')
                if not line_str or " là " in line_str.lower():
                    continue
                parts = [p.strip() for p in line_str.split('-')]
                if len(parts) >= 2:
                    raw_department = parts[1]
                    raw_role = parts[2] if len(parts) > 2 else ''
                    
                    person = {
                        'name': parts[0],
                        'department': format_department(raw_department),
                        'role': format_title(raw_role),
                        'raw_department': raw_department,
                        'raw_role': raw_role
                    }
                    self.people.append(person)
                    
                    # Display item in ListWidget
                    display_text = f"{person['name']} | {person['department']} | {person['role']}"
                    item = QListWidgetItem(display_text)
                    self.list_widget.addItem(item)
            
            if self.people:
                if self.current_person_index >= len(self.people):
                    self.current_person_index = 0
                self.list_widget.setCurrentRow(self.current_person_index)
                self.update_person_display()
            else:
                self.lbl_page.setText("0 / 0")
                self.statusBar().showMessage("Danh sách người tham gia rỗng!", 4000)
        except Exception as e:
            QMessageBox.critical(self, "Lỗi đọc dữ liệu", f"Không thể tải file NOIDUNGDIEN.TXT:\n{e}")

    def update_person_display(self):
        if not self.people or self.current_person_index >= len(self.people):
            return
            
        p = self.people[self.current_person_index]
        self.name_edit.setText(p['name'])
        self.dept_edit.setText(p['department'])
        self.role_edit.setText(p['role'])
        self.vaitro_edit.setText(DEFAULT_ROLE)
        self.hosp_edit.setText(DEFAULT_HOSPITAL)
        
        self.lbl_page.setText(f"{self.current_person_index + 1} / {len(self.people)}")
        self.save_state()
        
        # If auto fill is checked, run autofill inside web
        if self.chk_auto_fill.isChecked():
            self.fill_current_to_web()

    def on_person_selected(self, index):
        if index >= 0 and index < len(self.people):
            self.current_person_index = index
            self.update_person_display()

    def next_person(self):
        if self.people:
            self.current_person_index = (self.current_person_index + 1) % len(self.people)
            self.list_widget.setCurrentRow(self.current_person_index)

    def prev_person(self):
        if self.people:
            self.current_person_index = (self.current_person_index - 1) % len(self.people)
            self.list_widget.setCurrentRow(self.current_person_index)

    def open_list_editor(self):
        current_text = ""
        if os.path.exists(PEOPLE_FILE):
            try:
                with open(PEOPLE_FILE, 'r', encoding='utf-8') as f:
                    current_text = f.read()
            except Exception as e:
                self.statusBar().showMessage(f"Lỗi đọc file: {e}")
                
        dialog = PeopleEditorDialog(self, current_text)
        if dialog.exec_() == QDialog.Accepted:
            new_text = dialog.get_text()
            try:
                with open(PEOPLE_FILE, 'w', encoding='utf-8') as f:
                    f.write(new_text)
                self.load_people_data()
                self.statusBar().showMessage("Đã lưu danh sách người tham gia mới thành công!", 4000)
            except Exception as e:
                QMessageBox.critical(self, "Lỗi Lưu File", f"Không thể lưu file NOIDUNGDIEN.TXT:\n{e}")

    def copy_to_clipboard(self, text, label):
        if text:
            QApplication.clipboard().setText(text)
            self.statusBar().showMessage(f"Đã copy {label}: {text}", 3000)

    def export_converted_list(self):
        if not self.people:
            QMessageBox.warning(self, "Danh sách rỗng", "Không có dữ liệu để xuất.")
            return
            
        default_name = os.path.join(os.path.dirname(PEOPLE_FILE), "NOIDUNGDIEN_CHUANHOA.TXT")
        file_path, _ = QFileDialog.getSaveFileName(
            self, "Lưu danh sách đã chuẩn hóa", default_name, "Text Files (*.txt);;All Files (*)"
        )
        
        if file_path:
            try:
                lines = []
                for p in self.people:
                    lines.append(f"{p['name']} - {p['department']} - {p['role']}")
                
                with open(file_path, 'w', encoding='utf-8') as f:
                    f.write("\n".join(lines) + "\n")
                
                self.statusBar().showMessage(f"Đã xuất danh sách chuẩn hóa ra: {os.path.basename(file_path)}", 5000)
                QMessageBox.information(
                    self, "Xuất thành công", f"Đã xuất {len(self.people)} người thành công ra file:\n{file_path}"
                )
            except Exception as e:
                QMessageBox.critical(self, "Lỗi Xuất File", f"Không thể lưu file:\n{e}")

    # Dynamic JS Autofill
    def fill_current_to_web(self):
        if not self.people or self.current_person_index >= len(self.people):
            return

        data = {
            'phone': self.current_phone,
            'otp': self.current_otp,
            'name': self.name_edit.text(),
            'hospital': self.hosp_edit.text(),
            'department': self.dept_edit.text(),
            'role': self.role_edit.text(),
            'attendeeRole': self.vaitro_edit.text()
        }

        payload = json.dumps(data, ensure_ascii=False)
        
        # Complete Element UI mapping injection
        js_code = f"""
        (function() {{
            const data = {payload};
            const norm = (s) => (s || '').toString().toLowerCase()
              .normalize('NFD').replace(/[\\u0300-\\u036f]/g, '')
              .replace(/đ/g, 'd').replace(/\\s+/g, ' ').trim();
            const inputs = Array.from(document.querySelectorAll('input, textarea'));
            
            function labelOf(el) {{
                let txt = '';
                if (el.id) {{
                    const label = document.querySelector('label[for="' + el.id + '"]');
                    if (label) txt += ' ' + label.innerText;
                }}
                let p = el;
                for (let i = 0; i < 4 && p; i++, p = p.parentElement) {{
                    txt += ' ' + (p.innerText || '');
                }}
                txt += ' ' + (el.placeholder || '') + ' ' + (el.name || '') + ' ' + (el.id || '');
                return norm(txt);
            }}
            
            function setVal(el, val) {{
                if (!el || val == null || val === '') return false;
                el.focus();
                el.value = val;
                el.dispatchEvent(new Event('input', {{bubbles: true}}));
                el.dispatchEvent(new Event('change', {{bubbles: true}}));
                return true;
            }}
            
            function fillBy(keys, val) {{
                const el = inputs.find(i => keys.some(k => labelOf(i).includes(k)));
                return setVal(el, val);
            }}
            
            // Fill normal text/phone fields
            fillBy(['sdt', 'so dien thoai', 'dien thoai', 'phone'], data.phone);
            fillBy(['ma', 'otp', 'code', 'xac thuc'], data.otp);
            fillBy(['ho va ten', 'ho ten', 'name'], data.name);
            fillBy(['benh vien', 'hospital'], data.hospital);
            
            // Special Element UI dropdown option selector
            const selectWrappers = Array.from(document.querySelectorAll('.el-select'));
            selectWrappers.forEach(selectEl => {{
                let txt = norm(selectEl.innerText + ' ' + selectEl.innerHTML);
                let targetVal = '';
                
                if (txt.includes('vai tro')) {{
                    targetVal = data.attendeeRole;
                }} else if (txt.includes('phong ban') || txt.includes('khoa')) {{
                    targetVal = data.department;
                }} else if (txt.includes('chuc danh')) {{
                    targetVal = data.role;
                }}
                
                if (targetVal) {{
                    const clickTarget = selectEl.querySelector('input') || selectEl;
                    clickTarget.click();
                    setTimeout(() => {{
                        const options = Array.from(document.querySelectorAll('.el-select-dropdown__item'));
                        const bestOption = options.find(opt => {{
                            const optTxt = opt.innerText.trim();
                            return norm(optTxt) === norm(targetVal) || optTxt.includes(targetVal) || targetVal.includes(optTxt);
                        }});
                        if (bestOption) {{
                            bestOption.click();
                        }}
                    }}, 120);
                }}
            }});
        }})();
        """
        self.webview.page().runJavaScript(js_code)
        self.statusBar().showMessage("Đã chạy code điền tự động vào trang web!", 3000)

    # ViOTP Service Integration
    def fetch_service_id(self, callback):
        url = f"https://api.viotp.com/service/getv2?token={self.viotp_token}&country=vn"
        self.statusBar().showMessage("Đang tìm dịch vụ Abbott trên ViOTP...")
        self.worker = ApiWorker(url)
        self.worker.result.connect(lambda data: self.handle_service_id(data, callback))
        self.worker.error.connect(lambda err: self.statusBar().showMessage(f"Lỗi kết nối ViOTP: {err}"))
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
            QMessageBox.warning(self, "Lỗi ViOTP", "Không tìm thấy gói dịch vụ 'Abbott' trên tài khoản ViOTP này.")
        else:
            QMessageBox.warning(self, "Lỗi API ViOTP", data.get('message', 'Không thể lấy danh sách dịch vụ.'))

    def get_phone_number(self):
        if not self.viotp_token or len(self.viotp_token) < 10:
            QMessageBox.warning(self, "Thiếu Token", "Vui lòng cấu hình ViOTP Token chính xác trước khi lấy số.")
            return

        if not self.abbott_service_id:
            self.fetch_service_id(self.get_phone_number)
            return

        self.phone_input.setText("Đang lấy...")
        self.otp_input.clear()
        self.current_phone = ""
        self.current_otp = ""
        self.current_request_id = None
        
        url = f"https://api.viotp.com/request/getv2?token={self.viotp_token}&serviceId={self.abbott_service_id}"
        self.worker = ApiWorker(url)
        self.worker.result.connect(self.handle_get_phone)
        self.worker.error.connect(lambda err: self.phone_input.setText("Lỗi mạng!"))
        self.worker.start()

    def handle_get_phone(self, data):
        if data.get('status_code') == 200:
            phone = str(data['data']['phone_number'])
            if not phone.startswith('0'):
                phone = '0' + phone
            self.current_phone = phone
            self.current_request_id = str(data['data']['request_id'])
            
            self.phone_input.setText(phone)
            self.copy_to_clipboard(phone, "Số điện thoại")
            self.statusBar().showMessage(f"Thuê SĐT thành công: {phone} (RequestID: {self.current_request_id})")
            
            # Auto fill phone directly
            if self.chk_auto_fill.isChecked():
                self.fill_current_to_web()
        else:
            msg = data.get('message', 'Lỗi không xác định')
            self.phone_input.setText("Lỗi!")
            QMessageBox.warning(self, "Lỗi Thuê Số", f"API trả về lỗi:\n{msg}")

    def get_otp(self):
        if not self.current_request_id:
            QMessageBox.warning(self, "Thiếu request_id", "Vui lòng thực hiện 'Thuê Số ĐT' thành công trước.")
            return

        self.btn_get_otp.setEnabled(False)
        self.btn_get_otp.setText("Đang chờ...")
        self.otp_input.setText("Chờ OTP...")
        
        # We start a background thread or a loop that polls ViOTP session status
        # Since it is async, let's create a dedicated polling thread class to avoid freezing GUI
        class OtpPoller(QThread):
            otp_found = pyqtSignal(str)
            otp_failed = pyqtSignal(str)
            progress = pyqtSignal(int)

            def __init__(self, token, request_id):
                super().__init__()
                self.token = token
                self.request_id = request_id

            def run(self):
                import time
                for sec in range(60):
                    self.progress.emit(60 - sec)
                    try:
                        url = f"https://api.viotp.com/session/getv2?requestId={self.request_id}&token={self.token}"
                        req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
                        with urllib.request.urlopen(req, timeout=8) as r:
                            res = json.loads(r.read().decode('utf-8'))
                            if res.get('status_code') == 200:
                                status = res['data']['Status']
                                if status == 1:
                                    self.otp_found.emit(str(res['data']['Code']))
                                    return
                                elif status != 0:
                                    self.otp_failed.emit("Phiên thuê số đã bị hủy hoặc hết hạn.")
                                    return
                    except Exception as e:
                        pass
                    time.sleep(1)
                self.otp_failed.emit("Không nhận được OTP sau 60 giây.")

        self.poller = OtpPoller(self.viotp_token, self.current_request_id)
        self.poller.progress.connect(lambda sec: self.otp_input.setText(f"Chờ {sec}s..."))
        self.poller.otp_found.connect(self.on_otp_success)
        self.poller.otp_failed.connect(self.on_otp_failure)
        self.poller.start()

    def on_otp_success(self, otp_code):
        self.current_otp = otp_code
        self.otp_input.setText(otp_code)
        self.btn_get_otp.setEnabled(True)
        self.btn_get_otp.setText("Lấy OTP 60s")
        self.copy_to_clipboard(otp_code, "Mã OTP")
        self.statusBar().showMessage(f"Nhận được OTP: {otp_code}!", 5000)
        
        # Auto-fill OTP directly
        if self.chk_auto_fill.isChecked():
            self.fill_current_to_web()

    def on_otp_failure(self, error_msg):
        self.otp_input.setText("Không có OTP")
        self.btn_get_otp.setEnabled(True)
        self.btn_get_otp.setText("Lấy OTP 60s")
        QMessageBox.information(self, "Hết thời gian OTP", error_msg)

    # Persistent UI State
    def save_state(self):
        state = {
            'url': self.url_input.text().strip(),
            'viotp_token': self.viotp_token,
            'current_person_index': self.current_person_index,
            'auto_fill': self.chk_auto_fill.isChecked()
        }
        try:
            with open(STATE_FILE, 'w', encoding='utf-8') as f:
                json.dump(state, f, indent=4)
        except Exception as e:
            pass

    def load_state(self):
        if os.path.exists(STATE_FILE):
            try:
                with open(STATE_FILE, 'r', encoding='utf-8') as f:
                    state = json.load(f)
                
                self.viotp_token = state.get('viotp_token', self.viotp_token)
                self.token_input.setText(self.viotp_token)
                
                url = state.get('url', '')
                if url:
                    self.url_input.setText(url)
                    # Don't auto load url directly on startup if it causes issues, but let's load it
                    qurl = QUrl.fromUserInput(url)
                    self.webview.load(qurl)
                
                self.current_person_index = state.get('current_person_index', 0)
                self.chk_auto_fill.setChecked(state.get('auto_fill', True))
            except Exception as e:
                pass

if __name__ == "__main__":
    app = QApplication(sys.argv)
    window = AbbottHelperApp()
    window.show()
    sys.exit(app.exec_())
