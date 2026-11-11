Map<String, dynamic> object(Object? value) => value is Map
    ? value.map((key, value) => MapEntry(key.toString(), value))
    : {};
String field(Object? value) => value is String || value is num ? '$value' : '';

/// Accept only explicit school week/period expressions. Never guess all weeks.
List<int> numbers(String source, {int max = 60}) {
  // Normalize known typography, then require EVERY segment to match. Partial
  // parsing would silently drop meetings and overwrite a complete snapshot.
  if (source.length > 250 || max < 1 || max > 60) return [];
  final normalized = source
      .replaceAllMapped(
        RegExp(r'[０-９]'),
        (m) => '${m[0]!.codeUnitAt(0) - 0xff10}',
      )
      .replaceAll(RegExp(r'[\s\u200b-\u200d\ufeff]'), '')
      .replaceAll('（', '(')
      .replaceAll('）', ')')
      .replaceAll(RegExp(r'[－—–−～~至到]'), '-')
      .replaceAll('，', ',')
      .replaceAll('、', ',')
      .replaceAll('；', ',')
      .replaceAll(';', ',');
  final result = <int>{};
  for (final raw in normalized.split(',')) {
    final match = RegExp(
            r'^(?:第)?(\d{1,2})(?:-(?:第)?(\d{1,2}))?(?:[周节])?(?:\(([单双])(?:周)?\)(?:周)?|([单双])(?:周)?)?$')
        .firstMatch(raw);
    if (match == null) return [];
    final first = int.tryParse(match[1]!);
    final last = int.tryParse(match[2] ?? match[1]!);
    if (first == null ||
        last == null ||
        first < 1 ||
        last > max ||
        last < first) {
      return [];
    }
    final parity = match[3] ?? match[4];
    for (var i = first; i <= last; i++) {
      if ((parity != '单' || i.isOdd) && (parity != '双' || i.isEven)) {
        result.add(i);
      }
    }
  }
  return result.toList()..sort();
}

class Course {
  Course(
    this.name,
    this.teacher,
    this.room,
    this.day,
    this.periodText,
    this.weekText,
  );
  final String name, teacher, room, periodText, weekText;
  final int day;
  List<int> get periods => numbers(periodText, max: 30);
  List<int> get weeks => numbers(weekText);
  bool occurs(int week, int weekday) => day == weekday && weeks.contains(week);
  factory Course.fromJson(Map<String, dynamic> j) => Course(
        field(j['kcmc']),
        field(j['xm']),
        field(j['cdmc']),
        int.tryParse(field(j['xqj'])) ?? 0,
        field(j['jcs']),
        field(j['zcd']),
      );
  Map<String, dynamic> toJson() => {
        'kcmc': name,
        'xm': teacher,
        'cdmc': room,
        'xqj': day,
        'jcs': periodText,
        'zcd': weekText,
      };
}

class Practice {
  Practice(this.name, this.teacher, this.weeks);
  final String name, teacher, weeks;
  factory Practice.fromJson(Map<String, dynamic> j) =>
      Practice(field(j['name']), field(j['teacher']), field(j['weeks']));
  Map<String, dynamic> toJson() => {
        'name': name,
        'teacher': teacher,
        'weeks': weeks,
      };
}

class Period {
  const Period(this.number, this.start, this.end);
  final int number;
  final String start, end;
  Map<String, dynamic> toJson() => {
        'number': number,
        'start': start,
        'end': end,
      };
}

const handanPeriods = [
  Period(1, '08:00', '08:40'),
  Period(2, '08:45', '09:25'),
  Period(3, '09:45', '10:25'),
  Period(4, '10:30', '11:10'),
  Period(5, '11:15', '11:55'),
  Period(6, '14:30', '15:10'),
  Period(7, '15:15', '15:55'),
  Period(8, '16:15', '16:55'),
  Period(9, '17:00', '17:40'),
  Period(10, '17:45', '18:25'),
  Period(11, '19:00', '19:40'),
  Period(12, '19:45', '20:25'),
  Period(13, '20:30', '21:10'),
];

class Timetable {
  Timetable(
    this.year,
    this.term,
    this.courses,
    this.practice,
    this.periods,
    this.savedAt, {
    this.termStart,
  });
  final String year, term;
  final List<Course> courses;
  final List<Practice> practice;
  final List<Period> periods;
  final DateTime savedAt;
  DateTime? termStart;
  bool get empty => courses.isEmpty && practice.isEmpty;
  DateTime? get effectiveStart =>
      termStart ??
      (year == '2026' && term == '3' ? DateTime(2026, 9, 14) : null);
  int? weekAt(DateTime day) {
    final start = effectiveStart;
    if (start == null) return null;
    final days = DateTime.utc(
      day.year,
      day.month,
      day.day,
    ).difference(DateTime.utc(start.year, start.month, start.day)).inDays;
    return days < 0 ? 0 : days ~/ 7 + 1;
  }

  List<Course> on(int week, int weekday) =>
      courses.where((c) => c.occurs(week, weekday)).toList()
        ..sort(
          (a, b) => (a.periods.firstOrNull ?? 99).compareTo(
            b.periods.firstOrNull ?? 99,
          ),
        );
  String timeFor(Course c) {
    final selected = periods.where((p) => c.periods.contains(p.number)).toList()
      ..sort((a, b) => a.number.compareTo(b.number));
    return selected.isEmpty
        ? '时间待校准'
        : '${selected.first.start}–${selected.last.end}';
  }

  Course? nextAt(DateTime now) {
    final week = weekAt(now);
    if (week == null) return null;
    final time =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    for (final c in on(week, now.weekday)) {
      final slots = periods.where((p) => c.periods.contains(p.number)).toList();
      if (slots.isNotEmpty && slots.last.end.compareTo(time) > 0) return c;
    }
    return null;
  }

  factory Timetable.fromJson(Map<String, dynamic> j, {DateTime? now}) {
    final term = object(j['term']);
    final periods = <Period>[];
    for (final raw in j['periods'] is List ? j['periods'] as List : []) {
      final p = object(raw);
      final n = int.tryParse(field(p['number']));
      final s = field(p['start']), e = field(p['end']);
      if (n != null &&
          n > 0 &&
          n <= 30 &&
          RegExp(r'^(?:[01]\d|2[0-3]):[0-5]\d$').hasMatch(s) &&
          RegExp(r'^(?:[01]\d|2[0-3]):[0-5]\d$').hasMatch(e) &&
          s.compareTo(e) < 0) {
        periods.add(Period(n, s, e));
      }
    }
    periods.sort((a, b) => a.number.compareTo(b.number));
    return Timetable(
      field(term['xnm']),
      field(term['xqm']),
      (j['kbList'] is List ? j['kbList'] as List : [])
          .map((e) => Course.fromJson(object(e)))
          .where((c) => c.name.isNotEmpty)
          .toList(),
      (j['practice'] is List ? j['practice'] as List : [])
          .map((e) => Practice.fromJson(object(e)))
          .where((p) => p.name.isNotEmpty)
          .toList(),
      periods,
      DateTime.tryParse(field(j['savedAt'])) ?? now ?? DateTime.now(),
      termStart: DateTime.tryParse(field(j['termStart'])),
    );
  }
  Map<String, dynamic> toJson() => {
        'term': {'xnm': year, 'xqm': term},
        'kbList': courses.map((c) => c.toJson()).toList(),
        'practice': practice.map((p) => p.toJson()).toList(),
        'periods': periods.map((p) => p.toJson()).toList(),
        'savedAt': savedAt.toIso8601String(),
        if (termStart != null) 'termStart': termStart!.toIso8601String(),
      };
}
