import Foundation

/// Parses bounded response data only. Never evaluate source HTML, scripts, or onclick handlers.
enum LearningHTML {
    private static let datePattern = #"(20\d{2})[-/年](\d{1,2})[-/月](\d{1,2})(?:日)?[ T\s]+(\d{1,2}):(\d{2})(?::\d{2})?"#

    static func dates(_ text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: datePattern) else { return [] }
        let source = text as NSString
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return regex.matches(in: text, range: NSRange(location: 0, length: source.length)).compactMap { match in
            let values = (1...5).compactMap { Int(source.substring(with: match.range(at: $0))) }
            guard values.count == 5 else { return nil }
            let c = DateComponents(year: values[0], month: values[1], day: values[2], hour: values[3], minute: values[4])
            guard let date = calendar.date(from: c) else { return nil }
            let roundTrip = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
            guard roundTrip.year == c.year, roundTrip.month == c.month, roundTrip.day == c.day,
                  roundTrip.hour == c.hour, roundTrip.minute == c.minute else { return nil }
            return String(format: "%04d-%02d-%02dT%02d:%02d", values[0], values[1], values[2], values[3], values[4])
        }
    }

    static func deadline(_ text: String) -> String? {
        if let label = capture(#"(?:截止(?:时间)?|结束(?:时间)?)[：:\s]*([^\n]{0,80})"#, in: text) {
            return dates(label).first
        }
        guard let label = capture(#"(?:作答时间|起止时间)[：:\s]*([^\n]{0,120})"#, in: text) else { return nil }
        let values = dates(label)
        return values.count >= 2 ? values.last : nil
    }

    static func status(_ raw: String) -> String {
        if matches("未提交|未交|待做|待提交|未完成|未开始|待考试|待重做|未作答|打回|退回", raw) { return "pending" }
        if matches("已提交|待批阅|待批改|未批阅|已批阅|已批改|已完成|已交|已交卷|已结束.*已交", raw) { return "submitted" }
        if matches("已截止|已过期|已关闭|已结束", raw) { return "closed" }
        return "unknown"
    }

    /// nil means this is not the JSON course endpoint shape; callers may try the official HTML fallback.
    /// A recognized but invalid/failed JSON response throws instead of becoming a successful empty list.
    static func coursesJSON(_ body: String) throws -> (courses: [LearningCourse], complete: Bool)? {
        try checkSize(body)
        guard let root = try? JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any] else { return nil }
        if let result = root["result"], !["1", "true"].contains(string(result).lowercased()) {
            throw LearningError(code: body.contains("请先登录") ? "AUTH" : "COURSES_SCHEMA")
        }
        guard let raw = root["channelList"] else { return nil }
        guard let channels = raw as? [[String: Any]] else { throw LearningError(code: "COURSES_SCHEMA") }
        guard channels.count <= 1_000 else { throw LearningError(code: "LIMIT") }
        var output: [LearningCourse] = []
        var indices: [String: Int] = [:]
        var rejected = 0
        for channel in channels {
            guard let content = channel["content"] as? [String: Any],
                  let course = content["course"] as? [String: Any],
                  let rows = course["data"] as? [[String: Any]] else { rejected += 1; continue }
            guard rows.count <= LearningPolicy.maxCourses else { throw LearningError(code: "LIMIT") }
            for row in rows {
                let cid = identifier(row["id"]), clazz = identifier(content["id"]), cpi = identifier(content["cpi"])
                let name = (row["name"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard [cid, clazz, cpi].allSatisfy(LearningPolicy.numeric), !name.isEmpty else { rejected += 1; continue }
                let entry = LearningPolicy.params("https://mooc1.chaoxing.com/visit/stucoursemiddle", ["courseid": cid, "clazzid": clazz, "cpi": cpi])
                let value = LearningCourse(courseId: cid, classId: clazz, cpi: cpi, name: String(name.prefix(200)),
                                           teacher: String((row["teacherfactor"] as? String ?? "").prefix(150)), url: entry)
                if let index = indices[value.key] { output[index] = value }
                else { indices[value.key] = output.count; output.append(value) }
                guard output.count <= LearningPolicy.maxCourses else { throw LearningError(code: "LIMIT") }
            }
        }
        guard channels.isEmpty || !output.isEmpty else { throw LearningError(code: "COURSES_SCHEMA") }
        return (output, rejected == 0)
    }

    static func noticesJSON(_ body: String) throws -> [LearningNotice] {
        try checkSize(body)
        guard let root = try? JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any],
              ["1", "true"].contains(string(root["status"]).lowercased()),
              let notices = root["notices"] as? [String: Any],
              let list = notices["list"] as? [[String: Any]] else { throw LearningError(code: "NOTICES_SCHEMA") }
        guard list.count <= 1_000 else { throw LearningError(code: "LIMIT") }
        var output: [LearningNotice] = []
        var seen = Set<String>()
        for row in list.prefix(100) {
            let primary = identifier(row["id"])
            let id = String((primary.isEmpty ? identifier(row["noticeId"]) : primary).prefix(100))
            let title = plainText(row["title"] as? String ?? "", limit: 200)
            guard !id.isEmpty, !title.isEmpty, seen.insert(id).inserted else { continue }
            let time = string(row["sendTime"])
            output.append(LearningNotice(id: id, title: title,
                content: plainText(row["content"] as? String ?? "", limit: 6_000),
                sender: plainText(row["sendName"] as? String ?? "", limit: 100),
                publishedText: String((time.isEmpty ? string(row["insertTime"]) : time).prefix(100))))
        }
        guard list.isEmpty || !output.isEmpty else { throw LearningError(code: "NOTICES_SCHEMA") }
        return output
    }

    /// Display-only HTML-to-text conversion without WebKit, URL loading, or attributed-string import.
    static func plainText(_ html: String, limit: Int = 6_000) -> String {
        let bounded = String(html.prefix(LearningPolicy.maxPageBytes))
        var value = replacing(#"<!--[\s\S]*?(?:-->|$)"#, in: bounded, with: " ")
        value = replacing(#"(?is)<(script|style|template|noscript)\b[^>]*>[\s\S]*?(?:</\1\s*>|$)"#, in: value, with: " ")
        // A quote-aware tag scanner handles > characters inside attribute values.
        var result = "", inTag = false, quote: Character?
        for ch in value {
            if inTag {
                if let current = quote { if ch == current { quote = nil } }
                else if ch == "\"" || ch == "'" { quote = ch }
                else if ch == ">" { inTag = false; result.append(" ") }
            } else if ch == "<" { inTag = true }
            else { result.append(ch) }
        }
        let entities = ["amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": " ", "ensp": " ", "emsp": " ", "ndash": "–", "mdash": "—", "hellip": "…", "copy": "©"]
        if let regex = try? NSRegularExpression(pattern: #"&(#x[0-9a-fA-F]{1,6}|#[0-9]{1,7}|[a-zA-Z]{2,10});"#) {
            let source = result as NSString
            for match in regex.matches(in: result, range: NSRange(location: 0, length: source.length)).reversed() {
                let name = source.substring(with: match.range(at: 1))
                var decoded = entities[name]
                if name.hasPrefix("#") {
                    let hex = name.lowercased().hasPrefix("#x")
                    let digits = String(name.dropFirst(hex ? 2 : 1))
                    if let code = UInt32(digits, radix: hex ? 16 : 10), let scalar = UnicodeScalar(code), code != 0 {
                        decoded = String(scalar)
                    }
                }
                if let decoded, let range = Range(match.range, in: result) { result.replaceSubrange(range, with: decoded) }
            }
        }
        return String(replacing(#"\s+"#, in: result, with: " ").trimmingCharacters(in: .whitespacesAndNewlines).prefix(max(0, limit)))
    }

    static func checkSize(_ body: String) throws {
        guard body.utf8.count <= LearningPolicy.maxPageBytes else { throw LearningError(code: "LIMIT") }
    }
    private static func identifier(_ value: Any?) -> String {
        // JSON booleans bridge to NSNumber too; never manufacture a numeric identifier from true.
        if let number = value as? NSNumber, String(cString: number.objCType) == "c" { return "" }
        return string(value)
    }
    private static func string(_ value: Any?) -> String {
        if let value = value as? String { return value }
        if let value = value as? NSNumber { return value.stringValue }
        return ""
    }
    private static func matches(_ pattern: String, _ text: String) -> Bool { text.range(of: pattern, options: .regularExpression) != nil }
    private static func capture(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }
    private static func replacing(_ pattern: String, in text: String, with replacement: String) -> String {
        text.replacingOccurrences(of: pattern, with: replacement, options: .regularExpression)
    }

    /// callAsyncJavaScript arguments: operation, html, baseURL, course (dictionary or NSNull), item (optional).
    /// Result is a JSON string. Run only in a separate, nonpersistent, network-blocked blank WKWebView,
    /// in WKContentWorld.defaultClient. Input is parsed into a detached template, never a live document.
    /// Template contents are inert: images/frames cannot fetch, and event handlers/scripts never run.
    /// Available operations: courses, coursesResult, work, exams, navigation, enrich, text. Exceptions contain codes only.
    static let script = #"""
    "use strict";
    if (typeof html !== "string" || html.length > 1500000 || new TextEncoder().encode(html).length > 1500000) throw Error("LIMIT");
    const selectedCourse = typeof course === "object" && course !== null ? course : null;
    const selectedItem = typeof item === "object" && item !== null ? item : null;
    const base = typeof baseURL === "string" ? baseURL : "";
    const LIMIT = 1000;
    const readPaths = new Set(["/base","/mycourse/studentcourse","/mycourse/stu","/mycourse/backclazzdata","/visit/courselistdata","/mooc2-ans/visit/courselistdata","/visit/stucoursemiddle","/mooc-ans/visit/stucoursemiddle","/mooc2/work/all-task","/mooc-ans/mooc2/work/all-task","/mooc2/work/list","/mooc-ans/mooc2/work/list","/work/getallwork","/mooc-ans/work/getallwork","/mooc2/work/task","/mooc-ans/mooc2/work/task","/exam-ans/exam/test/examcode/examlist","/pc/notice/getnoticelist"]);
    const workPaths = new Set(["/mooc2/work/list","/mooc-ans/mooc2/work/list","/work/getallwork","/mooc-ans/work/getallwork"]);
    const framePaths = new Set(["/visit/stucoursemiddle","/mooc-ans/visit/stucoursemiddle","/mycourse/studentcourse","/mooc-ans/mycourse/studentcourse","/mooc2-ans/mycourse/studentcourse"]);
    const numeric = value => typeof value === "string" && /^[0-9]{1,24}$/.test(value);
    const allowed = value => {
      try {
        if (typeof value !== "string" || !value || value.length > 16384 || /[\s\x00-\x1F\x7F\\]/.test(value)) return false;
        if (/^https:\/\/[^/?#]*@/i.test(value)) return false;
        const u = new URL(value);
        return u.protocol === "https:" && !u.username && !u.password && (!u.port || u.port === "443") &&
          /^[a-z0-9.-]+$/.test(u.hostname) && (u.hostname === "chaoxing.com" || u.hostname.endsWith(".chaoxing.com"));
      } catch (_) { return false; }
    };
    const path = value => { try { return new URL(value).pathname.toLowerCase(); } catch (_) { return ""; } };
    const safeRead = value => allowed(value) && (readPaths.has(path(value)) || path(value).startsWith("/mooc2-ans/mycourse/") || path(value).startsWith("/mooc-ans/mycourse/"));
    const workList = value => allowed(value) && workPaths.has(path(value));
    const query = value => {
      const result = Object.create(null);
      try { for (const [key,entryValue] of new URL(value).searchParams) {
        const lower = key.toLowerCase();
        result[lower] = result[lower] !== undefined && result[lower] !== entryValue ? "\0" : entryValue;
      } } catch (_) {}
      return result;
    };
    const sameCourse = value => {
      if (!selectedCourse) return true;
      const q = query(value);
      return (q.courseid === undefined || q.courseid === selectedCourse.courseId) && (q.classid === undefined || q.classid === selectedCourse.classId) && (q.clazzid === undefined || q.clazzid === selectedCourse.classId);
    };
    const absolute = raw => {
      try {
        if (!allowed(base) || typeof raw !== "string" || !raw.trim()) return null;
        const input = raw.trim();
        if (/[\s\x00-\x1F\x7F\\]/.test(input) || /^(?:https:)?\/\/[^/?#]*@/i.test(input)) return null;
        const value = new URL(input, base).href;
        return allowed(value) ? value : null;
      } catch (_) { return null; }
    };
    const supplied = raw => {
      let value = String(raw || "").trim();
      if (!/^(https:\/\/|\/|\?)/i.test(value)) { try { value = decodeURIComponent(value); } catch (_) {} }
      return absolute(value);
    };
    const txt = element => (element?.textContent || "").replace(/\s+/g," ").trim();
    const attr = (element,name) => element?.getAttribute(name) || "";
    const cut = (value,max) => Array.from(String(value || "")).slice(0,max).join("");
    const first = (element,selector) => element.querySelector(selector);
    const all = (element,selector) => Array.from(element.querySelectorAll(selector));
    const template = document.createElement("template");
    template.innerHTML = html;
    const doc = template.content;
    if (doc.querySelectorAll("*").length > 30000) throw Error("LIMIT");
    const hiddenSelector = "script,style,template,noscript,[hidden],[aria-hidden='true']";
    const isVisible = el => {
      for (let p = el; p?.nodeType === 1; p = p.parentElement) {
        if (p.matches(hiddenSelector) || /(?:display\s*:\s*none|visibility\s*:\s*hidden)/i.test(attr(p,"style"))) return false;
      }
      return true;
    };
    const visible = doc.cloneNode(true);
    all(visible,"*").filter(el => !isVisible(el)).forEach(el => el.remove());
    const visibleText = (txt(visible) + " " + all(visible,"img[alt]").map(el=>attr(el,"alt")).join(" ")).trim();
    const auth = !allowed(base) || new URL(base).hostname.startsWith("passport") || path(base).includes("/login") || !!first(visible,"input[type='password']") || /请.{0,20}登录/.test(visibleText);
    const challenge = /antispider/i.test(base) || /验证码|访问过于频繁/.test(visibleText);
    const accessDenied = /没有此页面访问权限|无权访问此课程|您没有访问权限|课程已删除|课程不存在/.test(visibleText);
    const blocked = auth || challenge || accessDenied || /加载失败|系统异常/.test(visibleText);
    const status = raw => {
      if (/未提交|未交|待做|待提交|未完成|未开始|待考试|待重做|未作答|打回|退回/.test(raw)) return "pending";
      if (/已提交|待批阅|待批改|未批阅|已批阅|已批改|已完成|已交|已交卷|已结束.*已交/.test(raw)) return "submitted";
      if (/已截止|已过期|已关闭|已结束/.test(raw)) return "closed";
      return "unknown";
    };
    const dates = text => {
      const out = [];
      for (const m of String(text).matchAll(/(20\d{2})[-/年](\d{1,2})[-/月](\d{1,2})(?:日)?[ T\s]+(\d{1,2}):(\d{2})(?::\d{2})?/g)) {
        const [y,mo,d,h,mi] = m.slice(1).map(Number), value = new Date(Date.UTC(y,mo-1,d,h,mi));
        if (value.getUTCFullYear()===y && value.getUTCMonth()===mo-1 && value.getUTCDate()===d && value.getUTCHours()===h && value.getUTCMinutes()===mi)
          out.push(`${y}-${String(mo).padStart(2,"0")}-${String(d).padStart(2,"0")}T${String(h).padStart(2,"0")}:${String(mi).padStart(2,"0")}`);
      }
      return out;
    };
    const deadline = text => {
      const label = /(?:截止(?:时间)?|结束(?:时间)?)[：:\s]*([^\n]{0,80})/.exec(text);
      if (label) return dates(label[1])[0] || null;
      const range = /(?:作答时间|起止时间)[：:\s]*([^\n]{0,120})/.exec(text), values = range ? dates(range[1]) : [];
      return values.length >= 2 ? values.at(-1) : null;
    };
    const totalElement = first(doc,"#totalCount,input[name='totalCount'],input[name='total'],#total");
    const rawTotal = (attr(totalElement,"value") || txt(totalElement)).trim();
    const total = /^\d{1,9}$/.test(rawTotal) ? Number(rawTotal) : null;
    const hidden = name => cut(attr(all(doc,"input").find(el=>attr(el,"id")===name || attr(el,"name")===name),"value"),16384);
    const nextCandidates = all(doc,"a[rel='next'],a.next,.pagingNext,.nextPage,a").filter(el =>
      (el.matches("a[rel='next'],a.next,.pagingNext,.nextPage") || txt(el)==="下一页") && isVisible(el) &&
      attr(el,"aria-disabled")!=="true" && !el.closest(".disabled,[aria-disabled='true']"));
    const nextURL = nextCandidates.map(el=>absolute(attr(el,"href"))).find(url=>url && url!==base && safeRead(url) && path(url)===path(base) && sameCourse(url)) || null;
    const resultWork = (records,rejected,rowCount,emptyText) => {
      const recognized = !blocked && (records.length>0 || (rowCount===0 && rejected===0 && emptyText));
      const incomplete = (total!==null && total>records.length) || (records.length>=20 && total===null);
      return {records,recognized,complete:recognized && nextCandidates.length===0 && !incomplete && rejected===0,rejected,nextURL,total};
    };
    let result;
    if (operation === "navigation") {
      let menu = null;
      for (const el of all(doc,"a[data],a[href]").filter(isVisible)) {
        if (!txt(el).includes("作业")) continue;
        for (const raw of [attr(el,"data"),attr(el,"href")]) {
          const url = supplied(raw);
          if (url && workList(url) && sameCourse(url)) { menu = url; break; }
        }
        if (menu) break;
      }
      const frames = all(doc,"iframe[src],frame[src]").map(el=>supplied(attr(el,"src"))).filter(url=>url && url!==base && sameCourse(url));
      const fid = /["']?fid["']?\s*[:=]\s*["']?([0-9]{1,24})(?![0-9])/.exec(html)?.[1] || null;
      result = {menu, workFrame:frames.find(workList)||null,
        courseFrames:[...new Set(frames.filter(url=>safeRead(url)&&framePaths.has(path(url))))].slice(0,3),
        workEnc:hidden("workEnc"),openc:hidden("openc"),stuenc:hidden("enc"),auth,challenge,accessDenied,
        emptyCourses:!blocked && /暂无课程|没有课程/.test(visibleText),fid};
    } else if (operation === "courses" || operation === "coursesResult") {
      const output = new Map(); let rejected = 0;
      for (const el of all(doc,"[courseid],a[href*='stucoursemiddle']").filter(isVisible)) {
        const holder = el.closest("li.course,li.courseItem,.course-item,li") || el.parentElement || el;
        const url = absolute(attr(el,"href") || attr(first(holder,"a[href*='stucoursemiddle']"),"href")), q = query(url);
        const courseId = attr(el,"courseid") || q.courseid || "", classId = attr(el,"clazzid") || q.clazzid || q.classid || "", cpi = attr(el,"personid") || q.cpi || "";
        const nameElement = first(holder,".course-name,.courseName,h3 a,h3,.title"), name = attr(nameElement,"title") || txt(nameElement);
        if (![courseId,classId,cpi].every(numeric) || !name) { rejected++; continue; }
        const teacherElement = first(holder,"p.color3,p.overHidden2,.teacher"), teacher = attr(teacherElement,"title") || txt(teacherElement);
        const identityMatches = (q.courseid === undefined || q.courseid === courseId) && (q.clazzid === undefined || q.clazzid === classId) && (q.classid === undefined || q.classid === classId);
        const entry = url && safeRead(url) && identityMatches ? url : `https://mooc1.chaoxing.com/visit/stucoursemiddle?courseid=${courseId}&clazzid=${classId}&cpi=${cpi}`;
        output.set(`${courseId}/${classId}`,{courseId,classId,cpi,name:cut(name,200),teacher:cut(teacher,150),url:entry});
        if (output.size>200) throw Error("LIMIT");
      }
      const courses = [...output.values()];
      result = operation === "courses" ? courses : {courses, complete:!blocked && rejected===0 && (courses.length>0 || /暂无课程|没有课程/.test(visibleText)), rejected};
    } else if (operation === "work") {
      const output = new Map(); let rejected = 0;
      const rows = all(doc,"li[data*='work'],[onclick*='goTask'],li,a[data-workid]").filter(el =>
        isVisible(el) && (el.matches("li[data*='work'],[onclick*='goTask'],a[data-workid]") || !!first(el,"a.inspectTask")));
      if (rows.length>LIMIT) throw Error("LIMIT");
      for (const row of rows) {
        const link = first(row,"a[href*='work'],a[data*='work']");
        const raw = attr(row,"data") || attr(link,"href") || attr(link,"data");
        const url = raw ? supplied(raw) : null, q = query(url);
        const courseId = q.courseid ?? selectedCourse?.courseId ?? "", classId = q.classid ?? q.clazzid ?? selectedCourse?.classId ?? "";
        const inspect = row.matches("a.inspectTask,a[data-workid]") ? row : first(row,"a.inspectTask,a[data-workid]");
        const workId = q.workid || attr(row,"data-workid") || attr(inspect,"data-workid") || attr(inspect,"data");
        const labels = attr(row,"aria-label").split(";");
        const title = txt(first(row,".overHidden2.fl,.task-title,.title,a.inspectTask,.right-content p:not(.status)")) || (row.matches("a[data-workid]") ? txt(row) : "") || (labels[0]||"").trim();
        const explicit = all(row,".status,.work-status,.workStatus,.task-status,.pt5,.time,em,span").filter(isVisible).map(txt).filter(value=>status(value)!=="unknown" && value.length<=100 && !/截止时间|开始时间/.test(value));
        const preferred = txt(first(row,".status,.work-status,.workStatus,.task-status")), aria = labels.slice(1).join(";").trim();
        const statusText = cut(status(preferred)!=="unknown" ? preferred : status(aria)!=="unknown" ? aria : explicit[0] || "提交状态未知",100);
        if ((raw && !url) || (url && !safeRead(url)) || ![courseId,classId,workId].every(numeric) || !title ||
          (selectedCourse && (courseId!==selectedCourse.courseId || classId!==selectedCourse.classId))) { rejected++; continue; }
        const timeText = cut(all(row,".time,.pt5,.remaining,.fl span").filter(isVisible).map(txt).join("\n") || txt(row),1000);
        const courseName = selectedCourse?.name || txt(first(row,".courseName,.course-name"));
        const id = `${courseId}/${classId}/homework/${workId}`;
        output.set(id,{id,courseId,classId,workId,kind:"homework",title:cut(title,200),course:cut(courseName,200),status:status(statusText),statusText,
          deadline:deadline(timeText),startAt:null,timeText,description:"",url:url||"",stale:false});
      }
      const empty = /(?:暂无|没有|还没有|尚无)(?:相关|任何|发布的|布置的)?作业|(?:老师|教师)(?:还未|尚未|未)发布作业|暂无任务/.test(visibleText) || (total===0 && !!first(visible,".bottomList,.task-list"));
      result = resultWork([...output.values()],rejected,rows.length,empty);
    } else if (operation === "exams") {
      const headers = all(doc,"th").map(txt), records = [], ids = new Set(); let rejected = 0;
      const rows = all(doc,"tr.dataTr").filter(isVisible);
      if (rows.length>LIMIT) throw Error("LIMIT");
      for (const row of rows) {
        const cells = all(row,"td"), cell = pattern => txt(cells[headers.findIndex(value=>pattern.test(value))]);
        const url = absolute(attr(first(row,"a[href]"),"href")), q = query(url);
        const workId = q.testid || q.examid || attr(row,"data-examid"), courseId = q.courseid || "", classId = q.classid || q.clazzid || "", title = cell(/考试名称|试卷名称/);
        if (!url || !allowed(url) || ![workId,courseId,classId].every(numeric) || !title) { rejected++; continue; }
        const timeText = cut(cell(/考试时间|起止时间/),1000), times = dates(timeText), statusText = cut(cell(/状态/) || "未知",100), id = `${courseId}/${classId}/exam/${workId}`;
        if (ids.has(id)) continue; ids.add(id);
        records.push({id,courseId,classId,workId,kind:"exam",title:cut(title,200),course:cut(cell(/课程/),200),status:status(statusText),statusText,
          deadline:times.length>=2?times.at(-1):null,startAt:times[0]||null,timeText,description:"",url,stale:false});
      }
      result = resultWork(records,rejected,rows.length,/暂无考试|没有考试/.test(visibleText));
    } else if (operation === "enrich") {
      if (!selectedItem || ![selectedItem.courseId,selectedItem.classId,selectedItem.workId].every(numeric)) throw Error("WORK_SCHEMA");
      const machineDate = value => {
        const full = dates(value)[0]; if (full) return full;
        if (!/^(?:[0-9]{10}|[0-9]{13})$/.test(value)) return null;
        const millis = Number(value)*(value.length===10?1000:1);
        if (millis<946684800000 || millis>4102444799999) return null;
        return new Date(millis+8*3600*1000).toISOString().slice(0,16);
      };
      const machineEnd = machineDate(attr(first(doc,"input#endTime,input#workEndTime"),"value"));
      const machineStart = machineDate(attr(first(doc,"input#startTime,input#workStartTime"),"value"));
      all(visible,"input,textarea,select,button").forEach(el=>el.remove());
      const text = txt(visible), display = all(visible,".workTitle,.work-title,.mark_info,.workInfo,.answerTime,.time").map(txt).join("\n") || cut(text,2000);
      const startLabel = /(?:开始时间|作答时间)[：:\s]*(.{0,50})/.exec(display)?.[1] || "";
      result = {...selectedItem, deadline:machineEnd || deadline(display) || deadline(text) || selectedItem.deadline || null,
        startAt:machineStart || dates(startLabel)[0] || selectedItem.startAt || null,timeText:cut(display,1000),
        description:cut(txt(first(visible,".workDescription,.work-description,.workTitle")),4000)};
    } else if (operation === "text") {
      result = cut(visibleText,6000);
    } else { throw Error("METHOD"); }
    return JSON.stringify(result);
    """#
}
