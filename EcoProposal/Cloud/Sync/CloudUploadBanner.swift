import SwiftUI

/// Top-of-list status while proposals are waiting to upload (e.g. the first
/// launch after the cloud update), or when a proposal needs the rep's decision.
struct CloudUploadBanner: View {
    private var sync: CloudSync { CloudSync.shared }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if sync.pendingUploads > 0 {
                HStack(spacing: 10) {
                    if sync.isSyncing && sync.lastError == nil {
                        ProgressView()
                    } else {
                        Image(systemName: "icloud.slash")
                            .foregroundStyle(.orange)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(sync.lastError == nil ? "Uploading to EcoPRO Cloud" : "Waiting to upload")
                            .font(.subheadline.weight(.semibold))
                        Text("\(sync.pendingUploads) proposal\(sync.pendingUploads == 1 ? "" : "s") left. Keep the app open until this finishes.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let error = sync.lastError {
                            Text("Will retry automatically. Last problem: \(error)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                }
            }
            if !sync.conflicts.isEmpty {
                Label(
                    "\(sync.conflicts.count) proposal\(sync.conflicts.count == 1 ? " was" : "s were") also changed on the website. Open \(sync.conflicts.count == 1 ? "it" : "them") to choose which version to keep.",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.caption)
                .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 4)
    }
}
