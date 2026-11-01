-- Copied unchanged from duewise-invoicing-api v1.0.3, src/main/resources/db/migration/V1__create_reference_tables.sql

-- Reference (lookup) tables. Other tables point at these instead of storing free text,
-- so a currency or payment method is defined once and every row stays consistent.

CREATE TABLE currency (
    code         CHAR(3)     PRIMARY KEY,           -- ISO 4217 code, e.g. INR. Natural key: ISO codes never change.
    name         VARCHAR(60) NOT NULL,
    symbol       VARCHAR(5)  NOT NULL,
    minor_units  SMALLINT    NOT NULL,              -- decimal places: 2 for INR/USD, 0 for JPY, 3 for KWD
    active       BOOLEAN     NOT NULL DEFAULT TRUE,
    CONSTRAINT ck_currency_code        CHECK (code ~ '^[A-Z]{3}$'),
    CONSTRAINT ck_currency_minor_units CHECK (minor_units BETWEEN 0 AND 3)
);

CREATE TABLE payment_method (
    id                  SMALLINT    GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    code                VARCHAR(30) NOT NULL,
    display_name        VARCHAR(60) NOT NULL,
    requires_reference  BOOLEAN     NOT NULL DEFAULT FALSE,  -- e.g. UPI transaction id or cheque number
    active              BOOLEAN     NOT NULL DEFAULT TRUE,   -- retire a method without deleting history
    sort_order          SMALLINT    NOT NULL DEFAULT 0,
    CONSTRAINT uq_payment_method_code UNIQUE (code),
    CONSTRAINT ck_payment_method_code CHECK (code ~ '^[A-Z][A-Z0-9_]*$')
);
