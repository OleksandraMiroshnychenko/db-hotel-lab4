-- Збережені процедури: поселення існуючого клієнта (check_in)
-- Запуск у psql (база hotel):   \i /pg/5_1.sql
-- Тестові зміни наприкінці скасовуються, скрипт можна запускати повторно.

\pset pager off
\set VERBOSITY terse
\set ECHO queries

\echo
\echo '=== Поселити клієнта (процедура check_in) ==='
\echo '1. Клієнт уже є в базі: достатньо паспорта й номера кімнати'
CALL check_in('ЕК789012', 102);
\echo 'Кеш оновився тригером (було 4 вільні номери і 11 місць):'
SELECT memcache_get('/availability') AS availability;

\echo '2. Номер 102 вже заповнений: помилка від тригера місткості'
CALL check_in('ЕК567890', 102);

\echo '3. Номера 999 у готелі немає: помилка процедури'
CALL check_in('ЕК567890', 999);

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
