import 'package:flutter/material.dart';

/// Cores da Vectra Work.
class Cores {
  static const verde = Color(0xFF59C247);
  static const verdeEsc = Color(0xFF3F9631);
  static const tinta = Color(0xFF1D2620);
  static const tinta2 = Color(0xFF5A665E);
  static const papel = Color(0xFFEEF1ED);
  static const linha = Color(0xFFD6DCD4);
  static const ambar = Color(0xFFD98E0B);
  static const azul = Color(0xFF2D6CB0);
  static const vermelho = Color(0xFFCF3A2B);
}

/// Quanto tempo um chamado pode ficar esperando antes de virar alerta.
const int kAlertaMinutos = 30;

class Usuario {
  final int id;
  final String nome;
  final String login;
  final String perfil;
  final String? setor;

  Usuario.deJson(Map<String, dynamic> j)
      : id = j['id'] as int,
        nome = (j['nome'] ?? '').toString(),
        login = (j['login'] ?? '').toString(),
        perfil = (j['perfil'] ?? '').toString(),
        setor = j['setor']?.toString();

  bool get ehMecanico => perfil == 'MECANICO';
  bool get ehLider => perfil == 'LIDER';
  bool get ehEngenharia => perfil == 'ENGENHARIA';
  bool get ehGestor => perfil == 'ADMIN';
  String get perfilNome => const {
        'LIDER': 'Líder',
        'MECANICO': 'Mecânico',
        'ENGENHARIA': 'Engenharia',
        'ADMIN': 'Gestor',
      }[perfil] ??
      perfil;
}

class Prioridade {
  final String nome;
  final String curto;
  final Color cor;
  final int peso;
  const Prioridade(this.nome, this.curto, this.cor, this.peso);

  static const parada = Prioridade('Máquina parada', 'Parada', Cores.vermelho, 0);
  static const alta = Prioridade('Alta', 'Alta', Cores.ambar, 1);
  static const baixa = Prioridade('Baixa', 'Baixa', Cores.tinta2, 2);

  static Prioridade de(String? chave) {
    switch (chave) {
      case 'PARADA':
        return parada;
      case 'ALTA':
        return alta;
      default:
        return baixa;
    }
  }
}

class Chamado {
  final int id;
  final String status;
  final String prioridade;
  final String problema;
  final String? solucao;
  final String? setor;
  final String maquinaCodigo;
  final String maquinaDescricao;
  final String? funcionario;
  final String lider;
  final int liderId;
  final String? mecanico;
  final int? mecanicoId;
  final DateTime abertura;
  final DateTime? inicio;
  final DateTime? fim;

  Chamado.deJson(Map<String, dynamic> j)
      : id = j['id'] as int,
        status = (j['status'] ?? 'ABERTO').toString(),
        prioridade = (j['prioridade'] ?? (j['maquina_parada'] == true ? 'PARADA' : 'BAIXA')).toString(),
        problema = (j['problema'] ?? '').toString(),
        solucao = j['solucao']?.toString(),
        setor = j['setor']?.toString(),
        maquinaCodigo = (j['maq_codigo'] ?? '').toString(),
        maquinaDescricao = (j['maq_descricao'] ?? '').toString(),
        funcionario = j['func_nome']?.toString(),
        lider = (j['lider_nome'] ?? '').toString(),
        liderId = (j['lider_id'] ?? 0) as int,
        mecanico = j['mecanico_nome']?.toString(),
        mecanicoId = j['mecanico_id'] as int?,
        abertura = DateTime.parse(j['dt_abertura'].toString()),
        inicio = j['dt_inicio'] == null ? null : DateTime.parse(j['dt_inicio'].toString()),
        fim = j['dt_fim'] == null ? null : DateTime.parse(j['dt_fim'].toString());

  Prioridade get prio => Prioridade.de(prioridade);
  bool get aberto => status == 'ABERTO';
  bool get emAndamento => status == 'ANDAMENTO';
  bool get concluido => status == 'CONCLUIDO';
}

class Balanceamento {
  final int id;
  final String status;
  final String setor;
  final String produto;
  final String necessidade;
  final int? quantidade;
  final int? costureiros;
  final int? manuais;
  final String? observacao;
  final String? resposta;
  final String lider;
  final int liderId;
  final String? engenharia;
  final DateTime abertura;
  final DateTime? necessidadeEm;
  final DateTime? fim;

  Balanceamento.deJson(Map<String, dynamic> j)
      : id = j['id'] as int,
        status = (j['status'] ?? 'ABERTO').toString(),
        setor = (j['setor'] ?? '').toString(),
        produto = (j['produto'] ?? '').toString(),
        necessidade = (j['necessidade'] ?? 'BAIXA').toString(),
        quantidade = j['quantidade'] as int?,
        costureiros = j['costureiros'] as int?,
        manuais = j['manuais'] as int?,
        observacao = j['observacao']?.toString(),
        resposta = j['resposta']?.toString(),
        lider = (j['lider_nome'] ?? '').toString(),
        liderId = (j['lider_id'] ?? 0) as int,
        engenharia = j['eng_nome']?.toString(),
        abertura = DateTime.parse(j['dt_abertura'].toString()),
        necessidadeEm =
            j['dt_necessidade'] == null ? null : DateTime.parse(j['dt_necessidade'].toString()),
        fim = j['dt_fim'] == null ? null : DateTime.parse(j['dt_fim'].toString());

  bool get alta => necessidade == 'ALTA';
}

/// Status com nome e cor, usado nas três telas de quadro.
class Situacao {
  final String nome;
  final Color cor;
  final Color fundo;
  const Situacao(this.nome, this.cor, this.fundo);

  static const Map<String, Situacao> chamados = {
    'ABERTO': Situacao('Aberto', Cores.ambar, Color(0xFFFDF2DA)),
    'ANDAMENTO': Situacao('Em andamento', Cores.azul, Color(0xFFE3EDF8)),
    'CONCLUIDO': Situacao('Concluído', Cores.verdeEsc, Color(0xFFE6F4E2)),
    'CANCELADO': Situacao('Cancelado', Color(0xFF8A948D), Color(0xFFECEEEC)),
  };

  static const Map<String, Situacao> balanceamento = {
    'ABERTO': Situacao('Solicitado', Cores.ambar, Color(0xFFFDF2DA)),
    'ANDAMENTO': Situacao('Em análise', Cores.azul, Color(0xFFE3EDF8)),
    'CONCLUIDO': Situacao('Atendido', Cores.verdeEsc, Color(0xFFE6F4E2)),
    'CANCELADO': Situacao('Cancelado', Color(0xFF8A948D), Color(0xFFECEEEC)),
  };
}

/// Diferença entre o relógio do celular e o do servidor.
class Relogio {
  static Duration ajuste = Duration.zero;
  static DateTime get agora => DateTime.now().subtract(ajuste);
  static void sincronizar(String? agoraServidor) {
    if (agoraServidor == null) return;
    try {
      ajuste = DateTime.now().difference(DateTime.parse(agoraServidor));
    } catch (_) {}
  }
}

String duracao(Duration? d) {
  if (d == null) return '—';
  var m = d.inMinutes;
  if (m < 0) m = 0;
  if (m < 60) return '$m min';
  final h = m ~/ 60;
  final resto = m % 60;
  if (h < 24) return resto == 0 ? '${h}h' : '${h}h ${resto.toString().padLeft(2, '0')}';
  return '${h ~/ 24}d ${h % 24}h';
}

String _dois(int n) => n.toString().padLeft(2, '0');

String dataHora(DateTime? d) =>
    d == null ? '—' : '${_dois(d.day)}/${_dois(d.month)} ${_dois(d.hour)}:${_dois(d.minute)}';

String dataIso(DateTime d) => '${d.year}-${_dois(d.month)}-${_dois(d.day)}';

String dataBr(DateTime d) => '${_dois(d.day)}/${_dois(d.month)}/${d.year}';

/// Caixa de aviso no rodapé, sempre no mesmo padrão.
void aviso(BuildContext contexto, String texto, {bool erro = false}) {
  ScaffoldMessenger.of(contexto)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(texto, style: const TextStyle(fontWeight: FontWeight.w600)),
      backgroundColor: erro ? Cores.vermelho : Cores.verdeEsc,
      behavior: SnackBarBehavior.floating,
      duration: Duration(seconds: erro ? 4 : 2),
    ));
}
