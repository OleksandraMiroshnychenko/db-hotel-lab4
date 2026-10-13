-- Тригери цілісності. Правило 1 (продовження): зміна типів номерів
-- Запуск у psql (база hotel):   \i /pg/4_2.sql
-- Тестові зміни наприкінці скасовуються, скрипт можна запускати повторно.

\pset pager off
\set VERBOSITY terse
\set ECHO queries

\echo
\set ECHO none
\set QUIET on
-- підготовка: заселяємо другого клієнта в 201, щоб номер був заповнений (2 з 2)
INSERT INTO stays (client_id, room_id, checkin_date)
SELECT c.client_id, r.room_id, CURRENT_DATE
FROM clients c, rooms r
WHERE c.passport_number = 'ЕК789012' AND r.room_number = 201;
\set QUIET off
\set ECHO queries

\echo '=== Правило 1 (продовження). Зміна типів не повинна порушувати місткість ==='
\echo 'У номері 201 живуть двоє (2 з 2). Зменшити місткість двомісних номерів до 1 не можна:'
UPDATE room_types SET capacity = 1 WHERE name = 'двомісний';

\echo 'Зробити номер 201 одномісним теж не можна:'
UPDATE rooms
SET room_type_id = (SELECT room_type_id FROM room_types WHERE name = 'одномісний')
WHERE room_number = 201;

\set ECHO none
\set QUIET on
DELETE FROM stays
WHERE client_id = (SELECT client_id FROM clients WHERE passport_number = 'ЕК789012')
  AND room_id   = (SELECT room_id FROM rooms WHERE room_number = 201);
\set QUIET off
\set ECHO queries

\set ECHO none
\set VERBOSITY default
