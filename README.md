# E-commerce DB — Engenharia Reversa, Modelagem e Análise de Dados

Projeto de portfólio que simula um cenário comum no dia a dia de quem
trabalha com banco de dados: **assumir um sistema legado sem documentação
e precisar entendê-lo, corrigir seus problemas estruturais e extrair
valor analítico dele.**

O projeto cobre o ciclo completo: criação de um banco "legado" realista →
engenharia reversa real (via consultas ao `information_schema` do
PostgreSQL) → identificação de inconsistências → proposta de modelo
normalizado/refatorado → queries analíticas de negócio.

## Por que esse projeto

A maior parte dos projetos de portfólio com banco de dados começa do
zero: modela-se um sistema "ideal" e cria-se o banco perfeito desde o
início. Na prática profissional, é muito mais comum o caminho inverso —
herdar um banco que já existe, sem diagrama, sem dicionário de dados, e
precisar reconstruir esse entendimento. Este projeto foi desenhado para
demonstrar exatamente essa competência.

## Tecnologias e competências demonstradas

- **SQL** (DDL, DML, window functions, CTEs recursivas, agregações complexas)
- **PostgreSQL** (information_schema, pg_catalog, constraints, índices)
- **Modelagem de dados** (modelo conceitual, lógico, normalização)
- **Engenharia reversa de banco de dados**
- **Análise de dados** (KPIs de e-commerce: faturamento, churn, curva ABC, taxa de aprovação de pagamento)
- **Python** (psycopg2, Faker, para geração de dados e automação da extração de metadados)

## Estrutura do repositório

```
ecommerce-db-project/
├── sql/
│   ├── 01_schema_legado/          → Script de criação do banco "legado" (ponto de partida)
│   ├── 02_dados_exemplo/          → Script Python que popula o banco com dados realistas
│   ├── 03_engenharia_reversa/     → Scripts que extraem a estrutura do banco e geram o diagrama ER
│   ├── 04_modelo_normalizado/     → Proposta de schema refatorado, corrigindo os problemas encontrados
│   └── 05_queries_analiticas/     → Queries SQL respondendo perguntas de negócio
├── diagramas/
│   ├── der_engenharia_reversa.mmd     → Diagrama ER gerado a partir do banco legado (Mermaid)
│   └── der_modelo_normalizado.mmd     → Diagrama ER do modelo proposto (Mermaid)
└── docs/
    ├── relatorio_engenharia_reversa.md → Relatório completo do processo e achados
    └── estrutura_banco.json            → Estrutura completa extraída (saída bruta da engenharia reversa)
```

## O cenário

Um sistema de e-commerce está em produção há alguns anos. Não existe
diagrama ER, não existe dicionário de dados, e os desenvolvedores
originais não estão mais na empresa. O schema em
[`01_schema_legado/schema_legado.sql`](./sql/01_schema_legado/schema_legado.sql)
representa esse banco: 15 tabelas cobrindo clientes, produtos,
categorias hierárquicas, fornecedores, estoque multi-depósito, pedidos,
pagamentos, avaliações e cupons de desconto — com as inconsistências de
nomenclatura e padronização típicas de um sistema que cresceu de forma
orgânica.

## Etapa 1 — Engenharia reversa

O script [`extrair_estrutura.py`](./sql/03_engenharia_reversa/extrair_estrutura.py)
se conecta ao banco e extrai, via `information_schema` e `pg_catalog`:
tabelas, colunas, tipos, chaves primárias, chaves estrangeiras,
constraints UNIQUE/CHECK e índices — sem nenhuma suposição manual.

A partir dessa extração, [`gerar_diagrama_mermaid.py`](./sql/03_engenharia_reversa/gerar_diagrama_mermaid.py)
monta automaticamente o diagrama ER (visível em
[`diagramas/der_engenharia_reversa.mmd`](./diagramas/der_engenharia_reversa.mmd)),
e o [relatório completo](./docs/relatorio_engenharia_reversa.md) documenta
17 relacionamentos identificados e 7 inconsistências de modelagem
encontradas (nomenclatura inconsistente, ausência de tabela de domínio
para status do cliente, índices faltantes em colunas críticas, entre
outras).

## Etapa 2 — Modelo normalizado proposto

Com base nos achados, [`schema_normalizado.sql`](./sql/04_modelo_normalizado/schema_normalizado.sql)
propõe a versão corrigida do banco: nomenclatura padronizada, status do
cliente convertido em tabela de domínio, constraints de integridade
explicitadas (incluindo a regra "um cliente avalia um produto uma única
vez"), comentários de documentação embutidos no próprio schema (`COMMENT
ON`), e os índices identificados como faltantes.

## Etapa 3 — Análise de dados

As 10 queries em [`queries_analiticas.sql`](./sql/05_queries_analiticas/queries_analiticas.sql)
respondem perguntas reais de negócio sobre os dados de exemplo gerados
(400 clientes, 120 produtos, 1.500 pedidos, ~4.500 itens vendidos):
evolução do faturamento mensal, produtos mais vendidos, taxa de
cancelamento ao longo do tempo, ranking de categorias, clientes em risco
de churn, curva ABC de produtos, avaliação média por produto, efetividade
de cupons, níveis críticos de estoque (incluindo casos reais encontrados
de estoque reservado superior ao disponível — um problema de qualidade de
dados identificado na própria análise) e taxa de aprovação por forma de
pagamento.

## Como reproduzir

```bash
# 1. Criar o banco legado
psql -U postgres -c "CREATE DATABASE ecommerce_legado;"
psql -U postgres -d ecommerce_legado -f sql/01_schema_legado/schema_legado.sql

# 2. Popular com dados de exemplo
pip install faker psycopg2-binary
python3 sql/02_dados_exemplo/popular_dados.py

# 3. Executar a engenharia reversa
python3 sql/03_engenharia_reversa/extrair_estrutura.py
python3 sql/03_engenharia_reversa/gerar_diagrama_mermaid.py

# 4. Criar o modelo normalizado proposto (banco separado, para comparação)
psql -U postgres -c "CREATE DATABASE ecommerce_normalizado;"
psql -U postgres -d ecommerce_normalizado -f sql/04_modelo_normalizado/schema_normalizado.sql

# 5. Rodar as queries analíticas
psql -U postgres -d ecommerce_legado -f sql/05_queries_analiticas/queries_analiticas.sql
```

> Os scripts assumem usuário `postgres` com senha `postgres` em
> `localhost:5432`. Ajuste a string de conexão em `popular_dados.py` e
> `extrair_estrutura.py` conforme seu ambiente.

## Autor

Projeto desenvolvido como peça de portfólio para demonstrar competências
em banco de dados, modelagem de dados, engenharia reversa e análise de
dados com SQL.
