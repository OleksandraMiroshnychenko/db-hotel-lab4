\c hotel

SET ROLE hotel_admin;

-- ============================================================================
-- Кешування даних готелю в memcached
--
-- Ключі кешу збігаються з адресами REST API (nginx бере ключ з URI запиту):
--   /rooms/101      один номер (за номером кімнати)
--   /rooms          усі номери
--   /availability   кількість вільних номерів і вільних місць
-- Значення - JSON-документи.
-- ============================================================================

-- Стан кожного номера: тип, ціна та заповненість (скільки людей живе зараз).
-- Подання використовується всіма функціями нижче, тому логіка підрахунку одна.
CREATE VIEW room_status AS
SELECT
    rm.room_id,
    rm.room_number,
    rm.floor,
    rm.phone,
    rt.name AS room_type,
    rt.capacity,
    rt.price_per_day,
    COUNT(s.stay_id)::INTEGER AS occupied,
    (rt.capacity - COUNT(s.stay_id))::INTEGER AS free_places
FROM rooms rm
JOIN room_types rt ON rt.room_type_id = rm.room_type_id
LEFT JOIN stays s ON s.room_id = rm.room_id AND s.checkout_date IS NULL
GROUP BY rm.room_id, rm.room_number, rm.floor, rm.phone,
         rt.name, rt.capacity, rt.price_per_day;


-- ---------------------------------------------------------------------------
-- Формування JSON-документів
-- (рядкам дано імена через підзапит, інакше to_json() назве поля f1, f2, ...)
-- ---------------------------------------------------------------------------

CREATE FUNCTION room_json(p_room_id INTEGER) RETURNS TEXT AS $$
    SELECT to_json(x)::TEXT
    FROM (
        SELECT room_number, floor, phone, room_type, capacity,
               price_per_day, occupied, free_places
        FROM room_status
        WHERE room_id = p_room_id
    ) AS x;
$$ LANGUAGE sql STABLE;

CREATE FUNCTION rooms_json() RETURNS TEXT AS $$
    SELECT COALESCE(json_agg(x ORDER BY x.room_number), '[]'::JSON)::TEXT
    FROM (
        SELECT room_number, floor, phone, room_type, capacity,
               price_per_day, occupied, free_places
        FROM room_status
    ) AS x;
$$ LANGUAGE sql STABLE;

CREATE FUNCTION availability_json() RETURNS TEXT AS $$
    SELECT to_json(x)::TEXT
    FROM (
        SELECT COUNT(*) FILTER (WHERE occupied = 0)::INTEGER AS free_rooms,
               COALESCE(SUM(free_places), 0)::INTEGER        AS free_places
        FROM room_status
    ) AS x;
$$ LANGUAGE sql STABLE;


-- ---------------------------------------------------------------------------
-- Запис у кеш
-- ---------------------------------------------------------------------------

-- Кеш є допоміжним, а база даних - джерелом істини. Тому недоступність
-- memcached не повинна ламати зміну даних: помилка перетворюється на
-- попередження, а транзакція триває.
-- memcache_set (на відміну від memcache_add) перезаписує наявний ключ.
CREATE FUNCTION cache_put(p_key TEXT, p_value TEXT) RETURNS VOID AS $$
BEGIN
    PERFORM memcache_set(p_key, p_value);
EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'Кеш недоступний, ключ % не оновлено: %', p_key, SQLERRM;
END;
$$ LANGUAGE plpgsql;

CREATE FUNCTION cache_drop(p_key TEXT) RETURNS VOID AS $$
BEGIN
    PERFORM memcache_delete(p_key);
EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'Кеш недоступний, ключ % не видалено: %', p_key, SQLERRM;
END;
$$ LANGUAGE plpgsql;

-- Оновити в кеші один номер
CREATE FUNCTION cache_room(p_room_id INTEGER) RETURNS VOID AS $$
DECLARE
    v_number INTEGER;
BEGIN
    SELECT room_number INTO v_number FROM rooms WHERE room_id = p_room_id;
    IF v_number IS NOT NULL THEN
        PERFORM cache_put('/rooms/' || v_number, room_json(p_room_id));
    END IF;
END;
$$ LANGUAGE plpgsql;

-- Оновити зведені ключі: список номерів і кількість вільних місць
CREATE FUNCTION cache_summary() RETURNS VOID AS $$
BEGIN
    PERFORM cache_put('/rooms', rooms_json());
    PERFORM cache_put('/availability', availability_json());
END;
$$ LANGUAGE plpgsql;

-- Повністю перебудувати кеш (після запуску або перезапуску memcached)
CREATE FUNCTION cache_refresh_all() RETURNS VOID AS $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN SELECT room_id FROM rooms LOOP
        PERFORM cache_room(r.room_id);
    END LOOP;
    PERFORM cache_summary();
END;
$$ LANGUAGE plpgsql;
