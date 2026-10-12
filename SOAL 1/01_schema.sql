-- ============================================
-- SOAL 1 - Skema + Constraint + Trigger Balance
-- ============================================

CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE chart_of_accounts (
    account_id     BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    account_code   VARCHAR(10)  NOT NULL UNIQUE,
    account_name   VARCHAR(100) NOT NULL,
    normal_balance VARCHAR(6)   NOT NULL CHECK (normal_balance IN ('DEBIT','CREDIT')),
    report_class   VARCHAR(20)  NOT NULL CHECK (report_class IN ('BALANCE_SHEET','INCOME_STATEMENT'))
);

CREATE TABLE journal_headers (
    header_id      BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    trx_date       DATE         NOT NULL,
    ref_no         VARCHAR(50)  NOT NULL UNIQUE,
    description    TEXT,
    posting_status VARCHAR(10)  NOT NULL DEFAULT 'DRAFT'
                   CHECK (posting_status IN ('DRAFT','POSTED','REVERSED')),
    created_by     TEXT         NOT NULL,
    created_at     TIMESTAMPTZ  NOT NULL DEFAULT now(),
    hash_checksum  CHAR(64),
    reversal_of    BIGINT REFERENCES journal_headers(header_id) ON DELETE RESTRICT,
    CONSTRAINT chk_posted_has_hash
        CHECK (posting_status = 'DRAFT' OR hash_checksum IS NOT NULL)
);

CREATE TABLE journal_lines (
    line_id    BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    header_id  BIGINT NOT NULL REFERENCES journal_headers(header_id) ON DELETE RESTRICT,
    account_id BIGINT NOT NULL REFERENCES chart_of_accounts(account_id) ON DELETE RESTRICT,
    debit      NUMERIC(18,2) NOT NULL DEFAULT 0,
    credit     NUMERIC(18,2) NOT NULL DEFAULT 0,
    CONSTRAINT chk_non_negative  CHECK (debit >= 0 AND credit >= 0),
    CONSTRAINT chk_not_both_zero CHECK (NOT (debit = 0 AND credit = 0)),
    CONSTRAINT chk_one_side      CHECK (debit = 0 OR credit = 0)
);

CREATE INDEX idx_lines_header  ON journal_lines(header_id);
CREATE INDEX idx_lines_account ON journal_lines(account_id);

CREATE OR REPLACE FUNCTION fn_check_journal_balance() RETURNS trigger AS $$
DECLARE
    v_id BIGINT := COALESCE(NEW.header_id, OLD.header_id);
    v_d  NUMERIC; v_k NUMERIC;
BEGIN
    SELECT COALESCE(SUM(debit),0), COALESCE(SUM(credit),0)
      INTO v_d, v_k FROM journal_lines WHERE header_id = v_id;
    IF v_d <> v_k THEN
        RAISE EXCEPTION 'Jurnal % tidak seimbang: debit=% kredit=%', v_id, v_d, v_k;
    END IF;
    RETURN NULL;
END; $$ LANGUAGE plpgsql;

CREATE CONSTRAINT TRIGGER trg_journal_balance
AFTER INSERT OR UPDATE OR DELETE ON journal_lines
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION fn_check_journal_balance();

INSERT INTO chart_of_accounts(account_code, account_name, normal_balance, report_class) VALUES
 ('1-1100','Kas','DEBIT','BALANCE_SHEET'),
 ('1-1400','Persediaan Barang Dagang','DEBIT','BALANCE_SHEET'),
 ('5-1000','Beban Pokok Pendapatan (HPP)','DEBIT','INCOME_STATEMENT'),
 ('6-1100','Beban Operasional','DEBIT','INCOME_STATEMENT');