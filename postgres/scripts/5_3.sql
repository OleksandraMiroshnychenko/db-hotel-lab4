-- Збережені процедури: виселення клієнтів (check_out)
-- Запуск у psql (база hotel):   \i /pg/5_3.sql
-- Тестові зміни наприкінці скасовуються, скрипт можна запускати повторно.

\pset pager off
\set VERBOSITY terse
\set ECHO queries

\echo
\set ECHO none
\set QUIET on
SET client_min_messages = warning;
-- підготовка: заселяємо клієнта в номер 102
CALL check_in('ЕК789012', 102);
RESET client_min_messages;
\set QUIET off
\set ECHO queries

\echo '=== Виселити клієнта (процедура check_out) ==='
\echo '1. Виселення: проживання закривається поточною датою'
CALL check_out('ЕК789012');
\echo 'Кеш оновився: номер 102 знову вільний (occupied = 0):'
SELECT memcache_get('/rooms/102') AS room_102;

\echo '2. Цього клієнта вже виселено:'
CALL check_out('ЕК789012');

\echo '3. Такого паспорта в базі немає:'
CALL check_out('ЕК777777');

\echo '4. Дата виселення раніша за дату заселення:'
CALL check_out('ЕК456789', DATE '2026-01-01');

\set ECHO none
\set QUIET on
SET client_min_messages = warning;
DELETE FROM stays
WHERE client_id = (SELECT client_id FROM clients WHERE passport_number = 'ЕК789012')
  AND room_id   = (SELECT room_id FROM rooms WHERE room_number = 102)
  AND checkin_date = CURRENT_DATE;
RESET client_min_messages;
\set QUIET off
\set ECHO queries

\set ECHO none
\set VERBOSITY default
