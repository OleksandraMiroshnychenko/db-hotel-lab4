-- Тригери кешу: зміна ціни типу номера оновлює кеш усіх номерів цього типу
-- Запуск у psql (база hotel):   \i /pg/3_5.sql
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
\echo '=== Зміна ціни одномісних номерів (таблиця room_types) ==='
\echo 'Ціни в кеші до зміни (одномісні 101 і 302, двомісний 103):'
SELECT memcache_get('/rooms/101')::json->>'price_per_day' AS "101",
       memcache_get('/rooms/302')::json->>'price_per_day' AS "302",
       memcache_get('/rooms/103')::json->>'price_per_day' AS "103";

UPDATE room_types SET price_per_day = 900 WHERE name = 'одномісний';

\echo 'Після зміни ціна оновилась у кеші всіх одномісних номерів, двомісний не змінився:'
SELECT memcache_get('/rooms/101')::json->>'price_per_day' AS "101",
       memcache_get('/rooms/302')::json->>'price_per_day' AS "302",
       memcache_get('/rooms/103')::json->>'price_per_day' AS "103";

\set ECHO none
\set QUIET on
SET client_min_messages = warning;
UPDATE room_types SET price_per_day = 800 WHERE name = 'одномісний';
RESET client_min_messages;
\set QUIET off
\set ECHO queries

\set ECHO none
\set VERBOSITY default
