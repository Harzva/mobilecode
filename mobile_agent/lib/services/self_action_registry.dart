import 'self_invocation_service.dart';

/// Legacy self-action registry kept as a compile-time compatibility surface.
///
/// The old implementation exposed a broad set of in-process editor, terminal,
/// GitHub, AI, file, and settings actions. That path is now suspended in favor
/// of the newer typed harness and CLI Hub permission model, so this registry no
/// longer wires raw actions into the agent surface.
class SelfActionRegistry {
  const SelfActionRegistry._();

  static void registerAll(SelfInvocationService service) {
    service.registerActionHandler('self_use.disabled', _DisabledSelfAction());
  }
}

class _DisabledSelfAction implements SelfActionHandler {
  @override
  Future<dynamic> execute(Map<String, dynamic> params) async {
    return const <String, dynamic>{
      'status': 'disabled',
      'reason': 'Legacy self-use actions are suspended. Use typed harness tasks.',
    };
  }
}
