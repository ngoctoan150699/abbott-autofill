"""Chạy trong image Playwright: python test_other_department.py. Không gọi Abbott/Telegram."""
import ast
from pathlib import Path
from playwright.sync_api import sync_playwright

source = ast.parse(Path(__file__).with_name('abbott_browser.py').read_text(encoding='utf-8'))
fill_js = next(n.value.value for n in ast.walk(source) if isinstance(n, ast.Assign)
               and any(isinstance(t, ast.Name) and t.id == 'fill_js' for t in n.targets))
html = '''
<div class="el-form-item"><label>Vai trò</label><div class="el-select"><input placeholder="Vai trò"></div></div>
<div class="el-form-item"><label>Bệnh viện</label><div class="el-select"><input placeholder="Bệnh viện"></div></div>
<div class="el-form-item"><label>Phòng ban</label><div class="el-select"><input placeholder="Phòng ban"></div></div>
<div id="other"></div>
<div class="el-form-item"><label>Chức danh</label><div class="el-select"><input placeholder="Chức danh"></div></div>
<div id="options"></div>
<script>
document.querySelectorAll('.el-select input').forEach((el, index) => el.onclick = () => {
  let texts = [['Nguoi tham du'], ['BV X'], ['Khác biệt', 'Khác', 'Khoa Ngoai Tong Hop'], ['Bac Sy Dieu Tri']][index];
  document.querySelector('#options').innerHTML = '';
  texts.forEach(text => {
    let option = document.createElement('div'); option.className = 'el-select-dropdown__item'; option.innerText = text;
    option.onclick = () => {
      el.value = text; document.querySelector('#options').innerHTML = '';
      if (index === 2 && text === 'Khác') setTimeout(() => {
        document.querySelector('#other').innerHTML = '<div class="el-form-item"><label>Phòng ban (khác)</label><input placeholder="Nhập khoa khác"></div>';
        document.querySelector('#other input').addEventListener('input', e => window.savedDepartment = e.target.value);
      }, 200);
    };
    document.querySelector('#options').appendChild(option);
  });
});
</script>
'''
with sync_playwright() as p:
    browser = p.chromium.launch(headless=True, args=['--no-sandbox'])
    page = browser.new_page()
    page.set_content(html)
    page.evaluate(fill_js, {'roleParticipant': 'Nguoi tham du', 'hospital': 'BV X',
                            'department': 'Khac', 'otherDepartment': 'Khoa Lão', 'role': 'Bac Sy Dieu Tri'})
    assert page.locator('input[placeholder="Phòng ban"]').input_value() == 'Khác'
    assert page.locator('input[placeholder="Nhập khoa khác"]').input_value() == 'Khoa Lão'
    assert page.evaluate('window.savedDepartment') == 'Khoa Lão'
    # Khoa thông thường không mở hoặc điền ô Phòng ban (Khác).
    page = browser.new_page()
    page.set_content(html)
    page.evaluate(fill_js, {'roleParticipant': 'Nguoi tham du', 'hospital': 'BV X',
                            'department': 'Khoa Ngoai Tong Hop', 'otherDepartment': '', 'role': 'Bac Sy Dieu Tri'})
    assert page.locator('input[placeholder="Phòng ban"]').input_value() == 'Khoa Ngoai Tong Hop'
    assert page.locator('input[placeholder="Nhập khoa khác"]').count() == 0
    # Missing "Khác" must not select a partial match or fill another field.
    page = browser.new_page()
    page.set_content(html.replace("['Khác biệt', 'Khác', 'Khoa Ngoai Tong Hop']", "['Khác biệt', 'Khoa Ngoai Tong Hop']"))
    try:
        page.evaluate(fill_js, {'roleParticipant': 'Nguoi tham du', 'hospital': 'BV X',
                                'department': 'Khac', 'otherDepartment': 'Khoa Lão', 'role': 'Bac Sy Dieu Tri'})
        raise AssertionError('Thiếu lựa chọn Khác phải báo lỗi')
    except Exception as exc:
        assert 'Không chọn được Khoa' in str(exc)
    # Nếu ô nhập không xuất hiện thì dừng, không giả định thành công.
    page = browser.new_page()
    page.set_content(html.replace("document.querySelector('#other').innerHTML = '<div", "document.querySelector('#other').innerHTML = '<div style=\"display:none\""))
    try:
        page.evaluate(fill_js, {'roleParticipant': 'Nguoi tham du', 'hospital': 'BV X',
                                'department': 'Khac', 'otherDepartment': 'Khoa Lão', 'role': 'Bac Sy Dieu Tri'})
        raise AssertionError('Ô nhập ẩn phải báo lỗi')
    except Exception as exc:
        assert 'Không chọn/điền được Khoa' in str(exc)
    browser.close()
print('Custom department form check OK')
