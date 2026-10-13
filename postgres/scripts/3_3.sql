-- Тригери кешу: ROLLBACK не змінює кеш (відкладений тригер)
-- Запуск у psql (база hotel):   \i /pg/3_3.sql
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
\echo '=== Заселення і ROLLBACK: тригер відкладений, кеш не змінюється ==='
BEGIN;
INSERT INTO stays (client_id, room_id, checkin_date)
SELECT c.client_id, r.room_id, CURRENT_DATE
FROM clients c, rooms r
WHERE c.passport_number = 'ЕК789012' AND r.room_number = 102;

\echo 'Усередині транзакції, до COMMIT, кеш ще старий (4 вільні номери, 11 місць):'
SELECT memcache_get('/availability') AS availability;
ROLLBACK;

\echo 'Після ROLLBACK кеш і база збігаються:'
SELECT 'кеш' AS джерело, memcache_get('/availability') AS availability
UNION ALL
SELECT 'база', availability_json();

\set ECHO none
\set VERBOSITY default
