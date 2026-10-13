-- Перевірка тригерів синхронізації кешу.
-- Запуск у psql (база hotel):   \i /pg/3.sql
--
-- У кожному кроці порівнюється кеш (memcached) і база даних. Якщо тригери
-- працюють правильно, значення збігаються. Усі зміни наприкінці скасовуються,
-- тож скрипт можна запускати скільки завгодно разів.

\echo
\echo '=== 0. Початковий стан: наповнюємо кеш ==='
DO $$ BEGIN PERFORM cache_refresh_all(); END $$;
SELECT 'кеш' AS джерело, memcache_get('/availability') AS availability
UNION ALL
SELECT 'база', availability_json();


\echo
\echo '=== 1. Заселення клієнта в номер 102 (автоматичний COMMIT) ==='
INSERT INTO stays (client_id, room_id, checkin_date)
SELECT c.client_id, r.room_id, CURRENT_DATE
FROM clients c, rooms r
WHERE c.passport_number = 'ЕК789012' AND r.room_number = 102;

\echo 'Вільних номерів і місць стало менше, і в кеші, і в базі:'
SELECT 'кеш' AS джерело, memcache_get('/availability') AS availability
UNION ALL
SELECT 'база', availability_json();
\echo 'Кеш самого номера 102 (occupied = 1):'
SELECT memcache_get('/rooms/102') AS room_102;


\echo
\echo '=== 2. Виселення цього клієнта ==='
UPDATE stays SET checkout_date = CURRENT_DATE
WHERE checkout_date IS NULL
  AND client_id = (SELECT client_id FROM clients WHERE passport_number = 'ЕК789012');

SELECT 'кеш' AS джерело, memcache_get('/availability') AS availability
UNION ALL
SELECT 'база', availability_json();
-- тестовий рядок прибираємо, щоб повернути базу до початкового стану
-- (історичні проживання цього клієнта в інших номерах не чіпаємо)
DELETE FROM stays
WHERE client_id = (SELECT client_id FROM clients WHERE passport_number = 'ЕК789012')
  AND room_id   = (SELECT room_id FROM rooms WHERE room_number = 102);


\echo
\echo '=== 3. Заселення і ROLLBACK: відкладений тригер, кеш не змінюється ==='
BEGIN;
INSERT INTO stays (client_id, room_id, checkin_date)
SELECT c.client_id, r.room_id, CURRENT_DATE
FROM clients c, rooms r
WHERE c.passport_number = 'ЕК789012' AND r.room_number = 102;

\echo 'Усередині транзакції, до COMMIT, кеш ще старий (4 вільні номери, 11 місць):'
SELECT memcache_get('/availability') AS availability;
ROLLBACK;

\echo 'Після ROLLBACK кеш і база збігаються:'
SELECT 'кеш' AS джерело, memcache_get('/availability') AS availability
UNION ALL
SELECT 'база', availability_json();


\echo
\echo '=== 4. Що було б без відкладення (звичайний тригер) ==='
BEGIN;
SET CONSTRAINTS ALL IMMEDIATE;   -- вимикаємо відкладення: тригер спрацює одразу
INSERT INTO stays (client_id, room_id, checkin_date)
SELECT c.client_id, r.room_id, CURRENT_DATE
FROM clients c, rooms r
WHERE c.passport_number = 'ЕК789012' AND r.room_number = 102;
ROLLBACK;

\echo 'Кеш помилково зберіг заселення, якого немає (кеш і база РІЗНІ):'
SELECT 'кеш' AS джерело, memcache_get('/availability') AS availability
UNION ALL
SELECT 'база', availability_json();

\echo 'Виправляємо повною перебудовою кешу:'
DO $$ BEGIN PERFORM cache_refresh_all(); END $$;
SELECT 'кеш' AS джерело, memcache_get('/availability') AS availability
UNION ALL
SELECT 'база', availability_json();


\echo
\echo '=== 5. Зміна ціни одномісних номерів (таблиця room_types) ==='
UPDATE room_types SET price_per_day = 900 WHERE name = 'одномісний';
\echo 'Ціна змінилась в кеші всіх одномісних номерів (101, 102, 302):'
SELECT memcache_get('/rooms/101') AS room_101;
UPDATE room_types SET price_per_day = 800 WHERE name = 'одномісний';
\echo 'Ціну повернуто:'
SELECT memcache_get('/rooms/101') AS room_101;
