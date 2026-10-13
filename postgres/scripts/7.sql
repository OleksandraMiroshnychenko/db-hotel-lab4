-- Перевірка ефективності (pgbench).
-- Запуск у psql (база hotel):   \i /pg/7.sql
--
-- Кожен вимір триває 5 секунд (параметр -T 5 у рядках нижче). Скрипт тимчасово
-- вимикає тригери для порівняння, а наприкінці вмикає їх назад і перебудовує кеш.
-- Якщо виконання перервано, повтори \i /pg/7.sql: початок скрипта вмикає тригери.
--
-- "операція" = заселити клієнта, виселити його і видалити тестовий запис
-- (три окремі транзакції, у кожній спрацьовують тригери).

\pset pager off
\set ECHO none
\set VERBOSITY default
\set QUIET on
ALTER TABLE stays ENABLE TRIGGER USER;
DO $$ BEGIN PERFORM cache_refresh_all(); END $$;
\set QUIET off

\echo
\echo '=== 1. Читання зведення про вільні місця ==='
\echo 'З бази (availability_json(): підрахунок за таблицями):'
\! pgbench -n -c 1 -T 5 -U root -d hotel -f /pg/bench/read_db.sql 2>&1 | awk '/latency average/ {l=$4} /^tps/ && !t {t=$3} END {printf "    затримка %.2f мс, %.0f запитів/с\n", l, t}'
\echo 'З кешу (memcache_get: готовий JSON):'
\! pgbench -n -c 1 -T 5 -U root -d hotel -f /pg/bench/read_cache.sql 2>&1 | awk '/latency average/ {l=$4} /^tps/ && !t {t=$3} END {printf "    затримка %.2f мс, %.0f запитів/с\n", l, t}'

\echo
\echo '=== 2. Операція заселення і виселення: вартість тригерів ==='
\echo 'Процедури, усі тригери (цілісність і кеш):'
\! pgbench -n -c 1 -T 5 -U root -d hotel -f /pg/bench/cycle_proc.sql 2>&1 | awk '/latency average/ {l=$4} /^tps/ && !t {t=$3} END {printf "    затримка %.2f мс, %.0f операцій/с\n", l, t}'

\echo 'Звичайні SQL-команди (INSERT, UPDATE, DELETE), усі тригери:'
\! pgbench -n -c 1 -T 5 -U root -d hotel -f /pg/bench/cycle_sql.sql 2>&1 | awk '/latency average/ {l=$4} /^tps/ && !t {t=$3} END {printf "    затримка %.2f мс, %.0f операцій/с\n", l, t}'

\set QUIET on
ALTER TABLE stays DISABLE TRIGGER cache_stays;
\set QUIET off
\echo 'Процедури без тригера кешу:'
\! pgbench -n -c 1 -T 5 -U root -d hotel -f /pg/bench/cycle_proc.sql 2>&1 | awk '/latency average/ {l=$4} /^tps/ && !t {t=$3} END {printf "    затримка %.2f мс, %.0f операцій/с\n", l, t}'
\set QUIET on
ALTER TABLE stays ENABLE TRIGGER cache_stays;
ALTER TABLE stays DISABLE TRIGGER check_stay_capacity;
ALTER TABLE stays DISABLE TRIGGER check_stay_overlap;
\set QUIET off
\echo 'Процедури без тригерів цілісності:'
\! pgbench -n -c 1 -T 5 -U root -d hotel -f /pg/bench/cycle_proc.sql 2>&1 | awk '/latency average/ {l=$4} /^tps/ && !t {t=$3} END {printf "    затримка %.2f мс, %.0f операцій/с\n", l, t}'
\set QUIET on
ALTER TABLE stays DISABLE TRIGGER USER;
\set QUIET off
\echo 'Процедури без жодного тригера:'
\! pgbench -n -c 1 -T 5 -U root -d hotel -f /pg/bench/cycle_proc.sql 2>&1 | awk '/latency average/ {l=$4} /^tps/ && !t {t=$3} END {printf "    затримка %.2f мс, %.0f операцій/с\n", l, t}'

-- повертаємо тригери та кеш у робочий стан
\set QUIET on
ALTER TABLE stays ENABLE TRIGGER USER;
DO $$ BEGIN PERFORM cache_refresh_all(); END $$;
\set QUIET off
\echo
\echo 'Тригери ввімкнено, кеш перебудовано:'
SELECT 'кеш' AS джерело, memcache_get('/availability') AS availability
UNION ALL
SELECT 'база', availability_json();
