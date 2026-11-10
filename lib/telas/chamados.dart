import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../api.dart';
import '../comum.dart';
import '../notificacoes.dart';

class TelaChamados extends StatefulWidget {
  final Usuario usuario;
  const TelaChamados({super.key, required this.usuario});

  @override
  State<TelaChamados> createState() => _TelaChamadosState();
}

class _TelaChamadosState extends State<TelaChamados> with SingleTickerProviderStateMixin {
  static const _situacoes = ['ABERTO', 'ANDAMENTO', 'CONCLUIDO'];

  late final TabController _abas = TabController(length: 3, vsync: this);
  Timer? _timer;
  Timer? _relogio;

  List<Chamado> _chamados = [];
  Set<int> _vistos = {};
  bool _carregando = true;
  bool _primeira = true;
  String? _erro;
  String _busca = '';
  int _dias = 7;

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

  Future<void> _carregar({bool silencioso = false}) async {
    if (!silencioso && mounted) setState(() => _carregando = true);
    try {
      final dados = await Api.get('/api/chamados?dias=$_dias') as Map<String, dynamic>;
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
      if (c.status != situacao) return false;
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

  bool get _podeAbrir => !widget.usuario.ehMecanico;
  bool _podeAtender(Chamado c) =>
      c.aberto && (widget.usuario.ehMecanico || widget.usuario.ehGestor);
  bool _podeConcluir(Chamado c) =>
      c.emAndamento && (c.mecanicoId == widget.usuario.id || widget.usuario.ehGestor);
  bool _podeCancelar(Chamado c) =>
      c.aberto && (c.liderId == widget.usuario.id || widget.usuario.ehGestor);

  Future<void> _atender(Chamado c) async {
    HapticFeedback.mediumImpact();
    try {
      await Api.post('/api/chamados/${c.id}/atender');
      if (mounted) aviso(context, 'Chamado #${c.id} é seu. Bom trabalho!');
      _abas.animateTo(1);
    } on ErroApi catch (e) {
      if (mounted) aviso(context, e.mensagem, erro: true);
    }
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
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    onChanged: (v) => setState(() => _busca = v),
                    decoration: const InputDecoration(
                      isDense: true,
                      prefixIcon: Icon(Icons.search, size: 20),
                      hintText: 'Buscar máquina, problema ou nº',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                PopupMenuButton<int>(
                  tooltip: 'Período dos concluídos',
                  icon: const Icon(Icons.filter_list),
                  initialValue: _dias,
                  onSelected: (v) {
                    setState(() => _dias = v);
                    _carregar();
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 0, child: Text('Concluídos hoje')),
                    PopupMenuItem(value: 7, child: Text('Últimos 7 dias')),
                    PopupMenuItem(value: 30, child: Text('Últimos 30 dias')),
                    PopupMenuItem(value: 90, child: Text('Últimos 90 dias')),
                  ],
                ),
              ],
            ),
          ),
          Container(
            color: Colors.white,
            child: TabBar(
              controller: _abas,
              labelColor: Cores.tinta,
              indicatorColor: Cores.verdeEsc,
              indicatorWeight: 3,
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
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 90),
              itemCount: lista.length,
              itemBuilder: (_, i) => _CartaoChamado(
                chamado: lista[i],
                podeAtender: _podeAtender(lista[i]),
                podeConcluir: _podeConcluir(lista[i]),
                podeCancelar: _podeCancelar(lista[i]),
                aoAtender: () => _atender(lista[i]),
                aoConcluir: () => _concluir(lista[i]),
                aoCancelar: () => _cancelar(lista[i]),
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
  final bool mostrarLider;
  final VoidCallback aoAtender;
  final VoidCallback aoConcluir;
  final VoidCallback aoCancelar;

  const _CartaoChamado({
    required this.chamado,
    required this.podeAtender,
    required this.podeConcluir,
    required this.podeCancelar,
    required this.mostrarLider,
    required this.aoAtender,
    required this.aoConcluir,
    required this.aoCancelar,
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
    } else {
      tempo = duracao((c.fim ?? c.abertura).difference(c.abertura));
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
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
                color: emCurso ? c.prio.cor : situacao.cor,
                width: 5,
              ),
            ),
          ),
          padding: const EdgeInsets.fromLTRB(11, 9, 11, 9),
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
                  else if (widget.podeConcluir)
                    _BotaoMini(texto: 'Concluir', cor: Cores.verdeEsc, aoTocar: widget.aoConcluir)
                  else if (c.mecanico != null && !c.aberto)
                    Text(c.mecanico!.split(' ').first,
                        style: const TextStyle(
                            color: Cores.azul, fontWeight: FontWeight.w600, fontSize: 12.5)),
                ],
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
                _linha('Defeito', c.defeito ?? '—'),
                _linha('Prioridade', c.prio.nome),
                _linha('Funcionário', c.funcionario ?? '—'),
                if (widget.mostrarLider) _linha('Líder', c.lider),
                _linha('Mecânico', c.mecanico ?? '—'),
                _linha('Abertura', dataHora(c.abertura)),
                if (c.inicio != null)
                  _linha('Início',
                      '${dataHora(c.inicio)}  (espera ${duracao(c.inicio!.difference(c.abertura))})'),
                if (c.concluido && c.fim != null)
                  _linha('Fim',
                      '${dataHora(c.fim)}  (reparo ${duracao(c.fim!.difference(c.inicio ?? c.abertura))})'),
                if (widget.podeCancelar)
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: widget.aoCancelar,
                      child: const Text('Cancelar chamado',
                          style: TextStyle(color: Cores.vermelho)),
                    ),
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
                width: 92,
                child: Text(rotulo,
                    style: const TextStyle(color: Cores.tinta2, fontSize: 13))),
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
  int? _maquinaId;
  int? _funcionarioId;
  int? _defeitoId;
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

  Future<void> _carregarListas() async {
    try {
      final dados = await Api.get('/api/listas') as Map<String, dynamic>;
      setState(() {
        _maquinas = (dados['maquinas'] as List).cast<Map<String, dynamic>>();
        _funcionarios = (dados['funcionarios'] as List).cast<Map<String, dynamic>>();
        _defeitos = ((dados['defeitos'] ?? []) as List).cast<Map<String, dynamic>>();
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
    setState(() => _enviando = true);
    try {
      final r = await Api.post('/api/chamados', {
        'maquina_id': _maquinaId,
        'funcionario_id': _funcionarioId,
        'defeito_id': _defeitoId,
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
                  DropdownButtonFormField<int>(
                    value: _maquinaId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Máquina'),
                    items: _maquinas
                        .map((m) => DropdownMenuItem(
                              value: m['id'] as int,
                              child: Text('${m['codigo']} — ${m['descricao']}',
                                  overflow: TextOverflow.ellipsis),
                            ))
                        .toList(),
                    onChanged: (v) => setState(() => _maquinaId = v),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    value: _funcionarioId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Funcionário'),
                    items: _funcionarios
                        .map((f) => DropdownMenuItem(
                              value: f['id'] as int,
                              child: Text('${f['nome']}', overflow: TextOverflow.ellipsis),
                            ))
                        .toList(),
                    onChanged: (v) => setState(() => _funcionarioId = v),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    value: _defeitoId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Defeito'),
                    items: _defeitos
                        .map((d) => DropdownMenuItem(
                              value: d['id'] as int,
                              child: Text('${d['nome']}', overflow: TextOverflow.ellipsis),
                            ))
                        .toList(),
                    onChanged: (v) => setState(() => _defeitoId = v),
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
