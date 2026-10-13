-- Тригери кешу: заселення оновлює кеш
-- Запуск у psql (база hotel):   \i /pg/3_1.sql
-- Тестові зміни наприкінці скасовуються, скрипт можна запускати повторно.

\pset pager off
\set VERBOSITY terse
\set ECHO queries

\echo
\set ECHO none
\set QUIET on
SET client_min_messages = warning;
DO $$ BEGIN PERFORM cache_refresh_all(); END $$;
RESET client_min_messages;
\set QUIET off
\set ECHO queries
\echo '=== Заселення клієнта в номер 102 (автоматичний COMMIT) ==='
\echo 'До заселення в кеші було 4 вільні номери і 11 місць.'
INSERT INTO stays (client_id, room_id, checkin_date)
SELECT c.client_id, r.room_id, CURRENT_DATE
FROM clients c, rooms r
WHERE c.passport_number = 'ЕК789012' AND r.room_number = 102;
\echo 'Вільних номерів і місць стало менше, і в кеші, і в базі:'
SELECT 'кеш' AS джерело, memcache_get('/availability') AS availability
UNION ALL
SELECT 'база', availability_json();
\echo 'У кеші номер 102 став зайнятий:'
SELECT memcache_get('/rooms/102')::json->>'occupied' AS occupied;

\set ECHO none
\set QUIET on
SET client_min_messages = warning;
DELETE FROM stays
WHERE client_id = (SELECT client_id FROM clients WHERE passport_number = 'ЕК789012')
  AND room_id   = (SELECT room_id FROM rooms WHERE room_number = 102);
RESET client_min_messages;
\set QUIET off
\set ECHO queries

\set ECHO none
\set VERBOSITY default
