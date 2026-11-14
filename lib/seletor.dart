import 'package:flutter/material.dart';
import 'comum.dart';

/// Uma opção de qualquer lista pesquisável (máquina, funcionário, defeito, setor).
class Opcao {
  final Object valor;      // id (int) ou nome (String)
  final String titulo;
  final String? detalhe;
  const Opcao(this.valor, this.titulo, [this.detalhe]);

  bool combina(String busca) {
    final q = _simples(busca);
    if (q.isEmpty) return true;
    return _simples('$titulo ${detalhe ?? ''}').contains(q);
  }

  static String _simples(String s) {
    const de = 'áàâãäéèêëíìîïóòôõöúùûüçÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇ';
    const para = 'aaaaaeeeeiiiiooooouuuucAAAAAEEEEIIIIOOOOOUUUUC';
    var r = s.toLowerCase();
    for (var i = 0; i < de.length; i++) {
      r = r.replaceAll(de[i], para[i].toLowerCase());
    }
    return r.trim();
  }
}

/// Campo que parece um campo normal, mas abre uma folha com busca ao tocar.
/// Resolve a lista longa: o líder digita parte do código ou do nome e filtra.
class CampoBusca extends StatelessWidget {
  final String rotulo;
  final String dica;
  final String? ajuda;
  final Opcao? escolhida;
  final List<Opcao> opcoes;
  final ValueChanged<Opcao?> aoEscolher;
  final bool podeLimpar;

  const CampoBusca({
    super.key,
    required this.rotulo,
    required this.dica,
    required this.opcoes,
    required this.escolhida,
    required this.aoEscolher,
    this.ajuda,
    this.podeLimpar = false,
  });

  Future<void> _abrir(BuildContext context) async {
    final escolha = await showModalBottomSheet<Object?>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (_) => _FolhaBusca(
        titulo: rotulo,
        dica: dica,
        opcoes: opcoes,
        escolhida: escolhida,
        podeLimpar: podeLimpar,
      ),
    );
    if (escolha == null) return;                       // fechou sem escolher
    if (escolha == '__limpar__') return aoEscolher(null);
    aoEscolher(opcoes.firstWhere((o) => o.valor == escolha));
  }

  @override
  Widget build(BuildContext context) {
    final vazio = escolhida == null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () => _abrir(context),
        borderRadius: BorderRadius.circular(10),
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: rotulo,
            helperText: ajuda,
            helperMaxLines: 2,
            suffixIcon: const Icon(Icons.search, size: 20),
          ),
          child: Text(
            vazio ? dica : escolhida!.titulo,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: vazio ? Cores.tinta2 : Cores.tinta,
              fontWeight: vazio ? FontWeight.w400 : FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _FolhaBusca extends StatefulWidget {
  final String titulo;
  final String dica;
  final List<Opcao> opcoes;
  final Opcao? escolhida;
  final bool podeLimpar;

  const _FolhaBusca({
    required this.titulo,
    required this.dica,
    required this.opcoes,
    required this.escolhida,
    required this.podeLimpar,
  });

  @override
  State<_FolhaBusca> createState() => _FolhaBuscaState();
}

class _FolhaBuscaState extends State<_FolhaBusca> {
  final _busca = TextEditingController();

  @override
  void dispose() {
    _busca.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filtradas = widget.opcoes.where((o) => o.combina(_busca.text)).toList();
    final altura = MediaQuery.of(context).size.height * 0.75;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: altura,
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                  color: Cores.linha, borderRadius: BorderRadius.circular(2)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(widget.titulo,
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                  ),
                  if (widget.podeLimpar && widget.escolhida != null)
                    TextButton(
                      onPressed: () => Navigator.pop(context, '__limpar__'),
                      child: const Text('Limpar'),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _busca,
                autofocus: true,
                textInputAction: TextInputAction.search,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: widget.dica,
                  prefixIcon: const Icon(Icons.search, size: 20),
                  suffixIcon: _busca.text.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: () => setState(() => _busca.clear()),
                        ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Expanded(
              child: filtradas.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          widget.opcoes.isEmpty
                              ? 'Nenhum cadastro disponível.'
                              : 'Nada encontrado para "${_busca.text}".',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Cores.tinta2),
                        ),
                      ),
                    )
                  : ListView.separated(
                      itemCount: filtradas.length,
                      separatorBuilder: (_, __) =>
                          const Divider(height: 1, color: Cores.linha),
                      itemBuilder: (_, i) {
                        final o = filtradas[i];
                        final atual = widget.escolhida?.valor == o.valor;
                        return ListTile(
                          title: Text(o.titulo,
                              style: TextStyle(
                                  fontWeight:
                                      atual ? FontWeight.w700 : FontWeight.w500)),
                          subtitle: (o.detalhe == null || o.detalhe!.isEmpty)
                              ? null
                              : Text(o.detalhe!),
                          trailing: atual
                              ? const Icon(Icons.check, color: Cores.verdeEsc)
                              : null,
                          onTap: () => Navigator.pop(context, o.valor),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
