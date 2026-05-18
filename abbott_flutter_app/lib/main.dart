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
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
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
  final TextEditingController _tokenController = TextEditingController(text: 'de6faac93d8d4f3294070fe48a11224b');
  final TextEditingController _listDataController = TextEditingController();
  
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
    setState(() {
      _tokenController.text = token ?? 'de6faac93d8d4f3294070fe48a11224b';
      _urlController.text = lastUrl ?? '';
      _listDataController.text = peopleData ?? '';
      _parseData();
    });
    if (_urlController.text.isNotEmpty) {
      _loadUrl();
    }
  }

  Future<void> _savePreferences() async {
    await AppPreferences.setString('viotp_token', _tokenController.text);
    await AppPreferences.setString('last_url', _urlController.text);
    await AppPreferences.setString('people_data', _listDataController.text);
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

  String _cleanNoAccent(String input) {
    const vietnamese = {
      'à':'a','á':'a','ạ':'a','ả':'a','ã':'a','â':'a','ầ':'a','ấ':'a','ậ':'a','ẩ':'a','ẫ':'a','ă':'a','ằ':'a','ắ':'a','ặ':'a','ẳ':'a','ẵ':'a',
      'è':'e','é':'e','ẹ':'e','ẻ':'e','ẽ':'e','ê':'e','ề':'e','ế':'e','ệ':'e','ể':'e','ễ':'e',
      'ì':'i','í':'i','ị':'i','ỉ':'i','ĩ':'i',
      'ò':'o','ó':'o','ọ':'o','ỏ':'o','õ':'o','ô':'o','ồ':'o','ố':'o','ộ':'o','ổ':'o','ỗ':'o','ơ':'o','ờ':'o','ớ':'o','ợ':'o','ở':'o','ỡ':'o',
      'ù':'u','ú':'u','ụ':'u','ủ':'u','ũ':'u','ư':'u','ừ':'u','ứ':'u','ự':'u','ử':'u','ữ':'u',
      'ỳ':'y','ý':'y','ỵ':'y','ỷ':'y','ỹ':'y','đ':'d',
      'À':'A','Á':'A','Ạ':'A','Ả':'A','Ã':'A','Â':'A','Ầ':'A','Ấ':'A','Ậ':'A','Ẩ':'A','Ẫ':'A','Ă':'A','Ằ':'A','Ắ':'A','Ặ':'A','Ẳ':'A','Ẵ':'A',
      'È':'E','É':'E','Ẹ':'E','Ẻ':'E','Ẽ':'E','Ê':'E','Ề':'E','Ế':'E','Ệ':'E','Ể':'E','Ễ':'E',
      'Ì':'I','Í':'I','Ị':'I','Ỉ':'I','Ĩ':'I',
      'Ò':'O','Ó':'O','Ọ':'O','Ỏ':'O','Õ':'O','Ô':'O','Ồ':'O','Ố':'O','Ộ':'O','Ổ':'O','Ỗ':'O','Ơ':'O','Ờ':'O','Ớ':'O','Ợ':'O','Ở':'O','Ỡ':'O',
      'Ù':'U','Ú':'U','Ụ':'U','Ủ':'U','Ũ':'U','Ư':'U','Ừ':'U','Ứ':'U','Ự':'U','Ử':'U','Ữ':'U',
      'Ỳ':'Y','Ý':'Y','Ỵ':'Y','Ỷ':'Y','Ỹ':'Y','Đ':'D',
    };
    var out = input.trim();
    vietnamese.forEach((k, v) => out = out.replaceAll(k, v));
    return out.replaceAll(RegExp(r'\s+'), ' ');
  }

  String _formatDepartment(String raw) {
    final s = _cleanNoAccent(raw).toLowerCase();
    if (s.contains('gay me')) return 'Khoa Gay Me Hoi Suc';
    if (s.contains('ngoai than kinh')) return 'Khoa Ngoai Than Kinh';
    if (s.contains('chan thuong') || s.contains('chinh hinh') || s.contains('bong')) {
      return 'Khoa Chan Thuong Chinh Hinh - Bong';
    }
    return _titleCase(_cleanNoAccent(raw));
  }

  String _formatTitle(String raw) {
    final s = _cleanNoAccent(raw).toLowerCase().replaceAll('.', '').trim();
    if (s == 'bs' || s.contains('bac si') || s.contains('bac sy')) return 'Bac Sy Dieu Tri';
    if (s.contains('truong')) return 'Dieu Duong Truong';
    if (s == 'dd' || s.contains('dieu duong')) return 'Dieu Duong';
    return _titleCase(_cleanNoAccent(raw));
  }

  String _titleCase(String input) {
    return input
        .split(' ')
        .where((w) => w.isNotEmpty)
        .map((w) => w[0].toUpperCase() + (w.length > 1 ? w.substring(1).toLowerCase() : ''))
        .join(' ');
  }

  void _parseData() {
    final lines = _listDataController.text.split('\n');
    final parsed = <Map<String, String>>[];
    for (var line in lines) {
      if (line.trim().isEmpty) continue;
      final parts = line.split('-');
      if (parts.length >= 2) {
        final rawDepartment = parts[1].trim();
        final rawRole = parts.length > 2 ? parts[2].trim() : '';
        parsed.add({
          'name': parts[0].trim(),
          'department': _formatDepartment(rawDepartment),
          'role': _formatTitle(rawRole),
          'rawDepartment': rawDepartment,
          'rawRole': rawRole,
        });
      }
    }
    setState(() {
      _people = parsed;
      if (_currentPersonIndex >= _people.length) {
        _currentPersonIndex = 0;
      }
    });
    _savePreferences();
  }

  Future<void> _fetchServiceId() async {
    setState(() {
      _isLoadingService = true;
    });
    try {
      final token = _tokenController.text.trim();
      final url = Uri.parse('https://api.viotp.com/service/getv2?token=$token&country=vn');
      final response = await http.get(url);
      final json = jsonDecode(response.body);
      
      if (json['status_code'] == 200) {
        final data = json['data'];
        if (data is! List) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Dữ liệu dịch vụ ViOTP không hợp lệ!')),
          );
          return;
        }

        Map? service;
        for (final item in data) {
          if (item is Map && (item['name'] ?? '').toString().toLowerCase().contains('abbott')) {
            service = item;
            break;
          }
        }

        final serviceId = int.tryParse((service?['id'] ?? '').toString());
        if (serviceId != null) {
          _abbottServiceId = serviceId;
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Tìm thấy dịch vụ Abbott (ID: $_abbottServiceId)')));
        } else {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Không tìm thấy dịch vụ Abbott trên ViOTP!')));
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Lỗi: ${json['message']}")));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi kết nối: $e')));
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
      final url = Uri.parse('https://api.viotp.com/request/getv2?token=$token&serviceId=$_abbottServiceId');
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
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đã lấy và copy số điện thoại!')));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Lỗi: ${json['message']}")));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi kết nối: $e')));
    } finally {
      setState(() {
        _isGettingPhone = false;
      });
    }
  }

  Future<void> _getOtp() async {
    if (_currentRequestId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Chưa có số điện thoại nào đang thuê!')));
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

        final url = Uri.parse('https://api.viotp.com/session/getv2?requestId=$_currentRequestId&token=$token');
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
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đã nhận, copy và điền OTP!')));
            return;
          }
          if (status != 0) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Phiên đã hết hạn hoặc lỗi!')));
            return;
          }
        } else {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Lỗi: ${json['message']}")));
          return;
        }

        await Future.delayed(const Duration(seconds: 1));
      }

      setState(() {
        _otpStatusText = 'Không lấy được OTP sau 60s';
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Không lấy mã OTP được sau 60 giây.')));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi kết nối: $e')));
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
          .replace(/đ/g, 'd').replace(/\s+/g, ' ').trim();
        const inputs = Array.from(document.querySelectorAll('input, textarea'));
        function labelOf(el) {
          let txt = '';
          if (el.id) {
            const label = document.querySelector('label[for="' + el.id + '"]');
            if (label) txt += ' ' + label.innerText;
          }
          let p = el;
          for (let i = 0; i < 4 && p; i++, p = p.parentElement) {
            txt += ' ' + (p.innerText || '');
          }
          txt += ' ' + (el.placeholder || '') + ' ' + (el.name || '') + ' ' + (el.id || '');
          return norm(txt);
        }
        function setVal(el, val) {
          if (!el || val == null || val === '') return false;
          el.focus();
          el.value = val;
          el.dispatchEvent(new Event('input', {bubbles: true}));
          el.dispatchEvent(new Event('change', {bubbles: true}));
          return true;
        }
        function fillBy(keys, val) {
          const el = inputs.find(i => keys.some(k => labelOf(i).includes(k)));
          return setVal(el, val);
        }
        fillBy(['sdt', 'so dien thoai', 'dien thoai', 'phone'], data.phone);
        fillBy(['ma', 'otp', 'code', 'xac thuc'], data.otp);
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
  }

  Future<void> _fillOtpInWeb() async {
    await _fillWebFields({'otp': _currentOtp});
  }

  Future<void> _fillCurrentPersonInWeb() async {
    if (_people.isEmpty) return;
    final p = _people[_currentPersonIndex];
    await _fillWebFields({
      'name': p['name'] ?? '',
      'department': p['department'] ?? '',
      'role': p['role'] ?? '',
      'attendeeRole': 'Người tham dự',
      'hospital': 'BENH VIEN DA KHOA TINH QUANG NGAI',
    });
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đã điền thông tin người hiện tại. Vui lòng kiểm tra rồi tự bấm gửi.')));
  }

  void _copy(String text, String label) {
    if (text.isEmpty) return;
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Đã copy $label!')));
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
          style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: .2, fontSize: 16),
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
              Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
              Text(subtitle, style: TextStyle(color: Colors.white.withOpacity(0.58), fontSize: 11)),
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
      constraints: const BoxConstraints(maxHeight: 168),
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
              Icon(Icons.sms_rounded, color: const Color(0xFF5EEAD4), size: 18),
              const SizedBox(width: 6),
              const Text('OTP', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13)),
              const Spacer(),
              if (_otpStatusText.isNotEmpty)
                Flexible(
                  child: Text(
                    _otpStatusText,
                    textAlign: TextAlign.right,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11, color: Color(0xFF93C5FD), fontWeight: FontWeight.w700),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              FilledButton(
                onPressed: (_isGettingPhone || _isLoadingService) ? null : _getPhoneNumber,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(66, 32),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  visualDensity: VisualDensity.compact,
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  _loadingIcon(_isGettingPhone || _isLoadingService, Icons.phone_android_rounded),
                  const SizedBox(width: 4),
                  const Text('Số'),
                ]),
              ),
              const SizedBox(width: 6),
              Expanded(child: _valuePill(_currentPhoneNumber, 'SĐT', Icons.call_rounded)),
              IconButton.filledTonal(
                tooltip: 'Copy số',
                visualDensity: VisualDensity.compact,
                iconSize: 18,
                icon: const Icon(Icons.copy_rounded),
                onPressed: _currentPhoneNumber.isEmpty ? null : () => _copy(_currentPhoneNumber, 'Số điện thoại'),
              ),
              IconButton.filledTonal(
                tooltip: 'Điền số',
                visualDensity: VisualDensity.compact,
                iconSize: 18,
                icon: const Icon(Icons.keyboard_double_arrow_up_rounded),
                onPressed: _currentPhoneNumber.isEmpty ? null : _fillPhoneInWeb,
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
              Expanded(child: _valuePill(_currentOtp, 'Mã OTP', Icons.password_rounded)),
              IconButton.filledTonal(
                tooltip: 'Copy OTP',
                visualDensity: VisualDensity.compact,
                iconSize: 18,
                icon: const Icon(Icons.copy_rounded),
                onPressed: _currentOtp.isEmpty ? null : () => _copy(_currentOtp, 'OTP'),
              ),
              IconButton.filledTonal(
                tooltip: 'Điền OTP',
                visualDensity: VisualDensity.compact,
                iconSize: 18,
                icon: const Icon(Icons.keyboard_double_arrow_up_rounded),
                onPressed: _currentOtp.isEmpty ? null : _fillOtpInWeb,
              ),
            ],
          ),
          const SizedBox(height: 4),
          SizedBox(
            height: 34,
            child: hasPerson
                ? Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          const Color(0xFF5EEAD4).withOpacity(0.16),
                          const Color(0xFFF0ABFC).withOpacity(0.10),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white.withOpacity(0.10)),
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 11,
                          backgroundColor: const Color(0xFF5EEAD4),
                          foregroundColor: const Color(0xFF06211D),
                          child: Text('${_currentPersonIndex + 1}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12)),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            current?['name'] ?? '',
                            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12),
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
                              _currentPersonIndex = _currentPersonIndex < _people.length - 1 ? _currentPersonIndex + 1 : 0;
                            });
                          },
                        ),
                      ],
                    ),
                  )
                : Container(
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
          ),
        ],
        ),
      ),
    );
  }


  void _showSettingsDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF101827),
          surfaceTintColor: const Color(0xFF5EEAD4),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
          title: const Row(
            children: [
              Icon(Icons.tune_rounded, color: Color(0xFF5EEAD4)),
              SizedBox(width: 10),
              Text('Cài đặt dữ liệu'),
            ],
          ),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: _tokenController,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.vpn_key_rounded),
                      labelText: 'ViOTP Token',
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _listDataController,
                    minLines: 6,
                    maxLines: 10,
                    decoration: const InputDecoration(
                      alignLabelWithHint: true,
                      prefixIcon: Icon(Icons.list_alt_rounded),
                      labelText: 'Danh sách NOIDUNGDIEN.TXT',
                      hintText: 'VD: Phạm Thị Thu Vân - gây mê hồi sức - bs',
                    ),
                  ),
                ],
              ),
            ),
          ),
          actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Hủy'),
            ),
            FilledButton.icon(
              onPressed: () {
                _parseData();
                Navigator.pop(context);
              },
              icon: const Icon(Icons.save_rounded),
              label: const Text('Lưu'),
            )
          ],
        );
      },
    );
  }
}
