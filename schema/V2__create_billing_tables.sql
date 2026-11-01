-- Copied unchanged from duewise-invoicing-api v1.0.3, src/main/resources/db/migration/V2__create_billing_tables.sql

-- Core billing tables: clients, invoices, invoice line items and payments.
-- Money is NUMERIC(15,3): exact decimal arithmetic, with room for 3-decimal currencies such as KWD.
-- Only foreign-key indexes are created here. Indexes for reporting queries are added later,
-- based on measured query plans (see the duewise-postgres-performance repository).

CREATE TABLE client (
    id                     BIGINT       GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name                   VARCHAR(200) NOT NULL,
    email                  VARCHAR(254) NOT NULL,
    billing_email          VARCHAR(254),                     -- accounts team, if different from the main contact
    phone                  VARCHAR(30),
    tax_id                 VARCHAR(50),                      -- e.g. GSTIN or VAT number
    address_line1          VARCHAR(200),
    address_line2          VARCHAR(200),
    city                   VARCHAR(100),
    state                  VARCHAR(100),
    postal_code            VARCHAR(20),
    country_code           CHAR(2),                          -- ISO 3166-1 alpha-2
    default_currency_code  CHAR(3)      REFERENCES currency (code),
    payment_terms_days     SMALLINT     NOT NULL DEFAULT 30,
    reminders_enabled      BOOLEAN      NOT NULL DEFAULT TRUE,
    created_at             TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_at             TIMESTAMPTZ  NOT NULL DEFAULT now(),
    version                BIGINT       NOT NULL DEFAULT 0,  -- optimistic locking
    CONSTRAINT ck_client_payment_terms CHECK (payment_terms_days BETWEEN 0 AND 365),
    CONSTRAINT ck_client_country_code  CHECK (country_code IS NULL OR country_code ~ '^[A-Z]{2}$')
);

-- Emails are unique regardless of case: "Asha@Acme.com" and "asha@acme.com" are the same client.
CREATE UNIQUE INDEX ux_client_email_lower ON client (lower(email));
CREATE INDEX ix_client_default_currency ON client (default_currency_code);

-- Numbers like INV-2026-00042 are built from this sequence by the application.
CREATE SEQUENCE invoice_number_seq START WITH 1 INCREMENT BY 1;

CREATE TABLE invoice (
    id              BIGINT        GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    invoice_number  VARCHAR(30)   NOT NULL,
    client_id       BIGINT        NOT NULL REFERENCES client (id),
    currency_code   CHAR(3)       NOT NULL REFERENCES currency (code),
    status          VARCHAR(20)   NOT NULL DEFAULT 'DRAFT',
    issue_date      DATE          NOT NULL,
    due_date        DATE          NOT NULL,
    subtotal        NUMERIC(15,3) NOT NULL DEFAULT 0,
    tax_total       NUMERIC(15,3) NOT NULL DEFAULT 0,
    total           NUMERIC(15,3) NOT NULL DEFAULT 0,
    amount_paid     NUMERIC(15,3) NOT NULL DEFAULT 0,
    notes           VARCHAR(2000),
    sent_at         TIMESTAMPTZ,
    paid_at         TIMESTAMPTZ,
    voided_at       TIMESTAMPTZ,
    void_reason     VARCHAR(500),
    created_at      TIMESTAMPTZ   NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ   NOT NULL DEFAULT now(),
    version         BIGINT        NOT NULL DEFAULT 0,
    CONSTRAINT uq_invoice_number      UNIQUE (invoice_number),
    CONSTRAINT ck_invoice_status      CHECK (status IN ('DRAFT', 'SENT', 'PARTIALLY_PAID', 'PAID', 'VOID')),
    CONSTRAINT ck_invoice_dates       CHECK (due_date >= issue_date),
    CONSTRAINT ck_invoice_amounts     CHECK (subtotal >= 0 AND tax_total >= 0 AND total >= 0 AND amount_paid >= 0),
    CONSTRAINT ck_invoice_total       CHECK (total = subtotal + tax_total),
    CONSTRAINT ck_invoice_not_overpaid CHECK (amount_paid <= total)
);

CREATE INDEX ix_invoice_client   ON invoice (client_id);
CREATE INDEX ix_invoice_currency ON invoice (currency_code);

CREATE TABLE invoice_line_item (
    id             BIGINT        GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    invoice_id     BIGINT        NOT NULL REFERENCES invoice (id) ON DELETE CASCADE,  -- only drafts can be deleted
    line_no        SMALLINT      NOT NULL,
    description    VARCHAR(500)  NOT NULL,
    quantity       NUMERIC(12,3) NOT NULL,
    unit_price     NUMERIC(15,3) NOT NULL,
    tax_rate       NUMERIC(5,2)  NOT NULL DEFAULT 0,   -- percent, e.g. 18.00
    line_subtotal  NUMERIC(15,3) NOT NULL,
    line_tax       NUMERIC(15,3) NOT NULL,
    line_total     NUMERIC(15,3) NOT NULL,
    CONSTRAINT uq_line_item_position UNIQUE (invoice_id, line_no),   -- also serves as the invoice_id index
    CONSTRAINT ck_line_item_line_no  CHECK (line_no > 0),
    CONSTRAINT ck_line_item_quantity CHECK (quantity > 0),
    CONSTRAINT ck_line_item_price    CHECK (unit_price >= 0),
    CONSTRAINT ck_line_item_tax_rate CHECK (tax_rate BETWEEN 0 AND 100),
    CONSTRAINT ck_line_item_total    CHECK (line_total = line_subtotal + line_tax)
);

CREATE TABLE payment (
    id                 BIGINT        GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    invoice_id         BIGINT        NOT NULL REFERENCES invoice (id),
    payment_method_id  SMALLINT      NOT NULL REFERENCES payment_method (id) ON DELETE RESTRICT,
    amount             NUMERIC(15,3) NOT NULL,
    paid_on            DATE          NOT NULL,
    reference          VARCHAR(100),
    notes              VARCHAR(500),
    created_at         TIMESTAMPTZ   NOT NULL DEFAULT now(),
    CONSTRAINT ck_payment_amount CHECK (amount > 0)
);

CREATE INDEX ix_payment_invoice ON payment (invoice_id);
CREATE INDEX ix_payment_method  ON payment (payment_method_id);
