-- Тригери кешу: що було б без відкладення (звичайний тригер)
-- Запуск у psql (база hotel):   \i /pg/3_4.sql
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
\echo '=== Те саме, але тригер спрацьовує одразу (SET CONSTRAINTS ALL IMMEDIATE) ==='
BEGIN;
SET CONSTRAINTS ALL IMMEDIATE;
INSERT INTO stays (client_id, room_id, checkin_date)
SELECT c.client_id, r.room_id, CURRENT_DATE
FROM clients c, rooms r
WHERE c.passport_number = 'ЕК789012' AND r.room_number = 102;
ROLLBACK;

\echo 'Кеш помилково зберіг заселення, якого немає (кеш і база РІЗНІ):'
SELECT 'кеш' AS джерело, memcache_get('/availability') AS availability
UNION ALL
SELECT 'база', availability_json();

\echo 'Виправляємо повною перебудовою кешу:'
DO $$ BEGIN PERFORM cache_refresh_all(); END $$;
SELECT 'кеш' AS джерело, memcache_get('/availability') AS availability
UNION ALL
SELECT 'база', availability_json();

\set ECHO none
\set VERBOSITY default
