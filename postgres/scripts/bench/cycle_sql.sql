INSERT INTO stays (client_id, room_id, checkin_date)
SELECT c.client_id, r.room_id, CURRENT_DATE
FROM clients c, rooms r
WHERE c.passport_number = 'ЕК789012' AND r.room_number = 102;
UPDATE stays SET checkout_date = CURRENT_DATE
WHERE checkout_date IS NULL
  AND client_id = (SELECT client_id FROM clients WHERE passport_number = 'ЕК789012');
DELETE FROM stays
WHERE client_id = (SELECT client_id FROM clients WHERE passport_number = 'ЕК789012')
  AND room_id   = (SELECT room_id FROM rooms WHERE room_number = 102)
  AND checkin_date = CURRENT_DATE;
