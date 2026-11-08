import os, sys

try:
    import psycopg
except ImportError:
    try:
        import psycopg2 as psycopg
    except ImportError:
        sys.exit("Instale o driver do Postgres: pip install psycopg[binary]")

conn = psycopg.connect(
    host=os.getenv("DB_HOST", "localhost"),
    dbname=os.getenv("DB_NAME", "postgres"),
    user=os.getenv("DB_USER", "app_reservas"),
    password=os.getenv("DB_PASS", "senha_app_123")
)

def rodar(sql, params=(), commit=False, silencioso=False):
    """Executa consultas e repassa fielmente as exceções geradas pelo PostgreSQL."""
    try:
        with conn.cursor() as cur:
            cur.execute(sql, params)
            linhas = cur.fetchall() if cur.description else None
            if commit:
                conn.commit()
                if not silencioso:
                    print("Operação realizada com sucesso!")
            return linhas
    except Exception as e:
        conn.rollback()
        msg = getattr(getattr(e, "diag", None), "message_primary", None) or str(e).strip()
        print(f"Erro do Banco de Dados: {msg}")

while True:
    print("\n--- RESERVA DE SALAS ---")
    print("[1] Agenda [2] Reservar [3] Cancelar [4] Ocupacao Mensal [0] Sair")
    op = input("Opcao: ").strip()

    if op == "1":
        s, d = input("ID da Sala: "), input("Data (AAAA-MM-DD): ")
        res = rodar("SELECT reserva_id, hora_inicio, hora_fim, reservado_por, finalidade, status FROM v_agenda_dia WHERE sala_id = %s AND data_reserva = %s", (s, d))
        for r in (res or []):
            print(f"  [ID #{r[0]}] {r[1]} as {r[2]} | {r[3]} | {r[4]} ({r[5]})")

    elif op == "2":
        s, u = input("ID Sala: "), input("ID Usuario: ")
        ini, fim = input("Inicio (AAAA-MM-DD HH:MM): "), input("Fim (AAAA-MM-DD HH:MM): ")
        fin = input("Finalidade: ")
        res = rodar("SELECT criar_reserva(%s, %s, %s::timestamptz, %s::timestamptz, %s)", (s, u, ini, fim, fin), commit=True, silencioso=True)
        if res and res[0][0]:
            print(f"✅ Reserva [ID #{res[0][0]}] criada com sucesso!")

    elif op == "3":
        rodar("SELECT cancelar_reserva(%s)", (input("ID da Reserva a cancelar: "),), commit=True)

    elif op == "4":
        ano, mes = input("Ano (ex: 2026): "), input("Mes (1-12): ")
        rodar("SELECT atualizar_relatorio_ocupacao();", commit=True, silencioso=True)
        res = rodar("""
            SELECT sala_id, sala_nome, predio, total_efetivas, horas_ocupadas,
                   taxa_ocupacao(sala_id, %s::INT, %s::INT) AS taxa_pct
            FROM mv_ocupacao_mensal 
            WHERE ano = %s AND mes = %s
            ORDER BY horas_ocupadas DESC;
        """, (mes, ano, ano, mes))
        if not res:
            print(f"  Nenhuma reserva concluída ou ativa encontrada para {mes}/{ano}.")
        for r in (res or []):
            print(f"  {r[1]} ({r[2]}): {r[3]} reservas | {r[4]}h ocupadas | Taxa de Ocupacao: {r[5]}%")

    elif op == "0":
        conn.close()
        break
