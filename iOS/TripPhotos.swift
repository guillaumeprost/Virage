import CoreLocation
import Photos
import SwiftUI

/// A photo taken during a trip, pinned where it was taken.
struct TripPhoto: Identifiable {
    let id: String
    let coordinate: CLLocationCoordinate2D
    let date: Date
    let thumbnail: UIImage
}

/// Finds the photos taken during a ride: nothing to do on the road, Virage looks them up afterwards by time.
enum TripPhotos {
    /// Photos taken just before setting off or just after arriving belong to the ride too.
    static let margin: TimeInterval = 10 * 60
    static let maximum = 60
    static let thumbnailSize = CGSize(width: 160, height: 160)

    static var status: PHAuthorizationStatus {
        PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }

    static var isAuthorized: Bool {
        status == .authorized || status == .limited
    }

    static func requestAccess() async {
        _ = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
    }

    /// Where a photo has no location, it goes where the rider was when it was taken.
    @MainActor
    static func load(from start: Date, to end: Date, track: [TrackPoint]) async -> [TripPhoto] {
        guard isAuthorized else { return [] }
        let options = PHFetchOptions()
        options.predicate = NSPredicate(
            format: "creationDate >= %@ AND creationDate <= %@ AND mediaType == %d",
            start.addingTimeInterval(-margin) as NSDate,
            end.addingTimeInterval(margin) as NSDate,
            PHAssetMediaType.image.rawValue
        )
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        options.fetchLimit = maximum
        let result = PHAsset.fetchAssets(with: options)
        var assets: [PHAsset] = []
        result.enumerateObjects { asset, _, _ in assets.append(asset) }

        var photos: [TripPhoto] = []
        for asset in assets {
            let date = asset.creationDate ?? start
            guard let coordinate = asset.location?.coordinate ?? position(at: date, on: track),
                  let thumbnail = await image(for: asset, size: thumbnailSize) else { continue }
            photos.append(TripPhoto(id: asset.localIdentifier, coordinate: coordinate, date: date, thumbnail: thumbnail))
        }
        return photos
    }

    /// The track point closest in time.
    static func position(at date: Date, on track: [TrackPoint]) -> CLLocationCoordinate2D? {
        track.min { abs($0.timestamp.timeIntervalSince(date)) < abs($1.timestamp.timeIntervalSince(date)) }?.coordinate
    }

    @MainActor
    static func image(forIdentifier identifier: String, size: CGSize) async -> UIImage? {
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil).firstObject else { return nil }
        return await image(for: asset, size: size)
    }

    /// One image, at full quality: the handler then runs exactly once.
    @MainActor
    private static func image(for asset: PHAsset, size: CGSize) async -> UIImage? {
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        return await withCheckedContinuation { continuation in
            PHImageManager.default().requestImage(for: asset, targetSize: size, contentMode: .aspectFill, options: options) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }
}

/// A photo of the trip, full screen.
struct TripPhotoViewer: View {
    let photo: TripPhoto
    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?

    var body: some View {
        NavigationStack {
            Image(uiImage: image ?? photo.thumbnail)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
                .navigationTitle(photo.date.formatted(date: .omitted, time: .shortened))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("OK") { dismiss() }
                    }
                }
                .task {
                    image = await TripPhotos.image(forIdentifier: photo.id, size: CGSize(width: 2000, height: 2000))
                }
        }
        // White title and button over the black backdrop, whatever the app's appearance.
        .preferredColorScheme(.dark)
    }
}
