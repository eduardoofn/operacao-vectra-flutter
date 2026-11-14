import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'api.dart';
import 'comum.dart';
import 'telas/login.dart';
import 'telas/chamados.dart';
import 'telas/presenca.dart';
import 'telas/balanceamento.dart';
import 'telas/cadastros.dart';
import 'notificacoes.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Api.iniciar();
  await Avisos.iniciar();
  runApp(const AppVectra());
}

class AppVectra extends StatelessWidget {
  const AppVectra({super.key});

  @override
  Widget build(BuildContext context) {
    final base = ColorScheme.fromSeed(seedColor: Cores.verdeEsc, primary: Cores.verdeEsc);
    return MaterialApp(
      title: 'Operação Vectra',
      locale: const Locale('pt', 'BR'),
      supportedLocales: const [Locale('pt', 'BR')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: base,
        scaffoldBackgroundColor: Cores.papel,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: Cores.tinta,
          elevation: 0,
          surfaceTintColor: Colors.white,
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
            textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Cores.linha),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Cores.linha),
          ),
        ),
        snackBarTheme: const SnackBarThemeData(contentTextStyle: TextStyle(color: Colors.white)),
      ),
      home: const Porta(),
    );
  }
}

/// Decide entre login e app, conferindo se a sessão ainda vale.
class Porta extends StatefulWidget {
  const Porta({super.key});
  @override
  State<Porta> createState() => _PortaState();
}

class _PortaState extends State<Porta> {
  Usuario? _usuario;
  bool _carregando = true;

  @override
  void initState() {
    super.initState();
    _conferir();
  }

  Future<void> _conferir() async {
    try {
      final dados = await Api.get('/api/me');
      setState(() {
        _usuario = Usuario.deJson(dados as Map<String, dynamic>);
        _carregando = false;
      });
    } catch (_) {
      setState(() => _carregando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_carregando) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_usuario == null) {
      return TelaLogin(aoEntrar: (u) => setState(() => _usuario = u));
    }
    return Inicio(
      usuario: _usuario!,
      aoSair: () => setState(() => _usuario = null),
    );
  }
}

/// Esqueleto do app: barra inferior com as telas que o perfil pode ver.
class Inicio extends StatefulWidget {
  final Usuario usuario;
  final VoidCallback aoSair;
  const Inicio({super.key, required this.usuario, required this.aoSair});

  @override
  State<Inicio> createState() => _InicioState();
}

class _InicioState extends State<Inicio> {
  int _aba = 0;

  List<_Destino> get _destinos {
    final u = widget.usuario;
    if (u.ehMecanico) {
      return [_Destino('Chamados', Icons.build_outlined, Icons.build, TelaChamados(usuario: u))];
    }
    if (u.ehLider) {
      return [
        _Destino('Chamados', Icons.build_outlined, Icons.build, TelaChamados(usuario: u)),
        _Destino('Presença', Icons.groups_outlined, Icons.groups, TelaPresenca(usuario: u)),
        _Destino('Balanceamento', Icons.balance_outlined, Icons.balance,
            TelaBalanceamento(usuario: u)),
      ];
    }
    if (u.ehEngenharia) {
      return [
        _Destino('Balanceamento', Icons.balance_outlined, Icons.balance,
            TelaBalanceamento(usuario: u)),
        _Destino('Presença', Icons.groups_outlined, Icons.groups, TelaPresenca(usuario: u)),
        _Destino('Chamados', Icons.build_outlined, Icons.build, TelaChamados(usuario: u)),
      ];
    }
    return [
      _Destino('Chamados', Icons.build_outlined, Icons.build, TelaChamados(usuario: u)),
      _Destino('Presença', Icons.groups_outlined, Icons.groups, TelaPresenca(usuario: u)),
      _Destino(
          'Balanceamento', Icons.balance_outlined, Icons.balance, TelaBalanceamento(usuario: u)),
      _Destino('Cadastros', Icons.list_alt_outlined, Icons.list_alt, const TelaCadastros()),
    ];
  }

  Future<void> _sair() async {
    final confirma = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Sair do app?'),
        content: const Text('Você vai precisar digitar o usuário e o PIN de novo.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Ficar')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Sair')),
        ],
      ),
    );
    if (confirma != true) return;
    try {
      await Api.post('/api/logout');
    } catch (_) {}
    await Api.limparSessao();
    widget.aoSair();
  }

  @override
  Widget build(BuildContext context) {
    final destinos = _destinos;
    final indice = _aba.clamp(0, destinos.length - 1);
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 10,
        toolbarHeight: 48,
        title: Row(
          children: [
            Image.asset('assets/logo.png', height: 22),
            const SizedBox(width: 8),
            Expanded(
              child: Text(destinos[indice].nome,
                  style: const TextStyle(fontSize: 17.5, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
        actions: [
          Center(
            child: Padding(
              padding: const EdgeInsets.only(right: 4),
              child: CircleAvatar(
                radius: 14,
                backgroundColor: const Color(0xFFE6F4E2),
                child: Text(
                  widget.usuario.nome.isEmpty ? '?' : widget.usuario.nome[0].toUpperCase(),
                  style: const TextStyle(
                      color: Cores.verdeEsc, fontWeight: FontWeight.w700, fontSize: 13.5),
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Sair',
            visualDensity: VisualDensity.compact,
            onPressed: _sair,
            icon: const Icon(Icons.logout, size: 19),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(3),
          child: Container(height: 3, color: Cores.verde),
        ),
      ),
      body: IndexedStack(
        index: indice,
        children: destinos.map((d) => d.tela).toList(),
      ),
      bottomNavigationBar: destinos.length < 2
          ? null
          : NavigationBar(
              height: 56,
              selectedIndex: indice,
              onDestinationSelected: (i) => setState(() => _aba = i),
              backgroundColor: Colors.white,
              indicatorColor: const Color(0xFFE6F4E2),
              labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
              destinations: destinos
                  .map((d) => NavigationDestination(
                        icon: Icon(d.icone),
                        selectedIcon: Icon(d.iconeCheio, color: Cores.verdeEsc),
                        label: d.nome,
                      ))
                  .toList(),
            ),
    );
  }
}

class _Destino {
  final String nome;
  final IconData icone;
  final IconData iconeCheio;
  final Widget tela;
  _Destino(this.nome, this.icone, this.iconeCheio, this.tela);
}
