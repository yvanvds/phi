import 'dart:io';

import 'package:flutter/material.dart';

import 'design/theme.dart';
import 'domain/midi/custom_transform_registry.dart';
import 'domain/project/app_settings/app_settings_controller.dart';
import 'domain/project/app_settings/real_app_settings_store.dart';
import 'domain/project/lifecycle/project_controller.dart';
import 'domain/project/lifecycle/project_directory_picker.dart';
import 'domain/project/registry_seed.dart';
import 'domain/project/store/real_journal_store.dart';
import 'domain/project/store/real_project_store.dart';
import 'domain/project/store/registry_codecs.dart';
import 'domain/session/session_state.dart';
import 'engine/bridge/code_evaluator.dart';
import 'engine/engine.dart';
import 'shell/commands/command_registry.dart';
import 'shell/layout/shell_layout_controller.dart';
import 'shell/project/file_selector_project_directory_picker.dart';
import 'shell/workstation.dart';
import 'surfaces/midi/midi_file_io.dart';

class PhiApp extends StatefulWidget {
  const PhiApp({
    super.key,
    this.engine,
    this.session,
    this.projectController,
    this.directoryPicker,
    this.autoStartProject = false,
    this.midiFileIo,
    this.codeEvaluator,
    this.customTransformRegistry,
    this.layoutController,
    this.commandRegistry,
  });

  /// Optional engine override — tests inject a fake-backed engine here so
  /// the production `PhiEngine.production()` (and its libyse.dll load)
  /// never runs in a test process.
  final PhiEngine? engine;

  /// Optional session override. Tests can inject a pre-seeded state.
  final SessionState? session;

  /// Optional project-lifecycle controller. `null` lets the app build a
  /// production controller over the real project/journal stores and
  /// `%APPDATA%/phi/` settings; tests inject one wired to fakes.
  final ProjectController? projectController;

  /// Optional folder picker for the project menu. `null` uses the real
  /// `file_selector` dialogs; tests inject a fake that returns canned paths.
  final ProjectDirectoryPicker? directoryPicker;

  /// Whether to restore the last project (and offer recovery) on launch. The
  /// real entry point (`main`) sets this; tests opt in deliberately.
  final bool autoStartProject;

  /// Optional file-dialog backend for the MIDI surface's SMF import/export.
  /// `null` in production (the surface uses the real `file_selector` backend);
  /// tests inject a fake to drive the flow without native dialogs.
  final MidiFileIo? midiFileIo;

  /// Optional Code-surface evaluator override. `null` in production (the shell
  /// builds a `NoOpCodeEvaluator`); tests inject a `FakeCodeEvaluator` to drive
  /// the live-coding → custom-transform handshake (issue #38).
  final CodeEvaluator? codeEvaluator;

  /// Optional shared custom-transform registry. Injected alongside
  /// [codeEvaluator] so a fake evaluator registers into the same instance the
  /// MIDI `+` menu reads (issue #38).
  final CustomTransformRegistry? customTransformRegistry;

  /// Optional workspace layout controller (design `docs/design/shell-layout.md`
  /// §2). `null` lets the workstation seed its own (one pane, Mix open); tests
  /// inject one to drive dock moves and assert surface state survives.
  final ShellLayoutController? layoutController;

  /// Optional command registry (design `docs/design/shell-layout.md` §4). `null`
  /// lets the workstation build and own one seeded with the shell commands; tests
  /// inject one to inspect what the shell registered.
  final CommandRegistry? commandRegistry;

  @override
  State<PhiApp> createState() => _PhiAppState();
}

class _PhiAppState extends State<PhiApp> {
  late final PhiEngine _engine;
  late final bool _ownsEngine;
  late final SessionState _session;
  late final bool _ownsSession;
  late final ProjectController _projectController;
  late final bool _ownsProjectController;
  late final ProjectDirectoryPicker _directoryPicker;

  /// The single settings owner backing a self-built [_projectController]. Held
  /// only so it can be disposed with the controller; `null` when a controller
  /// was injected (the test owns its own settings controller).
  AppSettingsController? _ownedAppSettings;

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

    final injectedController = widget.projectController;
    if (injectedController != null) {
      _projectController = injectedController;
      _ownsProjectController = false;
    } else {
      final appSettings = AppSettingsController(RealAppSettingsStore());
      _ownedAppSettings = appSettings;
      _projectController = ProjectController(
        session: _session,
        settings: appSettings,
        storeFactory: (directory) => RealProjectStore(
          Directory(directory),
          codecs: defaultEntityCodecs(),
          groupPayloadKinds: defaultGroupPayloadKinds(),
        ),
        journalStoreFactory: (directory) =>
            RealJournalStore(Directory(directory)),
        seedRegistry: seedDefaultProject,
      );
      _ownsProjectController = true;
    }
    _directoryPicker =
        widget.directoryPicker ?? const FileSelectorProjectDirectoryPicker();
  }

  @override
  void dispose() {
    // The controller listens to the session, so dispose it before the session.
    if (_ownsProjectController) {
      _projectController.dispose();
      // The project controller listens to the settings owner; dispose it after.
      _ownedAppSettings?.dispose();
    }
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
      home: Workstation(
        engine: _engine,
        session: _session,
        projectController: _projectController,
        directoryPicker: _directoryPicker,
        autoStartProject: widget.autoStartProject,
        midiFileIo: widget.midiFileIo,
        codeEvaluator: widget.codeEvaluator,
        customTransformRegistry: widget.customTransformRegistry,
        layoutController: widget.layoutController,
        commandRegistry: widget.commandRegistry,
      ),
    );
  }
}
