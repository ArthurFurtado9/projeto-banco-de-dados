-- ============================================================================
-- 02_SEED.SQL: POVOAMENTO INICIAL + 12 MIL RESERVAS COM GENERATE_SERIES
-- ============================================================================

-- 1. Dados Iniciais de Teste
INSERT INTO usuario (nome, email, tipo, matricula) VALUES
('Lucas Silveira', 'lucas@universidade.edu.br', 'ALUNO', '202301'),
('Mariana Costa', 'mariana@universidade.edu.br', 'ALUNO', '202302'),
('Prof. Carlos', 'carlos@universidade.edu.br', 'PROFESSOR', 'P1001'),
('Prof. Ana', 'ana@universidade.edu.br', 'PROFESSOR', 'P1002')
ON CONFLICT (email) DO NOTHING;

INSERT INTO sala (nome, predio, capacidade, tipo, ativa) VALUES
('Sala 101', 'Bloco A', 40, 'SALA_AULA', TRUE),
('Lab 1 (Informatica)', 'Bloco B', 30, 'LABORATORIO', TRUE),
('Lab 2 (Redes)', 'Bloco B', 25, 'LABORATORIO', TRUE),
('Auditorio Nobre', 'Bloco Central', 120, 'AUDITORIO', TRUE),
('Sala 204 (Manutencao)', 'Bloco A', 30, 'SALA_AULA', FALSE)
ON CONFLICT (nome, predio) DO NOTHING;

INSERT INTO recurso (nome, descricao) VALUES
('Projetor 4K', 'Projetor Laser HDMI'),
('Computador Dell i7', 'Desktop para aula pratica'),
('Lousa Digital', 'Tela interativa 75 polegadas')
ON CONFLICT (nome) DO NOTHING;

INSERT INTO sala_recurso (sala_id, recurso_id, quantidade)
SELECT s.id, r.id, 1 FROM sala s, recurso r WHERE s.nome = 'Sala 101' AND r.nome = 'Projetor 4K'
ON CONFLICT DO NOTHING;

INSERT INTO sala_recurso (sala_id, recurso_id, quantidade)
SELECT s.id, r.id, 30 FROM sala s, recurso r WHERE s.nome = 'Lab 1 (Informatica)' AND r.nome = 'Computador Dell i7'
ON CONFLICT DO NOTHING;

-- 2. Carga em Lote: +12.000 Reservas Históricas
ALTER TABLE reserva DISABLE TRIGGER trg_valida_regras_reserva;
ALTER TABLE reserva DISABLE TRIGGER trg_audit_reserva;

INSERT INTO reserva (sala_id, usuario_id, periodo, finalidade, status, criado_em)
SELECT
    s.id,
    (SELECT id FROM usuario ORDER BY random() LIMIT 1),
    tstzrange(calc.base + (calc.slot * INTERVAL '2 hours'), calc.base + ((calc.slot + 1) * INTERVAL '2 hours'), '[)'),
    'Aula / Estudo #' || gs,
    (CASE WHEN (gs % 10 = 0) THEN 'CANCELADA'::status_reserva_enum WHEN (gs % 20 = 0) THEN 'ATIVA'::status_reserva_enum ELSE 'CONCLUIDA'::status_reserva_enum END),
    calc.base
FROM generate_series(1, 12000) AS gs
CROSS JOIN LATERAL (SELECT id FROM sala WHERE ativa = TRUE ORDER BY id OFFSET (gs % 4) LIMIT 1) AS s
CROSS JOIN LATERAL (
    SELECT TIMESTAMPTZ '2024-01-01 08:00:00-03' + ((gs / 16) * INTERVAL '1 day') AS base, (gs % 4) AS slot
) AS calc;

ALTER TABLE reserva ENABLE TRIGGER trg_valida_regras_reserva;
ALTER TABLE reserva ENABLE TRIGGER trg_audit_reserva;

ANALYZE reserva; ANALYZE sala; ANALYZE usuario;
REFRESH MATERIALIZED VIEW mv_ocupacao_mensal;
