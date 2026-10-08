// 1.4.2: placeholder at the top of the Profil tab.
//
// INTEGRATION POINT for the GitHub profile / friends feature
// (branch feature-social-attach-android): replace the body of
// [ProfileHeaderSlot] with the real profile header. The Profil tab only
// depends on this class name and its const constructor.
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';

import '../../theme/neovarch_mobile_theme.dart';
import 'nv_widgets.dart';

class ProfileHeaderSlot extends StatelessWidget {
  const ProfileHeaderSlot({super.key});

  @override
  Widget build(BuildContext context) => NvGlass(
        key: const ValueKey('profile-header-slot'),
        radius: NV.rCard,
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        child: Row(children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(color: NV.redWash, shape: BoxShape.circle, border: Border.all(color: NV.darkRed)),
            child: Icon(CupertinoIcons.person_2, size: 22, color: NV.red),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Profil & teman — segera', style: NV.display(size: 18)),
              const SizedBox(height: 4),
              Text('Profil GitHub dan daftar teman akan muncul di sini.', style: TextStyle(fontFamily: NV.sans, fontSize: 13, height: 1.35, color: NV.muted)),
            ]),
          ),
        ]),
      );
}
