import 'dart:ffi' as ffi;
import 'dart:typed_data';

/// What a native GTK window shows on screen, read back from the window
/// system (Linux only) — the pixels the engine actually presented, not the
/// Flutter layer tree.
///
/// `gdk_pixbuf_get_from_window` copies a mapped window's contents from the X
/// server, so on Xvfb it sees exactly what the window put on the display. The
/// result is in physical pixels: the window's size times its GDK scale.
class LinuxWindowPixels {
  LinuxWindowPixels._(this.rgba, this.width, this.height);

  /// Row-major RGBA, 8 bits per channel.
  final Uint8List rgba;

  final int width;
  final int height;

  /// The colour at ([x], [y]) as 0xAARRGGBB, or null outside the window.
  int? at(int x, int y) {
    if (x < 0 || y < 0 || x >= width || y >= height) return null;
    final o = (y * width + x) * 4;
    return (rgba[o + 3] << 24) |
        (rgba[o] << 16) |
        (rgba[o + 1] << 8) |
        rgba[o + 2];
  }

  /// Reads back the toplevel `GtkWindow` at [gtkWindow] (a
  /// `WindowControllerLinux.windowHandle`). Null when the window is not
  /// mapped yet or the read fails.
  static LinuxWindowPixels? read(ffi.Pointer<ffi.Void> gtkWindow) {
    final lib = ffi.DynamicLibrary.process();
    final getWindow = lib
        .lookupFunction<
          ffi.Pointer<ffi.Void> Function(ffi.Pointer<ffi.Void>),
          ffi.Pointer<ffi.Void> Function(ffi.Pointer<ffi.Void>)
        >('gtk_widget_get_window');
    final width = lib
        .lookupFunction<
          ffi.Int32 Function(ffi.Pointer<ffi.Void>),
          int Function(ffi.Pointer<ffi.Void>)
        >('gdk_window_get_width');
    final height = lib
        .lookupFunction<
          ffi.Int32 Function(ffi.Pointer<ffi.Void>),
          int Function(ffi.Pointer<ffi.Void>)
        >('gdk_window_get_height');
    final fromWindow = lib
        .lookupFunction<
          ffi.Pointer<ffi.Void> Function(
            ffi.Pointer<ffi.Void>,
            ffi.Int32,
            ffi.Int32,
            ffi.Int32,
            ffi.Int32,
          ),
          ffi.Pointer<ffi.Void> Function(
            ffi.Pointer<ffi.Void>,
            int,
            int,
            int,
            int,
          )
        >('gdk_pixbuf_get_from_window');
    final pixels = lib
        .lookupFunction<
          ffi.Pointer<ffi.Uint8> Function(ffi.Pointer<ffi.Void>),
          ffi.Pointer<ffi.Uint8> Function(ffi.Pointer<ffi.Void>)
        >('gdk_pixbuf_get_pixels');
    final pixbufWidth = lib
        .lookupFunction<
          ffi.Int32 Function(ffi.Pointer<ffi.Void>),
          int Function(ffi.Pointer<ffi.Void>)
        >('gdk_pixbuf_get_width');
    final pixbufHeight = lib
        .lookupFunction<
          ffi.Int32 Function(ffi.Pointer<ffi.Void>),
          int Function(ffi.Pointer<ffi.Void>)
        >('gdk_pixbuf_get_height');
    final rowstride = lib
        .lookupFunction<
          ffi.Int32 Function(ffi.Pointer<ffi.Void>),
          int Function(ffi.Pointer<ffi.Void>)
        >('gdk_pixbuf_get_rowstride');
    final channels = lib
        .lookupFunction<
          ffi.Int32 Function(ffi.Pointer<ffi.Void>),
          int Function(ffi.Pointer<ffi.Void>)
        >('gdk_pixbuf_get_n_channels');
    final unref = lib
        .lookupFunction<
          ffi.Void Function(ffi.Pointer<ffi.Void>),
          void Function(ffi.Pointer<ffi.Void>)
        >('g_object_unref');

    final gdkWindow = getWindow(gtkWindow);
    if (gdkWindow == ffi.nullptr) return null;
    final logicalWidth = width(gdkWindow);
    final logicalHeight = height(gdkWindow);
    if (logicalWidth <= 0 || logicalHeight <= 0) return null;
    final pixbuf = fromWindow(gdkWindow, 0, 0, logicalWidth, logicalHeight);
    if (pixbuf == ffi.nullptr) return null;
    try {
      final w = pixbufWidth(pixbuf);
      final h = pixbufHeight(pixbuf);
      final stride = rowstride(pixbuf);
      final n = channels(pixbuf);
      final src = pixels(pixbuf).asTypedList(stride * h);
      final rgba = Uint8List(w * h * 4);
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          final s = y * stride + x * n;
          final d = (y * w + x) * 4;
          rgba[d] = src[s];
          rgba[d + 1] = src[s + 1];
          rgba[d + 2] = src[s + 2];
          rgba[d + 3] = n == 4 ? src[s + 3] : 0xFF;
        }
      }
      return LinuxWindowPixels._(rgba, w, h);
    } finally {
      unref(pixbuf);
    }
  }
}
