import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'config.dart';

/// Error returned by the API: `{ error: { code, message, details } }`.
class ApiException implements Exception {
  ApiException(this.status, this.code, this.message, [this.details]);

  final int status;
  final String code;
  final String message;
  final Map<String, dynamic>? details;

  bool get isNetwork => code == 'NETWORK';
  bool get isSessionExpired => status == 401 && (code == 'SESSION_EXPIRED' || code == 'UNAUTHORIZED' || code == 'ACCOUNT_DEACTIVATED');
  String? get field => details?['field'] as String?;

  @override
  String toString() => message;
}

/// Thin JSON client used by every screen. Holds the session token and reports
/// expired sessions so the app can sign the user out (NFR4).
class Api {
  Api._();
  static final Api instance = Api._();

  String? token;
  void Function(ApiException e)? onSessionExpired;
  final http.Client _client = http.Client();
  // Generous: a free cloud server can take ~50 s to wake up from sleep.
  static const _timeout = Duration(seconds: 70);

  Uri _uri(String path, [Map<String, dynamic>? query]) {
    final q = query?.map((k, v) => MapEntry(k, v?.toString() ?? ''))?..removeWhere((k, v) => v.isEmpty);
    return Uri.parse('${AppConfig.apiBaseUrl}$path').replace(queryParameters: (q == null || q.isEmpty) ? null : q);
  }

  Map<String, String> _headers({bool background = false}) => {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
        if (background) 'X-Background': '1',
      };

  Future<Map<String, dynamic>> get(String path, {Map<String, dynamic>? query, bool background = false}) =>
      _send(() => _client.get(_uri(path, query), headers: _headers(background: background)));

  Future<Map<String, dynamic>> post(String path, [Object? body]) =>
      _send(() => _client.post(_uri(path), headers: _headers(), body: jsonEncode(body ?? {})));

  Future<Map<String, dynamic>> put(String path, [Object? body]) =>
      _send(() => _client.put(_uri(path), headers: _headers(), body: jsonEncode(body ?? {})));

  Future<Map<String, dynamic>> patch(String path, [Object? body]) =>
      _send(() => _client.patch(_uri(path), headers: _headers(), body: jsonEncode(body ?? {})));

  Future<Map<String, dynamic>> delete(String path, [Object? body]) =>
      _send(() => _client.delete(_uri(path), headers: _headers(), body: body == null ? null : jsonEncode(body)));

  /// Multipart upload (credential documents, music, article covers). The file goes in the `file` field.
  Future<Map<String, dynamic>> upload(String path, {required Uint8List bytes, required String filename, Map<String, String> fields = const {}, String method = 'POST'}) {
    return _send(() async {
      final req = http.MultipartRequest(method, _uri(path))
        ..headers.addAll({if (token != null) 'Authorization': 'Bearer $token', 'Accept': 'application/json'})
        ..fields.addAll(fields)
        ..files.add(http.MultipartFile.fromBytes('file', bytes, filename: filename));
      return http.Response.fromStream(await _client.send(req));
    });
  }

  Future<Map<String, dynamic>> _send(Future<http.Response> Function() run) async {
    http.Response res;
    try {
      res = await run().timeout(_timeout);
    } on TimeoutException {
      throw ApiException(0, 'NETWORK', 'The server took too long to respond. Check your connection and try again.');
    } catch (_) {
      throw ApiException(0, 'NETWORK', 'You’re offline or the server can’t be reached. Check your connection and try again.');
    }
    Map<String, dynamic> body = {};
    if (res.body.isNotEmpty) {
      try {
        final decoded = jsonDecode(utf8.decode(res.bodyBytes));
        if (decoded is Map<String, dynamic>) body = decoded;
      } catch (_) {}
    }
    if (res.statusCode >= 200 && res.statusCode < 300) return body;
    final err = body['error'] is Map ? body['error'] as Map<String, dynamic> : const <String, dynamic>{};
    final e = ApiException(
      res.statusCode,
      (err['code'] ?? 'HTTP_${res.statusCode}').toString(),
      (err['message'] ?? 'Something went wrong. Please try again.').toString(),
      err['details'] is Map<String, dynamic> ? err['details'] as Map<String, dynamic> : null,
    );
    if (e.isSessionExpired && token != null) onSessionExpired?.call(e);
    throw e;
  }
}

final api = Api.instance;
