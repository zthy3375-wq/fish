import SwiftUI
import UIKit
import PhotosUI
import UniformTypeIdentifiers

/// Keep modern navigation on newer systems and one-column native navigation on iOS 15.
struct CampusNavigation<Content: View>: View {
    private let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    @ViewBuilder var body: some View {
        if #available(iOS 16.0, *) { NavigationStack { content } }
        else { NavigationView { content }.navigationViewStyle(.stack) }
    }
}

struct CampusLabeledValue: View {
    let title: String
    let value: String
    init(_ title: String, value: String) { self.title = title; self.value = value }
    @ViewBuilder var body: some View {
        if #available(iOS 16.0, *) { LabeledContent(title, value: value) }
        else {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(title)
                Spacer(minLength: 8)
                Text(value).foregroundStyle(.secondary).multilineTextAlignment(.trailing)
            }.accessibilityElement(children: .combine)
        }
    }
}

struct CampusAdaptiveRow<Preferred: View, Fallback: View>: View {
    let preferred: Preferred
    let fallback: Fallback
    init(@ViewBuilder preferred: () -> Preferred, @ViewBuilder fallback: () -> Fallback) {
        self.preferred = preferred(); self.fallback = fallback()
    }
    @ViewBuilder var body: some View {
        if #available(iOS 16.0, *) { ViewThatFits(in: .horizontal) { preferred; fallback } }
        else { fallback }
    }
}

struct CampusMultilineField: View {
    let title: String
    @Binding var text: String
    let minimum: Int
    let maximum: Int
    init(_ title: String, text: Binding<String>, minimum: Int, maximum: Int) {
        self.title = title; _text = text; self.minimum = minimum; self.maximum = maximum
    }
    @ViewBuilder var body: some View {
        if #available(iOS 16.0, *) { TextField(title, text: $text, axis: .vertical).lineLimit(minimum...maximum) }
        else {
            TextEditor(text: $text).frame(minHeight: CGFloat(minimum) * 24, maxHeight: CGFloat(maximum) * 24)
                .overlay(alignment: .topLeading) {
                    if text.isEmpty { Text(title).foregroundStyle(.secondary).padding(.top, 8).padding(.leading, 5).allowsHitTesting(false).accessibilityHidden(true) }
                }.accessibilityLabel(title)
        }
    }
}

extension View {
    @ViewBuilder func campusScrollBackground() -> some View {
        if #available(iOS 16.0, *) { scrollContentBackground(.hidden) } else { self }
    }
    @ViewBuilder func campusKeyboardDismissal() -> some View {
        if #available(iOS 16.0, *) { scrollDismissesKeyboard(.interactively) } else { self }
    }
    @ViewBuilder func campusReplySheet() -> some View {
        if #available(iOS 16.0, *) { presentationDetents([.medium, .large]).presentationDragIndicator(.visible) }
        else { self } // Standard dismissible sheet; all reply controls remain available.
    }
}

/// Text-only sharing keeps the existing explicit system share sheet on iOS 15.
struct CampusShareLink<Label: View>: View {
    let item: String
    let label: Label
    @State private var presented = false
    init(item: String, @ViewBuilder label: () -> Label) { self.item = item; self.label = label() }
    @ViewBuilder var body: some View {
        if #available(iOS 16.0, *) { ShareLink(item: item) { label } }
        else { Button { presented = true } label: { label }.sheet(isPresented: $presented) { CampusActivityController(text: item) } }
    }
}
private struct CampusActivityController: UIViewControllerRepresentable {
    let text: String
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: [text], applicationActivities: nil) }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// PHPicker uses user-selected assets without requesting whole-library access.
struct CampusPhotoItem: Equatable {
    let id = UUID()
    let provider: NSItemProvider
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    func loadBoundedData(maximumBytes: Int) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadFileRepresentation(forTypeIdentifier: UTType.image.identifier) { url, error in
                do {
                    if let error { throw error }
                    guard let url, maximumBytes > 0,
                          let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
                          size > 0, size <= maximumBytes else { throw CocoaError(.fileReadTooLarge) }
                    // The provider URL is temporary: read inside its callback, before it expires.
                    let data = try Data(contentsOf: url, options: .mappedIfSafe)
                    guard data.count <= maximumBytes else { throw CocoaError(.fileReadTooLarge) }
                    continuation.resume(returning: data)
                } catch { continuation.resume(throwing: error) }
            }
        }
    }
    func loadData() async throws -> Data? {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: data) }
            }
        }
    }
}
struct CampusPhotoPicker<Label: View>: View {
    let maximum: Int
    let filter: PHPickerFilter
    let label: Label
    let selected: ([CampusPhotoItem]) -> Void
    @State private var presented = false
    init(selection: Binding<[CampusPhotoItem]>, maxSelectionCount: Int, matching: PHPickerFilter, @ViewBuilder label: () -> Label) {
        maximum = max(1, maxSelectionCount); filter = matching; self.label = label(); selected = { selection.wrappedValue = $0 }
    }
    init(selection: Binding<CampusPhotoItem?>, matching: PHPickerFilter, @ViewBuilder label: () -> Label) {
        maximum = 1; filter = matching; self.label = label(); selected = { selection.wrappedValue = $0.first }
    }
    var body: some View {
        Button { presented = true } label: { label }.sheet(isPresented: $presented) {
            CampusPhotoController(maximum: maximum, filter: filter) { items in selected(items); presented = false }
        }
    }
}
private struct CampusPhotoController: UIViewControllerRepresentable {
    let maximum: Int
    let filter: PHPickerFilter
    let selected: ([CampusPhotoItem]) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(selected: selected) }
    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration(); configuration.selectionLimit = maximum; configuration.filter = filter
        configuration.selection = .ordered
        let controller = PHPickerViewController(configuration: configuration); controller.delegate = context.coordinator
        return controller
    }
    func updateUIViewController(_ controller: PHPickerViewController, context: Context) {}
    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let selected: ([CampusPhotoItem]) -> Void
        init(selected: @escaping ([CampusPhotoItem]) -> Void) { self.selected = selected }
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            selected(results.map { CampusPhotoItem(provider: $0.itemProvider) })
        }
    }
}
