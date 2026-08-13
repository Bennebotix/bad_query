//
//  ContentView.swift
//  bad_query
//
//  Created by Taj C on 7/21/26.
//

import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var showingImporter = false
    @State private var showingDeleteConfirmation = false
    
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
                        showingImporter = true
                    } label: {
                        Label(
                            "Select File or Folder",
                            systemImage: "folder.badge.plus"
                        )
                    }

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

                Section("File Operations") {
                    Button {
                        copySelectedItemToCurrentDirectory()
                    } label: {
                        Label(
                            "Add to Current Directory",
                            systemImage: "arrow.down.doc"
                        )
                    }
                    .disabled(
                        selectedURL == nil ||
                        currentDirectoryURL == nil
                    )

                    Button(role: .destructive) {
                        showingDeleteConfirmation = true
                    } label: {
                        Label(
                            "Delete Selected Item",
                            systemImage: "trash"
                        )
                    }
                    .disabled(selectedURL == nil)
                }

                Section("Directory") {
                    if let currentDirectoryURL {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Current Directory")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Text(currentDirectoryURL.path)
                                .font(.system(.footnote, design: .monospaced))
                                .textSelection(.enabled)
                        }
                    } else {
                        Text("No directory selected")
                            .foregroundStyle(.secondary)
                    }

                    Button {
                        showingImporter = true
                    } label: {
                        Label(
                            "Select Directory",
                            systemImage: "folder"
                        )
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
            .fileImporter(
                isPresented: $showingImporter,
                allowedContentTypes: [
                    .item,
                    .folder
                ],
                allowsMultipleSelection: false
            ) { result in
                handleImportedItem(result)
            }
            .confirmationDialog(
                "Delete Selected Item?",
                isPresented: $showingDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    deleteSelectedItem()
                }

                Button("Cancel", role: .cancel) {}
            } message: {
                if let selectedURL {
                    Text(selectedURL.path)
                }
            }
        }
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

    private func copySelectedItemToCurrentDirectory() {
        guard let sourceURL = selectedURL else {
            appendLog("\nno source item selected")
            return
        }

        guard let destinationDirectory = currentDirectoryURL else {
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

    private func deleteSelectedItem() {
        guard let url = selectedURL else {
            appendLog("\nno item selected")
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
