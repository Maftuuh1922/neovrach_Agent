// Top of the Profil tab: the GitHub-backed profile + friends block
// ([SocialSection], read through the paired PC). The Profil tab only depends
// on this class name and its const constructor.
import 'package:flutter/material.dart';

import 'remote_social_screen.dart' show SocialSection;

class ProfileHeaderSlot extends StatelessWidget {
  const ProfileHeaderSlot({super.key, this.autoLoad = true});

  /// Tests: skip the initial refresh from the PC.
  final bool autoLoad;

  @override
  Widget build(BuildContext context) => KeyedSubtree(
        key: const ValueKey('profile-header-slot'),
        child: SocialSection(autoLoad: autoLoad),
      );
}
