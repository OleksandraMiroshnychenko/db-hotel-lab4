\c hotel

SET ROLE hotel_admin;

-- ============================================================================
-- Тригери синхронізації кешу
--
-- Memcached не бере участі в транзакціях PostgreSQL: ROLLBACK скасовує зміни в
-- таблицях, але не в кеші. Тому оновлення кешу виконують тригери, створені як
-- CONSTRAINT TRIGGER ... DEFERRABLE INITIALLY DEFERRED. Такий тригер спрацьовує
-- не одразу після зміни рядка, а в кінці транзакції, під час COMMIT:
--   * якщо транзакцію скасовано (ROLLBACK), тригер не спрацює і кеш не зміниться;
--   * якщо підтверджено, тригер бачить кінцевий стан даних транзакції.
-- (У PostgreSQL відкладеними можуть бути лише тригери-обмеження, тому звичайний
--  CREATE TRIGGER тут не підходить.)
-- ============================================================================


-- ---------------------------------------------------------------------------
-- stays: заселення, виселення, переселення змінюють заповненість номерів
-- ---------------------------------------------------------------------------
CREATE FUNCTION trg_cache_stays() RETURNS TRIGGER AS $$
BEGIN
    -- старий номер: рядок видалено або переселено в інший номер
    IF TG_OP = 'DELETE'
       OR (TG_OP = 'UPDATE' AND OLD.room_id IS DISTINCT FROM NEW.room_id) THEN
        PERFORM cache_room(OLD.room_id);
    END IF;
    -- новий (або той самий) номер
    IF TG_OP IN ('INSERT', 'UPDATE') THEN
        PERFORM cache_room(NEW.room_id);
    END IF;
    PERFORM cache_summary();
    RETURN NULL;   -- значення AFTER-тригера ігнорується
END;
$$ LANGUAGE plpgsql;

CREATE CONSTRAINT TRIGGER cache_stays
    AFTER INSERT OR UPDATE OR DELETE ON stays
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW EXECUTE FUNCTION trg_cache_stays();


-- ---------------------------------------------------------------------------
-- rooms: новий номер, зміна телефона, поверху, типу або номера кімнати, видалення
-- ---------------------------------------------------------------------------
CREATE FUNCTION trg_cache_rooms() RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'DELETE' THEN
        PERFORM cache_drop('/rooms/' || OLD.room_number);
    ELSE
        -- номер кімнати змінився: старий ключ більше не діє
        IF TG_OP = 'UPDATE' AND OLD.room_number <> NEW.room_number THEN
            PERFORM cache_drop('/rooms/' || OLD.room_number);
        END IF;
        PERFORM cache_room(NEW.room_id);
    END IF;
    PERFORM cache_summary();
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE CONSTRAINT TRIGGER cache_rooms
    AFTER INSERT OR UPDATE OR DELETE ON rooms
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW EXECUTE FUNCTION trg_cache_rooms();


-- ---------------------------------------------------------------------------
-- room_types: зміна назви, місткості чи ціни стосується всіх номерів цього типу.
-- Додавання нового типу кеш не змінює (номерів цього типу ще немає), а видалити
-- тип, який використовують номери, не дозволяє зовнішній ключ. Тому лише UPDATE.
-- ---------------------------------------------------------------------------
CREATE FUNCTION trg_cache_room_types() RETURNS TRIGGER AS $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN SELECT room_id FROM rooms WHERE room_type_id = NEW.room_type_id LOOP
        PERFORM cache_room(r.room_id);
    END LOOP;
    PERFORM cache_summary();
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE CONSTRAINT TRIGGER cache_room_types
    AFTER UPDATE ON room_types
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW EXECUTE FUNCTION trg_cache_room_types();
