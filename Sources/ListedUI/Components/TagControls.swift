import SwiftUI

/// Small chip with an inline remove (×) button. Used in the task detail view to
/// show projects / contexts attached to a task.
public struct TagPill: View {
    let text: String
    let tint: Color
    let onRemove: () -> Void

    public init(text: String, tint: Color, onRemove: @escaping () -> Void) {
        self.text = text
        self.tint = tint
        self.onRemove = onRemove
    }

    public var body: some View {
        HStack(spacing: 4) {
            Text(text)
                .font(.caption.weight(.medium))
                .foregroundStyle(tint)
                .lineLimit(1)
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption2)
                    .foregroundStyle(tint.opacity(0.55))
            }
            .buttonStyle(.plain)
            .help("Remove")
        }
        .padding(.leading, 10)
        .padding(.trailing, 6)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(tint.opacity(0.1))
                .overlay(Capsule().strokeBorder(tint.opacity(0.2), lineWidth: 0.5))
        )
    }
}

/// `+` button that opens a popover with a text field (and optional suggestion list)
/// for adding a project or context to a task.
public struct AddTagButton: View {
    let title: String
    let icon: String
    let tint: Color
    let suggestions: [String]
    let onAdd: (String) -> Void

    @State private var isPresented: Bool = false
    @State private var input: String = ""

    public init(title: String, icon: String, tint: Color, suggestions: [String], onAdd: @escaping (String) -> Void) {
        self.title = title
        self.icon = icon
        self.tint = tint
        self.suggestions = suggestions
        self.onAdd = onAdd
    }

    public var body: some View {
        Button {
            isPresented = true
        } label: {
            Image(systemName: "plus.circle.fill")
                .font(.title3)
                .foregroundStyle(tint)
                .symbolRenderingMode(.hierarchical)
        }
        .buttonStyle(.plain)
        .help(title)
        .popover(isPresented: $isPresented, arrowEdge: .top) {
            popoverContent
                .padding(14)
                .frame(minWidth: 280, idealWidth: 320)
                // On iOS, popovers normally adapt to a full-screen sheet on
                // compact-width devices. Force the actual popover treatment
                // (small floating panel anchored to the + button) so the user
                // doesn't get a giant slideover for a single text field.
                .presentationCompactAdaptation(.popover)
        }
    }

    private var popoverContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)

            HStack {
                Image(systemName: icon).foregroundStyle(tint)
                TextField("Name", text: $input)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { commit() }
                #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                #endif
                Button("Add") { commit() }
                    .buttonStyle(.borderedProminent)
                    .disabled(trimmed.isEmpty)
            }

            if !suggestions.isEmpty {
                Text("Existing").font(.caption).foregroundStyle(.secondary)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(suggestions, id: \.self) { suggestion in
                            Button {
                                onAdd(suggestion)
                                isPresented = false
                                input = ""
                            } label: {
                                HStack {
                                    Image(systemName: icon)
                                        .foregroundStyle(tint)
                                    Text(suggestion)
                                    Spacer()
                                }
                                .padding(.vertical, 4)
                                .padding(.horizontal, 8)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxHeight: 160)
            }
        }
    }

    private var trimmed: String {
        input.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "_")
    }

    private func commit() {
        let value = trimmed
        guard !value.isEmpty else { return }
        onAdd(value)
        input = ""
        isPresented = false
    }
}
