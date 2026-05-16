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
        HStack(spacing: 6) {
            Text(text)
                .font(.callout.weight(.medium))
                .foregroundStyle(tint)
                .lineLimit(1)
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.callout)
                    .foregroundStyle(tint.opacity(0.55))
            }
            .buttonStyle(.plain)
            .help("Remove")
        }
        .padding(.leading, 12)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
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
    @FocusState private var inputFocused: Bool

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
                .padding(20)
                .frame(minWidth: 360, idealWidth: 400)
                // On compact-width devices (iPhone), the popover content is
                // too wide to fit alongside the chevron arrow. Adapt to a
                // bottom sheet with a medium detent — the natural iOS pattern
                // for "small focused task" presentations. iPad/macOS keep the
                // anchored popover treatment.
                .presentationCompactAdaptation(.sheet)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .onAppear {
                    // Land the keyboard on the input on present.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        inputFocused = true
                    }
                }
        }
    }

    private var popoverContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Title
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous).fill(tint.gradient)
                    )
                Text(title)
                    .font(.title3.weight(.semibold))
                Spacer()
            }

            // Input row
            HStack(spacing: 10) {
                TextField("Name", text: $input)
                    .textFieldStyle(.plain)
                    .font(.body)
                    .focused($inputFocused)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color(.secondarySystemFill))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(.separator.opacity(0.4), lineWidth: 0.5)
                    )
                    .onSubmit { commit() }
                #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                #endif

                Button("Add") { commit() }
                    .buttonStyle(.borderedProminent)
                    .tint(tint)
                    .controlSize(.large)
                    .disabled(trimmed.isEmpty)
            }

            if !suggestions.isEmpty {
                Divider()

                Text("Existing")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(suggestions, id: \.self) { suggestion in
                            Button {
                                onAdd(suggestion)
                                isPresented = false
                                input = ""
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: icon)
                                        .font(.callout)
                                        .foregroundStyle(tint)
                                        .frame(width: 20)
                                    Text(suggestion)
                                        .font(.body)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                }
                                .padding(.vertical, 10)
                                .padding(.horizontal, 12)
                                .contentShape(Rectangle())
                                .background(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(Color.clear)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxHeight: 220)
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
