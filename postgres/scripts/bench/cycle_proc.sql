CALL check_in('ЕК789012', 102);
CALL check_out('ЕК789012');
DELETE FROM stays
WHERE client_id = (SELECT client_id FROM clients WHERE passport_number = 'ЕК789012')
  AND room_id   = (SELECT room_id FROM rooms WHERE room_number = 102)
  AND checkin_date = CURRENT_DATE;
