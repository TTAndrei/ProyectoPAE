// mobile_app/test/models_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pae_mobile/src/models/app_user.dart';
import 'package:pae_mobile/src/models/order_model.dart';
import 'package:pae_mobile/src/models/driver_model.dart';
import 'package:pae_mobile/src/models/analytics_models.dart';
import 'package:pae_mobile/src/models/simulation_model.dart';

void main() {
  group('AppUser Model', () {
    test('Create AppUser from JSON', () {
      final json = {
        'id': 'user1',
        'username': 'driver1',
        'role': 'repartidor',
        'name': 'Juan',
      };

      final user = AppUser.fromJson(json);

      expect(user.id, 'user1');
      expect(user.role, 'repartidor');
    });

    test('Convert AppUser to JSON', () {
      const user = AppUser(
        id: 'user1',
        username: 'driver1',
        role: 'repartidor',
        name: 'Juan',
      );

      final json = user.toJson();

      expect(json['id'], 'user1');
      expect(json['role'], 'repartidor');
    });
  });

  group('OrderModel', () {
    test('Parse order from JSON with all fields', () {
      final json = {
        'id': 'order1',
        'type': 'delivery',
        'address': '123 Main St',
        'lat': 40.7128,
        'lng': -74.0060,
        'status': 'pending',
        'created_at': '2026-05-15T10:00:00Z',
        'updated_at': '2026-05-15T10:00:00Z',
      };

      final order = OrderModel.fromJson(json);

      expect(order.id, 'order1');
      expect(order.isPending, true);
      expect(order.isAssigned, false);
    });

    test('Order status getters work correctly', () {
      final order = OrderModel(
        id: 'o1',
        type: 'pickup',
        address: 'Place',
        lat: 0,
        lng: 0,
        status: 'in_progress',
        createdAt: 'now',
        updatedAt: 'now',
      );

      expect(order.isInProgress, true);
      expect(order.isPending, false);
    });
  });

  group('DriverModel', () {
    test('Format location with shortLocation getter', () {
      const driver = DriverModel(
        id: 'd1',
        username: 'driver1',
        name: 'Juan',
        lat: 40.4168,
        lng: -3.7038,
      );

      expect(driver.shortLocation, contains('40.4168'));
      expect(driver.shortLocation, contains('-3.7038'));
    });

    test('Handle null location gracefully', () {
      const driver = DriverModel(
        id: 'd1',
        username: 'driver1',
        name: 'Juan',
      );

      expect(driver.shortLocation, 'No location');
    });

    test('Parse load efficiency KPIs from driver JSON', () {
      final driver = DriverModel.fromJson({
        'id': 'd1',
        'username': 'driver1',
        'name': 'Juan',
        'load_efficiency_ratio': 0.5,
        'load_efficiency_percent': 50.0,
        'loaded_distance_km': 1.25,
        'total_distance_km': 2.5,
        'active_order_count': 2,
        'pending_confirmation_count': 1,
        'completed_order_count': 3,
        'average_load_packages': 1.4,
        'load_weighted_distance': 3.5,
        'average_insertion_detour_minutes': 2.5,
        'packages_per_km': 1.2,
        'insertion_acceptance_rate': 0.75,
        'accepted_insertion_count': 3,
        'rejected_insertion_count': 1,
        'target_load_efficiency_ratio': 0.75,
        'meets_load_efficiency_target': false,
        'measurement_note': 'test',
      });

      expect(driver.kpis?.loadEfficiencyLabel, '50.0%');
      expect(driver.kpis?.loadDistanceLabel, '1.25 / 2.50 km');
      expect(driver.kpis?.activeOrderCount, 2);
      expect(driver.kpis?.averageLoadPackages, 1.4);
      expect(driver.kpis?.packagesPerKm, 1.2);
      expect(driver.kpis?.insertionAcceptanceRate, 0.75);
      expect(driver.kpis?.meetsLoadEfficiencyTarget, false);
    });

    test('copyWith updates location and preserves KPIs', () {
      const kpis = DriverKpiModel(
        driverId: 'driver-1',
        loadEfficiencyRatio: 0.5,
        loadEfficiencyPercent: 50,
        loadedDistanceKm: 1,
        totalDistanceKm: 2,
        activeOrderCount: 1,
        pendingConfirmationCount: 0,
        completedOrderCount: 2,
        averageLoadPackages: 1,
        loadWeightedDistance: 1,
        averageInsertionDetourMinutes: 0,
        packagesPerKm: 1,
        insertionAcceptanceRate: 1,
        acceptedInsertionCount: 1,
        rejectedInsertionCount: 0,
        targetLoadEfficiencyRatio: 0.75,
        meetsLoadEfficiencyTarget: false,
        measurementNote: 'test',
      );
      const driver = DriverModel(
        id: 'driver-1',
        username: 'driver1',
        name: 'Carlos',
        lat: 41,
        lng: 2,
        kpis: kpis,
      );

      final updated = driver.copyWith(lat: 41.5, lng: 2.5, heading: 90);

      expect(updated.lat, 41.5);
      expect(updated.lng, 2.5);
      expect(updated.heading, 90);
      expect(updated.kpis, same(kpis));
      expect(updated.name, 'Carlos');
    });
  });

  group('AnalyticsModels', () {
    test('Parse fleet and driver KPI extras from analytics JSON', () {
      final summary = FleetSummaryModel.fromJson({
        'total_distance_km': 10.0,
        'loaded_distance_km': 6.0,
        'average_load_efficiency_percent': 60.0,
        'total_active_orders': 2,
        'total_pending_confirmations': 1,
        'total_completed_orders': 4,
        'average_load_packages': 1.7,
        'average_insertion_detour_minutes': 3.2,
        'packages_per_km': 0.4,
        'insertion_acceptance_rate': 0.8,
      });

      final driver = DriverPerformanceModel.fromJson({
        'driver_id': 'driver-1',
        'name': 'Driver Uno',
        'load_efficiency_ratio': 0.6,
        'load_efficiency_percent': 60.0,
        'loaded_distance_km': 6.0,
        'total_distance_km': 10.0,
        'active_order_count': 2,
        'pending_confirmation_count': 1,
        'completed_order_count': 4,
        'average_load_packages': 1.7,
        'average_insertion_detour_minutes': 3.2,
        'packages_per_km': 0.4,
        'insertion_acceptance_rate': 0.8,
        'meets_load_efficiency_target': false,
      });

      expect(summary.averageLoadPackages, 1.7);
      expect(summary.packagesPerKm, 0.4);
      expect(driver.averageInsertionDetourMinutes, 3.2);
      expect(driver.insertionAcceptanceRate, 0.8);
    });
  });

  group('SimulationStatus', () {
    test('Parse route 20 status with KPIs and current stop', () {
      final status = SimulationStatus.fromJson({
        'id': 'route-20-demo',
        'status': 'running',
        'current_index': 7,
        'total_stops': 20,
        'driver_id': 'driver-1',
        'current_stop': {
          'id': 'sim-route20-08',
          'type': 'pickup',
          'address': 'Malgrat de Mar',
          'lat': 41.6469,
          'lng': 2.7408,
          'status': 'in_progress',
          'created_at': '2026-06-19T10:00:00Z',
          'updated_at': '2026-06-19T10:00:00Z',
        },
        'kpis': {
          'driver_id': 'driver-1',
          'load_efficiency_ratio': 0.75,
          'load_efficiency_percent': 75.0,
          'loaded_distance_km': 12.0,
          'total_distance_km': 16.0,
          'active_order_count': 13,
          'pending_confirmation_count': 0,
          'completed_order_count': 7,
        },
      });

      expect(status.isRunning, true);
      expect(status.progressLabel, '7/20');
      expect(status.progressValue, 0.35);
      expect(status.currentStop?.id, 'sim-route20-08');
      expect(status.kpis.loadEfficiencyLabel, '75.0%');
    });

    test('Parse rerouting comparison and events', () {
      final status = SimulationStatus.fromJson({
        'id': 'rerouting-demo',
        'status': 'running',
        'current_index': 1,
        'total_stops': 4,
        'driver_id': 'driver-1',
        'comparison': {
          'dynamic_distance_km': 3.2,
          'fifo_distance_km': 5.0,
          'savings_km': 1.8,
          'savings_percent': 36.0,
          'dynamic_order_ids': ['a', 'b'],
          'fifo_order_ids': ['b', 'a'],
          'completed_order_count': 1,
          'active_order_count': 3,
        },
        'events': [
          {
            'type': 'reroute',
            'order_id': 'new-1',
            'message': 'Nueva recogida insertada',
            'previous_order_ids': ['a'],
            'new_order_ids': ['new-1', 'a'],
          }
        ],
        'kpis': {'driver_id': 'driver-1'},
      });

      expect(status.comparison?.fifoDistanceKm, 5.0);
      expect(status.comparison?.savingsPercent, 36.0);
      expect(status.comparison?.dynamicOrderIds, ['a', 'b']);
      expect(status.events.single.orderId, 'new-1');
      expect(status.events.single.newOrderIds, ['new-1', 'a']);
    });
  });
}
