import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/project/entity_address.dart';
import 'package:phi/engine/state/domain_tempo_control_port.dart';

/// The real `domain tempo` leg of the control plane (issue #334): a decoded
/// `phi.ctl.domain.<d>.tempo` set forwards to the engine's live domain-tempo
/// override — the same seam the state-slice application applies through.
void main() {
  test('setTempo forwards the domain address and bpm to the apply seam', () {
    final applied = <(EntityAddress, double)>[];
    final port = DomainTempoControlPort(
      (domain, bpm) => applied.add((domain, bpm)),
    );

    port.setTempo(EntityAddress.parse('domain.drum'), 124);
    port.setTempo(EntityAddress.parse('domain.pad'), 90.5);

    expect(applied, [
      (EntityAddress.parse('domain.drum'), 124.0),
      (EntityAddress.parse('domain.pad'), 90.5),
    ]);
  });
}
