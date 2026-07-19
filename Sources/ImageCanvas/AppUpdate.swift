import AppKit
import CryptoKit
import Foundation
import SwiftUI

struct AppVersion: Comparable, Equatable {
    let components: [Int]
    let build: Int

    init?(_ version: String, build: String = "0") {
        let cleaned = version.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
        let values = cleaned.split(separator: ".", omittingEmptySubsequences: false)
        guard !values.isEmpty,
              values.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }) else {
            return nil
        }
        var normalizedComponents = values.compactMap { Int($0) }
        while normalizedComponents.count > 1, normalizedComponents.last == 0 {
            normalizedComponents.removeLast()
        }
        components = normalizedComponents
        self.build = Int(build) ?? 0
    }

    static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)
        for index in 0..<count {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right { return left < right }
        }
        return lhs.build < rhs.build
    }

    var displayString: String {
        components.map(String.init).joined(separator: ".")
    }
}

struct AppUpdateCandidate {
    let version: AppVersion
    let assetName: String
    let assetURL: URL
    let expectedSHA256: String
    let releasePageURL: URL
    let canInstallAutomatically: Bool
    let automaticInstallBlockReason: String?
}

enum AppUpdateState {
    case idle
    case checking
    case noUpdate
    case available(AppUpdateCandidate)
    case downloading(AppUpdateCandidate)
    case preparing(AppUpdateCandidate)
    case installing
    case error(String)
}

enum AppUpdateError: LocalizedError, Equatable {
    case invalidResponse
    case malformedRelease
    case ambiguousAssets
    case missingDigest
    case invalidDigest
    case invalidDownloadURL
    case downloadFailed
    case archiveTooLarge
    case unsafeArchive
    case invalidAppBundle(String)
    case updateIsNotNewer
    case automaticInstallUnavailable(String)
    case helperUnavailable
    case stagingFailed

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "GitHub returned an unexpected response."
        case .malformedRelease:
            "The latest GitHub release is missing required version information."
        case .ambiguousAssets:
            "The latest release must contain exactly one ImageCanvas ZIP asset."
        case .missingDigest:
            "The release ZIP has no GitHub-published SHA-256 digest."
        case .invalidDigest:
            "The downloaded ZIP does not match GitHub's published SHA-256 digest."
        case .invalidDownloadURL:
            "The release download URL is not a valid GitHub HTTPS URL."
        case .downloadFailed:
            "The update could not be downloaded from GitHub."
        case .archiveTooLarge:
            "The release ZIP is unexpectedly large."
        case .unsafeArchive:
            "The release ZIP contains an unsafe path or unsupported structure."
        case let .invalidAppBundle(reason):
            "The downloaded app failed validation: \(reason)"
        case .updateIsNotNewer:
            "The downloaded app is not newer than this copy."
        case let .automaticInstallUnavailable(reason):
            reason
        case .helperUnavailable:
            "The automatic replacement helper is missing from this copy."
        case .stagingFailed:
            "The new app could not be staged beside this copy."
        }
    }
}

@MainActor
final class AppUpdateController: ObservableObject {
    static let repositoryURL = URL(string: "https://github.com/viktorkpkn/ImageCanvas")!
    static let disclosure = "Update downloads the latest ImageCanvas release from GitHub, verifies its GitHub-published SHA-256 digest and app identity/version, then closes ImageCanvas, replaces this copy, and reopens it. Releases are not notarized or independently signed. Choose Open GitHub to install manually instead."

    @Published var isPresented = false
    @Published private(set) var state: AppUpdateState = .idle

    private var task: Task<Void, Never>?

    deinit {
        task?.cancel()
    }

    func presentAndCheck() {
        isPresented = true
        check()
    }

    func check() {
        task?.cancel()
        state = .checking
        task = Task { [weak self] in
            do {
                let result = try await AppUpdateService.checkForUpdate()
                guard !Task.isCancelled else { return }
                self?.state = result.map(AppUpdateState.available) ?? .noUpdate
            } catch is CancellationError {
                return
            } catch {
                self?.state = .error(error.localizedDescription)
            }
        }
    }

    func install(_ candidate: AppUpdateCandidate, beforeTermination: @escaping @MainActor () -> Void) {
        guard candidate.canInstallAutomatically else {
            state = .error(candidate.automaticInstallBlockReason ?? "This copy cannot be replaced automatically.")
            return
        }

        task?.cancel()
        state = .downloading(candidate)
        task = Task { [weak self] in
            do {
                let downloaded = try await AppUpdateService.download(candidate)
                guard !Task.isCancelled else { return }
                self?.state = .preparing(candidate)
                let launch = try await AppUpdateInstaller.prepare(candidate: candidate, archiveURL: downloaded)
                guard !Task.isCancelled else { return }
                try launch.start()
                self?.state = .installing
                beforeTermination()
            } catch is CancellationError {
                return
            } catch {
                self?.state = .error(error.localizedDescription)
            }
        }
    }

    func close() {
        task?.cancel()
        task = nil
        isPresented = false
        state = .idle
    }

    func openGitHub(_ url: URL? = nil) {
        NSWorkspace.shared.open(url ?? Self.repositoryURL)
    }
}

struct AppUpdateSheet: View {
    @ObservedObject var controller: AppUpdateController
    let saveBeforeTermination: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.title3.weight(.semibold))

            content

            Divider()

            HStack(spacing: 10) {
                Spacer()
                buttons
            }
        }
        .padding(20)
        .frame(width: 500)
        .interactiveDismissDisabled(isBusy)
    }

    private var title: String {
        switch controller.state {
        case .checking: "Checking for Updates"
        case .noUpdate: "No Updates Available"
        case let .available(candidate): "ImageCanvas \(candidate.version.displayString) Is Available"
        case .downloading: "Downloading Update"
        case .preparing: "Verifying Update"
        case .installing: "Installing Update"
        case .error: "Couldn’t Check for Updates"
        case .idle: "Check for Updates"
        }
    }

    @ViewBuilder
    private var content: some View {
        switch controller.state {
        case .checking:
            progress("Contacting GitHub…")
        case .noUpdate:
            Text("You’re using the latest stable version of ImageCanvas.")
                .foregroundStyle(.secondary)
        case let .available(candidate):
            VStack(alignment: .leading, spacing: 12) {
                Text("A newer stable release is available on GitHub.")
                Text(AppUpdateController.disclosure)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let reason = candidate.automaticInstallBlockReason {
                    Label(reason, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        case .downloading:
            progress("Downloading the release ZIP from GitHub…")
        case .preparing:
            progress("Checking the digest, app identity, version, and code structure…")
        case .installing:
            progress("Closing ImageCanvas and handing off to the replacement helper…")
        case let .error(message):
            Text(message)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        case .idle:
            EmptyView()
        }
    }

    private func progress(_ label: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(label)
                .foregroundStyle(.secondary)
            ProgressView()
                .progressViewStyle(.linear)
                .tint(.accentColor)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var buttons: some View {
        switch controller.state {
        case .checking, .downloading, .preparing, .installing:
            EmptyView()
        case .noUpdate:
            Button("Close") { controller.close() }
                .keyboardShortcut(.defaultAction)
        case let .available(candidate):
            Button("Open GitHub") { controller.openGitHub(candidate.releasePageURL) }
            Button("Close") { controller.close() }
                .keyboardShortcut(.cancelAction)
            Button("Update") {
                controller.install(candidate) {
                    saveBeforeTermination()
                    NSApplication.shared.terminate(nil)
                }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(!candidate.canInstallAutomatically)
        case .error:
            Button("Open GitHub") { controller.openGitHub() }
            Button("Close") { controller.close() }
                .keyboardShortcut(.cancelAction)
            Button("Try Again") { controller.check() }
                .keyboardShortcut(.defaultAction)
        case .idle:
            Button("Close") { controller.close() }
                .keyboardShortcut(.defaultAction)
        }
    }

    private var isBusy: Bool {
        switch controller.state {
        case .checking, .downloading, .preparing, .installing: true
        default: false
        }
    }
}

private struct GitHubRelease: Decodable {
    struct Asset: Decodable {
        let name: String
        let browserDownloadURL: URL
        let size: Int
        let digest: String?

        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadURL = "browser_download_url"
            case size
            case digest
        }
    }

    let tagName: String
    let htmlURL: URL
    let draft: Bool
    let prerelease: Bool
    let assets: [Asset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case draft
        case prerelease
        case assets
    }
}

enum AppUpdateService {
    private static let releaseAPI = URL(string: "https://api.github.com/repos/viktorkpkn/ImageCanvas/releases/latest")!
    private static let maximumArchiveBytes = 1_000_000_000

    static func checkForUpdate() async throws -> AppUpdateCandidate? {
        var request = URLRequest(url: releaseAPI)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("ImageCanvas-Updater", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 20

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw AppUpdateError.invalidResponse
        }

        let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
        guard !release.draft, !release.prerelease,
              let releaseVersion = AppVersion(release.tagName) else {
            throw AppUpdateError.malformedRelease
        }

        let zipAssets = release.assets.filter { $0.name.lowercased().hasSuffix(".zip") }
        guard zipAssets.count == 1,
              let asset = zipAssets.first,
              asset.name.localizedCaseInsensitiveContains("ImageCanvas") else {
            throw AppUpdateError.ambiguousAssets
        }
        guard asset.size > 0, asset.size <= maximumArchiveBytes else {
            throw AppUpdateError.archiveTooLarge
        }
        guard asset.browserDownloadURL.scheme == "https",
              asset.browserDownloadURL.host?.lowercased() == "github.com" else {
            throw AppUpdateError.invalidDownloadURL
        }
        guard let digest = normalizedDigest(asset.digest) else {
            throw AppUpdateError.missingDigest
        }

        let currentVersion = currentAppVersion()
        guard let assetBuild = buildNumber(in: asset.name) else {
            throw AppUpdateError.malformedRelease
        }
        let comparableRelease = AppVersion(releaseVersion.displayString, build: String(assetBuild))!
        guard comparableRelease > currentVersion else { return nil }

        let automaticInstall = AppUpdateInstaller.automaticInstallAvailability()
        return AppUpdateCandidate(
            version: comparableRelease,
            assetName: asset.name,
            assetURL: asset.browserDownloadURL,
            expectedSHA256: digest,
            releasePageURL: release.htmlURL,
            canInstallAutomatically: automaticInstall.reason == nil,
            automaticInstallBlockReason: automaticInstall.reason
        )
    }

    static func download(_ candidate: AppUpdateCandidate) async throws -> URL {
        var request = URLRequest(url: candidate.assetURL)
        request.setValue("ImageCanvas-Updater", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 120
        let (temporaryURL, response) = try await URLSession.shared.download(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw AppUpdateError.downloadFailed
        }

        let root = try AppUpdateInstaller.makePrivateTemporaryDirectory()
        let archiveURL = root.appendingPathComponent(candidate.assetName)
        try FileManager.default.moveItem(at: temporaryURL, to: archiveURL)
        let digest = try sha256(of: archiveURL)
        guard digest == candidate.expectedSHA256 else {
            try? FileManager.default.removeItem(at: root)
            throw AppUpdateError.invalidDigest
        }
        return archiveURL
    }

    static func normalizedDigest(_ digest: String?) -> String? {
        guard let digest else { return nil }
        let value = digest.lowercased().hasPrefix("sha256:")
            ? String(digest.dropFirst("sha256:".count)).lowercased()
            : digest.lowercased()
        guard value.count == 64, value.allSatisfy({ $0.isHexDigit }) else { return nil }
        return value
    }

    static func buildNumber(in assetName: String) -> Int? {
        guard let range = assetName.range(of: #"build([0-9]+)"#, options: [.regularExpression, .caseInsensitive]) else {
            return nil
        }
        return Int(assetName[range].drop(while: { !$0.isNumber }))
    }

    static func currentAppVersion() -> AppVersion {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        return AppVersion(version, build: build) ?? AppVersion("0")!
    }

    static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let data = try handle.read(upToCount: 1_048_576) ?? Data()
            if data.isEmpty { break }
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

struct PreparedUpdateLaunch {
    let helperURL: URL
    let arguments: [String]

    func start() throws {
        let process = Process()
        process.executableURL = helperURL
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
    }
}

enum AppUpdateInstaller {
    private static let bundleIdentifier = "local.imagecanvas.app"

    struct Availability {
        let reason: String?
    }

    static func automaticInstallAvailability() -> Availability {
        let appURL = Bundle.main.bundleURL.standardizedFileURL
        guard appURL.pathExtension == "app" else {
            return Availability(reason: "Automatic update is available only from a packaged ImageCanvas app.")
        }
        guard !appURL.path.contains("/AppTranslocation/") else {
            return Availability(reason: "Move ImageCanvas to Applications and reopen it before updating automatically.")
        }
        let parent = appURL.deletingLastPathComponent()
        guard FileManager.default.isWritableFile(atPath: parent.path),
              FileManager.default.isWritableFile(atPath: appURL.path) else {
            return Availability(reason: "This copy is not writable. Open GitHub to install the update manually.")
        }
        guard Bundle.main.url(forResource: "ImageCanvasUpdateHelper", withExtension: "sh") != nil else {
            return Availability(reason: "This copy does not include the automatic replacement helper. Open GitHub to install manually.")
        }
        return Availability(reason: nil)
    }

    static func makePrivateTemporaryDirectory() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ImageCanvasUpdate-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        return root
    }

    static func prepare(candidate: AppUpdateCandidate, archiveURL: URL) async throws -> PreparedUpdateLaunch {
        try await Task.detached(priority: .userInitiated) {
            try prepareSynchronously(candidate: candidate, archiveURL: archiveURL)
        }.value
    }

    private static func prepareSynchronously(
        candidate: AppUpdateCandidate,
        archiveURL: URL
    ) throws -> PreparedUpdateLaunch {
        let availability = automaticInstallAvailability()
        if let reason = availability.reason {
            throw AppUpdateError.automaticInstallUnavailable(reason)
        }

        let root = archiveURL.deletingLastPathComponent()
        try validateArchivePaths(archiveURL)
        let extractionURL = root.appendingPathComponent("Extracted", isDirectory: true)
        try FileManager.default.createDirectory(at: extractionURL, withIntermediateDirectories: false)
        try run("/usr/bin/ditto", arguments: ["-x", "-k", archiveURL.path, extractionURL.path])

        let appURL = try locateSingleApp(in: extractionURL)
        try validateApp(appURL, candidate: candidate)

        let currentApp = Bundle.main.bundleURL.standardizedFileURL
        let parent = currentApp.deletingLastPathComponent()
        let identifier = UUID().uuidString
        let stagedApp = parent.appendingPathComponent(".ImageCanvas.update-\(identifier).app", isDirectory: true)
        let backupApp = parent.appendingPathComponent(".ImageCanvas.backup-\(identifier).app", isDirectory: true)
        do {
            try FileManager.default.copyItem(at: appURL, to: stagedApp)
            try validateApp(stagedApp, candidate: candidate)
        } catch {
            try? FileManager.default.removeItem(at: stagedApp)
            throw AppUpdateError.stagingFailed
        }

        guard let bundledHelper = Bundle.main.url(forResource: "ImageCanvasUpdateHelper", withExtension: "sh") else {
            try? FileManager.default.removeItem(at: stagedApp)
            throw AppUpdateError.helperUnavailable
        }
        let helperURL = root.appendingPathComponent("ImageCanvasUpdateHelper.sh")
        try FileManager.default.copyItem(at: bundledHelper, to: helperURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: helperURL.path)

        return PreparedUpdateLaunch(
            helperURL: helperURL,
            arguments: [
                currentApp.path,
                stagedApp.path,
                backupApp.path,
                String(ProcessInfo.processInfo.processIdentifier),
                root.path
            ]
        )
    }

    private static func validateArchivePaths(_ archiveURL: URL) throws {
        let output = try run("/usr/bin/unzip", arguments: ["-Z1", archiveURL.path])
        let entries = output.split(whereSeparator: \.isNewline).map(String.init)
        guard !entries.isEmpty else { throw AppUpdateError.unsafeArchive }
        for entry in entries {
            let normalized = entry.replacingOccurrences(of: "\\", with: "/")
            let components = normalized.split(separator: "/", omittingEmptySubsequences: false)
            if normalized.hasPrefix("/") || components.contains("..") {
                throw AppUpdateError.unsafeArchive
            }
        }
    }

    private static func locateSingleApp(in extractionURL: URL) throws -> URL {
        let contents = try FileManager.default.contentsOfDirectory(
            at: extractionURL,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        )
        let apps = contents.filter { $0.pathExtension == "app" }
        guard apps.count == 1, contents.count == 1, let app = apps.first else {
            throw AppUpdateError.unsafeArchive
        }
        let values = try app.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else {
            throw AppUpdateError.unsafeArchive
        }
        return app
    }

    private static func validateApp(_ appURL: URL, candidate: AppUpdateCandidate) throws {
        guard let bundle = Bundle(url: appURL),
              bundle.bundleIdentifier == bundleIdentifier else {
            throw AppUpdateError.invalidAppBundle("bundle identifier mismatch")
        }
        guard let versionString = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
              let buildString = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
              let version = AppVersion(versionString, build: buildString) else {
            throw AppUpdateError.invalidAppBundle("missing version metadata")
        }
        guard version == candidate.version else {
            throw AppUpdateError.invalidAppBundle("release and app version/build do not match")
        }
        guard version > AppUpdateService.currentAppVersion() else {
            throw AppUpdateError.updateIsNotNewer
        }
        guard let executable = bundle.executableURL?.standardizedFileURL,
              executable.path.hasPrefix(appURL.standardizedFileURL.path + "/"),
              FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw AppUpdateError.invalidAppBundle("missing executable")
        }

        if let enumerator = FileManager.default.enumerator(
            at: appURL,
            includingPropertiesForKeys: [.isSymbolicLinkKey],
            options: [],
            errorHandler: { _, _ in false }
        ) {
            for case let url as URL in enumerator {
                if try url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true {
                    throw AppUpdateError.invalidAppBundle("symbolic links are not allowed")
                }
            }
        }
        try run("/usr/bin/codesign", arguments: ["--verify", "--deep", "--strict", appURL.path])
    }

    @discardableResult
    private static func run(_ executable: String, arguments: [String]) throws -> String {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard process.terminationStatus == 0 else {
            throw AppUpdateError.invalidAppBundle(String(data: data, encoding: .utf8) ?? "validation command failed")
        }
        return String(data: data, encoding: .utf8) ?? ""
    }
}
