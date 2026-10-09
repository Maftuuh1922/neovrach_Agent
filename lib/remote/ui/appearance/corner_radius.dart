// "Kelengkungan sudut": one user-set outer radius (0–32 dp) from which every
// rounded shape of the app derives (cards, sheets, dialogs, buttons, inputs,
// chat bubbles, the floating nav bar). Persisted in shared_preferences and
// mirrored into the global [NV.corner] token, so widgets and the Material
// theme that read `NV.rCard` / `NV.rCtl` / `NV.rMsg` follow it; widgets that
// prefer an explicit dependency read [AppCornerRadius.of].
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../theme/neovarch_mobile_theme.dart';

/// Named presets shown under the slider.
const cornerPresets = <(String, double)>[
  ('Kotak', 0),
  ('Sedang', 12),
  ('Bulat', 24),
  ('Pil', 32),
];

const kCornerMin = 0.0;
const kCornerMax = 32.0;

/// All radii derived from one outer card radius. Inner shapes are
/// concentric: `inner = outer − padding` ([inner]).
@immutable
class NvRadii {
  const NvRadii(this.card);
  final double card;
  double get control => NV.ctlFor(card);
  double get sheet => card;
  double get dialog => (card + 4).clamp(0, 36).toDouble();
  double get bubble => card * 0.75;
  double get chip => control;
  double nav(double height) => (card * 1.4).clamp(0, height / 2).toDouble();
  double inner(double outer, double padding) => NV.inner(outer, padding);
  BorderRadius get cardBr => BorderRadius.circular(card);
  BorderRadius get controlBr => BorderRadius.circular(control);

  @override
  bool operator ==(Object other) => other is NvRadii && other.card == card;
  @override
  int get hashCode => card.hashCode;
}

/// Persisted corner radius. Updates [NV.corner] on every change.
class CornerRadiusController extends ChangeNotifier {
  CornerRadiusController(this._prefs) {
    final v = _prefs?.getDouble(kPrefKey);
    _value = (v ?? NV.defaultCorner).clamp(kCornerMin, kCornerMax).toDouble();
    NV.corner = _value;
  }

  /// In-memory only (tests, previews, before prefs are loaded).
  CornerRadiusController.memory([double value = NV.defaultCorner]) : _prefs = null {
    _value = value.clamp(kCornerMin, kCornerMax).toDouble();
    NV.corner = _value;
  }

  static const kPrefKey = 'nv.ui.corner';
  final SharedPreferences? _prefs;
  late double _value;

  /// Bumped on every change (theme cache key).
  int revision = 0;

  double get value => _value;
  NvRadii get radii => NvRadii(_value);

  /// Name of the preset matching [value], or null.
  String? get presetName {
    for (final (n, v) in cornerPresets) {
      if (v == _value) return n;
    }
    return null;
  }

  /// Snaps to whole dp, clamps to 0–32, persists and applies app-wide.
  void set(double v) {
    final s = v.clamp(kCornerMin, kCornerMax).roundToDouble();
    if (s == _value) return;
    _value = s;
    NV.corner = s;
    revision++;
    _prefs?.setDouble(kPrefKey, s);
    notifyListeners();
  }

  void reset() => set(NV.defaultCorner);
}

/// Default is an in-memory controller (so screens and tests work without
/// an override); the app overrides it with a prefs-backed one.
final cornerRadiusProvider = ChangeNotifierProvider<CornerRadiusController>((ref) => CornerRadiusController.memory(NV.corner));

/// Provides [NvRadii] to the tree and, on change, repaints every element
/// below (widgets reading the `NV.r*` tokens directly included), keeping
/// state. Put it in `MaterialApp.builder`.
class AppCornerRadius extends StatefulWidget {
  const AppCornerRadius({super.key, required this.controller, required this.child});
  final CornerRadiusController controller;
  final Widget child;

  /// Current radii; registers a dependency. Falls back to [NV.corner].
  static NvRadii of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_RadiiScope>()?.radii ?? NvRadii(NV.corner);

  @override
  State<AppCornerRadius> createState() => _AppCornerRadiusState();
}

class _AppCornerRadiusState extends State<AppCornerRadius> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
  }

  @override
  void didUpdateWidget(AppCornerRadius old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_changed);
      widget.controller.addListener(_changed);
    }
  }

  void _changed() {
    if (!mounted) return;
    setState(() {});
    void mark(Element e) {
      e.markNeedsBuild();
      e.visitChildren(mark);
    }

    (context as Element).visitChildren(mark);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _RadiiScope(radii: widget.controller.radii, child: widget.child);
}

class _RadiiScope extends InheritedWidget {
  const _RadiiScope({required this.radii, required super.child});
  final NvRadii radii;
  @override
  bool updateShouldNotify(_RadiiScope old) => old.radii != radii;
}
