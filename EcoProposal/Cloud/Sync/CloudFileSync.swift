import Foundation
import SwiftUI
import SwiftData
import CryptoKit
import Supabase
#if canImport(UIKit)
import UIKit
#endif
#if canImport(PencilKit) && os(iOS)
import PencilKit
#endif

// MARK: - Rows for the file tables

nonisolated struct PhotoPayload: Encodable, Sendable {
    var id: UUID
    var proposal_id: UUID
    var image_path: String
    var markup_drawing_path: String?
    var markup_png_path: String?
    var caption: String
    var sort_order: Int
}

nonisolated struct SketchPayload: Encodable, Sendable {
    var id: UUID
    var proposal_id: UUID
    var page_number: Int
    var drawing_path: String?
    var png_path: String?
    var annotations: AnyJSON
    var segments: AnyJSON
    var cracks: AnyJSON
}

nonisolated struct SignaturePayload: Encodable, Sendable {
    var id: UUID
    var proposal_id: UUID
    var party: String
    var signer_name: String
    var signed_at: String
    var drawing_path: String?
    var png_path: String?
}

nonisolated struct ProposalDocumentPayload: Encodable, Sendable {
    var id: UUID
    var proposal_id: UUID
    var title: String
    var file_path: String
    var sort_order: Int
}

nonisolated struct CloudPhotoRow: Decodable, Sendable {
    let id: UUID
    let proposal_id: UUID?
    let image_path: String
    let markup_drawing_path: String?
    let caption: String
    let sort_order: Int
}

nonisolated struct CloudSketchRow: Decodable, Sendable {
    let id: UUID
    let proposal_id: UUID
    let drawing_path: String?
    let annotations: AnyJSON?
    let segments: AnyJSON?
    let cracks: AnyJSON?
}

nonisolated struct CloudSignatureRow: Decodable, Sendable {
    let id: UUID
    let proposal_id: UUID?
    let party: String
    let signer_name: String
    let signed_at: String
    let drawing_path: String?
}

nonisolated struct CloudProposalDocumentRow: Decodable, Sendable {
    let id: UUID
    let proposal_id: UUID
    let title: String
    let file_path: String
    let sort_order: Int
}

/// Phase 3, session 4: photos (+ Pencil markup), job sketches, signatures and
/// attached PDFs, in both directions.
///
/// Storage layout (the first folder must be the org id — the storage policy checks it):
///   <org>/proposals/<proposal>/photos/<photo>.jpg | -markup.pkdrawing | -markup.png
///   <org>/proposals/<proposal>/sketch/<proposal>.pkdrawing | .png
///   <org>/proposals/<proposal>/signatures/<party>.pkdrawing | .png
///   <org>/proposals/<proposal>/documents/<document>.pdf
/// PencilKit data keeps drawings editable on iPads; the PNG copies are what the
/// website shows.
extension CloudSync {

    // MARK: - Upload

    func pushFiles(for p: Proposal, profile: CloudProfile) async throws {
        let base = "\(profile.orgId.uuidString.lowercased())/proposals/\(p.id.uuidString.lowercased())"
        try await pushPhotos(for: p, base: base)
        try await pushDocuments(for: p, base: base)
        try await pushSketch(for: p, base: base)
        // Last on purpose: once customer + rep have both signed, the database locks the proposal.
        try await pushSignatures(for: p, base: base)
    }

    private func pushPhotos(for p: Proposal, base: String) async throws {
        let photos = p.photos
        for photo in photos {
            let imagePath = "\(base)/photos/\(photo.id.uuidString.lowercased()).jpg"
            if !state.stored.uploadedPhotoImages.contains(photo.id) {
                let data = Self.jpegForUpload(photo.imageData) ?? photo.imageData
                try await upload(imagePath, data: data, contentType: "image/jpeg")
                state.stored.uploadedPhotoImages.insert(photo.id)
                state.save()
            }

            let fp = Self.photoFingerprint(photo)
            guard state.stored.photoFingerprints[photo.id] != fp else { continue }

            var markupDrawing: String?
            var markupPNG: String?
            if let ink = photo.annotationData, !ink.isEmpty {
                markupDrawing = "\(base)/photos/\(photo.id.uuidString.lowercased())-markup.pkdrawing"
                try await upload(markupDrawing!, data: ink, contentType: "application/octet-stream")
                if let png = Self.drawingPNG(ink) {
                    markupPNG = "\(base)/photos/\(photo.id.uuidString.lowercased())-markup.png"
                    try await upload(markupPNG!, data: png, contentType: "image/png")
                }
            }

            let row = PhotoPayload(
                id: photo.id, proposal_id: p.id, image_path: imagePath,
                markup_drawing_path: markupDrawing, markup_png_path: markupPNG,
                caption: photo.caption, sort_order: photo.sortOrder
            )
            try await client.from("photos").upsert(row, onConflict: "id").execute()
            state.stored.photoFingerprints[photo.id] = fp
        }

        // Photos deleted on this iPad
        let current = Set(photos.map(\.id))
        let removed = Set(state.stored.proposalPhotoIDs[p.id] ?? []).subtracting(current)
        if !removed.isEmpty {
            try await client.from("photos").delete().in("id", values: removed.map(\.uuidString)).execute()
            let paths = removed.flatMap { id -> [String] in
                let stem = "\(base)/photos/\(id.uuidString.lowercased())"
                return ["\(stem).jpg", "\(stem)-markup.pkdrawing", "\(stem)-markup.png"]
            }
            _ = try? await client.storage.from("eco-files").remove(paths: paths)
            for id in removed {
                state.stored.photoFingerprints[id] = nil
                state.stored.uploadedPhotoImages.remove(id)
            }
        }
        state.stored.proposalPhotoIDs[p.id] = Array(current)
    }

    private func pushDocuments(for p: Proposal, base: String) async throws {
        let docs = p.documents
        for doc in docs {
            let path = "\(base)/documents/\(doc.id.uuidString.lowercased()).pdf"
            if !state.stored.uploadedDocuments.contains(doc.id) {
                try await upload(path, data: doc.pdfData, contentType: "application/pdf")
                state.stored.uploadedDocuments.insert(doc.id)
                state.save()
            }
            let fp = Self.hash(Data("\(doc.title)|\(doc.sortOrder)".utf8))
            guard state.stored.documentFingerprints[doc.id] != fp else { continue }
            let row = ProposalDocumentPayload(id: doc.id, proposal_id: p.id, title: doc.title, file_path: path, sort_order: doc.sortOrder)
            try await client.from("proposal_documents").upsert(row, onConflict: "id").execute()
            state.stored.documentFingerprints[doc.id] = fp
        }

        let current = Set(docs.map(\.id))
        let removed = Set(state.stored.proposalDocumentIDs[p.id] ?? []).subtracting(current)
        if !removed.isEmpty {
            try await client.from("proposal_documents").delete().in("id", values: removed.map(\.uuidString)).execute()
            _ = try? await client.storage.from("eco-files")
                .remove(paths: removed.map { "\(base)/documents/\($0.uuidString.lowercased()).pdf" })
            for id in removed {
                state.stored.documentFingerprints[id] = nil
                state.stored.uploadedDocuments.remove(id)
            }
        }
        state.stored.proposalDocumentIDs[p.id] = Array(current)
    }

    private func pushSketch(for p: Proposal, base: String) async throws {
        let fp = Self.sketchFingerprint(p)
        guard state.stored.sketchFingerprints[p.id] != fp else { return }

        let hasSketch = (p.sketchData?.isEmpty == false)
            || (p.sketchAnnotationsData?.isEmpty == false)
            || (p.sketchSegmentsData?.isEmpty == false)
            || (p.sketchCracksData?.isEmpty == false)

        if !hasSketch {
            try await client.from("sketches").delete().eq("proposal_id", value: p.id.uuidString).execute()
            state.stored.sketchFingerprints[p.id] = fp
            return
        }

        let stem = "\(base)/sketch/\(p.id.uuidString.lowercased())"
        var drawingPath: String?
        if let ink = p.sketchData, !ink.isEmpty {
            drawingPath = "\(stem).pkdrawing"
            try await upload(drawingPath!, data: ink, contentType: "application/octet-stream")
        }
        var pngPath: String?
        if let png = Self.sketchPNG(p) {
            pngPath = "\(stem).png"
            try await upload(pngPath!, data: png, contentType: "image/png")
        }

        let row = SketchPayload(
            id: p.id, proposal_id: p.id, page_number: 1,
            drawing_path: drawingPath, png_path: pngPath,
            annotations: Self.json(p.sketchAnnotationsData),
            segments: Self.json(p.sketchSegmentsData),
            cracks: Self.json(p.sketchCracksData)
        )
        try await client.from("sketches").upsert(row, onConflict: "id").execute()
        state.stored.sketchFingerprints[p.id] = fp
    }

    private func pushSignatures(for p: Proposal, base: String) async throws {
        let customerName = p.job?.customer?.displayName ?? ""
        let parties: [(party: String, data: Data?, signedAt: Date?, name: String)] = [
            ("customer", p.customerSignatureData, p.customerSignedAt, customerName),
            ("sales_rep", p.salesSignatureData, p.salesSignedAt, p.salesSignedBy ?? ""),
        ]
        for entry in parties {
            guard let ink = entry.data, !ink.isEmpty else { continue }
            let key = "\(p.id.uuidString):\(entry.party)"
            guard !state.stored.uploadedSignatures.contains(key) else { continue }

            let drawingPath = "\(base)/signatures/\(entry.party).pkdrawing"
            try await upload(drawingPath, data: ink, contentType: "application/octet-stream")
            var pngPath: String?
            if let png = Self.drawingPNG(ink) {
                pngPath = "\(base)/signatures/\(entry.party).png"
                try await upload(pngPath!, data: png, contentType: "image/png")
            }

            let row = SignaturePayload(
                id: Self.signatureID(proposal: p.id, party: entry.party),
                proposal_id: p.id,
                party: entry.party,
                signer_name: entry.name,
                signed_at: ISO8601DateFormatter().string(from: entry.signedAt ?? Date()),
                drawing_path: drawingPath,
                png_path: pngPath
            )
            try await client.from("signatures").upsert(row, onConflict: "id").execute()
            state.stored.uploadedSignatures.insert(key)
            state.save()
        }
        if p.customerSignatureData != nil && p.salesSignatureData != nil {
            state.stored.lockedProposalIDs.insert(p.id)
        }
    }

    // MARK: - Download

    /// Brings down files added or changed on the website (or another iPad) for
    /// proposals that have no unsent edits here.
    func pullFiles(proposals: [UUID: Proposal], applied: Set<UUID>, in context: ModelContext) async throws {
        let photos: [CloudPhotoRow] = try await client.from("photos")
            .select("id, proposal_id, image_path, markup_drawing_path, caption, sort_order")
            .execute().value
        let sketches: [CloudSketchRow] = try await client.from("sketches")
            .select("id, proposal_id, drawing_path, annotations, segments, cracks")
            .execute().value
        let signatures: [CloudSignatureRow] = try await client.from("signatures")
            .select("id, proposal_id, party, signer_name, signed_at, drawing_path")
            .execute().value
        let documents: [CloudProposalDocumentRow] = try await client.from("proposal_documents")
            .select("id, proposal_id, title, file_path, sort_order")
            .execute().value

        // Photos
        var photosByProposal: [UUID: [CloudPhotoRow]] = [:]
        for row in photos {
            if let pid = row.proposal_id { photosByProposal[pid, default: []].append(row) }
        }
        for id in applied {
            guard let p = proposals[id] else { continue }
            let cloudRows = photosByProposal[id] ?? []
            let localByID = Dictionary(p.photos.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })

            for row in cloudRows {
                if let local = localByID[row.id] {
                    // Caption / order changed elsewhere, and not edited here since the last sync
                    if state.stored.photoFingerprints[row.id] == Self.photoFingerprint(local) {
                        local.caption = row.caption
                        local.sortOrder = row.sort_order
                        state.stored.photoFingerprints[row.id] = Self.photoFingerprint(local)
                    }
                    continue
                }
                guard let image = try? await client.storage.from("eco-files").download(path: row.image_path) else { continue }
                let photo = JobPhoto(id: row.id, imageData: image, caption: row.caption, sortOrder: row.sort_order, proposal: p)
                if let markupPath = row.markup_drawing_path {
                    photo.annotationData = try? await client.storage.from("eco-files").download(path: markupPath)
                }
                context.insert(photo)
                p.photos.append(photo)
                state.stored.uploadedPhotoImages.insert(row.id)
                state.stored.photoFingerprints[row.id] = Self.photoFingerprint(photo)
            }

            // Removed elsewhere (only photos this iPad already knew were in the cloud)
            let cloudIDs = Set(cloudRows.map(\.id))
            for photoID in Set(state.stored.proposalPhotoIDs[id] ?? []).subtracting(cloudIDs) {
                if let local = localByID[photoID] { context.delete(local) }
                state.stored.photoFingerprints[photoID] = nil
                state.stored.uploadedPhotoImages.remove(photoID)
            }
            // What this iPad now knows is in the cloud for this proposal
            state.stored.proposalPhotoIDs[id] = cloudRows.map(\.id).filter { photoID in p.photos.contains { $0.id == photoID } }
        }

        // Attached PDFs
        let docsByProposal = Dictionary(grouping: documents, by: \.proposal_id)
        for id in applied {
            guard let p = proposals[id] else { continue }
            let cloudRows = docsByProposal[id] ?? []
            let localByID = Dictionary(p.documents.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            for row in cloudRows {
                if let local = localByID[row.id] {
                    local.title = row.title
                    local.sortOrder = row.sort_order
                    state.stored.documentFingerprints[row.id] = Self.hash(Data("\(local.title)|\(local.sortOrder)".utf8))
                    continue
                }
                guard let pdf = try? await client.storage.from("eco-files").download(path: row.file_path) else { continue }
                let filename = (row.title.hasSuffix(".pdf") ? row.title : "\(row.title).pdf")
                let doc = ProposalDocument(id: row.id, title: row.title, filename: filename, pdfData: pdf, sortOrder: row.sort_order, proposal: p)
                context.insert(doc)
                p.documents.append(doc)
                state.stored.uploadedDocuments.insert(row.id)
                state.stored.documentFingerprints[row.id] = Self.hash(Data("\(doc.title)|\(doc.sortOrder)".utf8))
            }
            let cloudIDs = Set(cloudRows.map(\.id))
            for docID in Set(state.stored.proposalDocumentIDs[id] ?? []).subtracting(cloudIDs) {
                if let local = localByID[docID] { context.delete(local) }
                state.stored.documentFingerprints[docID] = nil
                state.stored.uploadedDocuments.remove(docID)
            }
            state.stored.proposalDocumentIDs[id] = cloudRows.map(\.id).filter { docID in p.documents.contains { $0.id == docID } }
        }

        // Sketches drawn on another iPad (only fills in a proposal that has no sketch here)
        for row in sketches where applied.contains(row.proposal_id) {
            guard let p = proposals[row.proposal_id], p.sketchData == nil, p.sketchAnnotationsData == nil,
                  p.sketchSegmentsData == nil, p.sketchCracksData == nil else { continue }
            if let path = row.drawing_path {
                p.sketchData = try? await client.storage.from("eco-files").download(path: path)
            }
            p.sketchAnnotationsData = Self.data(row.annotations)
            p.sketchSegmentsData = Self.data(row.segments)
            p.sketchCracksData = Self.data(row.cracks)
            state.stored.sketchFingerprints[p.id] = Self.sketchFingerprint(p)
        }

        // Signatures captured on another iPad
        for row in signatures {
            guard let pid = row.proposal_id, applied.contains(pid), let p = proposals[pid],
                  let path = row.drawing_path else { continue }
            let signedAt = ISO8601DateFormatter().date(from: row.signed_at)
                ?? Self.isoWithFraction.date(from: row.signed_at)
            switch row.party {
            case "customer" where p.customerSignatureData == nil:
                p.customerSignatureData = try? await client.storage.from("eco-files").download(path: path)
                p.customerSignedAt = signedAt
            case "sales_rep" where p.salesSignatureData == nil:
                p.salesSignatureData = try? await client.storage.from("eco-files").download(path: path)
                p.salesSignedAt = signedAt
                p.salesSignedBy = row.signer_name
            default:
                continue
            }
            state.stored.uploadedSignatures.insert("\(pid.uuidString):\(row.party)")
        }
    }

    // MARK: - Helpers

    private func upload(_ path: String, data: Data, contentType: String) async throws {
        _ = try await client.storage
            .from("eco-files")
            .upload(path, data: data, options: FileOptions(contentType: contentType, upsert: true))
    }

    private static let isoWithFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    static func photoFingerprint(_ photo: JobPhoto) -> String {
        var data = Data("\(photo.caption)|\(photo.sortOrder)|".utf8)
        data.append(photo.annotationData ?? Data())
        return hash(data)
    }

    static func sketchFingerprint(_ p: Proposal) -> String {
        var data = Data()
        for part in [p.sketchData, p.sketchAnnotationsData, p.sketchSegmentsData, p.sketchCracksData] {
            data.append(part ?? Data())
            data.append(0x7C)
        }
        return hash(data)
    }

    /// Same id for a given proposal + party on every device, so a re-upload updates instead of duplicating.
    static func signatureID(proposal: UUID, party: String) -> UUID {
        var bytes = Array(SHA256.hash(data: Data("\(proposal.uuidString)|\(party)".utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50   // version 5 style
        bytes[8] = (bytes[8] & 0x3F) | 0x80   // RFC 4122 variant
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }

    static func json(_ data: Data?) -> AnyJSON {
        guard let data, let value = try? JSONDecoder().decode(AnyJSON.self, from: data) else { return .array([]) }
        return value
    }

    static func data(_ json: AnyJSON?) -> Data? {
        guard let json else { return nil }
        if case .array(let items) = json, items.isEmpty { return nil }
        if case .null = json { return nil }
        return try? JSONEncoder().encode(json)
    }

    /// Photos shrink to 2000 px on the long edge (JPEG 80%) for fast uploads on cellular.
    static func jpegForUpload(_ data: Data) -> Data? {
        #if canImport(UIKit)
        guard let image = UIImage(data: data) else { return nil }
        let longEdge = max(image.size.width, image.size.height)
        let scale = min(1, 2000 / max(longEdge, 1))
        let size = CGSize(width: (image.size.width * scale).rounded(), height: (image.size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return resized.jpegData(compressionQuality: 0.8)
        #else
        return nil
        #endif
    }

    /// PNG of a PencilKit drawing (signature or photo markup), cropped to the ink.
    static func drawingPNG(_ data: Data) -> Data? {
        #if canImport(PencilKit) && os(iOS)
        guard let drawing = try? PKDrawing(data: data), !drawing.bounds.isEmpty else { return nil }
        return drawing.image(from: drawing.bounds, scale: 2).pngData()
        #else
        return nil
        #endif
    }

    /// PNG of the whole job sketch (ink, walls, cracks, notes on the grid), as the iPad shows it.
    static func sketchPNG(_ p: Proposal) -> Data? {
        #if canImport(UIKit)
        let view = SketchThumbnail(
            sketchData: p.sketchData,
            annotations: SketchAnnotationsCodec.decode(p.sketchAnnotationsData),
            segments: SketchGeometryCodec.decodeSegments(p.sketchSegmentsData),
            cracks: SketchGeometryCodec.decodeCracks(p.sketchCracksData)
        )
        .frame(width: 1200, height: 900)
        .background(Color.white)

        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        return renderer.uiImage?.pngData()
        #else
        return nil
        #endif
    }
}
