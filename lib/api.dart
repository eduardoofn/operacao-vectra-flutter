import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Endereço do servidor. Dá para trocar sem mexer no código:
/// flutter build apk --dart-define=SERVER_URL=http://192.168.0.101:8503
const String kServidorPadrao =
    String.fromEnvironment('SERVER_URL', defaultValue: 'http://192.168.0.101:8503');

class ErroApi implements Exception {
  final String mensagem;
  final int status;
  ErroApi(this.mensagem, [this.status = 0]);
  @override
  String toString() => mensagem;
}

/// Conversa com o mesmo Flask que o site usa.
/// Guarda o cookie de sessão para o usuário não precisar logar todo dia.
class Api {
  static String servidor = kServidorPadrao;
  static String? _cookie;
  static final http.Client _cliente = http.Client();

  static Future<void> iniciar() async {
    final prefs = await SharedPreferences.getInstance();
    servidor = prefs.getString('servidor') ?? kServidorPadrao;
    _cookie = prefs.getString('cookie');
  }

  static Future<void> trocarServidor(String url) async {
    servidor = url.trim().replaceAll(RegExp(r'/+$'), '');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('servidor', servidor);
  }

  static Future<void> _guardarCookie(http.Response r) async {
    final bruto = r.headers['set-cookie'];
    if (bruto == null || bruto.isEmpty) return;
    _cookie = bruto.split(';').first;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('cookie', _cookie!);
  }

  static Future<void> limparSessao() async {
    _cookie = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('cookie');
  }

  static Map<String, String> get _cabecalhos => {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        if (_cookie != null) 'Cookie': _cookie!,
      };

  static Future<dynamic> get(String caminho) => _chamar('GET', caminho, null);

  static Future<dynamic> post(String caminho, [Map<String, dynamic>? corpo]) =>
      _chamar('POST', caminho, corpo);

  static Future<dynamic> _chamar(
      String metodo, String caminho, Map<String, dynamic>? corpo) async {
    final uri = Uri.parse('$servidor$caminho');
    http.Response r;
    try {
      if (metodo == 'GET') {
        r = await _cliente.get(uri, headers: _cabecalhos).timeout(const Duration(seconds: 15));
      } else {
        r = await _cliente
            .post(uri, headers: _cabecalhos, body: corpo == null ? null : jsonEncode(corpo))
            .timeout(const Duration(seconds: 15));
      }
    } catch (_) {
      throw ErroApi('Sem conexão com o servidor.', -1);
    }

    await _guardarCookie(r);

    dynamic dados;
    if (r.body.isNotEmpty) {
      try {
        dados = jsonDecode(utf8.decode(r.bodyBytes));
      } catch (_) {
        dados = null;
      }
    }

    if (r.statusCode >= 400) {
      final msg = (dados is Map && dados['erro'] != null)
          ? dados['erro'].toString()
          : 'Erro ${r.statusCode}. Tente de novo.';
      throw ErroApi(msg, r.statusCode);
    }
    return dados;
  }
}
