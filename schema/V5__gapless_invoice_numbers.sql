-- Copied unchanged from duewise-invoicing-api v1.0.3, src/main/resources/db/migration/V5__gapless_invoice_numbers.sql

-- Invoice numbers are now assigned when an invoice is SENT, not when the draft is created,
-- so deleting a draft never leaves a gap in the numbering (GST/VAT rules generally expect
-- consecutive numbers).

-- Drafts have no number yet; every other status must have one.
ALTER TABLE invoice ALTER COLUMN invoice_number DROP NOT NULL;
ALTER TABLE invoice ADD CONSTRAINT ck_invoice_number_when_issued
    CHECK (status = 'DRAFT' OR invoice_number IS NOT NULL);

-- A PostgreSQL sequence cannot guarantee no gaps: a value taken by a transaction that later
-- rolls back is lost. A counter row updated inside the sending transaction can: the row stays
-- locked until commit, and a rollback restores it.
DROP SEQUENCE invoice_number_seq;

CREATE TABLE invoice_number_counter (
    invoice_year  SMALLINT PRIMARY KEY,
    last_value    INTEGER  NOT NULL,
    CONSTRAINT ck_invoice_number_counter_value CHECK (last_value > 0)
);
