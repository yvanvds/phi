import 'package:flutter/material.dart';

import 'design/theme.dart';
import 'engine/engine.dart';
import 'shell/workstation.dart';

class PhiApp extends StatefulWidget {
  const PhiApp({super.key, this.engine});

  /// Optional engine override — tests inject a fake-backed engine here so
  /// the production `PhiEngine.production()` (and its libyse.dll load)
  /// never runs in a test process.
  final PhiEngine? engine;

  @override
  State<PhiApp> createState() => _PhiAppState();
}

class _PhiAppState extends State<PhiApp> {
  late final PhiEngine _engine;
  late final bool _ownsEngine;

  @override
  void initState() {
    super.initState();
    final injected = widget.engine;
    if (injected != null) {
      _engine = injected;
      _ownsEngine = false;
    } else {
      _engine = PhiEngine.production();
      _ownsEngine = true;
    }
    _engine.start();
  }

  @override
  void dispose() {
    if (_ownsEngine) {
      _engine.stop();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Phi',
      debugShowCheckedModeBanner: false,
      theme: buildPhiTheme(),
      home: Workstation(engine: _engine),
    );
  }
}
