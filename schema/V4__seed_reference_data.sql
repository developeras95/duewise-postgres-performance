-- Copied unchanged from duewise-invoicing-api v1.0.3, src/main/resources/db/migration/V4__seed_reference_data.sql

-- Starting reference data. More currencies or payment methods can be added through the API later.

INSERT INTO currency (code, name, symbol, minor_units) VALUES
    ('INR', 'Indian Rupee',         '₹',   2),
    ('USD', 'US Dollar',            '$',   2),
    ('EUR', 'Euro',                 '€',   2),
    ('GBP', 'Pound Sterling',       '£',   2),
    ('AED', 'UAE Dirham',           'AED', 2),
    ('SGD', 'Singapore Dollar',     'S$',  2),
    ('JPY', 'Japanese Yen',         '¥',   0),
    ('KWD', 'Kuwaiti Dinar',        'KD',  3);

INSERT INTO payment_method (code, display_name, requires_reference, sort_order) VALUES
    ('BANK_TRANSFER', 'Bank transfer', TRUE,  10),
    ('UPI',           'UPI',           TRUE,  20),
    ('CARD',          'Card',          TRUE,  30),
    ('CHEQUE',        'Cheque',        TRUE,  40),
    ('CASH',          'Cash',          FALSE, 50);

INSERT INTO reminder_settings (id) VALUES (1);

INSERT INTO reminder_offset (days_overdue) VALUES (1), (7), (14);
