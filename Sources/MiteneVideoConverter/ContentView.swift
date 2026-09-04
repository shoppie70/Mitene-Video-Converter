import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var model = AppModel()
    @State private var isTargeted = false
    @State private var showingImporter = false

    var body: some View {
        VStack(spacing: 0) {
            header
            if model.jobs.isEmpty {
                dropZone
            } else {
                queue
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [.movie, .mpeg4Movie, .quickTimeMovie],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result { model.add(urls: urls) }
        }
        .alert("写真に追加できませんでした", isPresented: $model.isShowingError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(model.errorMessage)
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("2分にしてね")
                    .font(.system(size: 25, weight: .bold, design: .rounded))
                Text("Mitene Video Converter")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if !model.jobs.isEmpty {
                Button("動画を追加") { showingImporter = true }
                    .buttonStyle(.bordered)
            }
        }
        .padding(.horizontal, 32)
        .padding(.top, 28)
        .padding(.bottom, 24)
    }

    private var dropZone: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "arrow.down.doc")
                .font(.system(size: 42, weight: .light))
                .foregroundStyle(Color.accentColor)
            VStack(spacing: 8) {
                Text("動画をここにドロップ")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                Text("みてねにアップロードしやすい動画に、いい感じに変換します")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            Button("または動画を選ぶ") { showingImporter = true }
                .buttonStyle(.borderedProminent)
            Text("MP4・MOV・M4V ／ 元の動画は変更しません")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(isTargeted ? Color.accentColor : Color.secondary.opacity(0.25), style: StrokeStyle(lineWidth: 2, dash: [8]))
                .padding(24)
                .allowsHitTesting(false)
        }
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: $isTargeted) { providers in
            model.handleDrop(providers: providers)
        }
    }

    private var queue: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(model.jobs) { job in
                        JobRow(job: job)
                    }
                }
                .padding(.horizontal, 32)
            }
            if !model.lastCompletedOutputs.isEmpty && !model.isProcessing {
                completionPanel
            } else if model.isProcessing {
                HStack {
                    ProgressView()
                    Text("動画を順番に変換しています")
                        .font(.callout)
                    Spacer()
                    Button("キャンセル") { model.cancel() }
                }
                .padding(20)
                .background(.bar)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: $isTargeted) { providers in
            model.handleDrop(providers: providers)
        }
    }

    private var completionPanel: some View {
        VStack(spacing: 14) {
            Text("できました！")
                .font(.system(size: 20, weight: .bold, design: .rounded))
            Text("\(model.lastCompletedOutputs.count)本のみてね用動画を作りました。")
                .foregroundStyle(.secondary)
            HStack {
                Button("写真に追加") { model.addLastResultsToPhotos() }
                    .buttonStyle(.borderedProminent)
                Button("Finderで表示") { model.revealOutputDirectory() }
                    .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(22)
        .background(.bar)
    }
}

private struct JobRow: View {
    let job: AppModel.Job
    @State private var isCopied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: iconName)
                    .foregroundStyle(iconColor)
                Text(job.url.lastPathComponent)
                    .lineLimit(1)
                    .fontWeight(.medium)
                Spacer()
                Text(job.state.label)
                    .font(.caption)
                    .foregroundStyle(statusColor)
            }
            if case .converting(let progress) = job.state {
                ProgressView(value: progress)
            }
            if case .failed(let message) = job.state {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(.red)
                        .font(.system(size: 13))
                        .padding(.top, 1)
                    Text(message)
                        .font(.system(size: 12))
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(message, forType: .string)
                        isCopied = true
                        Task {
                            try? await Task.sleep(for: .seconds(2))
                            isCopied = false
                        }
                    } label: {
                        Label(isCopied ? "コピー完了" : "エラーをコピー", systemImage: isCopied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(isCopied ? .green : .secondary)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.red.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.red.opacity(0.25), lineWidth: 1)
                )
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
    }

    private var iconName: String {
        switch job.state {
        case .failed: return "exclamationmark.triangle.fill"
        case .completed: return "checkmark.circle.fill"
        default: return "film"
        }
    }

    private var iconColor: Color {
        switch job.state {
        case .failed: return .red
        case .completed: return .green
        default: return Color.accentColor
        }
    }

    private var statusColor: Color {
        switch job.state {
        case .failed: return .red
        case .completed: return .green
        default: return .secondary
        }
    }
}
