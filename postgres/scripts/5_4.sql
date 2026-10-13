-- Збережені процедури: прийняти службовця й змінити розклад (hire_employee, change_schedule)
-- Запуск у psql (база hotel):   \i /pg/5_4.sql
-- Тестові зміни наприкінці скасовуються, скрипт можна запускати повторно.

\pset pager off
\set VERBOSITY terse
\set ECHO queries

\echo
\echo '=== Прийняти на роботу (hire_employee повертає employee_id) ==='
CALL hire_employee('Тестенко', 'Оксана', 'Василівна', NULL) \gset
\echo 'Отриманий employee_id =' :p_employee_id

\echo '=== Змінити розклад (change_schedule) ==='
\echo 'Вівторок: поверх 3. Четвер: поверх 1. Потім вівторок змінюємо на поверх 2:'
CALL change_schedule(:p_employee_id, 2, 3);
CALL change_schedule(:p_employee_id, 4, 1);
CALL change_schedule(:p_employee_id, 2, 2);
SELECT weekday, floor FROM cleaning_schedule WHERE employee_id = :p_employee_id ORDER BY weekday;

\echo 'Поверху 9 немає (тригер), дня тижня 8 немає (процедура):'
CALL change_schedule(:p_employee_id, 3, 9);
CALL change_schedule(:p_employee_id, 8, 1);

\set ECHO none
\set QUIET on
SET client_min_messages = warning;
DELETE FROM employees WHERE employee_id = :p_employee_id;
RESET client_min_messages;
\set QUIET off
\set ECHO queries

\set ECHO none
\set VERBOSITY default
