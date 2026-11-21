import SwiftUI

struct TreeholePollCard: View {
    let poll: TreeholePoll
    let enabled: Bool
    let pending: Bool
    let vote: (String?) -> Void
    var body: some View {
        TimelineView(.periodic(from: .now, by: 15)) { context in
            let ended = poll.ended(at: context.date)
            VStack(alignment: .leading, spacing: 10) {
                Label("投票 · 单选", systemImage: "chart.bar.xaxis").font(.caption).foregroundStyle(.secondary)
                Text(poll.question).font(.subheadline.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                ForEach(poll.options) { option in
                    Button { vote(option.id) } label: {
                        HStack(spacing: 8) {
                            Image(systemName: poll.myOptionId == option.id ? "checkmark.circle.fill" : "circle").foregroundStyle(poll.myOptionId == option.id ? TreeholeTheme.primary : TreeholeTheme.muted)
                            Text(option.text).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 2)
                            Text("\(option.count) · \(poll.total == 0 ? 0 : Int((Double(option.count) * 100 / Double(poll.total)).rounded()))%").font(.caption).monospacedDigit().foregroundStyle(.secondary)
                        }.font(.subheadline).padding(10).frame(minHeight: 44)
                            .background(GeometryReader { geometry in
                                RoundedRectangle(cornerRadius: 8).fill(TreeholeTheme.primary.opacity(0.12)).frame(width: geometry.size.width * (poll.total == 0 ? 0 : CGFloat(option.count) / CGFloat(poll.total)))
                            }).background(TreeholeTheme.surface, in: RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(poll.myOptionId == option.id ? TreeholeTheme.primary.opacity(0.5) : TreeholeTheme.muted.opacity(0.15)))
                    }.buttonStyle(.plain).disabled(!enabled || ended || pending).accessibilityAddTraits(poll.myOptionId == option.id ? .isSelected : [])
                }
                HStack {
                    Text("\(poll.total) 人参与 · " + (ended ? "已结束" : poll.deadlineLabel)).font(.caption2).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    if pending { ProgressView().controlSize(.small).accessibilityLabel("正在提交投票") }
                    else if poll.myOptionId != nil && !ended && enabled { Button("取消投票") { vote(nil) }.font(.caption).frame(minHeight: 44) }
                }
            }.padding(12).background(TreeholeTheme.background, in: RoundedRectangle(cornerRadius: 12))
        }
    }
}
struct TreeholePollEditor: View {
    @Binding var poll: TreeholePollDraft
    let remove: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Label("添加投票", systemImage: "chart.bar.xaxis").font(.subheadline.weight(.semibold)); Spacer(); Button("移除", action: remove).font(.caption).frame(minHeight: 44) }
            CampusMultilineField("想问大家什么？", text: $poll.question, minimum: 1, maximum: 3).accessibilityLabel("投票问题").onChange(of: poll.question) { poll.question = String($0.prefix(80)) }
            ForEach(poll.options.indices, id: \.self) { index in
                HStack {
                    TextField("选项 \(index + 1)", text: Binding(get: { index < poll.options.count ? poll.options[index] : "" }, set: { if index < poll.options.count { poll.options[index] = String($0.prefix(40)) } })).accessibilityLabel("投票选项 \(index + 1)")
                    if poll.options.count > 2 { Button { poll.options.remove(at: index) } label: { Image(systemName: "minus.circle").frame(width: 44, height: 44) }.accessibilityLabel("删除选项 \(index + 1)") }
                }.padding(.horizontal, 10).frame(minHeight: 44).background(TreeholeTheme.surface, in: RoundedRectangle(cornerRadius: 8))
            }
            if poll.options.count < 6 { Button("添加选项") { poll.options.append("") }.font(.subheadline).frame(minHeight: 44) }
            Picker("持续时间", selection: $poll.durationHours) { Text("1 天").tag(24); Text("3 天").tag(72); Text("7 天").tag(168) }.pickerStyle(.segmented)
            Text("单选，截止前可改选或取消；发布后问题和选项固定。参与者身份不公开。").font(.caption2).foregroundStyle(.secondary)
        }.padding(12).background(TreeholeTheme.background, in: RoundedRectangle(cornerRadius: 12))
    }
}
