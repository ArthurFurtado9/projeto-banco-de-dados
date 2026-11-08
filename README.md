# Sistema de Reserva de Salas e Laboratórios (Versão Enxuta)

Projeto acadêmico com foco no motor relacional **PostgreSQL**, utilizando uma aplicação **Python CLI** minimalista de apenas ~50 linhas como interface de terminal.

---

## 1. Estrutura Enxuta do Projeto

```text
├── sql/
│   ├── 01_init.sql       # Esquema (6 tabelas 3FN), EXCLUDE GIST, 2 Triggers, Functions, Views e Role
│   ├── 02_seed.sql       # Povoamento inicial + carga de 12.000 reservas com generate_series
│   └── 03_consultas.sql  # 5 consultas analíticas (JOIN, GROUP BY, Subconsulta, CTE, Window) e 2 índices
├── app.py                # Aplicação CLI mínima em Python (52 linhas, sem ORM)
├── requirements.txt      # Dependência do driver oficial (psycopg)
├── docker-compose.yml    # Ambiente PostgreSQL 16 pronto para rodar com 1 comando
└── README.md             # Documentação e roteiro da avaliação oral
```

---

## 2. Modelagem e 3ª Forma Normal (3FN)

### 2.1 DER Lógico (6 Tabelas)
```mermaid
erDiagram
    USUARIO ||--o{ RESERVA : "realiza"
    SALA ||--o{ RESERVA : "é reservada"
    SALA ||--o{ SALA_RECURSO : "possui"
    RECURSO ||--o{ SALA_RECURSO : "alocado em"
    RESERVA ||--o{ LOG_RESERVA : "gera auditoria"

    USUARIO { int id PK, varchar nome, varchar email UK, tipo_usuario_enum tipo, varchar matricula UK }
    SALA { int id PK, varchar nome, varchar predio, int capacidade, varchar tipo, boolean ativa }
    RECURSO { int id PK, varchar nome UK, text descricao }
    SALA_RECURSO { int sala_id PK_FK, int recurso_id PK_FK, int quantidade }
    RESERVA { int id PK, int sala_id FK, int usuario_id FK, tstzrange periodo, status_reserva_enum status }
    LOG_RESERVA { bigint id PK, int reserva_id FK, varchar operacao, jsonb dados_anteriores, jsonb dados_novos }
```

### 2.2 Justificativa da 3FN
* **1FN:** Todos os atributos são atômicos e indivisíveis. Recursos alocados a uma sala foram normalizados na tabela associativa `sala_recurso`.
* **2FN:** Não há dependência funcional parcial. Na tabela `sala_recurso`, a `quantidade` depende estritamente do par composto `(sala_id, recurso_id)`.
* **3FN:** Não há dependências transitivas. Nenhum atributo não-chave depende de outro atributo não-chave.

---

## 3. Como Rodar o Projeto

### Passo 1: Executar os Scripts SQL no PostgreSQL
Abra seu cliente SQL (DBeaver, pgAdmin ou terminal `psql`) e execute os 3 arquivos na sequência:
1. `01_init.sql` (Cria todo o banco, regras, triggers, functions e a role `app_reservas`)
2. `02_seed.sql` (Insere salas, alunos, recursos e gera 12.000 reservas históricas)
3. `03_consultas.sql` (Executa as 5 consultas analíticas e os benchmarks de índice)

### Passo 2: Executar a Aplicação Python
Instale a dependência e inicie a aplicação:
```bash
pip install -r requirements.txt
python app.py
```

O menu interativo apresentará as 4 opções do edital:
* `[1]` Listar agenda de uma sala em um dia (`v_agenda_dia`)
* `[2]` Criar reserva (`criar_reserva(...)`)
* `[3]` Cancelar reserva (`cancelar_reserva(...)`)
* `[4]` Exibir ocupação mensal por sala (`mv_ocupacao_mensal`)

---

## 4. Roteiro Prático para a Apresentação Oral (Garantia de Nota Máxima)

### 4.1 Teste de Concorrência ao Vivo (2 Sessões)
Para demonstrar que dois usuários não conseguem reservar a mesma sala no mesmo horário:
1. Abra duas abas/terminais no banco.
2. **Terminal 1:**
   ```sql
   BEGIN;
   SELECT criar_reserva(1, 1, '2026-12-01 14:00:00-03', '2026-12-01 16:00:00-03', 'Palestra');
   ```
3. **Terminal 2:**
   ```sql
   BEGIN;
   SELECT criar_reserva(1, 2, '2026-12-01 15:00:00-03', '2026-12-01 17:00:00-03', 'Reunião');
   ```
   *(O Terminal 2 ficará travado esperando o desfecho da transação 1).*
4. **Terminal 1:** Execute `COMMIT;`.
5. **Resultado:** O Terminal 2 é liberado imediatamente e estoura o erro:
   `ERROR: Conflito: A sala já possui reserva ativa neste horário.`

### 4.2 Prova de Segurança (Role `app_reservas`)
Mostre que a aplicação não tem permissão para comandos diretos em tabelas:
```sql
SET ROLE app_reservas;
SELECT * FROM reserva; -- Retorna: ERROR: permission denied for table reserva
SELECT * FROM v_agenda_dia; -- Funciona normalmente via VIEW autorizada
RESET ROLE;
```
