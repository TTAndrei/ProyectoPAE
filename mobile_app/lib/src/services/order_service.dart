import '../models/order_model.dart';
import 'api_client.dart';

export 'api_client.dart' show GeocodeCandidate;

/// Wraps all order-related API calls.
class OrderService {
  OrderService({required ApiClient apiClient}) : _apiClient = apiClient;

  final ApiClient _apiClient;

  /// Fetches all orders.
  Future<List<OrderModel>> fetchOrders({required String token}) {
    return _apiClient.getOrders(token: token);
  }

  /// Creates a new order.
  Future<OrderModel> createOrder({
    required String token,
    required CreateOrderInput input,
  }) {
    return _apiClient.createOrder(token: token, input: input);
  }

  /// Assigns an order to a driver.
  Future<AssignOrderResult> assignOrder({
    required String token,
    required String orderId,
    required String driverId,
  }) {
    return _apiClient.assignOrder(
      token: token,
      orderId: orderId,
      driverId: driverId,
    );
  }

  /// Responds to a pickup notification (accept / reject).
  Future<RespondOrderResult> respondOrder({
    required String token,
    required String orderId,
    required bool accepted,
  }) {
    return _apiClient.respondOrder(
      token: token,
      orderId: orderId,
      accepted: accepted,
    );
  }

  /// Updates the status of an order (e.g. 'completed').
  Future<OrderModel> updateOrderStatus({
    required String token,
    required String orderId,
    required String status,
  }) {
    return _apiClient.updateOrderStatus(
      token: token,
      orderId: orderId,
      status: status,
    );
  }

  /// Geocodes an address and returns candidate locations.
  Future<List<GeocodeCandidate>> geocodeAddressCandidates({
    required String address,
    int maxResults = 5,
  }) {
    return _apiClient.geocodeAddressCandidates(
      address: address,
      maxResults: maxResults,
    );
  }
}
