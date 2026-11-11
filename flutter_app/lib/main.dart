import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'academic_store.dart' as academic;
import 'domain.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final store = academic.AcademicStore(
    academic.NativeAcademicApi(),
    academic.DeviceSecureCache(),
  );
  runApp(CampusApp(store: store));
  store.restore();
}

class CampusApp extends StatelessWidget {
  const CampusApp({super.key, required this.store});
  final academic.AcademicStore store;
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: '邯院通 · 核心验证版',
        debugShowCheckedModeBanner: false,
        locale: const Locale('zh', 'CN'),
        supportedLocales: const [Locale('zh', 'CN')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.light,
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xff268678),
            brightness: Brightness.light,
          ),
          scaffoldBackgroundColor: const Color(0xfff5f7f6),
          appBarTheme: const AppBarTheme(
            backgroundColor: Color(0xfff5f7f6),
            centerTitle: false,
          ),
          visualDensity: VisualDensity.compact,
        ),
        home: CampusHome(store: store),
      );
}

class CampusHome extends StatefulWidget {
  const CampusHome({super.key, required this.store});
  final academic.AcademicStore store;
  @override
  State<CampusHome> createState() => _CampusHomeState();
}

class _CampusHomeState extends State<CampusHome> {
  int tab = 0;
  bool weekView = false;
  int? selectedWeek;
  int selectedDay = DateTime.now().weekday;
  academic.AcademicStore get store => widget.store;
  @override
  void initState() {
    super.initState();
    store.addListener(changed);
  }

  void changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    store.removeListener(changed);
    super.dispose();
  }

  Widget panel(Widget child) => Card(
        elevation: 0,
        color: Colors.white,
        child: Padding(padding: const EdgeInsets.all(16), child: child),
      );
  Widget heading(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 14, 4, 6),
        child: Text(
          text,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
      );
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Row(
            children: [
              const SizedBox(
                width: 32,
                height: 28,
                child: CustomPaint(painter: FishPainter()),
              ),
              const SizedBox(width: 8),
              Text(['邯院通', '我的课表', '学校与设置'][tab]),
            ],
          ),
          actions: [
            if (store.connected)
              IconButton(
                tooltip: '刷新课表',
                onPressed: store.busy ? null : store.refresh,
                icon: const Icon(Icons.refresh),
              ),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              if (store.busy) const LinearProgressIndicator(minHeight: 2),
              if (store.notice != null)
                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  color: const Color(0xffe5f0ec),
                  child:
                      Text(store.notice!, style: const TextStyle(fontSize: 12)),
                ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 24),
                  children: tab == 0
                      ? home()
                      : tab == 1
                          ? schedule()
                          : settings(),
                ),
              ),
            ],
          ),
        ),
        bottomNavigationBar: NavigationBar(
          height: 64,
          selectedIndex: tab,
          onDestinationSelected: (v) => setState(() => tab = v),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home),
              label: '首页',
            ),
            NavigationDestination(
              icon: Icon(Icons.calendar_view_week_outlined),
              label: '课表',
            ),
            NavigationDestination(icon: Icon(Icons.tune), label: '我的'),
          ],
        ),
      );
  List<Widget> home() {
    final table = store.timetable, now = DateTime.now();
    final week = table?.weekAt(now), next = table?.nextAt(now);
    return [
      panel(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '把校园日常，轻轻装进口袋',
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              '${now.month}月${now.day}日 · ${week == null ? '教学周待校准' : week < 1 ? '学期尚未开始' : '第 $week 教学周'}',
            ),
            const SizedBox(height: 8),
            const Text(
              'Android / iOS 共用核心 · 开发验证版',
              style: TextStyle(fontSize: 11, color: Colors.black54),
            ),
          ],
        ),
      ),
      if (table == null)
        ...empty()
      else ...[
        heading('接下来'),
        if (next != null)
          course(next, table)
        else
          panel(
            Text(
              week == null
                  ? '请先设置本学期第一教学周日期'
                  : table.periods.isEmpty
                      ? '请在设置中确认上课时间表'
                      : '今天没有后续课程',
            ),
          ),
        heading('今日课程'),
        ...day(table, week, now.weekday),
        if (table.practice.isNotEmpty) ...[
          heading('实践教学 · 单独安排'),
          ...table.practice.map(
            (p) => panel(
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    p.name,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  Text(
                    '${p.teacher} · ${p.weeks}周',
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        ],
        saved(table),
      ],
    ];
  }

  List<Widget> empty() => [
        panel(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '连接学校，带走自己的课表',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                store.state == academic.ConnectionState.noCourses
                    ? '学校本次查询暂无课程。可以稍后刷新。'
                    : '在学校官方页面完成登录，读取成功后可关闭重开、离线查看。',
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: store.busy ? null : store.connect,
                icon: const Icon(Icons.school_outlined),
                label: const Text('连接邯郸学院'),
              ),
            ],
          ),
        ),
      ];
  List<Widget> day(Timetable table, int? week, int weekday) {
    if (week == null) return [panel(const Text('教学周未设置，请在“我的”中校准。'))];
    final rows = table.on(week, weekday);
    return rows.isEmpty
        ? [panel(const Text('当天没有已安排课程'))]
        : rows.map((c) => course(c, table)).toList();
  }

  Widget course(Course c, Timetable table) => panel(
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 4,
              height: 54,
              decoration: BoxDecoration(
                color: const Color(0xff47998a),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    c.name,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    '${c.periodText}节 · ${table.timeFor(c)}',
                    style: const TextStyle(fontSize: 12),
                  ),
                  Text(
                    '${c.room.isEmpty ? '教室待定' : c.room} · ${c.teacher.isEmpty ? '教师待定' : c.teacher}',
                    style: const TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                  Text(
                    '${c.weekText}周',
                    style: const TextStyle(fontSize: 11, color: Colors.black54),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
  Widget saved(Timetable t) => Padding(
        padding: const EdgeInsets.all(10),
        child: Text(
          '学年 ${t.year} · 学期 ${t.term}\n本机保存：${t.savedAt.toLocal().toString().split('.').first}\n仅供本人使用；以学校最新安排为准。',
          style: const TextStyle(fontSize: 11, color: Colors.black54),
        ),
      );
  List<Widget> schedule() {
    final t = store.timetable;
    if (t == null) return empty();
    final current = t.weekAt(DateTime.now());
    final week = selectedWeek ?? (current == null || current < 1 ? 1 : current);
    return [
      SegmentedButton<bool>(
        segments: const [
          ButtonSegment(value: false, label: Text('日视图')),
          ButtonSegment(value: true, label: Text('周视图')),
        ],
        selected: {weekView},
        onSelectionChanged: (s) => setState(() => weekView = s.first),
      ),
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            tooltip: '上一周',
            onPressed:
                week > 1 ? () => setState(() => selectedWeek = week - 1) : null,
            icon: const Icon(Icons.chevron_left),
          ),
          Text(
            '第 $week 教学周',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          IconButton(
            tooltip: '下一周',
            onPressed: week < 60
                ? () => setState(() => selectedWeek = week + 1)
                : null,
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      ),
      if (!weekView)
        Wrap(
          spacing: 4,
          children: [
            for (var d = 1; d <= 7; d++)
              ChoiceChip(
                label: Text(['一', '二', '三', '四', '五', '六', '日'][d - 1]),
                selected: selectedDay == d,
                onSelected: (_) => setState(() => selectedDay = d),
              ),
          ],
        ),
      if (t.effectiveStart == null) panel(const Text('尚未设置开学日期。当前按所选教学周查看。')),
      for (final d in weekView ? [1, 2, 3, 4, 5, 6, 7] : [selectedDay]) ...[
        heading('星期${['一', '二', '三', '四', '五', '六', '日'][d - 1]}'),
        ...day(t, week, d),
      ],
      if (t.practice.isNotEmpty) ...[
        heading('实践教学'),
        ...t.practice.map(
          (p) => panel(Text('${p.name}\n${p.teacher} · ${p.weeks}周')),
        ),
      ],
      saved(t),
    ];
  }

  Future<void> connectSchool() async {
    if (store.timetable != null) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('重新连接学校？'),
          content: const Text('将清除当前账号的本机离线课表，再打开学校官方登录页。取消后续登录也不会恢复旧课表。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('保留课表'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('清除并登录'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    await store.connect();
  }

  List<Widget> settings() {
    final t = store.timetable;
    return [
      heading('学校连接'),
      panel(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '邯郸学院',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
            ),
            const SizedBox(height: 6),
            const Text(
              '密码仅在学校官方页面输入。登录会话由原生层管理；课表在本机安全存储。',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              children: [
                FilledButton(
                  onPressed: store.busy ? null : connectSchool,
                  child: Text(store.connected ? '重新登录 / 切换账号' : '连接学校'),
                ),
                if (store.connected || store.cleanupRequired)
                  OutlinedButton(
                    onPressed: store.busy ? null : store.logout,
                    child: Text(store.cleanupRequired ? '重试清理' : '退出并清除课表'),
                  ),
              ],
            ),
            const Text(
              '切换账号会先清除当前课表；取消登录不会恢复上一账号。',
              style: TextStyle(fontSize: 11, color: Colors.black54),
            ),
          ],
        ),
      ),
      if (t != null) ...[
        heading('教学安排'),
        panel(
          Column(
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('第一教学周 · 周一'),
                subtitle: Text(
                  t.effectiveStart?.toString().split(' ').first ??
                      '未设置：当前学期没有默认日期',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  final date = await showDatePicker(
                    context: context,
                    initialDate: t.effectiveStart ?? DateTime.now(),
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2040),
                  );
                  if (date != null) {
                    if (date.weekday != DateTime.monday) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('请选择第一教学周的周一')),
                        );
                      }
                      return;
                    }
                    await store.setTermStart(date);
                  }
                },
              ),
              const Divider(),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('上课时间表'),
                subtitle: Text(
                  t.periods.isEmpty
                      ? '未确认：不推算下一节时间'
                      : '已设置 ${t.periods.length} 节上课时间',
                ),
                onTap: () async {
                  final yes = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('使用邯郸学院 13 节时间表？'),
                      content: const Text(
                        '来源为用户提供的40分钟课表，并非学校实时接口。第1节08:00，第6节14:30，第11节19:00。请先确认适用于当前安排。',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('取消'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text('确认使用'),
                        ),
                      ],
                    ),
                  );
                  if (yes == true) await store.useHandanPeriods();
                },
              ),
            ],
          ),
        ),
        saved(t),
      ],
      heading('关于本次验证'),
      panel(
        const Text(
          '仅验证官方网页登录 → 真实课表 → 安全保存 → 重开 → 离线查看。\n\n独立学生项目，非学校官方应用。此版本不提供成绩、考试、生活支付或应用更新入口。',
          style: TextStyle(fontSize: 12),
        ),
      ),
    ];
  }
}

class FishPainter extends CustomPainter {
  const FishPainter();
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = const Color(0xff268678);
    canvas.drawOval(Rect.fromLTWH(1, 7, 23, 14), p);
    canvas.drawPath(
      Path()
        ..moveTo(20, 14)
        ..lineTo(31, 5)
        ..lineTo(31, 23)
        ..close(),
      p,
    );
    canvas.drawCircle(const Offset(7, 12), 1.7, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(FishPainter oldDelegate) => false;
}
