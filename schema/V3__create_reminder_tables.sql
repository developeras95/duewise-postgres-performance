-- Copied unchanged from duewise-invoicing-api v1.0.3, src/main/resources/db/migration/V3__create_reminder_tables.sql

-- Overdue reminder settings and the log of reminders sent.
-- Recipients and reminder days live in their own tables (one row per value) rather than
-- comma-separated lists or arrays, so each value can be validated, constrained and queried.

-- Single-row table holding the on/off switches. The CHECK keeps it to exactly one row.
CREATE TABLE reminder_settings (
    id                        SMALLINT    PRIMARY KEY DEFAULT 1,
    owner_digest_enabled      BOOLEAN     NOT NULL DEFAULT TRUE,   -- daily overdue summary to the business owner
    client_reminders_enabled  BOOLEAN     NOT NULL DEFAULT TRUE,   -- reminders to each client, PDF attached
    updated_at                TIMESTAMPTZ NOT NULL DEFAULT now(),
    version                   BIGINT      NOT NULL DEFAULT 0,
    CONSTRAINT ck_reminder_settings_single_row CHECK (id = 1)
);

-- Who receives the owner's daily overdue summary.
CREATE TABLE reminder_recipient (
    id             BIGINT       GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    email          VARCHAR(254) NOT NULL,
    delivery_type  VARCHAR(3)   NOT NULL DEFAULT 'TO',
    created_at     TIMESTAMPTZ  NOT NULL DEFAULT now(),
    CONSTRAINT ck_reminder_recipient_type CHECK (delivery_type IN ('TO', 'CC'))
);

CREATE UNIQUE INDEX ux_reminder_recipient_email_lower ON reminder_recipient (lower(email));

-- Days past the due date on which a client reminder is sent, e.g. 1, 7 and 14.
CREATE TABLE reminder_offset (
    days_overdue  SMALLINT PRIMARY KEY,
    CONSTRAINT ck_reminder_offset_days CHECK (days_overdue BETWEEN 1 AND 365)
);

-- Every reminder attempt. Used to avoid sending the same reminder twice and to retry failures.
CREATE TABLE reminder_log (
    id               BIGINT       GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    reminder_type    VARCHAR(20)  NOT NULL,
    invoice_id       BIGINT       REFERENCES invoice (id) ON DELETE CASCADE,  -- client reminders only
    days_overdue     SMALLINT,                                              -- client reminders only
    digest_date      DATE,                                                  -- owner digests only
    recipients       VARCHAR(1000) NOT NULL,                                -- snapshot of who it went to
    status           VARCHAR(10)  NOT NULL,
    attempts         SMALLINT     NOT NULL DEFAULT 1,
    last_error       VARCHAR(1000),
    sent_at          TIMESTAMPTZ,
    created_at       TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_at       TIMESTAMPTZ  NOT NULL DEFAULT now(),
    CONSTRAINT ck_reminder_log_type   CHECK (reminder_type IN ('CLIENT_REMINDER', 'OWNER_DIGEST')),
    CONSTRAINT ck_reminder_log_status CHECK (status IN ('SENT', 'FAILED')),
    CONSTRAINT ck_reminder_log_shape  CHECK (
        (reminder_type = 'CLIENT_REMINDER' AND invoice_id IS NOT NULL AND days_overdue IS NOT NULL AND digest_date IS NULL)
     OR (reminder_type = 'OWNER_DIGEST'    AND invoice_id IS NULL     AND days_overdue IS NULL     AND digest_date IS NOT NULL)
    )
);

-- Partial unique indexes: at most one row per invoice per reminder day, and one owner digest per day.
CREATE UNIQUE INDEX ux_reminder_log_client ON reminder_log (invoice_id, days_overdue)
    WHERE reminder_type = 'CLIENT_REMINDER';
CREATE UNIQUE INDEX ux_reminder_log_digest ON reminder_log (digest_date)
    WHERE reminder_type = 'OWNER_DIGEST';
