import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/qurbani_category.dart';
import '../models/form_settings.dart';

/// Single service layer for ALL backend communication.
/// Every screen imports this — change the base URL once, everything updates.
class DatabaseService {
  // ── DUAL BACKEND: Primary (Singapore) + Failover (US) ──
  static const String _primaryUrl = 'https://qurbani-api.onrender.com/api';   // Render — Singapore (fast for India)
  static const String _fallbackUrl = 'https://ibrahimmalek608-qurbani-api.hf.space/api'; // HF — US (backup)
  static const Duration _timeout = Duration(seconds: 10);

  // ═══════════════════════════════════════════════════════
  // SMART FAILOVER HTTP HELPERS
  // Try Primary (Render/Singapore) first → if it fails → auto-switch to Fallback (HF/US)
  // ═══════════════════════════════════════════════════════

  /// Generic GET with failover.
  static Future<Map<String, dynamic>> _get(String endpoint) async {
    // Try primary first
    try {
      final response = await http.get(Uri.parse('$_primaryUrl$endpoint')).timeout(_timeout);
      if (response.body.isNotEmpty) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) return decoded;
      }
    } catch (_) {}

    // Fallback to secondary
    try {
      final response = await http.get(Uri.parse('$_fallbackUrl$endpoint')).timeout(_timeout);
      if (response.body.isEmpty) {
        return {'success': false, 'message': 'Both servers returned empty response', 'data': null};
      }
      return jsonDecode(response.body);
    } catch (e) {
      return {'success': false, 'message': 'Network error (both servers down): $e', 'data': null};
    }
  }

  /// Generic POST with failover.
  static Future<Map<String, dynamic>> _post(String endpoint, Map<String, dynamic> body) async {
    final headers = {'Content-Type': 'application/json'};
    final encodedBody = jsonEncode(body);

    // Try primary first
    try {
      final response = await http.post(Uri.parse('$_primaryUrl$endpoint'), headers: headers, body: encodedBody).timeout(_timeout);
      if (response.body.isNotEmpty) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) return decoded;
      }
    } catch (_) {}

    // Fallback to secondary
    try {
      final response = await http.post(Uri.parse('$_fallbackUrl$endpoint'), headers: headers, body: encodedBody).timeout(_timeout);
      if (response.body.isEmpty) {
        return {'success': false, 'message': 'Both servers returned empty response', 'data': null};
      }
      return jsonDecode(response.body);
    } catch (e) {
      return {'success': false, 'message': 'Network error (both servers down): $e', 'data': null};
    }
  }

  /// Generic PUT with failover.
  static Future<Map<String, dynamic>> _put(String endpoint, Map<String, dynamic> body) async {
    final headers = {'Content-Type': 'application/json'};
    final encodedBody = jsonEncode(body);

    // Try primary first
    try {
      final response = await http.put(Uri.parse('$_primaryUrl$endpoint'), headers: headers, body: encodedBody).timeout(_timeout);
      if (response.body.isNotEmpty) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) return decoded;
      }
    } catch (_) {}

    // Fallback to secondary
    try {
      final response = await http.put(Uri.parse('$_fallbackUrl$endpoint'), headers: headers, body: encodedBody).timeout(_timeout);
      if (response.body.isEmpty) {
        return {'success': false, 'message': 'Both servers returned empty response', 'data': null};
      }
      return jsonDecode(response.body);
    } catch (e) {
      return {'success': false, 'message': 'Network error (both servers down): $e', 'data': null};
    }
  }

  /// Generic DELETE with failover.
  static Future<Map<String, dynamic>> _delete(String endpoint) async {
    // Try primary first
    try {
      final response = await http.delete(Uri.parse('$_primaryUrl$endpoint')).timeout(_timeout);
      if (response.body.isNotEmpty) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) return decoded;
      }
    } catch (_) {}

    // Fallback to secondary
    try {
      final response = await http.delete(Uri.parse('$_fallbackUrl$endpoint')).timeout(_timeout);
      if (response.body.isEmpty) {
        return {'success': false, 'message': 'Both servers returned empty response', 'data': null};
      }
      return jsonDecode(response.body);
    } catch (e) {
      return {'success': false, 'message': 'Network error (both servers down): $e', 'data': null};
    }
  }

  // ── CACHING HELPERS ──
  static Future<void> _saveToCache(String key, dynamic data) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('cache_$key', jsonEncode(data));
    } catch (e) {
      // Fail silently
    }
  }

  static Future<dynamic> _getFromCache(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final str = prefs.getString('cache_$key');
      if (str != null) return jsonDecode(str);
    } catch (e) {
      // Fail silently
    }
    return null;
  }

  // ═══════════════════════════════════════════════════════
  // CATEGORIES
  // ═══════════════════════════════════════════════════════

  static Future<List<QurbaniCategory>> loadCategories({bool useCache = false}) async {
    if (useCache) {
      final cached = await _getFromCache('categories');
      if (cached != null) {
        return (cached as List).map((e) => QurbaniCategory(
          id: e['id'].toString(),
          title: e['title'] ?? '',
          subtitle: e['subtitle'] ?? '',
          amount: (e['amount'] ?? 0).toDouble(),
          hissahPerToken: e['hissah_per_token'] ?? 7,
        )).toList();
      }
    }

    try {
      final result = await _get('/categories/');
      if (result['success'] == true && result['data'] != null) {
        final List<dynamic> list = result['data'];
        await _saveToCache('categories', list);
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

  static Future<FormSettings> loadFormSettings({bool useCache = false}) async {
    if (useCache) {
      final cached = await _getFromCache('settings');
      if (cached != null) return FormSettings.fromJson(cached);
    }

    try {
      final result = await _get('/settings/');
      if (result['success'] == true && result['data'] != null) {
        await _saveToCache('settings', result['data']);
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
    bool separateToken = false,
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
        'separate_token': separateToken,
      });
      return result;
    } catch (e) {
      return {'success': false, 'message': 'Failed to create booking: $e'};
    }
  }

  static Future<List<Map<String, dynamic>>> loadBookings({String? query, bool useCache = false}) async {
    if (useCache && query == null) {
      final cached = await _getFromCache('bookings');
      if (cached != null) return List<Map<String, dynamic>>.from(cached);
    }

    try {
      final endpoint = query != null ? '/bookings/?query=${Uri.encodeComponent(query)}' : '/bookings/';
      final result = await _get(endpoint);
      if (result['success'] == true && result['data'] != null) {
        final data = List<Map<String, dynamic>>.from(result['data']);
        if (query == null) await _saveToCache('bookings', data);
        return data;
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

  static Future<Map<String, dynamic>> editBooking(int bookingId, Map<String, dynamic> payload) async {
    try {
      final result = await _put('/bookings/$bookingId/', payload);
      return result;
    } catch (e) {
      return {'success': false, 'message': 'Failed to edit booking: $e'};
    }
  }

  static Future<Map<String, dynamic>> deleteBooking(int bookingId) async {
    try {
      final result = await _delete('/bookings/$bookingId/');
      return result;
    } catch (e) {
      return {'success': false, 'message': 'Failed to delete booking: $e'};
    }
  }

  // ═══════════════════════════════════════════════════════
  // TOKENS
  // ═══════════════════════════════════════════════════════

  static Future<List<Map<String, dynamic>>> loadTokens({String? category, bool useCache = false}) async {
    if (useCache && category == null) {
      final cached = await _getFromCache('tokens');
      if (cached != null) return List<Map<String, dynamic>>.from(cached);
    }

    try {
      final endpoint = category != null ? '/tokens/?category=$category' : '/tokens/';
      final result = await _get(endpoint);
      if (result['success'] == true && result['data'] != null) {
        final data = List<Map<String, dynamic>>.from(result['data']);
        if (category == null) await _saveToCache('tokens', data);
        return data;
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
  static Future<Map<String, dynamic>> editTokenEntryName(int entryId, String newName) async {
    try {
      final result = await _put('/tokens/entries/$entryId', {
        'new_name': newName,
      });
      return result;
    } catch (e) {
      return {'success': false, 'message': 'Failed to edit name: $e'};
    }
  }

  static Future<Map<String, dynamic>> moveTokenEntry(int entryId, int newTokenId) async {
    try {
      final result = await _put('/tokens/entries/$entryId/move', {
        'new_token_id': newTokenId,
      });
      return result;
    } catch (e) {
      return {'success': false, 'message': 'Failed to move entry: $e'};
    }
  }

  static Future<Map<String, dynamic>> swapTokenEntries(int entry1Id, int entry2Id) async {
    try {
      final result = await _post('/tokens/swap', {
        'entry1_id': entry1Id,
        'entry2_id': entry2Id,
      });
      return result;
    } catch (e) {
      return {'success': false, 'message': 'Failed to swap: $e'};
    }
  }

  static Future<Map<String, dynamic>> bulkMoveEntries(List<int> entryIds, int? targetTokenId) async {
    try {
      final result = await _post('/tokens/move_bulk', {
        'entry_ids': entryIds,
        'target_token_id': targetTokenId,
      });
      return result;
    } catch (e) {
      return {'success': false, 'message': 'Failed to bulk move: $e'};
    }
  }

  // ═══════════════════════════════════════════════════════
  // ADMIN
  // ═══════════════════════════════════════════════════════

  static Future<bool> verifyAdmin(String email, String password) async {
    try {
      final result = await _post('/admin/verify', {'email': email, 'password': password});
      return result['success'] == true;
    } catch (e) {
      return false;
    }
  }

  static Future<Map<String, dynamic>> resetAllData(String email, String password) async {
    try {
      final result = await _post('/admin/reset', {'email': email, 'password': password});
      if (result['success'] == true) {
        // Clear local cache too
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('cache_bookings');
        await prefs.remove('cache_tokens');
      }
      return result;
    } catch (e) {
      return {'success': false, 'message': 'Reset failed: $e'};
    }
  }

  // ═══════════════════════════════════════════════════════
  // BACKUP
  // ═══════════════════════════════════════════════════════

  static Future<Map<String, dynamic>> backupStatus() async {
    try {
      return await _get('/backup/status');
    } catch (e) {
      return {'success': false, 'message': 'Failed: $e'};
    }
  }

  static Future<Map<String, dynamic>> createBackup(String email, String password) async {
    try {
      return await _post('/backup/create', {'email': email, 'password': password});
    } catch (e) {
      return {'success': false, 'message': 'Backup failed: $e'};
    }
  }

  static Future<Map<String, dynamic>> listBackups() async {
    try {
      return await _get('/backup/list');
    } catch (e) {
      return {'success': false, 'message': 'Failed: $e'};
    }
  }

  static Future<Map<String, dynamic>> restoreBackup(String email, String password, String gdriveFileId) async {
    try {
      return await _post('/backup/restore', {'email': email, 'password': password, 'gdrive_file_id': gdriveFileId});
    } catch (e) {
      return {'success': false, 'message': 'Restore failed: $e'};
    }
  }
}
