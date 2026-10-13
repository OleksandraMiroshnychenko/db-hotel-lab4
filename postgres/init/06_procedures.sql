\c hotel

SET ROLE hotel_admin;

-- ============================================================================
-- Збережені процедури: операції адміністратора готелю
--
-- Кожна операція виконується однією командою CALL усередині однієї транзакції:
-- або виконується повністю, або не змінює нічого. Перевірки цілісності
-- (місткість, перетин періодів, поверхи) виконують тригери з 05_integrity.sql,
-- а процедури додають перевірки вхідних даних і зрозумілі повідомлення.
-- Кеш оновлюють тригери з 04_cache_triggers.sql після COMMIT.
-- ============================================================================


-- ---------------------------------------------------------------------------
-- Поселити клієнта.
-- Якщо клієнт уже є в базі, достатньо паспорта й номера кімнати. Для нового
-- клієнта потрібні ще прізвище, імʼя та місто. Клієнт і проживання створюються
-- в одній транзакції: якщо заселити не вдалося (номер заповнений), новий
-- клієнт теж не зберігається.
-- ---------------------------------------------------------------------------
CREATE PROCEDURE check_in(
    p_passport    TEXT,
    p_room_number INTEGER,
    p_date        DATE DEFAULT CURRENT_DATE,
    p_last_name   TEXT DEFAULT NULL,
    p_first_name  TEXT DEFAULT NULL,
    p_patronymic  TEXT DEFAULT NULL,
    p_city        TEXT DEFAULT NULL
) LANGUAGE plpgsql AS $$
DECLARE
    v_room_id   INTEGER;
    v_client_id INTEGER;
    v_new       BOOLEAN := FALSE;
BEGIN
    SELECT room_id INTO v_room_id FROM rooms WHERE room_number = p_room_number;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Номера % у готелі немає.', p_room_number
            USING ERRCODE = 'invalid_parameter_value';
    END IF;

    SELECT client_id INTO v_client_id FROM clients WHERE passport_number = p_passport;
    IF NOT FOUND THEN
        IF p_last_name IS NULL OR p_first_name IS NULL OR p_city IS NULL THEN
            RAISE EXCEPTION 'Клієнта з паспортом % немає в базі: для нового клієнта вкажіть прізвище, імʼя та місто.',
                p_passport
                USING ERRCODE = 'invalid_parameter_value';
        END IF;
        INSERT INTO clients (passport_number, last_name, first_name, patronymic, city)
        VALUES (p_passport, p_last_name, p_first_name, p_patronymic, p_city)
        RETURNING client_id INTO v_client_id;
        v_new := TRUE;
    END IF;

    -- місткість і перетин періодів перевіряють тригери
    INSERT INTO stays (client_id, room_id, checkin_date)
    VALUES (v_client_id, v_room_id, p_date);

    RAISE NOTICE 'Клієнта (паспорт %) поселено в номер % з %.%',
        p_passport, p_room_number, p_date,
        CASE WHEN v_new THEN ' Створено нового клієнта.' ELSE '' END;
END;
$$;


-- ---------------------------------------------------------------------------
-- Виселити клієнта: закриває його поточне проживання.
-- ---------------------------------------------------------------------------
CREATE PROCEDURE check_out(
    p_passport TEXT,
    p_date     DATE DEFAULT CURRENT_DATE
) LANGUAGE plpgsql AS $$
DECLARE
    v_stay_id  INTEGER;
    v_checkin  DATE;
    v_room     INTEGER;
BEGIN
    SELECT s.stay_id, s.checkin_date, r.room_number
      INTO v_stay_id, v_checkin, v_room
      FROM stays s
      JOIN clients c ON c.client_id = s.client_id
      JOIN rooms   r ON r.room_id   = s.room_id
     WHERE c.passport_number = p_passport
       AND s.checkout_date IS NULL
       FOR UPDATE OF s;

    IF NOT FOUND THEN
        IF EXISTS (SELECT 1 FROM clients WHERE passport_number = p_passport) THEN
            RAISE EXCEPTION 'Клієнт з паспортом % зараз не проживає в готелі.', p_passport
                USING ERRCODE = 'invalid_parameter_value';
        END IF;
        RAISE EXCEPTION 'Клієнта з паспортом % немає в базі.', p_passport
            USING ERRCODE = 'invalid_parameter_value';
    END IF;

    IF p_date < v_checkin THEN
        RAISE EXCEPTION 'Дата виселення % раніша за дату заселення %.', p_date, v_checkin
            USING ERRCODE = 'invalid_parameter_value';
    END IF;

    UPDATE stays SET checkout_date = p_date WHERE stay_id = v_stay_id;

    RAISE NOTICE 'Клієнта (паспорт %) виселено з номера % (проживав з %).',
        p_passport, v_room, v_checkin;
END;
$$;


-- ---------------------------------------------------------------------------
-- Прийняти службовця на роботу. Повертає його ідентифікатор через INOUT-параметр
-- (при виклику на його місце передається NULL).
-- ---------------------------------------------------------------------------
CREATE PROCEDURE hire_employee(
    p_last_name   TEXT,
    p_first_name  TEXT,
    p_patronymic  TEXT,
    INOUT p_employee_id INTEGER
) LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO employees (last_name, first_name, patronymic)
    VALUES (p_last_name, p_first_name, p_patronymic)
    RETURNING employee_id INTO p_employee_id;

    RAISE NOTICE 'Службовця % % прийнято на роботу, employee_id = %.',
        p_last_name, p_first_name, p_employee_id;
END;
$$;


-- ---------------------------------------------------------------------------
-- Звільнити службовця. Його графік прибирання видаляється автоматично
-- (ON DELETE CASCADE у cleaning_schedule).
-- ---------------------------------------------------------------------------
CREATE PROCEDURE fire_employee(p_employee_id INTEGER)
LANGUAGE plpgsql AS $$
DECLARE
    v_last_name TEXT;
    v_first_name TEXT;
    v_days      INTEGER;
BEGIN
    SELECT COUNT(*) INTO v_days FROM cleaning_schedule WHERE employee_id = p_employee_id;

    DELETE FROM employees
     WHERE employee_id = p_employee_id
    RETURNING last_name, first_name INTO v_last_name, v_first_name;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Службовця з employee_id = % немає.', p_employee_id
            USING ERRCODE = 'invalid_parameter_value';
    END IF;

    RAISE NOTICE 'Службовця % % звільнено, видалено записів графіка: %.',
        v_last_name, v_first_name, v_days;
END;
$$;


-- ---------------------------------------------------------------------------
-- Змінити розклад службовця: вказати, який поверх він прибирає у вказаний день
-- тижня (1 - понеділок ... 7 - неділя). Якщо запис на цей день уже є, його
-- змінено, якщо немає - додано. Поверх NULL знімає службовця з цього дня.
-- Існування поверху перевіряє тригер з 05_integrity.sql.
-- ---------------------------------------------------------------------------
CREATE PROCEDURE change_schedule(
    p_employee_id INTEGER,
    p_weekday     INTEGER,
    p_floor       INTEGER DEFAULT NULL
) LANGUAGE plpgsql AS $$
DECLARE
    v_days   TEXT[] := ARRAY['понеділок', 'вівторок', 'середа', 'четвер',
                             'пʼятниця', 'субота', 'неділя'];
    v_name   TEXT;
BEGIN
    IF p_weekday NOT BETWEEN 1 AND 7 THEN
        RAISE EXCEPTION 'День тижня має бути від 1 (понеділок) до 7 (неділя), отримано %.', p_weekday
            USING ERRCODE = 'invalid_parameter_value';
    END IF;

    SELECT last_name INTO v_name FROM employees WHERE employee_id = p_employee_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Службовця з employee_id = % немає.', p_employee_id
            USING ERRCODE = 'invalid_parameter_value';
    END IF;

    IF p_floor IS NULL THEN
        DELETE FROM cleaning_schedule
         WHERE employee_id = p_employee_id AND weekday = p_weekday;
        RAISE NOTICE 'Службовця % знято з прибирання в день: %.', v_name, v_days[p_weekday];
    ELSE
        INSERT INTO cleaning_schedule (employee_id, weekday, floor)
        VALUES (p_employee_id, p_weekday, p_floor)
        ON CONFLICT (employee_id, weekday) DO UPDATE SET floor = EXCLUDED.floor;
        RAISE NOTICE 'Службовець % у день "%" прибирає поверх %.', v_name, v_days[p_weekday], p_floor;
    END IF;
END;
$$;
