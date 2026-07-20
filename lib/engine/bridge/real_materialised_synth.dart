import 'package:yse/yse.dart';

import '../../domain/synth/fm_synth.dart';
import '../../domain/synth/lfo_type.dart' as dom_lfo;
import '../../domain/synth/sampler_synth.dart';
import '../../domain/synth/sine_synth.dart';
import '../../domain/synth/synth_definition.dart';
import '../../domain/synth/synth_kind.dart';
import '../../domain/synth/va_synth.dart';
import '../../domain/synth/va_waveform.dart' as dom_wave;
import 'materialised_synth.dart';
import 'synth_materialisation.dart';

/// Resolves a mix-bus channel id (the opaque id `YseGateway.createChannel`
/// hands out) to the live `package:yse` [Channel], or `null` to route through
/// the master bus. Supplied by the engine, which owns the channel map — the
/// bridge stays the only place a real [Channel] is handled.
typedef MixBusResolver = Channel? Function(int busChannelId);

/// Resolves a project-relative asset ref (e.g. `assets/rhodes.syx`) to an
/// absolute filesystem path the engine loaders can open. Defaults to the
/// identity so a caller that already passes absolute paths needs nothing.
typedef AssetPathResolver = String Function(String ref);

/// Production [MaterialisedSynth] backed by `package:yse` (design
/// `docs/design/racks-and-voices.md` §3–§4).
///
/// Owns one engine [Synth] (its voice pool) and, once bound, one [Sound] that
/// renders it into a mix bus. Every branch wraps the confirmed yse calls:
/// `addSineVoices` / `addVaVoices` + the `setVa*` panel, `addFmVoices` +
/// `Dx7Bank.load` + `setFmPatch` + `setFm*` overrides, `addSamplerVoices` over
/// `SfzInstrument.load` / `SfzInstrument.fromSample`, and `Sound.fromSynth` for
/// the bus binding.
///
/// **Channel note.** Only `addSineVoices` accepts a MIDI channel today, so a
/// sine pool registers on [channel] directly; VA/FM/sampler pools are built
/// omni until `dart-yse` grows a channel parameter on their `add*Voices`
/// (dart-yse#41 — the whole-synth `ClipTransport.connectSynth` still routes
/// correctly, the per-channel *filter* is what waits).
class RealMaterialisedSynth implements MaterialisedSynth {
  /// Builds and materialises the voice pool for [definition] straight away.
  RealMaterialisedSynth(
    this._definition, {
    required this.channel,
    required MixBusResolver busResolver,
    AssetPathResolver? resolveAsset,
  }) : _busResolver = busResolver,
       _resolveAsset = resolveAsset ?? _identity {
    _synth = _buildSynth(_definition);
  }

  static String _identity(String ref) => ref;

  final MixBusResolver _busResolver;
  final AssetPathResolver _resolveAsset;

  @override
  final int channel;

  SynthDefinition _definition;
  late Synth _synth;
  Sound? _sound;
  int? _boundBus;

  @override
  SynthKind get kind => _definition.kind;

  @override
  SynthDefinition get definition => _definition;

  @override
  int? get boundBus => _boundBus;

  /// The live engine synth, for sibling bridge code that wires it to a
  /// transport (`ClipTransport.connectSynth`). Not part of the yse-free surface.
  Synth get synth => _synth;

  @override
  void applyDefinition(SynthDefinition next) {
    if (SynthMaterialisation.needsRematerialise(_definition, next)) {
      _rematerialise(next);
    } else {
      _applyParams(_synth, next);
    }
    _definition = next;
  }

  @override
  void bindToBus(int? busChannelId) {
    _boundBus = busChannelId;
    final bus = busChannelId == null ? null : _busResolver(busChannelId);
    final sound = _sound;
    if (sound == null) {
      _sound = Sound.fromSynth(_synth, channel: bus)..play();
    } else {
      sound.moveTo(bus ?? Channel.master);
    }
  }

  @override
  void noteOn(int note, {double velocity = 0.8}) =>
      _synth.noteOn(note, channel: channel, velocity: velocity);

  @override
  void noteOff(int note) => _synth.noteOff(note, channel: channel);

  @override
  void dispose() {
    // Sound before synth: the audio thread renders the synth's voices *through*
    // the sound, so the sound must be gone first.
    _sound?.dispose();
    _sound = null;
    _synth.dispose();
  }

  // ─── materialisation ────────────────────────────────────────────────────────

  Synth _buildSynth(SynthDefinition def) {
    final synth = Synth();
    switch (def.kind) {
      case SynthKind.sine:
        // Only the sine pool can register on a specific channel today.
        synth.addSineVoices((def as SineSynth).voiceCount, channel: channel);
      case SynthKind.va:
        // TODO(dart-yse#41): register on `channel` once addVaVoices takes it.
        synth.addVaVoices((def as VaSynth).voiceCount);
        _applyVa(synth, def);
      case SynthKind.fm:
        // TODO(dart-yse#41): register on `channel` once addFmVoices takes it.
        synth.addFmVoices((def as FmSynth).voiceCount);
        _applyFm(synth, def);
      case SynthKind.sampler:
        // TODO(dart-yse#41): register on `channel` once addSamplerVoices takes it.
        _addSampler(synth, def as SamplerSynth);
    }
    return synth;
  }

  void _rematerialise(SynthDefinition next) {
    final hadSound = _sound != null;
    final bus = _boundBus;
    _sound?.dispose();
    _sound = null;
    _synth.dispose();
    _synth = _buildSynth(next);
    if (hadSound) {
      _sound = Sound.fromSynth(
        _synth,
        channel: bus == null ? null : _busResolver(bus),
      )..play();
    }
  }

  /// Re-apply the params of an edited definition that did **not** need a
  /// rebuild — VA panel setters and FM patch/override setters. Sine and sampler
  /// never reach here (any change to them re-materialises).
  void _applyParams(Synth synth, SynthDefinition def) {
    switch (def.kind) {
      case SynthKind.va:
        _applyVa(synth, def as VaSynth);
      case SynthKind.fm:
        _applyFm(synth, def as FmSynth);
      case SynthKind.sine:
      case SynthKind.sampler:
        break;
    }
  }

  void _applyVa(Synth synth, VaSynth d) {
    for (var i = 0; i < d.oscillators.length && i < 3; i++) {
      final o = d.oscillators[i];
      synth.setVaOscWave(i, _waveform(o.wave));
      synth.setVaOscDetune(i, o.detune);
      synth.setVaOscLevel(i, o.level);
      synth.setVaOscPulseWidth(i, o.pulseWidth);
    }
    synth.setVaWavetablePosition(d.wavetablePosition);
    synth.setVaCutoff(d.filter.cutoff);
    synth.setVaResonance(d.filter.resonance);
    synth.setVaKeyTracking(d.filter.keyTracking);
    synth.setVaFilterEnvAmount(d.filter.envAmount);
    synth.setVaFilterVelAmount(d.filter.velAmount);
    synth.setVaAmpAttack(d.ampEnvelope.attack);
    synth.setVaAmpDecay(d.ampEnvelope.decay);
    synth.setVaAmpSustain(d.ampEnvelope.sustain);
    synth.setVaAmpRelease(d.ampEnvelope.release);
    synth.setVaAmpVelAmount(d.ampVelAmount);
    synth.setVaFilterAttack(d.filterEnvelope.attack);
    synth.setVaFilterDecay(d.filterEnvelope.decay);
    synth.setVaFilterSustain(d.filterEnvelope.sustain);
    synth.setVaFilterRelease(d.filterEnvelope.release);
    synth.setVaLfoType(_lfoType(d.lfo.type));
    synth.setVaLfoRate(d.lfo.rate);
    synth.setVaLfoToPitch(d.lfo.toPitch);
    synth.setVaLfoToCutoff(d.lfo.toCutoff);
    synth.setVaLfoToWavetable(d.lfo.toWavetable);
    synth.setVaGain(d.gain);
  }

  void _applyFm(Synth synth, FmSynth d) {
    final bankAsset = d.bankAsset;
    if (bankAsset != null) {
      Dx7Bank? bank;
      try {
        bank = Dx7Bank.load(_resolveAsset(bankAsset));
        synth.setFmPatch(bank, d.patchIndex);
      } on YseException {
        // Unreadable / bad bank — keep the built-in test patch rather than
        // crash; the racks editor surfaces the load failure to the performer.
      } finally {
        bank?.dispose();
      }
    }
    if (d.algorithm != null) synth.setFmAlgorithm(d.algorithm!);
    if (d.feedback != null) synth.setFmFeedback(d.feedback!);
    if (d.transpose != null) {
      // Domain transpose is signed semitones (0 = none); DX7 is 0..48 centred
      // at 24.
      synth.setFmTranspose((24 + d.transpose!).clamp(0, 48));
    }
    for (final op in d.operators) {
      synth.setFmOpEnabled(op.op, op.enabled);
      synth.setFmOpOutputLevel(op.op, op.outputLevel);
      synth.setFmOpFreqCoarse(op.op, op.freqCoarse);
      synth.setFmOpFreqFine(op.op, op.freqFine);
      synth.setFmOpDetune(op.op, op.detune);
    }
  }

  void _addSampler(Synth synth, SamplerSynth d) {
    SfzInstrument? instrument;
    try {
      final sfz = d.sfzAsset;
      final recipe = d.recipe;
      if (sfz != null) {
        instrument = SfzInstrument.load(_resolveAsset(sfz));
      } else if (recipe != null) {
        instrument = SfzInstrument.fromSample(
          _resolveAsset(recipe.file),
          root: recipe.root,
          low: recipe.low,
          high: recipe.high,
          attack: recipe.attack,
          release: recipe.release,
        );
      }
      if (instrument != null) {
        synth.addSamplerVoices(instrument, d.voiceCount);
      }
      // else: an empty sampler — silent until the editor names a source.
    } on YseException {
      // Missing / unreadable instrument — leaves the pool voiceless (silent)
      // rather than crashing; the editor surfaces the failure.
    } finally {
      instrument?.dispose();
    }
  }

  // Both enums mirror the engine's by name (documented on each), so map by name
  // with a small switch to stay robust to future additions on either side.
  VaWaveform _waveform(dom_wave.VaWaveform w) => switch (w) {
    dom_wave.VaWaveform.saw => VaWaveform.saw,
    dom_wave.VaWaveform.pulse => VaWaveform.pulse,
    dom_wave.VaWaveform.triangle => VaWaveform.triangle,
    dom_wave.VaWaveform.sine => VaWaveform.sine,
    dom_wave.VaWaveform.noise => VaWaveform.noise,
    dom_wave.VaWaveform.wavetable => VaWaveform.wavetable,
  };

  LfoType _lfoType(dom_lfo.LfoType t) => switch (t) {
    dom_lfo.LfoType.none => LfoType.none,
    dom_lfo.LfoType.saw => LfoType.saw,
    dom_lfo.LfoType.sawReversed => LfoType.sawReversed,
    dom_lfo.LfoType.triangle => LfoType.triangle,
    dom_lfo.LfoType.sine => LfoType.sine,
    dom_lfo.LfoType.square => LfoType.square,
    dom_lfo.LfoType.random => LfoType.random,
  };
}
