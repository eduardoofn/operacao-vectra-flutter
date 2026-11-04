import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../api.dart';
import '../comum.dart';

class TelaLogin extends StatefulWidget {
  final void Function(Usuario) aoEntrar;
  const TelaLogin({super.key, required this.aoEntrar});

  @override
  State<TelaLogin> createState() => _TelaLoginState();
}

class _TelaLoginState extends State<TelaLogin> {
  final _usuario = TextEditingController();
  final _pin = TextEditingController();
  bool _enviando = false;
  String? _erro;

  @override
  void dispose() {
    _usuario.dispose();
    _pin.dispose();
    super.dispose();
  }

  Future<void> _entrar() async {
    setState(() {
      _enviando = true;
      _erro = null;
    });
    try {
      final dados = await Api.post('/api/login', {
        'login': _usuario.text.trim(),
        'pin': _pin.text.trim(),
      });
      widget.aoEntrar(Usuario.deJson(dados as Map<String, dynamic>));
    } on ErroApi catch (e) {
      setState(() => _erro = e.mensagem);
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  Future<void> _trocarServidor() async {
    final campo = TextEditingController(text: Api.servidor);
    final novo = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Endereço do servidor'),
        content: TextField(
          controller: campo,
          autofocus: true,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(hintText: 'http://192.168.0.101:8503'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(c, campo.text), child: const Text('Salvar')),
        ],
      ),
    );
    if (novo != null && novo.trim().isNotEmpty) {
      await Api.trocarServidor(novo);
      if (mounted) {
        setState(() {});
        aviso(context, 'Servidor: ${Api.servidor}');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -1.4),
            radius: 1.2,
            colors: [Color(0xFFE3F2DF), Cores.papel],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(24, 10, 24, 20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: const Border(top: BorderSide(color: Cores.verde, width: 6)),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0x1F1D2620),
                        blurRadius: 40,
                        offset: const Offset(0, 12),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 16),
                      Image.asset('assets/logo.png', height: 62),
                      const SizedBox(height: 18),
                      const Text('Operação Vectra Work',
                          style: TextStyle(fontSize: 25, fontWeight: FontWeight.w700, height: 1.15)),
                      const SizedBox(height: 6),
                      const Text('Chamados, presença e balanceamento na palma da mão.',
                          style: TextStyle(color: Cores.tinta2, fontSize: 14.5)),
                      const SizedBox(height: 22),
                      TextField(
                        controller: _usuario,
                        textInputAction: TextInputAction.next,
                        autocorrect: false,
                        decoration: const InputDecoration(labelText: 'Usuário'),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: _pin,
                        obscureText: true,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 24, letterSpacing: 8),
                        decoration: const InputDecoration(labelText: 'PIN'),
                        onSubmitted: (_) => _entrar(),
                      ),
                      if (_erro != null) ...[
                        const SizedBox(height: 12),
                        Text(_erro!,
                            style: const TextStyle(
                                color: Cores.vermelho, fontWeight: FontWeight.w600)),
                      ],
                      const SizedBox(height: 20),
                      FilledButton(
                        onPressed: _enviando ? null : _entrar,
                        child: _enviando
                            ? const SizedBox(
                                height: 22,
                                width: 22,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2.4, color: Colors.white))
                            : const Text('Entrar'),
                      ),
                      const SizedBox(height: 6),
                      TextButton.icon(
                        onPressed: _trocarServidor,
                        icon: const Icon(Icons.dns_outlined, size: 18),
                        label: Text(Api.servidor,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12.5)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
