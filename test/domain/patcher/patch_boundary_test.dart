import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/patcher/patch_boundary.dart';
import 'package:phi/domain/patcher/patch_port.dart';
import 'package:yse/yse.dart';

void main() {
  test('names the container and the four boundary objects', () {
    expect(PatchBoundary.isSubpatch(Obj.patcher), isTrue);
    expect(PatchBoundary.isSubpatch(Obj.dSine), isFalse);
    expect(PatchBoundary.isInlet(Obj.gInlet), isTrue);
    expect(PatchBoundary.isInlet(Obj.dInlet), isTrue);
    expect(PatchBoundary.isOutlet(Obj.gOutlet), isTrue);
    expect(PatchBoundary.isOutlet(Obj.dOutlet), isTrue);
    expect(PatchBoundary.isBoundary(Obj.patcher), isFalse);
    expect(PatchBoundary.boxSideOf(Obj.dInlet), PatchPortSide.input);
    expect(PatchBoundary.boxSideOf(Obj.gOutlet), PatchPortSide.output);
    expect(PatchBoundary.boxSideOf(Obj.dSine), isNull);
  });

  test('the pin index is the first argument, 0 when absent or bad', () {
    expect(PatchBoundary.indexOf('3'), 3);
    expect(PatchBoundary.indexOf(' 2  extra'), 2);
    expect(PatchBoundary.indexOf(''), 0);
    expect(PatchBoundary.indexOf('x'), 0);
    expect(PatchBoundary.indexOf('-1'), 0);
  });

  test('only the pin facing the parent is the hidden one', () {
    expect(
      PatchBoundary.isParentFacing(Obj.dInlet, PatchPortSide.input, 0),
      isTrue,
    );
    expect(
      PatchBoundary.isParentFacing(Obj.dInlet, PatchPortSide.output, 0),
      isFalse,
    );
    expect(
      PatchBoundary.isParentFacing(Obj.gOutlet, PatchPortSide.output, 0),
      isTrue,
    );
    expect(
      PatchBoundary.isParentFacing(Obj.gOutlet, PatchPortSide.input, 0),
      isFalse,
    );
    expect(
      PatchBoundary.isParentFacing(Obj.dSine, PatchPortSide.input, 0),
      isFalse,
    );
  });
}
