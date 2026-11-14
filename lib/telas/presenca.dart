import 'package:flutter/material.dart';
import '../api.dart';
import '../comum.dart';

class TelaPresenca extends StatefulWidget {
  final Usuario usuario;
  const TelaPresenca({super.key, required this.usuario});

  @override
  State<TelaPresenca> createState() => _TelaPresencaState();
}

class _TelaPresencaState extends State<TelaPresenca> {
  DateTime _data = DateTime.now();
  List<Map<String, dynamic>> _setores = [];
  List<Map<String, dynamic>> _registros = [];
  bool _carregando = true;
  String? _erro;

  bool get _podeLancar =>
      !widget.usuario.ehMecanico && !widget.usuario.soConsulta;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  int _num(dynamic v) => v == null ? 0 : (v as num).toInt();

  Map<String, dynamic>? _registroDe(String setor) {
    for (final r in _registros) {
      if (r['setor'] == setor) return r;
    }
    return null;
  }

  int? _faltas(Map<String, dynamic>? r) {
    if (r == null) return null;
    if (r['faltas'] != null) return _num(r['faltas']);   // vale a falta lançada
    if (r['capacidade'] == null) return null;
    final f = _num(r['capacidade']) -
        _num(r['presentes']) -
        _num(r['atestados']) -
        _num(r['bh']) -
        _num(r['ferias']);
    return f < 0 ? 0 : f;
  }

  Future<void> _carregar() async {
    setState(() => _carregando = true);
    try {
      final dados =
          await Api.get('/api/presenca?data=${dataIso(_data)}') as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _setores = (dados['setores'] as List).cast<Map<String, dynamic>>();
        _registros = (dados['registros'] as List).cast<Map<String, dynamic>>();
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

  Future<void> _escolherData() async {
    final escolhida = await showDatePicker(
      context: context,
      initialDate: _data,
      firstDate: DateTime(2024),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      locale: const Locale('pt', 'BR'),
    );
    if (escolhida != null) {
      setState(() => _data = escolhida);
      _carregar();
    }
  }

  Future<void> _lancar(String setor) async {
    if (widget.usuario.ehMecanico || widget.usuario.soConsulta) return;
    final salvou = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (_) => _FormPresenca(
        data: _data,
        setor: setor,
        setores: _setores,
        registro: _registroDe(setor),
      ),
    );
    if (salvou == true) _carregar();
  }

  @override
  Widget build(BuildContext context) {
    final lancados = _setores.where((s) => _registroDe(s['nome'].toString()) != null).toList();
    final capLancada =
        lancados.fold<int>(0, (a, s) => a + _num(s['capacidade']));
    final presentes = lancados.fold<int>(
        0, (a, s) => a + _num(_registroDe(s['nome'].toString())?['presentes']));
    final faltas = lancados.fold<int>(
        0, (a, s) => a + (_faltas(_registroDe(s['nome'].toString())) ?? 0));
    final cobertura = capLancada == 0 ? null : (presentes / capLancada * 100).round();

    return Scaffold(
      backgroundColor: Cores.papel,
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _carregar,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 86),
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _escolherData,
                          icon: const Icon(Icons.calendar_today, size: 18),
                          label: Text(dataBr(_data)),
                          style: OutlinedButton.styleFrom(
                              minimumSize: const Size.fromHeight(46),
                              side: const BorderSide(color: Cores.linha),
                              foregroundColor: Cores.tinta),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text('${lancados.length} de ${_setores.length}',
                          style: const TextStyle(color: Cores.tinta2, fontSize: 13)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (_erro != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      child: Text(_erro!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Cores.vermelho)),
                    ),
                  Row(
                    children: [
                      _Indicador(valor: '$presentes', rotulo: 'Presentes'),
                      _Indicador(valor: '$faltas', rotulo: 'Faltas', alerta: faltas > 0),
                      _Indicador(
                          valor: cobertura == null ? '—' : '$cobertura%', rotulo: 'Cobertura'),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ..._setores.map((s) {
                    final nome = s['nome'].toString();
                    final r = _registroDe(nome);
                    final f = _faltas(r);
                    final cap = _num(s['capacidade']);
                    final cob = (r != null && cap > 0)
                        ? (_num(r['presentes']) / cap * 100).round()
                        : null;
                    return Card(
                      elevation: 0,
                      margin: const EdgeInsets.only(bottom: 6),
                      color: r == null ? const Color(0xFFFFFAF0) : Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                        side: const BorderSide(color: Cores.linha),
                      ),
                      child: ListTile(
                        dense: true,
                        visualDensity: VisualDensity.compact,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                        onTap: () => _lancar(nome),
                        title: Text(nome, style: const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: Text(
                          r == null
                              ? 'Ainda não lançado${_podeLancar ? ' — toque para lançar' : ''}'
                              : 'Capacidade $cap · presentes ${_num(r['presentes'])} · faltas ${f ?? 0}'
                                  '\nAtestados ${_num(r['atestados'])} · BH ${_num(r['bh'])} · férias ${_num(r['ferias'])}',
                          style: const TextStyle(fontSize: 13, height: 1.4),
                        ),
                        isThreeLine: r != null,
                        trailing: cob == null
                            ? const Icon(Icons.edit_outlined, color: Cores.tinta2)
                            : Text('$cob%',
                                style: TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w700,
                                    color: cob < 80 ? Cores.vermelho : Cores.verdeEsc)),
                      ),
                    );
                  }),
                  if (_setores.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('Cadastre os setores primeiro, na tela Cadastros.',
                          textAlign: TextAlign.center, style: TextStyle(color: Cores.tinta2)),
                    ),
                ],
              ),
            ),
    );
  }
}

class _Indicador extends StatelessWidget {
  final String valor;
  final String rotulo;
  final bool alerta;
  const _Indicador({required this.valor, required this.rotulo, this.alerta = false});

  @override
  Widget build(BuildContext context) => Expanded(
        child: Container(
          margin: const EdgeInsets.only(right: 6),
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 11),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Cores.linha),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(valor,
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: alerta ? Cores.vermelho : Cores.tinta)),
              Text(rotulo, style: const TextStyle(fontSize: 12.5, color: Cores.tinta2)),
            ],
          ),
        ),
      );
}

class _FormPresenca extends StatefulWidget {
  final DateTime data;
  final String setor;
  final List<Map<String, dynamic>> setores;
  final Map<String, dynamic>? registro;

  const _FormPresenca({
    required this.data,
    required this.setor,
    required this.setores,
    required this.registro,
  });

  @override
  State<_FormPresenca> createState() => _FormPresencaState();
}

class _FormPresencaState extends State<_FormPresenca> {
  late final TextEditingController _presentes;
  late final TextEditingController _faltas;
  late final TextEditingController _atestados;
  late final TextEditingController _bh;
  late final TextEditingController _ferias;
  late final TextEditingController _nomesFerias;
  late final TextEditingController _nomesBh;
  late final TextEditingController _obs;
  bool _enviando = false;

  String _txt(dynamic v) => v == null ? '0' : v.toString();

  @override
  void initState() {
    super.initState();
    final r = widget.registro;
    _presentes = TextEditingController(text: _txt(r?['presentes']));
    _faltas = TextEditingController(text: _txt(r?['faltas']));
    _atestados = TextEditingController(text: _txt(r?['atestados']));
    _bh = TextEditingController(text: _txt(r?['bh']));
    _ferias = TextEditingController(text: _txt(r?['ferias']));
    _nomesFerias = TextEditingController(text: r?['ferias_nomes']?.toString() ?? '');
    _nomesBh = TextEditingController(text: r?['bh_nomes']?.toString() ?? '');
    _obs = TextEditingController(text: r?['observacao']?.toString() ?? '');
  }

  @override
  void dispose() {
    for (final c in [_presentes, _faltas, _atestados, _bh, _ferias, _nomesFerias, _nomesBh, _obs]) {
      c.dispose();
    }
    super.dispose();
  }

  int? get _capacidade {
    for (final s in widget.setores) {
      if (s['nome'] == widget.setor) return s['capacidade'] as int?;
    }
    return null;
  }

  Future<void> _salvar() async {
    setState(() => _enviando = true);
    try {
      await Api.post('/api/presenca', {
        'data': dataIso(widget.data),
        'setor': widget.setor,
        'presentes': _presentes.text,
        'faltas': _faltas.text,
        'atestados': _atestados.text,
        'bh': _bh.text,
        'ferias': _ferias.text,
        'ferias_nomes': _nomesFerias.text,
        'bh_nomes': _nomesBh.text,
        'observacao': _obs.text,
      });
      if (!mounted) return;
      Navigator.pop(context, true);
      aviso(context, 'Presença salva');
    } on ErroApi catch (e) {
      if (mounted) {
        setState(() => _enviando = false);
        aviso(context, e.mensagem, erro: true);
      }
    }
  }

  Widget _numero(String rotulo, TextEditingController c) => Expanded(
        child: Padding(
          padding: const EdgeInsets.only(right: 8, bottom: 10),
          child: TextField(
            controller: c,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: rotulo),
            onChanged: (_) {
              // mexeu em presentes, atestados, BH ou férias? a falta se ajusta sozinha
              if (!identical(c, _faltas) && _capacidade != null) {
                final sobra = _capacidade! -
                    _v(_presentes) - _v(_atestados) - _v(_bh) - _v(_ferias);
                _faltas.text = (sobra < 0 ? 0 : sobra).toString();
              }
              setState(() {});
            },
          ),
        ),
      );

  int _v(TextEditingController c) => int.tryParse(c.text.trim()) ?? 0;

  @override
  Widget build(BuildContext context) {
    final cap = _capacidade;
    final usados = _v(_presentes) + _v(_faltas) + _v(_atestados) + _v(_bh) + _v(_ferias);
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 18, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('${widget.setor} · ${dataBr(widget.data)}',
                style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(
              cap == null
                  ? 'Capacidade não cadastrada para este setor.'
                  : 'Capacidade $cap · lançados $usados · faltas ${cap - usados < 0 ? 0 : cap - usados}',
              style: const TextStyle(color: Cores.tinta2),
            ),
            const SizedBox(height: 16),
            Row(children: [_numero('Presentes', _presentes), _numero('Faltas', _faltas)]),
            Row(children: [_numero('Atestados', _atestados), _numero('Banco de horas', _bh)]),
            Row(children: [_numero('Férias', _ferias), const Expanded(child: SizedBox())]),
            TextField(
              controller: _nomesFerias,
              decoration: const InputDecoration(
                  labelText: 'Quem está de férias', hintText: 'Ex.: João, Maria'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _nomesBh,
              decoration: const InputDecoration(labelText: 'Quem está de banco de horas'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _obs,
              maxLines: 2,
              maxLength: 600,
              decoration: const InputDecoration(labelText: 'Observação'),
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: _enviando ? null : _salvar,
              child: _enviando
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                  : const Text('Salvar presença'),
            ),
          ],
        ),
      ),
    );
  }
}
