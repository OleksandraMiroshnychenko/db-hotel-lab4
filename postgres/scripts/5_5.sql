-- Збережені процедури: зняти з дня і звільнити службовця (change_schedule, fire_employee)
-- Запуск у psql (база hotel):   \i /pg/5_5.sql
-- Тестові зміни наприкінці скасовуються, скрипт можна запускати повторно.

\pset pager off
\set VERBOSITY terse
\set ECHO queries

\echo
\set ECHO none
\set QUIET on
SET client_min_messages = warning;
-- підготовка: службовець із розкладом на вівторок і четвер
CALL hire_employee('Тестенко', 'Оксана', 'Василівна', NULL) \gset
CALL change_schedule(:p_employee_id, 2, 2);
CALL change_schedule(:p_employee_id, 4, 1);
RESET client_min_messages;
\set QUIET off
\set ECHO queries

\echo '=== Зняти з четверга (поверх не вказано): у розкладі були вівторок і четвер ==='
CALL change_schedule(:p_employee_id, 4);
SELECT weekday, floor FROM cleaning_schedule WHERE employee_id = :p_employee_id ORDER BY weekday;

\echo '=== Звільнити (fire_employee): графік видаляється разом зі службовцем ==='
CALL fire_employee(:p_employee_id);
SELECT COUNT(*) AS "лишилось записів графіка" FROM cleaning_schedule WHERE employee_id = :p_employee_id;
\echo 'Звільнити ще раз:'
CALL fire_employee(:p_employee_id);

\set ECHO none
\set VERBOSITY default
