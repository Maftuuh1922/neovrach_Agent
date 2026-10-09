// Agent identity shared with the desktop (spec: agent-identity-spec.md):
// display name from the core, coat colour = hash(id) over six coats (same
// hash and palette as the desktop 3D office), circular initial avatar with a
// status dot.
import 'package:flutter/material.dart';

import '../theme/neovarch_mobile_theme.dart';
import 'office_models.dart';

/// Six coats, identical to the desktop's OFFICE3D_COATS.
const agentCoats = <Color>[
  Color(0xFF3A4A6E), // indigo
  Color(0xFF7A2E2E), // oxblood
  Color(0xFF3E5A4A), // pine
  Color(0xFF6A5A8C), // wisteria
  Color(0xFF8A6A3A), // ochre
  Color(0xFF45434A), // charcoal
];

/// `(h * 31 + codeUnit) >>> 0` over the UTF-16 code units (JS `coatFor`).
int agentHash(String id) {
  var h = 0;
  for (final c in id.codeUnits) {
    h = (h * 31 + c) & 0xFFFFFFFF;
  }
  return h;
}

Color agentCoat(String id) => agentCoats[agentHash(id) % agentCoats.length];

/// First user-perceived character, upper-cased ('?' when empty).
String agentInitial(String name) {
  final t = name.trim();
  return t.isEmpty ? '?' : t.characters.first.toUpperCase();
}

/// Status colours, identical to the desktop's OFFICE3D_STATUS.
const agentWorking = Color(0xFF6FCF8A), agentWaiting = Color(0xFFF2B544), agentIdle = Color(0xFF9C9488), agentError = Color(0xFFFF3B30);

Color agentStatusColor(String status) => switch (status) {
      'working' => agentWorking,
      'waiting-approval' || 'waiting' => agentWaiting,
      'error' => agentError,
      _ => agentIdle,
    };

/// Circular initial avatar in the agent's coat, optional status dot.
class NvAgentAvatar extends StatelessWidget {
  const NvAgentAvatar({super.key, required this.id, required this.name, this.size = 32, this.status});
  final String id;
  final String name;
  final double size;
  /// Null: no status dot (chat sender pill).
  final String? status;

  factory NvAgentAvatar.of(OfficeAgent a, {Key? key, double size = 32, bool dot = true}) =>
      NvAgentAvatar(key: key, id: a.id, name: a.name, size: size, status: dot ? a.status : null);

  @override
  Widget build(BuildContext context) {
    final dark = NV.palette.dark;
    final circle = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: agentCoat(id),
        shape: BoxShape.circle,
        border: dark ? null : Border.all(color: const Color(0x1F000000)),
      ),
      child: Text(agentInitial(name),
          style: TextStyle(fontFamily: NV.sans, fontWeight: FontWeight.w600, fontSize: size * 0.46, height: 1.0, color: const Color(0xFFFFFFFF))),
    );
    final st = status;
    if (st == null) return SizedBox(key: ValueKey('agent-avatar-$id'), width: size, height: size, child: circle);
    final d = (size * 0.34).clamp(7.0, 20.0);
    return SizedBox(
      key: ValueKey('agent-avatar-$id'),
      width: size,
      height: size,
      child: Stack(clipBehavior: Clip.none, children: [
        circle,
        Positioned(
          left: size * 0.85 - d / 2,
          top: size * 0.85 - d / 2,
          child: Container(
            key: ValueKey('agent-status-$id'),
            width: d,
            height: d,
            decoration: BoxDecoration(
              color: agentStatusColor(st),
              shape: BoxShape.circle,
              border: Border.all(color: dark ? const Color(0xFF141414) : const Color(0xFFFFFFFF), width: 2),
            ),
          ),
        ),
      ]),
    );
  }
}
