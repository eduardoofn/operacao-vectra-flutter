import 'dart:async';
import 'package:flutter/material.dart';
import '../api.dart';
import '../comum.dart';

class TelaBalanceamento extends StatefulWidget {
  final Usuario usuario;
  const TelaBalanceamento({super.key, required this.usuario});

  @override
  State<TelaBalanceamento> createState() => _TelaBalanceamentoState();
}

class _TelaBalanceamentoState extends State<TelaBalanceamento>
    with SingleTickerProviderStateMixin {
  static const _situacoes = ['ABERTO', 'ANDAMENTO', 'CONCLUIDO'];
  late final TabController _abas = TabController(length: 3, vsync: this);
  Timer? _timer;

  List<Balanceamento> _itens = [];
  bool _carregando = true;
  String? _erro;
  int _dias = 30;

  bool get _podeSolicitar => !widget.usuario.soConsulta &&
      (widget.usuario.ehLider || widget.usuario.ehGestor);
  bool get _podeAtender => !widget.usuario.soConsulta &&
      (widget.usuario.ehEngenharia || widget.usuario.ehGestor);

  @override
  void initState() {
    super.initState();
    _carregar();
    _timer = Timer.periodic(const Duration(seconds: 20), (_) => _carregar(silencioso: true));
  }

  @override
  void dispose() {
    _timer?.cancel();
    _abas.dispose();
    super.dispose();
  }

  Future<void> _carregar({bool silencioso = false}) async {
    if (!silencioso && mounted) setState(() => _carregando = true);
    try {
      final dados = await Api.get('/api/balanceamentos?dias=$_dias') as Map<String, dynamic>;
      Relogio.sincronizar(dados['agora']?.toString());
      if (!mounted) return;
      setState(() {
        _itens = (dados['balanceamentos'] as List)
            .map((e) => Balanceamento.deJson(e as Map<String, dynamic>))
            .toList();
        _carregando = false;
        _erro = null;
      });
    } on ErroApi catch (e) {
      if (!mounted) return;
      setState(() {
        _carregando = false;
        _erro = e.mensagem;
      });
    }
  }

  List<Balanceamento> _da(String situacao) {
    final lista = _itens.where((b) => b.status == situacao).toList();
    lista.sort((a, b) {
      final p = (a.alta ? 0 : 1).compareTo(b.alta ? 0 : 1);
      if (p != 0) return p;
      return (a.necessidadeEm ?? a.abertura).compareTo(b.necessidadeEm ?? b.abertura);
    });
    return lista;
  }

  Future<void> _assumir(Balanceamento b) async {
    try {
      await Api.post('/api/balanceamentos/${b.id}/atender');
      if (mounted) aviso(context, 'Solicitação #${b.id} assumida');
      _abas.animateTo(1);
    } on ErroApi catch (e) {
      if (mounted) aviso(context, e.mensagem, erro: true);
    }
    await _carregar(silencioso: true);
  }

  Future<void> _atender(Balanceamento b) async {
    final campo = TextEditingController();
    final resposta = await showModalBottomSheet<String>(
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
            Text('Atender balanceamento #${b.id}',
                style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w700)),
            const SizedBox(height: 14),
            TextField(
              controller: campo,
              autofocus: true,
              maxLines: 4,
              maxLength: 800,
              decoration: const InputDecoration(
                labelText: 'O que foi feito?',
                hintText: 'Ex.: remanejei 3 costureiras do Corte a partir das 13h',
              ),
            ),
            FilledButton(
              onPressed: () {
                if (campo.text.trim().length < 5) {
                  aviso(ctx, 'Descreva o que foi feito.', erro: true);
                  return;
                }
                Navigator.pop(ctx, campo.text.trim());
              },
              child: const Text('Marcar como atendido'),
            ),
          ],
        ),
      ),
    );
    if (resposta == null) return;
    try {
      await Api.post('/api/balanceamentos/${b.id}/concluir', {'resposta': resposta});
      if (mounted) aviso(context, 'Solicitação #${b.id} atendida');
    } on ErroApi catch (e) {
      if (mounted) aviso(context, e.mensagem, erro: true);
    }
    await _carregar(silencioso: true);
  }

  Future<void> _solicitar() async {
    final criou = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (_) => const _FormBalanceamento(),
    );
    if (criou == true) {
      _abas.animateTo(0);
      await _carregar(silencioso: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Cores.papel,
      floatingActionButton: _podeSolicitar
          ? FloatingActionButton.extended(
              onPressed: _solicitar,
              backgroundColor: Cores.verdeEsc,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add),
              label: const Text('Solicitar',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            )
          : null,
      body: Column(
        children: [
          Container(
            color: Colors.white,
            child: TabBar(
              controller: _abas,
              labelColor: Cores.tinta,
              indicatorColor: Cores.verdeEsc,
              indicatorWeight: 3,
              tabs: [
                for (final s in _situacoes)
                  Tab(text: '${Situacao.balanceamento[s]!.nome} (${_da(s).length})'),
              ],
            ),
          ),
          Expanded(
            child: _carregando && _itens.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : TabBarView(
                    controller: _abas,
                    children: [for (final s in _situacoes) _lista(s)],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _lista(String situacao) {
    final lista = _da(situacao);
    if (_erro != null && _itens.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.wifi_off, size: 48, color: Cores.vermelho),
              const SizedBox(height: 12),
              Text(_erro!, textAlign: TextAlign.center),
              const SizedBox(height: 14),
              FilledButton(onPressed: _carregar, child: const Text('Tentar de novo')),
            ],
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _carregar,
      child: lista.isEmpty
          ? ListView(
              children: const [
                SizedBox(height: 80),
                Icon(Icons.balance_outlined, size: 52, color: Cores.linha),
                SizedBox(height: 12),
                Center(
                  child: Text('Nada por aqui',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
                ),
              ],
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 88),
              itemCount: lista.length,
              itemBuilder: (_, i) {
                final b = lista[i];
                final situacaoCor = Situacao.balanceamento[b.status]!;
                final atrasado = b.necessidadeEm != null &&
                    !b.status.contains('CONCLUIDO') &&
                    b.necessidadeEm!.isBefore(Relogio.agora);
                return Card(
                  elevation: 0,
                  margin: const EdgeInsets.only(bottom: 6),
                  color: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                    side: const BorderSide(color: Cores.linha),
                  ),
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border(
                        left: BorderSide(
                            color: b.alta && b.status != 'CONCLUIDO'
                                ? Cores.ambar
                                : situacaoCor.cor,
                            width: 5),
                      ),
                    ),
                    padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text('#${b.id}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700, fontSize: 16)),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text('${b.setor} · ${b.produto}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 14)),
                            ),
                            Text(dataHora(b.necessidadeEm),
                                style: TextStyle(
                                    color: atrasado ? Cores.vermelho : situacaoCor.cor,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14)),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          [
                            if (b.quantidade != null) '${b.quantidade} pç',
                            if (b.costureiros != null) '${b.costureiros} costureiros',
                            if (b.manuais != null) '${b.manuais} manuais',
                          ].join(' · '),
                          style: const TextStyle(color: Cores.tinta2, fontSize: 13),
                        ),
                        if (b.observacao != null && b.observacao!.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(b.observacao!, style: const TextStyle(fontSize: 13.5)),
                          ),
                        if (b.resposta != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text('Engenharia: ${b.resposta}',
                                style:
                                    const TextStyle(color: Cores.verdeEsc, fontSize: 13.5)),
                          ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Pedido por ${b.lider}${b.engenharia != null ? ' · ${b.engenharia}' : ''}',
                                style: const TextStyle(color: Cores.tinta2, fontSize: 12.5),
                              ),
                            ),
                            if (b.status == 'ABERTO' && _podeAtender)
                              FilledButton(
                                onPressed: () => _assumir(b),
                                style: FilledButton.styleFrom(
                                    backgroundColor: Cores.azul,
                                    minimumSize: const Size(0, 34),
                                    padding: const EdgeInsets.symmetric(horizontal: 14)),
                                child: const Text('Assumir'),
                              )
                            else if (b.status == 'ANDAMENTO' && _podeAtender)
                              FilledButton(
                                onPressed: () => _atender(b),
                                style: FilledButton.styleFrom(
                                    minimumSize: const Size(0, 34),
                                    padding: const EdgeInsets.symmetric(horizontal: 14)),
                                child: const Text('Atendido'),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}

class _FormBalanceamento extends StatefulWidget {
  const _FormBalanceamento();
  @override
  State<_FormBalanceamento> createState() => _FormBalanceamentoState();
}

class _FormBalanceamentoState extends State<_FormBalanceamento> {
  List<String> _setores = [];
  String? _setor;
  String _necessidade = 'BAIXA';
  DateTime _quando = DateTime.now().add(const Duration(hours: 2));
  final _produto = TextEditingController();
  final _qtd = TextEditingController();
  final _costureiros = TextEditingController();
  final _manuais = TextEditingController();
  final _obs = TextEditingController();
  bool _enviando = false;

  @override
  void initState() {
    super.initState();
    _carregarSetores();
  }

  @override
  void dispose() {
    for (final c in [_produto, _qtd, _costureiros, _manuais, _obs]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _carregarSetores() async {
    try {
      final dados = await Api.get('/api/listas') as Map<String, dynamic>;
      setState(() {
        _setores = (dados['setores'] as List).map((s) => s['nome'].toString()).toList();
        if (_setores.isNotEmpty) _setor = _setores.first;
      });
    } catch (_) {}
  }

  Future<void> _escolherQuando() async {
    final dia = await showDatePicker(
      context: context,
      initialDate: _quando,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 90)),
      locale: const Locale('pt', 'BR'),
    );
    if (dia == null || !mounted) return;
    final hora = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_quando),
    );
    if (hora == null) return;
    setState(() =>
        _quando = DateTime(dia.year, dia.month, dia.day, hora.hour, hora.minute));
  }

  Future<void> _salvar() async {
    if (_setor == null) return aviso(context, 'Escolha o setor.', erro: true);
    if (_produto.text.trim().length < 2) {
      return aviso(context, 'Informe o produto.', erro: true);
    }
    setState(() => _enviando = true);
    try {
      final r = await Api.post('/api/balanceamentos', {
        'setor': _setor,
        'produto': _produto.text.trim(),
        'necessidade': _necessidade,
        'dt_necessidade':
            '${dataIso(_quando)}T${_quando.hour.toString().padLeft(2, '0')}:${_quando.minute.toString().padLeft(2, '0')}',
        'quantidade': _qtd.text,
        'costureiros': _costureiros.text,
        'manuais': _manuais.text,
        'observacao': _obs.text.trim(),
      }) as Map<String, dynamic>;
      if (!mounted) return;
      Navigator.pop(context, true);
      aviso(context, 'Solicitação #${r['id']} enviada para a Engenharia');
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
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Solicitar balanceamento',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: _setor,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Setor'),
              items: _setores.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
              onChanged: (v) => setState(() => _setor = v),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _produto,
              maxLength: 120,
              decoration: const InputDecoration(
                  labelText: 'Produto', hintText: 'Ex.: Camisa modelo X'),
            ),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'ALTA', label: Text('Alta')),
                ButtonSegment(value: 'BAIXA', label: Text('Baixa')),
              ],
              selected: {_necessidade},
              onSelectionChanged: (s) => setState(() => _necessidade = s.first),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _escolherQuando,
              icon: const Icon(Icons.schedule, size: 18),
              label: Text('Precisa em ${dataHora(_quando)}'),
              style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  side: const BorderSide(color: Cores.linha),
                  foregroundColor: Cores.tinta),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _qtd,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Peças'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _costureiros,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Costureiros'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _manuais,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Manuais'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _obs,
              maxLines: 3,
              maxLength: 800,
              decoration: const InputDecoration(labelText: 'Observação'),
            ),
            FilledButton(
              onPressed: _enviando ? null : _salvar,
              child: _enviando
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                  : const Text('Solicitar'),
            ),
          ],
        ),
      ),
    );
  }
}
