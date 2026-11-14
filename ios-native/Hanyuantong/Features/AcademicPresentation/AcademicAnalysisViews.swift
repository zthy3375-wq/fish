import SwiftUI

struct NativeGradeAnalysisView: View {
    let grades: [GradeRecord]
    let profile: AcademicProfile?
    @State private var tab = 0
    @State private var term = "all"
    @State private var query = ""
    @State private var kind = "all"
    @State private var state = "all"
    @State private var band = "all"
    @State private var sort = "term"
    private var report: NativeGradeReport { NativeGradeReport(grades) }
    private func number(_ value: Double?) -> String { value.map { String(format: "%.2f", $0) } ?? "—" }
    var body: some View {
        let report = report
        let summary = report.summary(term: term)
        Section {
            Picker("成绩视图", selection: $tab) { Text("分析概览").tag(0); Text("成绩明细").tag(1); Text("学分与性质").tag(2) }.pickerStyle(.segmented)
            Picker("成绩学期", selection: $term) { Text("全部已同步学期").tag("all"); ForEach(report.terms, id: \.self) { Text($0).tag($0) } }
            Text("仅分析本机已同步记录；单学期同步不代表完整历史。").font(.caption).foregroundStyle(CampusTheme.muted)
        }
        if grades.isEmpty { Section { Text("暂无本人已同步成绩，不使用演示数据。") } }
        if tab == 0 {
            Section("成绩概览") {
                LabeledContent("课程数 / 去重记录", value: "\(summary.courses) / \(summary.records)")
                metric("算术平均分", summary.mean, "\(summary.numericCount) 门百分制")
                metric("学分加权平均", summary.weightedMean, "\(summary.weightedCount) 门有学分")
                metric("学校绩点加权", summary.gpa, "\(summary.gpaCount) 门返回绩点及学分")
                metric("已获学分 · 参考", summary.earnedCredits, "\(summary.creditCount) 门已确认通过")
                LabeledContent("最高 / 最低分", value: "\(number(summary.max)) / \(number(summary.min))")
            }
            Section("统计口径") {
                Text("均分只统计 0–100 的数值成绩，等级和通过制不换算分数。绩点仅采用学校返回值按学分加权，不推算公式，也不等同学校官方总 GPA。")
                Text("同一课程多次公布成绩不擅自取最高或最后一次，暂不计入平均。学分按课程编号只累计一次；无编号同名多记录、学分冲突和未知结果不累计，归入首次确认通过的学期。")
                Text("\(summary.excluded) 组记录未参与平均；\(report.duplicates) 条完全重复已折叠；\(report.invalid) 条异常未参与。数值及格线参考 60 分；特殊课程以学校最终认定为准。")
                Text("\(report.records.filter { $0.credit == nil }.count) 条未提供有效学分，\(report.records.filter { $0.gpa == nil }.count) 条未提供绩点；统计仅覆盖已有字段。")
            }.font(.caption).foregroundStyle(CampusTheme.muted)
            Section("学期趋势 · 已同步学期") {
                ForEach(report.terms, id: \.self) { value in
                    let stats = report.summary(term: value)
                    Button { term = value; tab = 1 } label: {
                        VStack(alignment: .leading, spacing: 5) { Text(value); Text("平均 \(number(stats.mean)) · 绩点 \(number(stats.gpa)) · 已获 \(number(stats.earnedCredits)) 学分").font(.caption).foregroundStyle(CampusTheme.muted) }
                    }
                }
            }
            Section("成绩分布 · 去重记录") {
                ForEach(["0–59", "60–69", "70–79", "80–89", "90–100", "等级/两级制", "待公布", "未识别"], id: \.self) { value in
                    Button { band = value; tab = 1 } label: { LabeledContent(value, value: "\(report.records.filter { (term == "all" || $0.term == term) && $0.band == value }.count) 条") }
                }
            }
            Section("未通过与后续记录") {
                let failures = report.groups.filter { $0.state == .failed && (term == "all" || $0.rows.contains { $0.term == term }) }
                if failures.isEmpty { Text("已同步且可确认的课程中暂无未通过项。") }
                ForEach(failures.indices, id: \.self) { index in
                    let group = failures[index]
                    Button { query = group.rows[0].raw.name; tab = 1 } label: { Text(group.rows[0].raw.name + " · " + group.rows.map { $0.raw.score }.joined(separator: " / ")) }
                }
                Text("\(report.groups.filter(\.resolved).count) 门曾未通过，已有通过记录；\(report.groups.filter { $0.state == .unknown }.count) 组结果待核对。不会将同名多记录擅自判为挂科已解决。").font(.caption).foregroundStyle(CampusTheme.muted)
            }
        } else if tab == 1 {
            Section("筛选成绩明细") {
                TextField("搜索课程名称", text: $query)
                Picker("课程性质", selection: $kind) { Text("全部性质").tag("all"); ForEach(Array(Set(report.records.map(\.kind))).sorted(), id: \.self) { Text($0).tag($0) } }
                Picker("通过状态", selection: $state) { Text("全部状态").tag("all"); ForEach(GradeOutcome.allCases, id: \.rawValue) { Text($0.title).tag($0.rawValue) } }
                Picker("成绩区间", selection: $band) { Text("全部成绩").tag("all"); ForEach(["0–59", "60–69", "70–79", "80–89", "90–100", "等级/两级制", "待公布", "未识别"], id: \.self) { Text($0).tag($0) } }
                Picker("排序", selection: $sort) { Text("学期从新到旧").tag("term"); Text("分数从高到低").tag("score-desc"); Text("分数从低到高").tag("score-asc"); Text("学分从高到低").tag("credit"); Text("课程名称").tag("name") }
                Button("重置筛选") { term = "all"; query = ""; kind = "all"; state = "all"; band = "all"; sort = "term" }
            }
            let rows = report.filtered(term: term, query: query, kind: kind, state: state, band: band, sort: sort)
            Section("原始成绩明细 · \(rows.count) 条") {
                ForEach(rows) { row in
                    DisclosureGroup {
                        LabeledContent("学校原始成绩", value: row.raw.score.isEmpty ? "未公布" : row.raw.score)
                        LabeledContent("学校课程绩点", value: number(row.gpa))
                        LabeledContent("课程编号", value: row.raw.courseCode.isEmpty ? "未提供" : row.raw.courseCode)
                        LabeledContent("考试性质", value: row.raw.examType.isEmpty ? "未提供，不推测补考/重修" : row.raw.examType)
                        LabeledContent("原始学期", value: row.raw.term.isEmpty ? "未提供" : row.raw.term)
                        if let group = report.groups.first(where: { $0.rows.contains { $0.id == row.id } }), group.rows.count > 1 {
                            Text(group.ambiguous ? "同名多记录，课程身份待核对，暂不累计学分或替换成绩。" : "同一课程多次成绩，学分只累计一次；均分不选择替代成绩。").font(.caption)
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            HStack { Text(row.raw.name); Spacer(); Text(row.raw.score.isEmpty ? "待公布" : row.raw.score).bold() }
                            Text("\(row.term) · \(number(row.credit)) 学分 · \(row.kind) · \(row.state.title)").font(.caption).foregroundStyle(CampusTheme.muted)
                        }
                    }
                }
                if rows.isEmpty { Text("没有符合条件的已同步成绩。") }
            }
        } else {
            Section("学校返回学籍信息") {
                if let profile {
                    if !profile.name.isEmpty { LabeledContent("姓名", value: profile.name) }
                    if !profile.major.isEmpty { LabeledContent("专业", value: profile.major) }
                    if !profile.className.isEmpty { LabeledContent("班级", value: profile.className) }
                    if !profile.year.isEmpty { LabeledContent("年级", value: profile.year) }
                } else { Text("学校本次未提供有效学籍字段，不推测身份或培养要求。") }
                Text("仅保存在本机学校加密缓存；退出学校账号后清除。").font(.caption).foregroundStyle(CampusTheme.muted)
            }
            Section("课程性质与学分 · 全部已同步") {
                ForEach(Array(Set(report.records.map(\.kind))).sorted(), id: \.self) { kind in
                    let groups = report.groups.filter { $0.rows.first?.kind == kind }
                    LabeledContent(kind, value: "\(groups.count) 门 · 已获 \(number(groups.compactMap(\.credit).reduce(0, +))) 学分")
                }
                Text("仅供已同步记录参考，不代表培养方案或毕业审核。").font(.caption).foregroundStyle(CampusTheme.muted)
            }
        }
    }
    private func metric(_ title: String, _ value: Double?, _ coverage: String) -> some View {
        HStack { VStack(alignment: .leading) { Text(title); Text(coverage).font(.caption).foregroundStyle(CampusTheme.muted) }; Spacer(); Text(number(value)).bold() }
    }
}

struct NativeExamRecordsView: View {
    let exams: [ExamRecord]
    @State private var upcomingOnly = true
    var body: some View {
        let upcoming = NativeExamPresentation.upcoming(exams)
        Section("近期考试") {
            Text("今天及以后共 \(upcoming.count) 场；\(NativeExamPresentation.unknownDates(exams).count) 场日期待核对。").font(.subheadline)
            Toggle("仅看今天及以后和日期待核对", isOn: $upcomingOnly)
            Text("日期按学校时区；当天考试不推测是否已结束。请以学校最新通知为准。").font(.caption).foregroundStyle(CampusTheme.muted)
        }
        let rows = upcomingOnly ? upcoming + NativeExamPresentation.unknownDates(exams) : exams
        Section("考试安排") {
            if rows.isEmpty { Text("此范围暂无已同步考试安排，请更新核对。") }
            ForEach(rows) { exam in
                VStack(alignment: .leading, spacing: 7) {
                    HStack { Text(exam.name).font(.headline); Spacer(); Text(NativeExamPresentation.dayLabel(exam)).font(.caption).foregroundStyle(CampusTheme.muted) }
                    Text([exam.date, exam.time].filter { !$0.isEmpty }.joined(separator: " "))
                    if !exam.room.isEmpty { Label(exam.room, systemImage: "mappin.and.ellipse") }
                    if !exam.seat.isEmpty { Text("座位号：\(exam.seat)").font(.caption) }
                }.padding(.vertical, 4)
            }
        }
    }
}
