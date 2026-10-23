// Coloque em: lib/domain/categoria_conta.dart
//
// Tipos de conta que o usuário escolhe ao cadastrar uma conta a pagar.

/// Os nomes (agua, luz, ...) são gravados no banco e enviados ao servidor:
/// não renomeie. Para incluir um tipo novo, acrescente no fim da lista.
enum CategoriaConta {
  agua,
  luz,
  gas,
  internet,
  telefone,
  aluguel,
  condominio,
  cartao,
  financiamento,
  impostos,
  saude,
  educacao,
  assinaturas,
  outros,
}

extension CategoriaContaInfo on CategoriaConta {
  String get rotulo => switch (this) {
        CategoriaConta.agua => 'Água',
        CategoriaConta.luz => 'Luz',
        CategoriaConta.gas => 'Gás',
        CategoriaConta.internet => 'Internet',
        CategoriaConta.telefone => 'Telefone',
        CategoriaConta.aluguel => 'Aluguel',
        CategoriaConta.condominio => 'Condomínio',
        CategoriaConta.cartao => 'Cartão de crédito',
        CategoriaConta.financiamento => 'Financiamento',
        CategoriaConta.impostos => 'Impostos e taxas',
        CategoriaConta.saude => 'Plano de saúde',
        CategoriaConta.educacao => 'Educação',
        CategoriaConta.assinaturas => 'Assinaturas',
        CategoriaConta.outros => 'Outros',
      };

  /// Nome sugerido quando o usuário escolhe o tipo e ainda não digitou o título.
  String get tituloSugerido => switch (this) {
        CategoriaConta.agua => 'Conta de água',
        CategoriaConta.luz => 'Conta de luz',
        CategoriaConta.gas => 'Conta de gás',
        CategoriaConta.internet => 'Internet',
        CategoriaConta.telefone => 'Telefone',
        CategoriaConta.aluguel => 'Aluguel',
        CategoriaConta.condominio => 'Condomínio',
        CategoriaConta.cartao => 'Fatura do cartão',
        CategoriaConta.financiamento => 'Parcela do financiamento',
        CategoriaConta.impostos => 'Impostos e taxas',
        CategoriaConta.saude => 'Plano de saúde',
        CategoriaConta.educacao => 'Mensalidade escolar',
        CategoriaConta.assinaturas => 'Assinatura',
        CategoriaConta.outros => 'Conta',
      };
}

/// Lê o nome gravado (banco/servidor). Nome desconhecido vira null.
CategoriaConta? categoriaContaDoNome(Object? nome) {
  if (nome is! String) return null;
  for (final c in CategoriaConta.values) {
    if (c.name == nome) return c;
  }
  return null;
}

// Palavras (sem acento, minúsculas) que indicam o tipo da conta. A ordem
// importa: "fatura de luz" é luz, não cartão.
const _palavrasChave = <CategoriaConta, String>{
  CategoriaConta.agua: r'agua|saneamento|sabesp',
  CategoriaConta.luz: r'luz|energia|eletrica|eletricidade',
  CategoriaConta.gas: r'gas|comgas',
  CategoriaConta.internet: r'internet|wi-?fi|fibra|banda larga',
  CategoriaConta.telefone: r'telefone|celular|recarga',
  CategoriaConta.aluguel: r'aluguel',
  CategoriaConta.condominio: r'condominio',
  CategoriaConta.cartao: r'cartao|fatura',
  CategoriaConta.financiamento: r'financiamento|emprestimo|prestacao|parcela|consorcio',
  CategoriaConta.impostos: r'iptu|ipva|imposto|darf|taxa',
  CategoriaConta.saude: r'plano de saude|convenio|unimed',
  CategoriaConta.educacao: r'escola|faculdade|colegio|curso',
  CategoriaConta.assinaturas: r'netflix|spotify|youtube|disney|prime video|globoplay|assinatura',
};

final _regrasCategoria = <CategoriaConta, RegExp>{
  for (final e in _palavrasChave.entries) e.key: RegExp('\\b(?:${e.value})\\b'),
};

/// Descobre o tipo da conta numa frase já normalizada (minúscula, sem acento).
CategoriaConta? detectarCategoriaConta(String textoNormalizado) {
  for (final e in _regrasCategoria.entries) {
    if (e.value.hasMatch(textoNormalizado)) return e.key;
  }
  return null;
}