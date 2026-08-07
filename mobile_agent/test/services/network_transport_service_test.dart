import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/services/network_transport_service.dart';

void main() {
  test('none is a definitive offline signal before cloud routing', () async {
    final service = NetworkTransportService(
      source: const _FakeSource([ConnectivityResult.none]),
    );

    final snapshot = await service.snapshot();

    expect(snapshot.state, NetworkTransportState.offline);
    expect(snapshot.definitelyOffline, isTrue);
    expect(snapshot.evidenceMetadata['internetReachabilityProven'], isFalse);
  });

  test('any active transport keeps guarded cloud routing available', () async {
    final service = NetworkTransportService(
      source: const _FakeSource(
        [ConnectivityResult.wifi, ConnectivityResult.vpn],
      ),
    );

    final snapshot = await service.snapshot();

    expect(snapshot.state, NetworkTransportState.available);
    expect(snapshot.definitelyOffline, isFalse);
  });

  test(
      'empty and failing probes stay unknown instead of inventing reachability',
      () async {
    final empty = await NetworkTransportService(
      source: const _FakeSource([]),
    ).snapshot();
    final failed = await NetworkTransportService(
      source: const _ThrowingSource(),
    ).snapshot();

    expect(empty.state, NetworkTransportState.unknown);
    expect(failed.state, NetworkTransportState.unknown);
  });

  test('evidence never exposes transport types or network identifiers',
      () async {
    final snapshot = await NetworkTransportService(
      source: const _FakeSource([ConnectivityResult.wifi]),
    ).snapshot();
    final encoded = snapshot.evidenceMetadata.toString().toLowerCase();

    expect(encoded, isNot(contains('wifi')));
    expect(encoded, isNot(contains('ssid')));
    expect(encoded, isNot(contains('address')));
    expect(snapshot.evidenceMetadata['networkIdentifiersOmitted'], isTrue);
  });
}

class _FakeSource implements NetworkTransportSource {
  const _FakeSource(this.results);

  final List<ConnectivityResult> results;

  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => results;
}

class _ThrowingSource implements NetworkTransportSource {
  const _ThrowingSource();

  @override
  Future<List<ConnectivityResult>> checkConnectivity() async =>
      throw StateError('probe unavailable');
}
