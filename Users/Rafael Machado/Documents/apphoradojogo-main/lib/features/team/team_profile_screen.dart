import 'package:flutter/material.dart';

import '../../data/team_repository.dart';
import '../../models/categoria_membro.dart';
import '../../models/comentario_item.dart';
import '../../models/historico_item.dart';
import '../../models/membro.dart';
import '../../models/time.dart';
import '../../theme/app_colors.dart';
import '../../widgets/feedback_modal.dart';
import '../../widgets/category_3d_icon.dart';
import '../../widgets/star_rating_display.dart';
import '../../widgets/team_avatar_picker.dart';
import '../match/schedule_game_screen.dart';

class _ProfileHeaderBackground extends StatelessWidget {
  const _ProfileHeaderBackground({required this.time});

  final Time time;

  @override
  Widget build(BuildContext context) {
    final selectedCover =
        presetAvatarByKey(time.capaKey) ?? presetAvatarOptions.first;
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.asset(
          selectedCover.assetPath,
          fit: BoxFit.cover,
        ),
        SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 48, 16, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 8),
                StarRatingDisplay(
                  value: time.mediaAvaliacao,
                  size: 22,
                  starColor: AppColors.primaryYellow,
                  labelColor: AppColors.onDark,
                ),
                Text(
                  '${time.totalAvaliacoes} avaliações',
                  style: TextStyle(
                    color: AppColors.neutralTextLight,
                    fontWeight: FontWeight.w600,
                    shadows: [Shadow(blurRadius: 6, color: Colors.black87)],
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  time.nome,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.onDark,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    shadows: [Shadow(blurRadius: 8, color: Colors.black87)],
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  time.cidade,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.neutralTextLight,
                    fontWeight: FontWeight.w600,
                    shadows: [Shadow(blurRadius: 6, color: Colors.black87)],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class TeamProfileScreen extends StatefulWidget {
  const TeamProfileScreen({super.key, required this.time, this.initialTabIndex = 0});

  final Time time;
  final int initialTabIndex;

  @override
  State<TeamProfileScreen> createState() => _TeamProfileScreenState();
}

class _TeamProfileScreenState extends State<TeamProfileScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  late Time _timeAtual;
  late final bool _mostrarIntegrantes;

  @override
  void initState() {
    super.initState();
    _timeAtual = widget.time;
    _mostrarIntegrantes = TeamRepository.instance.activeTeamId == _timeAtual.id;
    final totalTabs = _mostrarIntegrantes ? 3 : 2;
    final maxIndex = totalTabs - 1;
    _tabController = TabController(
      length: totalTabs,
      vsync: this,
      initialIndex: widget.initialTabIndex.clamp(0, maxIndex),
    );
  }

  bool get _podeEditarIntegrantes =>
      TeamRepository.instance.activeTeamId == _timeAtual.id;

  Future<void> _removerIntegrante(Membro membro) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir integrante?'),
        content: Text('Deseja excluir ${membro.nome}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Não'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Sim, excluir'),
          ),
        ],
      ),
    );
    if (confirmar != true) return;
    final atualizado = _timeAtual.copyWith(
      membros: _timeAtual.membros.where((m) => m.id != membro.id).toList(),
    );
    await TeamRepository.instance.atualizar(atualizado);
    if (!mounted) return;
    setState(() => _timeAtual = atualizado);
    await showFeedbackModal(
      context,
      title: 'Tudo certo',
      message: 'Integrante excluído com sucesso.',
      type: FeedbackType.success,
    );
  }

  Future<void> _abrirEditarIntegrantes() async {
    final nomeCtrl = TextEditingController();
    CategoriaMembro categoria = CategoriaMembro.jogador;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFFFFAB00),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            Future<void> salvar() async {
              final nome = nomeCtrl.text.trim();
              if (nome.isEmpty) {
                await showFeedbackModal(
                  context,
                  title: 'Campo obrigatório',
                  message: 'Informe o nome do integrante.',
                  type: FeedbackType.info,
                );
                return;
              }
              final idNovo = '${_timeAtual.id}-${DateTime.now().millisecondsSinceEpoch}';
              final novo = Membro(
                id: idNovo,
                nome: nome,
                categoria: categoria,
                ativo: true,
              );
              final atualizado = _timeAtual.copyWith(
                membros: [..._timeAtual.membros, novo],
              );
              await TeamRepository.instance.atualizar(atualizado);
              if (!mounted) return;
              setState(() => _timeAtual = atualizado);
              if (!ctx.mounted) return;
              Navigator.of(ctx).pop();
              await showFeedbackModal(
                context,
                title: 'Tudo certo',
                message: 'Integrante adicionado com sucesso.',
                type: FeedbackType.success,
              );
            }

            return SafeArea(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  16,
                  12,
                  16,
                  16 + MediaQuery.of(ctx).viewInsets.bottom,
                ),
                child: SizedBox(
                  height: MediaQuery.of(ctx).size.height * 0.62,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: ScrollConfiguration(
                          behavior: const MaterialScrollBehavior().copyWith(
                            scrollbars: false,
                          ),
                          child: SingleChildScrollView(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                          Text(
                            'Editar integrantes',
                            style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  color: const Color(0xFF000000),
                                ),
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: nomeCtrl,
                            style: const TextStyle(color: Color(0xFF000000)),
                            decoration: const InputDecoration(
                              labelText: 'Nome do integrante',
                              labelStyle: TextStyle(color: Color(0xFF000000)),
                              filled: false,
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.all(Radius.circular(22)),
                                borderSide: BorderSide(color: Color(0xFFFFFFFF)),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.all(Radius.circular(22)),
                                borderSide: BorderSide(color: Color(0xFFFFFFFF)),
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          SegmentedButton<CategoriaMembro>(
                            style: ButtonStyle(
                              foregroundColor: WidgetStateProperty.all(
                                const Color(0xFF000000),
                              ),
                              side: WidgetStateProperty.all(
                                const BorderSide(color: Color(0xFFFFFFFF)),
                              ),
                            ),
                            segments: const [
                              ButtonSegment(
                                value: CategoriaMembro.goleiro,
                                label: Text('Goleiro'),
                                icon: Icon(Icons.sports_handball_rounded),
                              ),
                              ButtonSegment(
                                value: CategoriaMembro.jogador,
                                label: Text('Jogador'),
                                icon: Icon(Icons.sports_soccer),
                              ),
                            ],
                            selected: {categoria},
                            onSelectionChanged: (s) {
                              setSheetState(() => categoria = s.first);
                            },
                          ),
                          const SizedBox(height: 12),
                          if (_timeAtual.membros.isNotEmpty) ...[
                            Text(
                              'Integrantes atuais',
                              style: Theme.of(ctx).textTheme.labelLarge?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    color: const Color(0xFF000000),
                                  ),
                            ),
                            const SizedBox(height: 6),
                            ..._timeAtual.membros.map(
                              (m) => ListTile(
                                contentPadding: EdgeInsets.zero,
                                title: Text(
                                  m.nome,
                                  style: const TextStyle(color: Color(0xFF000000)),
                                ),
                                subtitle: Text(
                                  m.categoria.rotulo,
                                  style: const TextStyle(color: Color(0xFF000000)),
                                ),
                                trailing: IconButton(
                                  tooltip: 'Excluir integrante',
                                  onPressed: () async {
                                    Navigator.of(ctx).pop();
                                    await _removerIntegrante(m);
                                  },
                                  icon: const Icon(Icons.delete_outline),
                                  color: const Color(0xFF000000),
                                ),
                              ),
                            ),
                            const Divider(height: 20, color: Color(0xFFFFFFFF)),
                          ],
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Center(
                        child: Icon(
                          Icons.keyboard_arrow_down_rounded,
                          size: 18,
                          color: const Color(0xFF000000).withValues(alpha: 0.55),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: salvar,
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF000000),
                            foregroundColor: const Color(0xFFFFFFFF),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          icon: const Icon(Icons.save_outlined),
                          label: const Text('Adicionar'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
    nomeCtrl.dispose();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = _timeAtual;
    return Scaffold(
      backgroundColor: AppColors.surfaceLight,
      body: NestedScrollView(
        headerSliverBuilder: (context, inner) {
          return [
            SliverAppBar(
              pinned: true,
              expandedHeight: 200,
              backgroundColor: AppColors.backgroundDark,
              foregroundColor: AppColors.onDark,
              actions: [
                if (_podeEditarIntegrantes)
                  IconButton(
                    tooltip: 'Editar integrantes',
                    onPressed: _abrirEditarIntegrantes,
                    icon: const Icon(Icons.edit_outlined),
                  ),
              ],
              flexibleSpace: FlexibleSpaceBar(
                background: _ProfileHeaderBackground(time: t),
              ),
              bottom: TabBar(
                controller: _tabController,
                indicatorColor: AppColors.primaryYellow,
                labelColor: AppColors.onDark,
                unselectedLabelColor: AppColors.onDark.withValues(alpha: 0.55),
                tabs: [
                  if (_mostrarIntegrantes) const Tab(text: 'Integrantes'),
                  const Tab(text: 'Histórico'),
                  const Tab(text: 'Comentários'),
                ],
              ),
            ),
          ];
        },
        body: TabBarView(
          controller: _tabController,
          children: [
            if (_mostrarIntegrantes) _IntegrantesTab(membros: t.membros),
            _HistoricoTab(itens: t.historico),
            _ComentariosTab(itens: t.comentarios),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final meuTimeId = TeamRepository.instance.activeTeamId;
          if (meuTimeId == null || meuTimeId.isEmpty) {
            await showFeedbackModal(
              context,
              title: 'Não foi possível continuar',
              message: 'Time solicitante não identificado. Faça login novamente.',
              type: FeedbackType.error,
            );
            return;
          }
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => ScheduleGameScreen(
                meuTimeId: meuTimeId,
                adversarioPreSelecionado: meuTimeId == t.id ? null : t,
              ),
            ),
          );
        },
        icon: const Icon(Icons.event_note),
        label: const Text('Agendar jogo'),
      ),
    );
  }
}

class _IntegrantesTab extends StatelessWidget {
  const _IntegrantesTab({required this.membros});

  final List<Membro> membros;

  @override
  Widget build(BuildContext context) {
    if (membros.isEmpty) {
      return const Center(child: Text('Nenhum integrante.'));
    }
    final goleiros = membros
        .where((m) => m.categoria == CategoriaMembro.goleiro)
        .toList();
    final jogadores = membros
        .where((m) => m.categoria == CategoriaMembro.jogador)
        .toList();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _CategoriaIntegrantesSection(
          titulo: 'Goleiros',
          integrantes: goleiros,
        ),
        const SizedBox(height: 8),
        const Divider(height: 1),
        const SizedBox(height: 10),
        _CategoriaIntegrantesSection(
          titulo: 'Jogadores',
          integrantes: jogadores,
        ),
      ],
    );
  }
}

class _CategoriaIntegrantesSection extends StatelessWidget {
  const _CategoriaIntegrantesSection({
    required this.titulo,
    required this.integrantes,
  });

  final String titulo;
  final List<Membro> integrantes;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          titulo,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: AppColors.backgroundDark,
              ),
        ),
        const SizedBox(height: 8),
        if (integrantes.isEmpty)
          Text(
            'Nenhum $titulo cadastrado.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.neutralText,
                ),
          )
        else
          ...integrantes.map((m) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Card(
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: AppColors.pureBlack,
                    child: Text(
                      m.nome.isNotEmpty ? m.nome[0].toUpperCase() : '?',
                      style: const TextStyle(
                        color: AppColors.onDark,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  title: Text(m.nome),
                  subtitle: Text('${m.categoria.rotulo} · ${m.ativo ? "Ativo" : "Inativo"}'),
                  trailing: Category3dIcon(categoria: m.categoria, size: 36),
                ),
              ),
            );
          }),
      ],
    );
  }
}

class _HistoricoTab extends StatelessWidget {
  const _HistoricoTab({required this.itens});

  final List<HistoricoItem> itens;

  @override
  Widget build(BuildContext context) {
    if (itens.isEmpty) {
      return const Center(child: Text('Sem jogos no histórico.'));
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: itens.length,
      separatorBuilder: (context, index) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final h = itens[i];
        final data =
            '${h.data.day.toString().padLeft(2, '0')}/${h.data.month.toString().padLeft(2, '0')}/${h.data.year}';
        return Card(
          child: ListTile(
            title: Text('vs ${h.adversarioNome}'),
            subtitle: Text(data),
            trailing: Text(
              h.placar,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: AppColors.onPrimaryYellow,
                  ),
            ),
          ),
        );
      },
    );
  }
}

class _ComentariosTab extends StatelessWidget {
  const _ComentariosTab({required this.itens});

  final List<ComentarioItem> itens;

  @override
  Widget build(BuildContext context) {
    if (itens.isEmpty) {
      return const Center(child: Text('Sem comentários ainda.'));
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: itens.length,
      separatorBuilder: (context, index) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final c = itens[i];
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  c.jogoLabel,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: AppColors.backgroundDark,
                      ),
                ),
                const SizedBox(height: 6),
                StarRatingDisplay(value: c.estrelas.toDouble(), size: 18),
                const SizedBox(height: 6),
                Text(c.texto),
              ],
            ),
          ),
        );
      },
    );
  }
}
