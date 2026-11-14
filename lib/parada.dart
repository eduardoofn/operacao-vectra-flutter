import 'package:flutter/material.dart';
import 'comum.dart';

/// Quanto tempo de máquina parada o grupo acumulou no dia.
/// O servidor já recorta cada parada dentro do dia escolhido, então
/// uma parada que virou a noite não joga tudo em um dia só.
class Parada {
  final String data;
  final int minutos, minEspera, minReparo, paradas, emAndamento;
  final List<ParadaMaquina> porMaquina;
  final List<ParadaItem> itens;

  Parada.deJson(Map<String, dynamic> j)
      : data = (j['data'] ?? '').toString(),
        minutos = _i(j['minutos']),
        minEspera = _i(j['min_espera']),
        minReparo = _i(j['min_reparo']),
        paradas = _i(j['paradas']),
        emAndamento = _i(j['em_andamento']),
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

/// Painel de fechamento do dia, no topo dos chamados.
/// Fechado mostra uma linha; tocando, abre o detalhe por máquina.
class PainelParada extends StatelessWidget {
  final Parada? parada;
  final bool ehLider;
  final bool aberto;
  final VoidCallback aoAlternar;
  final ValueChanged<DateTime> aoTrocarDia;

  const PainelParada({
    super.key,
    required this.parada,
    required this.ehLider,
    required this.aberto,
    required this.aoAlternar,
    required this.aoTrocarDia,
  });

  @override
  Widget build(BuildContext context) {
    final p = parada;
    if (p == null) return const SizedBox.shrink();
    final zerado = p.minutos == 0;
    final cor = zerado ? Cores.verdeEsc : Cores.vermelho;
    final hoje = p.data == _hojeIso();
    final quando = hoje ? 'hoje' : 'em ${_brasileiro(p.data)}';
    final onde = ehLider ? 'no seu grupo' : 'na fábrica';

    return Container(
      margin: const EdgeInsets.fromLTRB(10, 2, 10, 6),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Cores.linha),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: zerado ? null : aoAlternar,
          // a faixa colorida entra como borda interna: o cartão de fora
          // é quem arredonda e recorta os cantos
          child: Container(
            decoration: BoxDecoration(
              border: Border(left: BorderSide(color: cor, width: 4)),
            ),
            padding: const EdgeInsets.fromLTRB(12, 9, 10, 9),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(horas(p.minutos),
                        style: TextStyle(
                            fontSize: 25, fontWeight: FontWeight.w800, color: cor, height: 1.1)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text('de máquina parada $quando',
                          style: const TextStyle(
                              fontSize: 13, color: Cores.tinta2, fontWeight: FontWeight.w600)),
                    ),
                    if (p.emAndamento > 0) _selo('${p.emAndamento} parada agora'),
                    if (!zerado)
                      Icon(aberto ? Icons.expand_less : Icons.expand_more,
                          size: 22, color: Cores.tinta2),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        zerado
                            ? 'Nenhuma máquina parou $quando $onde. Bom dia de produção.'
                            : '${p.paradas} parada${p.paradas > 1 ? 's' : ''} em '
                                '${p.porMaquina.length} máquina${p.porMaquina.length > 1 ? 's' : ''}'
                                ' · espera ${horas(p.minEspera)} · reparo ${horas(p.minReparo)}',
                        style: const TextStyle(fontSize: 12.5, color: Cores.tinta2, height: 1.35),
                      ),
                    ),
                    TextButton(
                      onPressed: () => _escolherDia(context, p.data),
                      style: TextButton.styleFrom(
                        minimumSize: const Size(0, 30),
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        visualDensity: VisualDensity.compact,
                      ),
                      child: Text(hoje ? 'Outro dia' : _brasileiro(p.data),
                          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
                if (!zerado) ...[
                  const SizedBox(height: 6),
                  _barra(p),
                ],
                if (aberto && !zerado) ...[
                  const Divider(height: 18, color: Cores.linha),
                  _titulo('Por máquina'),
                  for (final m in p.porMaquina)
                    _linha(horas(m.minutos), m.codigo,
                        '${m.descricao}${m.setor.isEmpty ? '' : ' · ${m.setor}'}'
                        ' · ${m.paradas} parada${m.paradas > 1 ? 's' : ''}',
                        m.emAndamento ? 'parada agora' : null),
                  const SizedBox(height: 6),
                  _titulo('Chamado por chamado'),
                  for (final i in p.itens)
                    _linha(horas(i.minutos), '#${i.id} ${i.codigo}',
                        '${i.defeito} · espera ${horas(i.minEspera)} · reparo ${horas(i.minReparo)}'
                        '${i.mecanico.isEmpty ? '' : ' · ${i.mecanico}'}',
                        i.emAndamento ? 'em aberto' : null),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _barra(Parada p) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              height: 6,
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
          const SizedBox(height: 3),
          Row(children: [
            _ponto(Cores.ambar),
            const Text(' esperando mecânico   ',
                style: TextStyle(fontSize: 11.5, color: Cores.tinta2)),
            _ponto(Cores.verde),
            const Text(' em reparo', style: TextStyle(fontSize: 11.5, color: Cores.tinta2)),
          ]),
        ],
      );

  Widget _ponto(Color c) => Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(2)));

  Widget _titulo(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: Text(t.toUpperCase(),
            style: const TextStyle(
                fontSize: 11, fontWeight: FontWeight.w800, color: Cores.tinta2, letterSpacing: .5)),
      );

  Widget _linha(String tempo, String titulo, String detalhe, String? selo) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
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
            if (selo != null) ...[const SizedBox(width: 6), _selo(selo)],
          ],
        ),
      );

  Widget _selo(String t) => Container(
        margin: const EdgeInsets.only(right: 4),
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration:
            BoxDecoration(color: Cores.vermelho, borderRadius: BorderRadius.circular(20)),
        child: Text(t,
            style: const TextStyle(
                color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w800)),
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

  static String _hojeIso() {
    final h = DateTime.now();
    return '${h.year}-${_dd(h.month)}-${_dd(h.day)}';
  }

  static String _dd(int n) => n.toString().padLeft(2, '0');

  static String _brasileiro(String iso) {
    final p = iso.split('-');
    return p.length == 3 ? '${p[2]}/${p[1]}' : iso;
  }
}
