//
//  ContentView.swift
//  bad_query
//
//  Created by Taj C on 7/21/26.
//  Edited by Bennebotix on 8/13/26.
//

import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var sandboxHandles: [String: Int64] = [:]

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
                        _ = consumeExtension(
                            selectedURL?.path ?? defaultPath
                        )
                    }
                    .disabled(
                        (selectedURL?.path.isEmpty ?? true) ||
                        sandboxHandles[selectedURL?.path ?? defaultPath] != nil
                    )

                    Button("Release Sandbox Extension") {
                        releaseAllExtensions()
                    }
                    .disabled(sandboxHandles.isEmpty)

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
        if let existing = sandboxHandles[path] {
            appendLog(
                "\nalready consumed sandbox token for:\n\(path)"
            )
            return existing
        }

        var pathC = path.utf8CString.map { Int8($0) }

        appendLog(
            "\nattempting consume sandbox extension for:\n\(path)"
        )

        let handle = bad_query(&pathC, true, nil, false)

        switch handle {
        case -255:
            appendLog("\nfailed: not an absolute path")
        case -254:
            appendLog(
                "\nfailed: path missing or not stat-able from the app sandbox (lstat pre-check)"
            )
        case -5:
            appendLog("\nfailed to build path traversal string")
        case -1:
            appendLog("\nfailed to resolve one or more functions")
        case -2:
            appendLog("\nfailed to create sandbox query")
        case -3:
            appendLog("\noutside of containermanager's sandbox")
        case -4:
            appendLog("\nkernel rejected sandbox query")
        default:
            if handle > 0 {
                sandboxHandles[path] = handle
                appendLog("\nsuccess! handle: \(handle)")
            } else {
                appendLog(
                    "\nsandbox_extension_consume failed with code: \(handle)"
                )
            }
        }

        return handle
    }

    private func releaseAllExtensions() {
        if sandboxHandles.isEmpty {
            appendLog("\nno sandbox extensions consumed")
            return
        }

        for (path, handle) in sandboxHandles {
            bad_query_release(handle)
            appendLog(
                "\nreleased extension (\(handle)) for:\n\(path)"
            )
        }

        sandboxHandles.removeAll()
        appendLog("\nreleased all sandbox extensions")
    }

    @discardableResult
    private func ensureExtension(for path: String) -> Bool {
        let handle = consumeExtension(path)
        return handle > 0
    }

    private func presentExportSheet(for url: URL) {
        guard let presenter = topViewController() else {
            appendLog(
                "\ncould not present export (no view controller)"
            )
            return
        }

        let item: Any
        var stagedURL: URL?

        if url.hasDirectoryPath {
            item = url
        } else {
            guard let tempURL = stageFileForExport(url) else {
                return
            }
            stagedURL = tempURL
            item = tempURL
        }

        let activityVC = UIActivityViewController(
            activityItems: [item],
            applicationActivities: nil
        )

        activityVC.completionWithItemsHandler = {
            _, completed, _, error in
            if let stagedURL {
                try? FileManager.default.removeItem(at: stagedURL)
            }

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

    private func stageFileForExport(_ url: URL) -> URL? {
        guard ensureExtension(for: url.path) else {
            appendLog(
                "\nexport aborted: no sandbox extension for:\n\(url.path)"
            )
            return nil
        }

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                UUID().uuidString + "-" + url.lastPathComponent
            )

        let accessed = url.startAccessingSecurityScopedResource()

        defer {
            if accessed {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            try FileManager.default.copyItem(at: url, to: tempURL)
        } catch {
            appendLog(
                "\nfailed to stage export file:\n\(error.localizedDescription)"
            )
            return nil
        }

        appendLog("\nstaged export file:\n\(tempURL.path)")
        return tempURL
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

    private func copyItem(
        _ sourceURL: URL,
        to destinationDirectory: URL?
    ) {
        guard let destinationDirectory else {
            appendLog("\nno destination directory selected")
            return
        }

        guard ensureExtension(for: destinationDirectory.path) else {
            appendLog(
                "\ncopy aborted: no sandbox extension for destination:\n\(destinationDirectory.path)"
            )
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
        let parentDirectory = url.deletingLastPathComponent()

        guard ensureExtension(for: parentDirectory.path) else {
            appendLog(
                "\ndelete aborted: no sandbox extension for parent:\n\(parentDirectory.path)"
            )
            return
        }

        let accessed =
            url.startAccessingSecurityScopedResource()

        defer {
            if accessed {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
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
