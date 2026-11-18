-- Limpa os dados existentes e reinicia os IDs para permitir reexecutar o seed sem conflito
TRUNCATE TABLE log_reserva, reserva, sala_recurso, recurso, sala, usuario RESTART IDENTITY CASCADE;

-- Usuarios iniciais (IDs 1 a 4)
INSERT INTO usuario (nome, email, tipo, matricula) VALUES
('Lucas Silveira', 'lucas@universidade.edu.br', 'ALUNO', '202301'),
('Mariana Costa', 'mariana@universidade.edu.br', 'ALUNO', '202302'),
('Prof. Carlos', 'carlos@universidade.edu.br', 'PROFESSOR', 'P1001'),
('Prof. Ana', 'ana@universidade.edu.br', 'PROFESSOR', 'P1002');

-- Salas e laboratorios (IDs 1 a 4 ativas, ID 5 inativa)
INSERT INTO sala (nome, predio, capacidade, tipo, ativa) VALUES
('Sala 101', 'Bloco A', 40, 'SALA_AULA', TRUE),
('Lab 1 (Informatica)', 'Bloco B', 30, 'LABORATORIO', TRUE),
('Lab 2 (Redes)', 'Bloco B', 25, 'LABORATORIO', TRUE),
('Auditorio Nobre', 'Bloco Central', 120, 'AUDITORIO', TRUE),
('Sala 204 (Manutencao)', 'Bloco A', 30, 'SALA_AULA', FALSE);

-- Recursos
INSERT INTO recurso (nome, descricao) VALUES
('Projetor 4K', 'Projetor Laser HDMI'),
('Computador Dell i7', 'Desktop para aula pratica'),
('Lousa Digital', 'Tela interativa 75 polegadas');

-- Relacao N:N entre salas e recursos
INSERT INTO sala_recurso (sala_id, recurso_id, quantidade) VALUES
(1, 1, 1),
(2, 1, 1),
(2, 2, 30),
(3, 2, 25),
(4, 1, 2),
(4, 3, 1);

-- Gera 12.000 reservas historicas usando generate_series e random()
-- Desativa triggers temporariamente para permitir inserir datas passadas de 2024
ALTER TABLE reserva DISABLE TRIGGER trg_valida_regras_reserva;
ALTER TABLE reserva DISABLE TRIGGER trg_audit_reserva;

INSERT INTO reserva (sala_id, usuario_id, periodo, finalidade, status, criado_em)
SELECT
    ((gs - 1) % 4) + 1 AS sala_id,
    floor(random() * 4 + 1)::int AS usuario_id,
    tstzrange(
        TIMESTAMPTZ '2024-01-01 08:00:00' + (((gs - 1) / 16) * INTERVAL '1 day') + ((((gs - 1) / 4) % 4) * INTERVAL '2 hours'),
        TIMESTAMPTZ '2024-01-01 08:00:00' + (((gs - 1) / 16) * INTERVAL '1 day') + (((((gs - 1) / 4) % 4) + 1) * INTERVAL '2 hours'),
        '[)'
    ) AS periodo,
    'Aula / Estudo #' || gs AS finalidade,
    CASE
        WHEN gs % 10 = 0 THEN 'CANCELADA'::status_reserva_enum
        WHEN gs % 20 = 0 THEN 'ATIVA'::status_reserva_enum
        ELSE 'CONCLUIDA'::status_reserva_enum
    END AS status,
    TIMESTAMPTZ '2024-01-01 08:00:00' + (((gs - 1) / 16) * INTERVAL '1 day')
FROM generate_series(1, 12000) AS gs;

ALTER TABLE reserva ENABLE TRIGGER trg_valida_regras_reserva;
ALTER TABLE reserva ENABLE TRIGGER trg_audit_reserva;

ANALYZE reserva;
ANALYZE sala;
ANALYZE usuario;

REFRESH MATERIALIZED VIEW mv_ocupacao_mensal;
