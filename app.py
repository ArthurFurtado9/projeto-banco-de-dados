import psycopg

def conectar():
    return psycopg.connect(
        host="localhost",
        port="5432",
        dbname="postgres",
        user="app_reservas",
        password="senha_app_123",
    )

def listar_agenda(conn):
    sala_id = input("ID da sala: ").strip()
    data = input("Data (AAAA-MM-DD): ").strip()

    try:
        with conn.cursor() as cur:
            cur.execute(
                """
                SELECT reserva_id, hora_inicio, hora_fim, reservado_por, finalidade, status
                FROM v_agenda_dia
                WHERE sala_id = %s AND data_reserva = %s::date
                """,
                (int(sala_id), data),
            )
            reservas = cur.fetchall()

        if not reservas:
            print("Nenhuma reserva encontrada para essa sala nessa data.")
            return

        print(f"\nAgenda da sala {sala_id} em {data}:")
        for r in reservas:
            print(f"  [ID {r[0]}] {r[1]} - {r[2]} | {r[3]} | {r[4]} ({r[5]})")
    except ValueError:
        print("ID da sala deve ser um numero inteiro.")
    except psycopg.Error as e:
        conn.rollback()
        print("Erro do banco:", str(e).splitlines()[0])

def criar_reserva(conn):
    sala_id = input("ID da sala: ").strip()
    usuario_id = input("ID do usuario: ").strip()
    inicio = input("Inicio (AAAA-MM-DD HH:MM): ").strip()
    fim = input("Fim (AAAA-MM-DD HH:MM): ").strip()
    finalidade = input("Finalidade: ").strip()

    try:
        with conn.cursor() as cur:
            cur.execute(
                "SELECT criar_reserva(%s, %s, %s::timestamptz, %s::timestamptz, %s)",
                (int(sala_id), int(usuario_id), inicio, fim, finalidade),
            )
            novo_id = cur.fetchone()[0]
        conn.commit()
        print(f"Reserva criada com sucesso! ID: {novo_id}")
    except ValueError:
        print("IDs devem ser numeros inteiros.")
    except psycopg.Error as e:
        conn.rollback()
        print("Erro do banco:", str(e).splitlines()[0])

def cancelar_reserva(conn):
    reserva_id = input("ID da reserva para cancelar: ").strip()

    try:
        with conn.cursor() as cur:
            cur.execute("SELECT cancelar_reserva(%s)", (int(reserva_id),))
        conn.commit()
        print(f"Reserva {reserva_id} cancelada com sucesso!")
    except ValueError:
        print("ID da reserva deve ser um numero inteiro.")
    except psycopg.Error as e:
        conn.rollback()
        print("Erro do banco:", str(e).splitlines()[0])

def relatorio_ocupacao(conn):
    ano = input("Ano (ex: 2024): ").strip()
    mes = input("Mes (1 a 12): ").strip()

    try:
        ano_int = int(ano)
        mes_int = int(mes)

        with conn.cursor() as cur:
            cur.execute("SELECT atualizar_relatorio_ocupacao()")
            conn.commit()

            cur.execute(
                """
                SELECT sala_nome, predio, total_efetivas, horas_ocupadas,
                       taxa_ocupacao(sala_id, %s, %s) AS taxa_pct
                FROM mv_ocupacao_mensal
                WHERE ano = %s AND mes = %s
                ORDER BY horas_ocupadas DESC
                """,
                (mes_int, ano_int, ano_int, mes_int),
            )
            linhas = cur.fetchall()

        if not linhas:
            print(f"Nenhuma reserva encontrada em {mes_int:02d}/{ano_int}.")
            return

        print(f"\nOcupacao das salas em {mes_int:02d}/{ano_int}:")
        for r in linhas:
            print(f"  {r[0]} ({r[1]}): {r[2]} reservas | {r[3]}h ocupadas | Taxa: {r[4]}%")
    except ValueError:
        print("Ano e mes devem ser numeros inteiros.")
    except psycopg.Error as e:
        conn.rollback()
        print("Erro do banco:", str(e).splitlines()[0])

def main():
    try:
        conn = conectar()
    except psycopg.Error as e:
        print("Nao foi possivel conectar ao PostgreSQL:", e)
        return

    try:
        while True:
            print("\n=== Sistema de Reserva de Salas ===")
            print("1 - Listar agenda de uma sala no dia")
            print("2 - Criar reserva")
            print("3 - Cancelar reserva")
            print("4 - Relatorio de ocupacao mensal")
            print("0 - Sair")
            opcao = input("Escolha uma opcao: ").strip()

            if opcao == "1":
                listar_agenda(conn)
            elif opcao == "2":
                criar_reserva(conn)
            elif opcao == "3":
                cancelar_reserva(conn)
            elif opcao == "4":
                relatorio_ocupacao(conn)
            elif opcao == "0":
                break
            else:
                print("Opcao invalida.")
    finally:
        conn.close()

if __name__ == "__main__":
    main()
