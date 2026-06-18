-- =====================================================================
-- SCHEMA LEGADO - SISTEMA DE E-COMMERCE
-- =====================================================================
-- Este script simula um banco de dados de e-commerce que já está em
-- produção há alguns anos, sem documentação formal. Propositalmente,
-- ele apresenta características comuns de bancos legados:
--   - nomenclatura inconsistente (mistura de padrões)
--   - poucos comentários
--   - algumas constraints implícitas na lógica da aplicação, não no banco
--   - nomes de colunas nem sempre autoexplicativos
--
-- Esse schema será o ponto de partida para o processo de
-- ENGENHARIA REVERSA documentado na pasta 03_engenharia_reversa.
-- =====================================================================

-- Tabela de clientes
CREATE TABLE tb_cliente (
    id_cliente      SERIAL PRIMARY KEY,
    nome            VARCHAR(150) NOT NULL,
    email           VARCHAR(150) NOT NULL UNIQUE,
    cpf             VARCHAR(14) UNIQUE,
    telefone        VARCHAR(20),
    dt_cadastro     TIMESTAMP DEFAULT NOW(),
    status          CHAR(1) DEFAULT 'A' -- A = Ativo, I = Inativo, B = Bloqueado
);

-- Endereços do cliente (1 cliente pode ter vários endereços)
CREATE TABLE endereco_cliente (
    id_endereco     SERIAL PRIMARY KEY,
    cliente_id      INTEGER NOT NULL REFERENCES tb_cliente(id_cliente),
    logradouro      VARCHAR(200) NOT NULL,
    numero          VARCHAR(10),
    complemento     VARCHAR(100),
    bairro          VARCHAR(100),
    cidade          VARCHAR(100) NOT NULL,
    uf              CHAR(2) NOT NULL,
    cep             VARCHAR(9) NOT NULL,
    principal       BOOLEAN DEFAULT FALSE
);

-- Categorias de produto (autorelacionamento p/ subcategorias)
CREATE TABLE categoria (
    cat_id          SERIAL PRIMARY KEY,
    cat_nome        VARCHAR(100) NOT NULL,
    cat_pai         INTEGER REFERENCES categoria(cat_id)
);

-- Fornecedores
CREATE TABLE fornecedor (
    id_fornecedor   SERIAL PRIMARY KEY,
    razao_social    VARCHAR(200) NOT NULL,
    cnpj            VARCHAR(18) UNIQUE NOT NULL,
    email_contato   VARCHAR(150),
    telefone        VARCHAR(20)
);

-- Produtos
CREATE TABLE produto (
    id_produto      SERIAL PRIMARY KEY,
    sku             VARCHAR(50) UNIQUE NOT NULL,
    nome_produto    VARCHAR(200) NOT NULL,
    descricao       TEXT,
    categoria_id    INTEGER REFERENCES categoria(cat_id),
    fornecedor_id   INTEGER REFERENCES fornecedor(id_fornecedor),
    preco_custo     NUMERIC(10,2) NOT NULL,
    preco_venda     NUMERIC(10,2) NOT NULL,
    ativo           BOOLEAN DEFAULT TRUE,
    dt_cadastro     TIMESTAMP DEFAULT NOW()
);

-- Estoque (separado do produto, controle por depósito)
CREATE TABLE deposito (
    id_deposito     SERIAL PRIMARY KEY,
    nome            VARCHAR(100) NOT NULL,
    cidade          VARCHAR(100),
    uf              CHAR(2)
);

CREATE TABLE estoque_produto (
    produto_id      INTEGER NOT NULL REFERENCES produto(id_produto),
    deposito_id     INTEGER NOT NULL REFERENCES deposito(id_deposito),
    qtd_disponivel  INTEGER NOT NULL DEFAULT 0,
    qtd_reservada   INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY (produto_id, deposito_id)
);

-- Formas de pagamento (tabela de domínio)
CREATE TABLE forma_pagamento (
    id_forma        SERIAL PRIMARY KEY,
    descricao       VARCHAR(50) NOT NULL -- Cartão, Boleto, Pix, etc.
);

-- Status de pedido (tabela de domínio)
CREATE TABLE status_pedido (
    id_status       SERIAL PRIMARY KEY,
    descricao       VARCHAR(50) NOT NULL -- Aguardando, Pago, Enviado, Entregue, Cancelado
);

-- Pedidos
CREATE TABLE pedido (
    id_pedido       SERIAL PRIMARY KEY,
    cliente_id      INTEGER NOT NULL REFERENCES tb_cliente(id_cliente),
    endereco_entrega_id INTEGER REFERENCES endereco_cliente(id_endereco),
    status_id       INTEGER NOT NULL REFERENCES status_pedido(id_status),
    dt_pedido       TIMESTAMP DEFAULT NOW(),
    valor_frete     NUMERIC(10,2) DEFAULT 0,
    valor_desconto  NUMERIC(10,2) DEFAULT 0,
    obs             TEXT
);

-- Itens do pedido
CREATE TABLE item_pedido (
    id_item         SERIAL PRIMARY KEY,
    pedido_id       INTEGER NOT NULL REFERENCES pedido(id_pedido),
    produto_id      INTEGER NOT NULL REFERENCES produto(id_produto),
    quantidade      INTEGER NOT NULL CHECK (quantidade > 0),
    preco_unitario  NUMERIC(10,2) NOT NULL -- preço no momento da compra (snapshot)
);

-- Pagamentos do pedido (pode haver mais de uma tentativa/parcela)
CREATE TABLE pagamento (
    id_pagamento    SERIAL PRIMARY KEY,
    pedido_id       INTEGER NOT NULL REFERENCES pedido(id_pedido),
    forma_id        INTEGER NOT NULL REFERENCES forma_pagamento(id_forma),
    valor           NUMERIC(10,2) NOT NULL,
    dt_pagamento    TIMESTAMP,
    aprovado        BOOLEAN DEFAULT FALSE,
    parcelas        INTEGER DEFAULT 1
);

-- Avaliações de produto (cliente avalia produto comprado)
CREATE TABLE avaliacao_produto (
    id_avaliacao    SERIAL PRIMARY KEY,
    produto_id      INTEGER NOT NULL REFERENCES produto(id_produto),
    cliente_id      INTEGER NOT NULL REFERENCES tb_cliente(id_cliente),
    nota            SMALLINT NOT NULL CHECK (nota BETWEEN 1 AND 5),
    comentario      TEXT,
    dt_avaliacao    TIMESTAMP DEFAULT NOW()
);

-- Cupons de desconto
CREATE TABLE cupom_desconto (
    id_cupom        SERIAL PRIMARY KEY,
    codigo          VARCHAR(30) UNIQUE NOT NULL,
    percentual      NUMERIC(5,2),
    valor_fixo      NUMERIC(10,2),
    dt_validade     DATE,
    ativo           BOOLEAN DEFAULT TRUE
);

-- Relação pedido x cupom (um pedido pode usar 1 cupom; modelado N:N pra flexibilidade futura)
CREATE TABLE pedido_cupom (
    pedido_id       INTEGER NOT NULL REFERENCES pedido(id_pedido),
    cupom_id        INTEGER NOT NULL REFERENCES cupom_desconto(id_cupom),
    PRIMARY KEY (pedido_id, cupom_id)
);

-- Índices adicionais (refletindo otimizações feitas "ao longo do tempo")
CREATE INDEX idx_pedido_cliente ON pedido(cliente_id);
CREATE INDEX idx_pedido_dt ON pedido(dt_pedido);
CREATE INDEX idx_item_pedido_pedido ON item_pedido(pedido_id);
CREATE INDEX idx_produto_categoria ON produto(categoria_id);
CREATE INDEX idx_avaliacao_produto ON avaliacao_produto(produto_id);
