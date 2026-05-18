const REQUIRED_LOCATION = {
  latitude: 15.1151,
  longitude: 108.7905,
  maxDistanceMeters: 350,
};

function removeVietnameseMarks(value) {
  return String(value || '')
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .replace(/đ/g, 'd')
    .replace(/Đ/g, 'D')
    .replace(/\s+/g, ' ')
    .trim();
}

function normalize(value) {
  return removeVietnameseMarks(value).toLowerCase();
}

function titleCase(value) {
  return removeVietnameseMarks(value)
    .toLowerCase()
    .split(' ')
    .filter(Boolean)
    .map((word) => word.charAt(0).toUpperCase() + word.slice(1))
    .join(' ');
}

function formatDepartment(raw) {
  const value = normalize(raw);
  if (value.includes('gay me')) return 'Khoa Gay Me Hoi Suc';
  if (value.includes('ngoai than kinh') || value.includes('phau thuat than kinh')) return 'Khoa phau thuat than kinh';
  if (value.includes('ngoai tong hop') || value.includes('ngoai tong quat')) return 'Khoa Ngoai Tong Quat';
  if (value.includes('ngoai tieu hoa') || value.includes('noi tieu hoa')) return 'Khoa Noi Tieu Hoa';
  if (value.includes('chan thuong') || value.includes('chinh hinh') || value.includes('bong')) return 'Khoa Chan Thuong Chinh Hinh';
  if (value.includes('noi tong hop')) return 'Khoa Noi Tong Hop';
  if (value.includes('phong dieu duong')) return 'Phong Dieu duong';
  return titleCase(raw);
}

function formatRole(raw) {
  const value = normalize(raw).replace(/\./g, '').trim();
  if (value === 'bs' || value.includes('bac si') || value.includes('bac sy')) return 'Bac Sy Dieu Tri';
  if (value.includes('truong')) return 'Y Ta Truong/ Dieu Duong Truong';
  if (value === 'dd' || value.includes('dieu duong')) return 'Y ta/ Dieu duong';
  return titleCase(raw);
}

function distanceMeters(a, b) {
  const earth = 6371000;
  const dLat = (b.latitude - a.latitude) * Math.PI / 180;
  const dLon = (b.longitude - a.longitude) * Math.PI / 180;
  const lat1 = a.latitude * Math.PI / 180;
  const lat2 = b.latitude * Math.PI / 180;
  const x = Math.sin(dLat / 2) ** 2 + Math.cos(lat1) * Math.cos(lat2) * Math.sin(dLon / 2) ** 2;
  return earth * 2 * Math.atan2(Math.sqrt(x), Math.sqrt(1 - x));
}

function getBrowserLocation() {
  return new Promise((resolve, reject) => {
    if (!navigator.geolocation) {
      reject(new Error('Trình duyệt không hỗ trợ geolocation'));
      return;
    }
    navigator.geolocation.getCurrentPosition(
      (position) => resolve({
        latitude: position.coords.latitude,
        longitude: position.coords.longitude,
      }),
      reject,
      { enableHighAccuracy: true, timeout: 10000, maximumAge: 0 },
    );
  });
}

async function ensureLocationReady() {
  const current = await getBrowserLocation();
  const distance = distanceMeters(current, REQUIRED_LOCATION);
  if (distance > REQUIRED_LOCATION.maxDistanceMeters) {
    throw new Error(`Chưa đúng vị trí BVĐK Quảng Ngãi. Sai lệch khoảng ${Math.round(distance)}m. Hãy bật GeoSpoof Location Protection 15.1151,108.7905 rồi reload.`);
  }
  return true;
}

function getTextAround(element) {
  const parts = [];
  const id = element.getAttribute('id');
  if (id) {
    const label = document.querySelector(`label[for="${CSS.escape(id)}"]`);
    if (label) parts.push(label.textContent);
  }
  parts.push(element.getAttribute('placeholder'));
  parts.push(element.getAttribute('name'));
  parts.push(element.getAttribute('id'));
  let parent = element.parentElement;
  for (let i = 0; i < 4 && parent; i += 1) {
    parts.push(parent.textContent);
    parent = parent.parentElement;
  }
  return normalize(parts.filter(Boolean).join(' '));
}

function setNativeValue(element, value) {
  const proto = element instanceof HTMLTextAreaElement ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype;
  const setter = Object.getOwnPropertyDescriptor(proto, 'value')?.set;
  setter?.call(element, value);
  element.dispatchEvent(new Event('input', { bubbles: true }));
  element.dispatchEvent(new Event('change', { bubbles: true }));
}

function clickByText(texts) {
  const normalizedTexts = texts.map(normalize);
  const candidates = [...document.querySelectorAll('button, [role="button"], .el-select-dropdown__item, .el-checkbox, label, span')];
  const target = candidates.find((el) => {
    const text = normalize(el.textContent);
    return normalizedTexts.some((needle) => text.includes(needle));
  });
  if (target) {
    target.click();
    return true;
  }
  return false;
}

function fillField(keywords, value, options = {}) {
  const fields = [...document.querySelectorAll('input, textarea')];
  const normalizedKeywords = keywords.map(normalize);
  const target = fields.find((field) => {
    const text = getTextAround(field);
    const maxLength = field.getAttribute('maxlength');
    const type = normalize(field.getAttribute('type'));
    const inputMode = normalize(field.getAttribute('inputmode'));
    if (options.oneTimeCode && field.getAttribute('autocomplete') === 'one-time-code') return true;
    if (options.otp && maxLength === '6' && (type === 'tel' || inputMode === 'numeric' || text.includes('ma') || text.includes('otp'))) return true;
    if (options.phone && maxLength === '10' && (text.includes('sdt') || text.includes('dien thoai') || text.includes('phone'))) return true;
    return normalizedKeywords.some((keyword) => text.includes(keyword));
  });
  if (!target) return false;
  target.focus();
  setNativeValue(target, value);
  return true;
}

function fillSelectLike(keywords, value) {
  if (fillField(keywords, value)) {
    const active = document.activeElement;
    active.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', bubbles: true }));
    setTimeout(() => clickByText([value]), 250);
    return true;
  }
  if (clickByText(keywords)) {
    setTimeout(() => {
      fillField([], value);
      clickByText([value]);
    }, 250);
    return true;
  }
  return clickByText([value]);
}

function detectPage() {
  const text = normalize(document.body.innerText);
  if (text.includes('sdt') && (text.includes('gui ma') || text.includes('xac thuc'))) return 'phone';
  if (text.includes('vai tro') || text.includes('benh vien') || text.includes('phong ban') || text.includes('chuc danh')) return 'fill';
  return 'unknown';
}

async function getState() {
  const data = await chrome.storage.local.get(['phone', 'otp', 'attendees', 'currentIndex']);
  return {
    phone: data.phone || '',
    otp: data.otp || '',
    attendees: data.attendees || [],
    currentIndex: data.currentIndex || 0,
  };
}

async function fillCurrentPage() {
  await ensureLocationReady();
  const state = await getState();
  const page = detectPage();

  if (page === 'phone') {
    const filled = [];
    if (state.phone && fillField(['sdt', 'so dien thoai', 'phone'], state.phone, { phone: true })) {
      filled.push('SĐT');
    }
    if (state.otp && fillField(['ma', 'otp', 'code', 'xac thuc'], state.otp, { otp: true, oneTimeCode: true })) {
      filled.push('OTP');
    }
    return filled.length ? `Đã fill ${filled.join(' + ')} trên trang xác thực.` : 'Trang SĐT / OTP: hãy nhập SĐT hoặc OTP trong popup trước.';
  }

  if (page === 'fill') {
    const person = state.attendees[state.currentIndex];
    if (!person) return 'Chưa có người tham dự để fill.';
    const department = formatDepartment(person.department);
    const role = formatRole(person.role);
    fillSelectLike(['vai tro', 'role'], 'Nguoi tham du');
    fillSelectLike(['benh vien', 'hospital'], 'BENH VIEN DA KHOA TINH QUANG NGAI');
    fillSelectLike(['phong ban', 'khoa', 'department'], department);
    fillSelectLike(['chuc danh', 'title'], role);
    clickByText(['dong y va chap nhan', 'dong y', 'chap nhan']);
    return `Đã fill người ${state.currentIndex + 1}: ${person.name}`;
  }

  return 'Không nhận diện được trang Abbott hiện tại.';
}

chrome.runtime.onMessage.addListener((message, _sender, sendResponse) => {
  (async () => {
    if (message.type === 'ABBOTT_FILL_PAGE') {
      const result = await fillCurrentPage();
      sendResponse({ ok: true, message: result });
      return;
    }
    if (message.type === 'ABBOTT_NEXT_PERSON') {
      const data = await chrome.storage.local.get(['attendees', 'currentIndex']);
      const attendees = data.attendees || [];
      const nextIndex = Math.min((data.currentIndex || 0) + 1, Math.max(attendees.length - 1, 0));
      await chrome.storage.local.set({ currentIndex: nextIndex });
      const result = await fillCurrentPage();
      sendResponse({ ok: true, message: result });
      return;
    }
    sendResponse({ ok: false, message: 'Lệnh không hỗ trợ.' });
  })().catch((error) => {
    sendResponse({ ok: false, message: error.message });
  });
  return true;
});
