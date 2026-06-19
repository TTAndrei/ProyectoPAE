import '../models/driver_model.dart';
import '../models/simulation_model.dart';
import 'api_client.dart';

class SimulationService {
  SimulationService({required ApiClient apiClient}) : _apiClient = apiClient;

  final ApiClient _apiClient;

  Future<SimulationStatus> startRoute20({required String token}) {
    return _apiClient.startRoute20Simulation(token: token);
  }

  Future<SimulationStatus> fetchRoute20Status({required String token}) {
    return _apiClient.getRoute20SimulationStatus(token: token);
  }

  Future<DriverKpiModel> fetchRoute20Kpis({required String token}) {
    return _apiClient.getRoute20SimulationKpis(token: token);
  }

  Future<SimulationStatus> resetRoute20({required String token}) {
    return _apiClient.resetRoute20Simulation(token: token);
  }

  Future<SimulationStatus> startRerouting({required String token}) {
    return _apiClient.startReroutingSimulation(token: token);
  }

  Future<SimulationStatus> fetchReroutingStatus({required String token}) {
    return _apiClient.getReroutingSimulationStatus(token: token);
  }

  Future<DriverKpiModel> fetchReroutingKpis({required String token}) {
    return _apiClient.getReroutingSimulationKpis(token: token);
  }

  Future<SimulationStatus> resetRerouting({required String token}) {
    return _apiClient.resetReroutingSimulation(token: token);
  }
}
