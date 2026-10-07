// Schedule parsing for on-device cron: `30m`, `every 2h`, `1d`, or a
// five-field cron expression (minute hour day-of-month month day-of-week)
// with `*`, lists, ranges and `*/n` steps. Same accepted syntax as the
// server route's validator `^[0-9A-Za-z*/,:\- ]{1,64}$`.

final scheduleSyntax = RegExp(r'^[0-9A-Za-z*/,:\- ]{1,64}$');

Duration? parseInterval(String s) {
  final m = RegExp(r'^(?:every\s+)?(\d+)\s*(m|min|h|d)$', caseSensitive: false)
      .firstMatch(s.trim());
  if (m == null) return null;
  final n = int.parse(m.group(1)!);
  if (n <= 0) return null;
  return switch (m.group(2)!.toLowerCase()) {
    'h' => Duration(hours: n),
    'd' => Duration(days: n),
    _ => Duration(minutes: n),
  };
}

Set<int>? _field(String f, int min, int max) {
  final out = <int>{};
  for (final part in f.split(',')) {
    var step = 1;
    var range = part;
    final slash = part.indexOf('/');
    if (slash >= 0) {
      step = int.tryParse(part.substring(slash + 1)) ?? 0;
      range = part.substring(0, slash);
      if (step <= 0) return null;
    }
    int lo, hi;
    if (range == '*') {
      lo = min;
      hi = max;
    } else if (range.contains('-')) {
      final ab = range.split('-');
      lo = int.tryParse(ab[0]) ?? -1;
      hi = int.tryParse(ab[1]) ?? -1;
    } else {
      lo = int.tryParse(range) ?? -1;
      hi = slash >= 0 ? max : lo;
    }
    if (lo < min || hi > max || lo > hi) return null;
    for (var v = lo; v <= hi; v += step) {
      out.add(v);
    }
  }
  return out;
}

class CronExpr {
  final Set<int> minute, hour, dom, month, dow;
  final bool domStar, dowStar;
  CronExpr(this.minute, this.hour, this.dom, this.month, this.dow, this.domStar, this.dowStar);

  static CronExpr? parse(String s) {
    final f = s.trim().split(RegExp(r'\s+'));
    if (f.length != 5) return null;
    final mi = _field(f[0], 0, 59), h = _field(f[1], 0, 23), d = _field(f[2], 1, 31);
    final mo = _field(f[3], 1, 12), w = _field(f[4], 0, 7);
    if (mi == null || h == null || d == null || mo == null || w == null) return null;
    if (w.contains(7)) w.add(0);
    return CronExpr(mi, h, d, mo, w, f[2] == '*', f[4] == '*');
  }

  bool matches(DateTime t) {
    if (!minute.contains(t.minute) || !hour.contains(t.hour) || !month.contains(t.month)) return false;
    final domOk = dom.contains(t.day);
    final dowOk = dow.contains(t.weekday % 7);
    if (domStar || dowStar) return domOk && dowOk;
    return domOk || dowOk; // classic cron OR rule
  }

  DateTime? next(DateTime from) {
    var t = DateTime(from.year, from.month, from.day, from.hour, from.minute).add(const Duration(minutes: 1));
    for (var i = 0; i < 366 * 24 * 60; i++) {
      if (matches(t)) return t;
      t = t.add(const Duration(minutes: 1));
    }
    return null;
  }
}

/// Validates a schedule; returns null when fine, or an Indonesian error.
String? validateSchedule(String s) {
  if (!scheduleSyntax.hasMatch(s)) return 'jadwal kosong atau berisi karakter tidak sah';
  if (parseInterval(s) != null || CronExpr.parse(s) != null) return null;
  return 'jadwal tidak dikenali — pakai 30m, every 2h, atau ekspresi cron 5 kolom';
}

DateTime? nextRun(String schedule, DateTime from) {
  final iv = parseInterval(schedule);
  if (iv != null) return from.add(iv);
  return CronExpr.parse(schedule)?.next(from);
}
