import SwiftUI
import ListedCore

/// First-launch onboarding asking whether the user wants to store tasks in iCloud Drive
/// or locally on the device. Surfaces the spec's first-launch flow (section 6.2).
public struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @Binding var isPresented: Bool

    @State private var working: Bool = false
    @State private var errorMessage: String?

    public init(isPresented: Binding<Bool>) {
        self._isPresented = isPresented
    }

    public var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 12) {
                Image(systemName: "checklist")
                    .font(.system(size: 48))
                    .foregroundStyle(.tint)
                Text("Welcome to Listed")
                    .font(.largeTitle.bold())
                Text("Your tasks are plain-text todo.txt files you fully own. Choose where Listed should keep them.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 24)
            }
            .padding(.top, 24)

            VStack(spacing: 12) {
                Button {
                    bootstrap(useICloud: true)
                } label: {
                    storageOption(
                        title: "Use iCloud Drive",
                        subtitle: model.bootstrap.isICloudAvailable
                            ? "Sync tasks across all your Apple devices."
                            : "iCloud Drive isn't available right now.",
                        icon: "icloud",
                        recommended: model.bootstrap.isICloudAvailable
                    )
                }
                .buttonStyle(.plain)
                .disabled(!model.bootstrap.isICloudAvailable || working)

                Button {
                    bootstrap(useICloud: false)
                } label: {
                    storageOption(
                        title: "Use Local Storage",
                        subtitle: "Keep tasks on this device only. You can change this later.",
                        icon: "internaldrive",
                        recommended: false
                    )
                }
                .buttonStyle(.plain)
                .disabled(working)
            }
            .padding(.horizontal, 24)

            if let errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Spacer()
        }
        .frame(minWidth: 420, minHeight: 460)
        .padding(20)
        .interactiveDismissDisabled(true)
    }

    private func storageOption(title: String, subtitle: String, icon: String, recommended: Bool) -> some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(title).font(.headline)
                    if recommended {
                        Text("Recommended")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill(.tint.opacity(0.2)))
                            .foregroundStyle(.tint)
                    }
                }
                Text(subtitle).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right").foregroundStyle(.secondary)
        }
        .padding(16)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func bootstrap(useICloud: Bool) {
        working = true
        errorMessage = nil
        Task {
            do {
                let workspace = try model.bootstrap.makeInitialWorkspace(useICloud: useICloud)
                try model.workspaceStore.save(workspace)
                await model.repository.updateWorkspace(workspace)
                await MainActor.run {
                    model.replaceWorkspace(workspace)
                }
                await model.refresh()
                isPresented = false
            } catch {
                errorMessage = error.localizedDescription
                working = false
            }
        }
    }
}

extension AppModel {
    /// Replace the in-memory workspace (used after onboarding / settings changes).
    public func replaceWorkspace(_ workspace: Workspace) {
        self.workspace = workspace
    }
}
