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

  int? _abbottServiceId;
  String _currentPhoneNumber = '';
  String _currentRequestId = '';
  String _currentOtp = '';
  String _otpStatusText = '';

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

  Future<void> _loadPreferences() async {
    final token = await AppPreferences.getString('viotp_token');
    final lastUrl = await AppPreferences.getString('last_url');
    final peopleData = await AppPreferences.getString('people_data');
    final fillSettings = await AppPreferences.getString('fill_settings');
    setState(() {
      _tokenController.text = token ?? 'de6faac93d8d4f3294070fe48a11224b';
      _urlController.text = lastUrl ?? '';
      if (peopleData != null && peopleData.isNotEmpty) {
        try {
          final List<dynamic> decoded = jsonDecode(peopleData);
          _people = decoded.map((e) => Map<String, String>.from(e)).toList();
        } catch (_) {
          _people = [];
        }
      } else {
        _people = [];
      }
      if (fillSettings != null && fillSettings.isNotEmpty) {
        try {
          final decoded = Map<String, dynamic>.from(jsonDecode(fillSettings));
          _fillEnabled.addAll(Map<String, dynamic>.from(decoded['enabled'] ?? {})
              .map((key, value) => MapEntry(key, value == true)));
          _fillDelayMs.addAll(Map<String, dynamic>.from(decoded['delays'] ?? {})
              .map((key, value) => MapEntry(key, (value as num).toInt().clamp(0, 10000).toInt())));
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
    final peopleJson = jsonEncode(_people);
    await AppPreferences.setString('people_data', peopleJson);
    await AppPreferences.setString('fill_settings', jsonEncode({
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

    setState(() {
      _isGettingPhone = true;
      _currentPhoneNumber = '';
      _currentRequestId = '';
      _currentOtp = '';
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

    setState(() {
      _isGettingOtp = true;
      _currentOtp = '';
      _otpStatusText = 'Đang chờ OTP 60s...';
    });

    try {
      final token = _tokenController.text.trim();
      for (var second = 0; second < 60; second++) {
        if (!mounted) return;
        setState(() {
          _otpStatusText = 'Đang chờ OTP... còn ${60 - second}s';
        });

        final url = Uri.parse(
            'https://api.viotp.com/session/getv2?requestId=$_currentRequestId&token=$token');
        final response = await http.get(url);
        final json = jsonDecode(response.body);

        if (json['status_code'] == 200) {
          final status = json['data']['Status'];
          if (status == 1) {
            final otp = json['data']['Code'].toString();
            setState(() {
              _currentOtp = otp;
              _otpStatusText = 'Đã có OTP';
            });
            Clipboard.setData(ClipboardData(text: otp));
            await _fillOtpInWeb();
            ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Đã nhận, copy và điền OTP!')));
            return;
          }
          if (status != 0) {
            ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Phiên đã hết hạn hoặc lỗi!')));
            return;
          }
        } else {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text("Lỗi: ${json['message']}")));
          return;
        }

        await Future.delayed(const Duration(seconds: 1));
      }

      setState(() {
        _otpStatusText = 'Không lấy được OTP sau 60s';
      });
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Không lấy mã OTP được sau 60 giây.')));
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Lỗi kết nối: $e')));
    } finally {
      if (mounted) {
        setState(() {
          _isGettingOtp = false;
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
    
    final payload = jsonEncode({
      'person': {
        'name': p['name'] ?? '',
        'department': p['department'] ?? '',
        'role': p['role'] ?? '',
        'attendeeRole': 'Nguoi tham du',
        'hospital': 'BENH VIEN DA KHOA TINH QUANG NGAI',
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
        content: Text(
            'Đang điền thông tin tuần tự. Vui lòng đợi và kiểm tra...')));
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
                padding: const EdgeInsets.fromLTRB(10, 4, 10, 6),
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: _glassDecoration(radius: 18),
                  child: Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 42,
                          child: TextField(
                            controller: _urlController,
                            style: const TextStyle(fontSize: 13),
                            decoration: const InputDecoration(
                              isDense: true,
                              prefixIcon: Icon(Icons.link_rounded, size: 18),
                              hintText: 'Dán link Abbott...',
                            ),
                            onSubmitted: (_) => _loadUrl(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: _loadUrl,
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(58, 42),
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                        ),
                        child: const Text('Mở'),
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(24),
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

  Widget _sectionTitle(IconData icon, String title, String subtitle) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFF5EEAD4).withOpacity(0.16),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: const Color(0xFF5EEAD4), size: 18),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 15)),
              Text(subtitle,
                  style: TextStyle(
                      color: Colors.white.withOpacity(0.58), fontSize: 11)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _valuePill(String value, String hint, IconData icon) {
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.18),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.10)),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.white70, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value.isEmpty ? hint : value,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: value.isEmpty ? Colors.white38 : Colors.white,
                fontWeight: FontWeight.w700,
                letterSpacing: .4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniAction({
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
    bool primary = false,
  }) {
    final child = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16),
        const SizedBox(width: 6),
        Text(label),
      ],
    );
    return primary
        ? FilledButton.tonal(onPressed: onPressed, child: child)
        : OutlinedButton(onPressed: onPressed, child: child);
  }

  Widget _loadingIcon(bool loading, IconData icon) {
    if (!loading) return Icon(icon, size: 18);
    return const SizedBox(
      width: 16,
      height: 16,
      child: CircularProgressIndicator(strokeWidth: 2),
    );
  }

  Widget _buildControlPanel() {
    final hasPerson = _people.isNotEmpty;
    final current = hasPerson ? _people[_currentPersonIndex] : null;

    return Container(
      margin: const EdgeInsets.fromLTRB(10, 6, 10, 8),
      constraints: const BoxConstraints(maxHeight: 230),
      padding: const EdgeInsets.all(8),
      decoration: _glassDecoration(radius: 22),
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.sms_rounded,
                    color: const Color(0xFF5EEAD4), size: 18),
                const SizedBox(width: 6),
                const Text('OTP',
                    style:
                        TextStyle(fontWeight: FontWeight.w900, fontSize: 13)),
                const Spacer(),
                if (_otpStatusText.isNotEmpty)
                  Flexible(
                    child: Text(
                      _otpStatusText,
                      textAlign: TextAlign.right,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF93C5FD),
                          fontWeight: FontWeight.w700),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                FilledButton(
                  onPressed: (_isGettingPhone || _isLoadingService)
                      ? null
                      : _getPhoneNumber,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(66, 32),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    visualDensity: VisualDensity.compact,
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    _loadingIcon(_isGettingPhone || _isLoadingService,
                        Icons.phone_android_rounded),
                    const SizedBox(width: 4),
                    const Text('Số'),
                  ]),
                ),
                const SizedBox(width: 6),
                Expanded(
                    child: _valuePill(
                        _currentPhoneNumber, 'SĐT', Icons.call_rounded)),
                IconButton.filledTonal(
                  tooltip: 'Copy số',
                  visualDensity: VisualDensity.compact,
                  iconSize: 18,
                  icon: const Icon(Icons.copy_rounded),
                  onPressed: _currentPhoneNumber.isEmpty
                      ? null
                      : () => _copy(_currentPhoneNumber, 'Số điện thoại'),
                ),
                IconButton.filledTonal(
                  tooltip: 'Điền số',
                  visualDensity: VisualDensity.compact,
                  iconSize: 18,
                  icon: const Icon(Icons.content_paste_go_rounded),
                  onPressed:
                      _currentPhoneNumber.isEmpty ? null : _fillPhoneInWeb,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                FilledButton(
                  onPressed: _isGettingOtp ? null : _getOtp,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(66, 32),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    visualDensity: VisualDensity.compact,
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    _loadingIcon(_isGettingOtp, Icons.mark_email_read_rounded),
                    const SizedBox(width: 4),
                    Text(_isGettingOtp ? 'Chờ' : 'OTP'),
                  ]),
                ),
                const SizedBox(width: 6),
                Expanded(
                    child: _valuePill(
                        _currentOtp, 'Mã OTP', Icons.password_rounded)),
                IconButton.filledTonal(
                  tooltip: 'Copy OTP',
                  visualDensity: VisualDensity.compact,
                  iconSize: 18,
                  icon: const Icon(Icons.copy_rounded),
                  onPressed: _currentOtp.isEmpty
                      ? null
                      : () => _copy(_currentOtp, 'OTP'),
                ),
                IconButton.filledTonal(
                  tooltip: 'Điền OTP',
                  visualDensity: VisualDensity.compact,
                  iconSize: 18,
                  icon: const Icon(Icons.content_paste_go_rounded),
                  onPressed: _currentOtp.isEmpty ? null : _fillOtpInWeb,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 32,
                    child: FilledButton.icon(
                      onPressed: _submitFormInWeb,
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFF0ABFC),
                        foregroundColor: const Color(0xFF1E0824),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: EdgeInsets.zero,
                      ),
                      icon: const Icon(Icons.send_rounded, size: 14),
                      label: const Text(
                        'Gửi Form Đăng Ký (Web)',
                        style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 11,
                            letterSpacing: .3),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            if (hasPerson) ...[
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 7, vertical: 4),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      const Color(0xFF5EEAD4).withOpacity(0.16),
                      const Color(0xFFF0ABFC).withOpacity(0.10),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border:
                      Border.all(color: Colors.white.withOpacity(0.10)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 11,
                          backgroundColor: const Color(0xFF5EEAD4),
                          foregroundColor: const Color(0xFF06211D),
                          child: Text('${_currentPersonIndex + 1}',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w900, fontSize: 12)),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            current?['name'] ?? '',
                            style: const TextStyle(
                                fontWeight: FontWeight.w900, fontSize: 12),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        IconButton.filledTonal(
                          tooltip: 'Điền người này',
                          visualDensity: VisualDensity.compact,
                          iconSize: 18,
                          icon: const Icon(Icons.auto_fix_high_rounded),
                          onPressed: _fillCurrentPersonInWeb,
                        ),
                        IconButton.filled(
                          tooltip: 'Người tiếp theo',
                          visualDensity: VisualDensity.compact,
                          iconSize: 20,
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
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.05),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.badge_outlined, size: 12, color: Color(0xFFF0ABFC)),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    current?['role'] ?? 'Chưa có chức vụ',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white.withOpacity(0.8),
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.05),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.local_hospital_outlined, size: 12, color: Color(0xFF5EEAD4)),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    current?['department'] ?? 'Chưa có khoa',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white.withOpacity(0.8),
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ] else ...[
              Container(
                height: 38,
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Text(
                  'Chưa có dữ liệu. Bấm cài đặt để dán NOIDUNGDIEN.TXT.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12),
                ),
              ),
            ],
          ],
        ),
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
      ),
    );

    if (result != null) {
      setState(() {
        _people = List<Map<String, String>>.from(result['people']);
        _fillEnabled = Map<String, bool>.from(result['enabled']);
        _fillDelayMs = Map<String, int>.from(result['delays']);
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

  const PeopleEditorDialog({
    super.key,
    required this.initialPeople,
    required this.tokenController,
    required this.initialEnabled,
    required this.initialDelays,
  });

  @override
  State<PeopleEditorDialog> createState() => _PeopleEditorDialogState();
}

class _PeopleEditorDialogState extends State<PeopleEditorDialog> {
  late List<Map<String, String>> _people;
  late Map<String, bool> _enabled;
  late Map<String, int> _delays;
  final TextEditingController _pasteController = TextEditingController();

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
    _people = List.from(widget.initialPeople.map((e) => Map<String, String>.from(e)));
    _enabled = Map<String, bool>.from(widget.initialEnabled);
    _delays = Map<String, int>.from(widget.initialDelays);
  }

  void _parsePastedData() {
    final lines = _pasteController.text.split('\n');
    for (var line in lines) {
      if (line.trim().isEmpty) continue;
      final parts = line.split('-');
      if (parts.length >= 2) {
        final rawDepartment = parts[1].trim();
        final rawRole = parts.length > 2 ? parts[2].trim() : '';
        
        String guessDept = _formatDepartment(rawDepartment);
        if (!kDepartments.contains(guessDept)) guessDept = kDepartments.first;
        
        String guessRole = _formatTitle(rawRole);
        if (!kTitles.contains(guessRole)) guessRole = kTitles.first;

        _people.add({
          'name': parts[0].trim(),
          'department': guessDept,
          'role': guessRole,
        });
      }
    }
    setState(() {
      _pasteController.clear();
    });
  }

  String _cleanNoAccent(String input) {
    const vietnamese = {
      'à': 'a', 'á': 'a', 'ạ': 'a', 'ả': 'a', 'ã': 'a', 'â': 'a', 'ầ': 'a', 'ấ': 'a', 'ậ': 'a', 'ẩ': 'a', 'ẫ': 'a',
      'ă': 'a', 'ằ': 'a', 'ắ': 'a', 'ặ': 'a', 'ẳ': 'a', 'ẵ': 'a',
      'è': 'e', 'é': 'e', 'ẹ': 'e', 'ẻ': 'e', 'ẽ': 'e', 'ê': 'e', 'ề': 'e', 'ế': 'e', 'ệ': 'e', 'ể': 'e', 'ễ': 'e',
      'ì': 'i', 'í': 'i', 'ị': 'i', 'ỉ': 'i', 'ĩ': 'i',
      'ò': 'o', 'ó': 'o', 'ọ': 'o', 'ỏ': 'o', 'õ': 'o', 'ô': 'o', 'ồ': 'o', 'ố': 'o', 'ộ': 'o', 'ổ': 'o', 'ỗ': 'o',
      'ơ': 'o', 'ờ': 'o', 'ớ': 'o', 'ợ': 'o', 'ở': 'o', 'ỡ': 'o',
      'ù': 'u', 'ú': 'u', 'ụ': 'u', 'ủ': 'u', 'ũ': 'u', 'ư': 'u', 'ừ': 'u', 'ứ': 'u', 'ự': 'u', 'ử': 'u', 'ữ': 'u',
      'ỳ': 'y', 'ý': 'y', 'ỵ': 'y', 'ỷ': 'y', 'ỹ': 'y',
      'đ': 'd',
      'À': 'A', 'Á': 'A', 'Ạ': 'A', 'Ả': 'A', 'Ã': 'A', 'Â': 'A', 'Ầ': 'A', 'Ấ': 'A', 'Ậ': 'A', 'Ẩ': 'A', 'Ẫ': 'A',
      'Ă': 'A', 'Ằ': 'A', 'Ắ': 'A', 'Ặ': 'A', 'Ẳ': 'A', 'Ẵ': 'A',
      'È': 'E', 'É': 'E', 'Ẹ': 'E', 'Ẻ': 'E', 'Ẽ': 'E', 'Ê': 'E', 'Ề': 'E', 'Ế': 'E', 'Ệ': 'E', 'Ể': 'E', 'Ễ': 'E',
      'Ì': 'I', 'Í': 'I', 'Ị': 'I', 'Ỉ': 'I', 'Ĩ': 'I',
      'Ò': 'O', 'Ó': 'O', 'Ọ': 'O', 'Ỏ': 'O', 'Õ': 'O', 'Ô': 'O', 'Ồ': 'O', 'Ố': 'O', 'Ộ': 'O', 'Ổ': 'O', 'Ỗ': 'O',
      'Ơ': 'O', 'Ờ': 'O', 'Ớ': 'O', 'Ợ': 'O', 'Ở': 'O', 'Ỡ': 'O',
      'Ù': 'U', 'Ú': 'U', 'Ụ': 'U', 'Ủ': 'U', 'Ũ': 'U', 'Ư': 'U', 'Ừ': 'U', 'Ứ': 'U', 'Ự': 'U', 'Ử': 'U', 'Ữ': 'U',
      'Ỳ': 'Y', 'Ý': 'Y', 'Ỵ': 'Y', 'Ỷ': 'Y', 'Ỹ': 'Y',
      'Đ': 'D',
    };
    var out = input.trim();
    vietnamese.forEach((k, v) => out = out.replaceAll(k, v));
    return out.replaceAll(RegExp(r'\s+'), ' ');
  }

  String _titleCase(String input) {
    return input.split(' ').where((w) => w.isNotEmpty).map((w) => w[0].toUpperCase() + (w.length > 1 ? w.substring(1).toLowerCase() : '')).join(' ');
  }

  String _formatDepartment(String raw) {
    final s = _cleanNoAccent(raw).toLowerCase();
    if (s.contains('gay me')) return 'Khoa Phau Thuat Gay Me - Hoi Suc';
    if (s.contains('ngoai than kinh')) return 'Khoa Ngoai Than Kinh';
    if (s.contains('chan thuong') || s.contains('chinh hinh') || s.contains('bong')) return 'Khoa Chan Thuong Chinh Hinh - Bong';
    if (s.contains('ngoai tong hop')) return 'Khoa Ngoai Tong Hop';
    if (s.contains('noi tim mach')) return 'Khoa Noi Tim Mach';
    if (s.contains('noi tong hop')) return 'Khoa Noi Tong Hop';
    if (s.contains('ngoai tieu hoa')) return 'Khoa Ngoai Tieu Hoa';
    if (s.contains('noi tieu hoa')) return 'Khoa Noi Tieu Hoa';
    if (s.contains('noi than kinh')) return 'Khoa Noi Than Kinh';
    final res = _titleCase(_cleanNoAccent(raw));
    if (!res.toLowerCase().startsWith('khoa ') && !res.toLowerCase().startsWith('phong ')) return 'Khoa \$res';
    return res;
  }

  String _formatTitle(String raw) {
    final s = _cleanNoAccent(raw).toLowerCase().replaceAll('.', '').trim();
    if (s == 'bs' || s.contains('bac si') || s.contains('bac sy')) return 'Bac Sy Dieu Tri';
    if (s.contains('truong')) return 'Y Ta Truong/ Dieu Duong Truong';
    if (s == 'dd' || s.contains('dieu duong') || s.contains('y ta')) return 'Y ta/ Dieu duong';
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
        height: 700,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.tune_rounded, color: Color(0xFF5EEAD4)),
                const SizedBox(width: 10),
                const Expanded(child: Text('Quản lý Dữ liệu Điền Tự động', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
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
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withOpacity(0.1)),
              ),
              child: Theme(
                data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  title: const Text('Cấu hình tự điền', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                  childrenPadding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                  children: [
                    ..._fieldLabels.entries.map((entry) => Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Row(
                        children: [
                          Switch(
                            value: _enabled[entry.key] ?? true,
                            onChanged: (value) => setState(() => _enabled[entry.key] = value),
                          ),
                          Expanded(child: Text(entry.value, style: const TextStyle(fontSize: 12))),
                          SizedBox(
                            width: 82,
                            child: TextFormField(
                              key: ValueKey('delay_${entry.key}'),
                              initialValue: '${_delays[entry.key] ?? 700}',
                              enabled: _enabled[entry.key] ?? true,
                              keyboardType: TextInputType.number,
                              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                              decoration: const InputDecoration(
                                isDense: true,
                                suffixText: 'ms',
                              ),
                              onChanged: (value) => _delays[entry.key] =
                                  (int.tryParse(value) ?? 0).clamp(0, 10000).toInt(),
                            ),
                          ),
                        ],
                      ),
                    )),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _pasteController,
                  minLines: 3,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    alignLabelWithHint: true,
                    prefixIcon: Icon(Icons.paste_rounded),
                    labelText: 'Dán danh sách NOIDUNGDIEN',
                    hintText: 'VD: Phạm Thị Thu Vân - gây mê hồi sức - bs',
                  ),
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: _parsePastedData,
                  icon: const Icon(Icons.add_task_rounded),
                  label: const Text('Phân tích và Thêm'),
                )
              ],
            ),
            const SizedBox(height: 16),
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
                    return Card(
                      color: Colors.white.withOpacity(0.05),
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.white.withOpacity(0.05))),
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
                                      child: Text('${index + 1}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 11)),
                                    ),
                                    const SizedBox(width: 8),
                                    const Text('Thông tin người tham gia', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Colors.white70)),
                                  ],
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                                  onPressed: () => setState(() => _people.removeAt(index)),
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                )
                              ],
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: TextEditingController(text: p['name'])..selection = TextSelection.collapsed(offset: (p['name'] ?? '').length),
                              onChanged: (val) => p['name'] = val,
                              decoration: const InputDecoration(isDense: true, labelText: 'Họ Tên'),
                            ),
                            const SizedBox(height: 10),
                            DropdownButtonFormField<String>(
                              value: kDepartments.contains(p['department']) ? p['department'] : kDepartments.first,
                              isExpanded: true,
                              decoration: const InputDecoration(isDense: true, labelText: 'Khoa'),
                              items: kDepartments.map((d) => DropdownMenuItem(value: d, child: Text(d, style: const TextStyle(fontSize: 13)))).toList(),
                              onChanged: (val) => setState(() => p['department'] = val!),
                            ),
                            const SizedBox(height: 10),
                            DropdownButtonFormField<String>(
                              value: kTitles.contains(p['role']) ? p['role'] : kTitles.first,
                              isExpanded: true,
                              decoration: const InputDecoration(isDense: true, labelText: 'Chức Danh'),
                              items: kTitles.map((t) => DropdownMenuItem(value: t, child: Text(t, style: const TextStyle(fontSize: 13)))).toList(),
                              onChanged: (val) => setState(() => p['role'] = val!),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Hủy')),
                const SizedBox(width: 10),
                FilledButton.icon(
                  onPressed: () => Navigator.pop(context, {
                    'people': _people,
                    'enabled': _enabled,
                    'delays': _delays,
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
