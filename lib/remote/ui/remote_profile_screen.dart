// 1.4.2: Profil tab. Top: [ProfileHeaderSlot] (placeholder for the GitHub
// profile / friends feature from the social branch). Below: the phone's
// appearance — the whole Tampilan section that used to live on the PC tab
// (accent, custom colour, Gelap/Terang/Sistem, Latar belakang + sliders,
// Ikuti tema PC) plus the launcher icon picker.
import 'package:flutter/material.dart';

import 'app_icon_panel.dart';
import 'nv_widgets.dart';
import 'profile_header_slot.dart';
import 'remote_pc_screen.dart' show AppearancePanel;

class RemoteProfileScreen extends StatelessWidget {
  const RemoteProfileScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        body: ListView(
          key: const ValueKey('profile-list'),
          padding: EdgeInsets.only(bottom: 24 + MediaQuery.paddingOf(context).bottom),
          children: const [
            NvHeader(kicker: 'hp ini', title: 'Profil'),
            Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: ProfileHeaderSlot()),
            NvSection('tampilan'),
            AppearancePanel(),
            NvSection('ikon aplikasi'),
            AppIconPanel(),
          ],
        ),
      );
}
