-- Тригери цілісності. Правило 2: періоди проживання клієнта не перетинаються
-- Запуск у psql (база hotel):   \i /pg/4_3.sql
-- Тестові зміни наприкінці скасовуються, скрипт можна запускати повторно.

\pset pager off
\set VERBOSITY terse
\set ECHO queries

\echo
\echo '=== Правило 2. Один клієнт не може жити в двох місцях одночасно ==='
\echo '2а. Коваленко вже проживає в номері 202, друге поточне проживання відхиляється'
INSERT INTO stays (client_id, room_id, checkin_date)
SELECT c.client_id, r.room_id, CURRENT_DATE
FROM clients c, rooms r
WHERE c.passport_number = 'ЕК123456' AND r.room_number = 102;

\echo '2б. Минулий період, що перетинається з її проживанням 2026-08-01..08-05, відхиляється'
INSERT INTO stays (client_id, room_id, checkin_date, checkout_date)
SELECT c.client_id, r.room_id, DATE '2026-08-03', DATE '2026-08-04'
FROM clients c, rooms r
WHERE c.passport_number = 'ЕК123456' AND r.room_number = 102;

\echo '2в. Минулий період, що не перетинається, допускається'
INSERT INTO stays (client_id, room_id, checkin_date, checkout_date)
SELECT c.client_id, r.room_id, DATE '2026-07-01', DATE '2026-07-05'
FROM clients c, rooms r
WHERE c.passport_number = 'ЕК123456' AND r.room_number = 102;

\set ECHO none
\set QUIET on
DELETE FROM stays
WHERE client_id = (SELECT client_id FROM clients WHERE passport_number = 'ЕК123456')
  AND room_id   = (SELECT room_id FROM rooms WHERE room_number = 102)
  AND checkin_date = DATE '2026-07-01';
\set QUIET off
\set ECHO queries

\set ECHO none
\set VERBOSITY default
