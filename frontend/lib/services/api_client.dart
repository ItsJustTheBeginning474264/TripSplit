import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config.dart';

/// Error returned by the backend (or a network failure, statusCode 0).
class ApiException implements Exception {
  ApiException(this.statusCode, this.message);

  final int statusCode;
  final String message;

  @override
  String toString() => message;
}

/// Thin JSON-over-HTTP client for the TripSplit Flask API.
class ApiClient {
  ApiClient({String? baseUrl}) : baseUrl = baseUrl ?? AppConfig.baseUrl;

  final String baseUrl;
  String? token;

  /// Called when a request made with a token comes back 401 (token expired / revoked).
  void Function()? onUnauthorized;

  Uri _uri(String path, Map<String, String>? query) {
    final uri = Uri.parse('$baseUrl$path');
    return query == null || query.isEmpty ? uri : uri.replace(queryParameters: query);
  }

  Future<Map<String, dynamic>> _send(
    String method,
    String path, {
    Object? body,
    Map<String, String>? query,
  }) async {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
    final uri = _uri(path, query);
    final encoded = body == null ? null : jsonEncode(body);

    http.Response res;
    try {
      final Future<http.Response> call;
      switch (method) {
        case 'POST':
          call = http.post(uri, headers: headers, body: encoded);
          break;
        case 'PUT':
          call = http.put(uri, headers: headers, body: encoded);
          break;
        case 'DELETE':
          call = http.delete(uri, headers: headers);
          break;
        default:
          call = http.get(uri, headers: headers);
      }
      res = await call.timeout(const Duration(seconds: 20));
    } on TimeoutException {
      throw ApiException(0, 'The server took too long to respond. Please try again.');
    } catch (_) {
      throw ApiException(0, 'Cannot reach the server. Check your connection and the API address.');
    }

    Map<String, dynamic> data = {};
    if (res.bodyBytes.isNotEmpty) {
      try {
        final decoded = jsonDecode(utf8.decode(res.bodyBytes));
        if (decoded is Map<String, dynamic>) data = decoded;
      } catch (_) {
        // non-JSON body: fall through with empty data
      }
    }

    if (res.statusCode >= 200 && res.statusCode < 300) return data;
    if (res.statusCode == 401 && token != null) onUnauthorized?.call();
    throw ApiException(res.statusCode, (data['error'] as String?) ?? 'Request failed (${res.statusCode})');
  }

  Future<Map<String, dynamic>> get(String path, {Map<String, String>? query}) =>
      _send('GET', path, query: query);

  Future<Map<String, dynamic>> post(String path, {Object? body}) => _send('POST', path, body: body);

  Future<Map<String, dynamic>> put(String path, {Object? body}) => _send('PUT', path, body: body);

  Future<Map<String, dynamic>> delete(String path) => _send('DELETE', path);
}
