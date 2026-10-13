-- Тригери цілісності. Правило 3: поверхи в графіку прибирання
-- Запуск у psql (база hotel):   \i /pg/4_4.sql
-- Тестові зміни наприкінці скасовуються, скрипт можна запускати повторно.

\pset pager off
\set VERBOSITY terse
\set ECHO queries

\echo
\echo '=== Правило 3. У графіку прибирання можуть бути лише існуючі поверхи ==='
\echo '3а. Поверху 9 у готелі немає:'
INSERT INTO cleaning_schedule (employee_id, weekday, floor) VALUES (1, 2, 9);

\echo '3б. Перенести наявний графік на поверх 9 теж не можна:'
UPDATE cleaning_schedule SET floor = 9 WHERE employee_id = 1 AND weekday = 1;

\echo '3в. Додаємо номер 401 (новий поверх 4) і вносимо поверх 4 у графік:'
INSERT INTO rooms (room_number, floor, phone, room_type_id) VALUES (401, 4, '+380441234599', 1);
INSERT INTO cleaning_schedule (employee_id, weekday, floor) VALUES (1, 5, 4);

\echo '3г. Номер 401 останній на поверсі 4, який є в графіку: видалити його не можна:'
DELETE FROM rooms WHERE room_number = 401;

\set ECHO none
\set QUIET on
DELETE FROM cleaning_schedule WHERE employee_id = 1 AND weekday = 5;
DELETE FROM rooms WHERE room_number = 401;
\set QUIET off
\set ECHO queries

\set ECHO none
\set VERBOSITY default
