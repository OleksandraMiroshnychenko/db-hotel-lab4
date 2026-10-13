-- Збережені процедури: поселення нового клієнта і атомарність (check_in)
-- Запуск у psql (база hotel):   \i /pg/5_2.sql
-- Тестові зміни наприкінці скасовуються, скрипт можна запускати повторно.

\pset pager off
\set VERBOSITY terse
\set ECHO queries

\echo
\echo '=== Поселити нового клієнта (процедура check_in) ==='
\echo '1. Даних про нового клієнта не вистачає: помилка процедури'
CALL check_in('ЕК000001', 203);

\echo '2. Усі дані вказано: процедура створює клієнта і заселяє його'
CALL check_in('ЕК000001', 203, p_last_name => 'Іваненко', p_first_name => 'Петро', p_patronymic => 'Олегович', p_city => 'Полтава');

\echo '3. Атомарність: новий клієнт і заселення в повний номер 101'
CALL check_in('ЕК000002', 101, p_last_name => 'Тестовий', p_first_name => 'Клієнт', p_city => 'Київ');
SELECT COUNT(*) AS "створено клієнтів ЕК000002" FROM clients WHERE passport_number = 'ЕК000002';

\set ECHO none
\set QUIET on
SET client_min_messages = warning;
DELETE FROM stays
WHERE client_id = (SELECT client_id FROM clients WHERE passport_number = 'ЕК000001');
DELETE FROM clients WHERE passport_number = 'ЕК000001';
RESET client_min_messages;
\set QUIET off
\set ECHO queries

\set ECHO none
\set VERBOSITY default
