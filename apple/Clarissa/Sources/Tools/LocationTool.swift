import Foundation
import CoreLocation
import MapKit

// MARK: - Typed Arguments

/// Typed arguments for LocationTool using Codable
struct LocationArguments: Codable {
    let includeAddress: Bool?
    let accuracy: String?
}

/// Helper class for CLLocationManager delegate - must be used from MainActor
@MainActor
private final class LocationHelper: NSObject, CLLocationManagerDelegate {
    let locationManager = CLLocationManager()
    private var locationContinuation: CheckedContinuation<CLLocation, Error>?
    private var authorizationContinuation: CheckedContinuation<CLAuthorizationStatus, Never>?
    private var isWaitingForAuthorization = false

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func setAccuracy(_ accuracy: String) {
        switch accuracy {
        case "best":
            locationManager.desiredAccuracy = kCLLocationAccuracyBest
        case "high":
            locationManager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        case "medium":
            locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        case "low":
            locationManager.desiredAccuracy = kCLLocationAccuracyKilometer
        default:
            locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        }
    }

    /// Request location with proper continuation handling
    func requestLocation() async throws -> CLLocation {
        return try await withCheckedThrowingContinuation { continuation in
            self.locationContinuation = continuation
            self.locationManager.requestLocation()
        }
    }

    /// Request authorization and wait for user response
    func requestAuthorizationAndWait() async -> CLAuthorizationStatus {
        let currentStatus = locationManager.authorizationStatus

        // If already determined, return immediately
        guard currentStatus == .notDetermined else {
            return currentStatus
        }

        // Mark that we're waiting so we know to resume the continuation
        isWaitingForAuthorization = true

        return await withCheckedContinuation { continuation in
            self.authorizationContinuation = continuation
            self.locationManager.requestWhenInUseAuthorization()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            // Atomically check and nil to prevent double resumption
            if let continuation = self.locationContinuation {
                self.locationContinuation = nil
                continuation.resume(returning: location)
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            // Atomically check and nil to prevent double resumption
            if let continuation = self.locationContinuation {
                self.locationContinuation = nil
                continuation.resume(throwing: error)
            }
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            // Only resume if we're actively waiting for authorization
            guard self.isWaitingForAuthorization else { return }
            self.isWaitingForAuthorization = false
            // Atomically check and nil to prevent double resumption
            if let continuation = self.authorizationContinuation {
                self.authorizationContinuation = nil
                continuation.resume(returning: status)
            }
        }
    }
}

/// Actor to hold the MainActor-isolated LocationHelper
private actor LocationHelperHolder {
    private var helper: LocationHelper?

    private func getOrCreateHelper() async -> LocationHelper {
        if let existing = helper {
            return existing
        }
        let newHelper = await MainActor.run { LocationHelper() }
        helper = newHelper
        return newHelper
    }

    func setAccuracy(_ accuracy: String) async {
        let h = await getOrCreateHelper()
        await h.setAccuracy(accuracy)
    }

    func requestAuthorizationAndWait() async -> CLAuthorizationStatus {
        let h = await getOrCreateHelper()
        return await h.requestAuthorizationAndWait()
    }

    func requestLocation() async throws -> CLLocation {
        let h = await getOrCreateHelper()
        return try await h.requestLocation()
    }
}

/// Tool for getting current location
final class LocationTool: ClarissaTool, @unchecked Sendable {
    let name = "location"
    let description = "Get the user's current location. Returns coordinates and address."
    let priority = ToolPriority.extended
    let requiresConfirmation = true

    // Lazily initialize the helper so that unit tests which only touch
    // static properties (and don't actually request location) don't
    // instantiate CLLocationManager in the SPM test environment.
    private lazy var helperHolder = LocationHelperHolder()

    var parametersSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "includeAddress": [
                    "type": "boolean",
                    "description": "Include reverse geocoded address (default: true)"
                ],
                "accuracy": [
                    "type": "string",
                    "enum": ["best", "high", "medium", "low"],
                    "description": "Location accuracy level (default: medium)"
                ]
            ]
        ]
    }

    /// Execute the location tool.
    ///
    /// **Input (arguments JSON):**
    /// - `includeAddress: Bool?` (optional) – whether to include a reverse
    ///   geocoded address object in the response. Defaults to `true`.
    /// - `accuracy: String?` (optional) – one of `"best"`, `"high"`,
    ///   `"medium"`, or `"low"`. Defaults to `"medium"`.
    ///
    /// **Output (JSON string):**
    /// - `latitude: Double`
    /// - `longitude: Double`
    /// - `altitude: Double`
    /// - `horizontalAccuracy: Double`
    /// - `timestamp: String` (ISO‑8601)
    /// - `address: Object` (optional, present when `includeAddress` is true)
    ///   - `formatted: String` – primary human‑friendly address
    ///   - `fullAddress: String?` – full postal address
    ///   - `shortAddress: String?` – concise address (for display)
    ///   - `name: String?` – place or point‑of‑interest name
    /// - `addressError: String` (optional) – present if reverse geocoding
    ///   fails; core location fields are still returned.
    func execute(arguments: String) async throws -> String {
        guard let data = arguments.data(using: .utf8) else {
            throw ToolError.invalidArguments("Invalid argument encoding")
        }

        // Decode using typed arguments with defaults for optional fields
        let args = (try? JSONDecoder().decode(LocationArguments.self, from: data)) ?? LocationArguments(includeAddress: nil, accuracy: nil)
        let includeAddress = args.includeAddress ?? true
        let accuracy = args.accuracy ?? "medium"

        // Set accuracy
        await helperHolder.setAccuracy(accuracy)

        // Request authorization and wait if needed
        let status = await helperHolder.requestAuthorizationAndWait()

        // Check authorization status
        switch status {
        case .denied, .restricted:
            throw ToolError.notAvailable("Location access denied. Please enable in Settings.")
        case .notDetermined:
            throw ToolError.notAvailable("Location authorization not granted.")
        case .authorizedWhenInUse, .authorizedAlways:
            break
        @unknown default:
            break
        }

        // Get location
        let location = try await helperHolder.requestLocation()

        var response: [String: Any] = [
            "latitude": location.coordinate.latitude,
            "longitude": location.coordinate.longitude,
            "altitude": location.altitude,
            "horizontalAccuracy": location.horizontalAccuracy,
            "timestamp": ISO8601DateFormatter().string(from: location.timestamp)
        ]

        // Reverse geocode if requested
        if includeAddress {
            do {
                let address = try await reverseGeocode(location: location)
                response["address"] = address
            } catch {
                response["addressError"] = error.localizedDescription
            }
        }

        let responseData = try JSONSerialization.data(withJSONObject: response)
        return String(data: responseData, encoding: .utf8) ?? "{}"
    }

    /// Reverse geocode a CLLocation into a structured address dictionary.
    ///
    /// On iOS and macOS we use the modern MapKit geocoding APIs to avoid
    /// deprecated CoreLocation geocoding types. Other platforms fall back
    /// to `CLGeocoder` for now.
    private func reverseGeocode(location: CLLocation) async throws -> [String: Any] {
        #if os(macOS) || os(iOS)
        // Use MapKit's reverse geocoding APIs so we avoid deprecated
        // CoreLocation geocoding and get a richer MKAddress payload.
        guard let request = MKReverseGeocodingRequest(location: location) else {
            throw ToolError.executionFailed("No address found")
        }
        let items = try await request.mapItems
        guard let item = items.first else {
            throw ToolError.executionFailed("No address found")
        }
        return formatMapItem(item)
        #else
        // Fallback for any non-iOS/macOS platforms where MapKit reverse
        // geocoding may not be available yet.
        let geocoder = CLGeocoder()
        let placemarks = try await geocoder.reverseGeocodeLocation(location)
        guard let placemark = placemarks.first else {
            throw ToolError.executionFailed("No address found")
        }
        return formatPlacemark(placemark)
        #endif
    }

    /// Format a MapKit geocoding result into a JSON-friendly address
    /// dictionary using the new MKAddress APIs.
    private func formatMapItem(_ item: MKMapItem) -> [String: Any] {
        var address: [String: Any] = [:]

        if let name = item.name {
            address["name"] = name
        }

        if let mkAddress = item.address {
            address["fullAddress"] = mkAddress.fullAddress
            if let short = mkAddress.shortAddress {
                address["shortAddress"] = short
                address["formatted"] = short
            } else {
                address["formatted"] = mkAddress.fullAddress
            }
        }

        // Fallback: if we still don't have a formatted string, use the
        // map item's name as a last resort.
        if address["formatted"] == nil, let name = item.name {
            address["formatted"] = name
        }

        return address
    }

    private func formatPlacemark(_ placemark: CLPlacemark) -> [String: Any] {
        var address: [String: Any] = [:]

        if let name = placemark.name { address["name"] = name }
        if let street = placemark.thoroughfare { address["street"] = street }
        if let subStreet = placemark.subThoroughfare { address["streetNumber"] = subStreet }
        if let city = placemark.locality { address["city"] = city }
        if let state = placemark.administrativeArea { address["state"] = state }
        if let postalCode = placemark.postalCode { address["postalCode"] = postalCode }
        if let country = placemark.country { address["country"] = country }
        if let isoCountry = placemark.isoCountryCode { address["countryCode"] = isoCountry }

        var components: [String] = []
        if let subStreet = placemark.subThoroughfare, let street = placemark.thoroughfare {
            components.append("\(subStreet) \(street)")
        } else if let street = placemark.thoroughfare {
            components.append(street)
        }
        if let city = placemark.locality { components.append(city) }
        if let state = placemark.administrativeArea { components.append(state) }
        if let postalCode = placemark.postalCode { components.append(postalCode) }

        address["formatted"] = components.joined(separator: ", ")
        return address
    }
}

