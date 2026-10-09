// 1.4.2: the user's profile photo for the Profil nav item.
//
// INTEGRATION POINT for the social branch (feature-social-attach-android):
// set this to the cached GitHub avatar, e.g.
//   ref.read(profileAvatarProvider.notifier).state = FileImage(cachedFile);
// Null = the person icon.
import 'package:flutter/widgets.dart' show ImageProvider;
import 'package:flutter_riverpod/legacy.dart';

final profileAvatarProvider = StateProvider<ImageProvider?>((ref) => null);
