import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform, Process;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_windows/webview_windows.dart' as win_web;

import 'app_preferences.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppPreferences.init();
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

  WebViewController? _webViewController;
  win_web.WebviewController? _windowsWebviewController;
  bool _isWindowsWebviewInitialized = false;
  bool _isPageLoading = false;
  String _viotpBalance = '';
  bool _isLoadingBalance = false;
  final FocusNode _urlFocusNode = FocusNode();

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
    if (Platform.isWindows) {
      _initWindowsWebview();
    } else if (WebViewPlatform.instance != null) {
      _webViewController = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setNavigationDelegate(
          NavigationDelegate(
            onPageStarted: (String url) {
              if (mounted) setState(() => _isPageLoading = true);
              _webViewController?.runJavaScript('''
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
            onPageFinished: (String url) {
              if (mounted) setState(() => _isPageLoading = false);
            },
          ),
        );
    }
    _loadPreferences();
  }

  Future<void> _initWindowsWebview() async {
    try {
      final controller = win_web.WebviewController();
      await controller.initialize();
      await controller.addScriptToExecuteOnDocumentCreated('''
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

      controller.loadingState.listen((state) {
        if (mounted) {
          setState(() {
            _isPageLoading = (state == win_web.LoadingState.loading);
          });
        }
        if (state == win_web.LoadingState.navigationCompleted) {
          controller.executeScript('''
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
        }
      });

      controller.url.listen((url) {
        if (url.isNotEmpty && url != 'about:blank' && mounted) {
          if (!_urlFocusNode.hasFocus && _urlController.text != url) {
            setState(() {
              _urlController.text = url;
            });
          }
        }
      });

      if (!mounted) {
        await controller.dispose();
        return;
      }

      setState(() {
        _windowsWebviewController = controller;
        _isWindowsWebviewInitialized = true;
      });

      final currentUrl = _urlController.text.trim();
      if (currentUrl.isNotEmpty) {
        _loadUrl(silent: true);
      }
    } catch (e) {
      debugPrint('Error initializing Windows WebView: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi khởi tạo WebView trên Windows: $e')),
        );
      }
    }
  }

  @override
  void dispose() {
    _cancelOtpTimer();
    _urlController.dispose();
    _tokenController.dispose();
    _urlFocusNode.dispose();
    _windowsWebviewController?.dispose();
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
            m['otherDepartment'] ??= '';
            if (m['department'] != null &&
                m['department']!.isNotEmpty &&
                !kDepartments.contains(m['department'])) {
              if (m['otherDepartment']!.isEmpty) {
                m['otherDepartment'] = m['department']!;
              }
              m['department'] = 'Khac';
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
    _fetchBalance();
    if (_urlController.text.isNotEmpty) {
      _loadUrl(silent: true);
    }
    _savePreferences();
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

  bool get _isWebviewAvailable {
    if (Platform.isWindows) {
      return _windowsWebviewController != null && _isWindowsWebviewInitialized;
    }
    return _webViewController != null;
  }

  Future<void> _runScriptInWeb(String script) async {
    if (Platform.isWindows) {
      if (_windowsWebviewController != null && _isWindowsWebviewInitialized) {
        await _windowsWebviewController!.executeScript(script);
      }
    } else {
      if (_webViewController != null) {
        await _webViewController!.runJavaScript(script);
      }
    }
  }

  Future<dynamic> _runScriptReturningResult(String script) async {
    if (Platform.isWindows) {
      if (_windowsWebviewController != null && _isWindowsWebviewInitialized) {
        return await _windowsWebviewController!.executeScript(script);
      }
      return null;
    } else {
      if (_webViewController != null) {
        return await _webViewController!.runJavaScriptReturningResult(script);
      }
      return null;
    }
  }

  void _loadUrl({bool silent = false}) {
    final url = _urlController.text.trim();
    if (url.isNotEmpty) {
      Uri uri = Uri.parse(url);
      if (!uri.hasScheme) {
        uri = Uri.parse('https://$url');
      }
      if (Platform.isWindows) {
        if (_windowsWebviewController != null && _isWindowsWebviewInitialized) {
          _windowsWebviewController!.loadUrl(uri.toString());
        } else if (!silent) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  'WebView trên Windows đang khởi tạo, vui lòng thử lại sau giây lát.'),
            ),
          );
        }
      } else {
        if (_webViewController != null) {
          _webViewController!.loadRequest(uri);
        } else if (!silent) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('WebView chỉ hoạt động trên Android và Windows.'),
            ),
          );
        }
      }
      _savePreferences();
    }
  }

  Future<void> _goBack() async {
    if (Platform.isWindows) {
      if (_windowsWebviewController != null && _isWindowsWebviewInitialized) {
        await _windowsWebviewController!.goBack();
      }
    } else {
      if (_webViewController != null && await _webViewController!.canGoBack()) {
        await _webViewController!.goBack();
      }
    }
  }

  Future<void> _goForward() async {
    if (Platform.isWindows) {
      if (_windowsWebviewController != null && _isWindowsWebviewInitialized) {
        await _windowsWebviewController!.goForward();
      }
    } else {
      if (_webViewController != null && await _webViewController!.canGoForward()) {
        await _webViewController!.goForward();
      }
    }
  }

  Future<void> _reloadPage() async {
    if (Platform.isWindows) {
      if (_windowsWebviewController != null && _isWindowsWebviewInitialized) {
        await _windowsWebviewController!.reload();
      }
    } else {
      if (_webViewController != null) {
        await _webViewController!.reload();
      }
    }
  }

  void _openInExternalBrowser() {
    final url = _urlController.text.trim();
    if (url.isEmpty) return;
    Uri uri = Uri.parse(url);
    if (!uri.hasScheme) {
      uri = Uri.parse('https://$url');
    }
    if (Platform.isWindows) {
      Process.run('cmd', ['/c', 'start', '', uri.toString()]);
    }
  }

  Future<void> _fetchBalance() async {
    final token = _tokenController.text.trim();
    if (token.isEmpty) return;
    setState(() => _isLoadingBalance = true);
    try {
      final url = Uri.parse('https://api.viotp.com/users/balance?token=$token');
      final res = await http.get(url).timeout(const Duration(seconds: 5));
      final json = jsonDecode(res.body);
      if (json['status_code'] == 200 && json['data'] != null) {
        final bal = json['data']['balance'];
        if (bal != null) {
          final balNum =
              (bal is num) ? bal.toInt() : int.tryParse(bal.toString()) ?? 0;
          if (mounted) {
            setState(() {
              _viotpBalance = '${_formatCurrency(balNum)} đ';
            });
          }
        }
      }
    } catch (_) {
    } finally {
      if (mounted) {
        setState(() => _isLoadingBalance = false);
      }
    }
  }

  String _formatCurrency(int value) {
    return value.toString().replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (Match m) => '${m[1]}.',
    );
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
    if (!_isWebviewAvailable) return;
    final payload = jsonEncode(data);
    await _runScriptInWeb('''
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
        fillBy(['phong ban(khac)', 'phong ban (khac)', 'phong ban khac', 'khoa khac'], data.otherDepartment);
        fillBy(['chuc danh', 'title'], data.role);
        fillBy(['vai tro', 'role'], data.attendeeRole);
      })();
    ''');
  }

  Future<void> _fillPhoneInWeb() async {
    if (!_isWebviewAvailable) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('WebView chưa sẵn sàng!')),
      );
      return;
    }
    await _fillWebFields({'phone': _currentPhoneNumber});
    await Future.delayed(const Duration(milliseconds: 500));
    final clicked = await _runScriptReturningResult('''
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
    final isClicked = clicked == true || clicked == 'true' || clicked == 1;
    if (!isClicked) {
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
        'otherDepartment': p['otherDepartment'] ?? '',
        'role': p['role'] ?? '',
        'attendeeRole': 'Nguoi tham du',
        'hospital': hospitalToFill,
      },
      'enabled': _fillEnabled,
      'delays': _fillDelayMs,
    });

    if (!_isWebviewAvailable) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('WebView chưa sẵn sàng!')),
      );
      return;
    }
    await _runScriptInWeb('''
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
          txt += ' ' + (el.placeholder || '') + ' ' + (el.name || '') + ' ' + (el.id || '') + ' ' + (el.getAttribute('aria-label') || '');
          return norm(txt);
        }
        
        function setVal(el, val) {
          if (!el || val == null || val === '') return false;
          try {
            const proto = el instanceof HTMLTextAreaElement ? window.HTMLTextAreaElement.prototype : window.HTMLInputElement.prototype;
            const setter = Object.getOwnPropertyDescriptor(proto, 'value')?.set;
            if (setter) {
              setter.call(el, val);
            } else {
              el.value = val;
            }
          } catch (_) {
            el.value = val;
          }
          el.focus();
          el.dispatchEvent(new Event('input', {bubbles: true}));
          el.dispatchEvent(new Event('change', {bubbles: true}));
          return true;
        }

        const delay = ms => new Promise(r => setTimeout(r, ms));

        // 1. Fill Name
        if (enabled.name) {
          const freshInputs = Array.from(document.querySelectorAll('input, textarea'));
          const nameInput = freshInputs.find(i => ['ho va ten', 'ho ten', 'name'].some(k => labelOf(i).includes(k)));
          if (nameInput) {
            setVal(nameInput, data.name);
            await delay(stepDelay('name'));
          }
        }

        // Helper to fill Element UI dropdown. fallbackIndex follows the form order:
        // Vai trò, Bệnh viện, Phòng ban/Khoa, Chức danh.
        async function fillDropdown(keywords, targetVal, fallbackIndex, waitMs, excludedKeywords = []) {
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
          const input = selectInputs.find(el => {
            const lbl = dropdownLabel(el);
            return keywords.some(k => lbl.includes(k)) &&
                   !excludedKeywords.some(ex => lbl.includes(ex));
          }) || selectInputs[fallbackIndex];
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
          const deptVal = (data.department || '').trim();
          await fillDropdown(['phong ban', 'khoa', 'department'], deptVal, 2, stepDelay('department'), ['khac', 'other']);

          // If department is 'Khac' (or contains 'khac') or otherDepartment has value:
          if (norm(deptVal) === 'khac' || norm(deptVal).includes('khac') || data.otherDepartment) {
            await delay(Math.max(300, Math.floor(stepDelay('department') / 2)));

            let otherInput = null;
            for (let attempt = 0; attempt < 8; attempt++) {
              const freshInputs = Array.from(document.querySelectorAll('input, textarea'));
              otherInput = freshInputs.find(i => {
                if (i.closest('.el-select') || i.getAttribute('role') === 'combobox' || i.readOnly) return false;
                const lbl = labelOf(i);
                return (
                  lbl.includes('phong ban(khac)') ||
                  lbl.includes('phong ban (khac)') ||
                  lbl.includes('phong ban khac') ||
                  (lbl.includes('phong ban') && lbl.includes('khac')) ||
                  (lbl.includes('khoa') && lbl.includes('khac')) ||
                  (lbl.includes('department') && lbl.includes('other'))
                ) && !['vai tro', 'benh vien', 'chuc danh'].some(k => lbl.includes(k));
              });
              if (otherInput) break;
              await delay(150);
            }

            const otherVal = (data.otherDepartment || '').trim() ||
                             (norm(deptVal) !== 'khac' ? deptVal : '');
            if (otherInput && otherVal) {
              setVal(otherInput, otherVal);
              await delay(stepDelay('department'));
            }
          }
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
    if (!_isWebviewAvailable) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('WebView chưa sẵn sàng!')),
      );
      return;
    }
    await _runScriptInWeb('''
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
    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.f5) {
            _reloadPage();
            return KeyEventResult.handled;
          }
          if (HardwareKeyboard.instance.isAltPressed) {
            if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
              _goBack();
              return KeyEventResult.handled;
            } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
              _goForward();
              return KeyEventResult.handled;
            } else if (event.logicalKey == LogicalKeyboardKey.keyN) {
              if (_people.isNotEmpty) {
                setState(() {
                  _currentPersonIndex =
                      (_currentPersonIndex + 1) % _people.length;
                });
              }
              return KeyEventResult.handled;
            } else if (event.logicalKey == LogicalKeyboardKey.keyP) {
              if (_people.isNotEmpty) {
                setState(() {
                  _currentPersonIndex = _currentPersonIndex > 0
                      ? _currentPersonIndex - 1
                      : _people.length - 1;
                });
              }
              return KeyEventResult.handled;
            } else if (event.logicalKey == LogicalKeyboardKey.keyF) {
              _fillCurrentPersonInWeb();
              return KeyEventResult.handled;
            }
          }
        }
        return KeyEventResult.ignored;
      },
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isDesktop = constraints.maxWidth >= 850;
          return Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF07111F), Color(0xFF102033), Color(0xFF08111E)],
              ),
            ),
            child: isDesktop
                ? _buildDesktopLayout()
                : SafeArea(child: _buildMobileLayout()),
          );
        },
      ),
    );
  }

  Widget _buildDesktopLayout() {
    return Row(
      children: [
        // Sidebar (400px)
        Container(
          width: 400,
          decoration: BoxDecoration(
            color: const Color(0xFF0C1524),
            border: Border(
              right: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
            ),
          ),
          child: Column(
            children: [
              _buildDesktopSidebarHeader(),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildAttendeeCard(isDesktop: true),
                      const SizedBox(height: 10),
                      _buildPhoneAndOtpCard(isDesktop: true),
                      const SizedBox(height: 10),
                      _buildHospitalAndSubmitCard(isDesktop: true),
                      const SizedBox(height: 10),
                      _buildQuickCopySection(),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        // Main Web Area
        Expanded(
          child: Column(
            children: [
              _buildDesktopBrowserBar(),
              if (_isPageLoading)
                const LinearProgressIndicator(
                  minHeight: 2.5,
                  color: Color(0xFF5EEAD4),
                  backgroundColor: Colors.transparent,
                ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: ColoredBox(
                      color: Colors.white,
                      child: _buildWebViewWidget(),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDesktopSidebarHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.2),
        border: Border(
          bottom: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF5EEAD4), Color(0xFF38BDF8)],
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.flash_on_rounded,
                size: 16, color: Color(0xFF06211D)),
          ),
          const SizedBox(width: 8),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Abbott Helper',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    letterSpacing: .3,
                    color: Colors.white,
                  ),
                ),
                Text(
                  'Trợ lý đăng ký sự kiện',
                  style: TextStyle(fontSize: 10, color: Colors.white54),
                ),
              ],
            ),
          ),
          // ViOTP Balance badge
          InkWell(
            onTap: _isLoadingBalance ? null : _fetchBalance,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF5EEAD4).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: const Color(0xFF5EEAD4).withValues(alpha: 0.3)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_isLoadingBalance)
                    const SizedBox(
                      width: 10,
                      height: 10,
                      child: CircularProgressIndicator(
                          strokeWidth: 1.5, color: Color(0xFF5EEAD4)),
                    )
                  else
                    const Icon(Icons.account_balance_wallet_rounded,
                        size: 12, color: Color(0xFF5EEAD4)),
                  const SizedBox(width: 4),
                  Text(
                    _viotpBalance.isNotEmpty ? _viotpBalance : 'Số dư ViOTP',
                    style: const TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF5EEAD4),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 6),
          IconButton.filledTonal(
            tooltip: 'Cài đặt (Token, DS Người, Bệnh viện)',
            iconSize: 17,
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.tune_rounded),
            onPressed: () => _showSettingsDialog(),
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopBrowserBar() {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF0C1524),
        border: Border(
          bottom: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Quay lại (Alt+Left)',
            iconSize: 18,
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.arrow_back_rounded, color: Colors.white70),
            onPressed: _goBack,
          ),
          IconButton(
            tooltip: 'Tiến tới (Alt+Right)',
            iconSize: 18,
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.arrow_forward_rounded, color: Colors.white70),
            onPressed: _goForward,
          ),
          IconButton(
            tooltip: 'Tải lại (F5)',
            iconSize: 18,
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.refresh_rounded, color: Colors.white70),
            onPressed: _reloadPage,
          ),
          const SizedBox(width: 6),
          // Address Input Bar
          Expanded(
            child: Container(
              height: 36,
              padding: const EdgeInsets.fromLTRB(10, 0, 4, 0),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.link_rounded,
                      size: 16, color: Color(0xFF5EEAD4)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _urlController,
                      focusNode: _urlFocusNode,
                      style: const TextStyle(fontSize: 12.5),
                      decoration: const InputDecoration(
                        isDense: true,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        fillColor: Colors.transparent,
                        filled: false,
                        hintText: 'Dán link trang đăng ký Abbott...',
                        hintStyle:
                            TextStyle(fontSize: 12, color: Colors.white38),
                        contentPadding: EdgeInsets.zero,
                      ),
                      onSubmitted: (_) => _loadUrl(),
                    ),
                  ),
                  if (_urlController.text.isNotEmpty)
                    IconButton(
                      icon: const Icon(Icons.clear_rounded,
                          size: 14, color: Colors.white38),
                      visualDensity: VisualDensity.compact,
                      onPressed: () {
                        setState(() => _urlController.clear());
                      },
                    ),
                  FilledButton(
                    onPressed: _loadUrl,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(48, 28),
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(7)),
                    ),
                    child: const Text('Mở',
                        style: TextStyle(
                            fontSize: 11.5, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 6),
          IconButton.filledTonal(
            tooltip: 'Mở bằng trình duyệt ngoài (Chrome/Edge)',
            iconSize: 18,
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.open_in_browser_rounded),
            onPressed: _openInExternalBrowser,
          ),
        ],
      ),
    );
  }

  Widget _buildMobileLayout() {
    return Scaffold(
      backgroundColor: Colors.transparent,
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
          if (_viotpBalance.isNotEmpty)
            InkWell(
              onTap: _fetchBalance,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                margin: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF5EEAD4).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: const Color(0xFF5EEAD4).withValues(alpha: 0.3)),
                ),
                child: Text(
                  _viotpBalance,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF5EEAD4),
                  ),
                ),
              ),
            ),
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
      body: Column(
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
          if (_isPageLoading)
            const LinearProgressIndicator(
              minHeight: 2,
              color: Color(0xFF5EEAD4),
              backgroundColor: Colors.transparent,
            ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: ColoredBox(
                  color: Colors.white,
                  child: _buildWebViewWidget(),
                ),
              ),
            ),
          ),
          _buildControlPanel(),
        ],
      ),
    );
  }

  Widget _buildWebViewWidget() {
    if (Platform.isWindows) {
      if (_isWindowsWebviewInitialized && _windowsWebviewController != null) {
        return win_web.Webview(_windowsWebviewController!);
      } else {
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(
                width: 32,
                height: 32,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  color: Color(0xFF5EEAD4),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Đang khởi tạo WebView Windows...',
                style: TextStyle(
                  color: Colors.grey.shade700,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        );
      }
    } else if (_webViewController != null) {
      return WebViewWidget(controller: _webViewController!);
    } else {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.devices, size: 48, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            const Text(
              'WebView nhúng chỉ hoạt động trên Android & Windows.',
              style: TextStyle(
                color: Colors.black87,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Bạn có thể copy số, OTP và dùng trình duyệt bên ngoài.',
              style: TextStyle(
                color: Colors.grey.shade600,
                fontSize: 12,
              ),
            ),
          ],
        ),
      );
    }
  }

  BoxDecoration _glassDecoration({double radius = 24}) {
    return BoxDecoration(
      color: Colors.white.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.28),
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
          color: Colors.black.withValues(alpha: 0.22),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
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

  Widget _infoTag(IconData icon, String text, Color color) {
    return Container(
      height: 22,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.32)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _quickCopyChip(
      String label, String value, IconData icon, Color color) {
    final hasVal = value.trim().isNotEmpty;
    return InkWell(
      onTap: hasVal ? () => _copy(value, label) : null,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: hasVal
              ? color.withValues(alpha: 0.12)
              : Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: hasVal
                ? color.withValues(alpha: 0.35)
                : Colors.white.withValues(alpha: 0.08),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: hasVal ? color : Colors.white38),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: hasVal ? color : Colors.white38,
              ),
            ),
            if (hasVal) ...[
              const SizedBox(width: 4),
              Icon(Icons.copy_rounded,
                  size: 10, color: color.withValues(alpha: 0.7)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildQuickCopySection() {
    final hasPerson = _people.isNotEmpty;
    final current = hasPerson ? _people[_currentPersonIndex] : null;
    final dept = current?['department'] == 'Khac'
        ? (current?['otherDepartment'] ?? '')
        : (current?['department'] ?? '');

    return Container(
      padding: const EdgeInsets.all(9),
      decoration: _glassDecoration(radius: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.content_copy_rounded,
                  size: 13, color: Color(0xFF5EEAD4)),
              SizedBox(width: 6),
              Text(
                'Sao chép nhanh 1-chạm',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _quickCopyChip('Họ tên', current?['name'] ?? '',
                  Icons.person_outline, const Color(0xFF5EEAD4)),
              _quickCopyChip('SĐT', _currentPhoneNumber, Icons.phone_rounded,
                  const Color(0xFF93C5FD)),
              _quickCopyChip('OTP', _currentOtp, Icons.password_rounded,
                  const Color(0xFFFDE047)),
              _quickCopyChip(
                  'BV',
                  (current?['hospital'] ?? '').isNotEmpty
                      ? current!['hospital']!
                      : _selectedHospital,
                  Icons.local_hospital_outlined,
                  const Color(0xFF67E8F9)),
              _quickCopyChip('Khoa', dept, Icons.domain_rounded,
                  const Color(0xFFA7F3D0)),
              _quickCopyChip('Chức danh', current?['role'] ?? '',
                  Icons.badge_outlined, const Color(0xFFF0ABFC)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAttendeeCard({required bool isDesktop}) {
    if (_people.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: _glassDecoration(radius: 14),
        child: Column(
          children: [
            const Icon(Icons.people_outline_rounded,
                size: 32, color: Colors.white38),
            const SizedBox(height: 6),
            const Text(
              'Chưa có dữ liệu người tham dự',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.white70),
            ),
            const SizedBox(height: 3),
            const Text(
              'Bấm nút bên dưới để dán danh sách',
              style: TextStyle(fontSize: 11, color: Colors.white38),
            ),
            const SizedBox(height: 8),
            FilledButton.tonalIcon(
              onPressed: () => _showSettingsDialog(),
              icon: const Icon(Icons.add_rounded, size: 16),
              label: const Text('Nhập danh sách ngay',
                  style: TextStyle(
                      fontSize: 11.5, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );
    }

    final current = _people[_currentPersonIndex];
    final hosp = (current['hospital'] ?? '').trim().isNotEmpty
        ? current['hospital']!.trim()
        : _selectedHospital;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF5EEAD4).withValues(alpha: 0.14),
            const Color(0xFFF0ABFC).withValues(alpha: 0.08),
          ],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              InkWell(
                onTap: _showPersonSelectionSheet,
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
                  decoration: BoxDecoration(
                    color: const Color(0xFF5EEAD4),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '#${_currentPersonIndex + 1}/${_people.length}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 10,
                          color: Color(0xFF06211D),
                        ),
                      ),
                      const SizedBox(width: 2),
                      const Icon(Icons.arrow_drop_down,
                          size: 13, color: Color(0xFF06211D)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  current['name'] ?? '',
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 13.5,
                    color: Colors.white,
                    height: 1.15,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 4),
              IconButton.filledTonal(
                tooltip: 'Điền người này vào Web (Alt+F)',
                visualDensity: VisualDensity.compact,
                iconSize: 15,
                padding: EdgeInsets.zero,
                constraints:
                    const BoxConstraints(minWidth: 28, minHeight: 28),
                style: IconButton.styleFrom(
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(7)),
                ),
                icon: const Icon(Icons.auto_fix_high_rounded),
                onPressed: _fillCurrentPersonInWeb,
              ),
              const SizedBox(width: 4),
              IconButton.filledTonal(
                tooltip: 'Người trước (Alt+P)',
                visualDensity: VisualDensity.compact,
                iconSize: 15,
                padding: EdgeInsets.zero,
                constraints:
                    const BoxConstraints(minWidth: 28, minHeight: 28),
                style: IconButton.styleFrom(
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(7)),
                ),
                icon: const Icon(Icons.navigate_before_rounded),
                onPressed: () {
                  setState(() {
                    _currentPersonIndex = _currentPersonIndex > 0
                        ? _currentPersonIndex - 1
                        : _people.length - 1;
                  });
                },
              ),
              const SizedBox(width: 4),
              IconButton.filled(
                tooltip: 'Người tiếp theo (Alt+N)',
                visualDensity: VisualDensity.compact,
                iconSize: 15,
                padding: EdgeInsets.zero,
                constraints:
                    const BoxConstraints(minWidth: 28, minHeight: 28),
                style: IconButton.styleFrom(
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(7)),
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
          const SizedBox(height: 7),
          Wrap(
            spacing: 5,
            runSpacing: 4,
            children: [
              _infoTag(
                Icons.badge_outlined,
                current['role'] ?? 'Chức vụ',
                const Color(0xFFF0ABFC),
              ),
              _infoTag(
                Icons.domain_rounded,
                current['department'] == 'Khac' &&
                        (current['otherDepartment'] ?? '').trim().isNotEmpty
                    ? 'Khác: ${current['otherDepartment']!.trim()}'
                    : (current['department'] ?? 'Khoa'),
                const Color(0xFF5EEAD4),
              ),
              _infoTag(
                Icons.local_hospital_rounded,
                hosp,
                const Color(0xFF93C5FD),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPhoneAndOtpCard({required bool isDesktop}) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: _glassDecoration(radius: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. Phone row
          Row(
            children: [
              FilledButton(
                onPressed: (_isGettingPhone || _isLoadingService)
                    ? null
                    : _getPhoneNumber,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(64, 32),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _loadingIcon(_isGettingPhone || _isLoadingService,
                        Icons.phone_android_rounded),
                    const SizedBox(width: 4),
                    const Text('Lấy Số',
                        style: TextStyle(
                            fontSize: 11.5, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
              const SizedBox(width: 6),
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
              const SizedBox(width: 6),
              IconButton.filledTonal(
                tooltip: 'Điền SĐT vào Web',
                visualDensity: VisualDensity.compact,
                iconSize: 16,
                padding: EdgeInsets.zero,
                constraints:
                    const BoxConstraints(minWidth: 34, minHeight: 32),
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
          const SizedBox(height: 7),
          // 2. OTP row
          Row(
            children: [
              FilledButton(
                onPressed: _isGettingOtp ? _cancelOtpWaiting : _getOtp,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(64, 32),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  backgroundColor:
                      _isGettingOtp ? Colors.orange.shade800 : null,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _loadingIcon(_isGettingOtp, Icons.mark_email_read_rounded),
                    const SizedBox(width: 4),
                    Text(_isGettingOtp ? 'Dừng' : 'Lấy OTP',
                        style: const TextStyle(
                            fontSize: 11.5, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _valuePill(
                  _currentOtp,
                  _otpStatusText.isNotEmpty ? _otpStatusText : 'Mã OTP...',
                  Icons.password_rounded,
                  _currentOtp.isEmpty ? null : () => _copy(_currentOtp, 'OTP'),
                ),
              ),
              const SizedBox(width: 6),
              IconButton.filledTonal(
                tooltip: 'Điền OTP vào Web',
                visualDensity: VisualDensity.compact,
                iconSize: 16,
                padding: EdgeInsets.zero,
                constraints:
                    const BoxConstraints(minWidth: 34, minHeight: 32),
                style: IconButton.styleFrom(
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                icon: const Icon(Icons.content_paste_go_rounded),
                onPressed: _currentOtp.isEmpty ? null : _fillOtpInWeb,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHospitalAndSubmitCard({required bool isDesktop}) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: _glassDecoration(radius: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Hospital selector row
          Row(
            children: [
              Expanded(
                child: Container(
                  height: 32,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: Colors.white.withValues(alpha: 0.1)),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _hospitals.contains(_selectedHospital)
                          ? _selectedHospital
                          : (_hospitals.isNotEmpty ? _hospitals.first : null),
                      isExpanded: true,
                      icon: const Icon(Icons.arrow_drop_down,
                          size: 18, color: Color(0xFF5EEAD4)),
                      dropdownColor: const Color(0xFF101827),
                      style: const TextStyle(
                          fontSize: 11.5,
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
              const SizedBox(width: 6),
              IconButton.filledTonal(
                tooltip: 'Gán BV này cho TẤT CẢ người trong danh sách',
                visualDensity: VisualDensity.compact,
                iconSize: 16,
                padding: EdgeInsets.zero,
                constraints:
                    const BoxConstraints(minWidth: 34, minHeight: 32),
                style: IconButton.styleFrom(
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                icon: const Icon(Icons.done_all_rounded,
                    color: Color(0xFF5EEAD4)),
                onPressed:
                    _people.isEmpty ? null : () => _applyHospitalToAll(),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Action buttons
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 34,
                  child: FilledButton.icon(
                    onPressed: _people.isEmpty ? null : _fillCurrentPersonInWeb,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF5EEAD4),
                      foregroundColor: const Color(0xFF06211D),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                      padding: EdgeInsets.zero,
                    ),
                    icon: const Icon(Icons.auto_fix_high_rounded, size: 14),
                    label: const Text(
                      'Điền Thông Tin',
                      style:
                          TextStyle(fontWeight: FontWeight.w900, fontSize: 11.5),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SizedBox(
                  height: 34,
                  child: FilledButton.icon(
                    onPressed: _submitFormInWeb,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFF0ABFC),
                      foregroundColor: const Color(0xFF1E0824),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                      padding: EdgeInsets.zero,
                    ),
                    icon: const Icon(Icons.send_rounded, size: 13),
                    label: const Text(
                      'Gửi Form',
                      style:
                          TextStyle(fontWeight: FontWeight.w900, fontSize: 11.5),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPersonSelectionContent(BuildContext ctx) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          margin: const EdgeInsets.only(top: 8, bottom: 4),
          width: 36,
          height: 4,
          decoration: BoxDecoration(
            color: Colors.white24,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Danh sách người tham gia (${_people.length})',
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.bold),
              ),
              Text(
                'Đang chọn: #${_currentPersonIndex + 1}',
                style: const TextStyle(
                    fontSize: 12, color: Color(0xFF5EEAD4)),
              ),
            ],
          ),
        ),
        const Divider(height: 1, color: Colors.white12),
        Flexible(
          child: ListView.separated(
            shrinkWrap: true,
            padding: const EdgeInsets.symmetric(vertical: 4),
            itemCount: _people.length,
            separatorBuilder: (_, __) =>
                const Divider(height: 1, color: Colors.white10),
            itemBuilder: (context, index) {
              final p = _people[index];
              final isSelected = index == _currentPersonIndex;
              final hosp = (p['hospital'] ?? '').trim().isNotEmpty
                  ? p['hospital']!.trim()
                  : _selectedHospital;

              return ListTile(
                dense: true,
                selected: isSelected,
                selectedTileColor:
                    const Color(0xFF5EEAD4).withValues(alpha: 0.12),
                leading: CircleAvatar(
                  radius: 12,
                  backgroundColor: isSelected
                      ? const Color(0xFF5EEAD4)
                      : Colors.white.withValues(alpha: 0.1),
                  foregroundColor:
                      isSelected ? const Color(0xFF06211D) : Colors.white70,
                  child: Text(
                    '${index + 1}',
                    style: const TextStyle(
                        fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                ),
                title: Text(
                  p['name'] ?? '',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight:
                        isSelected ? FontWeight.bold : FontWeight.w600,
                    color:
                        isSelected ? const Color(0xFF5EEAD4) : Colors.white,
                  ),
                ),
                subtitle: Text(
                  '${p['role'] ?? 'Chức danh'} • ${p['department'] == 'Khac' && (p['otherDepartment'] ?? '').trim().isNotEmpty ? 'Khác: ${p['otherDepartment']!.trim()}' : (p['department'] ?? 'Khoa')}\n$hosp',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.white.withValues(alpha: 0.65),
                  ),
                ),
                trailing: isSelected
                    ? const Icon(Icons.check_circle_rounded,
                        color: Color(0xFF5EEAD4), size: 18)
                    : null,
                onTap: () {
                  setState(() => _currentPersonIndex = index);
                  Navigator.pop(ctx);
                },
              );
            },
          ),
        ),
      ],
    );
  }

  void _showPersonSelectionSheet() {
    if (_people.isEmpty) return;
    final isDesktop = MediaQuery.of(context).size.width >= 850;
    if (isDesktop) {
      showDialog(
        context: context,
        builder: (ctx) => Dialog(
          backgroundColor: const Color(0xFF101827),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480, maxHeight: 580),
            child: _buildPersonSelectionContent(ctx),
          ),
        ),
      );
    } else {
      showModalBottomSheet(
        context: context,
        backgroundColor: const Color(0xFF101827),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        builder: (ctx) => SafeArea(
          child: _buildPersonSelectionContent(ctx),
        ),
      );
    }
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
    return Container(
      margin: const EdgeInsets.fromLTRB(10, 2, 10, 6),
      padding: const EdgeInsets.all(7),
      decoration: _glassDecoration(radius: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildPhoneAndOtpCard(isDesktop: false),
          const SizedBox(height: 4),
          _buildHospitalAndSubmitCard(isDesktop: false),
          const SizedBox(height: 4),
          _buildAttendeeCard(isDesktop: false),
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
      _fetchBalance();
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
      final parts = line.split('-').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
      if (parts.length >= 2) {
        final name = parts[0];
        String rawDepartment = parts[1];
        String rawRole = '';
        String rawHospital = '';
        String otherDept = '';

        final s1 = _cleanNoAccent(rawDepartment).toLowerCase();
        if ((s1 == 'khac' || s1 == 'khoa khac') && parts.length >= 4) {
          final s2Role = _cleanNoAccent(parts[2]).toLowerCase();
          final isPart2Role = s2Role == 'bs' ||
              s2Role.contains('bac si') ||
              s2Role.contains('bac sy') ||
              s2Role.contains('truong') ||
              s2Role.contains('dieu duong') ||
              s2Role.contains('y ta') ||
              s2Role.contains('duoc') ||
              kTitles.contains(_formatTitle(parts[2]));
          if (!isPart2Role) {
            otherDept = parts[2];
            rawRole = parts.length > 3 ? parts[3] : '';
            rawHospital = parts.length > 4 ? parts[4] : '';
          } else {
            rawRole = parts[2];
            rawHospital = parts.length > 3 ? parts[3] : '';
          }
        } else {
          rawRole = parts.length > 2 ? parts[2] : '';
          rawHospital = parts.length > 3 ? parts[3] : '';
        }

        String guessDept = _formatDepartment(rawDepartment);
        if (guessDept == 'Khac') {
          if (otherDept.isEmpty && s1 != 'khac' && s1 != 'khoa khac') {
            otherDept = rawDepartment;
          }
        } else if (!kDepartments.contains(guessDept)) {
          otherDept = rawDepartment;
          guessDept = 'Khac';
        }

        String guessRole = _formatTitle(rawRole);
        if (!kTitles.contains(guessRole)) guessRole = kTitles.first;

        String guessHospital =
            rawHospital.isNotEmpty ? rawHospital : _selectedHospital;
        if (!_hospitals.contains(guessHospital)) {
          _hospitals.add(guessHospital);
        }

        _people.add({
          'name': name,
          'department': guessDept,
          'otherDepartment': otherDept,
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
    if (s == 'khac' ||
        s == 'khoa khac' ||
        s == 'phong ban khac' ||
        s == 'phong khac') return 'Khac';
    for (final d in kDepartments) {
      if (_cleanNoAccent(d).toLowerCase() == s) return d;
    }
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
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: 860,
          maxHeight: 720,
        ),
        child: DefaultTabController(
          length: 3,
          child: Container(
            width: double.maxFinite,
            height: 720,
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                children: [
                  const Icon(Icons.tune_rounded,
                      color: Color(0xFF5EEAD4), size: 22),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Quản lý Cài đặt & Dữ liệu',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded,
                        size: 20, color: Colors.white60),
                    onPressed: () => Navigator.pop(context),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // TabBar chia 3 tab rõ ràng, không bị chiếm chỗ
              Container(
                height: 38,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: TabBar(
                  indicatorSize: TabBarIndicatorSize.tab,
                  indicator: BoxDecoration(
                    color: const Color(0xFF5EEAD4),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  labelColor: const Color(0xFF06211D),
                  unselectedLabelColor: Colors.white70,
                  labelStyle:
                      const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  unselectedLabelStyle: const TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w600),
                  tabs: [
                    Tab(text: 'DS Người (${_people.length})'),
                    const Tab(text: 'Bệnh Viện'),
                    const Tab(text: 'Cấu Hình'),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              // TabBarView
              Expanded(
                child: TabBarView(
                  children: [
                    // TAB 1: DANH SÁCH NGƯỜI (TỐI ƯU TOÀN DIỆN DIỆN TÍCH)
                    _buildPeopleTab(),

                    // TAB 2: QUẢN LÝ BỆNH VIỆN & PROFILE
                    _buildHospitalsTab(),

                    // TAB 3: CẤU HÌNH VIOTP & TỰ ĐIỀN
                    _buildConfigTab(),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              // Footer
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Hủy'),
                  ),
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
                    icon: const Icon(Icons.save_rounded, size: 18),
                    label: const Text('Lưu Thay Đổi'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

  Widget _buildPeopleTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Khối dán danh sách compact
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.04),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white.withOpacity(0.08)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _pasteController,
                minLines: 1,
                maxLines: 2,
                style: const TextStyle(fontSize: 12),
                decoration: const InputDecoration(
                  isDense: true,
                  prefixIcon: Icon(Icons.paste_rounded, size: 18),
                  labelText: 'Dán danh sách NOIDUNGDIEN',
                  hintText: 'VD: Họ tên - Khoa - Chức danh [- Bệnh viện]',
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _parsePastedData,
                      style: FilledButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                      ),
                      icon: const Icon(Icons.add_task_rounded, size: 16),
                      label: const Text('Phân tích & Thêm vào DS',
                          style: TextStyle(
                              fontSize: 12, fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: () {
                      setState(() {
                        _people.insert(0, {
                          'name': '',
                          'department': kDepartments.first,
                          'otherDepartment': '',
                          'role': kTitles.first,
                          'hospital': _selectedHospital,
                        });
                      });
                    },
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    icon: const Icon(Icons.person_add_alt_1_rounded, size: 16),
                    label: const Text('+ Thêm người',
                        style: TextStyle(fontSize: 11)),
                  ),
                  if (_people.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: () {
                        setState(() => _people.clear());
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text('Đã xóa toàn bộ danh sách!')),
                        );
                      },
                      style: OutlinedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        foregroundColor: Colors.redAccent,
                        side: const BorderSide(color: Colors.redAccent),
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                      icon: const Icon(Icons.delete_sweep_rounded, size: 16),
                      label: const Text('Xóa hết',
                          style: TextStyle(fontSize: 11)),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        // Danh sách người tham gia (Chiếm trọn vẹn toàn bộ diện tích còn lại)
        Expanded(
          child: _people.isEmpty
              ? Container(
                  alignment: Alignment.center,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.white.withOpacity(0.08)),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.group_off_rounded,
                          size: 40, color: Colors.white.withOpacity(0.3)),
                      const SizedBox(height: 8),
                      const Text(
                        'Chưa có người nào trong danh sách',
                        style: TextStyle(fontSize: 13, color: Colors.white70),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Dán nội dung vào ô trên và bấm "Phân tích & Thêm"',
                        style: TextStyle(
                            fontSize: 11, color: Colors.white.withOpacity(0.4)),
                      ),
                    ],
                  ),
                )
              : Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.white.withOpacity(0.1)),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: ListView.builder(
                    padding: const EdgeInsets.all(6),
                    itemCount: _people.length,
                    itemBuilder: (context, index) {
                      final p = _people[index];
                      final currentHosp = (p['hospital'] != null &&
                              _hospitals.contains(p['hospital']!.trim()))
                          ? p['hospital']!.trim()
                          : _selectedHospital;

                      return Card(
                        color: Colors.white.withOpacity(0.04),
                        margin: const EdgeInsets.only(bottom: 6),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                          side: BorderSide(
                              color: Colors.white.withOpacity(0.07)),
                        ),
                        elevation: 0,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // Dòng 1: STT + Tên người + Xóa
                              Row(
                                children: [
                                  CircleAvatar(
                                    radius: 10,
                                    backgroundColor: const Color(0xFF5EEAD4),
                                    foregroundColor: const Color(0xFF06211D),
                                    child: Text('${index + 1}',
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w900,
                                            fontSize: 9.5)),
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: TextFormField(
                                      initialValue: p['name'],
                                      onChanged: (val) => p['name'] = val,
                                      style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.bold),
                                      decoration: const InputDecoration(
                                        isDense: true,
                                        hintText: 'Họ và Tên...',
                                        contentPadding: EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 6),
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline,
                                        color: Colors.redAccent, size: 18),
                                    onPressed: () =>
                                        setState(() => _people.removeAt(index)),
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(
                                        minWidth: 28, minHeight: 28),
                                  )
                                ],
                              ),
                              const SizedBox(height: 5),
                              // Dòng 2: Khoa + Chức Danh (Ngang nhau gọn gàng)
                              Row(
                                children: [
                                  Expanded(
                                    flex: 5,
                                    child: DropdownButtonFormField<String>(
                                      value:
                                          kDepartments.contains(p['department'])
                                              ? p['department']
                                              : kDepartments.first,
                                      isExpanded: true,
                                      decoration: const InputDecoration(
                                        isDense: true,
                                        labelText: 'Khoa',
                                        contentPadding: EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 6),
                                      ),
                                      style: const TextStyle(
                                          fontSize: 11, color: Colors.white),
                                      items: kDepartments
                                          .map((d) => DropdownMenuItem(
                                              value: d,
                                              child: Text(d,
                                                  style: const TextStyle(
                                                      fontSize: 11),
                                                  overflow:
                                                      TextOverflow.ellipsis)))
                                          .toList(),
                                      onChanged: (val) => setState(
                                          () => p['department'] = val!),
                                    ),
                                  ),
                                  const SizedBox(width: 5),
                                  Expanded(
                                    flex: 4,
                                    child: DropdownButtonFormField<String>(
                                      value: kTitles.contains(p['role'])
                                          ? p['role']
                                          : kTitles.first,
                                      isExpanded: true,
                                      decoration: const InputDecoration(
                                        isDense: true,
                                        labelText: 'Chức Danh',
                                        contentPadding: EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 6),
                                      ),
                                      style: const TextStyle(
                                          fontSize: 11, color: Colors.white),
                                      items: kTitles
                                          .map((t) => DropdownMenuItem(
                                              value: t,
                                              child: Text(t,
                                                  style: const TextStyle(
                                                      fontSize: 11),
                                                  overflow:
                                                      TextOverflow.ellipsis)))
                                          .toList(),
                                      onChanged: (val) =>
                                          setState(() => p['role'] = val!),
                                    ),
                                  ),
                                ],
                              ),
                              if (p['department'] == 'Khac') ...[
                                const SizedBox(height: 5),
                                TextFormField(
                                  key: ValueKey('other_dept_$index'),
                                  initialValue: p['otherDepartment'] ?? '',
                                  onChanged: (val) =>
                                      p['otherDepartment'] = val,
                                  style: const TextStyle(
                                      fontSize: 11, color: Colors.white),
                                  decoration: InputDecoration(
                                    isDense: true,
                                    labelText: 'Phòng ban(Khác)',
                                    labelStyle: const TextStyle(
                                        fontSize: 11,
                                        color: Color(0xFF5EEAD4),
                                        fontWeight: FontWeight.bold),
                                    hintText:
                                        'Nhập phòng ban khác (VD: Khoa nhi)...',
                                    hintStyle: TextStyle(
                                        fontSize: 10.5,
                                        color: Colors.white.withOpacity(0.35)),
                                    prefixIcon: const Icon(
                                        Icons.edit_note_rounded,
                                        size: 16,
                                        color: Color(0xFF5EEAD4)),
                                    contentPadding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 6),
                                  ),
                                ),
                              ],
                              const SizedBox(height: 5),
                              // Dòng 3: Bệnh Viện
                              DropdownButtonFormField<String>(
                                value: currentHosp,
                                isExpanded: true,
                                decoration: const InputDecoration(
                                  isDense: true,
                                  labelText: 'Bệnh Viện',
                                  prefixIcon: Icon(
                                      Icons.local_hospital_outlined,
                                      size: 14),
                                  contentPadding: EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 6),
                                ),
                                style: const TextStyle(
                                    fontSize: 11, color: Colors.white),
                                items: _hospitals
                                    .map((h) => DropdownMenuItem(
                                        value: h,
                                        child: Text(h,
                                            style:
                                                const TextStyle(fontSize: 11),
                                            overflow: TextOverflow.ellipsis)))
                                    .toList(),
                                onChanged: (val) {
                                  if (val != null) {
                                    setState(() => p['hospital'] = val);
                                  }
                                },
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildHospitalsTab() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.04),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white.withOpacity(0.08)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Bệnh viện chung / mặc định',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF5EEAD4)),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: _hospitals.contains(_selectedHospital)
                      ? _selectedHospital
                      : _hospitals.first,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Chọn Bệnh viện mặc định',
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
                const SizedBox(height: 10),
                FilledButton.tonalIcon(
                  onPressed: _people.isEmpty
                      ? null
                      : () => _applyHospitalToAll(_selectedHospital),
                  icon: const Icon(Icons.done_all_rounded, size: 16),
                  label: Text(
                    'Gán BV này cho TẤT CẢ ${_people.length} người',
                    style: const TextStyle(
                        fontSize: 11.5, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // Danh sách Profile Bệnh viện lưu trong app
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.04),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white.withOpacity(0.08)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Icon(Icons.bookmark_outline_rounded,
                        size: 16, color: Color(0xFF5EEAD4)),
                    const SizedBox(width: 6),
                    const Text(
                      'Danh sách Bệnh viện trong Profile:',
                      style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.bold,
                          color: Colors.white),
                    ),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: _showBulkAddHospitalDialog,
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        visualDensity: VisualDensity.compact,
                      ),
                      icon: const Icon(Icons.playlist_add_rounded, size: 15),
                      label: const Text('Nhập nhiều',
                          style: TextStyle(fontSize: 11)),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Container(
                  constraints: const BoxConstraints(maxHeight: 180),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white.withOpacity(0.08)),
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
                          color:
                              isSel ? const Color(0xFF5EEAD4) : Colors.white38,
                        ),
                        title: Text(
                          h,
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight:
                                isSel ? FontWeight.bold : FontWeight.normal,
                            color:
                                isSel ? const Color(0xFF5EEAD4) : Colors.white,
                          ),
                        ),
                        trailing: _hospitals.length > 1
                            ? IconButton(
                                icon: const Icon(Icons.close_rounded,
                                    size: 15, color: Colors.white38),
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
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _newHospitalController,
                        style: const TextStyle(fontSize: 12),
                        decoration: const InputDecoration(
                          labelText: 'Thêm BV vào Profile',
                          hintText: 'Nhập tên BV mới...',
                          isDense: true,
                          contentPadding:
                              EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        ),
                        onSubmitted: _addHospital,
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: () =>
                          _addHospital(_newHospitalController.text),
                      style: FilledButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                      ),
                      child: const Text('Thêm'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConfigTab() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.04),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white.withOpacity(0.08)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Cấu hình ViOTP & Đồng bộ OTP',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF5EEAD4)),
                ),
                const SizedBox(height: 10),
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
                  value:
                      [60, 90, 120].contains(_otpTimeout) ? _otpTimeout : 60,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.timer_outlined, size: 20),
                    labelText: 'Thời gian chờ OTP (giây)',
                    isDense: true,
                  ),
                  items: const [
                    DropdownMenuItem(
                        value: 60,
                        child: Text('60 giây (Mặc định - Chuẩn Abbott)')),
                    DropdownMenuItem(value: 90, child: Text('90 giây')),
                    DropdownMenuItem(
                        value: 120, child: Text('120 giây (2 phút)')),
                  ],
                  onChanged: (val) {
                    if (val != null) setState(() => _otpTimeout = val);
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.04),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white.withOpacity(0.08)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Cấu hình trường tự điền & Độ trễ',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF5EEAD4)),
                ),
                const SizedBox(height: 8),
                ..._fieldLabels.entries.map((entry) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
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
                                contentPadding: EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 8),
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
        ],
      ),
    );
  }
}
