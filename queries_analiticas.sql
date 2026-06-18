-- =====================================================================
-- QUERIES ANALÍTICAS - ANÁLISE DE DADOS DE E-COMMERCE
-- =====================================================================
-- Conjunto de consultas SQL para responder perguntas de negócio comuns
-- em análise de dados de e-commerce. Executadas sobre o banco
-- "ecommerce_legado" (schema public).
-- =====================================================================

-- -----------------------------------------------------------------
-- 1. FATURAMENTO MENSAL (apenas pedidos pagos/entregues)
-- -----------------------------------------------------------------
SELECT
    DATE_TRUNC('month', p.dt_pedido)::DATE AS mes,
    COUNT(DISTINCT p.id_pedido) AS qtd_pedidos,
    ROUND(SUM(ip.quantidade * ip.preco_unitario), 2) AS faturamento_bruto,
    ROUND(SUM(ip.quantidade * ip.preco_unitario) / COUNT(DISTINCT p.id_pedido), 2) AS ticket_medio
FROM pedido p
JOIN item_pedido ip ON ip.pedido_id = p.id_pedido
JOIN status_pedido sp ON sp.id_status = p.status_id
WHERE sp.descricao IN ('Pago', 'Em Separação', 'Enviado', 'Entregue')
GROUP BY 1
ORDER BY 1;


-- -----------------------------------------------------------------
-- 2. TOP 10 PRODUTOS MAIS VENDIDOS (por quantidade e por receita)
-- -----------------------------------------------------------------
SELECT
    pr.id_produto,
    pr.nome_produto,
    SUM(ip.quantidade) AS qtd_total_vendida,
    ROUND(SUM(ip.quantidade * ip.preco_unitario), 2) AS receita_total
FROM item_pedido ip
JOIN produto pr ON pr.id_produto = ip.produto_id
JOIN pedido p ON p.id_pedido = ip.pedido_id
JOIN status_pedido sp ON sp.id_status = p.status_id
WHERE sp.descricao != 'Cancelado'
GROUP BY pr.id_produto, pr.nome_produto
ORDER BY receita_total DESC
LIMIT 10;


-- -----------------------------------------------------------------
-- 3. TAXA DE CANCELAMENTO DE PEDIDOS POR MÊS
-- -----------------------------------------------------------------
SELECT
    DATE_TRUNC('month', p.dt_pedido)::DATE AS mes,
    COUNT(*) AS total_pedidos,
    COUNT(*) FILTER (WHERE sp.descricao = 'Cancelado') AS pedidos_cancelados,
    ROUND(
        100.0 * COUNT(*) FILTER (WHERE sp.descricao = 'Cancelado') / COUNT(*), 2
    ) AS taxa_cancelamento_pct
FROM pedido p
JOIN status_pedido sp ON sp.id_status = p.status_id
GROUP BY 1
ORDER BY 1;


-- -----------------------------------------------------------------
-- 4. RANKING DE CATEGORIAS POR RECEITA (considerando subcategorias)
-- -----------------------------------------------------------------
WITH categoria_raiz AS (
    -- CTE recursiva para subir até a categoria-pai (nível 1) de cada produto,
    -- já que produtos estão vinculados a subcategorias
    SELECT c.cat_id, c.cat_nome,
           COALESCE(pai.cat_nome, c.cat_nome) AS categoria_principal
    FROM categoria c
    LEFT JOIN categoria pai ON pai.cat_id = c.cat_pai
)
SELECT
    cr.categoria_principal,
    COUNT(DISTINCT ip.pedido_id) AS qtd_pedidos,
    ROUND(SUM(ip.quantidade * ip.preco_unitario), 2) AS receita_total
FROM item_pedido ip
JOIN produto pr ON pr.id_produto = ip.produto_id
JOIN categoria_raiz cr ON cr.cat_id = pr.categoria_id
JOIN pedido p ON p.id_pedido = ip.pedido_id
JOIN status_pedido sp ON sp.id_status = p.status_id
WHERE sp.descricao != 'Cancelado'
GROUP BY cr.categoria_principal
ORDER BY receita_total DESC;


-- -----------------------------------------------------------------
-- 5. CLIENTES "EM RISCO DE CHURN": compraram no passado mas não nos
--    últimos 6 meses (considerando a data mais recente de pedido no banco)
-- -----------------------------------------------------------------
WITH ultima_compra AS (
    SELECT cliente_id, MAX(dt_pedido) AS dt_ultima_compra
    FROM pedido
    GROUP BY cliente_id
),
data_referencia AS (
    SELECT MAX(dt_pedido) AS hoje FROM pedido
)
SELECT
    c.id_cliente,
    c.nome,
    c.email,
    uc.dt_ultima_compra,
    (SELECT hoje FROM data_referencia) - uc.dt_ultima_compra::DATE AS dias_sem_comprar
FROM tb_cliente c
JOIN ultima_compra uc ON uc.cliente_id = c.id_cliente
WHERE uc.dt_ultima_compra < (SELECT hoje - INTERVAL '6 months' FROM data_referencia)
  AND c.status = 'A'
ORDER BY dias_sem_comprar DESC
LIMIT 20;


-- -----------------------------------------------------------------
-- 6. CURVA ABC DE PRODUTOS (classificação por contribuição de receita)
-- -----------------------------------------------------------------
WITH receita_produto AS (
    SELECT
        pr.id_produto,
        pr.nome_produto,
        SUM(ip.quantidade * ip.preco_unitario) AS receita
    FROM item_pedido ip
    JOIN produto pr ON pr.id_produto = ip.produto_id
    JOIN pedido p ON p.id_pedido = ip.pedido_id
    JOIN status_pedido sp ON sp.id_status = p.status_id
    WHERE sp.descricao != 'Cancelado'
    GROUP BY pr.id_produto, pr.nome_produto
),
receita_acumulada AS (
    SELECT
        *,
        SUM(receita) OVER (ORDER BY receita DESC) AS receita_cumulativa,
        SUM(receita) OVER () AS receita_total_geral
    FROM receita_produto
)
SELECT
    id_produto,
    nome_produto,
    ROUND(receita, 2) AS receita,
    ROUND(100.0 * receita_cumulativa / receita_total_geral, 2) AS pct_acumulado,
    CASE
        WHEN 100.0 * receita_cumulativa / receita_total_geral <= 80 THEN 'A'
        WHEN 100.0 * receita_cumulativa / receita_total_geral <= 95 THEN 'B'
        ELSE 'C'
    END AS classe_abc
FROM receita_acumulada
ORDER BY receita DESC;


-- -----------------------------------------------------------------
-- 7. AVALIAÇÃO MÉDIA POR PRODUTO E DISTRIBUIÇÃO DE NOTAS
-- -----------------------------------------------------------------
SELECT
    pr.id_produto,
    pr.nome_produto,
    COUNT(av.id_avaliacao) AS qtd_avaliacoes,
    ROUND(AVG(av.nota), 2) AS nota_media,
    COUNT(*) FILTER (WHERE av.nota <= 2) AS qtd_notas_baixas
FROM produto pr
JOIN avaliacao_produto av ON av.produto_id = pr.id_produto
GROUP BY pr.id_produto, pr.nome_produto
HAVING COUNT(av.id_avaliacao) >= 3
ORDER BY nota_media DESC, qtd_avaliacoes DESC
LIMIT 15;


-- -----------------------------------------------------------------
-- 8. EFETIVIDADE DOS CUPONS DE DESCONTO
-- -----------------------------------------------------------------
SELECT
    cd.codigo,
    COUNT(pc.pedido_id) AS qtd_usos,
    ROUND(SUM(p.valor_desconto), 2) AS desconto_total_concedido,
    ROUND(AVG(p.valor_desconto), 2) AS desconto_medio_por_uso
FROM cupom_desconto cd
JOIN pedido_cupom pc ON pc.cupom_id = cd.id_cupom
JOIN pedido p ON p.id_pedido = pc.pedido_id
GROUP BY cd.codigo
ORDER BY qtd_usos DESC;


-- -----------------------------------------------------------------
-- 9. NÍVEL DE ESTOQUE CRÍTICO (produtos com baixa disponibilidade)
-- -----------------------------------------------------------------
SELECT
    pr.id_produto,
    pr.nome_produto,
    d.nome AS deposito,
    ep.qtd_disponivel,
    ep.qtd_reservada,
    (ep.qtd_disponivel - ep.qtd_reservada) AS saldo_real
FROM estoque_produto ep
JOIN produto pr ON pr.id_produto = ep.produto_id
JOIN deposito d ON d.id_deposito = ep.deposito_id
WHERE (ep.qtd_disponivel - ep.qtd_reservada) < 10
ORDER BY saldo_real ASC;


-- -----------------------------------------------------------------
-- 10. TICKET MÉDIO POR FORMA DE PAGAMENTO E TAXA DE APROVAÇÃO
-- -----------------------------------------------------------------
SELECT
    fp.descricao AS forma_pagamento,
    COUNT(*) AS qtd_transacoes,
    ROUND(100.0 * COUNT(*) FILTER (WHERE pg.aprovado) / COUNT(*), 2) AS taxa_aprovacao_pct,
    ROUND(AVG(pg.valor), 2) AS ticket_medio,
    ROUND(AVG(pg.parcelas), 1) AS media_parcelas
FROM pagamento pg
JOIN forma_pagamento fp ON fp.id_forma = pg.forma_id
GROUP BY fp.descricao
ORDER BY qtd_transacoes DESC;
