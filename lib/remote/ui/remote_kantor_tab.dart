// 1.4.2: the Kantor tab holds two views behind a glass segmented control,
// "Kantor | Tugas" (the old Kantor and Tugas tabs). Segmented control only,
// no swipe: the Tugas lane strip already scrolls horizontally.
// 1.4.5: a third segment, "Perusahaan" (the PC's company of agents), shown
// only when the paired core has the `company.*` RPCs (hidden on older cores).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ui/widgets/motion.dart' show TabFade;

import '../remote_controller.dart';
import 'nv_widgets.dart';
import 'remote_company_screen.dart';
import 'remote_office_screen.dart';
import 'remote_tasks_screen.dart';

/// Segment indices inside the Kantor tab.
const kantorSegOffice = 0, kantorSegTasks = 1, kantorSegCompany = 2;

/// Web preview / tests: which segment the Kantor tab opens on.
int previewKantorSegment = kantorSegOffice;

class RemoteKantorTab extends ConsumerWidget {
  const RemoteKantorTab({super.key, required this.segment, required this.onSegment, required this.onOpenChat, required this.onOpenApprovals});
  final int segment;
  final ValueChanged<int> onSegment;
  final VoidCallback onOpenChat;
  final VoidCallback onOpenApprovals;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final top = MediaQuery.paddingOf(context).top;
    final company = ref.watch(remoteProvider.select((r) => r.companySupported)) != false;
    final segment = !company && this.segment == kantorSegCompany ? kantorSegOffice : this.segment;
    return Column(children: [
      Padding(
        padding: EdgeInsets.fromLTRB(16, top + 10, 16, 0),
        child: NvGlassSegmented(
          key: const ValueKey('kantor-segments'),
          labels: company ? const ['Kantor', 'Tugas', 'Perusahaan'] : const ['Kantor', 'Tugas'],
          index: segment,
          onChanged: onSegment,
        ),
      ),
      Expanded(
        child: MediaQuery.removePadding(
          context: context,
          removeTop: true,
          child: IndexedStack(index: segment, children: [
            TabFade(active: segment == kantorSegOffice, child: RemoteOfficeScreen(onOpenChat: onOpenChat, onOpenApprovals: onOpenApprovals)),
            TabFade(active: segment == kantorSegTasks, child: const RemoteTasksScreen()),
            if (company) TabFade(active: segment == kantorSegCompany, child: const RemoteCompanyScreen()),
          ]),
        ),
      ),
    ]);
  }
}
