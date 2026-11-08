-- ============================================================================
-- 03_CONSULTAS.SQL: 5 CONSULTAS ANALÍTICAS + 2 ÍNDICES COM EXPLAIN ANALYZE
-- ============================================================================

-- 1. JOIN: Salas e seus recursos agregados
SELECT s.nome AS sala, s.predio, s.capacidade,
       COALESCE(STRING_AGG(r.nome || ' (' || sr.quantidade || ')', ', '), 'Sem recursos') AS recursos
FROM sala s
LEFT JOIN sala_recurso sr ON s.id = sr.sala_id
LEFT JOIN recurso r ON r.id = sr.recurso_id
GROUP BY s.id, s.nome, s.predio, s.capacidade;

-- 2. GROUP BY / HAVING: Salas com mais de 10 reservas válidas
SELECT s.nome, COUNT(r.id) AS total_reservas,
       ROUND(AVG(EXTRACT(EPOCH FROM (upper(r.periodo) - lower(r.periodo))) / 3600.0)::NUMERIC, 2) AS media_horas
FROM sala s JOIN reserva r ON s.id = r.sala_id
WHERE r.status IN ('ATIVA', 'CONCLUIDA')
GROUP BY s.id, s.nome HAVING COUNT(r.id) >= 10;

-- 3. SUBCONSULTA: Usuários com volume de reservas acima da média global
SELECT u.nome, u.tipo, COUNT(r.id) AS total_reservas
FROM usuario u JOIN reserva r ON u.id = r.usuario_id
GROUP BY u.id, u.nome, u.tipo
HAVING COUNT(r.id) > (SELECT AVG(qtd) FROM (SELECT COUNT(id) AS qtd FROM reserva GROUP BY usuario_id) t);

-- 4. CTE (WITH): Taxa de cancelamento agrupada por prédio
WITH dados AS (
    SELECT s.predio, r.status, EXTRACT(EPOCH FROM (upper(r.periodo) - lower(r.periodo))) / 3600.0 AS duracao
    FROM reserva r JOIN sala s ON s.id = r.sala_id
)
SELECT predio, COUNT(*) AS total,
       COUNT(CASE WHEN status = 'CANCELADA' THEN 1 END) AS canceladas,
       ROUND((COUNT(CASE WHEN status = 'CANCELADA' THEN 1 END)::NUMERIC / COUNT(*)) * 100, 2) AS taxa_cancel_pct
FROM dados GROUP BY predio;

-- 5. WINDOW FUNCTION: Ranking das salas mais requisitadas por prédio
SELECT s.predio, s.nome AS sala, COUNT(r.id) AS total_reservas,
       RANK() OVER (PARTITION BY s.predio ORDER BY COUNT(r.id) DESC) AS rank_no_predio
FROM sala s LEFT JOIN reserva r ON s.id = r.sala_id
GROUP BY s.predio, s.nome;

-- ============================================================================
-- BENCHMARK: 2 ÍNDICES COM EXPLAIN (ANALYZE, BUFFERS)
-- ============================================================================

-- Índice 1: Composto (usuario_id, status)
DROP INDEX IF EXISTS idx_reserva_usr_status;
EXPLAIN (ANALYZE, BUFFERS) SELECT id, periodo FROM reserva WHERE usuario_id = 2 AND status = 'ATIVA'; -- ANTES (Seq Scan)
CREATE INDEX idx_reserva_usr_status ON reserva (usuario_id, status);
EXPLAIN (ANALYZE, BUFFERS) SELECT id, periodo FROM reserva WHERE usuario_id = 2 AND status = 'ATIVA'; -- DEPOIS (Index Scan)

-- Índice 2: Expressão B-Tree em lower(periodo)
DROP INDEX IF EXISTS idx_reserva_inicio;
EXPLAIN (ANALYZE, BUFFERS) SELECT id, sala_id FROM reserva WHERE lower(periodo) BETWEEN '2024-05-01' AND '2024-05-31'; -- ANTES
CREATE INDEX idx_reserva_inicio ON reserva ((lower(periodo)));
EXPLAIN (ANALYZE, BUFFERS) SELECT id, sala_id FROM reserva WHERE lower(periodo) BETWEEN '2024-05-01' AND '2024-05-31'; -- DEPOIS
