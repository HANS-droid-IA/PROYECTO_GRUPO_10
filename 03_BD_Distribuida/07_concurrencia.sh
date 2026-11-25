#!/bin/bash
# =====================================================================
# BD Distribuida - 07: control de concurrencia y bloqueo distribuido
# Se lanzan sesiones psql en paralelo (como operadores concurrentes) y una
# sesión monitora que observa pg_stat_activity / pg_locks en cada nodo.
#   A) Bloqueo de fila (2PL estricto con SELECT ... FOR UPDATE) en el nodo SUR
#   B) Actualización perdida: READ COMMITTED la permite, REPEATABLE READ la impide
#   C1) Interbloqueo LOCAL (un nodo): PostgreSQL lo detecta y aborta una víctima
#   C2) Interbloqueo DISTRIBUIDO (Norte + Sur vía coordinador): ningún nodo ve el
#       ciclo completo -> se resuelve por timeout
# Uso: bash 07_concurrencia.sh [A|B|C1|C2|ALL]   (por defecto ALL)
# =====================================================================
export PGUSER="${POSTGRES_USER:-olva_admin}" PGPASSWORD="$POSTGRES_PASSWORD"
SUR="psql -X -q -h pg_sur -d olva_sur"
NORTE="psql -X -q -h pg_norte -d olva_norte"
LIMA="psql -X -q -d olva_lima"
TMP=$(mktemp -d)
SEC="${1:-ALL}"   # sección a ejecutar: A, B, C1, C2 (varias separadas por coma) o ALL
sec() { [ "$SEC" = ALL ] || [[ ",$SEC," == *",$1,"* ]]; }
ts() { date +%H:%M:%S.%3N; }
mostrar() { echo "----- $1 -----"; cat "$2"; echo; }

# ---------------------------------------------------------------- preparación
# envíos de demostración: 990002 (NORTE, creado en 06) y 990003/990004 (SUR)
$SUR <<'SQL'
DELETE FROM operacion.envio WHERE id_envio IN (990003, 990004);
INSERT INTO operacion.envio
SELECT 990000 + n, 'OLV269999000' || n, c.id_cliente, 1, 1, h.id_hub, d.id_hub, 'Demo concurrencia ' || n,
       now() - INTERVAL '1 day', now() + INTERVAL '1 day', 'EN_HUB', 1.0, 100.00, 20.00, NULL, 'SUR'
  FROM generate_series(3, 4) n
  CROSS JOIN (SELECT MIN(id_cliente) AS id_cliente FROM operacion.cliente_contacto) c
  CROSS JOIN (SELECT id_hub FROM maestro.hub WHERE codigo = 'AG-AQP-01') h
  CROSS JOIN (SELECT id_hub FROM maestro.hub WHERE codigo = 'AG-CUZ-01') d;
SQL
$NORTE -c "UPDATE operacion.envio SET valor_declarado = 100 WHERE id_envio = 990002;"
echo "Preparación: envíos de demostración 990002 (NORTE), 990003 y 990004 (SUR) con valor_declarado = 100"
echo

if sec A; then
# =============================================================== A
echo "=================================================================="
echo "A) BLOQUEO DE FILA en el nodo SUR: dos operadores escanean el mismo envío"
echo "=================================================================="
( echo "[$(ts)] A: BEGIN; SELECT ... FOR UPDATE (toma bloqueo exclusivo de fila)"
  $SUR -c "BEGIN;
           SELECT nro_tracking, estado_actual FROM operacion.envio WHERE id_envio = 990003 FOR UPDATE;
           SELECT pg_sleep(4);
           UPDATE operacion.envio SET estado_actual = 'EN_TRANSITO' WHERE id_envio = 990003;
           COMMIT;"
  echo "[$(ts)] A: COMMIT (libera el bloqueo)" ) > $TMP/a1 2>&1 &
sleep 1
( echo "[$(ts)] B: UPDATE del mismo envío (debe ESPERAR a que A libere)"
  $SUR -c "\timing on" -c "UPDATE operacion.envio SET estado_actual = 'EN_HUB' WHERE id_envio = 990003;"
  echo "[$(ts)] B: terminó" ) > $TMP/a2 2>&1 &
sleep 1.5
$SUR -c "SELECT pid, usename, state, wait_event_type, wait_event, pg_blocking_pids(pid) AS bloqueado_por,
                left(regexp_replace(query, '\s+', ' ', 'g'), 70) AS consulta
           FROM pg_stat_activity WHERE datname = 'olva_sur' AND pid <> pg_backend_pid() AND state <> 'idle' ORDER BY pid;" \
     -c "SELECT l.pid, l.locktype, l.mode, l.granted, c.relname
           FROM pg_locks l LEFT JOIN pg_class c ON c.oid = l.relation
          WHERE l.pid <> pg_backend_pid() AND (c.relname = 'envio' OR l.locktype IN ('transactionid','tuple'))
          ORDER BY l.pid, l.granted DESC;" > $TMP/a3 2>&1
wait
mostrar "Sesión A" $TMP/a1; mostrar "Sesión B" $TMP/a2
mostrar "Monitor (t≈2.5 s): B espera un bloqueo de A" $TMP/a3

fi
if sec B; then
# =============================================================== B
echo "=================================================================="
echo "B) ACTUALIZACIÓN PERDIDA: dos supervisores ajustan el valor declarado"
echo "   A suma 100, B suma 50, ambos calculando a partir de lo que leyeron"
echo "=================================================================="
for NIVEL in "READ COMMITTED" "REPEATABLE READ"; do
  $SUR -c "UPDATE operacion.envio SET valor_declarado = 100 WHERE id_envio = 990004;"
  ( $SUR -v ON_ERROR_STOP=1 <<SQL
BEGIN ISOLATION LEVEL $NIVEL;
SELECT valor_declarado AS v FROM operacion.envio WHERE id_envio = 990004 \gset
\echo [A] leyó :v
SELECT pg_sleep(1);
UPDATE operacion.envio SET valor_declarado = :v + 100 WHERE id_envio = 990004;
\echo [A] escribió :v + 100
COMMIT;
\echo [A] COMMIT
SQL
  ) > $TMP/b1 2>&1 &
  sleep 0.3
  ( $SUR <<SQL
BEGIN ISOLATION LEVEL $NIVEL;
SELECT valor_declarado AS v FROM operacion.envio WHERE id_envio = 990004 \gset
\echo [B] leyó :v
SELECT pg_sleep(2);
UPDATE operacion.envio SET valor_declarado = :v + 50 WHERE id_envio = 990004;
\echo [B] intentó escribir :v + 50
COMMIT;
SQL
  ) > $TMP/b2 2>&1
  wait
  echo "### Nivel de aislamiento: $NIVEL"
  cat $TMP/b1 $TMP/b2 | grep -v "^$\|pg_sleep\|^-\|^(1 row)"
  $SUR -t -c "SELECT '   valor final = ' || valor_declarado || '   (esperado si no se pierde nada: 250)' FROM operacion.envio WHERE id_envio = 990004;"
done
echo "Conclusión: en READ COMMITTED la escritura de A se PIERDE; en REPEATABLE READ PostgreSQL"
echo "aborta a B (could not serialize access) y la aplicación debe reintentar."
echo

fi
if sec C1; then
# =============================================================== C1
echo "=================================================================="
echo "C1) INTERBLOQUEO LOCAL en un solo nodo (SUR): se detecta automáticamente"
echo "=================================================================="
( $SUR -c "BEGIN; UPDATE operacion.envio SET valor_declarado = valor_declarado + 1 WHERE id_envio = 990003;
           SELECT pg_sleep(1);
           UPDATE operacion.envio SET valor_declarado = valor_declarado + 1 WHERE id_envio = 990004; COMMIT;"
  echo "[$(ts)] A terminó" ) > $TMP/c1 2>&1 &
( $SUR -c "BEGIN; UPDATE operacion.envio SET valor_declarado = valor_declarado + 1 WHERE id_envio = 990004;
           SELECT pg_sleep(1);
           UPDATE operacion.envio SET valor_declarado = valor_declarado + 1 WHERE id_envio = 990003; COMMIT;"
  echo "[$(ts)] B terminó" ) > $TMP/c2 2>&1 &
wait
mostrar "Sesión A (bloquea 990003 y luego pide 990004)" $TMP/c1
mostrar "Sesión B (bloquea 990004 y luego pide 990003)" $TMP/c2

fi
if sec C2; then
# =============================================================== C2
echo "=================================================================="
echo "C2) INTERBLOQUEO DISTRIBUIDO: dos transacciones globales desde el coordinador"
echo "    T1: bloquea envío 990002 en NORTE y luego pide 990003 en SUR"
echo "    T2: bloquea envío 990003 en SUR   y luego pide 990002 en NORTE"
echo "=================================================================="
( echo "[$(ts)] T1 inicia"
  $LIMA -c "\timing on" -c "BEGIN;
    UPDATE global.envio SET valor_declarado = valor_declarado + 1 WHERE id_envio = 990002 AND nodo = 'NORTE';
    SELECT pg_sleep(1);
    SET LOCAL statement_timeout = '8s';
    UPDATE global.envio SET valor_declarado = valor_declarado + 1 WHERE id_envio = 990003 AND nodo = 'SUR';
    COMMIT;"
  echo "[$(ts)] T1 terminó" ) > $TMP/d1 2>&1 &
( echo "[$(ts)] T2 inicia"
  $LIMA -c "\timing on" -c "BEGIN;
    UPDATE global.envio SET valor_declarado = valor_declarado + 1 WHERE id_envio = 990003 AND nodo = 'SUR';
    SELECT pg_sleep(1);
    SET LOCAL statement_timeout = '4s';
    UPDATE global.envio SET valor_declarado = valor_declarado + 1 WHERE id_envio = 990002 AND nodo = 'NORTE';
    COMMIT;"
  echo "[$(ts)] T2 terminó" ) > $TMP/d2 2>&1 &
sleep 2.5
{
  echo "[NORTE] sesiones esperando bloqueo:"
  $NORTE -c "SELECT pid, wait_event_type, wait_event, pg_blocking_pids(pid) AS bloqueado_por,
                    left(regexp_replace(query, '\s+', ' ', 'g'), 80) AS consulta_remota
               FROM pg_stat_activity WHERE datname = 'olva_norte' AND wait_event_type = 'Lock';"
  echo "[SUR] sesiones esperando bloqueo:"
  $SUR -c "SELECT pid, wait_event_type, wait_event, pg_blocking_pids(pid) AS bloqueado_por,
                  left(regexp_replace(query, '\s+', ' ', 'g'), 80) AS consulta_remota
             FROM pg_stat_activity WHERE datname = 'olva_sur' AND wait_event_type = 'Lock';"
  echo "[NORTE y SUR] ¿algún nodo detectó interbloqueo? (contador deadlocks de pg_stat_database)"
  $NORTE -t -c "SELECT '   NORTE deadlocks = ' || deadlocks FROM pg_stat_database WHERE datname = 'olva_norte';"
  $SUR   -t -c "SELECT '   SUR   deadlocks = ' || deadlocks FROM pg_stat_database WHERE datname = 'olva_sur';"
} > $TMP/d3 2>&1
wait
mostrar "Monitor (t≈2.5 s): cada nodo ve UNA espera, pero no el ciclo global" $TMP/d3
mostrar "T1" $TMP/d1
mostrar "T2 (víctima por timeout)" $TMP/d2
$SUR -t -c "SELECT '   SUR: deadlocks detectados localmente = ' || deadlocks || ' (incluye C1)' FROM pg_stat_database WHERE datname = 'olva_sur';"
echo "Conclusión: el detector de interbloqueos de PostgreSQL es LOCAL a cada nodo. El ciclo"
echo "T1 -> T2 (en SUR) y T2 -> T1 (en NORTE) solo existe en el grafo de espera GLOBAL, por lo que"
echo "se resuelve por tiempo de espera (statement_timeout/lock_timeout) en el coordinador."
fi
rm -rf $TMP
