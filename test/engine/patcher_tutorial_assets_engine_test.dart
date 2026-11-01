import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/patcher/patch_type_name.dart';
import 'package:phi/domain/patcher/tutorial/patch_tutorial.dart';
import 'package:phi/domain/patcher/tutorial/tutorial_catalog.dart';
import 'package:phi/domain/patcher/tutorial/tutorial_slug.dart';
import 'package:phi/engine/bridge/real_patcher_gateway.dart';
import 'package:yse/yse.dart';

/// The **bundled tutorials** against the real engine, headless (issue #489):
/// every index entry points at a file that exists, every indexed and covered
/// type is in the engine's catalogue, and every tutorial's dump `parseJson`s
/// into a patch with objects in it. A non-failing report lists the object
/// types that still have no tutorial.
///
/// This is the test a content issue (#490–#510) leans on: add the file, add
/// the index lines, and this proves the tutorial loads on the engine Phi ships.
void main() {
  late RealPatcherGateway gateway;
  late Set<String> engineTypes;
  var engineUp = false;

  final index = TutorialCatalog.fromJson(
    (jsonDecode(File(TutorialCatalog.indexPath).readAsStringSync()) as Map)
        .cast<String, Object?>(),
  );

  PatchTutorial load(String slug) => PatchTutorial.fromJson(
    (jsonDecode(
      File(TutorialCatalog.assetPathFor(slug)).readAsStringSync(),
    ) as Map).cast<String, Object?>(),
  );

  setUpAll(() {
    System.instance
      ..requestedSampleRate = 48000
      ..initOffline();
    engineUp = true;
    gateway = RealPatcherGateway();
    engineTypes = {for (final d in gateway.objectTypes()) d.type};
  });

  tearDownAll(() {
    if (!engineUp) return;
    gateway.disposeAll();
    System.instance.close();
  });

  test('the index is not empty', () {
    expect(index.isEmpty, isFalse);
  });

  test('every index entry points at an existing tutorial file', () {
    for (final slug in index.slugs) {
      expect(
        File(TutorialCatalog.assetPathFor(slug)).existsSync(),
        isTrue,
        reason: 'index names "$slug" but its file is missing',
      );
    }
  });

  test('every tutorial file in the folder is indexed', () {
    final files = Directory(TutorialCatalog.assetDir)
        .listSync()
        .whereType<File>()
        .map((f) => f.uri.pathSegments.last)
        .where((n) => n.endsWith(TutorialCatalog.extension))
        .map((n) => n.substring(0, n.length - TutorialCatalog.extension.length))
        .toSet();
    expect(files, index.slugs);
  });

  test('every indexed and covered type exists in the engine catalogue', () {
    for (final type in index.types) {
      expect(engineTypes, contains(type), reason: 'index entry $type');
    }
    for (final slug in index.slugs) {
      final tutorial = load(slug);
      expect(tutorial.covers, isNotEmpty, reason: '$slug covers nothing');
      for (final type in tutorial.covers) {
        expect(engineTypes, contains(type), reason: '$slug covers $type');
        expect(
          index.tutorialFor(type),
          slug,
          reason: '$slug covers $type but the index does not point there',
        );
      }
    }
  });

  test('a single-type tutorial is named by the slug rule', () {
    for (final slug in index.slugs) {
      final types = index.typesFor(slug);
      if (types.length != 1) continue;
      expect(
        slug,
        TutorialSlug.of(types.single, knownTypes: engineTypes),
        reason: '${types.single} is stored as "$slug"',
      );
    }
  });

  test('every tutorial parses on the real engine and has a title note', () {
    for (final slug in index.slugs) {
      final tutorial = load(slug);
      final inst = gateway.createInstance();
      gateway.parseJson(inst, jsonEncode(tutorial.payload.dump));
      final graph = gateway.enumerate(inst);
      expect(graph.objects, isNotEmpty, reason: '$slug parsed to nothing');
      expect(
        graph.objects.any((o) => PatchTypeName.isNote(o.type)),
        isTrue,
        reason: '$slug has no note explaining it',
      );
      gateway.disposeInstance(inst);
    }
  });

  test('the metro tutorial sets itself up on load', () {
    final tutorial = load('metro');
    final inst = gateway.createInstance();
    gateway.parseJson(inst, jsonEncode(tutorial.payload.dump));
    final graph = gateway.enumerate(inst);
    final numbers = [
      for (final o in graph.objects)
        if (o.type == '.i') o.handleId,
    ];
    // `.loadmess 500` fills the interval box when the patch loads.
    expect(
      numbers.map((id) => gateway.guiValue(inst, id)),
      contains(startsWith('500')),
    );
    gateway.disposeInstance(inst);
  });

  test('report: object types with no tutorial yet', () {
    final missing = [
      for (final t in engineTypes.toList()..sort())
        if (!index.hasTutorial(t) && t != 'patcher') t,
    ];
    // ignore: avoid_print
    print(
      'tutorials: ${index.types.length} of ${engineTypes.length} types '
      'covered; without one: ${missing.join(' ')}',
    );
  });
}
