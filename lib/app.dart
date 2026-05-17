import 'package:flutter/material.dart';

import 'design/theme.dart';
import 'domain/session/session_state.dart';
import 'engine/engine.dart';
import 'shell/workstation.dart';

class PhiApp extends StatefulWidget {
  const PhiApp({super.key, this.engine, this.session});

  /// Optional engine override — tests inject a fake-backed engine here so
  /// the production `PhiEngine.production()` (and its libyse.dll load)
  /// never runs in a test process.
  final PhiEngine? engine;

  /// Optional session override. Tests can inject a pre-seeded state.
  final SessionState? session;

  @override
  State<PhiApp> createState() => _PhiAppState();
}

class _PhiAppState extends State<PhiApp> {
  late final PhiEngine _engine;
  late final bool _ownsEngine;
  late final SessionState _session;
  late final bool _ownsSession;

  @override
  void initState() {
    super.initState();
    final injectedEngine = widget.engine;
    if (injectedEngine != null) {
      _engine = injectedEngine;
      _ownsEngine = false;
    } else {
      _engine = PhiEngine.production();
      _ownsEngine = true;
    }
    _engine.start();

    final injectedSession = widget.session;
    if (injectedSession != null) {
      _session = injectedSession;
      _ownsSession = false;
    } else {
      _session = SessionState();
      _ownsSession = true;
    }
  }

  @override
  void dispose() {
    if (_ownsEngine) {
      _engine.stop();
    }
    if (_ownsSession) {
      _session.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Phi',
      debugShowCheckedModeBanner: false,
      theme: buildPhiTheme(),
      home: Workstation(engine: _engine, session: _session),
    );
  }
}
