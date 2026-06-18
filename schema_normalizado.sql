-- =====================================================================
-- MODELO REFATORADO E NORMALIZADO - SISTEMA DE E-COMMERCE
-- =====================================================================
-- Esta versão corrige as inconsistências identificadas no relatório de
-- engenharia reversa (docs/relatorio_engenharia_reversa.md), aplicando:
--
--   1. Padronização de nomenclatura: todas as tabelas no singular, sem
--      prefixos (tb_, etc.), e todas as PKs seguindo o padrão `id`
--      (chave simples, sempre chamada apenas "id" dentro da própria tabela)
--   2. Status do cliente convertido de CHAR(1) para tabela de domínio,
--      no mesmo padrão usado para status_pedido e forma_pagamento
--   3. Constraint UNIQUE composta em avaliacao para impedir duplicidade
--      (1 avaliação por cliente/produto)
--   4. Documentação explícita do "preço snapshot" via comentário de coluna
--   5. Índices adicionados nos pontos identificados como faltantes
--   6. Verificação de Forma Normal: o modelo já estava em 3FN nas
--      dependências funcionais identificadas; os ajustes abaixo são de
--      padronização e governança, não de normalização estrutural
--      (não havia dependências transitivas ou parciais problemáticas)
-- =====================================================================

CREATE SCHEMA IF NOT EXISTS ecommerce;
SET search_path TO ecommerce;

-- Tabela de domínio: status do cliente (antes era CHAR(1) com significado implícito)
CREATE TABLE status_cliente (
    id          SERIAL PRIMARY KEY,
    descricao   VARCHAR(50) NOT NULL UNIQUE
);

CREATE TABLE cliente (
    id              SERIAL PRIMARY KEY,
    nome            VARCHAR(150) NOT NULL,
    email           VARCHAR(150) NOT NULL UNIQUE,
    cpf             VARCHAR(14) UNIQUE,
    telefone        VARCHAR(20),
    data_cadastro   TIMESTAMP NOT NULL DEFAULT NOW(),
    status_id       INTEGER NOT NULL REFERENCES status_cliente(id)
);

CREATE TABLE endereco (
    id              SERIAL PRIMARY KEY,
    cliente_id      INTEGER NOT NULL REFERENCES cliente(id) ON DELETE CASCADE,
    logradouro      VARCHAR(200) NOT NULL,
    numero          VARCHAR(10),
    complemento     VARCHAR(100),
    bairro          VARCHAR(100),
    cidade          VARCHAR(100) NOT NULL,
    uf              CHAR(2) NOT NULL,
    cep             VARCHAR(9) NOT NULL,
    principal       BOOLEAN NOT NULL DEFAULT FALSE
);

CREATE TABLE categoria (
    id              SERIAL PRIMARY KEY,
    nome            VARCHAR(100) NOT NULL,
    categoria_pai_id INTEGER REFERENCES categoria(id)
);

CREATE TABLE fornecedor (
    id              SERIAL PRIMARY KEY,
    razao_social    VARCHAR(200) NOT NULL,
    cnpj            VARCHAR(18) NOT NULL UNIQUE,
    email_contato   VARCHAR(150),
    telefone        VARCHAR(20)
);

CREATE TABLE produto (
    id              SERIAL PRIMARY KEY,
    sku             VARCHAR(50) NOT NULL UNIQUE,
    nome            VARCHAR(200) NOT NULL,
    descricao       TEXT,
    categoria_id    INTEGER REFERENCES categoria(id),
    fornecedor_id   INTEGER REFERENCES fornecedor(id),
    preco_custo     NUMERIC(10,2) NOT NULL CHECK (preco_custo >= 0),
    preco_venda     NUMERIC(10,2) NOT NULL CHECK (preco_venda >= 0),
    ativo           BOOLEAN NOT NULL DEFAULT TRUE,
    data_cadastro   TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE TABLE deposito (
    id              SERIAL PRIMARY KEY,
    nome            VARCHAR(100) NOT NULL,
    cidade          VARCHAR(100),
    uf              CHAR(2)
);

CREATE TABLE estoque (
    produto_id      INTEGER NOT NULL REFERENCES produto(id),
    deposito_id     INTEGER NOT NULL REFERENCES deposito(id),
    qtd_disponivel  INTEGER NOT NULL DEFAULT 0 CHECK (qtd_disponivel >= 0),
    qtd_reservada   INTEGER NOT NULL DEFAULT 0 CHECK (qtd_reservada >= 0),
    PRIMARY KEY (produto_id, deposito_id)
);

CREATE TABLE forma_pagamento (
    id          SERIAL PRIMARY KEY,
    descricao   VARCHAR(50) NOT NULL UNIQUE
);

CREATE TABLE status_pedido (
    id          SERIAL PRIMARY KEY,
    descricao   VARCHAR(50) NOT NULL UNIQUE
);

CREATE TABLE pedido (
    id                      SERIAL PRIMARY KEY,
    cliente_id              INTEGER NOT NULL REFERENCES cliente(id),
    endereco_entrega_id     INTEGER NOT NULL REFERENCES endereco(id),
    status_id               INTEGER NOT NULL REFERENCES status_pedido(id),
    data_pedido             TIMESTAMP NOT NULL DEFAULT NOW(),
    valor_frete             NUMERIC(10,2) NOT NULL DEFAULT 0 CHECK (valor_frete >= 0),
    valor_desconto          NUMERIC(10,2) NOT NULL DEFAULT 0 CHECK (valor_desconto >= 0),
    observacao              TEXT
);

CREATE TABLE item_pedido (
    id              SERIAL PRIMARY KEY,
    pedido_id       INTEGER NOT NULL REFERENCES pedido(id) ON DELETE CASCADE,
    produto_id      INTEGER NOT NULL REFERENCES produto(id),
    quantidade      INTEGER NOT NULL CHECK (quantidade > 0),
    -- preco_unitario_snapshot: preserva o preço de venda do produto NO MOMENTO
    -- da compra. Não é redundância de modelagem -- é necessário para manter
    -- o histórico correto de vendas mesmo que o preço do produto mude depois.
    preco_unitario_snapshot NUMERIC(10,2) NOT NULL CHECK (preco_unitario_snapshot >= 0)
);

CREATE TABLE pagamento (
    id              SERIAL PRIMARY KEY,
    pedido_id       INTEGER NOT NULL REFERENCES pedido(id),
    forma_id        INTEGER NOT NULL REFERENCES forma_pagamento(id),
    valor           NUMERIC(10,2) NOT NULL CHECK (valor >= 0),
    data_registro   TIMESTAMP NOT NULL DEFAULT NOW(),
    data_pagamento  TIMESTAMP,
    aprovado        BOOLEAN NOT NULL DEFAULT FALSE,
    parcelas        INTEGER NOT NULL DEFAULT 1 CHECK (parcelas > 0)
);

CREATE TABLE avaliacao (
    id              SERIAL PRIMARY KEY,
    produto_id      INTEGER NOT NULL REFERENCES produto(id),
    cliente_id      INTEGER NOT NULL REFERENCES cliente(id),
    nota            SMALLINT NOT NULL CHECK (nota BETWEEN 1 AND 5),
    comentario      TEXT,
    data_avaliacao  TIMESTAMP NOT NULL DEFAULT NOW(),
    -- Regra de negócio explicitada: um cliente avalia um produto uma única vez
    CONSTRAINT uq_avaliacao_cliente_produto UNIQUE (cliente_id, produto_id)
);

CREATE TABLE cupom_desconto (
    id              SERIAL PRIMARY KEY,
    codigo          VARCHAR(30) NOT NULL UNIQUE,
    percentual      NUMERIC(5,2) CHECK (percentual BETWEEN 0 AND 100),
    valor_fixo      NUMERIC(10,2) CHECK (valor_fixo >= 0),
    data_validade   DATE,
    ativo           BOOLEAN NOT NULL DEFAULT TRUE,
    -- Garante que o cupom é OU percentual OU valor fixo, nunca os dois (nem nenhum)
    CONSTRAINT chk_tipo_desconto CHECK (
        (percentual IS NOT NULL AND valor_fixo IS NULL) OR
        (percentual IS NULL AND valor_fixo IS NOT NULL)
    )
);

CREATE TABLE pedido_cupom (
    pedido_id   INTEGER NOT NULL REFERENCES pedido(id),
    cupom_id    INTEGER NOT NULL REFERENCES cupom_desconto(id),
    PRIMARY KEY (pedido_id, cupom_id)
);

-- ---------------------------------------------------------------------
-- Índices (incluindo os identificados como faltantes na engenharia reversa)
-- ---------------------------------------------------------------------
CREATE INDEX idx_pedido_cliente ON pedido(cliente_id);
CREATE INDEX idx_pedido_data ON pedido(data_pedido);
CREATE INDEX idx_pedido_status ON pedido(status_id);
CREATE INDEX idx_item_pedido_pedido ON item_pedido(pedido_id);
CREATE INDEX idx_item_pedido_produto ON item_pedido(produto_id);
CREATE INDEX idx_produto_categoria ON produto(categoria_id);
CREATE INDEX idx_avaliacao_produto ON avaliacao(produto_id);
CREATE INDEX idx_pagamento_pedido ON pagamento(pedido_id);      -- faltava no legado
CREATE INDEX idx_estoque_produto ON estoque(produto_id);         -- faltava no legado
CREATE INDEX idx_endereco_cliente ON endereco(cliente_id);

-- ---------------------------------------------------------------------
-- Comentários de documentação (dicionário de dados embutido no schema)
-- ---------------------------------------------------------------------
COMMENT ON TABLE cliente IS 'Clientes cadastrados na plataforma de e-commerce';
COMMENT ON TABLE pedido IS 'Pedidos realizados pelos clientes';
COMMENT ON TABLE item_pedido IS 'Itens (produtos) que compõem cada pedido';
COMMENT ON COLUMN item_pedido.preco_unitario_snapshot IS
    'Preço do produto no momento da compra. Mantido separado de produto.preco_venda para preservar histórico fiel de vendas.';
COMMENT ON TABLE estoque IS 'Controle de quantidade de produtos por depósito/centro de distribuição';
COMMENT ON CONSTRAINT uq_avaliacao_cliente_produto ON avaliacao IS
    'Garante que um cliente avalie um mesmo produto apenas uma vez';
