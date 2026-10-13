\c hotel

SET ROLE hotel_admin;

-- ============================================================================
-- Тригери цілісності (процедурні обмеження)
--
-- Декларативні обмеження (PRIMARY KEY, FOREIGN KEY, UNIQUE, CHECK) перевіряють
-- кожен рядок окремо. Правила нижче залежать від ІНШИХ рядків і таблиць (скільки
-- людей уже живе в номері, чи є такий поверх), тому їх реалізовано BEFORE-тригерами.
-- Порушення блокується через RAISE EXCEPTION: оператор скасовується разом з
-- транзакцією, а відкладені тригери кешу в такому разі не спрацьовують.
--
-- Правила:
--   1. В номері не може проживати більше людей, ніж його місткість.
--   2. Клієнт не може проживати одночасно у двох місцях (періоди проживання
--      одного клієнта не перетинаються).
--   3. У графіку прибирання можуть бути лише поверхи, які існують у готелі.
-- Правила 1 і 3 діють з обох боків: їх не можна порушити і зміною самих номерів
-- чи типів номерів.
-- ============================================================================


-- ---------------------------------------------------------------------------
-- Правило 1. Місткість номера (таблиця stays)
-- Враховуються поточні проживання (checkout_date IS NULL), як і в запитах про
-- вільні місця. Завершене проживання місця не займає.
-- ---------------------------------------------------------------------------
CREATE FUNCTION trg_check_stay_capacity() RETURNS TRIGGER AS $$
DECLARE
    v_number   INTEGER;
    v_capacity INTEGER;
    v_occupied INTEGER;
BEGIN
    IF NEW.checkout_date IS NOT NULL THEN
        RETURN NEW;
    END IF;

    -- Блокуємо рядок номера: два паралельні заселення в останнє вільне місце
    -- виконуються по черзі, і друге побачить, що місце вже зайняте.
    -- (NO KEY UPDATE не заважає перевірці зовнішніх ключів.)
    SELECT r.room_number, rt.capacity
      INTO v_number, v_capacity
      FROM rooms r
      JOIN room_types rt ON rt.room_type_id = r.room_type_id
     WHERE r.room_id = NEW.room_id
       FOR NO KEY UPDATE OF r;

    IF v_capacity IS NULL THEN
        RETURN NEW;   -- такого номера немає: помилку дасть зовнішній ключ
    END IF;

    SELECT COUNT(*) INTO v_occupied
      FROM stays
     WHERE room_id = NEW.room_id
       AND checkout_date IS NULL
       AND stay_id IS DISTINCT FROM NEW.stay_id;   -- при UPDATE не рахуємо сам рядок

    IF v_occupied >= v_capacity THEN
        RAISE EXCEPTION 'Номер % заповнений: місткість %, зараз проживає %.',
            v_number, v_capacity, v_occupied
            USING ERRCODE = 'check_violation';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER check_stay_capacity
    BEFORE INSERT OR UPDATE ON stays
    FOR EACH ROW EXECUTE FUNCTION trg_check_stay_capacity();


-- ---------------------------------------------------------------------------
-- Правило 2. Періоди проживання одного клієнта не перетинаються (таблиця stays)
-- Поточне проживання (без дати виселення) триває "до нескінченності".
-- Проміжки напіввідкриті: виселення й заселення в один день не вважаються
-- перетином.
-- ---------------------------------------------------------------------------
CREATE FUNCTION trg_check_stay_overlap() RETURNS TRIGGER AS $$
DECLARE
    v_last_name TEXT;
BEGIN
    -- некоректні дати відхилить CHECK-обмеження таблиці
    IF NEW.checkin_date IS NULL
       OR (NEW.checkout_date IS NOT NULL AND NEW.checkout_date < NEW.checkin_date) THEN
        RETURN NEW;
    END IF;

    -- Блокуємо рядок клієнта, щоб паралельні заселення одного клієнта виконувались по черзі
    SELECT last_name INTO v_last_name
      FROM clients
     WHERE client_id = NEW.client_id
       FOR NO KEY UPDATE;

    IF EXISTS (
        SELECT 1
          FROM stays s
         WHERE s.client_id = NEW.client_id
           AND s.stay_id IS DISTINCT FROM NEW.stay_id
           AND daterange(s.checkin_date, COALESCE(s.checkout_date, 'infinity'::DATE))
            && daterange(NEW.checkin_date, COALESCE(NEW.checkout_date, 'infinity'::DATE))
    ) THEN
        RAISE EXCEPTION 'Клієнт % уже має проживання, що перетинається з вказаним періодом.',
            v_last_name
            USING ERRCODE = 'check_violation';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER check_stay_overlap
    BEFORE INSERT OR UPDATE ON stays
    FOR EACH ROW EXECUTE FUNCTION trg_check_stay_overlap();


-- ---------------------------------------------------------------------------
-- Правило 3а. Поверх у графіку прибирання має існувати (таблиця cleaning_schedule)
-- ---------------------------------------------------------------------------
CREATE FUNCTION trg_check_cleaning_floor() RETURNS TRIGGER AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM rooms WHERE floor = NEW.floor) THEN
        RAISE EXCEPTION 'У готелі немає поверху %, його не можна внести в графік прибирання.',
            NEW.floor
            USING ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER check_cleaning_floor
    BEFORE INSERT OR UPDATE OF floor ON cleaning_schedule
    FOR EACH ROW EXECUTE FUNCTION trg_check_cleaning_floor();


-- ---------------------------------------------------------------------------
-- Правило 3б. Поверх, який є в графіку прибирання, не можна "спорожнити"
-- (видалення останнього номера поверху або перенесення на інший поверх)
-- ---------------------------------------------------------------------------
CREATE FUNCTION trg_check_floor_in_use() RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'UPDATE' AND OLD.floor = NEW.floor THEN
        RETURN NEW;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM rooms
                    WHERE floor = OLD.floor AND room_id <> OLD.room_id)
       AND EXISTS (SELECT 1 FROM cleaning_schedule WHERE floor = OLD.floor) THEN
        RAISE EXCEPTION 'Номер % — останній на поверсі %, а цей поверх є в графіку прибирання.',
            OLD.room_number, OLD.floor
            USING ERRCODE = 'check_violation';
    END IF;

    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER check_floor_in_use
    BEFORE UPDATE OF floor OR DELETE ON rooms
    FOR EACH ROW EXECUTE FUNCTION trg_check_floor_in_use();


-- ---------------------------------------------------------------------------
-- Правило 1б. Зміна типу номера або місткості типу не повинна ставити
-- заповненість вище місткості
-- ---------------------------------------------------------------------------
CREATE FUNCTION trg_check_type_capacity() RETURNS TRIGGER AS $$
DECLARE
    v_number   INTEGER;
    v_occupied INTEGER;
BEGIN
    IF NEW.capacity >= OLD.capacity THEN
        RETURN NEW;
    END IF;

    SELECT r.room_number, COUNT(s.stay_id)
      INTO v_number, v_occupied
      FROM rooms r
      JOIN stays s ON s.room_id = r.room_id AND s.checkout_date IS NULL
     WHERE r.room_type_id = NEW.room_type_id
     GROUP BY r.room_number
    HAVING COUNT(s.stay_id) > NEW.capacity
     ORDER BY r.room_number
     LIMIT 1;

    IF FOUND THEN
        RAISE EXCEPTION 'Не можна зменшити місткість типу "%" до %: у номері % зараз проживає %.',
            NEW.name, NEW.capacity, v_number, v_occupied
            USING ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER check_type_capacity
    BEFORE UPDATE OF capacity ON room_types
    FOR EACH ROW EXECUTE FUNCTION trg_check_type_capacity();


CREATE FUNCTION trg_check_room_type_switch() RETURNS TRIGGER AS $$
DECLARE
    v_capacity INTEGER;
    v_name     TEXT;
    v_occupied INTEGER;
BEGIN
    IF NEW.room_type_id = OLD.room_type_id THEN
        RETURN NEW;
    END IF;

    SELECT capacity, name INTO v_capacity, v_name
      FROM room_types
     WHERE room_type_id = NEW.room_type_id;

    SELECT COUNT(*) INTO v_occupied
      FROM stays
     WHERE room_id = NEW.room_id AND checkout_date IS NULL;

    IF v_occupied > v_capacity THEN
        RAISE EXCEPTION 'Номер % не можна зробити типом "%": місткість %, зараз проживає %.',
            NEW.room_number, v_name, v_capacity, v_occupied
            USING ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER check_room_type_switch
    BEFORE UPDATE OF room_type_id ON rooms
    FOR EACH ROW EXECUTE FUNCTION trg_check_room_type_switch();
