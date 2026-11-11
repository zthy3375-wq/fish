import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hanyuantong_flutter/academic_store.dart' as a;
import 'package:hanyuantong_flutter/domain.dart';
import 'package:hanyuantong_flutter/main.dart';

Map<String, dynamic> payload({
  String scope = 'A',
  String name = '高等数学',
  String session = 'valid',
  bool empty = false,
}) =>
    {
      'session': session,
      'sessionScope': scope,
      'password': 'NEVER_SAVE',
      'modules': {
        'timetable': {
          'status': 'ok',
          'data': {
            'term': {'xnm': '2026', 'xqm': '3'},
            'kbList': empty
                ? []
                : [
                    {
                      'kcmc': name,
                      'xm': '测试教师',
                      'cdmc': '测试楼101',
                      'xqj': '1',
                      'jcs': '1-2',
                      'zcd': '1-18(单)',
                      'secret': 'NEVER_SAVE',
                    },
                  ],
            'practice': [],
          },
        },
      },
    };

class FakeApi implements a.AcademicApi {
  Map<String, dynamic> response = payload();
  Map<String, dynamic> loginResponse = {
    'session': 'valid',
    'sessionScope': 'A',
  };
  Completer<Map<String, dynamic>>? pending;
  bool fail = false;
  @override
  Future<Map<String, dynamic>> login() async => loginResponse;
  @override
  Future<void> logout() async {}
  @override
  Future<Map<String, dynamic>> timetable() async {
    if (fail) throw Exception('offline');
    return pending?.future ?? response;
  }
}

class MemoryCache implements a.SecureCache {
  final values = <String, String>{};
  bool fail = false;
  bool failDelete = false;
  Completer<void>? blocked;
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    await blocked?.future;
    if (fail) throw Exception('disk');
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    if (failDelete) throw Exception('delete unavailable');
    values.remove(key);
  }
}

void main() {
  test(
    'week parity, Chinese delimiters, multi periods, bounded invalid ranges',
    () {
      expect(numbers('1-8(单),10,12'), [1, 3, 5, 7, 10, 12]);
      expect(numbers('2-8（双）'), [2, 4, 6, 8]);
      expect(numbers('1-2节，5、7'), [1, 2, 5, 7]);
      expect(numbers('0-9999,8-2,no'), isEmpty);
      expect(numbers('1-8,10/12周'), isEmpty);
      expect(numbers('第１９－２１（单）周'), [19, 21]);
      expect(numbers('1-8,garbage'), isEmpty);
      expect(numbers('1周2'), isEmpty);
      expect(numbers('第1至第6周(双周);8周'), [2, 4, 6, 8]);
    },
  );
  test('known autumn only and teaching week boundary', () {
    final t = Timetable.fromJson(
      object(object(object(payload()['modules'])['timetable'])['data']),
    );
    expect(t.weekAt(DateTime(2026, 9, 14)), 1);
    expect(t.weekAt(DateTime(2026, 9, 21)), 2);
    expect(t.weekAt(DateTime(2026, 9, 13)), 0);
    expect(t.on(1, 1).length, 1);
    expect(t.on(2, 1), isEmpty);
    final other = Timetable.fromJson({
      'term': {'xnm': '2027', 'xqm': '3'},
    });
    expect(other.effectiveStart, isNull);
  });
  test('whitelist no secrets; practice stays separate; no guessed times', () {
    final t = Timetable.fromJson({
      'term': {'xnm': '2026', 'xqm': '3'},
      'kbList': [
        {
          'kcmc': 'Math',
          'xm': 'T',
          'cdmc': 'R',
          'xqj': 1,
          'jcs': '1-2',
          'zcd': '1-18',
          'token': 'bad',
        },
      ],
      'practice': [
        {'name': 'Practice', 'teacher': 'T', 'weeks': '3-4'},
      ],
      'cookies': 'bad',
    });
    expect(t.courses.length, 1);
    expect(t.practice.length, 1);
    expect(jsonEncode(t.toJson()), isNot(contains('bad')));
    expect(t.nextAt(DateTime(2026, 9, 14, 8)), isNull);
    t.periods.addAll(handanPeriods);
    expect(t.nextAt(DateTime(2026, 9, 14, 8))?.name, 'Math');
    expect(t.timeFor(t.courses.first), '08:00–09:25');
  });
  test('successful fetch restart offline exact same scoped cache', () async {
    final api = FakeApi(), cache = MemoryCache();
    final first = a.AcademicStore(api, cache);
    await first.connect();
    expect(first.timetable!.courses.first.name, '高等数学');
    expect(cache.values.values.join(), isNot(contains('NEVER_SAVE')));
    api.fail = true;
    final reopened = a.AcademicStore(api, cache);
    await reopened.restore();
    expect(reopened.state, a.ConnectionState.cached);
    await reopened.refresh();
    expect(reopened.timetable!.courses.length, 1);
    expect(reopened.state, a.ConnectionState.error);
  });
  test('empty errors expired malformed preserve successful table', () async {
    final api = FakeApi(), cache = MemoryCache();
    final s = a.AcademicStore(api, cache);
    await s.connect();
    final saved = Map.of(cache.values);
    api.response = payload(empty: true);
    await s.refresh();
    expect(s.state, a.ConnectionState.noCourses);
    expect(s.timetable!.courses.length, 1);
    expect(cache.values, saved);
    api.response = payload(session: 'expired');
    await s.refresh();
    expect(s.state, a.ConnectionState.expired);
    expect(s.timetable, isNotNull);
    api.response = {
      'session': 'valid',
      'sessionScope': 'A',
      'modules': {
        'timetable': {
          'status': 'ok',
          'data': {
            'term': {'xnm': '2026'},
            'kbList': [],
          },
        },
      },
    };
    await s.refresh();
    expect(s.state, a.ConnectionState.error);
    expect(cache.values, saved);
  });
  test(
    'first explicit empty distinct from errors and no fake courses',
    () async {
      final api = FakeApi()..response = payload(empty: true);
      final s = a.AcademicStore(api, MemoryCache());
      await s.connect();
      expect(s.state, a.ConnectionState.noCourses);
      expect(s.timetable, isNull);
    },
  );
  test('mismatched response scope cannot replace active cache', () async {
    final api = FakeApi(), cache = MemoryCache();
    final s = a.AcademicStore(api, cache);
    await s.connect();
    api.response = payload(scope: 'B', name: 'OTHER');
    await s.refresh();
    expect(s.timetable, isNull);
    final reopened = a.AcademicStore(api, cache);
    await reopened.restore();
    expect(reopened.timetable, isNull);
    expect(cache.values.values.join(), isNot(contains('OTHER')));
  });
  test(
    'switch immediately clears; cancelled login never restores old account',
    () async {
      final api = FakeApi(), cache = MemoryCache();
      final s = a.AcademicStore(api, cache);
      await s.connect();
      api.loginResponse = {'cancelled': true};
      final operation = s.connect();
      expect(s.timetable, isNull);
      await operation;
      expect(s.timetable, isNull);
      final reopen = a.AcademicStore(api, cache);
      await reopen.restore();
      expect(reopen.timetable, isNull);
      expect(cache.values, isEmpty);
    },
  );
  test('logout during in-flight fetch rejects delayed response', () async {
    final api = FakeApi(), cache = MemoryCache();
    final s = a.AcademicStore(api, cache);
    await s.connect();
    api.pending = Completer();
    final refresh = s.refresh();
    final logout = s.logout();
    expect(s.timetable, isNull);
    await logout;
    api.pending!.complete(payload(name: 'LATE'));
    await refresh;
    expect(s.timetable, isNull);
    expect(cache.values, isEmpty);
  });
  test(
    'logout waits out slow persistence and clears completed old writes',
    () async {
      final api = FakeApi(), cache = MemoryCache();
      final s = a.AcademicStore(api, cache);
      await s.connect();
      cache.blocked = Completer();
      final refresh = s.refresh();
      await Future<void>.delayed(Duration.zero);
      final logout = s.logout();
      cache.blocked!.complete();
      await Future.wait([refresh, logout]);
      expect(cache.values, isEmpty);
      expect(s.timetable, isNull);
    },
  );
  test('settings persist and future term does not inherit date', () async {
    final api = FakeApi(), cache = MemoryCache();
    final s = a.AcademicStore(api, cache);
    await s.connect();
    await s.setTermStart(DateTime(2026, 9, 7));
    await s.useHandanPeriods();
    await s.refresh();
    expect(s.timetable!.effectiveStart, DateTime(2026, 9, 7));
    expect(s.timetable!.periods.length, 13);
    final data = object(
      object(object(api.response['modules'])['timetable'])['data'],
    );
    data['term'] = {'xnm': '2027', 'xqm': '12'};
    api.response = {
      'session': 'valid',
      'sessionScope': 'A',
      'modules': {
        'timetable': {'status': 'ok', 'data': data},
      },
    };
    await s.refresh();
    expect(s.timetable!.effectiveStart, isNull);
    expect(s.timetable!.periods, isEmpty);
  });
  test(
    'persistence failure is visible and does not claim offline success',
    () async {
      final api = FakeApi(), cache = MemoryCache();
      final s = a.AcademicStore(api, cache);
      await s.connect();
      cache.fail = true;
      await s.refresh();
      expect(s.notice, contains('保存失败'));
      expect(s.timetable, isNotNull);
    },
  );
  test('native EMPTY code preserves prior success', () async {
    final api = FakeApi();
    final cache = MemoryCache();
    final s = a.AcademicStore(api, cache);
    await s.connect();
    api.response = {
      'session': 'valid',
      'sessionScope': 'A',
      'modules': {
        'timetable': {'status': 'error', 'code': 'EMPTY'},
      },
    };
    await s.refresh();
    expect(s.state, a.ConnectionState.noCourses);
    expect(s.timetable, isNotNull);
  });
  test('login returned timetable is consumed without a second query', () async {
    final api = FakeApi()
      ..loginResponse = payload()
      ..fail = true;
    final s = a.AcademicStore(api, MemoryCache());
    await s.connect();
    expect(s.state, a.ConnectionState.connected);
    expect(s.timetable, isNotNull);
  });
  test(
    'unparseable schedule preserves cache rather than silently hiding course',
    () async {
      final api = FakeApi();
      final cache = MemoryCache();
      final s = a.AcademicStore(api, cache);
      await s.connect();
      final before = Map.of(cache.values);
      final broken = payload();
      final data = object(
        object(object(broken['modules'])['timetable'])['data'],
      );
      (data['kbList'] as List).first['zcd'] = 'unknown';
      api.response = broken;
      await s.refresh();
      expect(s.state, a.ConnectionState.error);
      expect(cache.values, before);
    },
  );
  test(
    'corrupt or mismatched encrypted record never exposes another scope',
    () async {
      final cache = MemoryCache();
      final s = a.AcademicStore(FakeApi(), cache);
      cache.values[a.AcademicStore.activeKey] = 'A';
      cache.values[s.key('A')] = jsonEncode({
        'scope': 'B',
        'timetable': {'term': {}, 'kbList': []},
      });
      await s.restore();
      expect(s.timetable, isNull);
      expect(s.state, a.ConnectionState.error);
    },
  );
  test('MethodChannel contract uses only fixed native methods', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(a.NativeAcademicApi.channel, (call) async {
      calls.add(call.method);
      expect(call.arguments, isNull);
      if (call.method == 'logout') return null;
      return payload();
    });
    final native = a.NativeAcademicApi();
    expect((await native.login())['session'], 'valid');
    expect((await native.timetable())['sessionScope'], 'A');
    await native.logout();
    expect(calls, ['login', 'getTimetable', 'logout']);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(a.NativeAcademicApi.channel, null);
  });
  test('logout tombstone prevents reopening when key deletion fails', () async {
    final api = FakeApi();
    final cache = MemoryCache();
    final s = a.AcademicStore(api, cache);
    await s.connect();
    cache.failDelete = true;
    await s.logout();
    expect(s.timetable, isNull);
    expect(s.cleanupRequired, isTrue);
    final reopened = a.AcademicStore(api, cache);
    await reopened.restore();
    expect(reopened.timetable, isNull);
    cache.failDelete = false;
    await s.logout();
    expect(s.cleanupRequired, isFalse);
    expect(cache.values, isEmpty);
  });
  test('total storage failure keeps cleanup retry reachable', () async {
    final api = FakeApi();
    final cache = MemoryCache();
    final s = a.AcademicStore(api, cache);
    await s.connect();
    cache.fail = true;
    cache.failDelete = true;
    await s.logout();
    expect(s.timetable, isNull);
    expect(s.cleanupRequired, isTrue);
    expect(s.notice, contains('重试清理'));
    cache.fail = false;
    cache.failDelete = false;
    await s.logout();
    expect(s.cleanupRequired, isFalse);
    expect(cache.values, isEmpty);
  });
  testWidgets('compact light app connects and shows shared timetable tabs', (
    tester,
  ) async {
    final s = a.AcademicStore(FakeApi(), MemoryCache());
    await tester.pumpWidget(CampusApp(store: s));
    expect(find.text('连接邯郸学院'), findsOneWidget);
    await tester.tap(find.text('连接邯郸学院'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('课表'));
    await tester.pumpAndSettle();
    expect(find.text('日视图'), findsOneWidget);
    await tester.tap(find.text('周视图'));
    await tester.pumpAndSettle();
    expect(find.text('星期一'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('settings switching account removes previous schedule', (
    tester,
  ) async {
    final api = FakeApi();
    final s = a.AcademicStore(api, MemoryCache());
    await s.connect();
    await tester.pumpWidget(CampusApp(store: s));
    await tester.tap(find.text('我的'));
    await tester.pumpAndSettle();
    api.loginResponse = {'cancelled': true};
    await tester.tap(find.text('重新登录 / 切换账号'));
    await tester.pumpAndSettle();
    expect(find.text('清除并登录'), findsOneWidget);
    await tester.tap(find.text('清除并登录'));
    await tester.pumpAndSettle();
    expect(s.timetable, isNull);
    expect(find.text('已取消登录，未恢复上一账号课表'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      '320px and 1.3 text scale home week settings render without overflow',
      (tester) async {
    if (const bool.fromEnvironment('CAPTURE_CORE')) {
      await tester.runAsync(() async {
        final bytes =
            await File('/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc')
                .readAsBytes();
        for (final family in ['Ahem', 'Roboto']) {
          final loader = FontLoader(family)
            ..addFont(Future.value(bytes.buffer.asByteData()));
          await loader.load();
        }
        final icons = await File(
                '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf')
            .readAsBytes();
        await (FontLoader('MaterialIcons')
              ..addFont(Future.value(icons.buffer.asByteData())))
            .load();
      });
    }
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final s = a.AcademicStore(FakeApi(), MemoryCache());
    await s.connect();
    const boundaryKey = Key('capture');
    await tester.pumpWidget(
        RepaintBoundary(key: boundaryKey, child: CampusApp(store: s)));
    await tester.pumpAndSettle();
    Future<void> capture(String name) async {
      expect(tester.takeException(), isNull);
      if (!const bool.fromEnvironment('CAPTURE_CORE')) return;
      await tester.runAsync(() async {
        final boundary =
            tester.renderObject<RenderRepaintBoundary>(find.byKey(boundaryKey));
        final image = await boundary.toImage();
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        await File('/tmp/flutter-core-$name.png')
            .writeAsBytes(data!.buffer.asUint8List());
        image.dispose();
      });
    }

    await capture('home');
    await tester.tap(find.text('课表'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('周视图'));
    await tester.pumpAndSettle();
    await capture('week');
    await tester.tap(find.text('我的'));
    await tester.pumpAndSettle();
    await capture('settings');
  });
}
