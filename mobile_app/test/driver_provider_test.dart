import 'package:flutter_test/flutter_test.dart';
import 'package:pae_mobile/src/models/app_user.dart';
import 'package:pae_mobile/src/models/driver_model.dart';
import 'package:pae_mobile/src/models/order_model.dart';
import 'package:pae_mobile/src/providers/driver_provider.dart';
import 'package:pae_mobile/src/services/api_client.dart';
import 'package:pae_mobile/src/services/driver_service.dart';
import 'package:pae_mobile/src/services/route_service.dart';

void main() {
  test('DriverProvider does not emit duplicate assigned notifications',
      () async {
    final routeService = _FakeRouteService(
      plan: DriverRoutePlan(
        orders: [_assignedOrder('order-1')],
        totalMinutes: 1,
        totalDistanceKm: 1,
        routeGeometry: const [],
        legMinutes: const [],
      ),
    );
    final provider = DriverProvider(
      driverService: _FakeDriverService(),
      routeService: routeService,
      token: 'token',
      apiBaseUrl: 'http://localhost:8000',
      user: const AppUser(
        id: 'driver-1',
        username: 'driver1',
        role: 'repartidor',
        name: 'Driver Uno',
      ),
      autoConnect: false,
      enablePolling: false,
    );

    final received = <AssignOrderResult>[];
    final sub = provider.incomingOrderNotifications.listen(received.add);

    await Future<void>.delayed(Duration.zero);
    await provider.loadData();
    await Future<void>.delayed(Duration.zero);

    expect(received.map((item) => item.order.id), ['order-1']);

    await sub.cancel();
    provider.dispose();
  });
}

OrderModel _assignedOrder(String id) {
  return OrderModel(
    id: id,
    type: 'pickup',
    address: 'Calle Test',
    lat: 41.0,
    lng: 2.0,
    status: 'assigned',
    createdAt: 'now',
    updatedAt: 'now',
    assignedDriverId: 'driver-1',
    estimatedExtraMinutes: 1,
  );
}

class _FakeDriverService extends DriverService {
  _FakeDriverService() : super(apiClient: ApiClient(baseUrl: 'http://test'));

  @override
  Future<DriverLocation?> getDriverLocation({
    required String token,
    required String driverId,
  }) async {
    return DriverLocation(
      driverId: driverId,
      lat: 41.0,
      lng: 2.0,
      heading: 0,
    );
  }

  @override
  Future<Map<String, dynamic>?> getActiveJornada(
      {required String token}) async {
    return null;
  }

  @override
  Future<DriverKpiModel> getMyDriverKpis({required String token}) async {
    return const DriverKpiModel(
      driverId: 'driver-1',
      loadEfficiencyRatio: 0.5,
      loadEfficiencyPercent: 50,
      loadedDistanceKm: 1,
      totalDistanceKm: 2,
      activeOrderCount: 1,
      pendingConfirmationCount: 1,
      completedOrderCount: 0,
      averageLoadPackages: 1,
      loadWeightedDistance: 1,
      averageInsertionDetourMinutes: 2,
      packagesPerKm: 0,
      insertionAcceptanceRate: 0.5,
      acceptedInsertionCount: 1,
      rejectedInsertionCount: 1,
      targetLoadEfficiencyRatio: 0.75,
      meetsLoadEfficiencyTarget: false,
      measurementNote: 'test',
    );
  }
}

class _FakeRouteService extends RouteService {
  _FakeRouteService({required this.plan})
      : super(apiClient: ApiClient(baseUrl: 'http://test'));

  final DriverRoutePlan plan;

  @override
  Future<DriverRoutePlan> getRoutePlan({
    required String token,
    required String driverId,
  }) async {
    return plan;
  }
}
