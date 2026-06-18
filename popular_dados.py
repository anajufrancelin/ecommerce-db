"""
Script para popular o banco ecommerce_legado com dados de exemplo realistas.
Gera volume suficiente para que as queries analíticas tenham resultados
significativos (não apenas dados triviais).
"""
import psycopg2
import random
from datetime import datetime, timedelta
from faker import Faker

fake = Faker("pt_BR")
random.seed(42)
Faker.seed(42)

conn = psycopg2.connect(
    dbname="ecommerce_legado", user="postgres", password="postgres",
    host="localhost", port=5432
)
cur = conn.cursor()

# ---------- Categorias ----------
categorias_principais = ["Eletrônicos", "Moda", "Casa e Decoração", "Esporte e Lazer", "Livros", "Beleza e Saúde"]
subcategorias = {
    "Eletrônicos": ["Smartphones", "Notebooks", "Fones de Ouvido", "TVs"],
    "Moda": ["Camisetas", "Calças", "Calçados", "Acessórios"],
    "Casa e Decoração": ["Móveis", "Iluminação", "Utensílios de Cozinha"],
    "Esporte e Lazer": ["Suplementos", "Equipamentos Fitness", "Roupas Esportivas"],
    "Livros": ["Ficção", "Não-ficção", "Técnico"],
    "Beleza e Saúde": ["Skincare", "Maquiagem", "Higiene Pessoal"],
}

cat_ids = {}
for cat in categorias_principais:
    cur.execute("INSERT INTO categoria (cat_nome) VALUES (%s) RETURNING cat_id", (cat,))
    cat_ids[cat] = cur.fetchone()[0]

subcat_ids = []
for cat, subs in subcategorias.items():
    for sub in subs:
        cur.execute("INSERT INTO categoria (cat_nome, cat_pai) VALUES (%s, %s) RETURNING cat_id", (sub, cat_ids[cat]))
        subcat_ids.append(cur.fetchone()[0])

# ---------- Fornecedores ----------
fornecedor_ids = []
for _ in range(15):
    cur.execute(
        "INSERT INTO fornecedor (razao_social, cnpj, email_contato, telefone) VALUES (%s, %s, %s, %s) RETURNING id_fornecedor",
        (fake.company(), fake.cnpj(), fake.company_email(), fake.phone_number())
    )
    fornecedor_ids.append(cur.fetchone()[0])

# ---------- Produtos ----------
nomes_produtos = [
    "Smartphone Galaxy", "Notebook Pro", "Fone Bluetooth", "Smart TV 50pol",
    "Camiseta Básica", "Calça Jeans", "Tênis Esportivo", "Mochila Urbana",
    "Sofá 3 Lugares", "Lâmpada LED", "Conjunto de Panelas",
    "Whey Protein", "Esteira Elétrica", "Camisa de Time",
    "O Senhor dos Anéis", "Clean Code", "Sapiens",
    "Creme Hidratante", "Paleta de Sombras", "Shampoo Profissional",
]

produto_ids = []
for i in range(120):
    nome_base = random.choice(nomes_produtos)
    nome = f"{nome_base} {fake.word().capitalize()}"
    sku = f"SKU-{1000+i}"
    preco_custo = round(random.uniform(15, 2500), 2)
    preco_venda = round(preco_custo * random.uniform(1.3, 2.2), 2)
    cur.execute(
        """INSERT INTO produto (sku, nome_produto, descricao, categoria_id, fornecedor_id, preco_custo, preco_venda, dt_cadastro)
           VALUES (%s,%s,%s,%s,%s,%s,%s,%s) RETURNING id_produto""",
        (sku, nome, fake.sentence(nb_words=10), random.choice(subcat_ids), random.choice(fornecedor_ids),
         preco_custo, preco_venda, fake.date_time_between(start_date="-3y", end_date="-1y"))
    )
    produto_ids.append(cur.fetchone()[0])

# ---------- Depósitos e Estoque ----------
depositos = [("CD Sudeste", "São Paulo", "SP"), ("CD Sul", "Curitiba", "PR"), ("CD Nordeste", "Recife", "PE")]
dep_ids = []
for nome, cidade, uf in depositos:
    cur.execute("INSERT INTO deposito (nome, cidade, uf) VALUES (%s,%s,%s) RETURNING id_deposito", (nome, cidade, uf))
    dep_ids.append(cur.fetchone()[0])

for pid in produto_ids:
    for did in dep_ids:
        if random.random() < 0.7:  # nem todo produto está em todo depósito
            cur.execute(
                "INSERT INTO estoque_produto (produto_id, deposito_id, qtd_disponivel, qtd_reservada) VALUES (%s,%s,%s,%s)",
                (pid, did, random.randint(0, 500), random.randint(0, 20))
            )

# ---------- Formas de pagamento e Status ----------
formas = ["Cartão de Crédito", "Cartão de Débito", "Boleto", "Pix"]
forma_ids = []
for f in formas:
    cur.execute("INSERT INTO forma_pagamento (descricao) VALUES (%s) RETURNING id_forma", (f,))
    forma_ids.append(cur.fetchone()[0])

status_list = ["Aguardando Pagamento", "Pago", "Em Separação", "Enviado", "Entregue", "Cancelado"]
status_ids = {}
for s in status_list:
    cur.execute("INSERT INTO status_pedido (descricao) VALUES (%s) RETURNING id_status", (s,))
    status_ids[s] = cur.fetchone()[0]

# ---------- Clientes ----------
cliente_ids = []
for _ in range(400):
    nome = fake.name()
    email = fake.unique.email()
    cpf = fake.unique.cpf()
    telefone = fake.phone_number()
    dt_cad = fake.date_time_between(start_date="-3y", end_date="now")
    status = random.choices(["A", "I", "B"], weights=[0.85, 0.12, 0.03])[0]
    cur.execute(
        "INSERT INTO tb_cliente (nome, email, cpf, telefone, dt_cadastro, status) VALUES (%s,%s,%s,%s,%s,%s) RETURNING id_cliente",
        (nome, email, cpf, telefone, dt_cad, status)
    )
    cliente_ids.append(cur.fetchone()[0])

# ---------- Endereços ----------
endereco_por_cliente = {}
for cid in cliente_ids:
    n_end = random.choices([1, 2], weights=[0.8, 0.2])[0]
    end_ids = []
    for i in range(n_end):
        cur.execute(
            """INSERT INTO endereco_cliente (cliente_id, logradouro, numero, complemento, bairro, cidade, uf, cep, principal)
               VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s) RETURNING id_endereco""",
            (cid, fake.street_name(), str(fake.building_number()), (f"Apto {random.randint(1,200)}" if random.random() < 0.3 else None),
             fake.bairro(), fake.city(), fake.estado_sigla(), fake.postcode(), i == 0)
        )
        end_ids.append(cur.fetchone()[0])
    endereco_por_cliente[cid] = end_ids

# ---------- Cupons ----------
cupom_ids = []
for i in range(20):
    codigo = f"PROMO{2023+i%3}{i:02d}"
    is_percentual = random.random() < 0.6
    cur.execute(
        "INSERT INTO cupom_desconto (codigo, percentual, valor_fixo, dt_validade, ativo) VALUES (%s,%s,%s,%s,%s) RETURNING id_cupom",
        (codigo, round(random.uniform(5, 30), 2) if is_percentual else None,
         round(random.uniform(10, 100), 2) if not is_percentual else None,
         fake.date_between(start_date="-1y", end_date="+1y"), random.random() < 0.7)
    )
    cupom_ids.append(cur.fetchone()[0])

# ---------- Pedidos, Itens, Pagamentos ----------
# Pesos de status para simular funil realista (a maioria entregue, alguns cancelados)
status_weights = {
    "Aguardando Pagamento": 0.05, "Pago": 0.10, "Em Separação": 0.05,
    "Enviado": 0.08, "Entregue": 0.62, "Cancelado": 0.10
}

cur.execute("SELECT produto_id, preco_venda FROM produto JOIN (SELECT id_produto FROM produto) p ON produto.id_produto = p.id_produto") if False else None
cur.execute("SELECT id_produto, preco_venda FROM produto")
produto_preco = {row[0]: row[1] for row in cur.fetchall()}

n_pedidos = 1500
for _ in range(n_pedidos):
    cid = random.choice(cliente_ids)
    end_id = random.choice(endereco_por_cliente[cid])
    status_desc = random.choices(list(status_weights.keys()), weights=list(status_weights.values()))[0]
    dt_pedido = fake.date_time_between(start_date="-2y", end_date="now")
    frete = round(random.uniform(0, 45), 2)
    desconto = round(random.uniform(0, 30), 2) if random.random() < 0.3 else 0

    cur.execute(
        """INSERT INTO pedido (cliente_id, endereco_entrega_id, status_id, dt_pedido, valor_frete, valor_desconto)
           VALUES (%s,%s,%s,%s,%s,%s) RETURNING id_pedido""",
        (cid, end_id, status_ids[status_desc], dt_pedido, frete, desconto)
    )
    pedido_id = cur.fetchone()[0]

    # itens do pedido
    n_itens = random.randint(1, 5)
    produtos_pedido = random.sample(produto_ids, n_itens)
    valor_total_itens = 0
    for prod_id in produtos_pedido:
        qtd = random.randint(1, 3)
        preco_unit = float(produto_preco[prod_id])
        valor_total_itens += qtd * preco_unit
        cur.execute(
            "INSERT INTO item_pedido (pedido_id, produto_id, quantidade, preco_unitario) VALUES (%s,%s,%s,%s)",
            (pedido_id, prod_id, qtd, preco_unit)
        )

    # pagamento (se não estiver aguardando pagamento)
    if status_desc != "Aguardando Pagamento":
        valor_pago = round(valor_total_itens + frete - desconto, 2)
        forma_id = random.choice(forma_ids)
        aprovado = status_desc != "Cancelado"
        dt_pag = dt_pedido + timedelta(hours=random.randint(1, 48))
        cur.execute(
            """INSERT INTO pagamento (pedido_id, forma_id, valor, dt_pagamento, aprovado, parcelas)
               VALUES (%s,%s,%s,%s,%s,%s)""",
            (pedido_id, forma_id, valor_pago, dt_pag, aprovado, random.choice([1,1,1,2,3,6,12]))
        )

    # cupom (ocasional)
    if desconto > 0 and random.random() < 0.7:
        cur.execute(
            "INSERT INTO pedido_cupom (pedido_id, cupom_id) VALUES (%s,%s) ON CONFLICT DO NOTHING",
            (pedido_id, random.choice(cupom_ids))
        )

# ---------- Avaliações ----------
for _ in range(800):
    cid = random.choice(cliente_ids)
    pid = random.choice(produto_ids)
    cur.execute(
        "INSERT INTO avaliacao_produto (produto_id, cliente_id, nota, comentario, dt_avaliacao) VALUES (%s,%s,%s,%s,%s)",
        (pid, cid, random.choices([1,2,3,4,5], weights=[0.03,0.05,0.12,0.35,0.45])[0],
         fake.sentence(nb_words=12) if random.random() < 0.6 else None,
         fake.date_time_between(start_date="-2y", end_date="now"))
    )

conn.commit()

# ---------- Resumo ----------
tabelas = ["tb_cliente", "endereco_cliente", "categoria", "fornecedor", "produto",
           "deposito", "estoque_produto", "forma_pagamento", "status_pedido",
           "pedido", "item_pedido", "pagamento", "avaliacao_produto",
           "cupom_desconto", "pedido_cupom"]
print("Resumo de registros inseridos:")
for t in tabelas:
    cur.execute(f"SELECT COUNT(*) FROM {t}")
    print(f"  {t}: {cur.fetchone()[0]}")

cur.close()
conn.close()
print("\nPopulação concluída com sucesso.")
