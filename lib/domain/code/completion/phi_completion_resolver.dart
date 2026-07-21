import '../../midi/midi_clip.dart';
import '../../midi/store/clip_document.dart';
import '../../project/entity_address.dart';
import '../../project/project_registry.dart';
import '../../project/registry_entity.dart';
import '../../project/registry_group.dart';
import '../../project/registry_node.dart';
import '../../voice/voice_definition.dart';
import 'phi_completion.dart';
import 'phi_completion_item.dart';
import 'phi_completion_item_kind.dart';
import 'phi_method_table.dart';

/// Turns the text left of the cursor into the registry-driven completion the
/// popup shows — no LSP, no Python analysis (design `docs/design/live-coding.md`
/// §6). Pure Dart: given the live [registry] and the static [methodTable], it
/// reads the same name tree the `phi` interpreter mirrors and returns the rows,
/// or `null` when the context is not a `phi` namespace (so plain Python typing
/// is never obstructed).
///
/// The three levels the design names:
/// - **Namespace** (`voice.`) → the entities and groups directly under that kind.
/// - **Group** (`clip.drums.`) → that group's members (groups nest).
/// - **Entity** (`voice.bells.`) → the static [methodTable] verbs (a leaf has no
///   registry children; its API is the `phi` library's method set).
///
/// Matching is a case-insensitive prefix on whatever partial identifier trails
/// the last dot, so `voice.be` narrows to `bells` without a fresh trigger.
class PhiCompletionResolver {
  PhiCompletionResolver(this.registry, {this.methodTable = phiMethodTable});

  /// The live registry — read fresh on every resolve, so a voice added
  /// mid-session shows up in the very next popup.
  final ProjectRegistry registry;

  /// The verbs offered one level past an entity — the checked-in [phiMethodTable]
  /// by default, injectable for tests.
  final List<String> methodTable;

  /// The eight dot-access namespaces `phi` mirrors (design §3). The first
  /// segment must be one of these or the popup never appears — plain Python
  /// identifiers (and dotted chains rooted elsewhere) stay untouched.
  static const Set<String> namespaces = <String>{
    'voice',
    'clip',
    'mix',
    'fx',
    'patch',
    'domain',
    'var',
    'state',
  };

  /// Resolves the completion at a cursor sitting immediately after
  /// [textBeforeCursor], or `null` for a non-`phi` context / no matches.
  PhiCompletion? resolve(String textBeforeCursor) {
    final chain = _trailingChain(textBeforeCursor);
    if (chain == null) return null; // no dotted chain under the cursor

    final parts = chain.split('.');
    final input = parts.last; // partial after the last dot ('' right after it)
    final segments = parts.sublist(0, parts.length - 1);
    if (segments.isEmpty || segments.any((s) => s.isEmpty)) return null;

    final namespace = segments.first;
    if (!namespaces.contains(namespace)) return null; // not a phi namespace

    final pathSegs = segments.sublist(1);
    final List<PhiCompletionItem> items;
    if (pathSegs.isEmpty) {
      // `voice.` — the namespace root's direct children.
      items = _childItems(registry.childrenOfKind(namespace), namespace, input);
    } else {
      final EntityAddress address;
      try {
        address = EntityAddress(kind: namespace, segments: pathSegs);
      } on FormatException {
        return null; // an ill-formed segment can't name anything
      }
      final group = registry.groupAt(address);
      if (group != null) {
        // `clip.drums.` — a group narrows to its members.
        items = _childItems(
          registry.childrenOfGroup(address),
          namespace,
          input,
        );
      } else if (registry.entityAt(address) != null) {
        // `voice.bells.` — a leaf offers the static method table.
        items = _methodItems(input);
      } else {
        return null; // path resolves to nothing — no popup
      }
    }

    if (items.isEmpty) return null;
    return PhiCompletion(input: input, items: items);
  }

  /// The maximal run of identifier/dot characters ending at the cursor, or
  /// `null` when it holds no dot (a bare identifier is not yet a `phi` trigger).
  String? _trailingChain(String text) {
    var i = text.length;
    while (i > 0 && _isChainChar(text.codeUnitAt(i - 1))) {
      i--;
    }
    final chain = text.substring(i);
    if (!chain.contains('.')) return null;
    return chain;
  }

  bool _isChainChar(int c) {
    return (c >= 0x61 && c <= 0x7A) || // a-z
        (c >= 0x41 && c <= 0x5A) || // A-Z
        (c >= 0x30 && c <= 0x39) || // 0-9
        c == 0x5F || // _
        c == 0x2E; // .
  }

  List<PhiCompletionItem> _childItems(
    List<RegistryNode> children,
    String namespace,
    String input,
  ) {
    final lower = input.toLowerCase();
    final items = <PhiCompletionItem>[];
    for (final node in children) {
      if (!node.name.toLowerCase().startsWith(lower)) continue;
      items.add(_itemFor(node, namespace));
    }
    return items;
  }

  PhiCompletionItem _itemFor(RegistryNode node, String namespace) {
    if (node is RegistryGroup) {
      return PhiCompletionItem(
        identifier: node.name,
        kind: PhiCompletionItemKind.group,
        namespace: namespace,
      );
    }
    final entity = node as RegistryEntity;
    return PhiCompletionItem(
      identifier: entity.name,
      kind: PhiCompletionItemKind.entity,
      namespace: namespace,
      colorToken: namespace == 'voice'
          ? _voiceColorToken(entity.payload)
          : null,
      bars: namespace == 'clip' ? _clipBars(entity.payload) : null,
    );
  }

  List<PhiCompletionItem> _methodItems(String input) {
    final lower = input.toLowerCase();
    return <PhiCompletionItem>[
      for (final name in methodTable)
        if (name.toLowerCase().startsWith(lower))
          PhiCompletionItem(
            identifier: name,
            kind: PhiCompletionItemKind.method,
          ),
    ];
  }

  /// A voice entity's colour token, from either its typed [VoiceDefinition] or
  /// its persisted map form. `null` when neither carries one.
  String? _voiceColorToken(Object? payload) {
    if (payload is VoiceDefinition) return payload.color;
    if (payload is Map) {
      final color = payload['color'];
      if (color is String) return color;
    }
    return null;
  }

  /// A clip entity's bar length, from its typed document/clip or its persisted
  /// map (the current `source.bars` form, or a legacy top-level `bars`).
  int? _clipBars(Object? payload) {
    if (payload is ClipDocument) return payload.source.bars;
    if (payload is MidiClip) return payload.bars;
    if (payload is Map) {
      final source = payload['source'];
      if (source is Map) {
        final bars = source['bars'];
        if (bars is num) return bars.toInt();
      }
      final bars = payload['bars'];
      if (bars is num) return bars.toInt();
    }
    return null;
  }
}
