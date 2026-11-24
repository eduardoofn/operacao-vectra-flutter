import 'package:flutter/material.dart';
import '../api.dart';
import '../comum.dart';
import '../parada.dart' show horas;

/// Painel dos chamados: volume, tempos e os campeões de parada.
/// Os gráficos são desenhados à mão — nada de biblioteca, o celular
/// do chão de fábrica não precisa baixar mais nada.
class TelaDash extends StatefulWidget {
  final Usuario usuario;
  const TelaDash({super.key, required this.usuario});

  @override
  State<TelaDash> createState() => _TelaDashState();
}

class _TelaDashState extends State<TelaDash> {
  Map<String, dynamic>? _d;
  bool _carregando = true;
  String? _erro;
  int _dias = 30;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() {
      _carregando = _d == null;
      _erro = null;
    });
    try {
      final r = await Api.get('/api/dash?dias=$_dias') as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _d = r;
        _carregando = false;
      });
    } on ErroApi catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = e.mensagem;
        _carregando = false;
      });
    }
  }

  int _i(Object? v) => v is int ? v : int.tryParse('${v ?? 0}') ?? 0;

  List<_Fatia> _lista(String chave, {bool porMinutos = false}) {
    final bruto = (_d?[chave] ?? []) as List;
    return bruto
        .map((e) => _Fatia(
              (e['nome'] ?? '').toString(),
              _i(porMinutos ? e['minutos'] : e['chamados']),
              porMinutos ? horas(_i(e['minutos'])) : '${_i(e['chamados'])}',
            ))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    if (_carregando) return const Center(child: CircularProgressIndicator());
    if (_erro != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(_erro!, textAlign: TextAlign.center,
                style: const TextStyle(color: Cores.tinta2)),
            const SizedBox(height: 12),
            FilledButton(onPressed: _carregar, child: const Text('Tentar de novo')),
          ]),
        ),
      );
    }
    final d = _d!;
    final dias = ((d['por_dia'] ?? []) as List).cast<Map<String, dynamic>>();

    return RefreshIndicator(
      onRefresh: _carregar,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 90),
        children: [
          _seletorPeriodo(d),
          const SizedBox(height: 12),
          _numeros(d),
          const SizedBox(height: 14),
          if (dias.isNotEmpty) ...[
            _caixa('Chamados por dia', _colunas(dias)),
            const SizedBox(height: 12),
          ],
          _caixa('Defeitos que mais aparecem', _barras(_lista('por_defeito'))),
          const SizedBox(height: 12),
          _caixa('Máquinas que mais param',
              _barras(_lista('por_maquina', porMinutos: true))),
          const SizedBox(height: 12),
          _caixa('Por setor', _barras(_lista('por_setor'))),
          const SizedBox(height: 12),
          _caixa('Atendimentos por mecânico', _barras(_lista('por_mecanico'))),
        ],
      ),
    );
  }

  Widget _seletorPeriodo(Map<String, dynamic> d) => Row(
        children: [
          const Text('Período',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
          const SizedBox(width: 10),
          DropdownButton<int>(
            value: _dias,
            underline: const SizedBox.shrink(),
            style: const TextStyle(fontSize: 14, color: Cores.tinta),
            items: const [
              DropdownMenuItem(value: 7, child: Text('Últimos 7 dias')),
              DropdownMenuItem(value: 30, child: Text('Últimos 30 dias')),
              DropdownMenuItem(value: 90, child: Text('Últimos 90 dias')),
              DropdownMenuItem(value: 180, child: Text('Últimos 6 meses')),
            ],
            onChanged: (v) {
              if (v == null) return;
              setState(() => _dias = v);
              _carregar();
            },
          ),
        ],
      );

  Widget _numeros(Map<String, dynamic> d) {
    final abertos = _i(d['abertos_agora']), parados = _i(d['parados_agora']);
    return Column(
      children: [
        _caixaCrua(Row(children: [
          _num('${_i(d['total'])}', 'no período'),
          _risco(),
          _num('$abertos', 'em aberto', cor: abertos > 0 ? Cores.ambar : null),
          _risco(),
          _num('$parados', 'paradas', cor: parados > 0 ? Cores.vermelho : null),
        ])),
        const SizedBox(height: 8),
        _caixaCrua(Row(children: [
          _num(horas(_i(d['media_espera'])), 'espera média'),
          _risco(),
          _num(horas(_i(d['media_reparo'])), 'reparo médio'),
          _risco(),
          _num(horas(_i(d['media_total'])), 'atendimento'),
        ])),
      ],
    );
  }

  Widget _num(String valor, String rotulo, {Color? cor}) => Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(valor,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 19, fontWeight: FontWeight.w800, color: cor ?? Cores.tinta)),
            Text(rotulo,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11.5, color: Cores.tinta2)),
          ],
        ),
      );

  Widget _risco() => Container(
      width: 1, height: 30, color: Cores.linha, margin: const EdgeInsets.only(right: 10));

  Widget _caixaCrua(Widget filho) => Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Cores.linha),
        ),
        child: filho,
      );

  Widget _caixa(String titulo, Widget filho) => _caixaCrua(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(titulo.toUpperCase(),
                style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: Cores.tinta2,
                    letterSpacing: .5)),
            const SizedBox(height: 10),
            filho,
          ],
        ),
      );

  Widget _barras(List<_Fatia> itens) {
    if (itens.isEmpty) {
      return const Text('Sem dados no período.',
          style: TextStyle(color: Cores.tinta2, fontSize: 13));
    }
    final maior = itens.map((e) => e.valor).reduce((a, b) => a > b ? a : b);
    return Column(
      children: [
        for (final i in itens)
          Padding(
            padding: const EdgeInsets.only(bottom: 7),
            child: Row(
              children: [
                SizedBox(
                  width: 112,
                  child: Text(i.nome,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13)),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: SizedBox(
                      height: 13,
                      child: LayoutBuilder(
                        builder: (_, c) => Row(children: [
                          Container(
                            width: c.maxWidth * (maior == 0 ? 0 : i.valor / maior),
                            color: Cores.verde,
                          ),
                          Expanded(child: Container(color: Cores.linha)),
                        ]),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 54,
                  child: Text(i.texto,
                      textAlign: TextAlign.right,
                      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _colunas(List<Map<String, dynamic>> dias) {
    final ultimos = dias.length > 30 ? dias.sublist(dias.length - 30) : dias;
    final maior = ultimos
        .map((e) => _i(e['chamados']))
        .fold<int>(1, (a, b) => a > b ? a : b);
    String br(String iso) {
      final p = iso.split('-');
      return p.length == 3 ? '${p[2]}/${p[1]}' : iso;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 110,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final d in ultimos)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 1),
                    child: Stack(
                      alignment: Alignment.bottomCenter,
                      children: [
                        FractionallySizedBox(
                          heightFactor: _i(d['chamados']) / maior,
                          child: Container(
                            decoration: const BoxDecoration(
                              color: Cores.verde,
                              borderRadius:
                                  BorderRadius.vertical(top: Radius.circular(2)),
                            ),
                          ),
                        ),
                        FractionallySizedBox(
                          heightFactor: _i(d['paradas']) / maior,
                          child: Container(
                            decoration: const BoxDecoration(
                              color: Cores.vermelho,
                              borderRadius:
                                  BorderRadius.vertical(top: Radius.circular(2)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(br(ultimos.first['dia'].toString()),
                style: const TextStyle(fontSize: 11, color: Cores.tinta2)),
            Text(br(ultimos.last['dia'].toString()),
                style: const TextStyle(fontSize: 11, color: Cores.tinta2)),
          ],
        ),
        const SizedBox(height: 6),
        Row(children: [
          _ponto(Cores.verde),
          const Text(' chamados   ', style: TextStyle(fontSize: 11.5, color: Cores.tinta2)),
          _ponto(Cores.vermelho),
          const Text(' com máquina parada',
              style: TextStyle(fontSize: 11.5, color: Cores.tinta2)),
        ]),
      ],
    );
  }

  Widget _ponto(Color c) => Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(2)));
}

class _Fatia {
  final String nome;
  final int valor;
  final String texto;
  const _Fatia(this.nome, this.valor, this.texto);
}
