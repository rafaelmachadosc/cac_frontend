import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/confronto_solicitacao.dart';

/// Solicitações de confronto (`confronto_solicitacoes` no Supabase).
class MatchRequestRepository {
  MatchRequestRepository._();

  static final MatchRequestRepository instance = MatchRequestRepository._();
  String? ultimoErro;
  String? ultimoErroCodigo;
  String? ultimoErroMensagem;

  static const _sel =
      'id, match_id, solicitante_team_id, adversario_team_id, '
      'solicitante_nome_display, adversario_nome_display, modo, status, '
      'data_hora, data_fim, duracao_minutos, local_texto, mensagem, '
      'criado_em, respondido_em';

  Future<List<ConfrontoSolicitacao>> listarParaTime(String teamId) async {
    try {
      final client = Supabase.instance.client;
      final a = await client
          .from('confronto_solicitacoes')
          .select(_sel)
          .eq('solicitante_team_id', teamId)
          .order('criado_em', ascending: false)
          .limit(50);
      final b = await client
          .from('confronto_solicitacoes')
          .select(_sel)
          .eq('adversario_team_id', teamId)
          .order('criado_em', ascending: false)
          .limit(50);
      final map = <String, ConfrontoSolicitacao>{};
      for (final e in [...a as List<dynamic>, ...b as List<dynamic>]) {
        final p = ConfrontoSolicitacao.tryParse(
          Map<String, dynamic>.from(e as Map<dynamic, dynamic>),
        );
        if (p != null) map[p.id] = p;
      }
      final out = map.values.toList()
        ..sort((x, y) => y.criadoEm.compareTo(x.criadoEm));
      return out.take(50).toList();
    } catch (_) {
      return [];
    }
  }

  Future<String?> criar({
    String? matchId,
    required String solicitanteTeamId,
    required String adversarioTeamId,
    required String solicitanteNome,
    required String adversarioNome,
    required String modoDb,
    required DateTime dataHora,
    DateTime? dataFim,
    int? duracaoMinutos,
    required String localTexto,
    String? localChave,
    int? espacoNumero,
    String? mensagem,
  }) async {
    try {
      _limparUltimoErro();
      final client = Supabase.instance.client;
      final row = await client
          .from('confronto_solicitacoes')
          .insert({
            if (matchId != null && matchId.trim().isNotEmpty)
              'match_id': matchId.trim(),
            'solicitante_team_id': solicitanteTeamId,
            'adversario_team_id': adversarioTeamId,
            'solicitante_nome_display': solicitanteNome,
            'adversario_nome_display': adversarioNome,
            'modo': modoDb,
            'status': 'PENDENTE',
            'data_hora': dataHora.toUtc().toIso8601String(),
            if (dataFim case final fim?) 'data_fim': fim.toUtc().toIso8601String(),
            ...?duracaoMinutos == null
                ? null
                : {'duracao_minutos': duracaoMinutos},
            'local_texto': localTexto,
            if (localChave case final chave? when chave.trim().isNotEmpty)
              'local_chave': chave.trim(),
            ...?espacoNumero == null ? null : {'espaco_numero': espacoNumero},
            if (mensagem case final msg? when msg.trim().isNotEmpty)
              'mensagem': msg.trim(),
          })
          .select('id')
          .single();
      return row['id']?.toString();
    } catch (e) {
      _registrarErro(e);
      return null;
    }
  }

  Future<bool> responder({
    required String solicitacaoId,
    required bool aceitar,
  }) async {
    try {
      final client = Supabase.instance.client;
      await client.from('confronto_solicitacoes').update({
        'status': aceitar ? 'ACEITO' : 'RECUSADO',
        'respondido_em': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', solicitacaoId).eq('status', 'PENDENTE');
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> criarLoteAleatorio({
    required String matchId,
    required String solicitanteTeamId,
    required String solicitanteNome,
    required List<Map<String, String>> adversarios,
    required DateTime dataHora,
    required DateTime dataFim,
    required int duracaoMinutos,
    required String localTexto,
    String? localChave,
    int? espacoNumero,
    String? mensagem,
  }) async {
    if (adversarios.isEmpty) return false;
    try {
      _limparUltimoErro();
      final client = Supabase.instance.client;
      await client.from('confronto_solicitacoes').insert(
            adversarios
                .map(
                  (e) => {
                    'match_id': matchId,
                    'solicitante_team_id': solicitanteTeamId,
                    'adversario_team_id': e['id'],
                    'solicitante_nome_display': solicitanteNome,
                    'adversario_nome_display': e['nome'],
                    'modo': 'ALEATORIO',
                    'status': 'PENDENTE',
                    'data_hora': dataHora.toUtc().toIso8601String(),
                    'data_fim': dataFim.toUtc().toIso8601String(),
                    'duracao_minutos': duracaoMinutos,
                    'local_texto': localTexto,
                    if (localChave != null && localChave.trim().isNotEmpty)
                      'local_chave': localChave.trim(),
                    'espaco_numero': espacoNumero,
                    if (mensagem != null && mensagem.trim().isNotEmpty)
                      'mensagem': mensagem.trim(),
                  },
                )
                .toList(),
          );
      return true;
    } catch (e) {
      _registrarErro(e);
      return false;
    }
  }

  void _limparUltimoErro() {
    ultimoErro = null;
    ultimoErroCodigo = null;
    ultimoErroMensagem = null;
  }

  void _registrarErro(Object erro) {
    if (erro is PostgrestException) {
      final msg = erro.message.trim();
      final details = erro.details?.toString().trim();
      final hint = erro.hint?.toString().trim();
      ultimoErroCodigo = erro.code;
      ultimoErroMensagem = msg.isEmpty ? null : msg;
      final parts = <String>[
        if (erro.code != null && erro.code!.trim().isNotEmpty)
          'code=${erro.code!.trim()}',
        if (msg.isNotEmpty) msg,
        if (details != null && details.isNotEmpty) 'details=$details',
        if (hint != null && hint.isNotEmpty) 'hint=$hint',
      ];
      ultimoErro = parts.join(' | ');
      return;
    }
    final texto = erro.toString().trim();
    ultimoErro = texto.isEmpty ? 'Erro desconhecido ao registrar solicitação.' : texto;
    ultimoErroMensagem = ultimoErro;
  }

  Future<List<ConfrontoSolicitacao>> listarAceitosPorMatchId(
    String matchId,
  ) async {
    try {
      final client = Supabase.instance.client;
      final rows = await client
          .from('confronto_solicitacoes')
          .select(_sel)
          .eq('match_id', matchId)
          .eq('status', 'ACEITO')
          .order('respondido_em', ascending: true);
      return (rows as List<dynamic>)
          .map(
            (e) => ConfrontoSolicitacao.tryParse(
              Map<String, dynamic>.from(e as Map<dynamic, dynamic>),
            ),
          )
          .whereType<ConfrontoSolicitacao>()
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<bool> confirmarAleatorio({
    required String matchId,
    required String requestIdConfirmado,
  }) async {
    try {
      final client = Supabase.instance.client;
      await client.functions.invoke(
        'confirmar_confronto_aleatorio',
        body: {
          'match_id': matchId,
          'request_id_confirmado': requestIdConfirmado,
        },
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> cancelarConfronto({
    required String solicitacaoId,
  }) async {
    try {
      final client = Supabase.instance.client;
      final limiteUtc = DateTime.now()
          .add(const Duration(hours: 12))
          .toUtc()
          .toIso8601String();
      await client
          .from('confronto_solicitacoes')
          .update({
            'status': 'CANCELADO',
            'respondido_em': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', solicitacaoId)
          .inFilter('status', ['ACEITO', 'CONFIRMADO'])
          .gte('data_hora', limiteUtc);
      final selected = await client
          .from('confronto_solicitacoes')
          .select('id,status')
          .eq('id', solicitacaoId)
          .maybeSingle();
      if (selected == null) return false;
      return (selected['status']?.toString() ?? '') == 'CANCELADO';
    } catch (_) {
      return false;
    }
  }

  Future<bool> cancelarSolicitacaoEnviada({
    required String solicitacaoId,
  }) async {
    try {
      final client = Supabase.instance.client;
      await client
          .from('confronto_solicitacoes')
          .update({
            'status': 'CANCELADO',
            'respondido_em': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', solicitacaoId)
          .eq('status', 'PENDENTE');
      final selected = await client
          .from('confronto_solicitacoes')
          .select('id,status')
          .eq('id', solicitacaoId)
          .maybeSingle();
      if (selected == null) return false;
      return (selected['status']?.toString() ?? '') == 'CANCELADO';
    } catch (_) {
      return false;
    }
  }

  static const _statusComBloqueio = ['PENDENTE', 'ACEITO', 'CONFIRMADO'];

  Future<List<ConfrontoSolicitacao>> listarOcupacoesPorLocalNoPeriodo({
    required String localChave,
    required DateTime desde,
    required DateTime ate,
    int? espacoNumero,
  }) async {
    final chave = localChave.trim().toLowerCase();
    if (chave.isEmpty) return [];
    try {
      final client = Supabase.instance.client;
      var query = client
          .from('confronto_solicitacoes')
          .select(_sel)
          .eq('local_chave', chave)
          .inFilter('status', _statusComBloqueio)
          .lt('data_hora', ate.toUtc().toIso8601String());
      if (espacoNumero != null) {
        query = query.eq('espaco_numero', espacoNumero);
      }
      final rows = await query;
      final parsed = (rows as List<dynamic>)
          .map(
            (e) => ConfrontoSolicitacao.tryParse(
              Map<String, dynamic>.from(e as Map<dynamic, dynamic>),
            ),
          )
          .whereType<ConfrontoSolicitacao>()
          .where((e) {
            final fim = e.dataFim ??
                e.dataHora.add(Duration(minutes: e.duracaoMinutos ?? 60));
            return fim.isAfter(desde);
          })
          .toList()
        ..sort((a, b) => a.dataHora.compareTo(b.dataHora));
      return parsed;
    } catch (_) {
      return [];
    }
  }
}
