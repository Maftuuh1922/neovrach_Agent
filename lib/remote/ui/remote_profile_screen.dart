// 1.4.3: Profil tab. Top: [ProfileHeaderSlot] = Profil & Teman (GitHub
// profile, heatmap, stack, friends, Bagikan profil; through the PC). Below: the phone's
// appearance — the whole Tampilan section that used to live on the PC tab
// (accent, custom colour, Gelap/Terang/Sistem, Latar belakang + sliders,
// Ikuti tema PC) plus Warna dari wallpaper, Gaya kaca and the launcher icon
// picker.
import 'package:flutter/material.dart';

import 'app_icon_panel.dart';
import 'glass_style_picker.dart';
import 'nv_widgets.dart';
import 'profile_header_slot.dart';
import 'appearance/appearance_section.dart' show NvAppearanceSection;

class RemoteProfileScreen extends StatelessWidget {
  const RemoteProfileScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        body: ListView(
          key: const ValueKey('profile-list'),
          padding: EdgeInsets.only(bottom: 24 + MediaQuery.paddingOf(context).bottom),
          children: const [
            NvHeader(kicker: 'hp ini', title: 'Profil'),
            ProfileHeaderSlot(),
            NvSection('tampilan'),
            // NvAppearanceSection hosts its own NvPanelToneHost (wallpaper tone)
            NvAppearanceSection(),
            SizedBox(height: 12),
            WallpaperColorsPanel(),
            NvSection('gaya kaca'),
            GlassStylePicker(),
            NvSection('ikon aplikasi'),
            AppIconPanel(),
          ],
        ),
      );
}
