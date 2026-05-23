import '../models/driver_model.dart';
import 'api_client.dart';

/// Wraps all driver-related API calls.
class DriverService {
  DriverService({required ApiClient apiClient}) : _apiClient = apiClient;

  final ApiClient _apiClient;

  /// Fetches the list of all drivers.
  Future<List<DriverModel>> fetchDrivers({required String token}) {
    return _apiClient.getDrivers(token: token);
  }

  /// Fetches a driver's current location.
  Future<DriverLocation?> getDriverLocation({
    required String token,
    required String driverId,
  }) {
    return _apiClient.getDriverLocation(token: token, driverId: driverId);
  }

  /// Updates a driver's location on the server.
  Future<void> updateDriverLocation({
    required String token,
    required String driverId,
    required double lat,
    required double lng,
    double heading = 0.0,
  }) {
    return _apiClient.updateDriverLocation(
      token: token,
      driverId: driverId,
      lat: lat,
      lng: lng,
      heading: heading,
    );
  }
}
