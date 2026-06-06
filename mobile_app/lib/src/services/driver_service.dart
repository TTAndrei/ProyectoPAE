import '../models/app_user.dart';
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

  /// Fetches KPI metrics for the authenticated driver.
  Future<DriverKpiModel> getMyDriverKpis({required String token}) {
    return _apiClient.getMyDriverKpis(token: token);
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

  /// Updates a driver's availability.
  Future<void> updateDriverAvailability({
    required String token,
    required String driverId,
    required bool isAvailable,
  }) {
    return _apiClient.updateDriverAvailability(
      token: token,
      driverId: driverId,
      isAvailable: isAvailable,
    );
  }

  /// Retrieves the active shift for the driver.
  Future<Map<String, dynamic>?> getActiveJornada({
    required String token,
  }) {
    return _apiClient.getActiveJornada(token: token);
  }

  /// Starts a new work shift.
  Future<Map<String, dynamic>> startJornada({
    required String token,
  }) {
    return _apiClient.startJornada(token: token);
  }

  /// Ends the active work shift.
  Future<Map<String, dynamic>> endJornada({
    required String token,
  }) {
    return _apiClient.endJornada(token: token);
  }

  /// Registers a new driver.
  Future<AppUser> registerDriver({
    required String token,
    required String username,
    required String password,
    required String name,
  }) {
    return _apiClient.registerDriver(
      token: token,
      username: username,
      password: password,
      name: name,
    );
  }
}
