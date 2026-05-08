import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/team_repository.dart';
import '../../data/match_post_game_repository.dart';
import '../../data/match_request_repository.dart';
import '../../models/confronto_solicitacao.dart';
import '../../models/time.dart';
import '../../services/push_notification_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/feedback_modal.dart';
import '../../widgets/team_avatar_picker.dart';
import '../account/my_account_screen.dart';
import '../auth/access_login_screen.dart';
import '../auth/auth_session_storage.dart';
import '../auth/auth_team_resolution.dart';
import 'confrontos_solicitacoes_panel.dart';
import '../match/schedule_game_screen.dart';
import '../team/team_register_screen.dart';
import '../team/team_profile_screen.dart';

class InformativosScreen extends StatefulWidget {
  const InformativosScreen({super.key, this.timeId});

  final String? timeId;

  @override
  State<InformativosScreen> createState() => _InformativosScreenState();
}

class _InformativosScreenState extends State<InformativosScreen> {
  final GlobalKey<ConfrontosSolicitacoesPanelState> _confrontosKey =
      GlobalKey<ConfrontosSolicitacoesPanelState>();
  bool _carregandoDadosIniciais = false;
  bool _checandoPendenciaPosJogo = false;
  bool _modalPosJogoAberto = false;

  @override
  void initState() {
    super.initState();
    _bootstrapDadosIniciais();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _verificarPendenciaPosJogo();
    });
  }

  Future<void> _bootstrapDadosIniciais() async {
    final repo = TeamRepository.instance;
    final teamId = widget.timeId ?? repo.activeTeamId;
    if (teamId == null || teamId.isEmpty) return;
    repo.setActiveTeam(teamId);
    setState(() => _carregandoDadosIniciais = true);
    await repo.bootstrap();
    if (!mounted) return;
    setState(() => _carregandoDadosIniciais = false);
    await _confrontosKey.currentState?.reload();
    await _verificarPendenciaPosJogo();
  }

  Future<void> _openMyAccount() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const MyAccountScreen()),
    );
    await TeamRepository.instance.bootstrap();
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _logout(BuildContext context) async {
    await PushNotificationService.instance.deactivateTokenForCurrentSession();
    await releaseActiveSessionLockForCurrentUser(Supabase.instance.client);
    await Supabase.instance.client.auth.signOut();
    await AuthSessionStorage.clearSession(clearRememberedLogin: true);
    if (!context.mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const AccessLoginScreen()),
      (route) => false,
    );
  }

  Time? _resolveTeam() {
    final repo = TeamRepository.instance;
    if (widget.timeId != null) {
      return repo.porId(widget.timeId!);
    }
    final activeId = repo.activeTeamId;
    if (activeId != null && activeId.isNotEmpty) {
      return repo.porId(activeId);
    }
    return repo.todos.isNotEmpty ? repo.todos.first : null;
  }

  String? _resolveTeamId() {
    if (widget.timeId != null && widget.timeId!.isNotEmpty) return widget.timeId!;
    final repoActive = TeamRepository.instance.activeTeamId;
    if (repoActive != null && repoActive.isNotEmpty) return repoActive;
    return _resolveTeam()?.id;
  }

  bool _deveCobrarPosJogo(ConfrontoSolicitacao s, String meuTimeId) {
    if (!(s.confirmado || s.aceito)) return false;
    if (s.solicitanteTeamId != meuTimeId && s.adversarioTeamId != meuTimeId) {
      return false;
    }
    final agora = DateTime.now();
    final fim = s.dataFim ?? s.dataHora.add(Duration(minutes: s.duracaoMinutos ?? 60));
    final inicioCobranca = fim.add(const Duration(minutes: 15));
    final limite = fim.add(const Duration(hours: 24));
    return !agora.isBefore(inicioCobranca) && !agora.isAfter(limite);
  }

  Future<void> _verificarPendenciaPosJogo() async {
    if (!mounted || _checandoPendenciaPosJogo || _modalPosJogoAberto) return;
    final team = _resolveTeam();
    if (team == null) return;
    _checandoPendenciaPosJogo = true;
    try {
      final lista = await MatchRequestRepository.instance.listarParaTime(team.id);
      if (!mounted) return;
      ConfrontoSolicitacao? pendente;
      for (final s in lista) {
        if (!_deveCobrarPosJogo(s, team.id)) continue;
        final jaInformou = await MatchPostGameRepository.instance.timeJaInformouPlacar(
          solicitacaoId: s.id,
          teamId: team.id,
        );
        if (!jaInformou) {
          pendente = s;
          break;
        }
      }
      if (pendente == null) return;
      _modalPosJogoAberto = true;
      await _abrirModalObrigatorioPosJogo(pendente);
      _modalPosJogoAberto = false;
      if (!mounted) return;
      await _confrontosKey.currentState?.reload();
      await _verificarPendenciaPosJogo();
    } finally {
      _checandoPendenciaPosJogo = false;
    }
  }

  Future<void> _abrirModalObrigatorioPosJogo(ConfrontoSolicitacao confronto) async {
    final meuTeamId = _resolveTeamId();
    final souMandante = meuTeamId != null && meuTeamId == confronto.solicitanteTeamId;
    final souVisitante = meuTeamId != null && meuTeamId == confronto.adversarioTeamId;
    final podeEditarMandante = souMandante || (!souMandante && !souVisitante);
    final podeEditarVisitante = souVisitante || (!souMandante && !souVisitante);
    final placarMandante = TextEditingController();
    final placarVisitante = TextEditingController();
    final comentario = TextEditingController();
    int estrelas = 5;
    String? erroInline;
    bool salvando = false;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return PopScope(
          canPop: false,
          child: StatefulBuilder(
            builder: (ctx, setDialogState) {
              Future<void> salvar() async {
                if (salvando) return;
                final pm = int.tryParse(placarMandante.text.trim());
                final pv = int.tryParse(placarVisitante.text.trim());
                final placarMandanteEnvio = podeEditarMandante ? pm : null;
                final placarVisitanteEnvio = podeEditarVisitante ? pv : null;
                final placarInvalidoMandante =
                    podeEditarMandante && (placarMandanteEnvio == null || placarMandanteEnvio < 0);
                final placarInvalidoVisitante =
                    podeEditarVisitante &&
                    (placarVisitanteEnvio == null || placarVisitanteEnvio < 0);
                if (placarInvalidoMandante || placarInvalidoVisitante) {
                  setDialogState(() {
                    erroInline = 'Informe um placar válido para continuar.';
                  });
                  return;
                }
                setDialogState(() {
                  erroInline = null;
                  salvando = true;
                });
                final ok = await MatchPostGameRepository.instance.salvarPosJogo(
                  solicitacaoId: confronto.id,
                  placarMandante: placarMandanteEnvio,
                  placarVisitante: placarVisitanteEnvio,
                  comentarioTexto: comentario.text.trim().isEmpty ? null : comentario.text.trim(),
                  comentarioEstrelas: estrelas,
                );
                if (!mounted) return;
                if (!ok) {
                  setDialogState(() {
                    erroInline = MatchPostGameRepository.instance.ultimoErro ??
                        'Não foi possível salvar. Tente novamente.';
                    salvando = false;
                  });
                  return;
                }
                if (ctx.mounted) Navigator.of(ctx).pop();
                await _confrontosKey.currentState?.reload();
                if (!mounted) return;
                await showFeedbackModal(
                  context,
                  title: 'Resultado enviado',
                  message:
                      'Seu placar foi registrado com sucesso. Você já pode prosseguir no app.',
                  type: FeedbackType.success,
                );
              }

              Widget scoreField({
                required String teamName,
                required bool editable,
                required TextEditingController controller,
              }) {
                return Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF12161C),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: editable ? AppColors.primaryYellow : const Color(0xFF424242),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        teamName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: controller,
                        readOnly: !editable,
                        maxLength: 2,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        keyboardType: TextInputType.number,
                        textInputAction: TextInputAction.done,
                        cursorColor: Colors.white,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: editable ? Colors.white : Colors.white70,
                          fontWeight: FontWeight.w900,
                          fontSize: 28,
                        ),
                        decoration: InputDecoration(
                          counterText: '',
                          hintText: editable ? '0' : '-',
                          hintStyle: TextStyle(
                            color: editable ? Colors.white54 : Colors.white30,
                          ),
                          filled: true,
                          fillColor: const Color(0xFF1A1A1A),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }

              return Dialog(
                backgroundColor: const Color(0xFF111111),
                insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    16,
                    16,
                    16,
                    16 + MediaQuery.of(ctx).viewInsets.bottom,
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Resultado do Jogo',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 28,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Preencha o placar e avalie a partida',
                          style: TextStyle(color: Colors.white70),
                        ),
                        const SizedBox(height: 14),
                        scoreField(
                          teamName: confronto.solicitanteNomeDisplay,
                          editable: podeEditarMandante,
                          controller: placarMandante,
                        ),
                        const SizedBox(height: 10),
                        scoreField(
                          teamName: confronto.adversarioNomeDisplay,
                          editable: podeEditarVisitante,
                          controller: placarVisitante,
                        ),
                        const SizedBox(height: 14),
                        const Text(
                          'SUA AVALIAÇÃO',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: List.generate(5, (i) {
                            final ativa = i < estrelas;
                            return IconButton(
                              onPressed: () => setDialogState(() => estrelas = i + 1),
                              icon: Icon(
                                ativa ? Icons.star : Icons.star_border,
                                color: AppColors.primaryYellow,
                              ),
                            );
                          }),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'COMENTÁRIO (OPCIONAL)',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: comentario,
                          maxLines: 2,
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            hintText: 'Escreva um comentário sobre a partida...',
                            hintStyle: const TextStyle(color: Colors.white54),
                            filled: true,
                            fillColor: const Color(0xFF1A1A1A),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                        if (erroInline != null) ...[
                          const SizedBox(height: 10),
                          Text(
                            erroInline!,
                            style: const TextStyle(
                              color: Color(0xFFFFCDD2),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed: salvando ? null : salvar,
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColors.primaryYellow,
                              foregroundColor: AppColors.onPrimaryYellow,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            child: Text(
                              salvando ? 'Salvando...' : 'Confirmar Resultado',
                              style: const TextStyle(fontWeight: FontWeight.w900),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
    placarMandante.dispose();
    placarVisitante.dispose();
    comentario.dispose();
  }

  @override
  Widget build(BuildContext context) {
    void showMissingActiveTeamError() {
      showFeedbackModal(
        context,
        title: 'Não foi possível continuar',
        message: 'Time ativo não identificado. Faça login novamente.',
        type: FeedbackType.error,
      );
    }

    void goToRegisterIfMissingTeam() {
      showFeedbackModal(
        context,
        title: 'Atenção',
        message: 'Cadastre um time para acessar esta área.',
        type: FeedbackType.info,
      );
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => const TeamRegisterScreen(isOnboarding: true),
        ),
      );
    }

    final team = _resolveTeam();
    final hasAnyTeam = TeamRepository.instance.todos.isNotEmpty;
    return Scaffold(
      backgroundColor: AppColors.surfaceLight,
      body: RefreshIndicator(
        onRefresh: () async {
          await _confrontosKey.currentState?.reload();
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(
            16,
            16 + MediaQuery.of(context).viewPadding.top,
            16,
            16 + MediaQuery.of(context).viewPadding.bottom,
          ),
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.62),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.55),
                    ),
                  ),
                  child: Row(
                    children: [
                      Text(
                        'Início',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: AppColors.backgroundDark,
                            ),
                      ),
                      const Spacer(),
                      IconButton.filledTonal(
                        tooltip: 'Meu cadastro',
                        onPressed: _openMyAccount,
                        icon: const Icon(Icons.manage_accounts),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        tooltip: 'Desligar',
                        onPressed: () => _logout(context),
                        style: IconButton.styleFrom(
                          backgroundColor: const Color(0xFFB3261E),
                          foregroundColor: Colors.white,
                        ),
                        icon: const Icon(Icons.power_settings_new_rounded),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            _HeroInfoCard(
              teamName: team?.nome ?? 'Seu time',
              capaKey: team?.capaKey,
            ),
            if (_carregandoDadosIniciais) ...[
              const SizedBox(height: 8),
              const LinearProgressIndicator(minHeight: 2),
            ],
            if (_resolveTeamId() != null) ...[
              const SizedBox(height: 18),
              ConfrontosSolicitacoesPanel(
                key: _confrontosKey,
                meuTimeId: _resolveTeamId()!,
              ),
            ],
            const SizedBox(height: 18),
            Text(
              'Ações rápidas',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: AppColors.backgroundDark,
                ),
          ),
          const SizedBox(height: 10),
          _ActionTile(
            label: 'Perfil',
            subtitle: 'Visualize integrantes e dados do time',
            icon: Icons.person,
            onTap: () {
              final currentTeam = _resolveTeam();
              if (currentTeam == null) {
                if (hasAnyTeam) {
                  showMissingActiveTeamError();
                } else {
                  goToRegisterIfMissingTeam();
                }
                return;
              }
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => TeamProfileScreen(
                    time: currentTeam,
                    initialTabIndex: 0,
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          _ActionTile(
            label: 'Jogos (histórico do time)',
            subtitle: 'Acompanhe resultados e desempenho',
            icon: Icons.history_toggle_off,
            onTap: () {
              final currentTeam = _resolveTeam();
              if (currentTeam == null) {
                if (hasAnyTeam) {
                  showMissingActiveTeamError();
                } else {
                  goToRegisterIfMissingTeam();
                }
                return;
              }
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => TeamProfileScreen(
                    time: currentTeam,
                    initialTabIndex: 1,
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          _ActionTile(
            label: 'Agendar',
            subtitle: 'Crie o próximo jogo do seu time',
            icon: Icons.event_available,
            onTap: () async {
              final currentTeamId = _resolveTeamId();
              if (currentTeamId == null || currentTeamId.isEmpty) {
                if (hasAnyTeam) {
                  showMissingActiveTeamError();
                } else {
                  goToRegisterIfMissingTeam();
                }
                return;
              }
              await Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => ScheduleGameScreen(meuTimeId: currentTeamId),
                ),
              );
              if (mounted) {
                await _confrontosKey.currentState?.reload();
                await _verificarPendenciaPosJogo();
              }
            },
          ),
          const SizedBox(height: 18),
          Text(
            'Agenda de eventos',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: AppColors.backgroundDark,
                ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 146,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: 3,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                return Container(
                  width: 212,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.backgroundDark,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: AppColors.primaryYellow.withValues(alpha: 0.45),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: AppColors.primaryYellow,
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.primaryYellow.withValues(alpha: 0.35),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.celebration,
                          color: AppColors.onPrimaryYellow,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Evento ${index + 1}',
                        style: const TextStyle(
                          color: AppColors.onDark,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Rodada especial com destaque para confronto local.',
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: AppColors.neutralTextLight),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          SizedBox(height: 8 + MediaQuery.of(context).viewPadding.bottom),
        ],
        ),
      ),
    );
  }
}

class _HeroInfoCard extends StatelessWidget {
  const _HeroInfoCard({
    required this.teamName,
    this.capaKey,
  });

  final String teamName;
  final String? capaKey;

  @override
  Widget build(BuildContext context) {
    final selectedCover =
        presetAvatarByKey(capaKey) ?? presetAvatarOptions.first;
    return Container(
      height: 192,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          colors: [AppColors.backgroundDark, AppColors.pureBlack],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            selectedCover.assetPath,
            fit: BoxFit.cover,
          ),
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.18),
                  Colors.black.withValues(alpha: 0.72),
                ],
              ),
            ),
          ),
          Positioned(
            top: -28,
            right: -18,
            child: Container(
              width: 118,
              height: 118,
              decoration: BoxDecoration(
                color: AppColors.primaryYellow.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(36),
              ),
            ),
          ),
          Positioned(
            bottom: -36,
            left: -14,
            child: Container(
              width: 140,
              height: 92,
              decoration: BoxDecoration(
                color: AppColors.primaryYellow.withValues(alpha: 0.22),
                borderRadius: BorderRadius.circular(34),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: AppColors.primaryYellow,
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: const Text(
                    'PAINEL OFICIAL',
                    style: TextStyle(
                      color: AppColors.onPrimaryYellow,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
                const Spacer(),
                Text(
                  teamName,
                  style: const TextStyle(
                    color: AppColors.onDark,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Seu centro de comando para jogos, perfil e eventos.',
                  style: TextStyle(color: AppColors.neutralTextLight),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.onDark,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: AppColors.neutralBorder),
          ),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: AppColors.pureBlack,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(icon, color: AppColors.onDark),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        color: AppColors.pureBlack,
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: AppColors.pureBlack,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.onDark,
                size: 30,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
