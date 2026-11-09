import 'dart:convert';
import 'package:http/http.dart' as http;

enum OtpProviderType {
  viotp,
  hupsms;

  String get id => name;

  String get displayName {
    switch (this) {
      case OtpProviderType.viotp:
        return 'ViOTP';
      case OtpProviderType.hupsms:
        return 'HupSMS';
    }
  }

  String get subtitle {
    switch (this) {
      case OtpProviderType.viotp:
        return 'api.viotp.net';
      case OtpProviderType.hupsms:
        return 'hupsms.com';
    }
  }

  static OtpProviderType fromString(String? value) {
    if (value == 'hupsms') return OtpProviderType.hupsms;
    return OtpProviderType.viotp;
  }
}

class OtpServiceItem {
  final int id;
  final String name;
  final int price;
  final String? server;
  final int? timeoutMinutes;

  const OtpServiceItem({
    required this.id,
    required this.name,
    required this.price,
    this.server,
    this.timeoutMinutes,
  });

  String get displayName {
    if (server != null && server!.trim().isNotEmpty) {
      return '$name [${server!.trim()}]';
    }
    return name;
  }

  String get priceFormatted {
    if (price <= 0) return '';
    return price.toString().replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (Match m) => '${m[1]}.',
    ) + ' đ';
  }

  factory OtpServiceItem.fromJson(Map<String, dynamic> json) {
    final rawId = json['id'] ?? json['serviceId'] ?? json['service_id'];
    final id = int.tryParse(rawId.toString()) ?? 0;
    final name = (json['name'] ?? json['service_name'] ?? json['title'] ?? 'Dịch vụ $id').toString();
    final rawPrice = json['price'] ?? json['cost'];
    final price = (rawPrice is num) ? rawPrice.toInt() : (int.tryParse(rawPrice?.toString() ?? '') ?? 0);
    final server = json['server']?.toString();
    final timeout = json['timeoutMinutes'] != null ? int.tryParse(json['timeoutMinutes'].toString()) : null;

    return OtpServiceItem(
      id: id,
      name: name,
      price: price,
      server: server,
      timeoutMinutes: timeout,
    );
  }
}

class OtpRentalResult {
  final String orderId;
  final String phone;
  final int? balance;
  final int? price;

  const OtpRentalResult({
    required this.orderId,
    required this.phone,
    this.balance,
    this.price,
  });
}

enum OtpCheckStatus {
  pending,
  success,
  expired,
  cancelled,
  error;
}

class OtpCheckResult {
  final OtpCheckStatus status;
  final String? otp;
  final String? smsContent;
  final String? error;

  const OtpCheckResult({
    required this.status,
    this.otp,
    this.smsContent,
    this.error,
  });
}

class OtpService {
  static const String viotpBaseUrl = 'https://api.viotp.net/v1';
  static const String hupsmsBaseUrl = 'https://hupsms.com/api/v1';

  static Map<String, String> _headers(String token) => {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      };

  static String _extractErrorMessage(dynamic json, int statusCode) {
    if (json is Map) {
      if (json['message'] != null && json['message'].toString().isNotEmpty) {
        return json['message'].toString();
      }
      if (json['detail'] != null && json['detail'].toString().isNotEmpty) {
        return json['detail'].toString();
      }
      if (json['error'] != null && json['error'].toString().isNotEmpty) {
        return json['error'].toString();
      }
      if (json['code'] != null && json['code'].toString().isNotEmpty) {
        return json['code'].toString();
      }
    }
    return 'Mã lỗi HTTP $statusCode';
  }

  /// Lấy số dư tài khoản
  static Future<int> fetchBalance({
    required OtpProviderType provider,
    required String token,
  }) async {
    final cleanToken = token.trim();
    if (cleanToken.isEmpty) {
      throw Exception('Token/API key không được để trống!');
    }

    final Uri url;
    final Map<String, String> headers;

    if (provider == OtpProviderType.hupsms) {
      url = Uri.parse('$hupsmsBaseUrl/balance?api_key=$cleanToken');
      headers = _headers(cleanToken);
    } else {
      url = Uri.parse('$viotpBaseUrl/balance');
      headers = _headers(cleanToken);
    }

    final res = await http.get(url, headers: headers).timeout(const Duration(seconds: 7));

    if (res.statusCode == 200) {
      final json = jsonDecode(res.body);
      dynamic bal;
      if (json is Map) {
        bal = json['balance'];
        if (bal == null && json['data'] is Map) {
          bal = json['data']['balance'];
        }
      }
      if (bal is num) {
        return bal.toInt();
      } else if (bal != null) {
        return int.tryParse(bal.toString()) ?? 0;
      }
      return 0;
    } else {
      final json = jsonDecode(res.body);
      throw Exception(_extractErrorMessage(json, res.statusCode));
    }
  }

  /// Lấy danh sách dịch vụ OTP
  static Future<List<OtpServiceItem>> fetchServices({
    required OtpProviderType provider,
    required String token,
  }) async {
    final cleanToken = token.trim();
    if (cleanToken.isEmpty) {
      throw Exception('Token/API key không được để trống!');
    }

    final Uri url;
    final Map<String, String> headers;

    if (provider == OtpProviderType.hupsms) {
      url = Uri.parse('$hupsmsBaseUrl/services?api_key=$cleanToken');
      headers = _headers(cleanToken);
    } else {
      url = Uri.parse('$viotpBaseUrl/services');
      headers = _headers(cleanToken);
    }

    final res = await http.get(url, headers: headers).timeout(const Duration(seconds: 9));

    if (res.statusCode == 200) {
      final json = jsonDecode(res.body);
      List<dynamic> list = [];
      if (json is List) {
        list = json;
      } else if (json is Map && json['data'] is List) {
        list = json['data'];
      }

      return list
          .whereType<Map>()
          .map((item) => OtpServiceItem.fromJson(Map<String, dynamic>.from(item)))
          .toList();
    } else {
      final json = jsonDecode(res.body);
      throw Exception(_extractErrorMessage(json, res.statusCode));
    }
  }

  /// Thuê số điện thoại nhận OTP
  static Future<OtpRentalResult> rentPhone({
    required OtpProviderType provider,
    required String token,
    required int serviceId,
    String? network,
  }) async {
    final cleanToken = token.trim();
    if (cleanToken.isEmpty) {
      throw Exception('Token/API key không được để trống!');
    }

    if (provider == OtpProviderType.hupsms) {
      // HupSMS sử dụng GET /rent?api_key=...&serviceId=...
      var query = 'api_key=$cleanToken&serviceId=$serviceId';
      if (network != null && network.trim().isNotEmpty) {
        query += '&network=${network.trim()}';
      }
      final url = Uri.parse('$hupsmsBaseUrl/rent?$query');
      final res = await http.get(url, headers: _headers(cleanToken)).timeout(const Duration(seconds: 15));

      final json = jsonDecode(res.body);
      if (res.statusCode == 200 || res.statusCode == 201) {
        final data = (json is Map && json['data'] is Map) ? json['data'] as Map : json as Map;
        String phone = (data['phone'] ?? '').toString();
        if (phone.isNotEmpty && !phone.startsWith('0')) {
          phone = '0$phone';
        }
        final orderId = (data['orderId'] ?? data['id'] ?? '').toString();
        final rawBal = data['balance'];
        final bal = (rawBal is num) ? rawBal.toInt() : int.tryParse(rawBal?.toString() ?? '');
        final rawPrice = data['price'];
        final price = (rawPrice is num) ? rawPrice.toInt() : int.tryParse(rawPrice?.toString() ?? '');

        return OtpRentalResult(
          orderId: orderId,
          phone: phone,
          balance: bal,
          price: price,
        );
      } else {
        throw Exception(_extractErrorMessage(json, res.statusCode));
      }
    } else {
      // ViOTP sử dụng POST /rentals body: {"serviceId": serviceId}
      final url = Uri.parse('$viotpBaseUrl/rentals');
      final res = await http.post(
        url,
        headers: _headers(cleanToken),
        body: jsonEncode({'serviceId': serviceId}),
      ).timeout(const Duration(seconds: 15));

      final json = jsonDecode(res.body);
      if (res.statusCode == 200 || res.statusCode == 201) {
        final data = (json is Map && json['data'] is Map) ? json['data'] as Map : json as Map;
        String phone = (data['phone'] ?? '').toString();
        final phoneLocal = (data['phoneLocal'] ?? '').toString();
        if (phone.isEmpty && phoneLocal.isNotEmpty) {
          phone = '0$phoneLocal';
        } else if (phone.isNotEmpty && !phone.startsWith('0')) {
          phone = '0$phone';
        }
        final orderId = (data['id'] ?? '').toString();
        final rawBal = data['balance'];
        final bal = (rawBal is num) ? rawBal.toInt() : int.tryParse(rawBal?.toString() ?? '');

        return OtpRentalResult(
          orderId: orderId,
          phone: phone,
          balance: bal,
        );
      } else {
        throw Exception(_extractErrorMessage(json, res.statusCode));
      }
    }
  }

  /// Kiểm tra kết quả mã OTP
  static Future<OtpCheckResult> checkOtp({
    required OtpProviderType provider,
    required String token,
    required String orderId,
  }) async {
    final cleanToken = token.trim();
    if (cleanToken.isEmpty || orderId.trim().isEmpty) {
      return const OtpCheckResult(status: OtpCheckStatus.error, error: 'Thông tin không hợp lệ');
    }

    if (provider == OtpProviderType.hupsms) {
      // HupSMS: GET /check/:id?api_key=...
      final url = Uri.parse('$hupsmsBaseUrl/check/$orderId?api_key=$cleanToken');
      final res = await http.get(url, headers: _headers(cleanToken)).timeout(const Duration(seconds: 5));

      if (res.statusCode == 200) {
        final json = jsonDecode(res.body);
        final data = (json is Map && json['data'] is Map) ? json['data'] as Map : json as Map;
        final status = data['status']?.toString().toLowerCase();
        final otp = data['otp']?.toString().trim();
        final smsContent = data['smsContent']?.toString();

        if (status == 'success' || (otp != null && otp.isNotEmpty)) {
          String finalOtp = otp ?? '';
          if (finalOtp.isEmpty && smsContent != null) {
            final match = RegExp(r'\b\d{4,8}\b').firstMatch(smsContent);
            if (match != null) finalOtp = match.group(0)!;
          }
          return OtpCheckResult(
            status: OtpCheckStatus.success,
            otp: finalOtp,
            smsContent: smsContent,
          );
        } else if (status == 'cancelled') {
          return const OtpCheckResult(status: OtpCheckStatus.cancelled);
        } else if (status == 'expired') {
          return const OtpCheckResult(status: OtpCheckStatus.expired);
        }
        return const OtpCheckResult(status: OtpCheckStatus.pending);
      } else {
        final json = jsonDecode(res.body);
        final err = _extractErrorMessage(json, res.statusCode);
        return OtpCheckResult(status: OtpCheckStatus.error, error: err);
      }
    } else {
      // ViOTP: GET /rentals/:id
      final url = Uri.parse('$viotpBaseUrl/rentals/$orderId');
      final res = await http.get(url, headers: _headers(cleanToken)).timeout(const Duration(seconds: 5));

      if (res.statusCode == 200) {
        final json = jsonDecode(res.body);
        if (json is Map) {
          final status = json['status'];
          if (status == 1) {
            String otp = (json['code'] ?? '').toString().trim();
            final content = json['content']?.toString();
            if (otp.isEmpty && content != null) {
              final match = RegExp(r'\b\d{4,8}\b').firstMatch(content);
              if (match != null) otp = match.group(0)!;
            }
            return OtpCheckResult(
              status: OtpCheckStatus.success,
              otp: otp,
              smsContent: content,
            );
          } else if (status == 2) {
            return const OtpCheckResult(status: OtpCheckStatus.expired);
          }
        }
        return const OtpCheckResult(status: OtpCheckStatus.pending);
      } else {
        final json = jsonDecode(res.body);
        final err = _extractErrorMessage(json, res.statusCode);
        return OtpCheckResult(status: OtpCheckStatus.error, error: err);
      }
    }
  }

  /// Hủy đơn thuê số
  static Future<bool> cancelRental({
    required OtpProviderType provider,
    required String token,
    required String orderId,
  }) async {
    final cleanToken = token.trim();
    if (cleanToken.isEmpty || orderId.trim().isEmpty) return false;

    try {
      if (provider == OtpProviderType.hupsms) {
        // HupSMS: GET /cancel/:id?api_key=...
        final url = Uri.parse('$hupsmsBaseUrl/cancel/$orderId?api_key=$cleanToken');
        final res = await http.get(url, headers: _headers(cleanToken)).timeout(const Duration(seconds: 5));
        return res.statusCode == 200;
      } else {
        // ViOTP: DELETE /rentals/:id (hoặc tự hết hạn)
        return false;
      }
    } catch (_) {
      return false;
    }
  }
}

