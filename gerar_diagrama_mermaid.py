"""
Gera um diagrama ER em sintaxe Mermaid a partir do JSON produzido pela
engenharia reversa (docs/estrutura_banco.json).

Esse diagrama representa o que foi DESCOBERTO no banco legado, refletindo
fielmente as tabelas, colunas-chave e relacionamentos reais — e não um
desenho feito "de memória".
"""
import json

with open("/home/claude/ecommerce-db-project/docs/estrutura_banco.json", encoding="utf-8") as f:
    estrutura = json.load(f)

# Mapeamento simplificado de tipos para o diagrama (Mermaid ER é limitado)
def simplificar_tipo(tipo):
    tipo = tipo.split("(")[0]
    mapa = {
        "character varying": "varchar",
        "timestamp without time zone": "timestamp",
        "numeric": "numeric",
        "boolean": "boolean",
        "integer": "int",
        "smallint": "smallint",
        "text": "text",
        "character": "char",
        "date": "date",
    }
    return mapa.get(tipo, tipo)

linhas = ["erDiagram"]

# --- Relacionamentos (a partir das FKs encontradas) ---
relacionamentos = []
for tabela, info in estrutura.items():
    for fk in info["chaves_estrangeiras"]:
        ref_tabela = fk["tabela_referenciada"]
        # Heurística de cardinalidade: se a FK faz parte de uma PK composta,
        # tende a ser N:N (tabela associativa); senão, 1:N simples.
        pk = info["chave_primaria"]
        if fk["coluna"] in pk and len(pk) > 1:
            cardinalidade = "}o--o{"
        else:
            cardinalidade = "||--o{"
        relacionamentos.append((ref_tabela, tabela, cardinalidade, fk["coluna"]))

for ref_tabela, tabela, card, coluna in relacionamentos:
    linhas.append(f'    {ref_tabela} {card} {tabela} : "{coluna}"')

# --- Definição das entidades (colunas principais: PK, FK e NOT NULL relevantes) ---
for tabela, info in estrutura.items():
    linhas.append(f"    {tabela} {{")
    pk_cols = set(info["chave_primaria"])
    fk_cols = {fk["coluna"] for fk in info["chaves_estrangeiras"]}
    for col in info["colunas"]:
        tipo = simplificar_tipo(col["tipo"])
        marcador = ""
        if col["nome"] in pk_cols:
            marcador = "PK"
        elif col["nome"] in fk_cols:
            marcador = "FK"
        if marcador:
            linhas.append(f'        {tipo} {col["nome"]} {marcador}')
        else:
            linhas.append(f'        {tipo} {col["nome"]}')
    linhas.append("    }")

mermaid_code = "\n".join(linhas)

with open("/home/claude/ecommerce-db-project/diagramas/der_engenharia_reversa.mmd", "w", encoding="utf-8") as f:
    f.write(mermaid_code)

print("Diagrama Mermaid gerado em diagramas/der_engenharia_reversa.mmd")
print(f"Total de relacionamentos identificados: {len(relacionamentos)}")
