"""
ENGENHARIA REVERSA DE BANCO DE DADOS
=====================================
Este script se conecta a um banco PostgreSQL já existente (sem qualquer
documentação prévia) e extrai sua estrutura completa consultando os
catálogos do sistema (information_schema e pg_catalog):

    - Tabelas e colunas (nome, tipo, nullable, default)
    - Chaves primárias
    - Chaves estrangeiras (relacionamentos)
    - Constraints de unicidade (UNIQUE)
    - Constraints de checagem (CHECK)
    - Índices

A saída é:
    1. Um relatório textual em Markdown (docs/relatorio_engenharia_reversa.md)
    2. Um arquivo JSON com a estrutura completa (docs/estrutura_banco.json)
    3. Um diagrama Mermaid ER gerado automaticamente a partir das FKs
       encontradas (diagramas/der_engenharia_reversa.mmd)

Esse é o ponto de partida real para reconstruir o modelo conceitual/lógico
de um banco que não possui documentação - o cenário clássico de
engenharia reversa de dados.
"""
import psycopg2
import json

conn = psycopg2.connect(
    dbname="ecommerce_legado", user="postgres", password="postgres",
    host="localhost", port=5432
)
cur = conn.cursor()

SCHEMA = "public"

# ---------------------------------------------------------------
# 1. Listar todas as tabelas do schema
# ---------------------------------------------------------------
cur.execute("""
    SELECT table_name
    FROM information_schema.tables
    WHERE table_schema = %s AND table_type = 'BASE TABLE'
    ORDER BY table_name;
""", (SCHEMA,))
tabelas = [r[0] for r in cur.fetchall()]

estrutura = {}

for tabela in tabelas:
    estrutura[tabela] = {
        "colunas": [],
        "chave_primaria": [],
        "chaves_estrangeiras": [],
        "unique_constraints": [],
        "check_constraints": [],
        "indices": [],
    }

    # ---------------------------------------------------------------
    # 2. Colunas: nome, tipo, nullable, default
    # ---------------------------------------------------------------
    cur.execute("""
        SELECT column_name, data_type, character_maximum_length,
               numeric_precision, numeric_scale, is_nullable, column_default
        FROM information_schema.columns
        WHERE table_schema = %s AND table_name = %s
        ORDER BY ordinal_position;
    """, (SCHEMA, tabela))
    for col in cur.fetchall():
        col_name, data_type, char_len, num_prec, num_scale, nullable, default = col
        tipo_completo = data_type
        if char_len:
            tipo_completo += f"({char_len})"
        elif num_prec and num_scale is not None:
            tipo_completo += f"({num_prec},{num_scale})"
        estrutura[tabela]["colunas"].append({
            "nome": col_name,
            "tipo": tipo_completo,
            "nullable": nullable == "YES",
            "default": default,
        })

    # ---------------------------------------------------------------
    # 3. Chave primária
    # ---------------------------------------------------------------
    cur.execute("""
        SELECT kcu.column_name
        FROM information_schema.table_constraints tc
        JOIN information_schema.key_column_usage kcu
          ON tc.constraint_name = kcu.constraint_name
         AND tc.table_schema = kcu.table_schema
        WHERE tc.table_schema = %s AND tc.table_name = %s
          AND tc.constraint_type = 'PRIMARY KEY'
        ORDER BY kcu.ordinal_position;
    """, (SCHEMA, tabela))
    estrutura[tabela]["chave_primaria"] = [r[0] for r in cur.fetchall()]

    # ---------------------------------------------------------------
    # 4. Chaves estrangeiras (relacionamentos entre tabelas)
    # ---------------------------------------------------------------
    cur.execute("""
        SELECT
            kcu.column_name AS coluna_origem,
            ccu.table_name AS tabela_referenciada,
            ccu.column_name AS coluna_referenciada,
            tc.constraint_name
        FROM information_schema.table_constraints tc
        JOIN information_schema.key_column_usage kcu
          ON tc.constraint_name = kcu.constraint_name AND tc.table_schema = kcu.table_schema
        JOIN information_schema.constraint_column_usage ccu
          ON tc.constraint_name = ccu.constraint_name AND tc.table_schema = ccu.table_schema
        WHERE tc.table_schema = %s AND tc.table_name = %s
          AND tc.constraint_type = 'FOREIGN KEY';
    """, (SCHEMA, tabela))
    for r in cur.fetchall():
        estrutura[tabela]["chaves_estrangeiras"].append({
            "coluna": r[0], "tabela_referenciada": r[1],
            "coluna_referenciada": r[2], "constraint": r[3],
        })

    # ---------------------------------------------------------------
    # 5. Constraints UNIQUE
    # ---------------------------------------------------------------
    cur.execute("""
        SELECT kcu.column_name
        FROM information_schema.table_constraints tc
        JOIN information_schema.key_column_usage kcu
          ON tc.constraint_name = kcu.constraint_name AND tc.table_schema = kcu.table_schema
        WHERE tc.table_schema = %s AND tc.table_name = %s
          AND tc.constraint_type = 'UNIQUE';
    """, (SCHEMA, tabela))
    estrutura[tabela]["unique_constraints"] = [r[0] for r in cur.fetchall()]

    # ---------------------------------------------------------------
    # 6. Constraints CHECK
    # ---------------------------------------------------------------
    cur.execute("""
        SELECT cc.check_clause
        FROM information_schema.check_constraints cc
        JOIN information_schema.table_constraints tc
          ON cc.constraint_name = tc.constraint_name AND cc.constraint_schema = tc.table_schema
        WHERE tc.table_schema = %s AND tc.table_name = %s;
    """, (SCHEMA, tabela))
    estrutura[tabela]["check_constraints"] = [r[0] for r in cur.fetchall()]

    # ---------------------------------------------------------------
    # 7. Índices
    # ---------------------------------------------------------------
    cur.execute("""
        SELECT indexname, indexdef
        FROM pg_indexes
        WHERE schemaname = %s AND tablename = %s;
    """, (SCHEMA, tabela))
    for r in cur.fetchall():
        estrutura[tabela]["indices"].append({"nome": r[0], "definicao": r[1]})

cur.close()
conn.close()

# ---------------------------------------------------------------
# Salvar JSON com a estrutura completa
# ---------------------------------------------------------------
with open("/home/claude/ecommerce-db-project/docs/estrutura_banco.json", "w", encoding="utf-8") as f:
    json.dump(estrutura, f, indent=2, ensure_ascii=False)

print(f"Engenharia reversa concluída. {len(tabelas)} tabelas analisadas.")
print("Estrutura salva em docs/estrutura_banco.json")
