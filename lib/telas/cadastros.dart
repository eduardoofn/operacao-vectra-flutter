import 'package:flutter/material.dart';
import '../api.dart';
import '../comum.dart';

/// Cadastros do gestor: setores, máquinas, funcionários e usuários.
class TelaCadastros extends StatefulWidget {
  const TelaCadastros({super.key});

  @override
  State<TelaCadastros> createState() => _TelaCadastrosState();
}

class _Campo {
  final String chave;
  final String rotulo;
  final bool numero;
  final bool setor;
  final bool pin;
  final Map<String, String>? opcoes;
  const _Campo(this.chave, this.rotulo,
      {this.numero = false, this.setor = false, this.pin = false, this.opcoes});
}

class _Tipo {
  final String chave;
  final String titulo;
  final String singular;
  final List<_Campo> campos;
  const _Tipo(this.chave, this.titulo, this.singular, this.campos);
}

const _perfis = {
  'LIDER': 'Líder',
  'MECANICO': 'Mecânico',
  'ENGENHARIA': 'Engenharia',
  'ADMIN': 'Gestor',
};

const _tipos = [
  _Tipo('setores', 'Setores', 'setor', [
    _Campo('nome', 'Setor'),
    _Campo('capacidade', 'Capacidade (colaboradores)', numero: true),
  ]),
  _Tipo('defeitos', 'Defeitos', 'defeito', [
    _Campo('nome', 'Defeito'),
    _Campo('descricao', 'Descrição (opcional)'),
  ]),
  _Tipo('maquinas', 'Máquinas', 'máquina', [
    _Campo('codigo', 'Código'),
    _Campo('descricao', 'Descrição'),
    _Campo('setor', 'Setor', setor: true),
  ]),
  _Tipo('funcionarios', 'Funcionários', 'funcionário', [
    _Campo('matricula', 'Matrícula'),
    _Campo('nome', 'Nome'),
    _Campo('setor', 'Setor', setor: true),
  ]),
  _Tipo('usuarios', 'Usuários', 'usuário', [
    _Campo('nome', 'Nome'),
    _Campo('login', 'Usuário'),
    _Campo('perfil', 'Perfil', opcoes: _perfis),
    _Campo('setor', 'Setor', setor: true),
    _Campo('pin', 'PIN', pin: true),
  ]),
];

class _TelaCadastrosState extends State<TelaCadastros> {
  int _indice = 0;
  List<Map<String, dynamic>> _linhas = [];
  List<String> _setores = [];
  bool _carregando = true;
  String _busca = '';
  String? _erro;
  String _carregado = '';   // de qual cadastro são as linhas em tela

  _Tipo get _tipo => _tipos[_indice];

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    final alvo = _tipo.chave;
    setState(() {
      _carregando = true;
      _erro = null;
      _linhas = [];          // limpa antes, para não exibir o cadastro anterior
      _carregado = '';
    });
    try {
      final dados = await Api.get('/api/cad/$alvo') as List;
      final listas = await Api.get('/api/listas') as Map<String, dynamic>;
      if (!mounted || alvo != _tipo.chave) return;   // o usuário já trocou de aba
      setState(() {
        _linhas = dados.cast<Map<String, dynamic>>();
        _setores = (listas['setores'] as List).map((s) => s['nome'].toString()).toList();
        _carregado = alvo;
        _carregando = false;
      });
    } on ErroApi catch (e) {
      if (!mounted || alvo != _tipo.chave) return;
      setState(() {
        _carregando = false;
        _erro = e.status == 404
            ? 'Este cadastro ainda não existe no servidor. Rode o script sql/06_defeitos.sql e atualize o app.py.'
            : e.mensagem;
      });
    }
  }

  Future<void> _editar(Map<String, dynamic>? registro) async {
    final salvou = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (_) => _FormCadastro(tipo: _tipo, registro: registro, setores: _setores),
    );
    if (salvou == true) _carregar();
  }

  String _resumo(Map<String, dynamic> r) {
    final partes = <String>[];
    for (final c in _tipo.campos) {
      if (c.pin) continue;
      final v = r[c.chave];
      if (v == null || v.toString().isEmpty) continue;
      partes.add(c.opcoes != null ? (c.opcoes![v.toString()] ?? v.toString()) : v.toString());
    }
    return partes.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final q = _busca.toLowerCase();
    final visiveis = _carregado != _tipo.chave
        ? <Map<String, dynamic>>[]
        : _linhas.where((r) => q.isEmpty || _resumo(r).toLowerCase().contains(q)).toList();

    return Scaffold(
      backgroundColor: Cores.papel,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _editar(null),
        backgroundColor: Cores.verdeEsc,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: Text('Novo ${_tipo.singular}',
            style: const TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: Column(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 4),
            child: Row(
              children: [
                for (var i = 0; i < _tipos.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(_tipos[i].titulo),
                      selected: i == _indice,
                      selectedColor: const Color(0xFFE6F4E2),
                      onSelected: (_) {
                        setState(() => _indice = i);
                        _carregar();
                      },
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
            child: TextField(
              onChanged: (v) => setState(() => _busca = v),
              decoration: InputDecoration(
                isDense: true,
                prefixIcon: const Icon(Icons.search, size: 20),
                hintText: 'Buscar ${_tipo.singular}',
              ),
            ),
          ),
          Expanded(
            child: _carregando
                ? const Center(child: CircularProgressIndicator())
                : _erro != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(28),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.info_outline, size: 46, color: Cores.tinta2),
                          const SizedBox(height: 12),
                          Text(_erro!,
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Cores.tinta2)),
                          const SizedBox(height: 16),
                          FilledButton(onPressed: _carregar, child: const Text('Tentar de novo')),
                        ],
                      ),
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _carregar,
                    child: ListView.builder(
                      padding: const EdgeInsets.fromLTRB(8, 0, 8, 88),
                      itemCount: visiveis.length,
                      itemBuilder: (_, i) {
                        final r = visiveis[i];
                        final ativo = r['ativo'] == true || r['ativo'] == 1;
                        return Card(
                          elevation: 0,
                          margin: const EdgeInsets.only(bottom: 5),
                          color: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                            side: const BorderSide(color: Cores.linha),
                          ),
                          child: ListTile(
                            dense: true,
                            visualDensity: VisualDensity.compact,
                            onTap: () => _editar(r),
                            title: Text(_resumo(r),
                                style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: ativo ? Cores.tinta : Cores.tinta2)),
                            trailing: ativo
                                ? const Icon(Icons.edit_outlined, color: Cores.tinta2, size: 20)
                                : const Text('Inativo',
                                    style: TextStyle(color: Cores.tinta2, fontSize: 12.5)),
                          ),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _FormCadastro extends StatefulWidget {
  final _Tipo tipo;
  final Map<String, dynamic>? registro;
  final List<String> setores;
  const _FormCadastro({required this.tipo, required this.registro, required this.setores});

  @override
  State<_FormCadastro> createState() => _FormCadastroState();
}

class _FormCadastroState extends State<_FormCadastro> {
  final Map<String, TextEditingController> _campos = {};
  final Map<String, String?> _escolhas = {};
  bool _ativo = true;
  bool _enviando = false;

  @override
  void initState() {
    super.initState();
    final r = widget.registro;
    for (final c in widget.tipo.campos) {
      if (c.opcoes != null || c.setor) {
        _escolhas[c.chave] = r?[c.chave]?.toString();
      } else {
        _campos[c.chave] = TextEditingController(text: r?[c.chave]?.toString() ?? '');
      }
    }
    _ativo = r == null ? true : (r['ativo'] == true || r['ativo'] == 1);
  }

  @override
  void dispose() {
    for (final c in _campos.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _salvar() async {
    final corpo = <String, dynamic>{'id': widget.registro?['id'], 'ativo': _ativo};
    for (final c in widget.tipo.campos) {
      corpo[c.chave] = (c.opcoes != null || c.setor)
          ? (_escolhas[c.chave] ?? '')
          : _campos[c.chave]!.text.trim();
    }
    setState(() => _enviando = true);
    try {
      await Api.post('/api/cad/${widget.tipo.chave}', corpo);
      if (!mounted) return;
      Navigator.pop(context, true);
      aviso(context, 'Cadastro salvo');
    } on ErroApi catch (e) {
      if (mounted) {
        setState(() => _enviando = false);
        aviso(context, e.mensagem, erro: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final novo = widget.registro == null;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 18, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('${novo ? 'Novo' : 'Editar'} ${widget.tipo.singular}',
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
            const SizedBox(height: 16),
            for (final c in widget.tipo.campos) ...[
              if (c.opcoes != null)
                DropdownButtonFormField<String>(
                  value: _escolhas[c.chave] ?? c.opcoes!.keys.first,
                  decoration: InputDecoration(labelText: c.rotulo),
                  items: c.opcoes!.entries
                      .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                      .toList(),
                  onChanged: (v) => setState(() => _escolhas[c.chave] = v),
                )
              else if (c.setor)
                DropdownButtonFormField<String>(
                  value: widget.setores.contains(_escolhas[c.chave])
                      ? _escolhas[c.chave]
                      : null,
                  decoration: InputDecoration(labelText: c.rotulo),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('Sem setor')),
                    ...widget.setores.map((s) => DropdownMenuItem(value: s, child: Text(s))),
                  ],
                  onChanged: (v) => setState(() => _escolhas[c.chave] = v),
                )
              else
                TextField(
                  controller: _campos[c.chave],
                  obscureText: c.pin,
                  keyboardType:
                      (c.numero || c.pin) ? TextInputType.number : TextInputType.text,
                  decoration: InputDecoration(
                    labelText: c.rotulo,
                    hintText: c.pin
                        ? (novo ? '4 a 8 números' : 'Deixe em branco para manter o atual')
                        : null,
                  ),
                ),
              const SizedBox(height: 12),
            ],
            SwitchListTile(
              value: _ativo,
              onChanged: (v) => setState(() => _ativo = v),
              title: const Text('Ativo'),
              contentPadding: EdgeInsets.zero,
              activeColor: Cores.verdeEsc,
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: _enviando ? null : _salvar,
              child: _enviando
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                  : const Text('Salvar'),
            ),
          ],
        ),
      ),
    );
  }
}
