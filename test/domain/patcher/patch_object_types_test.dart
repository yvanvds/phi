import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/patcher/patch_object_types.dart';
import 'package:yse/yse.dart';

/// Drift guard for the pure-Dart mirror of the engine type ids (issue #483):
/// a renamed or removed engine object must fail here, not silently unregister
/// a node body on the patcher surface.
void main() {
  test('every mirrored id is a registered engine object', () {
    for (final type in PatchObjectTypes.all) {
      expect(Obj.all, contains(type), reason: '$type is not in Obj.all');
    }
  });

  test('each mirror equals the Obj constant it is named after', () {
    expect(PatchObjectTypes.dSine, Obj.dSine);
    expect(PatchObjectTypes.dDac, Obj.dDac);
    expect(PatchObjectTypes.gSlider, Obj.gSlider);
    expect(PatchObjectTypes.gToggle, Obj.gToggle);
    expect(PatchObjectTypes.gButton, Obj.gButton);
    expect(PatchObjectTypes.gFloat, Obj.gFloat);
    expect(PatchObjectTypes.gInt, Obj.gInt);
    expect(PatchObjectTypes.gMessage, Obj.gMessage);
    expect(PatchObjectTypes.gDial, Obj.gDial);
    expect(PatchObjectTypes.gIncdec, Obj.gIncdec);
    expect(PatchObjectTypes.gLed, Obj.gLed);
    expect(PatchObjectTypes.gTextbutton, Obj.gTextbutton);
    expect(PatchObjectTypes.gTextedit, Obj.gTextedit);
    expect(PatchObjectTypes.gList, Obj.gList);
    expect(PatchObjectTypes.gUmenu, Obj.gUmenu);
    expect(PatchObjectTypes.gRadiogroup, Obj.gRadiogroup);
    expect(PatchObjectTypes.gTab, Obj.gTab);
    expect(PatchObjectTypes.gRslider, Obj.gRslider);
    expect(PatchObjectTypes.gXyslider, Obj.gXyslider);
    expect(PatchObjectTypes.gMultislider, Obj.gMultislider);
    expect(PatchObjectTypes.gKslider, Obj.gKslider);
    expect(PatchObjectTypes.gNslider, Obj.gNslider);
    expect(PatchObjectTypes.gMatrixctrl, Obj.gMatrixctrl);
    expect(PatchObjectTypes.gFunction, Obj.gFunction);
  });

  test('the list holds each id exactly once', () {
    expect(
      PatchObjectTypes.all.toSet(),
      hasLength(PatchObjectTypes.all.length),
    );
  });
}
