// Agent identity shared with the desktop (agent-identity-spec.md): same hash,
// same six coats, same status colours.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neovarch_agent/remote/agent_identity.dart';
import 'package:neovarch_agent/remote/office_models.dart';

void main() {
  test('hash and coat match the desktop coatFor reference values', () {
    expect(agentHash('session:s1'), 1661818242);
    expect(agentHash('session:s2'), 1661818243);
    expect(agentHash('kanban:writer'), 3084314134);
    expect(agentCoat('session:s1'), const Color(0xFF3A4A6E));
    expect(agentCoat('session:s2'), const Color(0xFF7A2E2E));
    expect(agentCoat('kanban:writer'), const Color(0xFF8A6A3A));
  });

  test('initial and status colours', () {
    expect(agentInitial('raka'), 'R');
    expect(agentInitial('  '), '?');
    expect(agentStatusColor('working'), const Color(0xFF6FCF8A));
    expect(agentStatusColor('waiting-approval'), const Color(0xFFF2B544));
    expect(agentStatusColor('idle'), const Color(0xFF9C9488));
    expect(agentStatusColor('error'), const Color(0xFFFF3B30));
  });

  testWidgets('avatar: coat circle, white initial, status dot at bottom-right', (tester) async {
    final a = OfficeAgent.fromJson({'id': 'kanban:writer', 'name': 'writer', 'status': 'working'});
    await tester.pumpWidget(MaterialApp(home: Center(child: NvAgentAvatar.of(a, size: 40))));
    final box = tester.getRect(find.byKey(const ValueKey('agent-avatar-kanban:writer')));
    expect(box.size, const Size(40, 40));
    expect(find.text('W'), findsOneWidget);
    final dot = tester.getRect(find.byKey(const ValueKey('agent-status-kanban:writer')));
    expect(dot.center.dx - box.left, closeTo(34, 0.5));
    expect(dot.width, closeTo(13.6, 0.1));
    await tester.pumpWidget(MaterialApp(home: Center(child: NvAgentAvatar.of(a, size: 18, dot: false))));
    expect(find.byKey(const ValueKey('agent-status-kanban:writer')), findsNothing);
  });
}
