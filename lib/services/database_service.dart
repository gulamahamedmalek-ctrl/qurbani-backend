import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import '../models/qurbani_category.dart';
import '../models/form_settings.dart';

/// Single service layer for ALL backend communication.
/// Every screen imports this — change the base URL once, everything updates.
class DatabaseService {
  // ── SERVER URL CONFIGURATION ──
  // The app now connects to your LIVE backend on Render.com
  static const String _liveBaseUrl = 'https://qurbani-api.onrender.com/api';

  static String get _baseUrl {
    if (kIsWeb) {
      // For local web testing, you can still use localhost if you want, 
      // but for consistency we'll use the live URL
      return _liveBaseUrl;
    } else {
      // For the APK/Phone, we use the live public URL
      return _liveBaseUrl;
    }
  }

  // ═══════════════════════════════════════════════════════
  // REUSABLE HTTP HELPERS — Written once, used everywhere
  // ═══════════════════════════════════════════════════════

  /// Generic GET request with try/catch and JSON parsing.
  static Future<Map<String, dynamic>> _get(String endpoint) async {
    try {
      final response = await http.get(Uri.parse('$_baseUrl$endpoint'));
      if (response.body.isEmpty) {
        return {'success': false, 'message': 'Empty response (Status: ${response.statusCode})', 'data': null};
      }
      try {
        return jsonDecode(response.body);
      } catch (e) {
        return {'success': false, 'message': 'Invalid JSON: ${response.body.substring(0, response.body.length > 50 ? 50 : response.body.length)}', 'data': null};
      }
    } catch (e) {
      return {'success': false, 'message': 'Network error: $e', 'data': null};
    }
  }

  /// Generic POST request with try/catch and JSON body.
  static Future<Map<String, dynamic>> _post(String endpoint, Map<String, dynamic> body) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl$endpoint'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );
      
      if (response.body.isEmpty) {
        return {'success': false, 'message': 'Server returned empty response (Status: ${response.statusCode})', 'data': null};
      }

      try {
        return jsonDecode(response.body);
      } catch (e) {
        return {'success': false, 'message': 'Invalid JSON response: ${response.body.substring(0, response.body.length > 50 ? 50 : response.body.length)}', 'data': null};
      }
    } catch (e) {
      return {'success': false, 'message': 'Network error: $e', 'data': null};
    }
  }

  /// Generic PUT request with try/catch and JSON body.
  static Future<Map<String, dynamic>> _put(String endpoint, Map<String, dynamic> body) async {
    try {
      final response = await http.put(
        Uri.parse('$_baseUrl$endpoint'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );
      if (response.body.isEmpty) {
        return {'success': false, 'message': 'Empty response (Status: ${response.statusCode})', 'data': null};
      }
      try {
        return jsonDecode(response.body);
      } catch (e) {
        return {'success': false, 'message': 'Invalid JSON: ${response.body.substring(0, response.body.length > 50 ? 50 : response.body.length)}', 'data': null};
      }
    } catch (e) {
      return {'success': false, 'message': 'Network error: $e', 'data': null};
    }
  }

  /// Generic DELETE request with try/catch.
  static Future<Map<String, dynamic>> _delete(String endpoint) async {
    try {
      final response = await http.delete(Uri.parse('$_baseUrl$endpoint'));
      if (response.body.isEmpty) {
        return {'success': false, 'message': 'Empty response (Status: ${response.statusCode})', 'data': null};
      }
      try {
        return jsonDecode(response.body);
      } catch (e) {
        return {'success': false, 'message': 'Invalid JSON: ${response.body.substring(0, response.body.length > 50 ? 50 : response.body.length)}', 'data': null};
      }
    } catch (e) {
      return {'success': false, 'message': 'Network error: $e', 'data': null};
    }
  }

  // ═══════════════════════════════════════════════════════
  // CATEGORIES
  // ═══════════════════════════════════════════════════════

  static Future<List<QurbaniCategory>> loadCategories() async {
    try {
      final result = await _get('/categories/');
      if (result['success'] == true && result['data'] != null) {
        final List<dynamic> list = result['data'];
        return list.map((e) => QurbaniCategory(
          id: e['id'].toString(),
          title: e['title'] ?? '',
          subtitle: e['subtitle'] ?? '',
          amount: (e['amount'] ?? 0).toDouble(),
          hissahPerToken: e['hissah_per_token'] ?? 7,
        )).toList();
      }
    } catch (e) {
      // Fallback silently
    }
    // Return defaults if backend is unreachable
    return [
      QurbaniCategory(id: '1', title: 'Heavy Qurbani', subtitle: 'Premium size', amount: 2000.0),
      QurbaniCategory(id: '2', title: 'Medium Qurbani', subtitle: 'Standard size', amount: 1500.0),
    ];
  }

  static Future<void> saveCategories(List<QurbaniCategory> categories) async {
    // Optimized Strategy: Send everything in one bulk sync request.
    try {
      final List<Map<String, dynamic>> body = categories.map((cat) => {
        'title': cat.title,
        'subtitle': cat.subtitle,
        'amount': cat.amount,
        'hissah_per_token': cat.hissahPerToken,
      }).toList();

      await _post('/categories/sync/', {'categories': body});
    } catch (e) {
      // Fail silently
    }
  }

  // ═══════════════════════════════════════════════════════
  // FORM SETTINGS
  // ═══════════════════════════════════════════════════════

  static Future<FormSettings> loadFormSettings() async {
    try {
      final result = await _get('/settings/');
      if (result['success'] == true && result['data'] != null) {
        return FormSettings.fromJson(result['data']);
      }
    } catch (e) {
      // Fallback silently
    }
    return FormSettings(); // Return defaults if backend is unreachable
  }

  static Future<void> saveFormSettings(FormSettings settings) async {
    try {
      await _put('/settings/', settings.toJson());
    } catch (e) {
      // Fail silently
    }
  }

  // ═══════════════════════════════════════════════════════
  // BOOKINGS
  // ═══════════════════════════════════════════════════════

  static Future<Map<String, dynamic>> createBooking({
    required String categoryTitle,
    required double amountPerHissah,
    required String purpose,
    required String representativeName,
    required List<String> ownerNames,
    required int hissahCount,
    required double totalAmount,
    required String address,
    required String mobile,
    required String reference,
    Map<String, dynamic> customFieldsData = const {},
  }) async {
    try {
      final result = await _post('/bookings/', {
        'category_title': categoryTitle,
        'amount_per_hissah': amountPerHissah,
        'purpose': purpose,
        'representative_name': representativeName,
        'owner_names': ownerNames,
        'hissah_count': hissahCount,
        'total_amount': totalAmount,
        'address': address,
        'mobile': mobile,
        'reference': reference,
        'custom_fields_data': customFieldsData,
      });
      return result;
    } catch (e) {
      return {'success': false, 'message': 'Failed to create booking: $e'};
    }
  }

  static Future<List<Map<String, dynamic>>> loadBookings({String? query}) async {
    try {
      final endpoint = query != null ? '/bookings/?query=${Uri.encodeComponent(query)}' : '/bookings/';
      final result = await _get(endpoint);
      if (result['success'] == true && result['data'] != null) {
        return List<Map<String, dynamic>>.from(result['data']);
      }
    } catch (e) {
      // Fallback silently
    }
    return [];
  }

  static Future<Map<String, dynamic>> getBookingDetails(int bookingId) async {
    try {
      final result = await _get('/bookings/$bookingId/details/');
      return result;
    } catch (e) {
      return {'success': false, 'message': 'Failed to load booking details: $e'};
    }
  }

  // ═══════════════════════════════════════════════════════
  // TOKENS
  // ═══════════════════════════════════════════════════════

  static Future<List<Map<String, dynamic>>> loadTokens({String? category}) async {
    try {
      final endpoint = category != null ? '/tokens/?category=$category' : '/tokens/';
      final result = await _get(endpoint);
      if (result['success'] == true && result['data'] != null) {
        return List<Map<String, dynamic>>.from(result['data']);
      }
    } catch (e) {
      // Fallback silently
    }
    return [];
  }

  static Future<Map<String, dynamic>> markQurbaniDone(int tokenId) async {
    try {
      final result = await _put('/tokens/$tokenId/qurbani-done/', {});
      return result;
    } catch (e) {
      return {'success': false, 'message': 'Failed to mark qurbani done: $e'};
    }
  }

  static Future<Map<String, dynamic>> markBulkQurbaniDone(List<int> tokenIds) async {
    try {
      final result = await _put('/tokens/bulk/qurbani-done/', {
        'token_ids': tokenIds,
      });
      return result;
    } catch (e) {
      return {'success': false, 'message': 'Failed to process bulk update: $e'};
    }
  }
}
