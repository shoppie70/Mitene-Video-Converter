import AppKit
import Combine
import Foundation
import UniformTypeIdentifiers

@MainActor
final class AppModel: ObservableObject {
    enum JobState: Equatable {
        case waiting
        case analyzing
        case converting(Double)
        case completed(Int)
        case failed(String)

        var label: String {
            switch self {
            case .waiting: return "待機中"
            case .analyzing: return "読み込み中…"
            case .converting: return "みてね用に変換中…"
            case .completed(let count): return "完了（\(count)本）"
            case .failed(let message): return message
            }
        }
    }

    struct Job: Identifiable {
        let id = UUID()
        let url: URL
        var state: JobState = .waiting
        var outputs: [URL] = []
    }

    @Published var jobs: [Job] = []
    @Published var isProcessing = false
    @Published var lastCompletedOutputs: [URL] = []
    @Published var isShowingError = false
    @Published var errorMessage = ""

    let outputDirectory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Movies", isDirectory: true)
        .appendingPathComponent("2分にしてね", isDirectory: true)

    private let analyzer = VideoAnalyzer()
    private let planner = ConversionPlanner()
    private let converter = VideoConverter()
    private let photoExporter = PhotoLibraryExporter()
    private var processingTask: Task<Void, Never>?

    deinit {
        processingTask?.cancel()
    }

    func add(urls: [URL]) {
        let videos = urls.filter { $0.pathExtension.lowercased() == "mp4" || $0.pathExtension.lowercased() == "mov" || $0.pathExtension.lowercased() == "m4v" }
        let existing = Set(jobs.map(\.url.standardizedFileURL))
        jobs.append(contentsOf: videos.filter { !existing.contains($0.standardizedFileURL) }.map { Job(url: $0) })
        startIfNeeded()
    }

    func handleDrop(providers: [NSItemProvider]) -> Bool {
        let accepted = providers.contains { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
        guard accepted else { return false }
        providers.forEach { provider in
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { [weak self] item, _ in
                let url: URL?
                if let data = item as? Data {
                    url = URL(dataRepresentation: data, relativeTo: nil)
                } else if let fileURL = item as? URL {
                    url = fileURL
                } else {
                    url = nil
                }
                guard let url else { return }
                Task { @MainActor in self?.add(urls: [url]) }
            }
        }
        return true
    }

    func cancel() {
        processingTask?.cancel()
        processingTask = nil
        isProcessing = false
        jobs.indices.filter { isActive(jobs[$0].state) }.forEach { jobs[$0].state = .waiting }
    }

    func revealOutputDirectory() {
        NSWorkspace.shared.open(outputDirectory)
    }

    func addLastResultsToPhotos() {
        let urls = lastCompletedOutputs
        guard !urls.isEmpty else { return }
        Task {
            do {
                try await photoExporter.add(urls: urls)
            } catch {
                showError(error.localizedDescription)
            }
        }
    }

    private func startIfNeeded() {
        guard processingTask == nil else { return }
        processingTask = Task { [weak self] in
            await self?.processQueue()
        }
    }

    private func processQueue() async {
        isProcessing = true
        lastCompletedOutputs = []
        for index in jobs.indices {
            guard !Task.isCancelled else { break }
            guard case .waiting = jobs[index].state else { continue }
            do {
                jobs[index].state = .analyzing
                let analysis = try await analyzer.analyze(url: jobs[index].url)
                let plan = planner.plan(for: analysis)
                jobs[index].state = .converting(0)
                let outputs = try await converter.convert(analysis: analysis, plan: plan, outputDirectory: outputDirectory) { [weak self] value in
                    self?.jobs[index].state = .converting(value)
                }
                jobs[index].outputs = outputs
                jobs[index].state = .completed(outputs.count)
                lastCompletedOutputs.append(contentsOf: outputs)
            } catch is CancellationError {
                break
            } catch {
                jobs[index].state = .failed(error.localizedDescription)
            }
        }
        isProcessing = false
        processingTask = nil
    }

    private func isActive(_ state: JobState) -> Bool {
        switch state {
        case .analyzing, .converting: return true
        default: return false
        }
    }

    private func showError(_ message: String) {
        errorMessage = message
        isShowingError = true
    }
}
