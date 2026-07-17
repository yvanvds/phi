import 'name_validator.dart';

/// Turns a free-form display name into a valid registry address segment.
///
/// Entity addresses are strict `snake_case` ([NameValidator]) so they double as
/// Python attributes and file names, but display names are not: a channel called
/// `ch 1` or a clip called `phrase A` must still get an address. This slugger
/// lowercases, folds every run of disallowed characters to a single `_`, trims
/// stray underscores, prefixes a leading digit, truncates to
/// [NameValidator.maxLength], and appends `_` to anything that would collide with
/// a Python keyword or Windows device name — so its output always passes
/// [NameValidator]. An empty or fully-stripped name falls back to [fallback].
///
/// It intentionally does **not** guarantee uniqueness among siblings; that is a
/// tree constraint the caller resolves (e.g. by suffixing `_2`).
abstract final class NameSlug {
  /// The slug of [name], guaranteed valid per [NameValidator]. Uses [fallback]
  /// (itself slugged if needed) when [name] has no usable characters.
  static String of(String name, {String fallback = 'item'}) {
    var slug = name.toLowerCase().replaceAll(RegExp('[^a-z0-9]+'), '_');
    slug = slug.replaceAll(RegExp('_+'), '_');
    slug = _trimUnderscores(slug);
    if (slug.isEmpty) {
      return name == fallback ? 'item' : of(fallback, fallback: 'item');
    }
    if (RegExp('^[0-9]').hasMatch(slug)) slug = '_$slug';
    if (slug.length > NameValidator.maxLength) {
      slug = _trimUnderscores(slug.substring(0, NameValidator.maxLength));
      if (slug.isEmpty) slug = 'item';
    }
    // A keyword or reserved device name is still a well-formed token — nudge it
    // out of the way with a trailing underscore (still <= maxLength given the
    // truncation above leaves room, but guard anyway).
    if (!NameValidator.isValid(slug)) {
      final bumped = '${slug.substring(0, slug.length.clamp(0, 63))}_';
      slug = NameValidator.isValid(bumped) ? bumped : 'item';
    }
    return slug;
  }

  static String _trimUnderscores(String value) {
    var start = 0;
    var end = value.length;
    while (start < end && value[start] == '_') {
      start++;
    }
    while (end > start && value[end - 1] == '_') {
      end--;
    }
    return value.substring(start, end);
  }
}
