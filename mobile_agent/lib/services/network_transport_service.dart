import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

enum NetworkTransportState { available, offline, unknown }

class NetworkTransportSnapshot {
  const NetworkTransportSnapshot({
    required this.state,
    required this.checkedAt,
    this.source = 'os_connectivity',
  });

  final NetworkTransportState state;
  final DateTime checkedAt;
  final String source;

  bool get definitelyOffline => state == NetworkTransportState.offline;

  Map<String, Object> get evidenceMetadata => {
        'state': state.name,
        'source': source,
        // A network interface does not prove internet reachability. Cloud
        // transports must still handle timeouts and connection failures.
        'internetReachabilityProven': false,
        'networkIdentifiersOmitted': true,
      };
}

abstract interface class NetworkTransportSource {
  Future<List<ConnectivityResult>> checkConnectivity();
}

class ConnectivityPlusTransportSource implements NetworkTransportSource {
  ConnectivityPlusTransportSource({Connectivity? connectivity})
      : _connectivity = connectivity ?? Connectivity();

  final Connectivity _connectivity;

  @override
  Future<List<ConnectivityResult>> checkConnectivity() =>
      _connectivity.checkConnectivity();
}

/// Reads the current OS network-transport state immediately before routing.
///
/// This is intentionally not an internet probe: it stores no SSID, interface,
/// address, host, or portal data. A definitive `none` result is enough to avoid
/// opening the first cloud request while airplane mode is active. Available or
/// unknown transport still relies on the existing guarded cloud-failure path.
class NetworkTransportService {
  NetworkTransportService({NetworkTransportSource? source})
      : _source = source ?? ConnectivityPlusTransportSource();

  static final NetworkTransportService instance = NetworkTransportService();

  final NetworkTransportSource _source;

  Future<NetworkTransportSnapshot> snapshot({
    Duration timeout = const Duration(seconds: 2),
  }) async {
    try {
      final results = await _source.checkConnectivity().timeout(timeout);
      if (results.isEmpty) {
        return NetworkTransportSnapshot(
          state: NetworkTransportState.unknown,
          checkedAt: DateTime.now(),
        );
      }
      final hasTransport =
          results.any((result) => result != ConnectivityResult.none);
      return NetworkTransportSnapshot(
        state: hasTransport
            ? NetworkTransportState.available
            : NetworkTransportState.offline,
        checkedAt: DateTime.now(),
      );
    } on Object {
      return NetworkTransportSnapshot(
        state: NetworkTransportState.unknown,
        checkedAt: DateTime.now(),
      );
    }
  }
}
