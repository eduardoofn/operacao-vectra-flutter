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
          const SizedBox(height: 12),
          _caixa('Em que hora abrem os chamados', _horasDoDia()),
          const SizedBox(height: 12),
          _caixa('Onde o mecânico demora mais a chegar',
              _barras(_lista('espera_por_setor', porMinutos: true))),
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

  /// No celular cabem poucas colunas: acima de 16 dias, junta por semana.
  List<_Col> _serieDias(List<Map<String, dynamic>> dias) {
    String dd(String iso) => iso.split('-').length == 3 ? iso.split('-')[2] : iso;
    if (dias.length <= 16) {
      return [
        for (final d in dias)
          _Col(_i(d['chamados']), _i(d['paradas']), dd(d['dia'].toString()))
      ];
    }
    final passo = (dias.length / 12).ceil();
    final fora = <_Col>[];
    for (var i = 0; i < dias.length; i += passo) {
      final bloco = dias.sublist(i, (i + passo).clamp(0, dias.length));
      fora.add(_Col(
        bloco.fold<int>(0, (a, e) => a + _i(e['chamados'])),
        bloco.fold<int>(0, (a, e) => a + _i(e['paradas'])),
        dd(bloco.first['dia'].toString()),
      ));
    }
    return fora;
  }

  Widget _colunas(List<Map<String, dynamic>> dias) {
    final cols = _serieDias(dias);
    final maior = cols.map((e) => e.total).fold<int>(1, (a, b) => a > b ? a : b);
    final agrupado = dias.length > 16;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _grafico(cols, maior, Cores.verde, segunda: Cores.vermelho),
        const SizedBox(height: 6),
        Row(children: [
          _ponto(Cores.verde),
          Text(agrupado ? ' chamados agrupados   ' : ' chamados   ',
              style: const TextStyle(fontSize: 11.5, color: Cores.tinta2)),
          _ponto(Cores.vermelho),
          const Text(' com máquina parada',
              style: TextStyle(fontSize: 11.5, color: Cores.tinta2)),
        ]),
      ],
    );
  }

  /// Hora em que os chamados são abertos: mostra o pico do turno.
  Widget _horasDoDia() {
    final bruto = ((_d?['por_hora'] ?? []) as List).cast<Map<String, dynamic>>();
    final usadas = bruto.where((h) => _i(h['chamados']) > 0).toList();
    if (usadas.isEmpty) {
      return const Text('Sem dados no período.',
          style: TextStyle(color: Cores.tinta2, fontSize: 13));
    }
    final de = _i(usadas.first['hora']), ate = _i(usadas.last['hora']);
    final faixa = bruto.sublist(de, ate + 1);
    final cols = [
      for (final h in faixa) _Col(_i(h['chamados']), 0, '${_i(h['hora'])}')
    ];
    final maior = cols.map((e) => e.total).fold<int>(1, (a, b) => a > b ? a : b);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _grafico(cols, maior, Cores.azul),
        const SizedBox(height: 6),
        const Text('hora em que o chamado foi aberto',
            style: TextStyle(fontSize: 11.5, color: Cores.tinta2)),
      ],
    );
  }

  /// Colunas com o número em cima e o rótulo embaixo. Quando não cabe
  /// tudo, os rótulos aparecem de forma espaçada em vez de embolar.
  Widget _grafico(List<_Col> cols, int maior, Color cor, {Color? segunda}) {
    final passo = cols.length <= 8 ? 1 : (cols.length <= 14 ? 2 : 3);
    bool mostra(int i) => i % passo == 0 || i == cols.length - 1;
    return SizedBox(
      height: 132,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < cols.length; i++)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 1.5),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    SizedBox(
                      height: 14,
                      child: (mostra(i) || cols[i].total == maior) && cols[i].total > 0
                          ? FittedBox(
                              child: Text('${cols[i].total}',
                                  style: const TextStyle(
                                      fontSize: 10, color: Cores.tinta2)))
                          : null,
                    ),
                    Expanded(
                      child: Stack(
                        alignment: Alignment.bottomCenter,
                        children: [
                          FractionallySizedBox(
                            heightFactor: (cols[i].total / maior).clamp(0.0, 1.0),
                            child: Container(
                              decoration: BoxDecoration(
                                color: cor,
                                borderRadius: const BorderRadius.vertical(
                                    top: Radius.circular(2)),
                              ),
                            ),
                          ),
                          if (segunda != null)
                            FractionallySizedBox(
                              heightFactor: (cols[i].destaque / maior).clamp(0.0, 1.0),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: segunda,
                                  borderRadius: const BorderRadius.vertical(
                                      top: Radius.circular(2)),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    SizedBox(
                      height: 15,
                      child: mostra(i)
                          ? FittedBox(
                              child: Text(cols[i].rotulo,
                                  style: const TextStyle(
                                      fontSize: 10, color: Cores.tinta2)))
                          : null,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _ponto(Color c) => Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(2)));
}

class _Col {
  final int total;
  final int destaque;
  final String rotulo;
  const _Col(this.total, this.destaque, this.rotulo);
}

class _Fatia {
  final String nome;
  final int valor;
  final String texto;
  const _Fatia(this.nome, this.valor, this.texto);
}
