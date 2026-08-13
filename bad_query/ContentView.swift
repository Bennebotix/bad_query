//
//  ContentView.swift
//  bad_query
//
//  Created by Taj C on 7/21/26.
//

import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var sandboxHandle: Int64 = -99

    @State private var showingItemImporter = false
    @State private var showingAddImporter = false
    @State private var showingDeleteImporter = false
    @State private var showingDeleteConfirmation = false
    @State private var pendingDeleteURL: URL?

    private let defaultPath = "/var/containers/Shared/SystemGroup/systemgroup.com.apple.mobilegestaltcache/Library/Caches/com.apple.MobileGestalt.plist"

    @State private var selectedURL: URL?
    @State private var currentDirectoryURL: URL?

    @State private var log = "file manager ready"

    init() {
        let defaultURL = URL(fileURLWithPath: defaultPath)

        _selectedURL = State(initialValue: defaultURL)
        _currentDirectoryURL = State(
            initialValue: defaultURL.deletingLastPathComponent()
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Selected Item") {
                    TextField(
                        "Path",
                        text: Binding(
                            get: {
                                selectedURL?.path ?? defaultPath
                            },
                            set: { newValue in
                                selectedURL = URL(fileURLWithPath: newValue)
                            }
                        )
                    )
                    .font(.system(.body, design: .monospaced))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                    Button {
                        showingItemImporter = true
                    } label: {
                        Label(
                            "Select File or Folder",
                            systemImage: "folder.badge.plus"
                        )
                    }
                    .fileImporter(
                        isPresented: $showingItemImporter,
                        allowedContentTypes: [.item, .folder],
                        allowsMultipleSelection: false
                    ) { result in
                        handleImportedItem(result)
                    }

                    Button("Consume Sandbox Extension") {
                        sandboxHandle = consumeExtension(
                            selectedURL?.path ?? defaultPath
                        )
                    }
                    .disabled(
                        (selectedURL?.path.isEmpty ?? true) ||
                        sandboxHandle > 0
                    )

                    Button("Release Sandbox Extension") {
                        releaseExtension(handle: sandboxHandle)
                        sandboxHandle = -99
                    }
                    .disabled(sandboxHandle < 0)

                    Button {
                        showCurrentDirectory()
                    } label: {
                        Label(
                            "Show Current Directory",
                            systemImage: "folder"
                        )
                    }
                    .disabled(selectedURL == nil)

                    if let selectedURL {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Selected")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Text(selectedURL.path)
                                .font(.system(.footnote, design: .monospaced))
                                .textSelection(.enabled)

                            Text(
                                selectedURL.hasDirectoryPath
                                    ? "Directory"
                                    : "File"
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Export") {
                    if let selectedURL {
                        Button {
                            appendLog(
                                "\nopening export for:\n\(selectedURL.path)"
                            )
                            presentExportSheet(for: selectedURL)
                        } label: {
                            Label(
                                "Export At Path",
                                systemImage: "square.and.arrow.up"
                            )
                        }
                        .disabled(selectedURL.path.isEmpty)
                    } else {
                        Text("Select an item to export")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("File Operations") {
                    Button {
                        showingAddImporter = true
                    } label: {
                        Label(
                            "Add to Current Directory",
                            systemImage: "arrow.down.doc"
                        )
                    }
                    .disabled(currentDirectoryURL == nil)
                    .fileImporter(
                        isPresented: $showingAddImporter,
                        allowedContentTypes: [.item, .folder],
                        allowsMultipleSelection: false
                    ) { result in
                        handleAddImport(result)
                    }

                    Button(role: .destructive) {
                        showingDeleteImporter = true
                    } label: {
                        Label(
                            "Delete Selected Item",
                            systemImage: "trash"
                        )
                    }
                    .fileImporter(
                        isPresented: $showingDeleteImporter,
                        allowedContentTypes: [.item, .folder],
                        allowsMultipleSelection: false
                    ) { result in
                        handleDeleteImport(result)
                    }
                    .confirmationDialog(
                        "Delete Item?",
                        isPresented: $showingDeleteConfirmation,
                        titleVisibility: .visible
                    ) {
                        Button("Delete", role: .destructive) {
                            if let url = pendingDeleteURL {
                                deleteItem(at: url)
                            }
                            pendingDeleteURL = nil
                        }

                        Button("Cancel", role: .cancel) {
                            pendingDeleteURL = nil
                        }
                    } message: {
                        if let url = pendingDeleteURL {
                            Text(url.path)
                        }
                    }
                }

                Section("Log") {
                    ScrollView {
                        Text(log)
                            .font(.system(.footnote, design: .monospaced))
                            .textSelection(.enabled)
                            .fixedSize(
                                horizontal: false,
                                vertical: true
                            )
                            .frame(
                                maxWidth: .infinity,
                                alignment: .leading
                            )
                    }
                    .frame(minHeight: 180)

                    Button("Clear") {
                        log = "file manager ready"
                    }
                }
            }
            .navigationTitle("bad_query demo")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func consumeExtension(_ path: String) -> Int64 {
        if sandboxHandle > 0 {
            appendLog("\nalready consumed sandbox token!")
            return sandboxHandle
        }

        var pathC = path.utf8CString.map { Int8($0) }

        appendLog("\nattempting consume sandbox extension...")
        let handle = bad_query(&pathC, false, nil, false)

        switch handle {
        case -1:
            appendLog("\nfailed to resolve one or more functions")
        case -2:
            appendLog("\nfailed to create sandbox query")
        case -3:
            appendLog("\noutside of containermanager's sandbox")
        case -4:
            appendLog("\nkernel rejected sandbox query")
        default:
            appendLog("\nsuccess! handle: \(handle)")
        }

        return handle
    }

    private func releaseExtension(handle: Int64) {
        if handle < 0 {
            appendLog("\nsandbox extension hasn't been consumed!")
            return
        }

        bad_query_release(handle)
        appendLog("\nreleased sandbox extension!")
    }

    private func presentExportSheet(for url: URL) {
        guard let presenter = topViewController() else {
            appendLog(
                "\ncould not present export (no view controller)"
            )
            return
        }

        let activityVC = UIActivityViewController(
            activityItems: [url],
            applicationActivities: nil
        )

        activityVC.completionWithItemsHandler = {
            _, completed, _, error in
            if let error {
                appendLog(
                    "\nexport failed: \(error.localizedDescription)"
                )
            } else if completed {
                appendLog("\nexport completed")
            } else {
                appendLog("\nexport cancelled")
            }
        }

        if let popover = activityVC.popoverPresentationController {
            popover.sourceView = presenter.view
            popover.sourceRect = CGRect(
                x: presenter.view.bounds.midX,
                y: presenter.view.bounds.midY,
                width: 0,
                height: 0
            )
            popover.permittedArrowDirections = []
        }

        presenter.present(activityVC, animated: true)
    }

    private func topViewController() -> UIViewController? {
        guard
            let windowScene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive }),
            let rootVC = windowScene.windows
                .first(where: { $0.isKeyWindow })?
                .rootViewController
        else {
            return nil
        }

        return topMostViewController(from: rootVC)
    }

    private func topMostViewController(
        from viewController: UIViewController
    ) -> UIViewController {
        if let presented = viewController.presentedViewController {
            return topMostViewController(from: presented)
        }

        if let nav = viewController as? UINavigationController,
           let top = nav.topViewController {
            return topMostViewController(from: top)
        }

        if let tab = viewController as? UITabBarController,
           let selected = tab.selectedViewController {
            return topMostViewController(from: selected)
        }

        return viewController
    }

    private func handleImportedItem(
        _ result: Result<[URL], Error>
    ) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else {
                appendLog("\nno item selected")
                return
            }

            let accessed = url.startAccessingSecurityScopedResource()

            if !accessed {
                appendLog(
                    "\nfailed to obtain security-scoped access"
                )
                return
            }

            selectedURL = url

            if url.hasDirectoryPath {
                currentDirectoryURL = url

                appendLog(
                    "\nselected directory:\n\(url.path)"
                )
            } else {
                currentDirectoryURL = url.deletingLastPathComponent()

                appendLog(
                    "\nselected file:\n\(url.path)"
                )

                appendLog(
                    "\ncurrent directory:\n\(currentDirectoryURL?.path ?? "")"
                )
            }

            url.stopAccessingSecurityScopedResource()

        case .failure(let error):
            appendLog(
                "\nimport failed: \(error.localizedDescription)"
            )
        }
    }

    private func handleAddImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else {
                appendLog("\nno item selected to add")
                return
            }

            appendLog("\nadding item:\n\(url.path)")
            copyItem(url, to: currentDirectoryURL)

        case .failure(let error):
            appendLog(
                "\nadd import failed: \(error.localizedDescription)"
            )
        }
    }

    private func handleDeleteImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else {
                appendLog("\nno item selected to delete")
                return
            }

            pendingDeleteURL = url
            showingDeleteConfirmation = true

        case .failure(let error):
            appendLog(
                "\ndelete import failed: \(error.localizedDescription)"
            )
        }
    }

    private func showCurrentDirectory() {
        guard let url = selectedURL else {
            appendLog("\nno selected item")
            return
        }

        let directoryURL: URL

        if url.hasDirectoryPath {
            directoryURL = url
        } else {
            directoryURL = url.deletingLastPathComponent()
        }

        currentDirectoryURL = directoryURL

        appendLog(
            "\ncurrent directory:\n\(directoryURL.path)"
        )
    }

    private func copyItem(
        _ sourceURL: URL,
        to destinationDirectory: URL?
    ) {
        guard let destinationDirectory else {
            appendLog("\nno destination directory selected")
            return
        }

        let sourceAccessed =
            sourceURL.startAccessingSecurityScopedResource()

        let destinationAccessed =
            destinationDirectory
                .startAccessingSecurityScopedResource()

        defer {
            if sourceAccessed {
                sourceURL.stopAccessingSecurityScopedResource()
            }

            if destinationAccessed {
                destinationDirectory
                    .stopAccessingSecurityScopedResource()
            }
        }

        let destinationURL =
            destinationDirectory
                .appendingPathComponent(sourceURL.lastPathComponent)

        let fileManager = FileManager.default

        do {
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(
                    at: destinationURL
                )

                appendLog(
                    "\nremoved existing destination:\n\(destinationURL.path)"
                )
            }

            try fileManager.copyItem(
                at: sourceURL,
                to: destinationURL
            )

            appendLog(
                "\ncopied successfully:\n\(destinationURL.path)"
            )
        } catch {
            appendLog(
                "\ncopy failed:\n\(error.localizedDescription)"
            )
        }
    }

    private func deleteItem(at url: URL) {
        let accessed =
            url.startAccessingSecurityScopedResource()

        defer {
            if accessed {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let parentDirectory =
                url.deletingLastPathComponent()

            try FileManager.default.removeItem(
                at: url
            )

            appendLog(
                "\ndeleted:\n\(url.path)"
            )

            selectedURL = parentDirectory
            currentDirectoryURL = parentDirectory

            appendLog(
                "\ncurrent directory:\n\(parentDirectory.path)"
            )
        } catch {
            appendLog(
                "\ndelete failed:\n\(error.localizedDescription)"
            )
        }
    }

    private func appendLog(_ message: String) {
        log.append(message)
    }
}
