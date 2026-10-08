// Desktops this phone has paired with. Addresses live in shared_preferences;
// each gateway token lives in flutter_secure_storage (never in prefs, except
// the web preview build which has no keystore).
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'pairing.dart';

class SavedDesktop {
  final String id;
  final String name;
  final String url;
  final String? profile;
  final Map<String, String> headers;
  final DateTime addedAt;
  DateTime? lastConnected;
  SavedDesktop(
      {required this.id, required this.name, required this.url, this.profile, this.headers = const {}, required this.addedAt, this.lastConnected});

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'url': url,
        'profile': profile,
        'headers': headers,
        'addedAt': addedAt.toIso8601String(),
        'lastConnected': lastConnected?.toIso8601String(),
      };
  factory SavedDesktop.fromJson(Map<String, dynamic> j) => SavedDesktop(
        id: '${j['id']}',
        name: '${j['name'] ?? ''}',
        url: '${j['url'] ?? ''}',
        profile: j['profile'] as String?,
        headers: j['headers'] is Map ? (j['headers'] as Map).map((k, v) => MapEntry('$k', '$v')) : const {},
        addedAt: DateTime.tryParse('${j['addedAt'] ?? ''}') ?? DateTime.now(),
        lastConnected: DateTime.tryParse('${j['lastConnected'] ?? ''}'),
      );
}

class SavedDesktops {
  SavedDesktops(this._prefs);
  final SharedPreferences _prefs;
  final FlutterSecureStorage _secure = const FlutterSecureStorage();
  static const _key = 'remote.desktops';
  static const _activeKey = 'remote.active';

  final List<SavedDesktop> items = [];
  String? activeId;

  void load() {
    items.clear();
    try {
      final raw = jsonDecode(_prefs.getString(_key) ?? '[]') as List;
      items.addAll(raw.whereType<Map>().map((e) => SavedDesktop.fromJson(Map<String, dynamic>.from(e))));
    } catch (_) {}
    activeId = _prefs.getString(_activeKey);
  }

  void _save() {
    _prefs.setString(_key, jsonEncode(items.map((e) => e.toJson()).toList()));
    if (activeId == null) {
      _prefs.remove(_activeKey);
    } else {
      _prefs.setString(_activeKey, activeId!);
    }
  }

  SavedDesktop? get active => items.where((d) => d.id == activeId).firstOrNull ?? items.firstOrNull;

  /// Add or update (same URL = same desktop) and make it active.
  Future<SavedDesktop> upsert(GatewayPairing p) async {
    final existing = items.where((d) => d.url == p.url).firstOrNull;
    final d = SavedDesktop(
      id: existing?.id ?? 'pc_${DateTime.now().microsecondsSinceEpoch}',
      name: p.displayName,
      url: p.url,
      profile: p.profile,
      headers: p.headers,
      addedAt: existing?.addedAt ?? DateTime.now(),
      lastConnected: DateTime.now(),
    );
    items
      ..removeWhere((x) => x.id == d.id)
      ..insert(0, d);
    activeId = d.id;
    await _writeToken(d.id, p.token);
    _save();
    return d;
  }

  void touch(SavedDesktop d) {
    d.lastConnected = DateTime.now();
    activeId = d.id;
    _save();
  }

  Future<void> remove(String id) async {
    items.removeWhere((d) => d.id == id);
    if (activeId == id) activeId = items.firstOrNull?.id;
    try {
      await _secure.delete(key: 'remote.token.$id');
    } catch (_) {}
    await _prefs.remove('remote.tokenfallback.$id');
    _save();
  }

  Future<String> token(String id) async {
    if (kIsWeb) return _prefs.getString('remote.tokenfallback.$id') ?? '';
    try {
      return await _secure.read(key: 'remote.token.$id') ?? _prefs.getString('remote.tokenfallback.$id') ?? '';
    } catch (_) {
      return _prefs.getString('remote.tokenfallback.$id') ?? '';
    }
  }

  Future<void> _writeToken(String id, String token) async {
    if (kIsWeb) {
      await _prefs.setString('remote.tokenfallback.$id', token);
      return;
    }
    try {
      await _secure.write(key: 'remote.token.$id', value: token);
    } catch (_) {
      // Keystore unavailable (rare emulator images): keep the remote usable.
      await _prefs.setString('remote.tokenfallback.$id', token);
    }
  }
}
