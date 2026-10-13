-- Тригери цілісності. Правило 1: місткість номера
-- Запуск у psql (база hotel):   \i /pg/4_1.sql
-- Тестові зміни наприкінці скасовуються, скрипт можна запускати повторно.

\pset pager off
\set VERBOSITY terse
\set ECHO queries

\echo
\echo '=== Правило 1. Місткість номера ==='
\echo '1а. Номер 101 одномісний і вже зайнятий: заселення відхиляється'
INSERT INTO stays (client_id, room_id, checkin_date)
SELECT c.client_id, r.room_id, CURRENT_DATE
FROM clients c, rooms r
WHERE c.passport_number = 'ЕК789012' AND r.room_number = 101;

\echo '1б. Номер 201 двомісний, зайнято 1 місце: заселення можливе'
INSERT INTO stays (client_id, room_id, checkin_date)
SELECT c.client_id, r.room_id, CURRENT_DATE
FROM clients c, rooms r
WHERE c.passport_number = 'ЕК789012' AND r.room_number = 201;

\echo '1в. Тепер 201 заповнений (2 з 2): ще одне заселення відхиляється'
INSERT INTO stays (client_id, room_id, checkin_date)
SELECT c.client_id, r.room_id, CURRENT_DATE
FROM clients c, rooms r
WHERE c.passport_number = 'ЕК567890' AND r.room_number = 201;

\set ECHO none
\set QUIET on
DELETE FROM stays
WHERE client_id = (SELECT client_id FROM clients WHERE passport_number = 'ЕК789012')
  AND room_id   = (SELECT room_id FROM rooms WHERE room_number = 201);
\set QUIET off
\set ECHO queries

\set ECHO none
\set VERBOSITY default
