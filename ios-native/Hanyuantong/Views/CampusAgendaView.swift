import SwiftUI

struct CampusAgendaView:View {
    @EnvironmentObject var campus:CampusStore
    @EnvironmentObject var learning:LearningStore
    @State private var day=Date()
    @State private var task:CampusTask?
    private var dateKey:String { CampusTheme.date(day,format:"yyyy-MM-dd") }
    private var tasks:[CampusTask] { campus.tasks.filter { t in
        t.plannedDay == dateKey || [t.plannedAt,t.deadline].compactMap{$0}.contains { ScheduleMath.calendar.isDate($0,inSameDayAs:day) }
    } }
    var body:some View {
        List {
            DatePicker("日期",selection:$day,displayedComponents:.date)
            Section("课程") {
                let courses=campus.courses(on:day)
                if courses.isEmpty { Text("当日无已保存课程").foregroundStyle(.secondary) }
                ForEach(courses) { c in NavigationLink { CourseDetailView(course:c,occurrenceDate:day) } label: { CourseRow(course:c) } }
            }
            Section("个人待办") {
                if tasks.isEmpty { Text("当日暂无安排").foregroundStyle(.secondary) }
                ForEach(tasks) { item in Button { task=item } label: { Label(item.title,systemImage:item.completed ? "checkmark.circle.fill" : "circle") } }
            }
            Section("考试安排") {
                let exams=campus.exams.filter { NativeExamPresentation.day($0).map { ScheduleMath.calendar.isDate($0,inSameDayAs:day) } ?? false }
                if exams.isEmpty { Text("暂无当日考试记录").foregroundStyle(.secondary) }
                ForEach(exams) { item in VStack(alignment:.leading) { Text(item.name); Text([item.time,item.room].filter{!$0.isEmpty}.joined(separator:" · ")).font(.caption) } }
            }
            Section("学习通截止") {
                let items=learning.cache.items.filter { $0.deadline?.prefix(10) == Substring(dateKey) }
                if items.isEmpty { Text("暂无当日截止记录").foregroundStyle(.secondary) }
                ForEach(items) { item in Button { learning.openItem(item) } label: {
                    VStack(alignment:.leading) { Text(item.title); Text(LearningDisplay.state(item).label).font(.caption) }
                }.disabled(!item.hasLink) }
            }
        }.navigationTitle("统一日程").sheet(item:$task) { TaskEditorView(task:$0) }
    }
}

struct SemesterCalendar:View {
    @EnvironmentObject var campus:CampusStore
    @Environment(\.dismiss) var dismiss
    private var start:Date { campus.isConnected ? campus.schoolSemesterStart : campus.semesterStart }
    private var weeks:Int {
        if campus.isConnected { return min(60,campus.courses.filter{$0.source == "school"}.flatMap(\.weeks).max() ?? 0) }
        return min(60,campus.personalWeekCount)
    }
    var body:some View {
        List {
            Section("第一周周一") {
                Text(CampusTheme.date(start,format:"yyyy年M月d日"))
                Text(campus.isConnected ? "按校准日期及已保存学校课程的教学周显示。" : "按当前个人学期设置显示。").font(.footnote).foregroundStyle(.secondary)
            }
            if weeks == 0 { Text("同步学校课表后显示教学周。") }
            else {
                ForEach(1...max(1,weeks),id:\.self) { week in
                    if let monday=ScheduleMath.calendar.date(byAdding:.weekOfYear,value:week-1,to:start),
                       let sunday=ScheduleMath.calendar.date(byAdding:.day,value:6,to:monday) {
                        Button { campus.selectedDate=monday; dismiss(); campus.selectedTab = .schedule } label: {
                            HStack {
                                Text("第 \(week) 周"); Spacer()
                                Text(CampusTheme.date(monday,format:"M.d") + " – " + CampusTheme.date(sunday,format:"M.d"))
                                    .font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                            }
                        }.accessibilityHint("打开这一周的课表")
                    }
                }
            }
        }.navigationTitle("学期校历")
    }
}
