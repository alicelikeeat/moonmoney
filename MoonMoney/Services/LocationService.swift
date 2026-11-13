import CoreLocation
import Foundation

/// One-shot "where am I" for tagging a record with a place.
@MainActor
enum LocationService {
    struct Place {
        let latitude: Double
        let longitude: Double
        let name: String
    }

    /// Returns nil if permission is denied or no fix arrives within 8 seconds.
    static func currentPlace() async -> Place? {
        let session = CLServiceSession(authorization: .whenInUse)
        defer { session.invalidate() }

        let location: CLLocation? = await withTaskGroup(of: CLLocation?.self) { group in
            group.addTask {
                do {
                    for try await update in CLLocationUpdate.liveUpdates() {
                        if update.authorizationDenied || update.authorizationDeniedGlobally { return nil }
                        if let location = update.location, location.horizontalAccuracy < 1000 { return location }
                    }
                } catch {}
                return nil
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(8))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
        guard let location else { return nil }
        let name = await placeName(for: location)
        return Place(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude, name: name)
    }

    static func placeName(for location: CLLocation) async -> String {
        guard let placemark = try? await CLGeocoder().reverseGeocodeLocation(location).first else { return "" }
        return placemark.areasOfInterest?.first
            ?? placemark.name
            ?? [placemark.subLocality, placemark.thoroughfare].compactMap { $0 }.joined()
    }
}
