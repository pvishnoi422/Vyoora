// lib/services/storage_service.dart
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class StorageService {
  static const _keySkipOnboarding = 'skip_onboarding';
  static const _keyScanHistory = 'scan_history';

  // ── Onboarding ──────────────────────────────────────────────────────────
  static Future<bool> shouldShowOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    return !(prefs.getBool(_keySkipOnboarding) ?? false);
  }

  static Future<void> setSkipOnboarding(bool skip) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keySkipOnboarding, skip);
  }

  // ── Scan History ─────────────────────────────────────────────────────────
  static Future<List<ScanRecord>> getScanHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_keyScanHistory) ?? [];
    return raw
        .map((s) => ScanRecord.fromJson(jsonDecode(s)))
        .toList()
        .reversed
        .toList();
  }

  static Future<void> addScan(ScanRecord record) async {
    final prefs = await SharedPreferences.getInstance();
    final history = prefs.getStringList(_keyScanHistory) ?? [];
    history.add(jsonEncode(record.toJson()));
    // Keep only last 5
    if (history.length > 5) {
      history.removeRange(0, history.length - 5);
    }
    await prefs.setStringList(_keyScanHistory, history);
  }

  static Future<void> clearHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyScanHistory);
  }
}

class ScanRecord {
  final String date;
  final int score;
  final int ingredientCount;
  final int concernCount;
  final String summary;
  final Map<String, dynamic> fullResult;

  ScanRecord({
    required this.date,
    required this.score,
    required this.ingredientCount,
    required this.concernCount,
    required this.summary,
    required this.fullResult,
  });

  factory ScanRecord.fromJson(Map<String, dynamic> j) => ScanRecord(
    date: j['date'] ?? '',
    score: j['score'] ?? 0,
    ingredientCount: j['ingredientCount'] ?? 0,
    concernCount: j['concernCount'] ?? 0,
    summary: j['summary'] ?? '',
    fullResult: Map<String, dynamic>.from(j['fullResult'] ?? {}),
  );

  Map<String, dynamic> toJson() => {
    'date': date,
    'score': score,
    'ingredientCount': ingredientCount,
    'concernCount': concernCount,
    'summary': summary,
    'fullResult': fullResult,
  };
}
