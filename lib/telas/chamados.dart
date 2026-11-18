import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../api.dart';
import '../comum.dart';
import '../notificacoes.dart';
import '../parada.dart';
import '../seletor.dart';

class TelaChamados extends StatefulWidget {
  final Usuario usuario;
  const TelaChamados({super.key, required this.usuario});

  @override
  State<TelaChamados> createState() => _TelaChamadosState();
}

class _TelaChamadosState extends State<TelaChamados> with SingleTickerProviderStateMixin {
  static const _situacoes = ['ABERTO', 'ANDAMENTO', 'CONCLUIDO'];

  // a 4a aba (Relatório) só existe para quem acompanha os números
  late final TabController _abas =
      TabController(length: _situacoes.length, vsync: this);
  Timer? _timer;
  Timer? _relogio;

  List<Chamado> _chamados = [];
  Set<int> _vistos = {};
  bool _carregando = true;
  bool _primeira = true;
  String? _erro;
  String _busca = '';
  int _dias = 7;
  DateTimeRange? _intervalo;   // quando a pessoa escolhe datas

  // fechamento do dia: quanto tempo de máquina parada o grupo acumulou
  Parada? _parada;
  DateTime? _paradaDia;          // null = hoje
  DateTime? _paradaQuando;       // ultima busca, para nao pedir a cada poll
  List<Map<String, dynamic>> _mecanicos = [];   // buscados so quando precisa

  bool _podeTrocarMec(Chamado c) =>
      !widget.usuario.soConsulta &&
      (c.emAndamento || c.pausado) &&
      (widget.usuario.ehMecanico || widget.usuario.ehGestor);

  bool get _vePainelParada => !widget.usuario.ehMecanico;

  @override
  void initState() {
    super.initState();
    _carregar();
    _timer = Timer.periodic(const Duration(seconds: 15), (_) => _carregar(silencioso: true));
    // mantém os contadores de tempo andando sem bater no servidor
    _relogio = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _relogio?.cancel();
    _abas.dispose();
    super.dispose();
  }

  /// O painel é um extra: se falhar, a tela de chamados continua normal.
  Future<void> _carregarParadas({bool forcar = false}) async {
    if (!_vePainelParada) return;
    // o total do dia nao muda a cada 15s como os cartoes; pedir junto
    // com todo poll so enchia a fila do servidor.
    final agora = DateTime.now();
    if (!forcar &&
        _paradaQuando != null &&
        agora.difference(_paradaQuando!).inSeconds < 55) return;
    _paradaQuando = agora;
    final d = _paradaDia;
    final sufixo = d == null
        ? ''
        : '?data=${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    try {
      final dados = await Api.get('/api/paradas$sufixo') as Map<String, dynamic>;
      if (!mounted) return;
      setState(() => _parada = Parada.deJson(dados));
    } catch (_) {
      _paradaQuando = null;   // deixa tentar de novo no proximo ciclo
    }
  }

  Future<void> _carregar({bool silencioso = false}) async {
    if (!silencioso && mounted) setState(() => _carregando = true);
    try {
      final r = _intervalo;
      final q = r == null
          ? 'dias=$_dias'
          : 'de=${_iso(r.start)}&ate=${_iso(r.end)}';
      final dados = await Api.get('/api/chamados?$q') as Map<String, dynamic>;
      Relogio.sincronizar(dados['agora']?.toString());
      final lista = (dados['chamados'] as List)
          .map((e) => Chamado.deJson(e as Map<String, dynamic>))
          .toList();
      _avisarNovos(lista);
      if (!mounted) return;
      setState(() {
        _chamados = lista;
        _carregando = false;
        _erro = null;
      });
      if (_primeira) {
        _primeira = false;
        final meus = lista.any((c) => c.emAndamento && c.mecanicoId == widget.usuario.id);
        if (meus) _abas.animateTo(1);
      }
      _carregarParadas();
    } on ErroApi catch (e) {
      if (!mounted) return;
      setState(() {
        _carregando = false;
        _erro = e.mensagem;
      });
    }
  }

  void _avisarNovos(List<Chamado> lista) {
    final abertos = lista.where((c) => c.aberto).toList();
    if (_vistos.isNotEmpty && !widget.usuario.ehLider) {
      final novos = abertos.where((c) => !_vistos.contains(c.id)).toList();
      for (final c in novos.take(3)) {
        final marca = c.prio == Prioridade.parada ? '🔴 MÁQUINA PARADA · ' : '';
        Avisos.mostrar(c.id, '${marca}Chamado #${c.id} · ${c.maquinaCodigo}',
            <String?>[c.setor, c.defeito ?? c.problema]
                .whereType<String>()
                .where((x) => x.isNotEmpty)
                .join(' — '));
      }
      if (novos.isNotEmpty) HapticFeedback.heavyImpact();
    }
    _vistos = {..._vistos, ...lista.map((c) => c.id)};
  }

  List<Chamado> _filtrados(String situacao) {
    final q = _busca.trim().toLowerCase();
    final lista = _chamados.where((c) {
      // pausa não é uma fase à parte: o chamado segue em Andamento
      final bate = situacao == 'ANDAMENTO'
          ? (c.emAndamento || c.pausado)
          : c.status == situacao;
      if (!bate) return false;
      if (q.isEmpty) return true;
      final texto = [
        c.id,
        c.maquinaCodigo,
        c.maquinaDescricao,
        c.problema,
        c.defeito ?? '',
        c.solucao ?? '',
        c.funcionario ?? '',
        c.lider,
        c.mecanico ?? '',
        c.setor ?? '',
      ].join(' ').toLowerCase();
      return texto.contains(q);
    }).toList();

    if (situacao == 'ABERTO') {
      lista.sort((a, b) {
        final p = a.prio.peso.compareTo(b.prio.peso);
        return p != 0 ? p : a.abertura.compareTo(b.abertura);
      });
    } else if (situacao == 'ANDAMENTO') {
      lista.sort((a, b) {
        final meuA = a.mecanicoId == widget.usuario.id ? 0 : 1;
        final meuB = b.mecanicoId == widget.usuario.id ? 0 : 1;
        final p = meuA.compareTo(meuB);
        return p != 0 ? p : (a.inicio ?? a.abertura).compareTo(b.inicio ?? b.abertura);
      });
    } else {
      lista.sort((a, b) => (b.fim ?? b.abertura).compareTo(a.fim ?? a.abertura));
    }
    return lista;
  }

  bool get _podeAbrir => !widget.usuario.ehMecanico && !widget.usuario.soConsulta;
  bool _podeAtender(Chamado c) => !widget.usuario.soConsulta &&
      c.aberto && (widget.usuario.ehMecanico || widget.usuario.ehGestor);
  bool _podeConcluir(Chamado c) => !widget.usuario.soConsulta &&
      (c.emAndamento || c.pausado) &&
      (c.mecanicoId == widget.usuario.id || widget.usuario.ehGestor);

  // pausa é de quem está com a mão na máquina: só o mecânico dono do chamado
  bool _podePausar(Chamado c) =>
      c.emAndamento && widget.usuario.ehMecanico && c.mecanicoId == widget.usuario.id;
  bool _podeRetomar(Chamado c) =>
      c.pausado && widget.usuario.ehMecanico && c.mecanicoId == widget.usuario.id;
  bool _podeCancelar(Chamado c) => !widget.usuario.soConsulta &&
      c.aberto && (c.liderId == widget.usuario.id || widget.usuario.ehGestor);

  /// Passa o chamado para outro mecânico, ou devolve para a fila.
  /// A lista de mecânicos só é buscada quando alguém abre esta folha.
  Future<void> _pausar(Chamado c) async {
    String motivo = 'PECA';
    final obs = TextEditingController();
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (_) => StatefulBuilder(
        builder: (ctx, repinta) => Padding(
          padding: EdgeInsets.fromLTRB(
              18, 16, 18, MediaQuery.of(ctx).viewInsets.bottom + 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Pausar #${c.id}',
                  style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(
                  '${c.maquinaCodigo} ${c.maquinaDescricao}\n'
                  'A máquina continua contando como parada. A pausa só registra '
                  'que você não está nela.',
                  style: const TextStyle(color: Cores.tinta2, fontSize: 12.5, height: 1.35)),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                children: [
                  for (final e in MotivoPausa.curtos.entries)
                    ChoiceChip(
                      label: Text(e.value.replaceAll('\n', ' '),
                          style: const TextStyle(fontSize: 12.5)),
                      selected: motivo == e.key,
                      onSelected: (_) => repinta(() => motivo = e.key),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: obs,
                maxLength: 300,
                decoration: const InputDecoration(
                  labelText: 'Observação (opcional)',
                  hintText: 'Ex.: agulha 90, pedida ao almoxarifado',
                ),
              ),
              const SizedBox(height: 6),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  style: FilledButton.styleFrom(
                      backgroundColor: Cores.verdeEsc,
                      minimumSize: const Size.fromHeight(46)),
                  child: const Text('Pausar chamado'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    obs.dispose();
    if (ok != true) return;

    HapticFeedback.mediumImpact();
    try {
      await Api.post('/api/chamados/${c.id}/pausar',
          {'motivo': motivo, 'observacao': obs.text.trim()});
      if (mounted) {
        aviso(context, 'Chamado em pausa. O líder foi avisado.');
      }
    } on ErroApi catch (e) {
      if (mounted) aviso(context, e.mensagem, erro: true);
    }
    _paradaQuando = null;
    await _carregar(silencioso: true);
  }

  Future<void> _retomar(Chamado c) async {
    HapticFeedback.mediumImpact();
    try {
      await Api.post('/api/chamados/${c.id}/retomar');
      if (mounted) {
        aviso(context, 'Chamado retomado.');
      }
    } on ErroApi catch (e) {
      if (mounted) aviso(context, e.mensagem, erro: true);
    }
    _paradaQuando = null;
    await _carregar(silencioso: true);
  }

  Future<void> _trocarMecanico(Chamado c) async {
    if (_mecanicos.isEmpty) {
      try {
        final dados = await Api.get('/api/listas') as Map<String, dynamic>;
        _mecanicos = ((dados['mecanicos'] ?? []) as List).cast<Map<String, dynamic>>();
      } catch (_) {
        if (mounted) aviso(context, 'Não consegui buscar os mecânicos.', erro: true);
        return;
      }
    }
    if (!mounted) return;
    if (_mecanicos.isEmpty) {
      return aviso(context, 'Nenhum mecânico ativo cadastrado.', erro: true);
    }

    final escolha = await showModalBottomSheet<Object?>(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 2),
              child: Text('Mecânico do #${c.id}',
                  style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
              child: Text(
                  '${c.maquinaCodigo} ${c.maquinaDescricao}\n'
                  'Hoje: ${c.mecanico ?? 'ninguém — está na fila'}',
                  style: const TextStyle(color: Cores.tinta2, fontSize: 13)),
            ),
            const Divider(height: 1, color: Cores.linha),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final m in _mecanicos)
                    ListTile(
                      leading: const Icon(Icons.build_outlined, size: 20),
                      title: Text(m['nome'].toString()),
                      trailing: m['id'] == c.mecanicoId
                          ? const Icon(Icons.check, color: Cores.verdeEsc)
                          : null,
                      onTap: () => Navigator.pop(context, m['id']),
                    ),
                  if (c.mecanico != null)
                    ListTile(
                      leading: const Icon(Icons.undo, size: 20, color: Cores.vermelho),
                      title: const Text('Devolver para a fila',
                          style: TextStyle(color: Cores.vermelho)),
                      onTap: () => Navigator.pop(context, '__fila__'),
                    ),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(18, 8, 18, 14),
              child: Text('O tempo de parada não reinicia: continua contando desde a abertura.',
                  style: TextStyle(color: Cores.tinta2, fontSize: 12)),
            ),
          ],
        ),
      ),
    );
    if (escolha == null) return;
    if (escolha != '__fila__' && escolha == c.mecanicoId) return;

    HapticFeedback.mediumImpact();
    try {
      await Api.post('/api/chamados/${c.id}/mecanico',
          {'mecanico_id': escolha == '__fila__' ? null : escolha});
      if (mounted) {
        aviso(context,
            escolha == '__fila__' ? 'Chamado devolvido para a fila.' : 'Mecânico trocado.');
      }
    } on ErroApi catch (e) {
      if (mounted) aviso(context, e.mensagem, erro: true);
    }
    _paradaQuando = null;
    await _carregar(silencioso: true);
  }

  Future<void> _atender(Chamado c) async {
    HapticFeedback.mediumImpact();
    try {
      await Api.post('/api/chamados/${c.id}/atender');
      if (mounted) aviso(context, 'Chamado #${c.id} é seu. Bom trabalho!');
      _abas.animateTo(1);
    } on ErroApi catch (e) {
      if (mounted) aviso(context, e.mensagem, erro: true);
    }
    _paradaQuando = null;   // acao mudou os chamados: refaz a conta
    await _carregar(silencioso: true);
  }

  Future<void> _concluir(Chamado c) async {
    final solucao = await _pedirTexto(
      titulo: 'Concluir #${c.id}',
      subtitulo: '${c.maquinaCodigo} ${c.maquinaDescricao}\n${c.defeito ?? c.problema}',
      rotulo: 'O que foi feito?',
      dica: 'Ex.: troquei a correia e regulei a tensão',
      minimo: 5,
      botao: 'Concluir chamado',
    );
    if (solucao == null) return;
    HapticFeedback.mediumImpact();
    try {
      await Api.post('/api/chamados/${c.id}/concluir', {'solucao': solucao});
      if (mounted) aviso(context, 'Chamado #${c.id} concluído. Máquina de volta!');
    } on ErroApi catch (e) {
      if (mounted) aviso(context, e.mensagem, erro: true);
    }
    _paradaQuando = null;   // acao mudou os chamados: refaz a conta
    await _carregar(silencioso: true);
  }

  Future<void> _cancelar(Chamado c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Cancelar o chamado #${c.id}?'),
        content: const Text('Só dá para cancelar enquanto nenhum mecânico assumiu.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Voltar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Cores.vermelho),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Cancelar chamado'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await Api.post('/api/chamados/${c.id}/cancelar');
      if (mounted) aviso(context, 'Chamado #${c.id} cancelado');
    } on ErroApi catch (e) {
      if (mounted) aviso(context, e.mensagem, erro: true);
    }
    _paradaQuando = null;   // acao mudou os chamados: refaz a conta
    await _carregar(silencioso: true);
  }

  Future<String?> _pedirTexto({
    required String titulo,
    String? subtitulo,
    required String rotulo,
    required String dica,
    required int minimo,
    required String botao,
  }) async {
    final campo = TextEditingController();
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(20, 18, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(titulo, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
            if (subtitulo != null) ...[
              const SizedBox(height: 6),
              Text(subtitulo, style: const TextStyle(color: Cores.tinta2)),
            ],
            const SizedBox(height: 16),
            TextField(
              controller: campo,
              autofocus: true,
              maxLines: 4,
              maxLength: 2000,
              decoration: InputDecoration(labelText: rotulo, hintText: dica),
            ),
            const Text('Isso vira histórico da máquina e ajuda no próximo chamado parecido.',
                style: TextStyle(color: Cores.tinta2, fontSize: 13)),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () {
                if (campo.text.trim().length < minimo) {
                  aviso(ctx, 'Escreva o que você fez na máquina.', erro: true);
                  return;
                }
                Navigator.pop(ctx, campo.text.trim());
              },
              child: Text(botao),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _abrirNovo() async {
    final criado = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (ctx) => const FormNovoChamado(),
    );
    if (criado == true) {
      _abas.animateTo(0);
      _paradaQuando = null;   // acao mudou os chamados: refaz a conta
    await _carregar(silencioso: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final contagem = {for (final s in _situacoes) s: _filtrados(s).length};
    return Scaffold(
      backgroundColor: Cores.papel,
      floatingActionButton: _podeAbrir
          ? FloatingActionButton.extended(
              onPressed: _abrirNovo,
              backgroundColor: Cores.verdeEsc,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add),
              label: const Text('Abrir chamado',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            )
          : null,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 10, 4),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    onChanged: (v) => setState(() => _busca = v),
                    textInputAction: TextInputAction.search,
                    decoration: const InputDecoration(
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      prefixIcon: Icon(Icons.search, size: 19),
                      hintText: 'Buscar máquina, defeito ou nº',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                PopupMenuButton<int>(
                  tooltip: 'Período dos concluídos',
                  icon: Icon(Icons.filter_list,
                      color: _intervalo == null ? null : Cores.verdeEsc),
                  initialValue: _intervalo == null ? _dias : -1,
                  onSelected: (v) async {
                    if (v == -1) return _escolherIntervalo();
                    setState(() {
                      _dias = v;
                      _intervalo = null;
                    });
                    _carregar();
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 0, child: Text('Concluídos hoje')),
                    const PopupMenuItem(value: 7, child: Text('Últimos 7 dias')),
                    const PopupMenuItem(value: 30, child: Text('Últimos 30 dias')),
                    const PopupMenuItem(value: 90, child: Text('Últimos 90 dias')),
                    PopupMenuItem(
                      value: -1,
                      child: Text(_intervalo == null
                          ? 'Escolher datas…'
                          : '${_br(_intervalo!.start)} a ${_br(_intervalo!.end)}'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (_vePainelParada)
            PainelParada(
              parada: _parada,
              ehLider: widget.usuario.ehLider,
              aoTocar: _abrirRelatorio,
            ),
          Container(
            color: Colors.white,
            child: TabBar(
              controller: _abas,
              labelColor: Cores.tinta,
              indicatorColor: Cores.verdeEsc,
              indicatorWeight: 3,
              labelPadding: const EdgeInsets.symmetric(horizontal: 4),
              labelStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
              unselectedLabelStyle: const TextStyle(fontSize: 13.5),
              tabs: [
                for (final s in _situacoes)
                  Tab(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(Situacao.chamados[s]!.nome == 'Em andamento'
                            ? 'Andamento'
                            : Situacao.chamados[s]!.nome),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                          decoration: BoxDecoration(
                            color: Situacao.chamados[s]!.fundo,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text('${contagem[s]}',
                              style: TextStyle(
                                  color: Situacao.chamados[s]!.cor,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12.5)),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _abas,
              children: [for (final s in _situacoes) _lista(s)],
            ),
          ),
        ],
      ),
    );
  }

  static String _iso(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  static String _br(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';

  Future<void> _escolherIntervalo() async {
    final hoje = DateTime.now();
    final escolhido = await showDateRangePicker(
      context: context,
      firstDate: DateTime(hoje.year - 2),
      lastDate: hoje,
      initialDateRange: _intervalo ??
          DateTimeRange(start: hoje.subtract(const Duration(days: 6)), end: hoje),
      helpText: 'Período dos chamados',
      saveText: 'Aplicar',
    );
    if (escolhido == null) return;
    setState(() => _intervalo = escolhido);
    _carregar();
  }

  static Duration? _espera(Chamado c) =>
      c.inicio == null ? null : c.inicio!.difference(c.abertura);
  static Duration? _reparo(Chamado c) =>
      c.fim == null || c.inicio == null ? null : c.fim!.difference(c.inicio!);

  /// Média, em minutos, de uma medida sobre os chamados do período.
  int _mediaMin(Duration? Function(Chamado) medida) {
    final vals = _chamados.map(medida).whereType<Duration>().toList();
    if (vals.isEmpty) return 0;
    return vals.map((d) => d.inMinutes).reduce((a, b) => a + b) ~/ vals.length;
  }

  /// Soma, em minutos, da mesma medida.
  int _somaMin(Duration? Function(Chamado) medida) => _chamados
      .map(medida)
      .whereType<Duration>()
      .fold<int>(0, (a, d) => a + d.inMinutes);

  /// Relatório abre como tela própria, a partir do painel do topo.
  Future<void> _abrirRelatorio() async {
    if (_parada == null) await _carregarParadas(forcar: true);
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TelaRelatorio(
          parada: _parada,
          ehLider: widget.usuario.ehLider,
          mediaEspera: _mediaMin(_espera),
          mediaReparo: _mediaMin(_reparo),
          totalEspera: _somaMin(_espera),
          totalReparo: _somaMin(_reparo),
          aoPedirDia: (d) async {
            _paradaDia = d;
            _parada = null;
            await _carregarParadas(forcar: true);
            return _parada;
          },
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  Widget _lista(String situacao) {
    if (_carregando && _chamados.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_erro != null && _chamados.isEmpty) {
      return _SemConexao(mensagem: _erro!, aoTentar: _carregar);
    }
    final lista = _filtrados(situacao);
    return RefreshIndicator(
      onRefresh: _carregar,
      child: lista.isEmpty
          ? ListView(
              padding: const EdgeInsets.all(28),
              children: [
                const SizedBox(height: 40),
                Icon(
                  situacao == 'ABERTO' ? Icons.check_circle_outline : Icons.inbox_outlined,
                  size: 54,
                  color: Cores.linha,
                ),
                const SizedBox(height: 12),
                Text(
                  switch (situacao) {
                    'ABERTO' => 'Fila vazia',
                    'ANDAMENTO' => 'Ninguém em atendimento',
                    _ => 'Nada concluído no período',
                  },
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
                ),
                const SizedBox(height: 4),
                Text(
                  switch (situacao) {
                    'ABERTO' => 'Nenhuma máquina esperando mecânico.',
                    'ANDAMENTO' => 'Quando alguém assumir, aparece aqui.',
                    _ => 'Use o filtro para aumentar o período.',
                  },
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Cores.tinta2),
                ),
              ],
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 88),
              itemCount: lista.length,
              itemBuilder: (_, i) => _CartaoChamado(
                chamado: lista[i],
                podeAtender: _podeAtender(lista[i]),
                podeConcluir: _podeConcluir(lista[i]),
                podeCancelar: _podeCancelar(lista[i]),
                podeTrocarMec: _podeTrocarMec(lista[i]),
                podePausar: _podePausar(lista[i]),
                podeRetomar: _podeRetomar(lista[i]),
                aoAtender: () => _atender(lista[i]),
                aoConcluir: () => _concluir(lista[i]),
                aoCancelar: () => _cancelar(lista[i]),
                aoTrocarMec: () => _trocarMecanico(lista[i]),
                aoPausar: () => _pausar(lista[i]),
                aoRetomar: () => _retomar(lista[i]),
                mostrarLider: !widget.usuario.ehLider,
              ),
            ),
    );
  }
}

class _SemConexao extends StatelessWidget {
  final String mensagem;
  final Future<void> Function() aoTentar;
  const _SemConexao({required this.mensagem, required this.aoTentar});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off, size: 56, color: Cores.vermelho),
            const SizedBox(height: 14),
            const Text('Sem conexão com o servidor',
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(mensagem, textAlign: TextAlign.center, style: const TextStyle(color: Cores.tinta2)),
            const SizedBox(height: 10),
            const Text('Confira se o celular está no Wi-Fi da fábrica.',
                textAlign: TextAlign.center, style: TextStyle(color: Cores.tinta2)),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: () => aoTentar(),
              icon: const Icon(Icons.refresh),
              label: const Text('Tentar de novo'),
            ),
          ],
        ),
      ),
    );
  }
}

class _CartaoChamado extends StatefulWidget {
  final Chamado chamado;
  final bool podeAtender;
  final bool podeConcluir;
  final bool podeCancelar;
  final bool podeTrocarMec;
  final bool podePausar;
  final bool podeRetomar;
  final bool mostrarLider;
  final VoidCallback aoAtender;
  final VoidCallback aoConcluir;
  final VoidCallback aoCancelar;
  final VoidCallback aoTrocarMec;
  final VoidCallback aoPausar;
  final VoidCallback aoRetomar;

  const _CartaoChamado({
    required this.chamado,
    required this.podeAtender,
    required this.podeConcluir,
    required this.podeCancelar,
    required this.podeTrocarMec,
    required this.podePausar,
    required this.podeRetomar,
    required this.mostrarLider,
    required this.aoAtender,
    required this.aoConcluir,
    required this.aoCancelar,
    required this.aoTrocarMec,
    required this.aoPausar,
    required this.aoRetomar,
  });

  @override
  State<_CartaoChamado> createState() => _CartaoChamadoState();
}

class _CartaoChamadoState extends State<_CartaoChamado> {
  bool _aberto = false;

  @override
  Widget build(BuildContext context) {
    final c = widget.chamado;
    final situacao = Situacao.chamados[c.status]!;
    final emCurso = !c.concluido && c.status != 'CANCELADO';

    String tempo;
    Color corTempo = situacao.cor;
    if (c.aberto) {
      final d = Relogio.agora.difference(c.abertura);
      tempo = duracao(d);
      if (d.inMinutes > kAlertaMinutos) corTempo = Cores.vermelho;
    } else if (c.emAndamento) {
      tempo = duracao(Relogio.agora.difference(c.inicio ?? c.abertura));
    } else if (c.pausado) {
      // em pausa a maquina segue parada: conta desde a abertura
      tempo = duracao(Relogio.agora.difference(c.abertura));
      corTempo = Cores.roxo;
    } else {
      tempo = duracao((c.fim ?? c.abertura).difference(c.abertura));
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: emCurso && c.prio == Prioridade.parada ? Cores.vermelho : Cores.linha,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => setState(() => _aberto = !_aberto),
        child: Container(
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                color: c.pausado
                    ? Cores.roxo
                    : (emCurso ? c.prio.cor : situacao.cor),
                width: 5,
              ),
            ),
          ),
          padding: const EdgeInsets.fromLTRB(10, 7, 10, 7),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text('#${c.id}',
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                  if (emCurso && c.prio != Prioridade.baixa) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                          color: c.prio.cor, borderRadius: BorderRadius.circular(4)),
                      child: Text(c.prio.curto.toUpperCase(),
                          style: const TextStyle(
                              color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w700)),
                    ),
                  ],
                  if (c.pausado) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                          color: Cores.roxo, borderRadius: BorderRadius.circular(4)),
                      child: const Text('PAUSA',
                          style: TextStyle(
                              color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w700)),
                    ),
                  ],
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text.rich(
                      TextSpan(children: [
                        TextSpan(
                            text: c.maquinaCodigo,
                            style: const TextStyle(fontWeight: FontWeight.w700)),
                        TextSpan(
                            text: ' ${c.maquinaDescricao}',
                            style: const TextStyle(color: Cores.tinta2)),
                      ]),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 14),
                    ),
                  ),
                  Text(tempo,
                      style: TextStyle(
                          color: corTempo, fontWeight: FontWeight.w700, fontSize: 15.5)),
                  Icon(_aberto ? Icons.expand_less : Icons.expand_more,
                      size: 20, color: Cores.tinta2),
                ],
              ),
              const SizedBox(height: 3),
              Row(
                children: [
                  if (c.setor != null)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Text(c.setor!,
                          style: const TextStyle(
                              color: Cores.tinta2, fontWeight: FontWeight.w600, fontSize: 13)),
                    ),
                  Expanded(
                    child: Text(c.defeito ?? c.problema,
                        maxLines: _aberto ? 4 : 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13.5)),
                  ),
                  if (widget.podeAtender)
                    _BotaoMini(texto: 'Atender', cor: Cores.azul, aoTocar: widget.aoAtender)
                  else if (widget.podeRetomar)
                    _BotaoMini(texto: 'Retomar', cor: Cores.azul, aoTocar: widget.aoRetomar)
                  else if (widget.podeConcluir)
                    _BotaoMini(texto: 'Concluir', cor: Cores.verdeEsc, aoTocar: widget.aoConcluir)
                  else if (c.mecanico != null && !c.aberto)
                    Text(c.mecanico!.split(' ').first,
                        style: const TextStyle(
                            color: Cores.azul, fontWeight: FontWeight.w600, fontSize: 12.5)),
                ],
              ),
              if (!_aberto)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text('Ver ficha',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Cores.azul)),
                  ),
                ),
              if (_aberto) ...[
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Divider(height: 1, color: Cores.linha),
                ),
                if (c.defeito != null && c.problema.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(c.problema,
                        style: const TextStyle(color: Cores.tinta2, fontSize: 13.5)),
                  ),
                if (c.solucao != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text('Feito: ${c.solucao}',
                        style: const TextStyle(color: Cores.verdeEsc, fontSize: 13.5)),
                  ),
                if (c.pausado)
                  Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFE9FB),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.pause_circle_outline, size: 18, color: Cores.roxo),
                        const SizedBox(width: 7),
                        Expanded(
                          child: Text(
                              c.pausaNome +
                                  (c.pausaObs == null || c.pausaObs!.isEmpty
                                      ? ''
                                      : ' — ${c.pausaObs}'),
                              style: const TextStyle(
                                  color: Cores.roxo,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700)),
                        ),
                      ],
                    ),
                  ),
                _linha('Setor', c.setor ?? '—'),
                _linha('Defeito', c.defeito ?? '—'),
                _linha('Prioridade', c.prio.nome),
                _linha('Funcionário', c.funcionario ?? '—'),
                if (widget.mostrarLider) _linha('Líder', c.lider),
                if (!c.aberto) _linha('Mecânico', c.mecanico ?? '—'),
                _linha('Abertura', dataHora(c.abertura)),
                if (c.inicio != null)
                  _linha('Início',
                      '${dataHora(c.inicio)}  (espera ${duracao(c.inicio!.difference(c.abertura))})'),
                if (c.concluido && c.fim != null)
                  _linha('Fim',
                      '${dataHora(c.fim)}  (reparo ${duracao(c.fim!.difference(c.inicio ?? c.abertura))})'),
                if (widget.podePausar || widget.podeTrocarMec || widget.podeCancelar)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (widget.podePausar)
                        TextButton.icon(
                          onPressed: widget.aoPausar,
                          icon: const Icon(Icons.pause, size: 18),
                          label: const Text('Pausar'),
                        ),
                      if (widget.podeTrocarMec)
                        TextButton.icon(
                          onPressed: widget.aoTrocarMec,
                          icon: const Icon(Icons.swap_horiz, size: 18),
                          label: const Text('Trocar mecânico'),
                        ),
                      if (widget.podeCancelar)
                        TextButton(
                          onPressed: widget.aoCancelar,
                          child: const Text('Cancelar chamado',
                              style: TextStyle(color: Cores.vermelho)),
                        ),
                    ],
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _linha(String rotulo, String valor) => Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
                width: 84,
                child: Text(rotulo,
                    style: const TextStyle(color: Cores.tinta2, fontSize: 12.5))),
            Expanded(
                child: Text(valor,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
          ],
        ),
      );
}

class _BotaoMini extends StatelessWidget {
  final String texto;
  final Color cor;
  final VoidCallback aoTocar;
  const _BotaoMini({required this.texto, required this.cor, required this.aoTocar});

  @override
  Widget build(BuildContext context) => FilledButton(
        onPressed: aoTocar,
        style: FilledButton.styleFrom(
          backgroundColor: cor,
          minimumSize: const Size(0, 34),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          textStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
        ),
        child: Text(texto),
      );
}

/// Formulário de abertura: máquina, funcionário, problema e prioridade.
class FormNovoChamado extends StatefulWidget {
  const FormNovoChamado({super.key});
  @override
  State<FormNovoChamado> createState() => _FormNovoChamadoState();
}

class _FormNovoChamadoState extends State<FormNovoChamado> {
  List<Map<String, dynamic>> _maquinas = [];
  List<Map<String, dynamic>> _funcionarios = [];
  List<Map<String, dynamic>> _defeitos = [];
  List<String> _setores = [];
  int? _maquinaId;
  int? _funcionarioId;
  int? _defeitoId;
  String? _setor;
  String _prioridade = 'BAIXA';
  final _problema = TextEditingController();
  bool _enviando = false;
  bool _carregando = true;

  @override
  void initState() {
    super.initState();
    _carregarListas();
  }

  @override
  void dispose() {
    _problema.dispose();
    super.dispose();
  }

  List<Opcao> get _opcoesMaquina => _maquinas
      .map((m) => Opcao(m['id'] as int, '${m['codigo']} — ${m['descricao']}',
          m['setor']?.toString()))
      .toList();

  List<Opcao> get _opcoesFuncionario => _funcionarios
      .map((f) => Opcao(f['id'] as int, '${f['nome']}',
          [f['matricula'], f['setor']].where((x) => x != null).join(' · ')))
      .toList();

  List<Opcao> get _opcoesDefeito => _defeitos
      .map((d) => Opcao(d['id'] as int, '${d['nome']}', d['descricao']?.toString()))
      .toList();

  Opcao? _acha(List<Opcao> lista, Object? valor) {
    if (valor == null) return null;
    for (final o in lista) {
      if (o.valor == valor) return o;
    }
    return null;
  }

  Future<void> _carregarListas() async {
    try {
      final dados = await Api.get('/api/listas') as Map<String, dynamic>;
      setState(() {
        _maquinas = (dados['maquinas'] as List).cast<Map<String, dynamic>>();
        _funcionarios = (dados['funcionarios'] as List).cast<Map<String, dynamic>>();
        _defeitos = ((dados['defeitos'] ?? []) as List).cast<Map<String, dynamic>>();
        _setores = ((dados['setores'] ?? []) as List).map((s) => s['nome'].toString()).toList();
        _carregando = false;
      });
    } on ErroApi catch (e) {
      if (mounted) {
        setState(() => _carregando = false);
        aviso(context, e.mensagem, erro: true);
      }
    }
  }

  Future<void> _salvar() async {
    if (_maquinaId == null) return aviso(context, 'Escolha a máquina.', erro: true);
    if (_funcionarioId == null) return aviso(context, 'Escolha o funcionário.', erro: true);
    if (_defeitoId == null && _problema.text.trim().length < 3) {
      return aviso(context, 'Escolha o defeito ou descreva o problema.', erro: true);
    }
    if (_setor == null || _setor!.isEmpty) {
      return aviso(context, 'Escolha o setor do chamado.', erro: true);
    }
    setState(() => _enviando = true);
    try {
      final r = await Api.post('/api/chamados', {
        'maquina_id': _maquinaId,
        'funcionario_id': _funcionarioId,
        'defeito_id': _defeitoId,
        'setor': _setor ?? '',
        'problema': _problema.text.trim(),
        'prioridade': _prioridade,
      }) as Map<String, dynamic>;
      HapticFeedback.mediumImpact();
      if (!mounted) return;
      Navigator.pop(context, true);
      aviso(context, 'Chamado #${r['id']} aberto. Os mecânicos já foram avisados.');
    } on ErroApi catch (e) {
      if (mounted) {
        setState(() => _enviando = false);
        aviso(context, e.mensagem, erro: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 18, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: _carregando
          ? const SizedBox(height: 180, child: Center(child: CircularProgressIndicator()))
          : SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Abrir chamado',
                      style: TextStyle(fontSize: 23, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 16),
                  CampoBusca(
                    rotulo: 'Máquina',
                    dica: 'Toque para buscar por código ou nome',
                    opcoes: _opcoesMaquina,
                    escolhida: _acha(_opcoesMaquina, _maquinaId),
                    aoEscolher: (o) => setState(() {
                      _maquinaId = o?.valor as int?;
                      // o setor da máquina escolhida já entra preenchido
                      final m = _maquinas.firstWhere((x) => x['id'] == _maquinaId,
                          orElse: () => <String, dynamic>{});
                      final setorMaquina = m['setor']?.toString();
                      _setor = (setorMaquina != null && _setores.contains(setorMaquina))
                          ? setorMaquina
                          : null;
                    }),
                  ),
                  CampoBusca(
                    rotulo: 'Funcionário',
                    dica: 'Toque para buscar por nome ou matrícula',
                    opcoes: _opcoesFuncionario,
                    escolhida: _acha(_opcoesFuncionario, _funcionarioId),
                    aoEscolher: (o) => setState(() => _funcionarioId = o?.valor as int?),
                  ),
                  CampoBusca(
                    rotulo: 'Defeito',
                    dica: 'Toque para buscar o defeito',
                    opcoes: _opcoesDefeito,
                    escolhida: _acha(_opcoesDefeito, _defeitoId),
                    podeLimpar: true,
                    aoEscolher: (o) => setState(() => _defeitoId = o?.valor as int?),
                  ),
                  CampoBusca(
                    rotulo: 'Setor *',
                    dica: 'Escolha o setor',
                    opcoes: _setores.map((s) => Opcao(s, s)).toList(),
                    escolhida: _setor == null ? null : Opcao(_setor!, _setor!),
                    podeLimpar: false,
                    ajuda: _maquinaId == null
                        ? 'Escolha a máquina para preencher o setor.'
                        : _setor == null
                            ? 'Máquina sem setor cadastrado — escolha aqui.'
                            : null,
                    aoEscolher: (o) => setState(() => _setor = o?.valor as String?),
                  ),
                  if (_defeitos.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: Text('Cadastre os defeitos em Cadastros > Defeitos.',
                          style: TextStyle(color: Cores.tinta2, fontSize: 12.5)),
                    ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _problema,
                    maxLines: 2,
                    maxLength: 1000,
                    decoration: const InputDecoration(
                      labelText: 'Detalhe (opcional)',
                      hintText: 'Ex.: começou depois da troca de peça',
                    ),
                  ),
                  const Text('Prioridade',
                      style: TextStyle(fontWeight: FontWeight.w600, color: Cores.tinta2)),
                  const SizedBox(height: 8),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'PARADA', label: Text('Parada')),
                      ButtonSegment(value: 'ALTA', label: Text('Alta')),
                      ButtonSegment(value: 'BAIXA', label: Text('Baixa')),
                    ],
                    selected: {_prioridade},
                    onSelectionChanged: (s) => setState(() => _prioridade = s.first),
                  ),
                  const SizedBox(height: 18),
                  FilledButton(
                    onPressed: _enviando ? null : _salvar,
                    child: _enviando
                        ? const SizedBox(
                            height: 22,
                            width: 22,
                            child:
                                CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                        : const Text('Abrir chamado'),
                  ),
                ],
              ),
            ),
    );
  }
}
