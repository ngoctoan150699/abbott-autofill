import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:webview_flutter/webview_flutter.dart';

import 'app_preferences.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Abbott Event Helper',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF5EEAD4),
          brightness: Brightness.dark,
          primary: const Color(0xFF5EEAD4),
          secondary: const Color(0xFFF0ABFC),
          surface: const Color(0xFF101827),
        ),
        scaffoldBackgroundColor: const Color(0xFF07111F),
        fontFamily: 'Roboto',
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white.withOpacity(0.08),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: Colors.white.withOpacity(0.12)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: Colors.white.withOpacity(0.12)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Color(0xFF5EEAD4), width: 1.4),
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        ),
      ),
      home: const MainScreen(),
    );
  }
}

const List<String> kDefaultHospitals = [
  'BENH VIEN DA KHOA TINH QUANG NGAI',
  'BENH VIEN SAN NHI TINH QUANG NGAI',
  'BENH VIEN DA KHOA PHUC HUNG',
  'BENH VIEN NOI TIET TINH QUANG NGAI',
];

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  final TextEditingController _urlController = TextEditingController();
  final TextEditingController _tokenController =
      TextEditingController(text: 'de6faac93d8d4f3294070fe48a11224b');

  late final WebViewController _webViewController;

  bool _isLoadingService = false;
  bool _isGettingPhone = false;
  bool _isGettingOtp = false;

  Timer? _otpTimer;
  int _otpTimeoutSeconds = 60;

  int? _abbottServiceId;
  String _currentPhoneNumber = '';
  String _currentRequestId = '';
  String _currentOtp = '';
  String _otpStatusText = '';

  List<String> _hospitals = List.from(kDefaultHospitals);
  String _selectedHospital = kDefaultHospitals.first;

  List<Map<String, String>> _people = [];
  int _currentPersonIndex = 0;
  Map<String, bool> _fillEnabled = {
    'name': true,
    'attendeeRole': true,
    'hospital': true,
    'department': true,
    'role': true,
    'agreement': true,
  };
  Map<String, int> _fillDelayMs = {
    'name': 700,
    'attendeeRole': 700,
    'hospital': 1800,
    'department': 700,
    'role': 700,
    'agreement': 700,
  };

  @override
  void initState() {
    super.initState();
    _webViewController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (String url) {
            _webViewController.runJavaScript('''
              navigator.geolocation.getCurrentPosition = function(success, error, options) {
                  success({
                      coords: { latitude: 15.114757, longitude: 108.791015, accuracy: 10 },
                      timestamp: Date.now()
                  });
              };
              navigator.geolocation.watchPosition = function(success, error, options) {
                  navigator.geolocation.getCurrentPosition(success, error, options);
                  return 1;
              };
            ''');
          },
          onPageFinished: (String url) {},
        ),
      );
    _loadPreferences();
  }

  @override
  void dispose() {
    _cancelOtpTimer();
    _urlController.dispose();
    _tokenController.dispose();
    super.dispose();
  }

  void _cancelOtpTimer() {
    _otpTimer?.cancel();
    _otpTimer = null;
  }

  void _cancelOtpWaiting() {
    _cancelOtpTimer();
    if (mounted) {
      setState(() {
        _isGettingOtp = false;
        _otpStatusText = 'Đã dừng chờ';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Đã dừng chờ OTP.')),
      );
    }
  }

  Future<void> _loadPreferences() async {
    final token = await AppPreferences.getString('viotp_token');
    final lastUrl = await AppPreferences.getString('last_url');
    final peopleData = await AppPreferences.getString('people_data');
    final fillSettings = await AppPreferences.getString('fill_settings');
    final hospitalsData = await AppPreferences.getString('hospital_list');
    final defaultHospital = await AppPreferences.getString('default_hospital');
    final otpTimeoutStr = await AppPreferences.getString('otp_timeout_seconds');

    setState(() {
      _tokenController.text = token ?? 'de6faac93d8d4f3294070fe48a11224b';
      _urlController.text = lastUrl ?? '';

      if (otpTimeoutStr != null && otpTimeoutStr.isNotEmpty) {
        _otpTimeoutSeconds = int.tryParse(otpTimeoutStr) ?? 60;
      }

      if (hospitalsData != null && hospitalsData.isNotEmpty) {
        try {
          final List<dynamic> decodedHosp = jsonDecode(hospitalsData);
          _hospitals = decodedHosp
              .map((e) => e.toString().trim())
              .where((e) => e.isNotEmpty)
              .toList();
          for (final h in kDefaultHospitals) {
            if (!_hospitals.contains(h)) {
              _hospitals.add(h);
            }
          }
        } catch (_) {
          _hospitals = List.from(kDefaultHospitals);
        }
      } else {
        _hospitals = List.from(kDefaultHospitals);
      }

      if (defaultHospital != null && defaultHospital.isNotEmpty) {
        _selectedHospital = defaultHospital;
        if (!_hospitals.contains(_selectedHospital)) {
          _hospitals.insert(0, _selectedHospital);
        }
      } else {
        _selectedHospital =
            _hospitals.isNotEmpty ? _hospitals.first : kDefaultHospitals.first;
      }

      if (peopleData != null && peopleData.isNotEmpty) {
        try {
          final List<dynamic> decoded = jsonDecode(peopleData);
          _people = decoded.map((e) {
            final m = Map<String, String>.from(e);
            if (m['hospital'] == null || m['hospital']!.isEmpty) {
              m['hospital'] = _selectedHospital;
            }
            return m;
          }).toList();
        } catch (_) {
          _people = [];
        }
      } else {
        _people = [];
      }
      if (fillSettings != null && fillSettings.isNotEmpty) {
        try {
          final decoded = Map<String, dynamic>.from(jsonDecode(fillSettings));
          _fillEnabled.addAll(
              Map<String, dynamic>.from(decoded['enabled'] ?? {})
                  .map((key, value) => MapEntry(key, value == true)));
          _fillDelayMs.addAll(Map<String, dynamic>.from(decoded['delays'] ?? {})
              .map((key, value) => MapEntry(
                  key, (value as num).toInt().clamp(0, 10000).toInt())));
        } catch (_) {}
      }
    });
    if (_urlController.text.isNotEmpty) {
      _loadUrl();
    }
  }

  Future<void> _savePreferences() async {
    await AppPreferences.setString('viotp_token', _tokenController.text);
    await AppPreferences.setString('last_url', _urlController.text);
    await AppPreferences.setString('hospital_list', jsonEncode(_hospitals));
    await AppPreferences.setString('default_hospital', _selectedHospital);
    await AppPreferences.setString(
        'otp_timeout_seconds', _otpTimeoutSeconds.toString());
    final peopleJson = jsonEncode(_people);
    await AppPreferences.setString('people_data', peopleJson);
    await AppPreferences.setString(
        'fill_settings',
        jsonEncode({
          'enabled': _fillEnabled,
          'delays': _fillDelayMs,
        }));
  }

  void _loadUrl() {
    final url = _urlController.text.trim();
    if (url.isNotEmpty) {
      Uri uri = Uri.parse(url);
      if (!uri.hasScheme) {
        uri = Uri.parse('https://$url');
      }
      _webViewController.loadRequest(uri);
      _savePreferences();
    }
  }

  Future<void> _fetchServiceId() async {
    setState(() {
      _isLoadingService = true;
    });
    try {
      final token = _tokenController.text.trim();
      final url = Uri.parse(
          'https://api.viotp.com/service/getv2?token=$token&country=vn');
      final response = await http.get(url);
      final json = jsonDecode(response.body);

      if (json['status_code'] == 200) {
        final data = json['data'];
        if (data is! List) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Dữ liệu dịch vụ ViOTP không hợp lệ!')),
          );
          return;
        }

        Map? service;
        for (final item in data) {
          if (item is Map &&
              (item['name'] ?? '')
                  .toString()
                  .toLowerCase()
                  .contains('abbott')) {
            service = item;
            break;
          }
        }

        final serviceId = int.tryParse((service?['id'] ?? '').toString());
        if (serviceId != null) {
          _abbottServiceId = serviceId;
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content:
                  Text('Tìm thấy dịch vụ Abbott (ID: $_abbottServiceId)')));
        } else {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Không tìm thấy dịch vụ Abbott trên ViOTP!')));
        }
      } else {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text("Lỗi: ${json['message']}")));
      }
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Lỗi kết nối: $e')));
    } finally {
      setState(() {
        _isLoadingService = false;
      });
    }
  }

  Future<void> _getPhoneNumber() async {
    if (_abbottServiceId == null) {
      await _fetchServiceId();
      if (_abbottServiceId == null) return;
    }

    _cancelOtpTimer();

    setState(() {
      _isGettingPhone = true;
      _currentPhoneNumber = '';
      _currentRequestId = '';
      _currentOtp = '';
      _isGettingOtp = false;
      _otpStatusText = '';
    });

    try {
      final token = _tokenController.text.trim();
      final url = Uri.parse(
          'https://api.viotp.com/request/getv2?token=$token&serviceId=$_abbottServiceId');
      final response = await http.get(url);
      final json = jsonDecode(response.body);

      if (json['status_code'] == 200) {
        String phone = json['data']['phone_number'];
        if (!phone.startsWith('0')) {
          phone = '0$phone';
        }
        setState(() {
          _currentPhoneNumber = phone;
          _currentRequestId = json['data']['request_id'].toString();
        });
        Clipboard.setData(ClipboardData(text: _currentPhoneNumber));
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Đã lấy và copy số điện thoại!')));
      } else {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text("Lỗi: ${json['message']}")));
      }
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Lỗi kết nối: $e')));
    } finally {
      setState(() {
        _isGettingPhone = false;
      });
    }
  }

  Future<void> _getOtp() async {
    if (_currentRequestId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Chưa có số điện thoại nào đang thuê!')));
      return;
    }

    _cancelOtpTimer();

    final expireAt =
        DateTime.now().add(Duration(seconds: _otpTimeoutSeconds));

    setState(() {
      _isGettingOtp = true;
      _currentOtp = '';
      _otpStatusText = 'Đang chờ OTP... ${_otpTimeoutSeconds}s';
    });

    // 1. Timer chạy trên UI isolate: đếm đúng từng giây theo DateTime thật
    _otpTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      final remaining = expireAt.difference(DateTime.now()).inSeconds;
      if (remaining <= 0) {
        timer.cancel();
        if (_isGettingOtp) {
          setState(() {
            _isGettingOtp = false;
            _otpStatusText = 'Hết thời gian chờ OTP';
          });
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(
                  'Không lấy được mã OTP sau $_otpTimeoutSeconds giây.')));
        }
      } else {
        setState(() {
          _otpStatusText = 'Đang chờ OTP... còn ${remaining}s';
        });
      }
    });

    // 2. Polling ViOTP chạy song song, không làm chậm hay sai lệch bộ đếm giây
    try {
      final token = _tokenController.text.trim();
      while (_isGettingOtp && DateTime.now().isBefore(expireAt)) {
        if (!mounted) break;

        final url = Uri.parse(
            'https://api.viotp.com/session/getv2?requestId=$_currentRequestId&token=$token');

        try {
          final response =
              await http.get(url).timeout(const Duration(seconds: 4));
          if (!mounted || !_isGettingOtp) break;

          final json = jsonDecode(response.body);

          if (json['status_code'] == 200) {
            final status = json['data']['Status'];
            if (status == 1) {
              final otp = json['data']['Code'].toString();
              _cancelOtpTimer();
              if (mounted) {
                setState(() {
                  _isGettingOtp = false;
                  _currentOtp = otp;
                  _otpStatusText = 'Đã có OTP';
                });
                Clipboard.setData(ClipboardData(text: otp));
                await _fillOtpInWeb();
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('Đã nhận, copy và điền OTP!')));
              }
              return;
            }
            if (status != 0) {
              _cancelOtpTimer();
              if (mounted) {
                setState(() {
                  _isGettingOtp = false;
                  _otpStatusText = 'Phiên hết hạn/lỗi';
                });
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('Phiên ViOTP đã hết hạn hoặc lỗi!')));
              }
              return;
            }
          } else {
            _cancelOtpTimer();
            if (mounted) {
              setState(() {
                _isGettingOtp = false;
                _otpStatusText = 'Lỗi API';
              });
              ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text("Lỗi: ${json['message']}")));
            }
            return;
          }
        } catch (e) {
          // Bỏ qua lỗi timeout kết nối đơn lẻ trong lúc polling
          debugPrint('Lỗi tạm thời khi poll OTP: $e');
        }

        // Chờ 1.5 giây giữa mỗi lần check ViOTP
        await Future.delayed(const Duration(milliseconds: 1500));
      }
    } catch (e) {
      _cancelOtpTimer();
      if (mounted) {
        setState(() {
          _isGettingOtp = false;
          _otpStatusText = 'Lỗi kết nối';
        });
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Lỗi kết nối: $e')));
      }
    } finally {
      if (mounted && _isGettingOtp && DateTime.now().isAfter(expireAt)) {
        _cancelOtpTimer();
        setState(() {
          _isGettingOtp = false;
          _otpStatusText = 'Không lấy được OTP sau ${_otpTimeoutSeconds}s';
        });
      }
    }
  }

  Future<void> _fillWebFields(Map<String, String> data) async {
    final payload = jsonEncode(data);
    await _webViewController.runJavaScript('''
      (function() {
        const data = $payload;
        const norm = (s) => (s || '').toString().toLowerCase()
          .normalize('NFD').replace(/[\\u0300-\\u036f]/g, '')
          .replace(/đ/g, 'd').replace(/\\s+/g, ' ').trim();
        const inputs = Array.from(document.querySelectorAll('input, textarea'));
        function labelOf(el) {
          let txt = (el.placeholder || '') + ' ' + (el.name || '') + ' ' + (el.id || '');
          if (el.id) {
            const label = document.querySelector('label[for="' + el.id + '"]');
            if (label) txt += ' ' + (label.innerText || '');
          }
          const field = el.closest('.el-form-item, .form-group, [class*="form-item"], [class*="input-group"]');
          if (field) {
            const label = field.querySelector('label, .el-form-item__label');
            if (label) txt += ' ' + (label.innerText || '');
          }
          return norm(txt);
        }
        function setVal(el, val) {
          if (!el || val == null || val === '') return false;
          const proto = el instanceof HTMLTextAreaElement
            ? window.HTMLTextAreaElement.prototype
            : window.HTMLInputElement.prototype;
          Object.getOwnPropertyDescriptor(proto, 'value').set.call(el, val);
          el.dispatchEvent(new Event('input', {bubbles: true}));
          el.dispatchEvent(new Event('change', {bubbles: true}));
          el.blur();
          return true;
        }
        function fillBy(keys, val, fallbackSelector, excludedKeys) {
          let el = inputs.find(i => {
            const label = labelOf(i);
            return keys.some(k => label.includes(k)) &&
              !(excludedKeys || []).some(k => label.includes(k));
          });
          if (!el && fallbackSelector) el = document.querySelector(fallbackSelector);
          return setVal(el, val);
        }
        fillBy(
          ['sdt', 'so dien thoai', 'dien thoai', 'phone', 'so dt', 'di dong', 'mobile'],
          data.phone,
          'input[type="tel"], input[name*="phone" i], input[name*="sdt" i]',
          ['ma', 'otp', 'code', 'xac thuc']
        );
        fillBy(
          ['ma otp', 'otp', 'verification code', 'ma xac thuc', 'code'],
          data.otp,
          'input[name*="otp" i], input[name*="code" i], input[autocomplete="one-time-code"]'
        );
        fillBy(['ho va ten', 'ho ten', 'name'], data.name);
        fillBy(['benh vien', 'hospital'], data.hospital);
        fillBy(['phong ban', 'khoa', 'department'], data.department);
        fillBy(['chuc danh', 'title'], data.role);
        fillBy(['vai tro', 'role'], data.attendeeRole);
      })();
    ''');
  }

  Future<void> _fillPhoneInWeb() async {
    await _fillWebFields({'phone': _currentPhoneNumber});
    await Future.delayed(const Duration(milliseconds: 500));
    final clicked = await _webViewController.runJavaScriptReturningResult('''
      (function() {
        const norm = (s) => (s || '').toString().toLowerCase()
          .normalize('NFD').replace(/[\\u0300-\\u036f]/g, '')
          .replace(/đ/g, 'd').replace(/\\s+/g, ' ').trim();
        const buttons = Array.from(document.querySelectorAll('button, a, input[type="button"]'));
        const btn = buttons.find(b => {
          const txt = norm(b.innerText || b.value || '');
          return txt.includes('gui ma') || txt.includes('lay ma') ||
            txt.includes('nhan ma') || txt.includes('send code');
        });
        if (!btn || btn.disabled) return false;
        btn.click();
        return true;
      })();
    ''');

    if (!mounted) return;
    if (clicked != true) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Đã điền SĐT nhưng chưa tìm thấy nút Gửi mã!')));
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Đã điền SĐT, bấm Gửi mã và tự động chờ OTP!')));
    if (!_isGettingOtp) await _getOtp();
  }

  Future<void> _fillOtpInWeb() async {
    await _fillWebFields({'otp': _currentOtp});
  }

  Future<void> _fillCurrentPersonInWeb() async {
    if (_people.isEmpty) return;
    final p = _people[_currentPersonIndex];
    final hospitalToFill =
        (p['hospital'] != null && p['hospital']!.trim().isNotEmpty)
            ? p['hospital']!.trim()
            : _selectedHospital;

    final payload = jsonEncode({
      'person': {
        'name': p['name'] ?? '',
        'department': p['department'] ?? '',
        'role': p['role'] ?? '',
        'attendeeRole': 'Nguoi tham du',
        'hospital': hospitalToFill,
      },
      'enabled': _fillEnabled,
      'delays': _fillDelayMs,
    });

    await _webViewController.runJavaScript('''
      (async function() {
        const settings = $payload;
        const data = settings.person;
        const enabled = settings.enabled;
        const delays = settings.delays;
        const stepDelay = key => Math.max(0, Math.min(10000, Number(delays[key]) || 0));
        const norm = (s) => (s || '').toString().toLowerCase()
          .normalize('NFD').replace(/[\\u0300-\\u036f]/g, '')
          .replace(/đ/g, 'd').replace(/\\s+/g, ' ').trim();
        const inputs = Array.from(document.querySelectorAll('input, textarea'));
        
        function labelOf(el) {
          let txt = '';
          if (el.id) {
            const label = document.querySelector('label[for="' + el.id + '"]');
            if (label) txt += ' ' + label.innerText;
          }
          let pNode = el;
          for (let i = 0; i < 4 && pNode; i++, pNode = pNode.parentElement) {
            txt += ' ' + (pNode.innerText || '');
          }
          txt += ' ' + (el.placeholder || '') + ' ' + (el.name || '') + ' ' + (el.id || '');
          return norm(txt);
        }
        
        function setVal(el, val) {
          if (!el || val == null || val === '') return false;
          el.value = val;
          el.dispatchEvent(new Event('input', {bubbles: true}));
          el.dispatchEvent(new Event('change', {bubbles: true}));
          return true;
        }

        const delay = ms => new Promise(r => setTimeout(r, ms));

        // 1. Fill Name
        if (enabled.name) {
          const nameInput = inputs.find(i => ['ho va ten', 'ho ten', 'name'].some(k => labelOf(i).includes(k)));
          if (nameInput) {
            setVal(nameInput, data.name);
            await delay(stepDelay('name'));
          }
        }

        // Helper to fill Element UI dropdown. fallbackIndex follows the form order:
        // Vai trò, Bệnh viện, Phòng ban/Khoa, Chức danh.
        async function fillDropdown(keywords, targetVal, fallbackIndex, waitMs) {
          if (!targetVal) return false;

          const selectInputs = Array.from(
            document.querySelectorAll('.el-select input, input[role="combobox"]')
          ).filter((el, index, all) => all.indexOf(el) === index);
          function dropdownLabel(el) {
            const field = el.closest('.el-form-item, .form-group, [class*="form-item"]');
            let txt = field ? field.innerText : '';
            if (field) {
              const label = field.querySelector('label, .el-form-item__label');
              if (label) txt += ' ' + label.innerText;
            }
            txt += ' ' + (el.placeholder || '') + ' ' + (el.name || '') + ' ' + (el.id || '');
            return norm(txt);
          }
          const input = selectInputs.find(el =>
            keywords.some(k => dropdownLabel(el).includes(k))
          ) || selectInputs[fallbackIndex];
          if (!input) return false;

          const wasReadOnly = input.readOnly;
          input.readOnly = true;
          input.scrollIntoView({block: 'center'});
          input.click();
          await delay(waitMs);

          let options = Array.from(document.querySelectorAll(
            '.el-select-dropdown__item, [role="option"]'
          )).filter(o => o.offsetParent !== null && !o.classList.contains('is-disabled'));
          const target = norm(targetVal);
          let bestOption = options.find(o => norm(o.innerText) === target) ||
            options.find(o => norm(o.innerText).includes(target) || target.includes(norm(o.innerText)));

          if (!bestOption) {
            const setter = Object.getOwnPropertyDescriptor(
              window.HTMLInputElement.prototype, 'value'
            ).set;
            setter.call(input, targetVal);
            input.dispatchEvent(new Event('input', {bubbles: true}));
            await delay(Math.max(1200, waitMs));
            options = Array.from(document.querySelectorAll(
              '.el-select-dropdown__item, [role="option"]'
            )).filter(o => o.offsetParent !== null && !o.classList.contains('is-disabled'));
            bestOption = options.find(o => norm(o.innerText) === target) ||
              options.find(o => norm(o.innerText).includes(target) || target.includes(norm(o.innerText)));
          }

          if (!bestOption) {
            input.dispatchEvent(new KeyboardEvent('keydown', {key: 'Escape', bubbles: true}));
            input.blur();
            input.readOnly = wasReadOnly;
            return false;
          }
          bestOption.click();
          await delay(waitMs);
          input.blur();
          input.readOnly = wasReadOnly;
          return true;
        }

        if (enabled.attendeeRole) {
          await fillDropdown(['vai tro', 'role'], data.attendeeRole, 0, stepDelay('attendeeRole'));
        }
        if (enabled.hospital) {
          await fillDropdown(['benh vien', 'hospital'], data.hospital, 1, stepDelay('hospital'));
        }
        if (enabled.department) {
          await fillDropdown(['phong ban', 'khoa', 'department'], data.department, 2, stepDelay('department'));
        }
        if (enabled.role) {
          await fillDropdown(['chuc danh', 'title'], data.role, 3, stepDelay('role'));
        }

        // Tick checkbox "Đồng ý"
        if (enabled.agreement) {
          const checkboxes = Array.from(document.querySelectorAll('input[type="checkbox"]'));
          const agreeCheckbox = checkboxes.find(c => {
             let pNode = c.parentElement;
             let txt = '';
             for(let i=0; i<3 && pNode; i++, pNode = pNode.parentElement) {
                txt += ' ' + (pNode.innerText || '');
             }
             return norm(txt).includes('dong y') || norm(txt).includes('chap nhan');
          });
          if (agreeCheckbox && !agreeCheckbox.checked) {
             agreeCheckbox.click();
             await delay(stepDelay('agreement'));
          }
        }

      })();
    ''');

    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content:
            Text('Đang điền thông tin tuần tự. Vui lòng đợi và kiểm tra...')));
  }

  Future<void> _submitFormInWeb() async {
    await _webViewController.runJavaScript('''
      (function() {
        const norm = (s) => (s || '').toString().toLowerCase()
          .normalize('NFD').replace(/[\\u0300-\\u036f]/g, '')
          .replace(/đ/g, 'd').replace(/\\s+/g, ' ').trim();
        const buttons = Array.from(document.querySelectorAll('button, input[type="submit"], input[type="button"], a'));
        
        const submitKeywords = ['gui', 'xac nhan', 'submit', 'dang ky', 'gui dang ky', 'hoan tat', 'gui ma'];
        
        let foundBtn = null;
        for (const btn of buttons) {
          const txt = norm(btn.innerText || btn.value || '');
          if (submitKeywords.some(k => txt === k || (txt.length < 25 && txt.includes(k)))) {
            foundBtn = btn;
            break;
          }
        }
        
        if (foundBtn) {
          foundBtn.focus();
          foundBtn.click();
          return;
        }

        const form = document.querySelector('form');
        if (form) {
          form.submit();
        }
      })();
    ''');
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Đã kích hoạt hành động gửi form trên web!')));
  }

  void _copy(String text, String label) {
    if (text.isEmpty) return;
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('Đã copy $label!')));
  }

  void _applyHospitalToAll([String? hospital]) {
    final target = hospital ?? _selectedHospital;
    if (_people.isEmpty) return;
    setState(() {
      _selectedHospital = target;
      for (var p in _people) {
        p['hospital'] = target;
      }
    });
    _savePreferences();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Đã gán "$target" cho tất cả ${_people.length} người!'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        toolbarHeight: 44,
        elevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: const Text(
          'Abbott Helper',
          style: TextStyle(
              fontWeight: FontWeight.w800, letterSpacing: .2, fontSize: 16),
        ),
        actions: [
          IconButton.filledTonal(
            tooltip: 'Cài đặt',
            iconSize: 18,
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.tune_rounded),
            onPressed: () => _showSettingsDialog(),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF07111F), Color(0xFF102033), Color(0xFF08111E)],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 2, 10, 4),
                child: Container(
                  height: 38,
                  padding: const EdgeInsets.fromLTRB(10, 2, 4, 2),
                  decoration: _glassDecoration(radius: 14),
                  child: Row(
                    children: [
                      const Icon(Icons.link_rounded,
                          size: 16, color: Color(0xFF5EEAD4)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _urlController,
                          style: const TextStyle(fontSize: 12),
                          decoration: const InputDecoration(
                            isDense: true,
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            fillColor: Colors.transparent,
                            filled: false,
                            hintText: 'Dán link Abbott...',
                            hintStyle:
                                TextStyle(fontSize: 12, color: Colors.white38),
                            contentPadding: EdgeInsets.zero,
                          ),
                          onSubmitted: (_) => _loadUrl(),
                        ),
                      ),
                      FilledButton(
                        onPressed: _loadUrl,
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(46, 30),
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                        child: const Text('Mở',
                            style: TextStyle(
                                fontSize: 12, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: ColoredBox(
                      color: Colors.white,
                      child: WebViewWidget(controller: _webViewController),
                    ),
                  ),
                ),
              ),
              _buildControlPanel(),
            ],
          ),
        ),
      ),
    );
  }

  BoxDecoration _glassDecoration({double radius = 24}) {
    return BoxDecoration(
      color: Colors.white.withOpacity(0.08),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: Colors.white.withOpacity(0.12)),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.28),
          blurRadius: 24,
          offset: const Offset(0, 12),
        ),
      ],
    );
  }

  Widget _valuePill(
      String value, String hint, IconData icon, VoidCallback? onCopy) {
    return InkWell(
      onTap: onCopy,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        height: 29,
        padding: const EdgeInsets.symmetric(horizontal: 7),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.22),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white.withOpacity(0.10)),
        ),
        child: Row(
          children: [
            Icon(icon, color: Colors.white70, size: 14),
            const SizedBox(width: 5),
            Expanded(
              child: Text(
                value.isEmpty ? hint : value,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: value.isEmpty ? Colors.white38 : Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 11,
                  letterSpacing: .3,
                ),
              ),
            ),
            if (value.isNotEmpty)
              const Icon(Icons.copy_rounded, size: 12, color: Colors.white38),
          ],
        ),
      ),
    );
  }

  Widget _miniChip(IconData icon, String text, Color color) {
    return Expanded(
      child: Container(
        height: 20,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          children: [
            Icon(icon, size: 10, color: color),
            const SizedBox(width: 3),
            Expanded(
              child: Text(
                text,
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  color: Colors.white.withOpacity(0.85),
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _loadingIcon(bool loading, IconData icon) {
    if (!loading) return Icon(icon, size: 15);
    return const SizedBox(
      width: 14,
      height: 14,
      child: CircularProgressIndicator(strokeWidth: 2),
    );
  }

  Widget _buildControlPanel() {
    final hasPerson = _people.isNotEmpty;
    final current = hasPerson ? _people[_currentPersonIndex] : null;

    return Container(
      margin: const EdgeInsets.fromLTRB(10, 4, 10, 6),
      constraints: const BoxConstraints(maxHeight: 185),
      padding: const EdgeInsets.all(7),
      decoration: _glassDecoration(radius: 18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. Hàng SĐT (Bấm vào SĐT là copy ngay)
          Row(
            children: [
              FilledButton(
                onPressed: (_isGettingPhone || _isLoadingService)
                    ? null
                    : _getPhoneNumber,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(58, 29),
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _loadingIcon(_isGettingPhone || _isLoadingService,
                        Icons.phone_android_rounded),
                    const SizedBox(width: 3),
                    const Text('Số',
                        style: TextStyle(
                            fontSize: 11, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
              const SizedBox(width: 5),
              Expanded(
                child: _valuePill(
                  _currentPhoneNumber,
                  'Số điện thoại...',
                  Icons.call_rounded,
                  _currentPhoneNumber.isEmpty
                      ? null
                      : () => _copy(_currentPhoneNumber, 'Số điện thoại'),
                ),
              ),
              const SizedBox(width: 5),
              IconButton.filledTonal(
                tooltip: 'Điền SĐT vào Web',
                visualDensity: VisualDensity.compact,
                iconSize: 15,
                padding: EdgeInsets.zero,
                constraints:
                    const BoxConstraints(minWidth: 32, minHeight: 29),
                style: IconButton.styleFrom(
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                icon: const Icon(Icons.content_paste_go_rounded),
                onPressed:
                    _currentPhoneNumber.isEmpty ? null : _fillPhoneInWeb,
              ),
            ],
          ),
          const SizedBox(height: 4),
          // 2. Hàng OTP (Bấm vào OTP là copy ngay)
          Row(
            children: [
              FilledButton(
                onPressed: _isGettingOtp ? _cancelOtpWaiting : _getOtp,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(58, 29),
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  backgroundColor:
                      _isGettingOtp ? Colors.orange.shade800 : null,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _loadingIcon(_isGettingOtp, Icons.mark_email_read_rounded),
                    const SizedBox(width: 3),
                    Text(_isGettingOtp ? 'Dừng' : 'OTP',
                        style: const TextStyle(
                            fontSize: 11, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
              const SizedBox(width: 5),
              Expanded(
                child: _valuePill(
                  _currentOtp,
                  _otpStatusText.isNotEmpty ? _otpStatusText : 'Mã OTP...',
                  Icons.password_rounded,
                  _currentOtp.isEmpty ? null : () => _copy(_currentOtp, 'OTP'),
                ),
              ),
              const SizedBox(width: 5),
              IconButton.filledTonal(
                tooltip: 'Điền OTP vào Web',
                visualDensity: VisualDensity.compact,
                iconSize: 15,
                padding: EdgeInsets.zero,
                constraints:
                    const BoxConstraints(minWidth: 32, minHeight: 29),
                style: IconButton.styleFrom(
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                icon: const Icon(Icons.content_paste_go_rounded),
                onPressed: _currentOtp.isEmpty ? null : _fillOtpInWeb,
              ),
            ],
          ),
          const SizedBox(height: 4),
          // 3. Hàng Bệnh viện & Nút Gửi Form Web (Tích hợp cùng 1 dòng siêu gọn)
          Row(
            children: [
              Expanded(
                flex: 11,
                child: Container(
                  height: 29,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white.withOpacity(0.1)),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _hospitals.contains(_selectedHospital)
                          ? _selectedHospital
                          : (_hospitals.isNotEmpty ? _hospitals.first : null),
                      isExpanded: true,
                      icon: const Icon(Icons.arrow_drop_down,
                          size: 16, color: Color(0xFF5EEAD4)),
                      dropdownColor: const Color(0xFF101827),
                      style: const TextStyle(
                          fontSize: 11,
                          color: Colors.white,
                          fontWeight: FontWeight.w600),
                      items: _hospitals
                          .map((h) => DropdownMenuItem(
                                value: h,
                                child: Text(h, overflow: TextOverflow.ellipsis),
                              ))
                          .toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setState(() => _selectedHospital = val);
                          _savePreferences();
                        }
                      },
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              IconButton.filledTonal(
                tooltip: 'Gán BV này cho TẤT CẢ người trong DS',
                visualDensity: VisualDensity.compact,
                iconSize: 15,
                padding: EdgeInsets.zero,
                constraints:
                    const BoxConstraints(minWidth: 30, minHeight: 29),
                style: IconButton.styleFrom(
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                icon: const Icon(Icons.done_all_rounded,
                    color: Color(0xFF5EEAD4)),
                onPressed:
                    _people.isEmpty ? null : () => _applyHospitalToAll(),
              ),
              const SizedBox(width: 4),
              Expanded(
                flex: 8,
                child: SizedBox(
                  height: 29,
                  child: FilledButton.icon(
                    onPressed: _submitFormInWeb,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFF0ABFC),
                      foregroundColor: const Color(0xFF1E0824),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                      padding: EdgeInsets.zero,
                    ),
                    icon: const Icon(Icons.send_rounded, size: 12),
                    label: const Text(
                      'Gửi Form',
                      style:
                          TextStyle(fontWeight: FontWeight.w900, fontSize: 11),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          // 4. Thẻ người hiện tại (2 dòng cực kỳ gọn gàng)
          if (hasPerson)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFF5EEAD4).withOpacity(0.14),
                    const Color(0xFFF0ABFC).withOpacity(0.08),
                  ],
                ),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white.withOpacity(0.10)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 9,
                        backgroundColor: const Color(0xFF5EEAD4),
                        foregroundColor: const Color(0xFF06211D),
                        child: Text(
                          '${_currentPersonIndex + 1}',
                          style: const TextStyle(
                              fontWeight: FontWeight.w900, fontSize: 9),
                        ),
                      ),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          current?['name'] ?? '',
                          style: const TextStyle(
                              fontWeight: FontWeight.w900, fontSize: 12),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 4),
                      IconButton.filledTonal(
                        tooltip: 'Điền người này vào Web',
                        visualDensity: VisualDensity.compact,
                        iconSize: 15,
                        padding: EdgeInsets.zero,
                        constraints:
                            const BoxConstraints(minWidth: 28, minHeight: 26),
                        style: IconButton.styleFrom(
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(6)),
                        ),
                        icon: const Icon(Icons.auto_fix_high_rounded),
                        onPressed: _fillCurrentPersonInWeb,
                      ),
                      const SizedBox(width: 4),
                      IconButton.filled(
                        tooltip: 'Người tiếp theo',
                        visualDensity: VisualDensity.compact,
                        iconSize: 15,
                        padding: EdgeInsets.zero,
                        constraints:
                            const BoxConstraints(minWidth: 28, minHeight: 26),
                        style: IconButton.styleFrom(
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(6)),
                        ),
                        icon: const Icon(Icons.navigate_next_rounded),
                        onPressed: () {
                          setState(() {
                            _currentPersonIndex =
                                _currentPersonIndex < _people.length - 1
                                    ? _currentPersonIndex + 1
                                    : 0;
                          });
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      _miniChip(
                          Icons.badge_outlined,
                          current?['role'] ?? 'Chức vụ',
                          const Color(0xFFF0ABFC)),
                      const SizedBox(width: 4),
                      _miniChip(
                          Icons.domain_rounded,
                          current?['department'] ?? 'Khoa',
                          const Color(0xFF5EEAD4)),
                      const SizedBox(width: 4),
                      _miniChip(
                          Icons.local_hospital_rounded,
                          current?['hospital'] ?? _selectedHospital,
                          const Color(0xFF93C5FD)),
                    ],
                  ),
                ],
              ),
            )
          else
            Container(
              height: 30,
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.06),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'Chưa có dữ liệu. Bấm icon Cài đặt ở góc trên để dán danh sách.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: Colors.white70),
              ),
            ),
        ],
      ),
    );
  }

  void _showSettingsDialog() async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (context) => PeopleEditorDialog(
        initialPeople: _people,
        tokenController: _tokenController,
        initialEnabled: _fillEnabled,
        initialDelays: _fillDelayMs,
        initialHospitals: _hospitals,
        initialSelectedHospital: _selectedHospital,
        initialOtpTimeout: _otpTimeoutSeconds,
      ),
    );

    if (result != null) {
      setState(() {
        _people = List<Map<String, String>>.from(result['people']);
        _fillEnabled = Map<String, bool>.from(result['enabled']);
        _fillDelayMs = Map<String, int>.from(result['delays']);
        if (result['hospitals'] != null) {
          _hospitals = List<String>.from(result['hospitals']);
        }
        if (result['selectedHospital'] != null) {
          _selectedHospital = result['selectedHospital'];
        }
        if (result['otpTimeout'] != null) {
          _otpTimeoutSeconds = result['otpTimeout'];
        }
        if (_currentPersonIndex >= _people.length) {
          _currentPersonIndex = 0;
        }
      });
      _savePreferences();
    }
  }
}

const List<String> kDepartments = [
  'Khoa Noi Tim Mach',
  'Khoa Phau Thuat Gay Me - Hoi Suc',
  'Khoa Kham Benh & Cap Cuu',
  'Khoa Noi Tong Hop',
  'Khoa Duoc',
  'Khoa Hoi Suc Tich Cuc - Chong Doc',
  'Khoa Chan Thuong Chinh Hinh - Bong',
  'Khoa Chan Doan Hinh Anh',
  'Khoa Ngoai Tong Hop',
  'Khoa Than Nhan Tao',
  'Khoa Noi Tieu Hoa',
  'Khoa Kiem Soat Nhiem Khuan',
  'Khoa Huyet Hoc',
  'Khoa Noi Than Kinh',
  'Khoa Dieu Tri Yeu Cau',
  'Khoa Ngoai Tieu Hoa',
  'Khoa Benh Nhiet Doi',
  'Khoa Ngoai Than Kinh',
  'Khoa Hoa Sinh',
  'Khoa Phuc Hoi Chuc Nang',
  'Khoa Rang Ham Mat',
  'Khoa Ung Buou',
  'Khoa Tai Mui Hong',
  'Khoa Mat',
  'Khoa Vi Sinh',
  'Khoa Giai Phau Benh',
  'Khoa Da Lieu',
  'Phong Dieu Duong',
  'Ban Giam Doc',
  'Khoa Dinh Duong',
  'Khac'
];

const List<String> kTitles = [
  'Y Ta Truong/ Dieu Duong Truong',
  'Giam Doc',
  'Duoc sy',
  'Pho Giam Doc',
  'Truong Khoa',
  'Pho Khoa',
  'Bac Sy Dieu Tri',
  'Y ta/ Dieu duong'
];

class PeopleEditorDialog extends StatefulWidget {
  final List<Map<String, String>> initialPeople;
  final TextEditingController tokenController;
  final Map<String, bool> initialEnabled;
  final Map<String, int> initialDelays;
  final List<String> initialHospitals;
  final String initialSelectedHospital;
  final int initialOtpTimeout;

  const PeopleEditorDialog({
    super.key,
    required this.initialPeople,
    required this.tokenController,
    required this.initialEnabled,
    required this.initialDelays,
    required this.initialHospitals,
    required this.initialSelectedHospital,
    required this.initialOtpTimeout,
  });

  @override
  State<PeopleEditorDialog> createState() => _PeopleEditorDialogState();
}

class _PeopleEditorDialogState extends State<PeopleEditorDialog> {
  late List<Map<String, String>> _people;
  late Map<String, bool> _enabled;
  late Map<String, int> _delays;
  late List<String> _hospitals;
  late String _selectedHospital;
  late int _otpTimeout;
  final TextEditingController _pasteController = TextEditingController();
  final TextEditingController _newHospitalController = TextEditingController();

  static const _fieldLabels = {
    'name': 'Họ và tên',
    'attendeeRole': 'Vai trò người tham dự',
    'hospital': 'Bệnh viện / Tỉnh',
    'department': 'Phòng ban / Khoa',
    'role': 'Chức danh',
    'agreement': 'Checkbox Đồng ý',
  };

  @override
  void initState() {
    super.initState();
    _people =
        List.from(widget.initialPeople.map((e) => Map<String, String>.from(e)));
    _enabled = Map<String, bool>.from(widget.initialEnabled);
    _delays = Map<String, int>.from(widget.initialDelays);
    _hospitals = List.from(widget.initialHospitals);
    _otpTimeout = widget.initialOtpTimeout;
    if (_hospitals.isEmpty) {
      _hospitals = List.from(kDefaultHospitals);
    }
    _selectedHospital = widget.initialSelectedHospital;
    if (!_hospitals.contains(_selectedHospital)) {
      _selectedHospital = _hospitals.first;
    }

    for (var p in _people) {
      final h = p['hospital']?.trim();
      if (h == null || h.isEmpty) {
        p['hospital'] = _selectedHospital;
      } else if (!_hospitals.contains(h)) {
        _hospitals.add(h);
      }
    }
  }

  void _applyHospitalToAll(String hospital) {
    final target = hospital.trim();
    if (target.isEmpty) return;
    setState(() {
      _selectedHospital = target;
      for (var p in _people) {
        p['hospital'] = target;
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Đã gán "$target" cho tất cả ${_people.length} người!'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _addHospital(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    if (!_hospitals.contains(trimmed)) {
      setState(() {
        _hospitals.add(trimmed);
        _selectedHospital = trimmed;
        _newHospitalController.clear();
      });
    } else {
      setState(() {
        _selectedHospital = trimmed;
        _newHospitalController.clear();
      });
    }
  }

  void _removeHospital(String hospital) {
    if (_hospitals.length <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cần giữ lại ít nhất 1 bệnh viện!')),
      );
      return;
    }
    setState(() {
      _hospitals.remove(hospital);
      if (_selectedHospital == hospital) {
        _selectedHospital = _hospitals.first;
      }
    });
  }

  void _showBulkAddHospitalDialog() {
    final textController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF101827),
        title: const Text('Nhập danh sách Bệnh Viện (Mỗi dòng 1 tên)',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
        content: TextField(
          controller: textController,
          maxLines: 6,
          decoration: const InputDecoration(
            hintText: 'Bệnh viện A\nBệnh viện B\n...',
            isDense: true,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () {
              final lines = textController.text
                  .split('\n')
                  .map((e) => e.trim())
                  .where((e) => e.isNotEmpty);
              int count = 0;
              setState(() {
                for (var line in lines) {
                  if (!_hospitals.contains(line)) {
                    _hospitals.add(line);
                    count++;
                  }
                }
              });
              Navigator.pop(ctx);
              if (count > 0) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                      content: Text('Đã thêm $count bệnh viện vào Profile!')),
                );
              }
            },
            child: const Text('Thêm vào Profile'),
          ),
        ],
      ),
    );
  }

  void _parsePastedData() {
    final lines = _pasteController.text.split('\n');
    for (var line in lines) {
      if (line.trim().isEmpty) continue;
      final parts = line.split('-');
      if (parts.length >= 2) {
        final rawDepartment = parts[1].trim();
        final rawRole = parts.length > 2 ? parts[2].trim() : '';
        final rawHospital = parts.length > 3 ? parts[3].trim() : '';

        String guessDept = _formatDepartment(rawDepartment);
        if (!kDepartments.contains(guessDept)) guessDept = kDepartments.first;

        String guessRole = _formatTitle(rawRole);
        if (!kTitles.contains(guessRole)) guessRole = kTitles.first;

        String guessHospital =
            rawHospital.isNotEmpty ? rawHospital : _selectedHospital;
        if (!_hospitals.contains(guessHospital)) {
          _hospitals.add(guessHospital);
        }

        _people.add({
          'name': parts[0].trim(),
          'department': guessDept,
          'role': guessRole,
          'hospital': guessHospital,
        });
      }
    }
    setState(() {
      _pasteController.clear();
    });
  }

  String _cleanNoAccent(String input) {
    const vietnamese = {
      'à': 'a',
      'á': 'a',
      'ạ': 'a',
      'ả': 'a',
      'ã': 'a',
      'â': 'a',
      'ầ': 'a',
      'ấ': 'a',
      'ậ': 'a',
      'ẩ': 'a',
      'ẫ': 'a',
      'ă': 'a',
      'ằ': 'a',
      'ắ': 'a',
      'ặ': 'a',
      'ẳ': 'a',
      'ẵ': 'a',
      'è': 'e',
      'é': 'e',
      'ẹ': 'e',
      'ẻ': 'e',
      'ẽ': 'e',
      'ê': 'e',
      'ề': 'e',
      'ế': 'e',
      'ệ': 'e',
      'ể': 'e',
      'ễ': 'e',
      'ì': 'i',
      'í': 'i',
      'ị': 'i',
      'ỉ': 'i',
      'ĩ': 'i',
      'ò': 'o',
      'ó': 'o',
      'ọ': 'o',
      'ỏ': 'o',
      'õ': 'o',
      'ô': 'o',
      'ồ': 'o',
      'ố': 'o',
      'ộ': 'o',
      'ổ': 'o',
      'ỗ': 'o',
      'ơ': 'o',
      'ờ': 'o',
      'ớ': 'o',
      'ợ': 'o',
      'ở': 'o',
      'ỡ': 'o',
      'ù': 'u',
      'ú': 'u',
      'ụ': 'u',
      'ủ': 'u',
      'ũ': 'u',
      'ư': 'u',
      'ừ': 'u',
      'ứ': 'u',
      'ự': 'u',
      'ử': 'u',
      'ữ': 'u',
      'ỳ': 'y',
      'ý': 'y',
      'ỵ': 'y',
      'ỷ': 'y',
      'ỹ': 'y',
      'đ': 'd',
      'À': 'A',
      'Á': 'A',
      'Ạ': 'A',
      'Ả': 'A',
      'Ã': 'A',
      'Â': 'A',
      'Ầ': 'A',
      'Ấ': 'A',
      'Ậ': 'A',
      'Ẩ': 'A',
      'Ẫ': 'A',
      'Ă': 'A',
      'Ằ': 'A',
      'Ắ': 'A',
      'Ặ': 'A',
      'Ẳ': 'A',
      'Ẵ': 'A',
      'È': 'E',
      'É': 'E',
      'Ẹ': 'E',
      'Ẻ': 'E',
      'Ẽ': 'E',
      'Ê': 'E',
      'Ề': 'E',
      'Ế': 'E',
      'Ệ': 'E',
      'Ể': 'E',
      'Ễ': 'E',
      'Ì': 'I',
      'Í': 'I',
      'Ị': 'I',
      'Ỉ': 'I',
      'Ĩ': 'I',
      'Ò': 'O',
      'Ó': 'O',
      'Ọ': 'O',
      'Ỏ': 'O',
      'Õ': 'O',
      'Ô': 'O',
      'Ồ': 'O',
      'Ố': 'O',
      'Ộ': 'O',
      'Ổ': 'O',
      'Ỗ': 'O',
      'Ơ': 'O',
      'Ờ': 'O',
      'Ớ': 'O',
      'Ợ': 'O',
      'Ở': 'O',
      'Ỡ': 'O',
      'Ù': 'U',
      'Ú': 'U',
      'Ụ': 'U',
      'Ủ': 'U',
      'Ũ': 'U',
      'Ư': 'U',
      'Ừ': 'U',
      'Ứ': 'U',
      'Ự': 'U',
      'Ử': 'U',
      'Ữ': 'U',
      'Ỳ': 'Y',
      'Ý': 'Y',
      'Ỵ': 'Y',
      'Ỷ': 'Y',
      'Ỹ': 'Y',
      'Đ': 'D',
    };
    var out = input.trim();
    vietnamese.forEach((k, v) => out = out.replaceAll(k, v));
    return out.replaceAll(RegExp(r'\s+'), ' ');
  }

  String _titleCase(String input) {
    return input
        .split(' ')
        .where((w) => w.isNotEmpty)
        .map((w) =>
            w[0].toUpperCase() +
            (w.length > 1 ? w.substring(1).toLowerCase() : ''))
        .join(' ');
  }

  String _formatDepartment(String raw) {
    final s = _cleanNoAccent(raw).toLowerCase();
    if (s.contains('gay me')) return 'Khoa Phau Thuat Gay Me - Hoi Suc';
    if (s.contains('ngoai than kinh')) return 'Khoa Ngoai Than Kinh';
    if (s.contains('chan thuong') ||
        s.contains('chinh hinh') ||
        s.contains('bong')) return 'Khoa Chan Thuong Chinh Hinh - Bong';
    if (s.contains('ngoai tong hop')) return 'Khoa Ngoai Tong Hop';
    if (s.contains('noi tim mach')) return 'Khoa Noi Tim Mach';
    if (s.contains('noi tong hop')) return 'Khoa Noi Tong Hop';
    if (s.contains('ngoai tieu hoa')) return 'Khoa Ngoai Tieu Hoa';
    if (s.contains('noi tieu hoa')) return 'Khoa Noi Tieu Hoa';
    if (s.contains('noi than kinh')) return 'Khoa Noi Than Kinh';
    final res = _titleCase(_cleanNoAccent(raw));
    if (!res.toLowerCase().startsWith('khoa ') &&
        !res.toLowerCase().startsWith('phong ')) return 'Khoa $res';
    return res;
  }

  String _formatTitle(String raw) {
    final s = _cleanNoAccent(raw).toLowerCase().replaceAll('.', '').trim();
    if (s == 'bs' || s.contains('bac si') || s.contains('bac sy'))
      return 'Bac Sy Dieu Tri';
    if (s.contains('truong')) return 'Y Ta Truong/ Dieu Duong Truong';
    if (s == 'dd' || s.contains('dieu duong') || s.contains('y ta'))
      return 'Y ta/ Dieu duong';
    return _titleCase(_cleanNoAccent(raw));
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF101827),
      surfaceTintColor: const Color(0xFF5EEAD4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.all(12),
      child: Container(
        width: double.maxFinite,
        height: 720,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.tune_rounded, color: Color(0xFF5EEAD4)),
                const SizedBox(width: 10),
                const Expanded(
                    child: Text('Quản lý Dữ liệu Điền Tự động',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold))),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: widget.tokenController,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.vpn_key_rounded),
                labelText: 'ViOTP Token',
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<int>(
              value: [60, 90, 120].contains(_otpTimeout) ? _otpTimeout : 60,
              isExpanded: true,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.timer_outlined, size: 20),
                labelText: 'Thời gian chờ OTP (khớp web Abbott)',
                isDense: true,
              ),
              items: const [
                DropdownMenuItem(
                    value: 60, child: Text('60 giây (Mặc định - Chuẩn Abbott)')),
                DropdownMenuItem(value: 90, child: Text('90 giây')),
                DropdownMenuItem(value: 120, child: Text('120 giây (2 phút)')),
              ],
              onChanged: (val) {
                if (val != null) setState(() => _otpTimeout = val);
              },
            ),
            const SizedBox(height: 10),
            // Profile & Quản lý Bệnh Viện
            Container(
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withOpacity(0.1)),
              ),
              child: Theme(
                data: Theme.of(context)
                    .copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  leading: const Icon(Icons.local_hospital_rounded,
                      color: Color(0xFF5EEAD4), size: 20),
                  title: const Text('Bệnh Viện & Profile Bệnh Viện',
                      style:
                          TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                  subtitle: Text(
                    'Đang chọn: $_selectedHospital',
                    style: TextStyle(
                        fontSize: 11, color: Colors.white.withOpacity(0.6)),
                    overflow: TextOverflow.ellipsis,
                  ),
                  childrenPadding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: _hospitals.contains(_selectedHospital)
                                ? _selectedHospital
                                : _hospitals.first,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Bệnh viện mặc định / chung',
                              isDense: true,
                            ),
                            items: _hospitals
                                .map((h) => DropdownMenuItem(
                                      value: h,
                                      child: Text(h,
                                          style: const TextStyle(fontSize: 12),
                                          overflow: TextOverflow.ellipsis),
                                    ))
                                .toList(),
                            onChanged: (val) {
                              if (val != null) {
                                setState(() => _selectedHospital = val);
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.tonalIcon(
                            onPressed: _people.isEmpty
                                ? null
                                : () => _applyHospitalToAll(_selectedHospital),
                            icon: const Icon(Icons.done_all_rounded, size: 16),
                            label: const Text(
                              'Gán BV này cho TẤT CẢ người trong DS',
                              style: TextStyle(
                                  fontSize: 11, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Divider(color: Colors.white12, height: 1),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Text(
                          'Danh sách Profile BV lưu trong app:',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF5EEAD4)),
                        ),
                        const Spacer(),
                        TextButton.icon(
                          onPressed: _showBulkAddHospitalDialog,
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            visualDensity: VisualDensity.compact,
                          ),
                          icon:
                              const Icon(Icons.playlist_add_rounded, size: 14),
                          label: const Text('Nhập nhiều',
                              style: TextStyle(fontSize: 11)),
                        ),
                      ],
                    ),
                    Container(
                      constraints: const BoxConstraints(maxHeight: 110),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                        border:
                            Border.all(color: Colors.white.withOpacity(0.08)),
                      ),
                      child: ListView.separated(
                        shrinkWrap: true,
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        itemCount: _hospitals.length,
                        separatorBuilder: (_, __) =>
                            const Divider(height: 1, color: Colors.white10),
                        itemBuilder: (context, idx) {
                          final h = _hospitals[idx];
                          final isSel = h == _selectedHospital;
                          return ListTile(
                            dense: true,
                            visualDensity: VisualDensity.compact,
                            contentPadding:
                                const EdgeInsets.symmetric(horizontal: 8),
                            leading: Icon(
                              isSel
                                  ? Icons.radio_button_checked_rounded
                                  : Icons.radio_button_off_rounded,
                              size: 16,
                              color: isSel
                                  ? const Color(0xFF5EEAD4)
                                  : Colors.white38,
                            ),
                            title: Text(
                              h,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight:
                                    isSel ? FontWeight.bold : FontWeight.normal,
                                color: isSel
                                    ? const Color(0xFF5EEAD4)
                                    : Colors.white,
                              ),
                            ),
                            trailing: _hospitals.length > 1
                                ? IconButton(
                                    icon: const Icon(Icons.close_rounded,
                                        size: 14, color: Colors.white38),
                                    onPressed: () => _removeHospital(h),
                                  )
                                : null,
                            onTap: () {
                              setState(() => _selectedHospital = h);
                            },
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _newHospitalController,
                            style: const TextStyle(fontSize: 12),
                            decoration: const InputDecoration(
                              labelText: 'Thêm BV vào Profile',
                              hintText: 'Nhập tên BV...',
                              isDense: true,
                            ),
                            onSubmitted: _addHospital,
                          ),
                        ),
                        const SizedBox(width: 6),
                        FilledButton(
                          onPressed: () =>
                              _addHospital(_newHospitalController.text),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size(54, 40),
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                          ),
                          child: const Text('Thêm'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            // Cấu hình tự điền
            Container(
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withOpacity(0.1)),
              ),
              child: Theme(
                data: Theme.of(context)
                    .copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  title: const Text('Cấu hình tự điền',
                      style:
                          TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                  childrenPadding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                  children: [
                    ..._fieldLabels.entries.map((entry) => Padding(
                          padding: const EdgeInsets.only(bottom: 2),
                          child: Row(
                            children: [
                              Switch(
                                value: _enabled[entry.key] ?? true,
                                onChanged: (value) =>
                                    setState(() => _enabled[entry.key] = value),
                              ),
                              Expanded(
                                  child: Text(entry.value,
                                      style: const TextStyle(fontSize: 12))),
                              SizedBox(
                                width: 82,
                                child: TextFormField(
                                  key: ValueKey('delay_${entry.key}'),
                                  initialValue: '${_delays[entry.key] ?? 700}',
                                  enabled: _enabled[entry.key] ?? true,
                                  keyboardType: TextInputType.number,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.digitsOnly
                                  ],
                                  decoration: const InputDecoration(
                                    isDense: true,
                                    suffixText: 'ms',
                                  ),
                                  onChanged: (value) => _delays[entry.key] =
                                      (int.tryParse(value) ?? 0)
                                          .clamp(0, 10000)
                                          .toInt(),
                                ),
                              ),
                            ],
                          ),
                        )),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _pasteController,
                  minLines: 2,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    alignLabelWithHint: true,
                    prefixIcon: Icon(Icons.paste_rounded),
                    labelText: 'Dán danh sách NOIDUNGDIEN',
                    hintText:
                        'VD: Phạm Thị Thu Vân - gây mê hồi sức - bs [- bệnh viện]',
                  ),
                ),
                const SizedBox(height: 6),
                FilledButton.icon(
                  onPressed: _parsePastedData,
                  icon: const Icon(Icons.add_task_rounded),
                  label: const Text('Phân tích và Thêm'),
                )
              ],
            ),
            const SizedBox(height: 10),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white.withOpacity(0.1)),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: _people.length,
                  itemBuilder: (context, index) {
                    final p = _people[index];
                    final currentHosp = (p['hospital'] != null &&
                            _hospitals.contains(p['hospital']!.trim()))
                        ? p['hospital']!.trim()
                        : _selectedHospital;

                    return Card(
                      color: Colors.white.withOpacity(0.05),
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(
                              color: Colors.white.withOpacity(0.05))),
                      elevation: 0,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    CircleAvatar(
                                      radius: 12,
                                      backgroundColor: const Color(0xFF5EEAD4),
                                      foregroundColor: const Color(0xFF06211D),
                                      child: Text('${index + 1}',
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w900,
                                              fontSize: 11)),
                                    ),
                                    const SizedBox(width: 8),
                                    const Text('Thông tin người tham gia',
                                        style: TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 13,
                                            color: Colors.white70)),
                                  ],
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline,
                                      color: Colors.redAccent, size: 20),
                                  onPressed: () =>
                                      setState(() => _people.removeAt(index)),
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                )
                              ],
                            ),
                            const SizedBox(height: 10),
                            TextField(
                              controller: TextEditingController(text: p['name'])
                                ..selection = TextSelection.collapsed(
                                    offset: (p['name'] ?? '').length),
                              onChanged: (val) => p['name'] = val,
                              decoration: const InputDecoration(
                                  isDense: true, labelText: 'Họ Tên'),
                            ),
                            const SizedBox(height: 8),
                            DropdownButtonFormField<String>(
                              value: currentHosp,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                isDense: true,
                                labelText: 'Bệnh Viện',
                                prefixIcon: Icon(Icons.local_hospital_outlined,
                                    size: 16),
                              ),
                              items: _hospitals
                                  .map((h) => DropdownMenuItem(
                                      value: h,
                                      child: Text(h,
                                          style: const TextStyle(fontSize: 12),
                                          overflow: TextOverflow.ellipsis)))
                                  .toList(),
                              onChanged: (val) {
                                if (val != null) {
                                  setState(() => p['hospital'] = val);
                                }
                              },
                            ),
                            const SizedBox(height: 8),
                            DropdownButtonFormField<String>(
                              value: kDepartments.contains(p['department'])
                                  ? p['department']
                                  : kDepartments.first,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                  isDense: true, labelText: 'Khoa'),
                              items: kDepartments
                                  .map((d) => DropdownMenuItem(
                                      value: d,
                                      child: Text(d,
                                          style:
                                              const TextStyle(fontSize: 13))))
                                  .toList(),
                              onChanged: (val) =>
                                  setState(() => p['department'] = val!),
                            ),
                            const SizedBox(height: 8),
                            DropdownButtonFormField<String>(
                              value: kTitles.contains(p['role'])
                                  ? p['role']
                                  : kTitles.first,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                  isDense: true, labelText: 'Chức Danh'),
                              items: kTitles
                                  .map((t) => DropdownMenuItem(
                                      value: t,
                                      child: Text(t,
                                          style:
                                              const TextStyle(fontSize: 13))))
                                  .toList(),
                              onChanged: (val) =>
                                  setState(() => p['role'] = val!),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Hủy')),
                const SizedBox(width: 10),
                FilledButton.icon(
                  onPressed: () => Navigator.pop(context, {
                    'people': _people,
                    'enabled': _enabled,
                    'delays': _delays,
                    'hospitals': _hospitals,
                    'selectedHospital': _selectedHospital,
                    'otpTimeout': _otpTimeout,
                  }),
                  icon: const Icon(Icons.save_rounded),
                  label: const Text('Lưu Thay Đổi'),
                )
              ],
            )
          ],
        ),
      ),
    );
  }
}
