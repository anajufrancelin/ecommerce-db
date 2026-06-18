# Relatório de Engenharia Reversa — Banco `ecommerce_legado`

## 1. Contexto

Este relatório documenta o processo de engenharia reversa aplicado a um
banco de dados PostgreSQL de um sistema de e-commerce **sem qualquer
documentação prévia** (modelo ER, dicionário de dados ou diagrama). O
objetivo foi reconstruir o modelo lógico do banco a partir de sua estrutura
real, identificando entidades, relacionamentos, regras de integridade e
pontos de atenção — exatamente como aconteceria ao assumir a manutenção de
um sistema legado em uma empresa.

## 2. Metodologia

O processo foi 100% automatizado, sem nenhuma suposição manual sobre a
estrutura. O script [`extrair_estrutura.py`](../sql/03_engenharia_reversa/extrair_estrutura.py)
se conecta ao banco e consulta diretamente os catálogos do sistema:

| Informação extraída | Fonte consultada |
|---|---|
| Tabelas | `information_schema.tables` |
| Colunas, tipos, nullability, defaults | `information_schema.columns` |
| Chaves primárias | `information_schema.table_constraints` + `key_column_usage` |
| Chaves estrangeiras (relacionamentos) | `table_constraints` + `constraint_column_usage` |
| Constraints UNIQUE | `information_schema.table_constraints` |
| Constraints CHECK | `information_schema.check_constraints` |
| Índices | `pg_indexes` |

A saída foi salva em [`estrutura_banco.json`](./estrutura_banco.json), que
serviu de fonte única para gerar o diagrama ER (`gerar_diagrama_mermaid.py`),
garantindo que o diagrama reflita exatamente o que existe no banco — e não
uma reconstrução de memória.

## 3. Inventário de tabelas identificadas

A engenharia reversa identificou **15 tabelas** no schema `public`:

`tb_cliente`, `endereco_cliente`, `categoria`, `fornecedor`, `produto`,
`deposito`, `estoque_produto`, `forma_pagamento`, `status_pedido`,
`pedido`, `item_pedido`, `pagamento`, `avaliacao_produto`,
`cupom_desconto`, `pedido_cupom`.

## 4. Relacionamentos identificados

Foram identificadas **17 chaves estrangeiras**, mapeando os seguintes
relacionamentos principais:

- **Cliente → Endereço** (1:N): um cliente pode ter múltiplos endereços (`endereco_cliente.cliente_id`).
- **Cliente → Pedido** (1:N): um cliente pode fazer vários pedidos.
- **Pedido → Item do Pedido** (1:N) e **Produto → Item do Pedido** (1:N): modelando a relação N:N clássica entre pedidos e produtos através de uma tabela associativa.
- **Pedido → Pagamento** (1:N): um pedido pode ter mais de um registro de pagamento (reflete tentativas/parcelas).
- **Pedido ↔ Cupom** via `pedido_cupom`: tabela associativa com chave composta (`pedido_id`, `cupom_id`), indicando relação N:N — embora a regra de negócio observada nos dados sugira uso de **apenas um cupom por pedido** na prática atual.
- **Produto → Categoria** (N:1) e **Categoria → Categoria** (autorelacionamento): a tabela `categoria` referencia a si mesma via `cat_pai`, implementando uma hierarquia de categorias/subcategorias.
- **Produto → Fornecedor** (N:1).
- **Produto ↔ Depósito** via `estoque_produto`: tabela associativa com chave composta, controle de estoque por depósito/centro de distribuição.
- **Produto → Avaliação** e **Cliente → Avaliação**: cada avaliação está associada a um produto e a um cliente.
- **Pedido → Status** e **Pagamento → Forma de Pagamento**: ambos apontando para tabelas de domínio (lookup tables).

O diagrama completo, gerado automaticamente a partir dessas chaves, está em
[`diagramas/der_engenharia_reversa.mmd`](../diagramas/der_engenharia_reversa.mmd).

## 5. Inconsistências e pontos de atenção encontrados

Um dos objetivos centrais da engenharia reversa é justamente identificar
problemas de modelagem antes de propor melhorias. Os seguintes pontos
foram observados durante a análise:

1. **Nomenclatura inconsistente de tabelas e PKs.** A tabela de clientes
   é `tb_cliente` (com prefixo `tb_`), enquanto as demais não seguem esse
   padrão (`produto`, `pedido`, `categoria`). As colunas de chave primária
   também variam: algumas usam `id_<entidade>` (`id_cliente`, `id_produto`),
   outras usam `<entidade>_id` invertido (`cat_id`), e a tabela `categoria`
   usa um padrão próprio (`cat_nome`, `cat_pai`) diferente do restante do
   banco. Isso indica que o schema evoluiu sem um padrão de nomenclatura
   centralizado — comportamento típico de sistemas que cresceram organicamente
   ao longo do tempo, possivelmente com diferentes desenvolvedores.

2. **Redundância de preço no item do pedido (intencional, mas merece nota).**
   `item_pedido.preco_unitario` duplica a informação de `produto.preco_venda`.
   Isso **não é um erro** — é uma prática correta de "snapshot" para preservar
   o preço histórico de uma compra mesmo que o preço do produto mude depois —
   mas precisa estar documentado, pois pode parecer redundância de modelagem
   para quem não conhece a regra de negócio.

3. **`pedido_cupom` modelada como N:N, mas usada como 1:1 na prática.**
   A estrutura permite múltiplos cupons por pedido, mas os dados e a regra de
   negócio observada (campo único `valor_desconto` no pedido) sugerem que,
   atualmente, apenas um cupom é aplicado por vez. A tabela foi
   provavelmente desenhada "pensando no futuro", mas isso deveria estar
   documentado para evitar ambiguidade.

4. **Ausência de UNIQUE em colunas que deveriam ser únicas por regra de negócio.**
   `produto.sku` e `fornecedor.cnpj` corretamente possuem constraint
   `UNIQUE`. Porém, não há nenhuma constraint impedindo, por exemplo, que
   um mesmo cliente avalie o mesmo produto múltiplas vezes em
   `avaliacao_produto` — o que pode ou não ser desejado, mas não está
   explícito no banco.

5. **Campo de status como `CHAR(1)` com significado codificado em comentário.**
   `tb_cliente.status` usa `'A'`, `'I'`, `'B'` (Ativo/Inativo/Bloqueado),
   com o significado documentado apenas em comentário no SQL, e não em uma
   tabela de domínio como foi feito para `status_pedido` e
   `forma_pagamento`. Isso é uma inconsistência de padrão dentro do próprio
   banco — duas formas distintas de representar o mesmo conceito (status).

6. **Falta de constraint `NOT NULL` em `pagamento.dt_pagamento`.** Permite
   registros de pagamento sem data de pagamento, o que é coerente para
   pagamentos pendentes, mas combinado com a falta de um campo `dt_criacao`
   separado, dificulta saber quando o registro de pagamento foi de fato
   criado versus efetivado.

7. **Falta de índice em `pagamento.pedido_id` e `estoque_produto`**, mesmo
   sendo colunas frequentemente usadas em filtros/joins — diferente de
   `pedido.cliente_id` e `item_pedido.pedido_id`, que possuem índices
   dedicados. Isso sugere otimizações pontuais feitas reativamente (ex:
   após problemas de performance em produção), e não um planejamento de
   indexação abrangente.

## 6. Conclusão da etapa de engenharia reversa

A estrutura do banco é funcionalmente coerente — as relações fazem sentido
e os dados são íntegros — mas carrega marcas claras de evolução orgânica
sem padronização. A próxima etapa ([`04_modelo_normalizado`](../sql/04_modelo_normalizado/))
propõe uma versão revisada do modelo, padronizando nomenclatura,
formalizando a tabela de domínio de status do cliente e documentando as
decisões de design que antes existiam apenas implicitamente.
