-- Consultas analiticas do sistema

-- 1. JOIN: Salas e os recursos disponiveis em cada uma
SELECT s.nome AS sala,
       s.predio,
       s.capacidade,
       COALESCE(STRING_AGG(r.nome || ' (' || sr.quantidade || ')', ', '), 'Sem recursos') AS recursos
FROM sala s
LEFT JOIN sala_recurso sr ON s.id = sr.sala_id
LEFT JOIN recurso r ON r.id = sr.recurso_id
GROUP BY s.id, s.nome, s.predio, s.capacidade
ORDER BY s.predio, s.nome;

-- 2. GROUP BY / HAVING: Salas com pelo menos 10 reservas validas e media de duracao
SELECT s.nome,
       COUNT(r.id) AS total_reservas,
       ROUND(AVG(EXTRACT(EPOCH FROM (upper(r.periodo) - lower(r.periodo))) / 3600.0)::NUMERIC, 2) AS media_horas
FROM sala s
JOIN reserva r ON s.id = r.sala_id
WHERE r.status IN ('ATIVA', 'CONCLUIDA')
GROUP BY s.id, s.nome
HAVING COUNT(r.id) >= 10
ORDER BY total_reservas DESC;

-- 3. SUBCONSULTA: Usuarios com numero de reservas acima da media geral
SELECT u.nome,
       u.tipo,
       COUNT(r.id) AS total_reservas
FROM usuario u
JOIN reserva r ON u.id = r.usuario_id
GROUP BY u.id, u.nome, u.tipo
HAVING COUNT(r.id) > (
    SELECT AVG(qtd)
    FROM (SELECT COUNT(id) AS qtd FROM reserva GROUP BY usuario_id) t
)
ORDER BY total_reservas DESC;

-- 4. CTE (WITH): Total de reservas, cancelamentos e horas ocupadas por predio
WITH dados AS (
    SELECT s.predio,
           r.status,
           EXTRACT(EPOCH FROM (upper(r.periodo) - lower(r.periodo))) / 3600.0 AS duracao
    FROM reserva r
    JOIN sala s ON s.id = r.sala_id
)
SELECT predio,
       COUNT(*) AS total,
       COUNT(CASE WHEN status = 'CANCELADA' THEN 1 END) AS canceladas,
       ROUND((COUNT(CASE WHEN status = 'CANCELADA' THEN 1 END)::NUMERIC / COUNT(*)) * 100, 2) AS taxa_cancel_pct,
       ROUND(SUM(CASE WHEN status <> 'CANCELADA' THEN duracao ELSE 0 END)::NUMERIC, 2) AS horas_ocupadas
FROM dados
GROUP BY predio
ORDER BY total DESC;

-- 5. WINDOW FUNCTION: Ranking das salas mais reservadas dentro de cada predio
SELECT s.predio,
       s.nome AS sala,
       COUNT(r.id) AS total_reservas,
       RANK() OVER (PARTITION BY s.predio ORDER BY COUNT(r.id) DESC) AS rank_no_predio
FROM sala s
LEFT JOIN reserva r ON s.id = r.sala_id
GROUP BY s.predio, s.nome
ORDER BY s.predio, rank_no_predio;

-- Testes de desempenho com EXPLAIN ANALYZE antes e depois de criar 2 indices

-- Indice 1: busca por usuario e status
DROP INDEX IF EXISTS idx_reserva_usr_status;
EXPLAIN (ANALYZE, BUFFERS)
SELECT id, periodo FROM reserva WHERE usuario_id = 2 AND status = 'ATIVA';

CREATE INDEX idx_reserva_usr_status ON reserva (usuario_id, status);
EXPLAIN (ANALYZE, BUFFERS)
SELECT id, periodo FROM reserva WHERE usuario_id = 2 AND status = 'ATIVA';

-- Indice 2: filtro por data de inicio da reserva
DROP INDEX IF EXISTS idx_reserva_inicio;
EXPLAIN (ANALYZE, BUFFERS)
SELECT id, sala_id FROM reserva WHERE lower(periodo) BETWEEN '2024-05-01' AND '2024-05-31';

CREATE INDEX idx_reserva_inicio ON reserva ((lower(periodo)));
EXPLAIN (ANALYZE, BUFFERS)
SELECT id, sala_id FROM reserva WHERE lower(periodo) BETWEEN '2024-05-01' AND '2024-05-31';
