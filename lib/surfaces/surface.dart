import 'package:flutter/widgets.dart';

/// Marker interface for the six performer surfaces. Each concrete surface
/// (Scene, Patcher, Code, State, MIDI, Mix) implements this so the
/// workstation chrome can swap them generically.
abstract class Surface extends StatelessWidget {
  const Surface({super.key});
}
