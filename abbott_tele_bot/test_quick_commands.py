"""Chạy: python test_quick_commands.py (không gọi Telegram thật)."""
import sys
import types
from unittest.mock import patch

# Chỉ kiểm tra điều hướng Telegram; tránh nạp trình duyệt/QR khi chạy local.
sys.modules['qr_reader'] = types.SimpleNamespace(read_qr_from_file=None, parse_abbott_event_url=None)
sys.modules['abbott_browser'] = types.SimpleNamespace(AbbottAutomationRunner=object)
import telegram_bot as bot
from config import normalize_people_lines, parse_people_lines

sample = """Phan Kim Thuỳ Linh - bs - ngoại tổng hợp
Nguyễn Thị Kim Thuỳ - điều dưỡng trưởng - ngoại thần kinh
Trương Thị Mỹ Quyên - điều dưỡng - ngoại tiêu hoá
Phạm Thị Truyền - điều dưỡng - ngoại tiêu hoá
Đặng Thị Bích Liễu - điều dưỡng - ngoại tổng hợp
Cao Thị Huyền Trang - bs - ngoại tổng hợp
Trần Thị Hoàng Mai - điều dưỡng trưởng - ngoại tổng hợp
Nguyễn thị như quyên - ngoại tổng hợp - bs điều trị
Huỳnh thị việt trinh - ngoại tổng hợp - y tá điều dưỡng"""
expected = """Phan Kim Thuỳ Linh - Khoa Ngoại Tổng Hợp - Bác Sỹ Điều Trị
Nguyễn Thị Kim Thuỳ - Khoa Ngoại Thần Kinh - Y Tá Trưởng/Điều Dưỡng Trưởng
Trương Thị Mỹ Quyên - Khoa Ngoại Tiêu Hóa - Y Tá/Điều Dưỡng
Phạm Thị Truyền - Khoa Ngoại Tiêu Hóa - Y Tá/Điều Dưỡng
Đặng Thị Bích Liễu - Khoa Ngoại Tổng Hợp - Y Tá/Điều Dưỡng
Cao Thị Huyền Trang - Khoa Ngoại Tổng Hợp - Bác Sỹ Điều Trị
Trần Thị Hoàng Mai - Khoa Ngoại Tổng Hợp - Y Tá Trưởng/Điều Dưỡng Trưởng
Nguyễn thị như quyên - Khoa Ngoại Tổng Hợp - Bác Sỹ Điều Trị
Huỳnh thị việt trinh - Khoa Ngoại Tổng Hợp - Y Tá/Điều Dưỡng"""
assert normalize_people_lines(sample) == expected
assert len(parse_people_lines(expected)) == 9
other = 'Trần Văn An - Khoa Khác - Khoa Lão - bs'
assert normalize_people_lines(other) == 'Trần Văn An - Khoa Khác - Khoa Lão - Bác Sỹ Điều Trị'
assert parse_people_lines(normalize_people_lines(other))[0]['otherDepartment'] == 'Khoa Lão'
assert parse_people_lines('Trần Văn An - Khoa Lão - bs')[0]['department'] == 'Khac'
assert parse_people_lines('Trần Văn An - Khoa Lão - bs')[0]['otherDepartment'] == 'Khoa Lão'
assert parse_people_lines('Trần Văn An - Khoa Khác - Khoa Lão - bs - BV X')[0]['hospital'] == 'BV X'
assert normalize_people_lines('Trần Văn An - Khoa Lão - bs - BV X') == 'Trần Văn An - Khoa Khác - Khoa Lão - Bác Sỹ Điều Trị - BV X'
assert parse_people_lines(normalize_people_lines('Trần Văn An - Khoa Lão - bs - BV X'))[0]['hospital'] == 'BV X'
try:
    parse_people_lines('Trần Văn An - Khoa Khác - bs')
    assert False, 'Khoa Khác không có tên khoa phải báo lỗi'
except ValueError:
    pass
try:
    parse_people_lines('Tên - vai trò lạ - ngoại tổng hợp')
    assert False, 'Phải từ chối vai trò không rõ'
except ValueError:
    pass


updates = [
    {'update_id': i, 'message': {'chat': {'id': 123}, 'text': text}}
    for i, text in enumerate(['/token', '/cancel', '/otp', '/help', '/people', '/run', '/stop'])
]
requests_seen = []
messages = []

class Response:
    status_code = 200
    ok = True
    def __init__(self, result): self.result = result
    def json(self): return {'ok': True, 'result': self.result}

def fake_get(url, **kw):
    if url.endswith('/getMe'): return Response({'username': 'test_bot'})
    if updates: return Response([updates.pop(0)])
    raise KeyboardInterrupt

def fake_post(url, json=None, **kw):
    if url.endswith('/setMyCommands'): requests_seen.extend(json['commands'])
    return Response(True)

with patch.object(bot.requests, 'get', side_effect=fake_get), \
     patch.object(bot.requests, 'post', side_effect=fake_post), \
     patch.object(bot, 'send_message', side_effect=lambda chat, text, **kw: messages.append(text)), \
     patch.object(bot.threading, 'Thread'):
    bot.main()

assert not bot.user_states, 'Lệnh /cancel phải hủy trạng thái nhập token'
assert any('Vui lòng gửi HupSMS API Key' in m for m in messages)
assert any('LỆNH NHANH' in m for m in messages)
assert {c['command'] for c in requests_seen} >= {'start','help','otp','token','run','stop','people','balance','normalize','mode'}

# Review gate: skip/stale must not approve; only matching current approval unblocks.
import threading
pending = [123, 'unique', threading.Event(), None]
bot.review_pending = pending
bot.is_queue_running = True
with patch.object(bot, 'answer_callback_query'):
    bot.handle_callback_query({'callback_query': {'id':'x','data':'approve:stale','from':{'id':123},'message':{'chat':{'id':123}}}})
    assert pending[3] is None and not pending[2].is_set()
    bot.handle_callback_query({'callback_query': {'id':'y','data':'skip:unique','from':{'id':123},'message':{'chat':{'id':123}}}})
assert pending[3] == 'skip' and pending[2].is_set()
bot.review_pending = None
bot.is_queue_running = False

# Dấu tick chỉ xuất hiện tại chế độ đang chọn.
with patch.object(bot, 'load_config', return_value={'submit_mode': 'review'}), \
     patch.object(bot, 'send_message') as send:
    bot.show_mode_menu(123)
    rows = send.call_args.kwargs['reply_markup']['inline_keyboard']
    assert rows[0][0]['text'].startswith('✅ ') and not rows[1][0]['text'].startswith('✅ ')
with patch.object(bot, 'load_config', return_value={'submit_mode': 'auto'}), \
     patch.object(bot, 'send_message') as send:
    bot.show_mode_menu(123)
    rows = send.call_args.kwargs['reply_markup']['inline_keyboard']
    assert not rows[0][0]['text'].startswith('✅ ') and rows[1][0]['text'].startswith('✅ ')
print('Quick commands OK')
from unittest.mock import patch
import copy

with patch.object(bot, 'send_message') as sent, patch.object(bot, 'answer_callback_query'), patch.object(bot, 'save_config') as save:
    bot.cfg = {'people': parse_people_lines('Trần Văn An - ngoại tổng hợp - bs - BV X')}
    bot.is_queue_running = False
    bot.queue_thread = None
    bot.show_people_menu(123)
    token = bot.person_sessions[123]['token']
    def click(action):
        bot.handle_callback_query({'callback_query': {'id': 'cb', 'data': f'person:{token}:0:{action}', 'message': {'chat': {'id': 123}}}})
    click('name')
    bot.handle_person_text(123, 'Tên mới')
    assert bot.cfg['people'][0]['name'] == 'Tên mới'
    token = bot.person_sessions[123]['token']
    click('role:0')
    assert bot.cfg['people'][0]['role'] == bot.STANDARD_ROLES[0]
    token = bot.person_sessions[123]['token']
    click(f'department:{len(bot.STANDARD_DEPARTMENTS)-1}')
    bot.handle_person_text(123, 'Khoa Lão')
    assert bot.cfg['people'][0]['department'] == 'Khac' and bot.cfg['people'][0]['otherDepartment'] == 'Khoa Lão'
    token = bot.person_sessions[123]['token']
    click('hospital:custom')
    bot.handle_person_text(123, 'BV Y')
    assert bot.cfg['people'][0]['hospital'] == 'BV Y'
    token = bot.person_sessions[123]['token']
    before = copy.deepcopy(bot.cfg)
    bot.is_queue_running = True
    click('remove')
    assert bot.cfg == before
    bot.is_queue_running = False
    click('remove')
    assert bot.cfg == before
    click('remove:confirm')
    assert bot.cfg['people'] == []
    click('remove')  # stale button must not affect a different person
    assert bot.cfg['people'] == []

with patch.object(bot, 'send_message') as sent, patch.object(bot, 'answer_callback_query'), patch.object(bot, 'save_config'):
    bot.cfg = {'people': parse_people_lines('A <B> - ngoại tổng hợp - bs - BV X\nC - Khoa Khác - Lão - bs - BV Y'), 'hospitals': ['BV X', 'BV Y']}
    bot.show_people_menu(123)
    token = bot.person_sessions[123]['token']
    assert 'A &lt;B&gt;' in sent.call_args.args[1] and 'BV X' in sent.call_args.args[1]
    rows = sent.call_args.kwargs['reply_markup']['inline_keyboard']
    buttons = [button['callback_data'] for row in rows for button in row]
    assert f'person:{token}:1:open' in buttons and not any('otherDepartment' in b for b in buttons)
    bot.handle_person_callback(123, 'cb', f'person:{token}:1:open')
    assert 'Lão' in sent.call_args.args[1]
    assert any('otherDepartment' in b['callback_data'] for r in sent.call_args.kwargs['reply_markup']['inline_keyboard'] for b in r)
    bot.handle_person_callback(123, 'cb', f'person:{token}:1:hospital')
    assert any(b['callback_data'].endswith('hospital:0') for r in sent.call_args.kwargs['reply_markup']['inline_keyboard'] for b in r)
    bot.handle_person_callback(123, 'cb', f'person:{token}:1:hospital:0')
    assert bot.cfg['people'][1]['hospital'] == 'BV X' and '2/2' in sent.call_args.args[1]
    bot.handle_person_callback(123, 'cb', f'person:{token}:0:remove:confirm')
    assert len(bot.cfg['people']) == 2  # stale session cannot delete
