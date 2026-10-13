DROP DATABASE IF EXISTS hotel;
DROP ROLE IF EXISTS hotel_admin;

CREATE ROLE hotel_admin LOGIN;

CREATE DATABASE hotel
    ENCODING 'UTF-8'
    LC_COLLATE 'en_US.UTF-8'
    LC_CTYPE 'en_US.UTF-8'
    TEMPLATE template0
    OWNER hotel_admin;

\c hotel

-- розширення для роботи з memcached (потребує суперкористувача)
CREATE EXTENSION pgmemcache;

SET ROLE hotel_admin;

-- Типи номерів
CREATE TABLE room_types (
    room_type_id INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name TEXT NOT NULL UNIQUE,
    capacity INTEGER NOT NULL CHECK (capacity BETWEEN 1 AND 3),
    price_per_day NUMERIC(10,2) NOT NULL CHECK (price_per_day > 0)
);

-- Номери готелю
CREATE TABLE rooms (
    room_id INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    room_number INTEGER NOT NULL UNIQUE,
    floor INTEGER NOT NULL CHECK (floor > 0),
    phone TEXT NOT NULL,
    room_type_id INTEGER NOT NULL REFERENCES room_types(room_type_id)
);

-- Клієнти
CREATE TABLE clients (
    client_id INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    passport_number TEXT NOT NULL UNIQUE,
    last_name TEXT NOT NULL,
    first_name TEXT NOT NULL,
    patronymic TEXT,
    city TEXT NOT NULL
);

-- Проживання (історія заселень)
CREATE TABLE stays (
    stay_id INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    client_id INTEGER NOT NULL REFERENCES clients(client_id) ON DELETE CASCADE,
    room_id INTEGER NOT NULL REFERENCES rooms(room_id),
    checkin_date DATE NOT NULL,
    checkout_date DATE,
    CHECK (checkout_date IS NULL OR checkout_date >= checkin_date)
);

-- Службовці
CREATE TABLE employees (
    employee_id INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    last_name TEXT NOT NULL,
    first_name TEXT NOT NULL,
    patronymic TEXT
);

-- Графік прибирання
CREATE TABLE cleaning_schedule (
    employee_id INTEGER NOT NULL REFERENCES employees(employee_id) ON DELETE CASCADE,
    weekday SMALLINT NOT NULL CHECK (weekday BETWEEN 1 AND 7),
    floor INTEGER NOT NULL CHECK (floor > 0),
    PRIMARY KEY (employee_id, weekday)
);
