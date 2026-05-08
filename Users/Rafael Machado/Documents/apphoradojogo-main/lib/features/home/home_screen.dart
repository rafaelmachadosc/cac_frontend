import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/team_repository.dart';
import '../../theme/app_colors.dart';
import '../../widgets/feedback_modal.dart';
import '../account/my_account_screen.dart';
import '../auth/access_login_screen.dart';
import '../auth/auth_session_storage.dart';
import '../auth/auth_team_resolution.dart';
import '../match/schedule_game_screen.dart';
import '../team/team_profile_screen.dart';
import '../team/team_register_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  Future<void> _logout(BuildContext context) async {
    await releaseActiveSessionLockForCurrentUser(Supabase.instance.client);
    await Supabase.instance.client.auth.signOut();
    await AuthSessionStorage.clearSession(clearRememberedLogin: true);
    if (!context.mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const AccessLoginScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final repo = TeamRepository.instance;
    final hasTimes = repo.todos.isNotEmpty;
    final activeTeamId = repo.activeTeamId;
    final timeInicial = activeTeamId == null || activeTeamId.isEmpty
        ? (hasTimes ? repo.todos.first : null)
        : repo.porId(activeTeamId);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Hora do Jogo'),
        actions: [
          IconButton(
            tooltip: 'Sair',
            onPressed: () => _logout(context),
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      backgroundColor: AppColors.surfaceLight,
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          20,
          20,
          20,
          20 + MediaQuery.of(context).viewPadding.bottom,
        ),
        children: [
          Text(
            hasTimes
                ? 'Escolha um fluxo para continuar.'
                : 'Nenhum time cadastrado ainda. Comece por "Cadastrar time".',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: AppColors.onPrimaryYellow,
                ),
          ),
          const SizedBox(height: 20),
          _HomeCard(
            icon: Icons.group_add,
            title: 'Cadastrar time',
            subtitle: 'Goleiros e jogadores, validação mínima.',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const TeamRegisterScreen(),
              ),
            ),
          ),
          _HomeCard(
            icon: Icons.person_search,
            title: 'Perfil do time',
            subtitle: 'Abra o perfil do primeiro time cadastrado.',
            onTap: () {
              final t = timeInicial;
              if (t == null) {
                showFeedbackModal(
                  context,
                  title: 'Atenção',
                  message: 'Cadastre um time antes de abrir o perfil.',
                  type: FeedbackType.info,
                );
                return;
              }
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => TeamProfileScreen(time: t),
                ),
              );
            },
          ),
          _HomeCard(
            icon: Icons.event_available,
            title: 'Agendar jogo',
            subtitle: 'Modo aleatório e direto na mesma tela.',
            onTap: () {
              final meuTimeId = repo.activeTeamId;
              if (meuTimeId == null || meuTimeId.isEmpty) {
                showFeedbackModal(
                  context,
                  title: 'Não foi possível continuar',
                  message: 'Time ativo não identificado. Faça login novamente.',
                  type: FeedbackType.error,
                );
                return;
              }
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ScheduleGameScreen(
                    meuTimeId: meuTimeId,
                  ),
                ),
              );
            },
          ),
          _HomeCard(
            icon: Icons.manage_accounts,
            title: 'Meu cadastro',
            subtitle: 'Edite dados do time e conta de acesso.',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const MyAccountScreen(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HomeCard extends StatelessWidget {
  const _HomeCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: AppColors.primaryYellow,
                foregroundColor: AppColors.onPrimaryYellow,
                child: Icon(icon),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: AppColors.backgroundDark,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.onPrimaryYellow,
                          ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppColors.backgroundDark),
            ],
          ),
        ),
      ),
    );
  }
}
