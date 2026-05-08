import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:apphoradojogo/data/team_repository.dart';
import 'package:apphoradojogo/features/home/home_screen.dart';
import 'package:apphoradojogo/features/match/schedule_game_screen.dart';
import 'package:apphoradojogo/features/team/team_profile_screen.dart';
import 'package:apphoradojogo/models/time.dart';

void main() {
  testWidgets('Home exibe ações principais', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: HomeScreen()),
    );

    expect(find.text('Hora do Jogo'), findsOneWidget);
    expect(find.text('Cadastrar time'), findsOneWidget);
    expect(find.text('Agendar jogo'), findsOneWidget);
  });

  testWidgets(
    'Perfil de outro time agenda usando time ativo como solicitante',
    (WidgetTester tester) async {
      TeamRepository.instance
        ..clearActiveTeam()
        ..setActiveTeam('meu-time-id');
      final adversario = Time(
        id: 'time-adversario-id',
        nome: 'Adversario FC',
        cidade: 'Jaragua do Sul',
        mediaAvaliacao: 0,
        membros: const [],
      );

      await tester.pumpWidget(
        MaterialApp(home: TeamProfileScreen(time: adversario)),
      );

      await tester.tap(find.widgetWithText(FloatingActionButton, 'Agendar jogo'));
      await tester.pumpAndSettle();

      final schedule = tester.widget<ScheduleGameScreen>(
        find.byType(ScheduleGameScreen),
      );
      expect(schedule.meuTimeId, 'meu-time-id');
      expect(schedule.adversarioPreSelecionado?.id, 'time-adversario-id');
    },
  );
}
