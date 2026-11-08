-- ============================================================================
-- 01_INIT.SQL: ESTRUTURA COMPLETA, REGRAS, FUNÇÕES, VIEWS E SEGURANÇA
-- ============================================================================
CREATE EXTENSION IF NOT EXISTS btree_gist;

-- 1. TIPOS E DOMÍNIOS
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'status_reserva_enum') THEN
        CREATE TYPE status_reserva_enum AS ENUM ('ATIVA', 'CANCELADA', 'CONCLUIDA');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'tipo_usuario_enum') THEN
        CREATE TYPE tipo_usuario_enum AS ENUM ('ALUNO', 'PROFESSOR', 'FUNCIONARIO');
    END IF;
END $$;

CREATE DOMAIN email_institucional AS VARCHAR(150)
CHECK (VALUE ~* '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$');

-- 2. TABELAS (6 Tabelas em 3FN)
CREATE TABLE IF NOT EXISTS usuario (
    id SERIAL PRIMARY KEY,
    nome VARCHAR(100) NOT NULL,
    email email_institucional NOT NULL UNIQUE,
    tipo tipo_usuario_enum NOT NULL DEFAULT 'ALUNO',
    matricula VARCHAR(20) NOT NULL UNIQUE
);

CREATE TABLE IF NOT EXISTS sala (
    id SERIAL PRIMARY KEY,
    nome VARCHAR(50) NOT NULL,
    predio VARCHAR(50) NOT NULL,
    capacidade INT NOT NULL CHECK (capacidade > 0),
    tipo VARCHAR(30) NOT NULL DEFAULT 'SALA_AULA',
    ativa BOOLEAN NOT NULL DEFAULT TRUE,
    CONSTRAINT uq_sala_predio UNIQUE (nome, predio)
);

CREATE TABLE IF NOT EXISTS recurso (
    id SERIAL PRIMARY KEY,
    nome VARCHAR(60) NOT NULL UNIQUE,
    descricao TEXT
);

CREATE TABLE IF NOT EXISTS sala_recurso (
    sala_id INT NOT NULL REFERENCES sala(id) ON DELETE CASCADE,
    recurso_id INT NOT NULL REFERENCES recurso(id) ON DELETE RESTRICT,
    quantidade INT NOT NULL DEFAULT 1 CHECK (quantidade > 0),
    PRIMARY KEY (sala_id, recurso_id)
);

CREATE TABLE IF NOT EXISTS reserva (
    id SERIAL PRIMARY KEY,
    sala_id INT NOT NULL REFERENCES sala(id) ON DELETE RESTRICT,
    usuario_id INT NOT NULL REFERENCES usuario(id) ON DELETE RESTRICT,
    periodo TSTZRANGE NOT NULL,
    finalidade VARCHAR(200) NOT NULL,
    status status_reserva_enum NOT NULL DEFAULT 'ATIVA',
    criado_em TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT chk_periodo CHECK (NOT isempty(periodo) AND lower(periodo) < upper(periodo)),
    CONSTRAINT chk_duracao CHECK (upper(periodo) - lower(periodo) <= INTERVAL '8 hours'),
    CONSTRAINT sem_conflito EXCLUDE USING gist (sala_id WITH =, periodo WITH &&) WHERE (status = 'ATIVA')
);

CREATE TABLE IF NOT EXISTS log_reserva (
    id BIGSERIAL PRIMARY KEY,
    reserva_id INT REFERENCES reserva(id) ON DELETE SET NULL,
    operacao VARCHAR(10) NOT NULL,
    dados_anteriores JSONB,
    dados_novos JSONB,
    usuario_banco VARCHAR(100) NOT NULL DEFAULT CURRENT_USER,
    data_hora TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- 3. TRIGGERS (Auditoria e Limite de 3 Reservas Futuras)
CREATE OR REPLACE FUNCTION fn_audit_reserva() RETURNS TRIGGER AS $$
BEGIN
    IF (TG_OP = 'INSERT') THEN
        INSERT INTO log_reserva (reserva_id, operacao, dados_novos) VALUES (NEW.id, 'INSERT', to_jsonb(NEW));
    ELSIF (TG_OP = 'UPDATE') THEN
        INSERT INTO log_reserva (reserva_id, operacao, dados_anteriores, dados_novos) VALUES (NEW.id, 'UPDATE', to_jsonb(OLD), to_jsonb(NEW));
    ELSIF (TG_OP = 'DELETE') THEN
        INSERT INTO log_reserva (reserva_id, operacao, dados_anteriores) VALUES (OLD.id, 'DELETE', to_jsonb(OLD));
    END IF;
    RETURN COALESCE(NEW, OLD);
END; $$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_audit_reserva ON reserva;
CREATE TRIGGER trg_audit_reserva AFTER INSERT OR UPDATE OR DELETE ON reserva FOR EACH ROW EXECUTE FUNCTION fn_audit_reserva();

CREATE OR REPLACE FUNCTION fn_valida_regras_reserva() RETURNS TRIGGER AS $$
DECLARE v_total INT;
BEGIN
    IF (TG_OP = 'UPDATE' AND NEW.status = 'CANCELADA') THEN RETURN NEW; END IF;
    IF (lower(NEW.periodo) < CURRENT_TIMESTAMP) THEN
        RAISE EXCEPTION 'Não é permitido criar reserva para horários passados.';
    END IF;
    IF (NEW.status = 'ATIVA') THEN
        SELECT COUNT(*) INTO v_total FROM reserva 
        WHERE usuario_id = NEW.usuario_id AND status = 'ATIVA' AND lower(periodo) > CURRENT_TIMESTAMP AND id <> COALESCE(NEW.id, -1);
        IF v_total >= 3 THEN
            RAISE EXCEPTION 'Usuário % atingiu o limite máximo de 3 reservas ativas futuras.', NEW.usuario_id;
        END IF;
    END IF;
    RETURN NEW;
END; $$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_valida_regras_reserva ON reserva;
CREATE TRIGGER trg_valida_regras_reserva BEFORE INSERT OR UPDATE ON reserva FOR EACH ROW EXECUTE FUNCTION fn_valida_regras_reserva();

-- 4. STORED FUNCTIONS (Com SECURITY DEFINER para role app_reservas)
CREATE OR REPLACE FUNCTION criar_reserva(
    p_sala_id INT, p_usuario_id INT, p_inicio TIMESTAMPTZ, p_fim TIMESTAMPTZ, p_finalidade TEXT
) RETURNS INT AS $$
DECLARE v_id INT;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM sala WHERE id = p_sala_id AND ativa = TRUE) THEN
        RAISE EXCEPTION 'Sala % inexistente ou inativa.', p_sala_id;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM usuario WHERE id = p_usuario_id) THEN
        RAISE EXCEPTION 'Usuário % não encontrado.', p_usuario_id;
    END IF;
    BEGIN
        INSERT INTO reserva (sala_id, usuario_id, periodo, finalidade, status)
        VALUES (p_sala_id, p_usuario_id, tstzrange(p_inicio, p_fim, '[)'), p_finalidade, 'ATIVA')
        RETURNING id INTO v_id;
        RETURN v_id;
    EXCEPTION WHEN exclusion_violation THEN
        RAISE EXCEPTION 'Conflito: A sala já possui reserva ativa neste horário.';
    END;
END; $$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION cancelar_reserva(p_reserva_id INT) RETURNS VOID AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM reserva WHERE id = p_reserva_id) THEN
        RAISE EXCEPTION 'Reserva % não encontrada.', p_reserva_id;
    END IF;
    IF EXISTS (SELECT 1 FROM reserva WHERE id = p_reserva_id AND status = 'CANCELADA') THEN
        RAISE EXCEPTION 'Reserva % já está cancelada.', p_reserva_id;
    END IF;
    IF EXISTS (SELECT 1 FROM reserva WHERE id = p_reserva_id AND upper(periodo) < CURRENT_TIMESTAMP) THEN
        RAISE EXCEPTION 'Não é permitido cancelar reservas passadas.';
    END IF;
    UPDATE reserva SET status = 'CANCELADA' WHERE id = p_reserva_id;
END; $$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION taxa_ocupacao(p_sala_id INT, p_mes INT, p_ano INT) RETURNS NUMERIC AS $$
DECLARE
    v_ini TIMESTAMPTZ := make_timestamptz(p_ano, p_mes, 1, 0, 0, 0, 'America/Sao_Paulo');
    v_fim TIMESTAMPTZ := v_ini + INTERVAL '1 month';
    v_horas_totais NUMERIC := 14.0 * (SELECT COUNT(*) FROM generate_series(v_ini, v_fim - INTERVAL '1 day', '1 day') d WHERE EXTRACT(DOW FROM d) BETWEEN 1 AND 5);
    v_horas_ocupadas NUMERIC;
BEGIN
    SELECT COALESCE(SUM(EXTRACT(EPOCH FROM (LEAST(upper(periodo), v_fim) - GREATEST(lower(periodo), v_ini))) / 3600.0), 0)
    INTO v_horas_ocupadas FROM reserva
    WHERE sala_id = p_sala_id AND status = 'ATIVA' AND periodo && tstzrange(v_ini, v_fim);
    RETURN ROUND(((v_horas_ocupadas / NULLIF(v_horas_totais, 0)) * 100.0)::NUMERIC, 2);
END; $$ LANGUAGE plpgsql SECURITY DEFINER;

-- 5. VIEWS E MATERIALIZED VIEW
CREATE OR REPLACE VIEW v_agenda_dia AS
SELECT r.id AS reserva_id, s.id AS sala_id, s.nome AS sala_nome, s.predio, u.nome AS reservado_por,
       r.finalidade, r.status, (lower(r.periodo) AT TIME ZONE 'America/Sao_Paulo')::DATE AS data_reserva,
       to_char(lower(r.periodo) AT TIME ZONE 'America/Sao_Paulo', 'HH24:MI') AS hora_inicio,
       to_char(upper(r.periodo) AT TIME ZONE 'America/Sao_Paulo', 'HH24:MI') AS hora_fim
FROM reserva r JOIN sala s ON s.id = r.sala_id JOIN usuario u ON u.id = r.usuario_id
ORDER BY lower(r.periodo);

CREATE OR REPLACE VIEW v_reservas_usuario AS
SELECT r.id AS reserva_id, u.id AS usuario_id, u.nome AS usuario_nome, s.nome AS sala_nome,
       r.finalidade, r.status, lower(r.periodo) AS inicio, upper(r.periodo) AS fim
FROM reserva r JOIN usuario u ON u.id = r.usuario_id JOIN sala s ON s.id = r.sala_id;

DROP MATERIALIZED VIEW IF EXISTS mv_ocupacao_mensal CASCADE;
CREATE MATERIALIZED VIEW mv_ocupacao_mensal AS
SELECT s.id AS sala_id, s.nome AS sala_nome, s.predio,
       EXTRACT(YEAR FROM (lower(r.periodo) AT TIME ZONE 'America/Sao_Paulo'))::INT AS ano,
       EXTRACT(MONTH FROM (lower(r.periodo) AT TIME ZONE 'America/Sao_Paulo'))::INT AS mes,
       COUNT(r.id) AS total_reservas,
       COUNT(CASE WHEN r.status = 'CANCELADA' THEN 1 END) AS total_canceladas,
       COUNT(CASE WHEN r.status = 'ATIVA' THEN 1 END) AS total_efetivas,
       ROUND(COALESCE(SUM(CASE WHEN r.status = 'ATIVA' THEN EXTRACT(EPOCH FROM (upper(r.periodo) - lower(r.periodo))) / 3600.0 ELSE 0 END), 0)::NUMERIC, 2) AS horas_ocupadas
FROM sala s LEFT JOIN reserva r ON s.id = r.sala_id
GROUP BY s.id, s.nome, s.predio, ano, mes;

CREATE UNIQUE INDEX IF NOT EXISTS idx_mv_ocupacao ON mv_ocupacao_mensal (sala_id, COALESCE(ano, 0), COALESCE(mes, 0));

CREATE OR REPLACE FUNCTION atualizar_relatorio_ocupacao() RETURNS VOID AS $$
BEGIN
    REFRESH MATERIALIZED VIEW mv_ocupacao_mensal;
END; $$ LANGUAGE plpgsql SECURITY DEFINER;

-- 6. SEGURANÇA E ROLE (Menor Privilégio)
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'app_reservas') THEN
        CREATE ROLE app_reservas WITH LOGIN PASSWORD 'senha_app_123';
    END IF;
END $$;
GRANT USAGE ON SCHEMA public TO app_reservas;
REVOKE ALL ON ALL TABLES IN SCHEMA public FROM app_reservas;
GRANT SELECT ON v_agenda_dia, v_reservas_usuario, mv_ocupacao_mensal TO app_reservas;
GRANT EXECUTE ON FUNCTION criar_reserva, cancelar_reserva, taxa_ocupacao, atualizar_relatorio_ocupacao TO app_reservas;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO app_reservas;
