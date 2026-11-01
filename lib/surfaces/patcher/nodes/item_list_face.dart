/// How an `ItemListNodeBody` draws its items — the one thing that tells a
/// `.umenu`, a `.radiogroup` and a `.tab` apart (issue #471).
enum ItemListFace {
  /// A drop-down (`.umenu`).
  menu,

  /// A column of radio buttons or check boxes (`.radiogroup`).
  radio,

  /// A row of tabs (`.tab`).
  tabs,
}
