import os
import sys
import time
import json
import html
import re
import threading
import secrets
import copy
from datetime import datetime
from typing import Optional, Dict, Any, List
import requests

from config import (
    load_config,
    save_config,
    parse_people_lines,
    normalize_people_lines,
    SCREENSHOTS_DIR,
    DATA_DIR,
    DEFAULT_HOSPITALS,
    STANDARD_DEPARTMENTS,
    STANDARD_ROLES,
)
from otp_service import OtpService
from qr_reader import read_qr_from_file, parse_abbott_event_url
from abbott_browser import AbbottAutomationRunner

# Đảm bảo UTF-8 trên Windows
if sys.platform.startswith("win"):
    try:
        sys.stdout.reconfigure(encoding="utf-8")
        sys.stderr.reconfigure(encoding="utf-8")
    except Exception:
        pass

cfg = load_config()
BOT_TOKEN = os.environ.get("BOT_TOKEN") or cfg.get("bot_token", "")
TELEGRAM_API_URL = f"https://api.telegram.org/bot{BOT_TOKEN}"

# Trạng thái người dùng đang nhập liệu
# chat_id -> "WAITING_VIOTP_TOKEN" | "WAITING_HUPSMS_KEY" | "WAITING_PEOPLE" | "WAITING_HOSPITAL"
user_states: Dict[int, str] = {}
# Per-chat snapshot invalidates buttons after any list change.
person_sessions = {}
active_runner: Optional[AbbottAutomationRunner] = None
queue_thread: Optional[threading.Thread] = None
is_queue_running = False
review_pending = None  # (chat_id, unique_id, threading.Event, decision)
review_lock = threading.Lock()

# ==============================================================================
# BÀN PHÍM CHÍNH (REPLY KEYBOARD)
# ==============================================================================
MAIN_KEYBOARD = {
    "keyboard": [
        [
            {"text": "🚀 Chạy Tự Động"},
            {"text": "🔗 Link Sự Kiện"},
        ],
        [
            {"text": "📋 DS Người Tham Gia"},
            {"text": "🏥 Chọn Bệnh Viện"},
        ],
        [
            {"text": "🔑 Nguồn OTP & Token"},
            {"text": "💰 Số Dư Tài Khoản"},
        ],
        [
            {"text": "📋 Chuẩn Hóa DS"},
            {"text": "📸 Chế Độ Gửi"},
        ],
        [
            {"text": "⚙️ Cài Đặt Chung"},
            {"text": "📖 Hướng Dẫn Sử Dụng"},
        ],
    ],
    "resize_keyboard": True,
    "input_field_placeholder": "Gửi link sự kiện, ảnh QR hoặc chọn menu...",
}

CANCEL_KEYBOARD = {
    "keyboard": [
        [{"text": "🔙 Quay lại Menu Chính"}]
    ],
    "resize_keyboard": True,
}

# Lệnh / hiển thị trong menu Telegram; không đưa token vào tên lệnh.
BOT_COMMANDS = [
    {"command": "start", "description": "Mở menu chính"},
    {"command": "help", "description": "Hướng dẫn và các lệnh nhanh"},
    {"command": "link", "description": "Xem link sự kiện hoặc gửi link mới"},
    {"command": "people", "description": "Xem danh sách người tham gia"},
    {"command": "normalize", "description": "Chuẩn hóa danh sách để dán lại"},
    {"command": "hospital", "description": "Chọn bệnh viện"},
    {"command": "otp", "description": "Chọn nguồn OTP và nhập token"},
    {"command": "balance", "description": "Kiểm tra số dư OTP"},
    {"command": "services", "description": "Dò server dịch vụ Abbott"},
    {"command": "mode", "description": "Chọn duyệt ảnh hoặc tự động gửi"},
    {"command": "token", "description": "Nhập token nguồn OTP hiện tại"},
    {"command": "hupsms", "description": "Nhập API key HupSMS"},
    {"command": "viotp", "description": "Nhập token ViOTP"},
    {"command": "run", "description": "Chạy hàng đợi tự động"},
    {"command": "stop", "description": "Dừng hàng đợi"},
    {"command": "cancel", "description": "Hủy thao tác nhập liệu"},
]


# ==============================================================================
# TELEGRAM API HELPERS
# ==============================================================================
def send_message(
    chat_id: int,
    text: str,
    parse_mode: str = "HTML",
    reply_markup: Any = None,
    reply_to_message_id: Optional[int] = None,
) -> Optional[dict]:
    url = f"{TELEGRAM_API_URL}/sendMessage"
    payload = {
        "chat_id": chat_id,
        "text": text,
        "parse_mode": parse_mode,
        "disable_web_page_preview": True,
    }
    if reply_to_message_id:
        payload["reply_to_message_id"] = reply_to_message_id
    if reply_markup is not None:
        payload["reply_markup"] = reply_markup
    else:
        payload["reply_markup"] = MAIN_KEYBOARD

    try:
        r = requests.post(url, json=payload, timeout=20)
        return r.json()
    except Exception as e:
        print(f"[!] Lỗi sendMessage: {e}")
        return None


def send_photo(
    chat_id: int,
    photo_path: str,
    caption: str = "",
    parse_mode: str = "HTML",
    reply_markup: Any = None,
) -> Optional[dict]:
    url = f"{TELEGRAM_API_URL}/sendPhoto"
    data = {"chat_id": chat_id, "caption": caption, "parse_mode": parse_mode}
    if reply_markup is not None:
        data["reply_markup"] = json.dumps(reply_markup)

    try:
        with open(photo_path, "rb") as f:
            files = {"photo": f}
            r = requests.post(url, data=data, files=files, timeout=35)
            return r.json()
    except Exception as e:
        print(f"[!] Lỗi sendPhoto: {e}")
        return None


def send_chat_action(chat_id: int, action: str = "typing"):
    url = f"{TELEGRAM_API_URL}/sendChatAction"
    try:
        requests.post(url, json={"chat_id": chat_id, "action": action}, timeout=10)
    except Exception:
        pass


def answer_callback_query(callback_query_id: str, text: str = "", show_alert: bool = False):
    url = f"{TELEGRAM_API_URL}/answerCallbackQuery"
    try:
        requests.post(url, json={"callback_query_id": callback_query_id, "text": text, "show_alert": show_alert}, timeout=10)
    except Exception:
        pass


def download_telegram_file(file_id: str, save_path: str) -> bool:
    try:
        # 1. Lấy file path từ Telegram
        r1 = requests.get(f"{TELEGRAM_API_URL}/getFile?file_id={file_id}", timeout=15)
        j1 = r1.json()
        if not j1.get("ok"):
            return False
        remote_path = j1["result"]["file_path"]

        # 2. Tải file binary
        download_url = f"https://api.telegram.org/file/bot{BOT_TOKEN}/{remote_path}"
        r2 = requests.get(download_url, timeout=30)
        if r2.status_code == 200:
            with open(save_path, "wb") as f:
                f.write(r2.content)
            return True
        return False
    except Exception as e:
        print(f"[!] Lỗi download file: {e}")
        return False


# ==============================================================================
# HÀM XỬ LÝ SỰ KIỆN ABBOTT & QUÉT QR
# ==============================================================================
def handle_event_url(chat_id: int, url: str):
    global cfg
    info = parse_abbott_event_url(url)
    if not info["is_abbott"]:
        send_message(
            chat_id,
            "⚠️ <b>Link không phải sự kiện Abbott hợp lệ!</b>\n"
            "Vui lòng kiểm tra lại đường dẫn (cần chứa domain <code>spot.abbott.com</code>).",
        )
        return

    cfg["active_event_url"] = info["url"]
    cfg["event_info"] = {
        "event_id": info["event_id"],
        "expire_time_str": info["expire_time_str"],
        "remaining_str": info["remaining_str"],
        "is_expired": info["is_expired"],
    }
    save_config(cfg)

    status_icon = "🔴" if info["is_expired"] else "🟢"
    expire_alert = f"<b>{status_icon} Thời gian hết hạn:</b> {info['expire_time_str']} (<i>{info['remaining_str']}</i>)"

    people_count = len(cfg.get("people", []))
    msg = (
        f"🎯 <b>ĐÃ NHẬN DIỆN SỰ KIỆN ABBOTT!</b>\n\n"
        f"🆔 <b>Mã sự kiện:</b> <code>{info['event_id'] or 'Chưa rõ'}</code>\n"
        f"🌐 <b>Quốc gia:</b> {info['country']}\n"
        f"{expire_alert}\n\n"
        f"👥 <b>DS người tham gia:</b> {people_count} người\n"
        f"📸 <b>Chế độ:</b> {'Duyệt ảnh' if cfg.get('submit_mode', 'review') == 'review' else 'Tự động gửi'}\n"
        f"🏥 <b>Bệnh viện:</b> {cfg.get('selected_hospital', 'Chưa chọn')}\n"
        f"🔑 <b>Nguồn OTP:</b> {cfg.get('otp_provider', 'hupsms').upper()}\n\n"
        f"👇 <i>Bạn có muốn khởi động chạy tự động toàn bộ danh sách ngay không?</i>"
    )

    inline_kb = {
        "inline_keyboard": [
            [
                {"text": "🚀 Bắt Đầu Chạy Tự Động Ngay", "callback_data": "start_queue"},
            ],
            [
                {"text": "📋 Xem Danh Sách Người", "callback_data": "menu_people"},
                {"text": "🏥 Đổi Bệnh Viện", "callback_data": "menu_hospital"},
            ],
        ]
    }
    send_message(chat_id, msg, reply_markup=inline_kb)


def handle_qr_photo(chat_id: int, file_id: str):
    send_chat_action(chat_id, "typing")
    temp_qr_path = os.path.join(DATA_DIR, "temp_qr.jpg")
    ok = download_telegram_file(file_id, temp_qr_path)
    if not ok:
        send_message(chat_id, "❌ Không tải được ảnh từ Telegram. Vui lòng thử lại!")
        return

    decoded_url = read_qr_from_file(temp_qr_path)
    try:
        if os.path.exists(temp_qr_path):
            os.remove(temp_qr_path)
    except Exception:
        pass

    if not decoded_url:
        send_message(
            chat_id,
            "❌ <b>Không quét được mã QR từ ảnh!</b>\n"
            "Vui lòng chụp lại ảnh QR rõ nét, đủ ánh sáng và không bị lóa hoặc gửi link URL trực tiếp.",
        )
        return

    send_message(chat_id, f"🔍 <b>Đã quét QR thành công:</b>\n<code>{decoded_url}</code>")
    handle_event_url(chat_id, decoded_url)


def show_mode_menu(chat_id: int):
    mode = load_config().get("submit_mode", "review")
    send_message(chat_id, f"📸 <b>CHẾ ĐỘ GỬI:</b> {'Duyệt ảnh trước khi gửi' if mode == 'review' else 'Tự động hoàn toàn'}\n"
                 "Duyệt ảnh: bot gửi ảnh, chờ bạn xác nhận tối đa 120 giây; quá hạn bỏ qua, không gửi form.\n"
                 "Tự động: gửi ảnh rồi tự bấm Gửi. OTP đã dùng có thể bị trừ phí ngay cả khi bỏ qua.",
                 reply_markup={"inline_keyboard": [
                     [{"text": f"{'✅ ' if mode == 'review' else ''}Duyệt ảnh từng người", "callback_data": "mode_review"}],
                     [{"text": f"{'✅ ' if mode == 'auto' else ''}Tự động hoàn toàn", "callback_data": "mode_auto"}],
                 ]})


# ==============================================================================
# LUỒNG CHẠY HÀNG ĐỢI TỰ ĐỘNG (QUEUE RUNNER)
# ==============================================================================
def run_automation_queue(chat_id: int):
    global is_queue_running, active_runner, cfg
    cfg = load_config()

    event_url = cfg.get("active_event_url", "")
    if not event_url:
        send_message(
            chat_id,
            "⚠️ <b>Chưa có Link sự kiện Abbott!</b>\n"
            "Vui lòng gửi link sự kiện hoặc gửi ảnh mã QR trước khi bắt đầu.",
        )
        is_queue_running = False
        return

    provider = cfg.get("otp_provider", "hupsms")
    token = cfg.get("hupsms_api_key" if provider == "hupsms" else "viotp_token", "")
    if not token:
        send_message(
            chat_id,
            f"⚠️ <b>Chưa cấu hình Token cho {provider.upper()}!</b>\n"
            f"Vào menu <b>🔑 Nguồn OTP & Token</b> để nhập mã xác thực.",
        )
        is_queue_running = False
        return

    # Lấy Service ID Abbott
    service_id = cfg.get(f"{provider}_service_id")
    if not service_id:
        send_message(chat_id, f"🔍 Đang tự động dò dịch vụ Abbott trên {provider.upper()}...")
        matches = OtpService.find_abbott_services(provider, token)
        if matches:
            service_id = matches[0]["id"]
            cfg[f"{provider}_service_id"] = service_id
            save_config(cfg)
            send_message(chat_id, f"✅ Đã chọn dịch vụ: <b>{matches[0]['displayName']}</b> (ID: {service_id})")
        else:
            send_message(chat_id, f"❌ Không tìm thấy dịch vụ 'Abbott' trên {provider.upper()}. Vui lòng kiểm tra lại!")
            is_queue_running = False
            return

    people = cfg.get("people", [])
    if not people:
        send_message(
            chat_id,
            "⚠️ <b>Danh sách người tham gia đang trống!</b>\n"
            "Vui lòng bấm <b>📋 DS Người Tham Gia</b> để nhập danh sách.",
        )
        is_queue_running = False
        return

    total = len(people)
    send_message(
        chat_id,
        f"🚀 <b>BẮT ĐẦU CHẠY TỰ ĐỘNG CHO {total} NGƯỜI!</b>\n"
        f"🏥 Bệnh viện: <b>{cfg.get('selected_hospital')}</b>\n"
        f"🔑 Nguồn OTP: <b>{provider.upper()}</b> (ID: {service_id})\n"
        f"⏱ Thời gian chờ OTP: <b>60 giây</b>\n"
        f"📸 Chế độ gửi: <b>{'Chờ duyệt ảnh' if cfg.get('submit_mode', 'review') == 'review' else 'Tự động hoàn toàn'}</b>\n"
        f"<i>Bot sẽ chụp ảnh thẻ form gửi lại Telegram trước khi submit từng người.</i>",
    )

    success_count = 0
    fail_count = 0
    start_all_time = time.time()

    def status_callback(msg: str):
        send_message(chat_id, msg)

    def screenshot_callback(img_path: str, caption: str):
        global review_pending
        markup = None
        if cfg.get("submit_mode", "review") == "review":
            with review_lock:
                review_pending = [chat_id, f"{time.time_ns()}", threading.Event(), None]
                uid = review_pending[1]
            markup = {"inline_keyboard": [[
                {"text": "✅ Gửi form", "callback_data": f"approve:{uid}"},
                {"text": "⏭ Bỏ qua", "callback_data": f"skip:{uid}"},
            ], [{"text": "⏹ Dừng hàng đợi", "callback_data": "stop_queue"}]]}
        result = send_photo(chat_id, img_path, caption=caption, reply_markup=markup)
        if not result or not result.get("ok"):
            with review_lock:
                review_pending = None
            return False
        return True

    def review_callback():
        global review_pending
        with review_lock:
            pending = review_pending
        if not pending or pending[0] != chat_id:
            return False
        pending[2].wait(timeout=120)
        with review_lock:
            decision = pending[3] if review_pending is pending else None
            if review_pending is pending:
                review_pending = None
        if decision is None:
            send_message(chat_id, "⏰ Quá 120 giây chưa duyệt: bỏ qua, chưa gửi form.")
        return decision == "approve" and is_queue_running

    active_runner = AbbottAutomationRunner(
        event_url=event_url,
        provider=provider,
        token=token,
        service_id=service_id,
        delay_ms=cfg.get("delay_ms", 700),
        otp_timeout=cfg.get("otp_timeout", 60),
        on_status_callback=status_callback,
        on_screenshot_callback=screenshot_callback,
        on_review_callback=review_callback if cfg.get("submit_mode", "review") == "review" else None,
    )

    for i, person in enumerate(people, start=1):
        if not is_queue_running or (active_runner and active_runner._is_stopped):
            send_message(chat_id, "⏹ <b>Hàng đợi đã được dừng theo yêu cầu của bạn!</b>")
            break

        send_message(chat_id, f"━━━━━━━━━━━━━━━━━━━━\n👤 <b>ĐANG XỬ LÝ [{i}/{total}]:</b> <code>{person['name']}</code>")

        ok, msg_res, shot_path = active_runner.process_person(person, i, total)
        if ok:
            success_count += 1
            send_message(chat_id, f"✅ <b>[Queue {i}/{total} XONG]</b> {msg_res}")
        else:
            fail_count += 1
            send_message(chat_id, f"❌ <b>[Queue {i}/{total} THẤT BẠI]</b> {msg_res}")

        # Nghỉ nhẹ giữa các người
        time.sleep(3.0)

    total_time = int(time.time() - start_all_time)
    minutes, seconds = divmod(total_time, 60)

    summary_msg = (
        f"🏁 <b>BÁO CÁO TỔNG KẾT HÀNG ĐỢI:</b>\n\n"
        f"👥 <b>Tổng số người:</b> {total}\n"
        f"✅ <b>Thành công:</b> {success_count}\n"
        f"❌ <b>Thất bại / Hết hạn:</b> {fail_count}\n"
        f"⏱ <b>Tổng thời gian:</b> {minutes} phút {seconds} giây\n"
        f"🎉 <i>Cảm ơn bạn đã sử dụng Abbott Auto-Fill Bot!</i>"
    )
    send_message(chat_id, summary_msg)
    is_queue_running = False
    active_runner = None


# ==============================================================================
# HÀM XỬ LÝ CALLBACK QUERIES (NÚT BẤM INLINE)
# ==============================================================================
def handle_callback_query(update: dict):
    global is_queue_running, active_runner, queue_thread, cfg, review_pending
    cb = update.get("callback_query", {})
    cb_id = cb.get("id")
    data = cb.get("data", "")
    msg = cb.get("message", {})
    chat_id = msg.get("chat", {}).get("id")

    if not chat_id:
        return

    if data.startswith("person:"):
        handle_person_callback(chat_id, cb_id, data)
        return

    if data.startswith(("approve:", "skip:")):
        with review_lock:
            pending = review_pending
            # ponytail: chỉ duyệt trong chat riêng của chủ queue; hỗ trợ nhóm khi có ACL người duyệt.
            if pending and chat_id > 0 and cb.get("from", {}).get("id") == chat_id and pending[0] == chat_id and pending[1] == data.split(":", 1)[1] and pending[3] is None and is_queue_running:
                pending[3] = "approve" if data.startswith("approve:") else "skip"
                pending[2].set()
                accepted = True
            else:
                accepted = False
        answer_callback_query(cb_id, "✅ Đã ghi nhận" if accepted else "Nút đã hết hiệu lực", show_alert=not accepted)
        return

    if data.startswith("mode_"):
        mode = data[5:]
        if mode not in ("review", "auto") or is_queue_running:
            answer_callback_query(cb_id, "Không đổi chế độ khi đang chạy", show_alert=True)
            return
        cfg["submit_mode"] = mode
        save_config(cfg)
        answer_callback_query(cb_id, "Đã lưu chế độ")
        show_mode_menu(chat_id)
        return

    if data == "start_queue":
        answer_callback_query(cb_id, "Đang khởi động hàng đợi...")
        if is_queue_running:
            send_message(chat_id, "⚠️ Hàng đợi đang chạy! Vui lòng đợi hoặc bấm Dừng.")
            return
        is_queue_running = True
        queue_thread = threading.Thread(target=run_automation_queue, args=(chat_id,), daemon=True)
        queue_thread.start()

    elif data == "stop_queue":
        answer_callback_query(cb_id, "Đang dừng hàng đợi...")
        is_queue_running = False
        with review_lock:
            if review_pending:
                review_pending[3] = "skip"
                review_pending[2].set()
        if active_runner:
            active_runner.stop()
        send_message(chat_id, "⏹ Đã gửi lệnh dừng tiến trình chạy tự động.")

    elif data == "menu_people":
        answer_callback_query(cb_id)
        show_people_menu(chat_id)

    elif data == "export_people":
        answer_callback_query(cb_id)
        people = cfg.get("people", [])
        if people:
            text = "\n".join(
                f"{p['name']} - " +
                (f"Khoa Khác - {p['otherDepartment']}" if p['department'] == 'Khac' else p['department']) +
                f" - {p['role']}" +
                (f" - {p['hospital']}" if p.get('hospital') != cfg.get('selected_hospital') else "")
                for p in people
            )
            if len(text) > 3500:
                send_message(chat_id, "Danh sách quá dài cho một tin nhắn; hãy chia nhỏ danh sách.")
            else:
                send_message(chat_id, "📋 Danh sách có thể dán lại:\n<pre>" + html.escape(text) + "</pre>")
        else:
            send_message(chat_id, "Danh sách trống; dùng /normalize để chuẩn hóa danh sách mới.")

    elif data == "menu_hospital":
        answer_callback_query(cb_id)
        show_hospital_menu(chat_id)

    elif data == "menu_otp":
        answer_callback_query(cb_id)
        show_otp_menu(chat_id)

    elif data.startswith("set_provider_"):
        new_p = data.replace("set_provider_", "")
        cfg["otp_provider"] = new_p
        save_config(cfg)
        answer_callback_query(cb_id, f"Đã chuyển sang {new_p.upper()}")
        show_otp_menu(chat_id)

    elif data.startswith("set_hosp_"):
        idx = int(data.replace("set_hosp_", ""))
        hosps = cfg.get("hospitals", DEFAULT_HOSPITALS)
        if 0 <= idx < len(hosps):
            chosen = hosps[idx]
            cfg["selected_hospital"] = chosen
            # Cập nhật luôn cho tất cả người trong DS
            for p in cfg.get("people", []):
                p["hospital"] = chosen
            save_config(cfg)
            answer_callback_query(cb_id, f"Đã chọn: {chosen}")
            send_message(chat_id, f"🏥 Đã đặt Bệnh viện mặc định: <b>{chosen}</b> (và gán cho toàn bộ DS).")
            show_hospital_menu(chat_id)

    elif data == "scan_services":
        answer_callback_query(cb_id, "Đang dò dịch vụ...")
        scan_abbott_services_for_user(chat_id)

    elif data.startswith("set_service_"):
        s_id = int(data.replace("set_service_", ""))
        provider = cfg.get("otp_provider", "hupsms")
        cfg[f"{provider}_service_id"] = s_id
        save_config(cfg)
        answer_callback_query(cb_id, f"Đã chọn Service ID: {s_id}")
        send_message(chat_id, f"✅ Đã lưu Service ID cho <b>{provider.upper()}</b>: <code>{s_id}</code>")

    elif data == "clear_people":
        if is_queue_running:
            answer_callback_query(cb_id, "Không sửa danh sách khi hàng đợi đang chạy", show_alert=True)
            return
        cfg["people"] = []
        save_config(cfg)
        answer_callback_query(cb_id, "Đã xóa toàn bộ danh sách")
        send_message(chat_id, "🗑 Đã xóa toàn bộ danh sách người tham gia.")

    elif data == "prompt_viotp_token":
        user_states[chat_id] = "WAITING_VIOTP_TOKEN"
        answer_callback_query(cb_id, "Nhập ViOTP Token")
        send_message(
            chat_id,
            "✏️ <b>VUI LÒNG GỬI VIOTP TOKEN CỦA BẠN:</b>\n\n"
            "👉 Hãy copy Token từ website <code>viotp.com</code> và gửi tin nhắn vào đây.\n\n"
            "<i>(Bấm '🔙 Quay lại Menu Chính' hoặc gửi /cancel để hủy)</i>",
            reply_markup=CANCEL_KEYBOARD,
        )

    elif data == "prompt_hupsms_key":
        user_states[chat_id] = "WAITING_HUPSMS_KEY"
        answer_callback_query(cb_id, "Nhập HupSMS API Key")
        send_message(
            chat_id,
            "✏️ <b>VUI LÒNG GỬI HUPSMS API KEY CỦA BẠN:</b>\n\n"
            "👉 Hãy copy API Key từ website <code>hupsms.com</code> và gửi tin nhắn vào đây.\n\n"
            "<i>(Bấm '🔙 Quay lại Menu Chính' hoặc gửi /cancel để hủy)</i>",
            reply_markup=CANCEL_KEYBOARD,
        )

    elif data == "prompt_current_token":
        provider = cfg.get("otp_provider", "hupsms")
        if provider == "hupsms":
            user_states[chat_id] = "WAITING_HUPSMS_KEY"
            answer_callback_query(cb_id, "Nhập HupSMS API Key")
            send_message(
                chat_id,
                "✏️ <b>VUI LÒNG GỬI HUPSMS API KEY CỦA BẠN:</b>\n\n"
                "👉 Hãy copy API Key từ website <code>hupsms.com</code> và gửi tin nhắn vào đây.\n\n"
                "<i>(Bấm '🔙 Quay lại Menu Chính' hoặc gửi /cancel để hủy)</i>",
                reply_markup=CANCEL_KEYBOARD,
            )
        else:
            user_states[chat_id] = "WAITING_VIOTP_TOKEN"
            answer_callback_query(cb_id, "Nhập ViOTP Token")
            send_message(
                chat_id,
                "✏️ <b>VUI LÒNG GỬI VIOTP TOKEN CỦA BẠN:</b>\n\n"
                "👉 Hãy copy Token từ website <code>viotp.com</code> và gửi tin nhắn vào đây.\n\n"
                "<i>(Bấm '🔙 Quay lại Menu Chính' hoặc gửi /cancel để hủy)</i>",
                reply_markup=CANCEL_KEYBOARD,
            )

    elif data == "prompt_new_hospital":
        user_states[chat_id] = "WAITING_NEW_HOSPITAL"
        answer_callback_query(cb_id, "Nhập tên bệnh viện")
        send_message(
            chat_id,
            "🏥 <b>VUI LÒNG GỬI TÊN BỆNH VIỆN MỚI:</b>\n\n"
            "👉 Gửi tin nhắn tên bệnh viện bạn muốn thêm (ví dụ: <code>Bệnh Viện Chợ Rẫy</code>).\n\n"
            "<i>(Bấm '🔙 Quay lại Menu Chính' hoặc gửi /cancel để hủy)</i>",
            reply_markup=CANCEL_KEYBOARD,
        )

    elif data == "check_balance_now":
        answer_callback_query(cb_id, "Đang lấy số dư...")
        show_balance(chat_id)


# ==============================================================================
# HÀM HIỂN THỊ CÁC MENU
# ==============================================================================
def person_session_valid(chat_id, token):
    session = person_sessions.get(chat_id)
    return session and session["token"] == token and session["people"] == cfg.get("people", [])


def handle_person_callback(chat_id, cb_id, data):
    parts = data.split(":")
    if len(parts) not in (4, 5) or not parts[2].isdigit():
        answer_callback_query(cb_id, "Nút không hợp lệ", show_alert=True)
        return
    _, token, raw_index, action, *choice = parts
    index = int(raw_index)
    if not person_session_valid(chat_id, token) or index >= len(cfg.get("people", [])):
        answer_callback_query(cb_id, "Danh sách đã thay đổi; mở lại /people", show_alert=True)
        return
    if is_queue_running or (queue_thread and queue_thread.is_alive()):
        answer_callback_query(cb_id, "Không sửa danh sách khi hàng đợi đang chạy", show_alert=True)
        return
    person = cfg["people"][index]
    user_states.pop(chat_id, None)
    prefix = f"person:{token}:{index}:"
    if action == "open" and not choice:
        answer_callback_query(cb_id)
        show_person_card(chat_id, index, token)
    elif action == "hospital" and not choice:
        hospitals = person_sessions[chat_id]["hospitals"]
        rows = [[{"text": ("✅ " if h == person.get('hospital') else "") + h, "callback_data": prefix + "hospital:" + str(i)}] for i, h in enumerate(hospitals)]
        rows.append([{"text": "✏️ Nhập bệnh viện khác", "callback_data": prefix + "hospital:custom"}])
        answer_callback_query(cb_id)
        send_message(chat_id, "Chọn bệnh viện:", reply_markup={"inline_keyboard": rows})
    elif action == "hospital" and len(choice) == 1 and choice[0].isdigit():
        hospitals = person_sessions[chat_id]["hospitals"]
        n = int(choice[0])
        if n >= len(hospitals) or hospitals != cfg.get("hospitals", DEFAULT_HOSPITALS):
            answer_callback_query(cb_id, "Danh sách bệnh viện đã thay đổi; mở lại /people", show_alert=True)
            return
        person["hospital"] = hospitals[n]
        save_config(cfg)
        answer_callback_query(cb_id, "Đã lưu")
        show_people_menu(chat_id, index)
    elif action in ("role", "department") and not choice:
        values = STANDARD_ROLES if action == "role" else STANDARD_DEPARTMENTS
        rows = [[{"text": ("✅ " if value == person.get(action) else "") + value, "callback_data": prefix + action + ":" + str(i)}] for i, value in enumerate(values)]
        answer_callback_query(cb_id)
        send_message(chat_id, "Chọn chức danh:" if action == "role" else "Chọn khoa:", reply_markup={"inline_keyboard": rows})
    elif action in ("role", "department") and len(choice) == 1 and choice[0].isdigit():
        values = STANDARD_ROLES if action == "role" else STANDARD_DEPARTMENTS
        n = int(choice[0])
        if n >= len(values):
            answer_callback_query(cb_id, "Lựa chọn không hợp lệ", show_alert=True)
            return
        if action == "department" and values[n] == "Khac":
            person_sessions[chat_id].update(index=index, field="otherDepartment")
            user_states[chat_id] = "WAITING_PERSON"
            answer_callback_query(cb_id)
            send_message(chat_id, "Nhập tên khoa khác hoặc /cancel:", reply_markup=CANCEL_KEYBOARD)
            return
        person[action] = values[n]
        if action == "department":
            person["otherDepartment"] = ""
        save_config(cfg)
        answer_callback_query(cb_id, "Đã lưu")
        show_people_menu(chat_id, index)
    elif (action == "name" and not choice) or (action == "hospital" and choice == ["custom"]) or (action == "otherDepartment" and not choice and person.get("department") == "Khac"):
        person_sessions[chat_id].update(index=index, field=action)
        user_states[chat_id] = "WAITING_PERSON"
        answer_callback_query(cb_id)
        send_message(chat_id, "Nhập " + ("tên" if action == "name" else "khoa khác" if action == "otherDepartment" else "bệnh viện") + " mới hoặc /cancel:", reply_markup=CANCEL_KEYBOARD)
    elif action == "remove" and not choice:
        answer_callback_query(cb_id)
        send_message(chat_id, "Xác nhận xóa <b>" + html.escape(person["name"]) + "</b>?", reply_markup={"inline_keyboard": [[
            {"text": "🗑 Xác nhận xóa", "callback_data": prefix + "remove:confirm"},
            {"text": "Hủy", "callback_data": prefix + "open"}]]})
    elif action == "remove" and choice == ["confirm"]:
        cfg["people"].pop(index)
        save_config(cfg)
        answer_callback_query(cb_id, "Đã xóa")
        show_people_menu(chat_id, max(0, index - 1))
    else:
        answer_callback_query(cb_id, "Nút không hợp lệ", show_alert=True)


def handle_person_text(chat_id, text):
    if text in ("/cancel", "🔙 Quay lại Menu Chính"):
        user_states.pop(chat_id, None)
        person_sessions.pop(chat_id, None)
        send_message(chat_id, "Đã hủy chỉnh sửa.", reply_markup=MAIN_KEYBOARD)
        return
    session = person_sessions.get(chat_id)
    if is_queue_running or (queue_thread and queue_thread.is_alive()):
        send_message(chat_id, "Không sửa danh sách khi hàng đợi đang chạy.")
        return
    if not session or not person_session_valid(chat_id, session["token"]) or session.get("index", -1) not in range(len(cfg.get("people", []))):
        user_states.pop(chat_id, None)
        send_message(chat_id, "Danh sách đã thay đổi; mở lại /people.", reply_markup=MAIN_KEYBOARD)
        return
    if not text.strip() or len(text) > 200 or "\n" in text or "\r" in text:
        send_message(chat_id, "Giá trị phải có 1–200 ký tự trên một dòng; gửi lại hoặc /cancel.")
        return
    person = cfg["people"][session["index"]]
    field = session["field"]
    person[field] = text.strip()
    if field == "otherDepartment":
        person["department"] = "Khac"
    save_config(cfg)
    user_states.pop(chat_id, None)
    send_message(chat_id, "Đã lưu.", reply_markup=MAIN_KEYBOARD)
    show_people_menu(chat_id, session["index"])


def show_person_card(chat_id, index, token):
    people = cfg.get("people", [])
    p = people[index]
    prefix = f"person:{token}:{index}:"
    fields = [("👤 Tên", "name"), ("🏷 Khoa", "department")]
    if p.get("department") == "Khac":
        fields.append(("🏷 Khoa khác", "otherDepartment"))
    fields += [("🩺 Chức danh", "role"), ("🏥 Bệnh viện", "hospital")]
    lines = [f"<b>👤 NGƯỜI THAM GIA {index + 1}/{len(people)}</b>"]
    rows = []
    for label, field in fields:
        lines.append(f"{label}: <b>{html.escape(str(p.get(field) or '—'))}</b>")
        rows.append([{"text": "✏️ " + label, "callback_data": prefix + field}])
    nav = []
    for target, label in ((index - 1, "⬅️ Trước"), (index + 1, "Tiếp ➡️")):
        if 0 <= target < len(people):
            nav.append({"text": label, "callback_data": f"person:{token}:{target}:open"})
    if nav:
        rows.append(nav)
    rows += [[{"text": "🗑 Xóa người này", "callback_data": prefix + "remove"}],
             [{"text": "📋 Xuất danh sách chuẩn", "callback_data": "export_people"}],
             [{"text": "🗑 Xóa toàn bộ danh sách", "callback_data": "clear_people"}]]
    send_message(chat_id, "\n".join(lines), reply_markup={"inline_keyboard": rows})


def show_people_menu(chat_id: int, index=0):
    people = cfg.get("people", [])
    count = len(people)
    token = secrets.token_hex(4)
    person_sessions[chat_id] = {"token": token, "people": copy.deepcopy(people), "hospitals": copy.deepcopy(cfg.get("hospitals", DEFAULT_HOSPITALS))}

    if count == 0:
        msg = (
            "📋 <b>DANH SÁCH NGƯỜI THAM GIA: (Trống)</b>\n\n"
            "👉 Hãy gửi danh sách người bằng cách gửi tin nhắn theo cú pháp chuẩn:\n"
            "Hoặc dùng /normalize để nhận bản chuẩn có thể sao chép dán lại.\n"
            "Khoa Khác: <code>Tên - Khoa Khác - Tên khoa - Chức danh [- Bệnh viện]</code>\n"
            "<code>Họ tên - Khoa/Phòng - Chức danh [- Tên BV]</code>\n\n"
            "<b>Ví dụ gửi tin nhắn:</b>\n"
            "<code>Huỳnh thị việt trinh - Khoa Ngoại Tổng Hợp - Y tá/ Điều dưỡng\n"
            "Nguyễn Văn An - Gây Mê Hồi Sức - Bác Sĩ Điều Trị\n"
            "Trần Thị Bình - Khoa Dược - Dược sĩ</code>"
        )
        send_message(chat_id, msg)
    else:
        show_person_card(chat_id, min(index, count - 1), token)


def show_hospital_menu(chat_id: int):
    cfg = load_config()
    current = cfg.get("selected_hospital", "Chưa chọn")
    hosps = cfg.get("hospitals", DEFAULT_HOSPITALS)

    rows = []
    for idx, h in enumerate(hosps):
        prefix = "✅ " if h == current else ""
        rows.append([{"text": f"{prefix}{h}", "callback_data": f"set_hosp_{idx}"}])

    # Nút thêm bệnh viện mới
    rows.append([{"text": "➕ Thêm Bệnh Viện Mới", "callback_data": "prompt_new_hospital"}])

    msg = (
        f"🏥 <b>QUẢN LÝ BỆNH VIỆN / PROFILE</b>\n\n"
        f"👉 Bệnh viện đang chọn: <b>{current}</b>\n\n"
        f"Chọn bệnh viện bên dưới hoặc bấm thêm mới:"
    )
    send_message(chat_id, msg, reply_markup={"inline_keyboard": rows})


def show_otp_menu(chat_id: int):
    cfg = load_config()
    provider = cfg.get("otp_provider", "hupsms")
    v_token = cfg.get("viotp_token", "")
    h_token = cfg.get("hupsms_api_key", "")
    h_server = cfg.get("hupsms_server_id", "247")
    v_sid = cfg.get("viotp_service_id")
    h_sid = cfg.get("hupsms_service_id")

    v_active = "✅ ViOTP" if provider == "viotp" else "ViOTP"
    h_active = "✅ HupSMS" if provider == "hupsms" else "HupSMS"

    curr_token_name = "HupSMS API Key" if provider == "hupsms" else "ViOTP Token"
    has_curr_token = bool(h_token if provider == "hupsms" else v_token)

    msg = (
        f"🔑 <b>CẤU HÌNH NGUỒN SIM & MÃ OTP</b>\n\n"
        f"📌 <b>Nguồn đang chọn:</b> <b>{provider.upper()}</b>\n\n"
        f"🔹 <b>ViOTP:</b>\n"
        f"  • Token: <code>{v_token[:8] + '...' if v_token else 'Chưa nhập ⚠️'}</code>\n"
        f"  • Service ID: <code>{v_sid or 'Tự dò'}</code>\n\n"
        f"🔹 <b>HupSMS:</b>\n"
        f"  • API Key: <code>{h_token[:8] + '...' if h_token else 'Chưa nhập ⚠️'}</code>\n"
        f"  • Server ưu tiên: <b>Server {h_server}</b> (1.500 đ ⭐)\n"
        f"  • Service ID: <code>{h_sid or 'Tự dò'}</code>\n\n"
        f"👇 <i>Bấm các nút dưới đây để cấu hình:</i>"
    )

    inline_kb = {
        "inline_keyboard": [
            [
                {"text": v_active, "callback_data": "set_provider_viotp"},
                {"text": h_active, "callback_data": "set_provider_hupsms"},
            ],
            [
                {"text": f"✏️ Nhập {curr_token_name}", "callback_data": f"prompt_{'hupsms_key' if provider == 'hupsms' else 'viotp_token'}"},
            ],
            [
                {"text": "✏️ Nhập ViOTP Token", "callback_data": "prompt_viotp_token"},
                {"text": "✏️ Nhập HupSMS Key", "callback_data": "prompt_hupsms_key"},
            ],
            [
                {"text": "🔍 Dò Dịch Vụ Abbott (Chọn Server)", "callback_data": "scan_services"},
                {"text": "💰 Xem Số Dư OTP", "callback_data": "check_balance_now"},
            ],
        ]
    }
    send_message(chat_id, msg, reply_markup=inline_kb)


def scan_abbott_services_for_user(chat_id: int):
    cfg = load_config()
    provider = cfg.get("otp_provider", "hupsms")
    token = cfg.get("hupsms_api_key" if provider == "hupsms" else "viotp_token", "")

    if not token:
        send_message(chat_id, f"⚠️ Chưa nhập Token cho {provider.upper()}! Vui lòng nhập token trước.")
        return

    send_chat_action(chat_id, "typing")
    matches = OtpService.find_abbott_services(provider, token)
    if not matches:
        send_message(chat_id, f"❌ Không tìm thấy dịch vụ 'Abbott' nào trên {provider.upper()}!")
        return

    rows = []
    for s in matches:
        price_str = f"{s['price']:,} đ".replace(",", ".") if s['price'] > 0 else ""
        label = f"{s['displayName']} - {price_str}"
        rows.append([{"text": label, "callback_data": f"set_service_{s['id']}"}])

    msg = (
        f"🎯 <b>CÁC SERVER ABBOTT KHẢ DỤNG TRÊN {provider.upper()}:</b>\n\n"
        f"Hệ thống đã sắp xếp từ giá rẻ nhất đến cao nhất. Hãy bấm chọn Server bạn muốn dùng:"
    )
    send_message(chat_id, msg, reply_markup={"inline_keyboard": rows})


def show_balance(chat_id: int):
    cfg = load_config()
    v_token = cfg.get("viotp_token", "")
    h_token = cfg.get("hupsms_api_key", "")

    v_bal_str = "Chưa có token"
    if v_token:
        ok, bal, err = OtpService.fetch_balance("viotp", v_token)
        v_bal_str = f"<b>{bal:,} đ</b>".replace(",", ".") if ok else f"Lỗi: {err}"

    h_bal_str = "Chưa có API key"
    if h_token:
        ok, bal, err = OtpService.fetch_balance("hupsms", h_token)
        h_bal_str = f"<b>{bal:,} đ</b>".replace(",", ".") if ok else f"Lỗi: {err}"

    msg = (
        f"💰 <b>SỐ DƯ TÀI KHOẢN HIỆN TẠI:</b>\n\n"
        f"🔹 <b>ViOTP (api.viotp.net):</b> {v_bal_str}\n"
        f"🔹 <b>HupSMS (hupsms.com):</b> {h_bal_str}\n\n"
        f"📌 Đang chọn nguồn: <b>{cfg.get('otp_provider', 'hupsms').upper()}</b>"
    )
    send_message(chat_id, msg)


# ==============================================================================
# VÒNG LẶP POLLING CHÍNH (MAIN BOT LOOP)
# ==============================================================================
def main():
    global cfg, user_states, is_queue_running, queue_thread, review_pending
    if not BOT_TOKEN:
        raise SystemExit("Thiếu BOT_TOKEN. Cấu hình biến môi trường BOT_TOKEN trước khi chạy.")
    print("=" * 60)
    print("🤖 ABBOTT TELEGRAM AUTOMATION BOT ĐANG KHỞI CHẠY...")
    print(f"📌 Bot Token: {BOT_TOKEN[:10]}...")

    # Kiểm tra xác thực Token với Telegram API
    try:
        r_me = requests.get(f"{TELEGRAM_API_URL}/getMe", timeout=10)
        if r_me.status_code == 200:
            bot_info = r_me.json().get("result", {})
            print(f"✅ Bot kết nối thành công: @{bot_info.get('username')} ({bot_info.get('first_name')})")
        else:
            print(f"⚠️ Telegram getMe status: {r_me.status_code} - {r_me.text}")
    except Exception as e:
        print(f"⚠️ Lỗi kết nối getMe: {e}")
    # Đăng ký danh sách gợi ý khi người dùng gõ '/' (bot vẫn chạy nếu đăng ký lỗi).
    try:
        r_commands = requests.post(
            f"{TELEGRAM_API_URL}/setMyCommands",
            json={"commands": BOT_COMMANDS}, timeout=10,
        )
        if not r_commands.ok or not r_commands.json().get("ok"):
            print(f"[!] Không đăng ký được lệnh Telegram: {r_commands.status_code}")
        r_menu = requests.post(
            f"{TELEGRAM_API_URL}/setChatMenuButton",
            json={"menu_button": {"type": "commands"}}, timeout=10,
        )
        if not r_menu.ok or not r_menu.json().get("ok"):
            print(f"[!] Không bật được menu lệnh Telegram: {r_menu.status_code}")
    except requests.exceptions.RequestException as e:
        print(f"[!] Không đăng ký được lệnh Telegram: {e}")
    print("=" * 60)
    print("🚀 Bot đang lắng nghe tin nhắn (Polling)...")

    offset = 0
    while True:
        try:
            url = f"{TELEGRAM_API_URL}/getUpdates?offset={offset}&timeout=25"
            r = requests.get(url, timeout=35)
            if r.status_code != 200:
                time.sleep(2)
                continue

            j = r.json()
            if not j.get("ok"):
                time.sleep(2)
                continue

            for update in j.get("result", []):
                offset = update["update_id"] + 1

                # 1. Xử lý Callback Query (Nút bấm Inline)
                if "callback_query" in update:
                    handle_callback_query(update)
                    continue

                msg = update.get("message", {})
                if not msg:
                    continue

                chat_id = msg.get("chat", {}).get("id")
                text = (msg.get("text") or "").strip()
                photos = msg.get("photo", [])
                doc = msg.get("document", {})

                # 2. Xử lý ảnh QR Code gửi qua photo hoặc document
                if photos:
                    # Lấy ảnh có độ phân giải cao nhất
                    largest_photo = photos[-1]
                    handle_qr_photo(chat_id, largest_photo["file_id"])
                    continue

                if doc and doc.get("mime_type", "").startswith("image/"):
                    handle_qr_photo(chat_id, doc["file_id"])
                    continue

                if not text:
                    continue

                # Lệnh / được ưu tiên hơn nội dung token đang chờ; /cancel vẫn xử lý trong trạng thái đó.
                command = text.split(maxsplit=1)[0].split("@", 1)[0].lower() if text.startswith("/") else ""
                if command and command != "/cancel":
                    user_states.pop(chat_id, None)
                if text == "🔙 Quay lại Menu Chính" and user_states.get(chat_id) not in ("WAITING_HUPSMS_KEY", "WAITING_VIOTP_TOKEN", "WAITING_NEW_HOSPITAL", "WAITING_NORMALIZE", "WAITING_PERSON"):
                    user_states.pop(chat_id, None)

                # 3. Xử lý trạng thái nhập liệu đang chờ
                state = user_states.get(chat_id)
                if state == "WAITING_PERSON":
                    handle_person_text(chat_id, text)
                    continue
                if state == "WAITING_NORMALIZE":
                    if text in ("/cancel", "🔙 Quay lại Menu Chính"):
                        user_states.pop(chat_id, None)
                        send_message(chat_id, "Đã hủy chuẩn hóa.", reply_markup=MAIN_KEYBOARD)
                    else:
                        try:
                            normalized = normalize_people_lines(text, cfg.get("selected_hospital", ""))
                            if len(normalized) > 3500:
                                raise ValueError("Danh sách chuẩn quá dài cho một tin nhắn; hãy chia nhỏ danh sách.")
                            user_states.pop(chat_id, None)
                            send_message(chat_id, "📋 Danh sách chuẩn (sao chép/dán lại để lưu):\n<pre>" + html.escape(normalized) + "</pre>", reply_markup=MAIN_KEYBOARD)
                        except ValueError as e:
                            send_message(chat_id, html.escape(str(e)) + "\nVui lòng gửi lại hoặc /cancel.")
                    continue

                if state == "WAITING_VIOTP_TOKEN":
                    if text in ["/cancel", "🔙 Quay lại Menu Chính"]:
                        user_states.pop(chat_id, None)
                        send_message(chat_id, "❌ Đã hủy nhập Token ViOTP.", reply_markup=MAIN_KEYBOARD)
                        show_otp_menu(chat_id)
                        continue

                    token_val = text.strip()
                    cfg["viotp_token"] = token_val
                    save_config(cfg)
                    user_states.pop(chat_id, None)

                    send_message(chat_id, "⏳ Đang kiểm tra token với hệ thống ViOTP...", reply_markup=MAIN_KEYBOARD)
                    ok, bal, err = OtpService.fetch_balance("viotp", token_val)
                    if ok:
                        bal_str = f"{bal:,} đ".replace(",", ".")
                        send_message(
                            chat_id,
                            f"✅ <b>LƯU VIOTP TOKEN THÀNH CÔNG!</b>\n\n"
                            f"💰 Số dư tài khoản: <b>{bal_str}</b>\n"
                            f"🔑 Token: <code>{token_val[:6]}...{token_val[-4:] if len(token_val)>10 else ''}</code>",
                            reply_markup=MAIN_KEYBOARD,
                        )
                    else:
                        send_message(
                            chat_id,
                            f"⚠️ <b>Đã lưu token nhưng không lấy được số dư!</b>\n"
                            f"Chi tiết: <code>{err}</code>\n"
                            f"Vui lòng kiểm tra lại nếu copy nhầm.",
                            reply_markup=MAIN_KEYBOARD,
                        )
                    show_otp_menu(chat_id)
                    continue

                elif state == "WAITING_HUPSMS_KEY":
                    if text in ["/cancel", "🔙 Quay lại Menu Chính"]:
                        user_states.pop(chat_id, None)
                        send_message(chat_id, "❌ Đã hủy nhập HupSMS API Key.", reply_markup=MAIN_KEYBOARD)
                        show_otp_menu(chat_id)
                        continue

                    token_val = text.strip()
                    cfg["hupsms_api_key"] = token_val
                    save_config(cfg)
                    user_states.pop(chat_id, None)

                    send_message(chat_id, "⏳ Đang kiểm tra API Key với hệ thống HupSMS...", reply_markup=MAIN_KEYBOARD)
                    ok, bal, err = OtpService.fetch_balance("hupsms", token_val)
                    if ok:
                        bal_str = f"{bal:,} đ".replace(",", ".")
                        send_message(
                            chat_id,
                            f"✅ <b>LƯU HUPSMS API KEY THÀNH CÔNG!</b>\n\n"
                            f"💰 Số dư tài khoản: <b>{bal_str}</b>\n"
                            f"🔑 API Key: <code>{token_val[:6]}...{token_val[-4:] if len(token_val)>10 else ''}</code>",
                            reply_markup=MAIN_KEYBOARD,
                        )
                        # Tự động dò danh sách server Abbott cho người dùng chọn luôn
                        scan_abbott_services_for_user(chat_id)
                    else:
                        send_message(
                            chat_id,
                            f"⚠️ <b>Đã lưu API Key nhưng không lấy được số dư!</b>\n"
                            f"Chi tiết: <code>{err}</code>\n"
                            f"Vui lòng kiểm tra lại nếu copy nhầm.",
                            reply_markup=MAIN_KEYBOARD,
                        )
                        show_otp_menu(chat_id)
                    continue

                elif state == "WAITING_NEW_HOSPITAL":
                    if text in ["/cancel", "🔙 Quay lại Menu Chính"]:
                        user_states.pop(chat_id, None)
                        send_message(chat_id, "❌ Đã hủy thêm bệnh viện.", reply_markup=MAIN_KEYBOARD)
                        show_hospital_menu(chat_id)
                        continue

                    hosp_name = text.strip()
                    hosps = cfg.get("hospitals", DEFAULT_HOSPITALS)
                    if hosp_name not in hosps:
                        hosps.append(hosp_name)
                    cfg["hospitals"] = hosps
                    cfg["selected_hospital"] = hosp_name
                    for p in cfg.get("people", []):
                        p["hospital"] = hosp_name
                    save_config(cfg)
                    user_states.pop(chat_id, None)
                    send_message(
                        chat_id,
                        f"✅ <b>ĐÃ THÊM VÀ CHỌN BỆNH VIỆN:</b>\n<b>{hosp_name}</b>\n<i>(Đã áp dụng cho toàn bộ danh sách)</i>",
                        reply_markup=MAIN_KEYBOARD,
                    )
                    show_hospital_menu(chat_id)
                    continue

                # 4. Xử lý các lệnh trực tiếp /hupsms, /viotp, /token, /cancel
                if command == "/cancel":
                    user_states.pop(chat_id, None)
                    send_message(chat_id, "❌ Đã hủy thao tác hiện tại.", reply_markup=MAIN_KEYBOARD)
                    continue

                if command == "/hupsms":
                    parts = text.split(maxsplit=1)
                    if len(parts) > 1:
                        val = parts[1].strip()
                        cfg["hupsms_api_key"] = val
                        cfg["otp_provider"] = "hupsms"
                        save_config(cfg)
                        send_message(chat_id, "⏳ Đang kiểm tra HupSMS API Key...", reply_markup=MAIN_KEYBOARD)
                        ok, bal, err = OtpService.fetch_balance("hupsms", val)
                        bal_str = f"{bal:,} đ".replace(",", ".") if ok else f"Lỗi: {err}"
                        send_message(chat_id, f"✅ Đã lưu HupSMS API Key!\n💰 Số dư: <b>{bal_str}</b>", reply_markup=MAIN_KEYBOARD)
                        scan_abbott_services_for_user(chat_id)
                    else:
                        user_states[chat_id] = "WAITING_HUPSMS_KEY"
                        send_message(chat_id, "✏️ <b>Vui lòng gửi HupSMS API Key vào đây:</b>", reply_markup=CANCEL_KEYBOARD)
                    continue

                if command == "/viotp":
                    parts = text.split(maxsplit=1)
                    if len(parts) > 1:
                        val = parts[1].strip()
                        cfg["viotp_token"] = val
                        cfg["otp_provider"] = "viotp"
                        save_config(cfg)
                        send_message(chat_id, "⏳ Đang kiểm tra ViOTP Token...", reply_markup=MAIN_KEYBOARD)
                        ok, bal, err = OtpService.fetch_balance("viotp", val)
                        bal_str = f"{bal:,} đ".replace(",", ".") if ok else f"Lỗi: {err}"
                        send_message(chat_id, f"✅ Đã lưu ViOTP Token!\n💰 Số dư: <b>{bal_str}</b>", reply_markup=MAIN_KEYBOARD)
                        show_otp_menu(chat_id)
                    else:
                        user_states[chat_id] = "WAITING_VIOTP_TOKEN"
                        send_message(chat_id, "✏️ <b>Vui lòng gửi ViOTP Token vào đây:</b>", reply_markup=CANCEL_KEYBOARD)
                    continue

                if command == "/token":
                    parts = text.split(maxsplit=1)
                    provider = cfg.get("otp_provider", "hupsms")
                    if len(parts) > 1:
                        val = parts[1].strip()
                        if provider == "hupsms":
                            cfg["hupsms_api_key"] = val
                        else:
                            cfg["viotp_token"] = val
                        save_config(cfg)
                        send_message(chat_id, f"⏳ Đang kiểm tra Token {provider.upper()}...", reply_markup=MAIN_KEYBOARD)
                        ok, bal, err = OtpService.fetch_balance(provider, val)
                        bal_str = f"{bal:,} đ".replace(",", ".") if ok else f"Lỗi: {err}"
                        send_message(chat_id, f"✅ Đã lưu Token cho {provider.upper()}!\n💰 Số dư: <b>{bal_str}</b>", reply_markup=MAIN_KEYBOARD)
                        if provider == "hupsms" and ok:
                            scan_abbott_services_for_user(chat_id)
                        else:
                            show_otp_menu(chat_id)
                    else:
                        if provider == "hupsms":
                            user_states[chat_id] = "WAITING_HUPSMS_KEY"
                            send_message(chat_id, "✏️ <b>Vui lòng gửi HupSMS API Key vào đây:</b>", reply_markup=CANCEL_KEYBOARD)
                        else:
                            user_states[chat_id] = "WAITING_VIOTP_TOKEN"
                            send_message(chat_id, "✏️ <b>Vui lòng gửi ViOTP Token vào đây:</b>", reply_markup=CANCEL_KEYBOARD)
                    continue

                if command == "/normalize":
                    parts = text.split(maxsplit=1)
                    if len(parts) == 1:
                        user_states[chat_id] = "WAITING_NORMALIZE"
                        send_message(chat_id, "📋 Dán danh sách mỗi dòng: Tên - Chức danh - Khoa (hoặc Tên - Khoa - Chức danh). Bot chỉ chuẩn hóa, không lưu; /cancel để hủy.", reply_markup=CANCEL_KEYBOARD)
                    else:
                        try:
                            normalized = normalize_people_lines(parts[1], cfg.get("selected_hospital", ""))
                            if len(normalized) > 3500:
                                raise ValueError("Danh sách chuẩn quá dài cho một tin nhắn; hãy chia nhỏ danh sách.")
                            send_message(chat_id, "📋 Danh sách chuẩn (sao chép/dán lại để lưu):\n<pre>" + html.escape(normalized) + "</pre>")
                        except ValueError as e:
                            send_message(chat_id, html.escape(str(e)))
                    continue
                if command == "/mode":
                    show_mode_menu(chat_id)
                    continue
                if command == "/run":
                    if is_queue_running:
                        send_message(chat_id, "⚠️ Hàng đợi đang chạy! Vui lòng đợi hoặc bấm Dừng.")
                    else:
                        is_queue_running = True
                        queue_thread = threading.Thread(target=run_automation_queue, args=(chat_id,), daemon=True)
                        queue_thread.start()
                    continue
                if command == "/stop":
                    is_queue_running = False
                    with review_lock:
                        if review_pending:
                            review_pending[3] = "skip"
                            review_pending[2].set()
                    if active_runner:
                        active_runner.stop()
                    send_message(chat_id, "⏹ Đã gửi lệnh dừng tiến trình chạy tự động.")
                    continue
                if command == "/people":
                    show_people_menu(chat_id)
                    continue
                if command == "/hospital":
                    show_hospital_menu(chat_id)
                    continue
                if command == "/otp":
                    show_otp_menu(chat_id)
                    continue
                if command == "/balance":
                    show_balance(chat_id)
                    continue
                if command == "/services":
                    scan_abbott_services_for_user(chat_id)
                    continue
                if command == "/link":
                    parts = text.split(maxsplit=1)
                    if len(parts) > 1:
                        handle_event_url(chat_id, parts[1].strip())
                    elif cfg.get("active_event_url"):
                        handle_event_url(chat_id, cfg["active_event_url"])
                    else:
                        send_message(chat_id, "🔗 Chưa có link sự kiện. Gửi /link &lt;URL&gt; hoặc ảnh QR.")
                    continue
                if command == "/help":
                    send_message(chat_id, "📖 <b>LỆNH NHANH:</b>\n"
                                 "/start — Menu chính\n/link &lt;URL&gt; — Link sự kiện\n"
                                 "/people — Danh sách người\n/normalize — Chuẩn hóa để dán lại\n/hospital — Bệnh viện\n"
                                 "/mode — Duyệt ảnh hoặc tự động gửi\n"
                                 "/otp — Nguồn OTP\n/token — Nhập token nguồn hiện tại\n"
                                 "/hupsms — Nhập HupSMS key\n/viotp — Nhập ViOTP token\n"
                                 "/balance — Số dư\n/services — Dò server Abbott\n"
                                 "/run — Chạy hàng đợi\n/stop — Dừng hàng đợi\n/cancel — Hủy nhập liệu")
                    continue
                if command and command != "/start":
                    send_message(chat_id, "⚠️ Lệnh không hỗ trợ. Gửi /help để xem các lệnh.")
                    continue

                lower_text = text.lower().strip()
                if lower_text in ["nhập token", "nhap token", "cài đặt token", "cai dat token"]:
                    show_otp_menu(chat_id)
                    continue

                # 4. Nhận diện URL sự kiện Abbott từ tin nhắn
                if "spot.abbott.com" in text or "eventRecordNumber" in text or text.startswith("http"):
                    handle_event_url(chat_id, text)
                    continue

                # 5. Xử lý Menu nút bấm chính
                if text == "🚀 Chạy Tự Động":
                    if is_queue_running:
                        send_message(chat_id, "⚠️ Hàng đợi đang chạy! Vui lòng đợi hoặc bấm Dừng.")
                    else:
                        is_queue_running = True
                        queue_thread = threading.Thread(target=run_automation_queue, args=(chat_id,), daemon=True)
                        queue_thread.start()

                elif text == "🔗 Link Sự Kiện":
                    curr_url = cfg.get("active_event_url", "")
                    if curr_url:
                        handle_event_url(chat_id, curr_url)
                    else:
                        send_message(
                            chat_id,
                            "🔗 <b>Chưa có link sự kiện nào được lưu!</b>\n"
                            "Hãy gửi link URL sự kiện hoặc gửi ảnh chụp mã QR để bot nhận diện.",
                        )

                elif text == "📋 DS Người Tham Gia":
                    show_people_menu(chat_id)

                elif text == "🏥 Chọn Bệnh Viện":
                    show_hospital_menu(chat_id)

                elif text == "🔑 Nguồn OTP & Token":
                    show_otp_menu(chat_id)

                elif text == "💰 Số Dư Tài Khoản":
                    show_balance(chat_id)

                elif text == "📋 Chuẩn Hóa DS":
                    user_states[chat_id] = "WAITING_NORMALIZE"
                    send_message(chat_id, "📋 Dán danh sách: Tên - Chức danh - Khoa (hoặc Tên - Khoa - Chức danh). Bot trả bản chuẩn để bạn dán lại; /cancel để hủy.", reply_markup=CANCEL_KEYBOARD)

                elif text == "📸 Chế Độ Gửi":
                    show_mode_menu(chat_id)

                elif text == "⚙️ Cài Đặt Chung":
                    cfg = load_config()
                    msg = (
                        f"⚙️ <b>CÀI ĐẶT HỆ THỐNG:</b>\n\n"
                        f"🏥 Bệnh viện mặc định: <b>{cfg.get('selected_hospital')}</b>\n"
                        f"🔑 Nguồn OTP: <b>{cfg.get('otp_provider', 'hupsms').upper()}</b>\n"
                        f"⏱ Timeout OTP: <b>{cfg.get('otp_timeout', 60)} giây</b>\n"
                        f"⚡ Độ trễ điền form: <b>{cfg.get('delay_ms', 700)} ms</b>\n"
                        f"👥 Số người trong DS: <b>{len(cfg.get('people', []))}</b>\n\n"
                        f"<i>(Dữ liệu được lưu vĩnh viễn trong Docker volume)</i>"
                    )
                    send_message(chat_id, msg)

                elif text == "📖 Hướng Dẫn Sử Dụng":
                    guide = (
                        "📖 <b>HƯỚNG DẪN SỬ DỤNG ABBOTT TELEGRAM BOT:</b>\n\n"
                        "1️⃣ <b>Gửi Link sự kiện hoặc Ảnh QR:</b>\n"
                        "  • Dán link hoặc gửi ảnh mã QR sự kiện.\n"
                        "  • Bot sẽ phân tích thời gian hết hạn cụ thể.\n\n"
                        "2️⃣ <b>Cấu hình Token OTP:</b>\n"
                        "  • Bấm <b>🔑 Nguồn OTP & Token</b> -> Nhập token ViOTP hoặc API key HupSMS.\n"
                        "  • Bấm dò dịch vụ để chọn Server Abbott (Server 247 giá 1.500đ).\n\n"
                        "3️⃣ <b>Chuẩn hóa danh sách:</b>\n"
                        "  • /normalize rồi dán danh sách; sao chép bản chuẩn trả về để lưu.\n\n"
                        "4️⃣ <b>Chọn chế độ:</b> /mode (duyệt ảnh hoặc tự động gửi).\n"
                        "5️⃣ <b>Bấm 🚀 Chạy Tự Động:</b>\n"
                        "  • Bot thuê số, xác thực OTP, điền form, gửi ảnh.\n"
                        "  • Chế độ duyệt ảnh chỉ bấm Gửi khi bạn xác nhận; quá 120 giây sẽ bỏ qua."
                    )
                    send_message(chat_id, guide)

                elif text == "/start" or text == "🔙 Quay lại Menu Chính":
                    user_states.pop(chat_id, None)
                    welcome = (
                        "👋 <b>CHÀO MỪNG ĐẾN VỚI ABBOTT EVENT AUTO-FILL BOT!</b>\n\n"
                        "Ứng dụng tự động hóa đăng ký sự kiện & hội thảo Abbott qua Telegram.\n\n"
                        "👉 <b>Bước 1:</b> Gửi <b>Link URL</b> hoặc <b>Ảnh mã QR</b> sự kiện.\n"
                        "👉 <b>Bước 2:</b> Bấm <b>🔑 Nguồn OTP</b> để nạp token & chọn Server.\n"
                        "👉 <b>Bước 3:</b> Gửi danh sách người cần đăng ký.\n"
                        "👉 <b>Bước 4:</b> Bấm <b>🚀 Chạy Tự Động</b> và nhận ảnh chụp thẻ hoàn tất!"
                    )
                    send_message(chat_id, welcome, reply_markup=MAIN_KEYBOARD)

                elif " - " in text:
                    # Người dùng gửi văn bản danh sách người tham gia
                    if is_queue_running:
                        send_message(chat_id, "⚠️ Không sửa danh sách khi hàng đợi đang chạy.")
                        continue
                    if len(text) > 20000:
                        send_message(chat_id, "⚠️ Danh sách quá dài (tối đa 20.000 ký tự).")
                        continue
                    try:
                        parsed = parse_people_lines(text, cfg.get("selected_hospital", ""))
                    except ValueError as e:
                        send_message(chat_id, "⚠️ " + html.escape(str(e)) + "\nDùng /normalize để xem bản chuẩn trước khi lưu.")
                        continue
                    if parsed:
                        cfg["people"] = parsed
                        save_config(cfg)
                        send_message(
                            chat_id,
                            f"✅ <b>ĐÃ CẬP NHẬT {len(parsed)} NGƯỜI VÀO DANH SÁCH!</b>\n"
                            f"Bấm các trường bên dưới để chỉnh từng người; thay đổi được lưu ngay.",
                        )
                        show_people_menu(chat_id)

        except requests.exceptions.Timeout:
            # Long-polling bình thường timeout khi không có tin nhắn mới, không cần in log
            continue
        except requests.exceptions.RequestException as req_err:
            print(f"[!] Lỗi kết nối Telegram (đang kết nối lại): {req_err}")
            time.sleep(3)
        except KeyboardInterrupt:
            print("\n[*] Đã dừng bot theo yêu cầu.")
            break
        except Exception as e:
            import traceback
            traceback.print_exc()
            time.sleep(2)


if __name__ == "__main__":
    main()
