const REQUIRED_LOCATION = {
  latitude: 15.1151,
  longitude: 108.7905,
  address: 'Bệnh viện Đa khoa tỉnh Quảng Ngãi, Trần Tế Xương, Trần Phú, Phường Nghĩa Lộ, Tỉnh Quảng Ngãi, Việt Nam',
};

const $ = (id) => document.getElementById(id);

function setStatus(message, ok = false) {
  const el = $('status');
  el.textContent = message;
  el.style.color = ok ? '#7cf7b5' : '#9db4c8';
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function viotpGet(path, params) {
  const url = new URL(`https://api.viotp.com${path}`);
  Object.entries(params).forEach(([key, value]) => url.searchParams.set(key, value));
  const response = await fetch(url.toString());
  if (!response.ok) throw new Error(`ViOTP HTTP ${response.status}`);
  return response.json();
}

function getToken() {
  const token = $('viotpToken').value.trim();
  if (!token) throw new Error('Chưa nhập token ViOTP.');
  return token;
}

function normalizePhone(phone) {
  const digits = String(phone || '').replace(/\D/g, '');
  if (!digits) return '';
  return digits.startsWith('0') ? digits : `0${digits}`;
}

function parseAttendees(text) {
  return String(text || '')
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter(Boolean)
    .map((line) => {
      const parts = line.split('-').map((part) => part.trim());
      if (parts.length < 2) return null;
      return {
        name: parts[0],
        department: parts[1],
        role: parts[2] || '',
      };
    })
    .filter(Boolean);
}

async function saveData() {
  const attendees = parseAttendees($('attendees').value);
  const phone = normalizePhone($('phone').value);
  const otp = String($('otp').value || '').replace(/\D/g, '').slice(0, 6);
  $('phone').value = phone;
  $('otp').value = otp;
  await chrome.storage.local.set({
    eventLink: $('eventLink').value.trim(),
    viotpToken: $('viotpToken').value.trim(),
    phone,
    otp,
    attendeesText: $('attendees').value,
    attendees,
    currentIndex: 0,
    requiredLocation: REQUIRED_LOCATION,
  });
  setStatus(`Đã lưu ${attendees.length} người tham dự.`, true);
}

async function saveConfigOnly() {
  const attendees = parseAttendees($('attendees').value);
  await chrome.storage.local.set({
    eventLink: $('eventLink').value.trim(),
    viotpToken: $('viotpToken').value.trim(),
    attendeesText: $('attendees').value,
    attendees,
    requiredLocation: REQUIRED_LOCATION,
  });
}

async function getActiveTab() {
  const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
  return tab;
}

async function openOrReloadLink() {
  await saveConfigOnly();
  const link = $('eventLink').value.trim();
  if (!link) {
    setStatus('Chưa có link Abbott.');
    return;
  }
  const tab = await getActiveTab();
  if (tab?.id) {
    await chrome.tabs.update(tab.id, { url: link });
  } else {
    await chrome.tabs.create({ url: link });
  }
  setStatus('Đã mở link. Hãy bật GeoSpoof Location Protection rồi reload.', true);
}

async function sendFillCommand(action) {
  await saveData();
  const tab = await getActiveTab();
  if (!tab?.id) return setStatus('Không tìm thấy tab hiện tại.');
  chrome.tabs.sendMessage(tab.id, { type: action }, (response) => {
    if (chrome.runtime.lastError) {
      setStatus('Không gửi được lệnh. Hãy reload trang rồi thử lại.');
      return;
    }
    setStatus(response?.message || 'Đã gửi lệnh.', response?.ok);
  });
}

async function handleQrFile(file) {
  if (!file) return;
  if (!('BarcodeDetector' in window)) {
    setStatus('Trình duyệt chưa hỗ trợ đọc QR. Hãy dán link thủ công.');
    return;
  }
  try {
    const bitmap = await createImageBitmap(file);
    const detector = new BarcodeDetector({ formats: ['qr_code'] });
    const codes = await detector.detect(bitmap);
    const raw = codes?.[0]?.rawValue || '';
    if (!raw) throw new Error('Không đọc được QR');
    $('eventLink').value = raw;
    setStatus('Đã đọc link từ QR.', true);
  } catch (error) {
    setStatus('Không đọc được QR. Hãy thử ảnh rõ hơn hoặc dán link.');
  }
}

async function findAbbottServiceId(token) {
  setStatus('Đang tìm service Abbott trên ViOTP...');
  const result = await viotpGet('/service/getv2', { token, country: 'vn' });
  if (result.status_code !== 200) throw new Error(result.message || 'Không lấy được danh sách service.');
  const service = (result.data || []).find((item) => String(item.name || '').toLowerCase().includes('abbott'));
  if (!service) throw new Error('Không tìm thấy service Abbott trên ViOTP.');
  await chrome.storage.local.set({ serviceId: service.id });
  return service.id;
}

async function checkToken() {
  try {
    await saveConfigOnly();
    const token = getToken();
    setStatus('Đang check token ViOTP...');
    const result = await viotpGet('/service/getv2', { token, country: 'vn' });
    if (result.status_code !== 200 || result.success === false) {
      throw new Error(result.message || `Token lỗi: ${result.status_code}`);
    }
    const services = result.data || [];
    const abbott = services.find((item) => String(item.name || '').toLowerCase().includes('abbott'));
    if (abbott) {
      await chrome.storage.local.set({ serviceId: abbott.id });
      setStatus(`Token OK. Tìm thấy Abbott service ID ${abbott.id}.`, true);
      return;
    }
    setStatus(`Token OK nhưng chưa thấy service Abbott. Tổng service: ${services.length}.`, true);
  } catch (error) {
    setStatus(error.message || 'Token ViOTP không hợp lệ.');
  }
}

async function rentPhone() {
  try {
    await saveConfigOnly();
    const token = getToken();
    const cached = await chrome.storage.local.get(['serviceId']);
    const serviceId = cached.serviceId || await findAbbottServiceId(token);
    setStatus('Đang thuê số ViOTP...');
    const result = await viotpGet('/request/getv2', { token, serviceId });
    if (result.status_code !== 200) throw new Error(result.message || 'Thuê số thất bại.');
    const phone = normalizePhone(result.data?.phone_number || result.data?.re_phone_number || '');
    const requestId = result.data?.request_id;
    if (!phone || !requestId) throw new Error('API không trả về số hoặc request_id.');
    $('phone').value = phone;
    await chrome.storage.local.set({ phone, requestId, otp: '' });
    $('otp').value = '';
    await navigator.clipboard?.writeText(phone).catch(() => {});
    setStatus(`Đã lấy số ${phone}. Đã copy số.`, true);
  } catch (error) {
    setStatus(error.message);
  }
}

async function getOtp() {
  try {
    await saveConfigOnly();
    const token = getToken();
    const stored = await chrome.storage.local.get(['requestId']);
    if (!stored.requestId) throw new Error('Chưa có request_id. Hãy bấm Lấy số ViOTP trước.');
    setStatus('Đang chờ OTP tối đa 60 giây...');
    for (let second = 0; second < 60; second += 1) {
      const result = await viotpGet('/session/getv2', { requestId: stored.requestId, token });
      if (result.status_code === 200) {
        const status = Number(result.data?.Status ?? 0);
        const code = String(result.data?.Code || '').replace(/\D/g, '').slice(0, 6);
        if (status === 1 && code) {
          $('otp').value = code;
          await chrome.storage.local.set({ otp: code });
          await navigator.clipboard?.writeText(code).catch(() => {});
          setStatus(`Đã lấy OTP ${code}. Đã copy OTP.`, true);
          return;
        }
        if (status === 2) throw new Error('Phiên OTP đã hết hạn.');
      } else if (result.message) {
        setStatus(`Đang chờ OTP... ${second + 1}s (${result.message})`);
      } else {
        setStatus(`Đang chờ OTP... ${second + 1}s`);
      }
      await sleep(1000);
    }
    throw new Error('Quá 60 giây chưa có OTP.');
  } catch (error) {
    setStatus(error.message);
  }
}

async function restoreData() {
  const data = await chrome.storage.local.get(['eventLink', 'viotpToken', 'phone', 'otp', 'attendeesText']);
  $('eventLink').value = data.eventLink || '';
  $('viotpToken').value = data.viotpToken || '';
  $('phone').value = data.phone || '';
  $('otp').value = data.otp || '';
  $('attendees').value = data.attendeesText || '';
}

$('saveData').addEventListener('click', saveData);
$('checkToken').addEventListener('click', checkToken);
$('rentPhone').addEventListener('click', rentPhone);
$('getOtp').addEventListener('click', getOtp);
$('openLink').addEventListener('click', openOrReloadLink);
$('fillPage').addEventListener('click', () => sendFillCommand('ABBOTT_FILL_PAGE'));
$('nextPerson').addEventListener('click', () => sendFillCommand('ABBOTT_NEXT_PERSON'));

const dropZone = $('dropZone');
const qrFile = $('qrFile');
dropZone.addEventListener('click', () => qrFile.click());
qrFile.addEventListener('change', () => handleQrFile(qrFile.files?.[0]));
dropZone.addEventListener('dragover', (event) => {
  event.preventDefault();
  dropZone.classList.add('drag-over');
});
dropZone.addEventListener('dragleave', () => dropZone.classList.remove('drag-over'));
dropZone.addEventListener('drop', (event) => {
  event.preventDefault();
  dropZone.classList.remove('drag-over');
  handleQrFile(event.dataTransfer?.files?.[0]);
});

restoreData();
