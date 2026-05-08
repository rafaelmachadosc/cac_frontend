import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../../data/court_repository.dart';
import '../../data/match_request_repository.dart';
import '../../data/team_repository.dart';
import '../../models/confronto_solicitacao.dart';
import '../../models/quadra.dart';
import '../../models/quadra_horario_funcional.dart';
import '../../models/quadra_reserva.dart';
import '../../models/tipo_agendamento.dart';
import '../../models/time.dart';
import '../../theme/app_colors.dart';
import '../../widgets/feedback_modal.dart';
import '../../widgets/star_rating_display.dart';
import '../home/informativos_screen.dart';
import '../team/team_profile_screen.dart';

class ScheduleGameScreen extends StatefulWidget {
  const ScheduleGameScreen({
    super.key,
    required this.meuTimeId,
    this.adversarioPreSelecionado,
  });

  /// Time logado / solicitante (mock).
  final String meuTimeId;
  final Time? adversarioPreSelecionado;

  @override
  State<ScheduleGameScreen> createState() => _ScheduleGameScreenState();
}

class _ScheduleGameScreenState extends State<ScheduleGameScreen> {
  static const _monthViewportBase = 1200;
  final _buscaNome = TextEditingController();
  final _local = TextEditingController();
  final _mensagem = TextEditingController();
  final _matchIdCtrl = TextEditingController();
  final _localFieldKey = GlobalKey();
  late final PageController _monthController;

  TipoAgendamento _modo = TipoAgendamento.aleatorio;
  DateTime _selectedDay = DateTime.now();
  TimeOfDay _startTime = const TimeOfDay(hour: 18, minute: 0);
  int _duracaoMinutos = 60;
  Time? _adversario;
  List<Time> _resultadosBusca = [];
  List<ConfrontoSolicitacao> _aceitesAleatorio = [];
  ConfrontoSolicitacao? _aceiteSelecionado;
  bool _enviandoLoteAleatorio = false;
  bool _carregandoAceites = false;
  bool _confirmandoAleatorio = false;
  bool _carregandoQuadras = false;
  bool _carregandoAgendaQuadra = false;
  List<Quadra> _quadras = [];
  List<Quadra> _sugestoesQuadra = [];
  Quadra? _quadraSelecionada;
  int? _espacoSelecionado;
  List<QuadraHorarioFuncional> _quadraHorarios = [];
  List<QuadraReserva> _quadraReservas = [];
  List<ConfrontoSolicitacao> _ocupacoesConfronto = [];
  Set<DateTime> _diasComHorarioOcupado = <DateTime>{};
  bool _carregandoDiasOcupados = false;
  Timer? _buscaDebounce;

  @override
  void initState() {
    super.initState();
    _adversario = widget.adversarioPreSelecionado;
    _buscaNome.addListener(_onBusca);
    _monthController = PageController(initialPage: _monthViewportBase);
    _matchIdCtrl.text = _gerarMatchId();
    _carregarQuadras();
    _carregarDiasComHorarioOcupado(_selectedDay);
  }

  @override
  void dispose() {
    _buscaDebounce?.cancel();
    _buscaNome.dispose();
    _local.dispose();
    _mensagem.dispose();
    _matchIdCtrl.dispose();
    _monthController.dispose();
    super.dispose();
  }

  String _gerarMatchId() {
    final now = DateTime.now().millisecondsSinceEpoch;
    final suffix = Random().nextInt(99999).toString().padLeft(5, '0');
    return 'm$now$suffix';
  }

  DateTime get _dataHoraInicio => DateTime(
    _selectedDay.year,
    _selectedDay.month,
    _selectedDay.day,
    _startTime.hour,
    _startTime.minute,
  );

  DateTime get _dataHoraFim =>
      _dataHoraInicio.add(Duration(minutes: _duracaoMinutos));

  String _fmt2(int n) => n.toString().padLeft(2, '0');

  String get _intervaloHorario {
    final ini = _dataHoraInicio;
    final fim = _dataHoraFim;
    return '${_fmt2(ini.hour)}:${_fmt2(ini.minute)} — ${_fmt2(fim.hour)}:${_fmt2(fim.minute)}';
  }

  String _localChaveAgendamento() {
    final qid = _quadraSelecionada?.id.trim();
    if (qid != null && qid.isNotEmpty) return 'quadra:$qid';
    return _local.text.trim().toLowerCase();
  }

  String _localTextoAgendamento() {
    final q = _quadraSelecionada;
    if (q != null) return q.textoResumoLocal;
    return _local.text.trim();
  }

  Future<void> _mostrarConflitoHorarioModal() async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Horário indisponível'),
        content: const Text(
          'Este horário, local e espaço já estão ocupados. '
          'Selecione outro horário para evitar conflito.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _onBusca() {
    if (_modo != TipoAgendamento.direto) return;
    _buscaDebounce?.cancel();
    _buscaDebounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      final termo = _buscaNome.text.trim();
      setState(() {
        _resultadosBusca = termo.isEmpty
            ? []
            : TeamRepository.instance.buscarPorNome(termo);
      });
    });
  }

  Future<void> _carregarQuadras() async {
    setState(() => _carregandoQuadras = true);
    final rows = await CourtRepository.instance.listarAtivas();
    if (!mounted) return;
    setState(() {
      _quadras = rows;
      _carregandoQuadras = false;
    });
  }

  void _atualizarSugestoesQuadra(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) {
      setState(() => _sugestoesQuadra = []);
      return;
    }
    final itens = _quadras
        .where(
          (e) =>
              e.nome.toLowerCase().contains(q) ||
              e.cidade.toLowerCase().contains(q) ||
              e.endereco.toLowerCase().contains(q) ||
              e.proprietarioNome.toLowerCase().contains(q),
        )
        .take(6)
        .toList();
    setState(() => _sugestoesQuadra = itens);
  }

  Future<void> _selecionarQuadra(Quadra q) async {
    FocusScope.of(context).unfocus();
    setState(() {
      _quadraSelecionada = q;
      _espacoSelecionado = q.espacosDisponiveis > 1 ? 1 : 1;
      _local.clear();
      _sugestoesQuadra = [];
    });
    await _carregarDiasComHorarioOcupado(_selectedDay);
    await _carregarAgendaQuadra(_selectedDay);
    _ajustarEspacoSelecionadoSeOcupado();
  }

  bool _mostrarSugestoesAcima(BuildContext context) {
    final fieldCtx = _localFieldKey.currentContext;
    if (fieldCtx == null) return MediaQuery.of(context).viewInsets.bottom > 0;
    final box = fieldCtx.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return MediaQuery.of(context).viewInsets.bottom > 0;
    final fieldTop = box.localToGlobal(Offset.zero).dy;
    final fieldHeight = box.size.height;
    final mq = MediaQuery.of(context);
    final availableAbove = fieldTop - mq.padding.top;
    final availableBelow =
        mq.size.height - (fieldTop + fieldHeight) - mq.viewInsets.bottom;
    if (availableBelow >= 220) return false;
    return availableAbove > availableBelow;
  }

  Widget _buildSugestoesQuadraCard() {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 220),
      child: Card(
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: _sugestoesQuadra.length,
          itemBuilder: (context, i) {
            final q = _sugestoesQuadra[i];
            return ListTile(
              leading: const Icon(Icons.stadium_outlined),
              title: Text(q.nome),
              subtitle: Text('${q.cidade} · Resp.: ${q.proprietarioNome}'),
              onTap: () => _selecionarQuadra(q),
            );
          },
        ),
      ),
    );
  }

  Future<void> _carregarAgendaQuadra(DateTime dia) async {
    final quadra = _quadraSelecionada;
    if (quadra == null) return;
    setState(() => _carregandoAgendaQuadra = true);
    final inicioDia = DateTime(dia.year, dia.month, dia.day);
    final fimDia = inicioDia.add(const Duration(days: 1));
    final horarios = await CourtRepository.instance.listarHorarios(quadra.id);
    final reservas = await CourtRepository.instance.listarReservasNoIntervalo(
      quadraId: quadra.id,
      desde: inicioDia,
      ate: fimDia,
    );
    final ocupacoesConfronto = await MatchRequestRepository.instance
        .listarOcupacoesPorLocalNoPeriodo(
      localChave: _localChaveAgendamento(),
      desde: inicioDia,
      ate: fimDia,
      espacoNumero: _espacoSelecionado,
    );
    if (!mounted) return;
    setState(() {
      _quadraHorarios = horarios;
      _quadraReservas = reservas;
      _ocupacoesConfronto = ocupacoesConfronto;
      _carregandoAgendaQuadra = false;
    });
    _ajustarEspacoSelecionadoSeOcupado();
  }

  Future<void> _carregarDiasComHorarioOcupado(DateTime referencia) async {
    final localChave = _localChaveAgendamento();
    if (localChave.trim().isEmpty) {
      if (!mounted) return;
      setState(() => _diasComHorarioOcupado = <DateTime>{});
      return;
    }
    final inicioMes = DateTime(referencia.year, referencia.month, 1);
    final fimMes = DateTime(referencia.year, referencia.month + 1, 1);
    setState(() => _carregandoDiasOcupados = true);
    final rows = await MatchRequestRepository.instance.listarOcupacoesPorLocalNoPeriodo(
      localChave: localChave,
      desde: inicioMes,
      ate: fimMes,
      espacoNumero: _espacoSelecionado,
    );
    if (!mounted) return;
    final dias = <DateTime>{};
    for (final e in rows) {
      final inicio = e.dataHora;
      final fim = e.dataFim ?? inicio.add(Duration(minutes: e.duracaoMinutos ?? 60));
      var d = DateTime(inicio.year, inicio.month, inicio.day);
      final ultimo = DateTime(fim.year, fim.month, fim.day);
      while (!d.isAfter(ultimo)) {
        dias.add(DateTime(d.year, d.month, d.day));
        d = d.add(const Duration(days: 1));
      }
    }
    setState(() {
      _diasComHorarioOcupado = dias;
      _carregandoDiasOcupados = false;
    });
  }

  QuadraHorarioFuncional? _horarioFuncionalDoDia() {
    final wd = _selectedDay.weekday;
    for (final h in _quadraHorarios) {
      if (h.diaSemana == wd) return h;
    }
    return null;
  }

  bool _slotOcupado(DateTime inicio, DateTime fim) {
    final espacoSelecionado = _espacoSelecionado;
    for (final r in _quadraReservas) {
      final ri = r.inicio.toLocal();
      final rf = r.fim.toLocal();
      final sobrepoe = inicio.isBefore(rf) && fim.isAfter(ri);
      if (!sobrepoe) continue;
      if (espacoSelecionado == null) return true;
      if (r.espacoNumero == null || r.espacoNumero == espacoSelecionado) {
        return true;
      }
    }
    return false;
  }

  bool _slotConflitaConfronto(DateTime inicio, DateTime fim) {
    for (final c in _ocupacoesConfronto) {
      final ci = c.dataHora;
      final cf = c.dataFim ?? ci.add(Duration(minutes: c.duracaoMinutos ?? 60));
      if (inicio.isBefore(cf) && fim.isAfter(ci)) {
        return true;
      }
    }
    return false;
  }

  bool _inicioConflitaDuracao(int duracaoMinutos) {
    final inicio = _dataHoraInicio;
    final fim = inicio.add(Duration(minutes: duracaoMinutos));
    return _slotOcupado(inicio, fim) || _slotConflitaConfronto(inicio, fim);
  }

  bool _espacoOcupadoNoIntervalo(int espacoNumero, DateTime inicio, DateTime fim) {
    for (final r in _quadraReservas) {
      final ri = r.inicio.toLocal();
      final rf = r.fim.toLocal();
      final sobrepoe = inicio.isBefore(rf) && fim.isAfter(ri);
      if (!sobrepoe) continue;
      if (r.espacoNumero == null || r.espacoNumero == espacoNumero) {
        return true;
      }
    }
    return false;
  }

  void _ajustarEspacoSelecionadoSeOcupado() {
    final quadra = _quadraSelecionada;
    if (quadra == null) return;
    if (quadra.espacosDisponiveis <= 1) {
      if (_espacoSelecionado != 1) {
        setState(() {
          _espacoSelecionado = 1;
        });
      }
      return;
    }
    final selecionado = _espacoSelecionado;
    if (selecionado != null &&
        !_espacoOcupadoNoIntervalo(selecionado, _dataHoraInicio, _dataHoraFim)) {
      return;
    }
    for (var i = 1; i <= quadra.espacosDisponiveis; i++) {
      if (!_espacoOcupadoNoIntervalo(i, _dataHoraInicio, _dataHoraFim)) {
        setState(() {
          _espacoSelecionado = i;
        });
        return;
      }
    }
    setState(() {
      _espacoSelecionado = null;
    });
  }

  List<_AgendaSlot> _slotsDia60Min() {
    final horario = _horarioFuncionalDoDia();
    if (horario == null) return const [];
    final base = DateTime(_selectedDay.year, _selectedDay.month, _selectedDay.day);
    final abre = base.add(Duration(minutes: horario.abreMinutos));
    final fecha = base.add(Duration(minutes: horario.fechaMinutos));
    if (!fecha.isAfter(abre)) return const [];
    final out = <_AgendaSlot>[];
    var cursor = abre;
    while (true) {
      final fim = cursor.add(const Duration(minutes: 60));
      if (fim.isAfter(fecha)) break;
      out.add(
        _AgendaSlot(
          inicio: cursor,
          fim: fim,
          disponivel:
              !_slotOcupado(cursor, fim) && !_slotConflitaConfronto(cursor, fim),
        ),
      );
      cursor = fim;
    }
    return out;
  }

  Future<void> _abrirCardHorarios() async {
    if (_quadraSelecionada == null) {
      await showFeedbackModal(
        context,
        title: 'Atenção',
        message: 'Selecione uma quadra cadastrada primeiro.',
        type: FeedbackType.info,
      );
      return;
    }
    await _carregarAgendaQuadra(_selectedDay);
    if (!mounted) return;
    final slots = _slotsDia60Min();
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return Dialog(
          backgroundColor: const Color(0xFF000000),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Horários da quadra (${_quadraSelecionada!.nome})',
                  style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFFFFFFFF),
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Slots de 60 minutos — verde: disponível, cinza: ocupado.'
                  '${_espacoSelecionado == null ? '' : ' Espaço $_espacoSelecionado.'}',
                  style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                        color: const Color(0xFFFFFFFF),
                      ),
                ),
                const SizedBox(height: 10),
                if (_carregandoAgendaQuadra)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (slots.isEmpty)
                  Text(
                    'Sem horários de funcionamento para este dia.',
                    style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                          color: const Color(0xFFFFFFFF),
                        ),
                  )
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: slots.map((slot) {
                      final ativo = _dataHoraInicio.year == slot.inicio.year &&
                          _dataHoraInicio.month == slot.inicio.month &&
                          _dataHoraInicio.day == slot.inicio.day &&
                          _dataHoraInicio.hour == slot.inicio.hour &&
                          _dataHoraInicio.minute == slot.inicio.minute;
                      final cor = slot.disponivel
                          ? Colors.green.withValues(alpha: ativo ? 0.95 : 0.72)
                          : Colors.grey.withValues(alpha: 0.45);
                      return InkWell(
                        onTap: slot.disponivel
                            ? () {
                                setState(() {
                                  _selectedDay = DateTime(
                                    slot.inicio.year,
                                    slot.inicio.month,
                                    slot.inicio.day,
                                  );
                                  _startTime = TimeOfDay(
                                    hour: slot.inicio.hour,
                                    minute: slot.inicio.minute,
                                  );
                                  _duracaoMinutos = 60;
                                });
                                Navigator.of(ctx).pop();
                              }
                            : null,
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 7,
                          ),
                          decoration: BoxDecoration(
                            color: cor,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: ativo
                                  ? AppColors.primaryYellow
                                  : Colors.transparent,
                              width: 1.5,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (!slot.disponivel) ...[
                                const Icon(
                                  Icons.lock_outline,
                                  size: 14,
                                  color: Colors.white70,
                                ),
                                const SizedBox(width: 4),
                              ],
                              Text(
                                '${_fmt2(slot.inicio.hour)}:${_fmt2(slot.inicio.minute)}'
                                ' - ${_fmt2(slot.fim.hour)}:${_fmt2(slot.fim.minute)}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFFFFFFF),
                      side: const BorderSide(color: Color(0xFFFFFFFF)),
                    ),
                    child: const Text('Fechar'),
                  ),
                ),
              ],
            ),
          ),
          ),
        );
      },
    );
  }

  Future<void> _carregarAceitesAleatorio() async {
    final matchId = _matchIdCtrl.text.trim();
    if (matchId.isEmpty) return;
    setState(() => _carregandoAceites = true);
    final rows = await MatchRequestRepository.instance.listarAceitosPorMatchId(
      matchId,
    );
    if (!mounted) return;
    setState(() {
      _aceitesAleatorio = rows;
      if (_aceiteSelecionado != null) {
        final same = rows.where((e) => e.id == _aceiteSelecionado!.id);
        _aceiteSelecionado = same.isEmpty ? null : same.first;
      }
      _carregandoAceites = false;
    });
  }

  Future<void> _enviarSolicitacoesAleatorias() async {
    final repo = TeamRepository.instance;
    final meuTime = repo.porId(widget.meuTimeId);
    if (meuTime == null) return;
    if (_localTextoAgendamento().isEmpty) {
      await showFeedbackModal(
        context,
        title: 'Campo obrigatório',
        message: 'Informe o local antes de buscar times.',
        type: FeedbackType.info,
      );
      return;
    }
    final adversarios = repo.todos
        .where((t) => t.id != widget.meuTimeId)
        .map((t) => {'id': t.id, 'nome': t.nome})
        .toList();
    if (adversarios.isEmpty) {
      await showFeedbackModal(
        context,
        title: 'Sem adversários',
        message: 'Nenhum time elegível para convite.',
        type: FeedbackType.info,
      );
      return;
    }
    setState(() => _enviandoLoteAleatorio = true);
    final ok = await MatchRequestRepository.instance.criarLoteAleatorio(
      matchId: _matchIdCtrl.text.trim(),
      solicitanteTeamId: meuTime.id,
      solicitanteNome: meuTime.nome,
      adversarios: adversarios,
      dataHora: _dataHoraInicio,
      dataFim: _dataHoraFim,
      duracaoMinutos: _duracaoMinutos,
      localTexto: _localTextoAgendamento(),
      localChave: _localChaveAgendamento(),
      espacoNumero: _espacoSelecionado,
      mensagem: _mensagem.text.trim().isEmpty ? null : _mensagem.text.trim(),
    );
    if (!mounted) return;
    setState(() => _enviandoLoteAleatorio = false);
    final conflito = (MatchRequestRepository.instance.ultimoErro ?? '')
        .contains('HORARIO_LOCAL_ESPACO_OCUPADO');
    if (conflito) {
      await _mostrarConflitoHorarioModal();
      return;
    }
    await showFeedbackModal(
      context,
      title: ok ? 'Tudo certo' : 'Não foi possível enviar',
      message: ok
          ? 'Solicitações enviadas. Os times que aceitarem vão aparecer em Informativos.'
          : 'Não foi possível enviar as solicitações agora.',
      type: ok ? FeedbackType.success : FeedbackType.error,
    );
    if (ok) {
      await _carregarAceitesAleatorio();
      if (!mounted) return;
      Navigator.of(context).maybePop();
    }
  }

  Future<void> _abrirPerfilAceite(ConfrontoSolicitacao s) async {
    final team = TeamRepository.instance.porId(s.adversarioTeamId);
    if (team == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => TeamProfileScreen(time: team)),
    );
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _confirmarAleatorio() async {
    final selecionado = _aceiteSelecionado;
    if (selecionado == null) {
      await showFeedbackModal(
        context,
        title: 'Atenção',
        message: 'Selecione um time aceito para confirmar.',
        type: FeedbackType.info,
      );
      return;
    }
    setState(() => _confirmandoAleatorio = true);
    final ok = await MatchRequestRepository.instance.confirmarAleatorio(
      matchId: _matchIdCtrl.text.trim(),
      requestIdConfirmado: selecionado.id,
    );
    if (!mounted) return;
    setState(() => _confirmandoAleatorio = false);
    if (!ok) {
      await showFeedbackModal(
        context,
        title: 'Não foi possível confirmar',
        message: 'Não foi possível confirmar o confronto agora.',
        type: FeedbackType.error,
      );
      return;
    }
    await _showSuccessDialog(
      title: 'Confronto confirmado',
      subtitle: 'Modo aleatório',
      destaque: '${selecionado.solicitanteNomeDisplay} x ${selecionado.adversarioNomeDisplay}',
      horario: _intervaloHorario,
      local: _localTextoAgendamento(),
      mensagem:
          'Confronto confirmado com sucesso. Os demais times aceitos deste grupo foram recusados automaticamente.',
    );
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const InformativosScreen()),
      (route) => false,
    );
  }

  Future<void> _showSuccessDialog({
    required String title,
    required String subtitle,
    required String destaque,
    required String horario,
    required String local,
    required String mensagem,
  }) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        child: Container(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
          decoration: BoxDecoration(
            color: AppColors.surfaceWhite,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: AppColors.neutralBorder),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check_circle_rounded,
                  color: Colors.green,
                  size: 34,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.w900,
                  color: AppColors.backgroundDark,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.neutralText,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.surfaceLight,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  children: [
                    Text(
                      destaque,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                        color: AppColors.backgroundDark,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      horario,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppColors.neutralText,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      local,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.neutralText),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Text(
                mensagem,
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.neutralTextLight),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primaryYellow,
                    foregroundColor: AppColors.onPrimaryYellow,
                  ),
                  child: const Text(
                    'OK',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _sortearAdversario() {
    final repo = TeamRepository.instance;
    final meuTime = repo.porId(widget.meuTimeId);
    final adv = repo.sortearAdversario(
      excluirId: widget.meuTimeId,
      cidadeFiltro: meuTime?.cidade,
    );
    setState(() => _adversario = adv);
    if (!mounted) return;
    if (adv == null) {
      showFeedbackModal(
        context,
        title: 'Sem time disponível',
        message: 'Nenhum time disponível no momento.',
        type: FeedbackType.info,
      );
    } else {
      showFeedbackModal(
        context,
        title: 'Time sorteado',
        message: '${adv.nome} foi selecionado. Revise e confirme.',
        type: FeedbackType.success,
      );
    }
  }

  Future<void> _confirmar() async {
    if (_localTextoAgendamento().isEmpty) {
      await showFeedbackModal(
        context,
        title: 'Campo obrigatório',
        message: 'Preencha o local.',
        type: FeedbackType.info,
      );
      return;
    }
    if (_modo == TipoAgendamento.aleatorio) {
      await _confirmarAleatorio();
      return;
    }

    final meu = TeamRepository.instance.porId(widget.meuTimeId);
    if (meu == null) {
      await showFeedbackModal(
        context,
        title: 'Não foi possível continuar',
        message: 'Time solicitante não encontrado.',
        type: FeedbackType.error,
      );
      return;
    }
    if (_adversario == null) {
      await showFeedbackModal(
        context,
        title: 'Atenção',
        message: 'Selecione ou sorteie um adversário.',
        type: FeedbackType.info,
      );
      return;
    }
    if (_adversario!.id == meu.id) {
      await showFeedbackModal(
        context,
        title: 'Ação não permitida',
        message: 'Não é possível agendar contra o próprio time.',
        type: FeedbackType.info,
      );
      return;
    }
    final modoDb = 'DIRETO';
    final id = await MatchRequestRepository.instance.criar(
      matchId: _matchIdCtrl.text.trim(),
      solicitanteTeamId: meu.id,
      adversarioTeamId: _adversario!.id,
      solicitanteNome: meu.nome,
      adversarioNome: _adversario!.nome,
      modoDb: modoDb,
      dataHora: _dataHoraInicio,
      dataFim: _dataHoraFim,
      duracaoMinutos: _duracaoMinutos,
      localTexto: _localTextoAgendamento(),
      localChave: _localChaveAgendamento(),
      espacoNumero: _espacoSelecionado,
      mensagem: _mensagem.text.trim().isEmpty ? null : _mensagem.text.trim(),
    );
    if (!mounted) return;
    if (id == null) {
      final repo = MatchRequestRepository.instance;
      final erroCadastro = repo.ultimoErro ?? '';
      final erroCodigo = (repo.ultimoErroCodigo ?? '').toUpperCase();
      final erroMensagem = (repo.ultimoErroMensagem ?? '').toUpperCase();
      final conflito = erroMensagem.contains('HORARIO_LOCAL_ESPACO_OCUPADO') ||
          erroCadastro.contains('HORARIO_LOCAL_ESPACO_OCUPADO');
      if (conflito) {
        await _mostrarConflitoHorarioModal();
        return;
      }
      final erroPermissao = erroCodigo == '42501' ||
          erroMensagem.contains('ROW-LEVEL SECURITY') ||
          erroMensagem.contains('PERMISSION DENIED');
      final erroSessao = erroMensagem.contains('JWT') ||
          erroMensagem.contains('TOKEN') ||
          erroMensagem.contains('NOT AUTHENTICATED');
      final erroForeignKey = erroCodigo == '23503';
      final erroSchema = erroCodigo == 'PGRST204';
      final detalheTecnico = erroCodigo.isEmpty ? '' : ' (código: $erroCodigo)';
      await showFeedbackModal(
        context,
        title: 'Não foi possível registrar',
        message: erroSessao
            ? 'Sua sessão expirou. Faça login novamente para continuar.'
            : erroPermissao
            ? 'Seu time ativo não corresponde ao perfil autenticado no servidor. Faça login novamente para sincronizar o time.'
            : erroForeignKey
                ? 'Um dos times selecionados não existe mais no servidor. Atualize a lista e tente novamente.'
                : erroSchema
                    ? 'O banco está com schema desatualizado para agendamento. Atualize as migrações do Supabase e tente novamente.'
            : 'Não foi possível registrar a solicitação agora$detalheTecnico.',
        type: FeedbackType.error,
      );
      return;
    }
    await _showSuccessDialog(
      title: 'Solicitação enviada',
      subtitle: 'Modo direto',
      destaque: _adversario!.nome,
      horario: _intervaloHorario,
      local: _localTextoAgendamento(),
      mensagem:
          'O outro time verá o pedido em Informativos e poderá aceitar ou recusar.',
    );
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const InformativosScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Agendar jogo')),
      backgroundColor: AppColors.surfaceLight,
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => FocusScope.of(context).unfocus(),
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            16,
            16,
            16,
            16 + MediaQuery.of(context).viewInsets.bottom,
          ),
          children: [
          SegmentedButton<TipoAgendamento>(
            style: ButtonStyle(
              backgroundColor: WidgetStateProperty.resolveWith<Color?>(
                (states) => states.contains(WidgetState.selected)
                    ? const Color(0xFF000000)
                    : null,
              ),
              foregroundColor: WidgetStateProperty.resolveWith<Color?>(
                (states) => states.contains(WidgetState.selected)
                    ? const Color(0xFFFFFFFF)
                    : const Color(0xFF000000),
              ),
            ),
            segments: const [
              ButtonSegment(
                value: TipoAgendamento.aleatorio,
                label: Text('Aleatório'),
                icon: Icon(Icons.shuffle),
              ),
              ButtonSegment(
                value: TipoAgendamento.direto,
                label: Text('Direto'),
                icon: Icon(Icons.search),
              ),
            ],
            selected: {_modo},
            onSelectionChanged: (s) {
              setState(() {
                _modo = s.first;
                if (_modo == TipoAgendamento.aleatorio) {
                  _matchIdCtrl.text = _gerarMatchId();
                  _aceitesAleatorio = [];
                  _aceiteSelecionado = null;
                  _resultadosBusca = [];
                  _adversario = null;
                }
              });
            },
          ),
          const SizedBox(height: 16),
          _MinimalMonthCalendar(
            controller: _monthController,
            basePage: _monthViewportBase,
            selectedDay: _selectedDay,
            occupiedDays: _diasComHorarioOcupado,
            loadingOccupiedDays: _carregandoDiasOcupados,
            onMonthChanged: _carregarDiasComHorarioOcupado,
            onDaySelected: (d) async {
              setState(() => _selectedDay = d);
              if (_quadraSelecionada != null) {
                await _carregarAgendaQuadra(d);
              }
            },
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              ChoiceChip(
                label: const Text('1hr'),
                selected: _duracaoMinutos == 60,
                onSelected: _inicioConflitaDuracao(60)
                    ? null
                    : (_) => setState(() => _duracaoMinutos = 60),
                selectedColor: const Color(0xFF000000),
                backgroundColor: AppColors.surfaceWhite,
                labelStyle: TextStyle(
                  color: _duracaoMinutos == 60
                      ? const Color(0xFFFFFFFF)
                      : const Color(0xFF000000),
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('2hr'),
                selected: _duracaoMinutos == 120,
                onSelected: _inicioConflitaDuracao(120)
                    ? null
                    : (_) => setState(() => _duracaoMinutos = 120),
                selectedColor: const Color(0xFF000000),
                backgroundColor: AppColors.surfaceWhite,
                labelStyle: TextStyle(
                  color: _duracaoMinutos == 120
                      ? const Color(0xFFFFFFFF)
                      : const Color(0xFF000000),
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Text(
                'Horário: $_intervaloHorario',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.end,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: const Color(0xFF00B8D4),
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (_quadraSelecionada != null) ...[
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: const BorderSide(
                  color: AppColors.primaryYellow,
                  width: 1.5,
                ),
              ),
              child: ListTile(
                leading: const Icon(Icons.stadium_outlined),
                title: Text(_quadraSelecionada!.nome),
                subtitle: Text(_quadraSelecionada!.textoResumoLocal),
                trailing: IconButton(
                  tooltip: 'Remover seleção',
                  icon: const Icon(Icons.close),
                  onPressed: () {
                    setState(() {
                      _quadraSelecionada = null;
                      _espacoSelecionado = null;
                      _sugestoesQuadra = [];
                    });
                    unawaited(_carregarDiasComHorarioOcupado(_selectedDay));
                  },
                ),
              ),
            ),
          ] else if (_sugestoesQuadra.isNotEmpty && _mostrarSugestoesAcima(context)) ...[
            _buildSugestoesQuadraCard(),
            const SizedBox(height: 8),
          ],
          if (_quadraSelecionada == null)
            TextField(
              key: _localFieldKey,
              controller: _local,
              onChanged: (value) {
                _atualizarSugestoesQuadra(value);
                unawaited(_carregarDiasComHorarioOcupado(_selectedDay));
              },
              decoration: InputDecoration(
                labelText: 'Local (buscar quadra cadastrada)',
                suffixIcon: _carregandoQuadras
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : IconButton(
                        tooltip: 'Atualizar locais',
                        onPressed: _carregarQuadras,
                        icon: const Icon(Icons.refresh),
                      ),
              ),
            ),
          if (_quadraSelecionada == null &&
              _sugestoesQuadra.isNotEmpty &&
              !_mostrarSugestoesAcima(context)) ...[
            const SizedBox(height: 8),
            _buildSugestoesQuadraCard(),
          ],
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _quadraSelecionada == null ? null : _abrirCardHorarios,
            icon: const Icon(Icons.view_agenda_outlined),
            label: const Text('Horários'),
          ),
          const SizedBox(height: 12),
          if (_modo == TipoAgendamento.aleatorio) ...[
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _enviandoLoteAleatorio
                    ? null
                    : _enviarSolicitacoesAleatorias,
                icon: const Icon(Icons.send),
                label: Text(
                  _enviandoLoteAleatorio
                      ? 'Publicando...'
                      : 'Buscar times',
                ),
              ),
            ),
            const SizedBox(height: 8),
            if (_aceitesAleatorio.isEmpty)
              Text(
                'Nenhum aceite disponível ainda.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.neutralText,
                    ),
              )
            else
              ..._aceitesAleatorio.map((s) {
                final team = TeamRepository.instance.porId(s.adversarioTeamId);
                final selected = _aceiteSelecionado?.id == s.id;
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: BorderSide(
                      color: selected
                          ? AppColors.primaryYellow
                          : AppColors.neutralBorder,
                      width: selected ? 2 : 1,
                    ),
                  ),
                  child: ListTile(
                    onTap: () => setState(() => _aceiteSelecionado = s),
                    title: Text(s.adversarioNomeDisplay),
                    subtitle: Text(
                      team == null
                          ? 'Sem detalhes locais do time'
                          : '${team.cidade} · avaliação ${team.mediaAvaliacao.toStringAsFixed(1)} (${team.totalAvaliacoes})',
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (team != null)
                          IgnorePointer(
                            child: StarRatingDisplay(
                              value: team.mediaAvaliacao,
                              size: 14,
                            ),
                          ),
                        IconButton(
                          tooltip: 'Ver perfil',
                          onPressed: () => _abrirPerfilAceite(s),
                          icon: const Icon(Icons.open_in_new),
                        ),
                      ],
                    ),
                  ),
                );
              }),
          ] else ...[
            if (_adversario != null) ...[
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: const BorderSide(color: AppColors.primaryYellow, width: 1.5),
                ),
                child: ListTile(
                  leading: const Icon(Icons.shield_outlined),
                  title: Text(_adversario!.nome),
                  subtitle: const Text('Time selecionado'),
                  trailing: IconButton(
                    tooltip: 'Remover seleção',
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(() => _adversario = null),
                  ),
                ),
              ),
            ],
            if (_resultadosBusca.isNotEmpty) ...[
              Builder(
                builder: (context) {
                  final visiveis = _resultadosBusca
                      .where((t) => t.id != widget.meuTimeId)
                      .toList();
                  if (visiveis.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        'Só aparece o seu time nos resultados. Busque outro nome.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppColors.onPrimaryYellow,
                            ),
                      ),
                    );
                  }
                  final selecionado = _adversario;
                  final filtrados = List<Time>.from(visiveis);
                  if (selecionado != null &&
                      selecionado.id != widget.meuTimeId &&
                      !filtrados.any((t) => t.id == selecionado.id)) {
                    filtrados.insert(0, selecionado);
                  }
                  return Column(
                    children: filtrados.map((t) {
                      final sel = _adversario?.id == t.id;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          curve: Curves.easeOutCubic,
                          padding: sel
                              ? const EdgeInsets.all(10)
                              : EdgeInsets.zero,
                          decoration: BoxDecoration(
                            color: sel
                                ? AppColors.surfaceLight
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: sel
                                  ? AppColors.neutralBorder
                                  : Colors.transparent,
                              width: 1,
                            ),
                          ),
                          child: Card(
                            margin: EdgeInsets.zero,
                            elevation: sel ? 0 : 1,
                            color: AppColors.surfaceWhite,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                              side: BorderSide(
                                color: sel
                                    ? AppColors.primaryYellow
                                    : AppColors.neutralBorder,
                                width: sel ? 2 : 1,
                              ),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: InkWell(
                              onTap: () {
                                FocusScope.of(context).unfocus();
                                setState(() {
                                  _adversario = t;
                                  _buscaNome.clear();
                                  _resultadosBusca = [];
                                });
                              },
                              borderRadius: BorderRadius.circular(14),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                  vertical: 2,
                                ),
                                child: ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: AppColors.primaryYellow
                                        .withValues(alpha: 0.4),
                                    child: Text(
                                      t.nome.isNotEmpty
                                          ? t.nome[0].toUpperCase()
                                          : '?',
                                      style: const TextStyle(
                                        color: AppColors.onPrimaryYellow,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  title: Text(t.nome),
                                  subtitle: Text(
                                    '${t.cidade} · avaliação ${t.mediaAvaliacao.toStringAsFixed(1)} (${t.totalAvaliacoes})',
                                  ),
                                  trailing: IgnorePointer(
                                    ignoring: true,
                                    child: StarRatingDisplay(
                                      value: t.mediaAvaliacao,
                                      size: 16,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  );
                },
              ),
              const SizedBox(height: 8),
            ],
            if (_adversario == null)
              TextField(
                controller: _buscaNome,
                decoration: const InputDecoration(
                  labelText: 'Buscar time por nome',
                ),
              ),
            const SizedBox(height: 8),
            if (_resultadosBusca.isEmpty)
              Text(
                'Digite para buscar.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.onPrimaryYellow,
                    ),
              ),
            TextButton.icon(
              onPressed: _adversario == null
                  ? null
                  : () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => TeamProfileScreen(time: _adversario!),
                        ),
                      );
                    },
              icon: const Icon(Icons.open_in_new),
              label: const Text('Adversário'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _sortearAdversario,
              icon: const Icon(Icons.casino),
              label: const Text('Sortear time disponível'),
            ),
          ],
          const Divider(height: 32),
          TextField(
            controller: _mensagem,
            decoration: const InputDecoration(
              labelText: 'Mensagem (opcional)',
            ),
            maxLines: 2,
          ),
          const SizedBox(height: 16),
        ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: FilledButton(
          onPressed: _confirmandoAleatorio ? null : () => _confirmar(),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primaryYellow,
            foregroundColor: AppColors.onPrimaryYellow,
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          child: Text(
            _confirmandoAleatorio
                ? 'Confirmando...'
                : _modo == TipoAgendamento.aleatorio
                    ? 'Confirmar time selecionado'
                    : 'Confirmar agendamento',
          ),
        ),
      ),
    );
  }
}

class _MinimalMonthCalendar extends StatefulWidget {
  const _MinimalMonthCalendar({
    required this.controller,
    required this.basePage,
    required this.selectedDay,
    required this.onDaySelected,
    required this.occupiedDays,
    required this.loadingOccupiedDays,
    this.onMonthChanged,
  });

  final PageController controller;
  final int basePage;
  final DateTime selectedDay;
  final ValueChanged<DateTime> onDaySelected;
  final Set<DateTime> occupiedDays;
  final bool loadingOccupiedDays;
  final ValueChanged<DateTime>? onMonthChanged;

  @override
  State<_MinimalMonthCalendar> createState() => _MinimalMonthCalendarState();
}

class _MinimalMonthCalendarState extends State<_MinimalMonthCalendar> {
  DateTime _monthForPage(int page) {
    final now = DateTime.now();
    return DateTime(now.year, now.month + (page - widget.basePage), 1);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 308,
      child: PageView.builder(
        controller: widget.controller,
        onPageChanged: (index) => widget.onMonthChanged?.call(_monthForPage(index)),
        itemBuilder: (context, index) {
          final month = _monthForPage(index);
          final label = _monthLabel(month);
          final gridDays = _buildGridDays(month);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () {
                        widget.controller.previousPage(
                          duration: const Duration(milliseconds: 180),
                          curve: Curves.easeOut,
                        );
                      },
                      icon: const Icon(Icons.chevron_left, size: 18),
                      visualDensity: VisualDensity.compact,
                      tooltip: 'Mês anterior',
                    ),
                    Expanded(
                      child: Text(
                        label,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: AppColors.backgroundDark,
                            ),
                      ),
                    ),
                    IconButton(
                      onPressed: () {
                        widget.controller.nextPage(
                          duration: const Duration(milliseconds: 180),
                          curve: Curves.easeOut,
                        );
                      },
                      icon: const Icon(Icons.chevron_right, size: 18),
                      visualDensity: VisualDensity.compact,
                      tooltip: 'Próximo mês',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              const Row(
                children: [
                  _Dow('SEG'),
                  _Dow('TER'),
                  _Dow('QUA'),
                  _Dow('QUI'),
                  _Dow('SEX'),
                  _Dow('SAB'),
                  _Dow('DOM'),
                ],
              ),
              const SizedBox(height: 4),
              SizedBox(
                height: 218,
                child: GridView.builder(
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: gridDays.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 7,
                    mainAxisSpacing: 5,
                    crossAxisSpacing: 5,
                    mainAxisExtent: 32,
                  ),
                  itemBuilder: (context, i) {
                    final d = gridDays[i];
                    final isCurrentMonth = d.month == month.month;
                    final isToday = _sameDate(d, DateTime.now());
                    final isSelected = _sameDate(d, widget.selectedDay);
                    return InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => widget.onDaySelected(d),
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: !isCurrentMonth && !isSelected
                              ? LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    AppColors.neutralText.withValues(alpha: 0.04),
                                    AppColors.neutralText.withValues(alpha: 0.12),
                                  ],
                                )
                              : null,
                          color: isSelected
                              ? AppColors.primaryYellow
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(12),
                          border: isToday && !isSelected
                              ? Border.all(color: AppColors.primaryYellow)
                              : null,
                        ),
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '${d.day}',
                                style: TextStyle(
                                  fontWeight: isSelected || isToday
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                  color: isSelected
                                      ? AppColors.onDark
                                      : isCurrentMonth
                                          ? AppColors.backgroundDark
                                          : AppColors.neutralText.withValues(alpha: 0.42),
                                ),
                              ),
                              const SizedBox(height: 2),
                              if (isCurrentMonth &&
                                  widget.occupiedDays.any((od) => _sameDate(od, d)))
                                Container(
                                  width: 5,
                                  height: 5,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: isSelected
                                        ? AppColors.onDark
                                        : AppColors.primaryYellow,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              if (widget.loadingOccupiedDays)
                const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: LinearProgressIndicator(minHeight: 2),
                ),
            ],
          );
        },
      ),
    );
  }

  String _monthLabel(DateTime month) {
    const nomes = [
      'Janeiro',
      'Fevereiro',
      'Março',
      'Abril',
      'Maio',
      'Junho',
      'Julho',
      'Agosto',
      'Setembro',
      'Outubro',
      'Novembro',
      'Dezembro',
    ];
    return '${nomes[month.month - 1]} ${month.year}';
  }

  List<DateTime> _buildGridDays(DateTime month) {
    final first = DateTime(month.year, month.month, 1);
    final nextMonth = DateTime(month.year, month.month + 1, 1);
    final totalDias = nextMonth.difference(first).inDays;
    final inicioSemana = first.subtract(Duration(days: first.weekday - 1));
    final totalCelulas = ((first.weekday - 1 + totalDias + 6) ~/ 7) * 7;
    return List.generate(
      totalCelulas,
      (i) => DateTime(
        inicioSemana.year,
        inicioSemana.month,
        inicioSemana.day + i,
      ),
    );
  }

  bool _sameDate(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }
}

class _Dow extends StatelessWidget {
  const _Dow(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Center(
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: AppColors.neutralText,
                fontWeight: FontWeight.w700,
              ),
        ),
      ),
    );
  }
}

class _AgendaSlot {
  const _AgendaSlot({
    required this.inicio,
    required this.fim,
    required this.disponivel,
  });

  final DateTime inicio;
  final DateTime fim;
  final bool disponivel;
}
