import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'domain.dart';

abstract interface class AcademicApi {
  Future<Map<String, dynamic>> login();
  Future<Map<String, dynamic>> timetable();
  Future<void> logout();
}

class NativeAcademicApi implements AcademicApi {
  static const channel = MethodChannel('org.handancampus.flutter/academic');
  Future<Map<String, dynamic>> call(String method) async =>
      object(await channel.invokeMethod<Object?>(method));
  @override
  Future<Map<String, dynamic>> login() => call('login');
  @override
  Future<Map<String, dynamic>> timetable() => call('getTimetable');
  @override
  Future<void> logout() async {
    await channel.invokeMethod<void>('logout');
  }
}

abstract interface class SecureCache {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class DeviceSecureCache implements SecureCache {
  final FlutterSecureStorage _storage = const FlutterSecureStorage(
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.unlocked_this_device,
    ),
  );
  @override
  Future<String?> read(String key) => _storage.read(key: key);
  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);
  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

enum ConnectionState {
  disconnected,
  cached,
  connected,
  expired,
  error,
  noCourses,
}

class AcademicStore extends ChangeNotifier {
  AcademicStore(this.api, this.cache);
  final AcademicApi api;
  final SecureCache cache;
  static const activeKey = 'academic.v1.active';
  String? _scope;
  String? _cleanupScope;
  bool cleanupRequired = false;
  int _generation = 0;
  Future<void> _writes = Future.value();
  Timetable? timetable;
  ConnectionState state = ConnectionState.disconnected;
  bool busy = false;
  String? notice;
  bool get connected => _scope != null;
  String key(String scope) =>
      'academic.v1.${base64Url.encode(utf8.encode(scope))}';
  Future<void> _serial(Future<void> Function() action) {
    final result = _writes.then((_) => action());
    _writes = result.catchError((Object _) {});
    return result;
  }

  bool valid(int generation) => generation == _generation;
  Future<void> restore() async {
    final generation = _generation;
    try {
      final scope = await cache.read(activeKey);
      if (!valid(generation) || scope == null || scope.isEmpty) return;
      final raw = await cache.read(key(scope));
      if (!valid(generation)) return;
      _scope = scope;
      if (raw != null) {
        final data = object(jsonDecode(raw));
        if (data['scope'] != scope) {
          throw const FormatException('Cache scope mismatch');
        }
        timetable = Timetable.fromJson(object(data['timetable']));
        state = ConnectionState.cached;
        notice = '正在查看本机保存的课表，可离线使用';
      }
    } catch (_) {
      if (valid(generation)) {
        state = ConnectionState.error;
        notice = '本机课表暂时无法读取，请重新连接';
      }
    }
    if (valid(generation)) notifyListeners();
  }

  Future<void> _persist(int generation) async {
    final scope = _scope, table = timetable;
    if (scope == null || table == null) return;
    final encoded = jsonEncode({'scope': scope, 'timetable': table.toJson()});
    await _serial(() async {
      if (!valid(generation)) return;
      await cache.write(key(scope), encoded);
      if (!valid(generation)) return;
      await cache.write(activeKey, scope);
    });
  }

  /// Tombstone first: if deletion fails, cold start still cannot restore scope.
  /// If both writes and deletes fail, keep an explicit retry action visible.
  Future<void> _invalidate(String? scope) => _serial(() async {
        var tombstoned = false;
        try {
          await cache.write(activeKey, '');
          tombstoned = true;
        } catch (_) {
          /* Try deletion independently. */
        }
        try {
          await cache.delete(activeKey);
        } catch (_) {
          if (!tombstoned) rethrow;
        }
        if (scope != null) await cache.delete(key(scope));
      });

  /// Account change invalidates visible data before any asynchronous operation.
  Future<void> connect() async {
    if (busy) return;
    final oldScope = _scope ?? _cleanupScope;
    _cleanupScope = oldScope;
    cleanupRequired = true;
    final generation = ++_generation;
    _scope = null;
    timetable = null;
    busy = true;
    notice = null;
    state = ConnectionState.disconnected;
    notifyListeners();
    try {
      try {
        await _invalidate(oldScope);
      } finally {
        await api.logout();
      }
      if (!valid(generation)) return;
      cleanupRequired = false;
      _cleanupScope = null;
      final response = await api.login();
      if (!valid(generation)) return;
      final scope = field(response['sessionScope']);
      if (response['session'] != 'valid' || scope.isEmpty) {
        notice = response['cancelled'] == true ? '已取消登录，未恢复上一账号课表' : '尚未完成学校认证';
        return;
      }
      _scope = scope;
      await _serial(() async {
        if (valid(generation)) await cache.write(activeKey, scope);
      });
      if (valid(generation)) {
        await _refresh(
          generation,
          initial: response.containsKey('modules') ? response : null,
        );
      }
    } on PlatformException catch (error) {
      if (valid(generation)) {
        state = ConnectionState.disconnected;
        notice = error.code.toUpperCase().contains('CANCEL')
            ? '已取消登录，未恢复上一账号课表'
            : '学校连接未完成，请重新尝试';
      }
    } catch (_) {
      if (valid(generation)) {
        state = ConnectionState.error;
        notice =
            cleanupRequired ? '本机清理未完成，请点击重试清理；离线数据可能仍在设备上' : '连接未完成，请检查网络后重试';
      }
    } finally {
      if (valid(generation)) {
        busy = false;
        notifyListeners();
      }
    }
  }

  Future<void> refresh() async {
    if (busy || _scope == null) return;
    busy = true;
    notifyListeners();
    final generation = _generation;
    try {
      await _refresh(generation);
    } finally {
      if (valid(generation)) {
        busy = false;
        notifyListeners();
      }
    }
  }

  Future<void> _refresh(int generation, {Map<String, dynamic>? initial}) async {
    try {
      final result = initial ?? await api.timetable();
      if (!valid(generation)) return;
      if (field(result['sessionScope']).isNotEmpty &&
          result['sessionScope'] != _scope) {
        _cleanupScope = _scope;
        cleanupRequired = true;
        _scope = null;
        timetable = null;
        state = ConnectionState.error;
        notice = '账号状态已变化，已隐藏旧课表，请重新连接';
        notifyListeners();
        try {
          await _invalidate(null);
          cleanupRequired = false;
          _cleanupScope = null;
        } catch (_) {
          notice = '账号已变化；本机清理失败，请重试清理';
        }
        return;
      }
      if (result['session'] == 'expired') {
        state = ConnectionState.expired;
        notice = '学校登录已过期，本机课表仍可查看';
        return;
      }
      if (result['sessionScope'] != _scope) {
        state = ConnectionState.error;
        notice = '学校会话暂时无法确认，已保留本机课表';
        return;
      }
      final module = object(object(result['modules'])['timetable']);
      final data = object(module['data']);
      if (module['code'] == 'EMPTY' && result['session'] == 'valid') {
        state = ConnectionState.noCourses;
        notice = timetable == null ? '学校本次返回暂无课程' : '学校本次返回暂无课程，继续保留上次成功课表';
        return;
      }
      if (result['session'] != 'valid' ||
          module['status'] != 'ok' ||
          data['kbList'] is! List ||
          data['practice'] is! List ||
          object(data['term']).isEmpty) {
        state = ConnectionState.error;
        notice = '读取失败，已保留上次成功课表';
        return;
      }
      final incoming = Timetable.fromJson(data);
      // An unrecognized nonempty row must not silently replace a good snapshot.
      if (incoming.courses.length != (data['kbList'] as List).length ||
          incoming.practice.length != (data['practice'] as List).length ||
          incoming.courses.any(
            (c) =>
                c.day < 1 || c.day > 7 || c.periods.isEmpty || c.weeks.isEmpty,
          )) {
        state = ConnectionState.error;
        notice = '课表数据不完整，已保留上次成功课表';
        return;
      }
      if (incoming.empty) {
        state = ConnectionState.noCourses;
        notice = timetable == null ? '学校本次返回暂无课程' : '学校本次返回暂无课程，继续保留上次成功课表';
        return;
      }
      final previous = timetable;
      if (previous != null &&
          previous.year == incoming.year &&
          previous.term == incoming.term) {
        incoming.termStart = previous.termStart;
        if (incoming.periods.isEmpty) incoming.periods.addAll(previous.periods);
      }
      timetable = incoming;
      state = ConnectionState.connected;
      notice = '课表已更新';
      try {
        await _persist(generation);
      } catch (_) {
        if (valid(generation)) notice = '课表已读取，但本机保存失败，请勿依赖离线查看';
      }
    } catch (_) {
      if (valid(generation)) {
        state = ConnectionState.error;
        notice = '网络或读取失败，已保留上次成功课表';
      }
    }
  }

  Future<void> logout() async {
    final oldScope = _scope ?? _cleanupScope;
    _cleanupScope = oldScope;
    cleanupRequired = true;
    final generation = ++_generation;
    _scope = null;
    timetable = null;
    busy = true;
    state = ConnectionState.disconnected;
    notice = null;
    notifyListeners();
    try {
      try {
        await _invalidate(oldScope);
      } finally {
        await api.logout();
      }
      if (valid(generation)) {
        cleanupRequired = false;
        _cleanupScope = null;
        notice = '已退出并清除本机课表';
      }
    } catch (_) {
      if (valid(generation)) {
        state = ConnectionState.error;
        notice = '清理未完成，请点击重试清理；离线数据可能仍在设备上';
      }
    } finally {
      if (valid(generation)) {
        busy = false;
        notifyListeners();
      }
    }
  }

  Future<void> setTermStart(DateTime date) async {
    if (timetable == null) return;
    timetable!.termStart = DateTime(date.year, date.month, date.day);
    await _saveSettings();
  }

  Future<void> useHandanPeriods() async {
    if (timetable == null) return;
    timetable!.periods
      ..clear()
      ..addAll(handanPeriods);
    await _saveSettings();
  }

  Future<void> _saveSettings() async {
    try {
      await _persist(_generation);
    } catch (_) {
      notice = '设置保存失败，下次打开可能需要重新设置';
    }
    notifyListeners();
  }
}
