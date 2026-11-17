import 'package:flutter/material.dart';
import 'comum.dart';

/// Quanto tempo de máquina parada o grupo acumulou no dia.
/// O servidor já recorta cada parada dentro do dia escolhido, então
/// uma parada que virou a noite não joga tudo em um dia só.
class Parada {
  final String data;
  final int minutos, minEspera, minReparo, paradas, emAndamento;
  final List<int> expediente;        // [abre, fecha] em horas
  final List<ParadaMaquina> porMaquina;
  final List<ParadaItem> itens;

  Parada.deJson(Map<String, dynamic> j)
      : data = (j['data'] ?? '').toString(),
        minutos = _i(j['minutos']),
        minEspera = _i(j['min_espera']),
        minReparo = _i(j['min_reparo']),
        paradas = _i(j['paradas']),
        emAndamento = _i(j['em_andamento']),
        expediente =
            ((j['expediente'] ?? const [0, 24]) as List).map(_i).toList(),
        porMaquina = ((j['por_maquina'] ?? []) as List)
            .map((e) => ParadaMaquina.deJson(e as Map<String, dynamic>))
            .toList(),
        itens = ((j['itens'] ?? []) as List)
            .map((e) => ParadaItem.deJson(e as Map<String, dynamic>))
            .toList();

  static int _i(Object? v) => v is int ? v : int.tryParse('${v ?? 0}') ?? 0;

  int get pctEspera => minutos == 0 ? 0 : (minEspera * 100 / minutos).round();

}

class ParadaMaquina {
  final String codigo, descricao, setor;
  final int minutos, paradas;
  final bool emAndamento;
  ParadaMaquina.deJson(Map<String, dynamic> j)
      : codigo = (j['codigo'] ?? '').toString(),
        descricao = (j['descricao'] ?? '').toString(),
        setor = (j['setor'] ?? '').toString(),
        minutos = Parada._i(j['minutos']),
        paradas = Parada._i(j['paradas']),
        emAndamento = j['em_andamento'] == true;
}

class ParadaItem {
  final int id, minutos, minEspera, minReparo;
  final String codigo, defeito, mecanico;
  final bool emAndamento;
  ParadaItem.deJson(Map<String, dynamic> j)
      : id = Parada._i(j['id']),
        minutos = Parada._i(j['minutos']),
        minEspera = Parada._i(j['min_espera']),
        minReparo = Parada._i(j['min_reparo']),
        codigo = (j['codigo'] ?? '').toString(),
        defeito = (j['defeito'] ?? j['problema'] ?? '').toString(),
        mecanico = (j['mecanico'] ?? '').toString(),
        emAndamento = j['em_andamento'] == true;
}

String horas(int min) {
  if (min <= 0) return '0 min';
  final h = min ~/ 60, m = min % 60;
  if (h == 0) return '$m min';
  return m == 0 ? '${h}h' : '${h}h ${m.toString().padLeft(2, '0')}';
}

/// Faixa enxuta no topo dos chamados: uma linha, e tocar abre o Relatório.
class PainelParada extends StatelessWidget {
  final Parada? parada;
  final bool ehLider;
  final VoidCallback aoTocar;

  const PainelParada({
    super.key,
    required this.parada,
    required this.ehLider,
    required this.aoTocar,
  });

  @override
  Widget build(BuildContext context) {
    final p = parada;
    if (p == null) return const SizedBox.shrink();
    final zerado = p.minutos == 0;
    final cor = zerado ? Cores.verdeEsc : Cores.vermelho;
    final quando = p.data == hojeIso() ? 'hoje' : 'em ${diaMes(p.data)}';

    return Container(
      margin: const EdgeInsets.fromLTRB(10, 2, 10, 4),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Cores.linha),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: aoTocar,
          child: Container(
            decoration: BoxDecoration(
              border: Border(left: BorderSide(color: cor, width: 4)),
            ),
            padding: const EdgeInsets.fromLTRB(12, 7, 8, 7),
            child: Row(
              children: [
                Text(horas(p.minutos),
                    style: TextStyle(
                        fontSize: 21, fontWeight: FontWeight.w800, color: cor, height: 1.1)),
                const SizedBox(width: 7),
                Expanded(
                  child: Text('de máquina parada $quando',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 12.5, color: Cores.tinta2, fontWeight: FontWeight.w600)),
                ),
                if (p.emAndamento > 0) selo('${p.emAndamento} parada agora'),
                const Icon(Icons.chevron_right, size: 20, color: Cores.tinta2),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Aba Relatório: as paradas do dia por inteiro.
class RelatorioParadas extends StatelessWidget {
  final Parada parada;
  final bool ehLider;
  final ValueChanged<DateTime> aoTrocarDia;
  // médias do período filtrado nos chamados, em minutos
  final int mediaEspera, mediaReparo, mediaTotal;

  const RelatorioParadas({
    super.key,
    required this.parada,
    required this.ehLider,
    required this.aoTrocarDia,
    this.mediaEspera = 0,
    this.mediaReparo = 0,
    this.mediaTotal = 0,
  });

  @override
  Widget build(BuildContext context) {
    final p = parada;
    final hoje = p.data == hojeIso();
    final quando = hoje ? 'hoje' : 'em ${diaMes(p.data)}';
    final onde = ehLider ? 'no seu grupo' : 'na fábrica';
    final zerado = p.minutos == 0;

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(horas(p.minutos),
                style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                    height: 1,
                    color: zerado ? Cores.verdeEsc : Cores.vermelho)),
            const SizedBox(width: 8),
            Expanded(
              child: Text('de máquina parada\n$quando $onde',
                  style: const TextStyle(
                      fontSize: 12.5, color: Cores.tinta2, fontWeight: FontWeight.w600)),
            ),
            TextButton.icon(
              onPressed: () => _escolherDia(context, p.data),
              icon: const Icon(Icons.calendar_today_outlined, size: 16),
              label: Text(hoje ? 'Outro dia' : diaMes(p.data),
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (mediaTotal > 0) ...[
          _titulo('Tempo de atendimento no período'),
          Wrap(spacing: 8, runSpacing: 8, children: [
            _cartao(horas(mediaEspera), 'Espera média'),
            _cartao(horas(mediaReparo), 'Reparo médio'),
            _cartao(horas(mediaTotal), 'Atendimento total'),
          ]),
          const SizedBox(height: 16),
        ],
        if (zerado)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Text('Nenhuma máquina parou neste dia.\nBom dia de produção.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Cores.tinta2, fontSize: 14)),
          )
        else ...[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _cartao('${p.paradas}', 'Paradas'),
              _cartao('${p.porMaquina.length}', 'Máquinas'),
              _cartao('${p.emAndamento}', 'Paradas agora',
                  alerta: p.emAndamento > 0),
              _cartao(horas(p.minEspera), 'Esperando'),
              _cartao(horas(p.minReparo), 'Em reparo'),
            ],
          ),
          const SizedBox(height: 14),
          _barra(p),
          const SizedBox(height: 16),
          _titulo('Por máquina'),
          for (final m in p.porMaquina)
            _linha(horas(m.minutos), m.codigo,
                '${m.descricao}${m.setor.isEmpty ? '' : ' · ${m.setor}'}'
                ' · ${m.paradas} parada${m.paradas > 1 ? 's' : ''}',
                m.emAndamento ? 'parada agora' : null),
          const SizedBox(height: 14),
          _titulo('Chamado por chamado'),
          for (final i in p.itens)
            _linha(horas(i.minutos), '#${i.id} ${i.codigo}',
                '${i.defeito} · espera ${horas(i.minEspera)} · reparo ${horas(i.minReparo)}'
                '${i.mecanico.isEmpty ? '' : ' · ${i.mecanico}'}',
                i.emAndamento ? 'em aberto' : null),
        ],
      ],
    );
  }

  Widget _cartao(String valor, String rotulo, {bool alerta = false}) => Container(
        width: 108,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Cores.linha),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(valor,
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: alerta ? Cores.vermelho : Cores.tinta)),
            Text(rotulo, style: const TextStyle(fontSize: 11.5, color: Cores.tinta2)),
          ],
        ),
      );

  Widget _barra(Parada p) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              height: 7,
              child: LayoutBuilder(
                builder: (_, caixa) {
                  final largura = caixa.maxWidth;
                  final espera = largura * p.pctEspera / 100;
                  return Row(children: [
                    SizedBox(width: espera, child: const ColoredBox(color: Cores.ambar)),
                    SizedBox(
                        width: largura - espera, child: const ColoredBox(color: Cores.verde)),
                  ]);
                },
              ),
            ),
          ),
          const SizedBox(height: 5),
          Row(children: [
            _ponto(Cores.ambar),
            Text(' esperando mecânico ${p.pctEspera}%   ',
                style: const TextStyle(fontSize: 11.5, color: Cores.tinta2)),
            _ponto(Cores.verde),
            Text(' em reparo ${100 - p.pctEspera}%',
                style: const TextStyle(fontSize: 11.5, color: Cores.tinta2)),
          ]),
        ],
      );

  Widget _ponto(Color c) => Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(2)));

  Widget _titulo(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(t.toUpperCase(),
            style: const TextStyle(
                fontSize: 11, fontWeight: FontWeight.w800, color: Cores.tinta2, letterSpacing: .5)),
      );

  Widget _linha(String tempo, String titulo, String detalhe, String? marca) => Container(
        margin: const EdgeInsets.only(bottom: 1),
        padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Cores.linha),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 58,
              child: Text(tempo,
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(titulo,
                      style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
                  Text(detalhe,
                      style: const TextStyle(fontSize: 11.5, color: Cores.tinta2, height: 1.3)),
                ],
              ),
            ),
            if (marca != null) ...[const SizedBox(width: 6), selo(marca)],
          ],
        ),
      );

  Future<void> _escolherDia(BuildContext context, String atual) async {
    final hoje = DateTime.now();
    final partes = atual.split('-');
    final inicial = partes.length == 3
        ? DateTime(int.parse(partes[0]), int.parse(partes[1]), int.parse(partes[2]))
        : hoje;
    final escolhido = await showDatePicker(
      context: context,
      initialDate: inicial,
      firstDate: DateTime(hoje.year - 2),
      lastDate: hoje,
      helpText: 'Dia do fechamento',
    );
    if (escolhido != null) aoTrocarDia(escolhido);
  }
}

Widget selo(String t) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration:
          BoxDecoration(color: Cores.vermelho, borderRadius: BorderRadius.circular(20)),
      child: Text(t,
          style: const TextStyle(
              color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w800)),
    );

String hojeIso() {
  final h = DateTime.now();
  return '${h.year}-${_dd(h.month)}-${_dd(h.day)}';
}

String _dd(int n) => n.toString().padLeft(2, '0');

String diaMes(String iso) {
  final p = iso.split('-');
  return p.length == 3 ? '${p[2]}/${p[1]}' : iso;
}
