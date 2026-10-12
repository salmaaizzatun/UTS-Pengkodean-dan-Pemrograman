-- ============================================
-- SOAL 3.2 - Immutability, hash, audit log
-- ============================================

CREATE OR REPLACE FUNCTION fn_journal_hash(p_id BIGINT) RETURNS TEXT AS $$
    SELECT encode(digest(concat_ws('|',
        h.ref_no, h.trx_date::text, h.created_by,
        extract(epoch from h.created_at)::text,
        (SELECT string_agg(l.account_id || ':' || l.debit || ':' || l.credit, ','
                           ORDER BY l.line_id)
           FROM journal_lines l WHERE l.header_id = h.header_id)
    ), 'sha256'), 'hex')
    FROM journal_headers h WHERE h.header_id = p_id;
$$ LANGUAGE sql STABLE;

CREATE OR REPLACE FUNCTION trg_header_guard() RETURNS trigger AS $$
DECLARE v_d NUMERIC; v_k NUMERIC; v_n INT;
BEGIN
    IF TG_OP = 'DELETE' THEN
        IF OLD.posting_status <> 'DRAFT' THEN
            RAISE EXCEPTION 'Jurnal % berstatus % tidak boleh dihapus; gunakan jurnal pembalik',
                            OLD.ref_no, OLD.posting_status;
        END IF;
        RETURN OLD;
    END IF;

    IF OLD.posting_status = 'DRAFT' AND NEW.posting_status = 'DRAFT' THEN
        RETURN NEW;
    ELSIF OLD.posting_status = 'DRAFT' AND NEW.posting_status = 'POSTED' THEN
        IF ROW(NEW.ref_no, NEW.trx_date, NEW.description, NEW.created_by, NEW.created_at)
           IS DISTINCT FROM
           ROW(OLD.ref_no, OLD.trx_date, OLD.description, OLD.created_by, OLD.created_at) THEN
            RAISE EXCEPTION 'Saat posting hanya status yang boleh berubah';
        END IF;
        SELECT COALESCE(SUM(debit),0), COALESCE(SUM(credit),0), COUNT(*)
          INTO v_d, v_k, v_n FROM journal_lines WHERE header_id = OLD.header_id;
        IF v_n < 2 OR v_d <> v_k OR v_d = 0 THEN
            RAISE EXCEPTION 'Jurnal % tidak dapat diposting (baris=%, debit=%, kredit=%)',
                            OLD.ref_no, v_n, v_d, v_k;
        END IF;
        NEW.hash_checksum := fn_journal_hash(OLD.header_id);
        RETURN NEW;
    ELSIF OLD.posting_status = 'POSTED' AND NEW.posting_status = 'REVERSED'
          AND ROW(NEW.ref_no, NEW.trx_date, NEW.description, NEW.created_by,
                  NEW.created_at, NEW.hash_checksum)
              IS NOT DISTINCT FROM
              ROW(OLD.ref_no, OLD.trx_date, OLD.description, OLD.created_by,
                  OLD.created_at, OLD.hash_checksum) THEN
        RETURN NEW;
    END IF;
    RAISE EXCEPTION 'Jurnal % berstatus % tidak boleh diubah (immutable)',
                    OLD.ref_no, OLD.posting_status;
END; $$ LANGUAGE plpgsql;

CREATE TRIGGER trg_header_guard
BEFORE UPDATE OR DELETE ON journal_headers
FOR EACH ROW EXECUTE FUNCTION trg_header_guard();

CREATE OR REPLACE FUNCTION trg_line_guard() RETURNS trigger AS $$
DECLARE s TEXT;
BEGIN
    IF TG_OP IN ('UPDATE','DELETE') THEN
        SELECT posting_status INTO s FROM journal_headers WHERE header_id = OLD.header_id;
        IF s <> 'DRAFT' THEN RAISE EXCEPTION 'Baris jurnal terkunci (status %)', s; END IF;
    END IF;
    IF TG_OP IN ('INSERT','UPDATE') THEN
        SELECT posting_status INTO s FROM journal_headers WHERE header_id = NEW.header_id;
        IF s <> 'DRAFT' THEN RAISE EXCEPTION 'Baris jurnal terkunci (status %)', s; END IF;
    END IF;
    RETURN COALESCE(NEW, OLD);
END; $$ LANGUAGE plpgsql;

CREATE TRIGGER trg_line_guard
BEFORE INSERT OR UPDATE OR DELETE ON journal_lines
FOR EACH ROW EXECUTE FUNCTION trg_line_guard();

CREATE TABLE audit_log (
    log_id     BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    table_name TEXT NOT NULL,
    record_id  BIGINT NOT NULL,
    action     TEXT NOT NULL,
    actor      TEXT NOT NULL DEFAULT current_user,
    old_data   JSONB,
    new_data   JSONB,
    logged_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE OR REPLACE FUNCTION trg_audit_block() RETURNS trigger AS $$
BEGIN RAISE EXCEPTION 'audit_log bersifat append-only'; END; $$ LANGUAGE plpgsql;

CREATE TRIGGER trg_audit_block BEFORE UPDATE OR DELETE ON audit_log
FOR EACH ROW EXECUTE FUNCTION trg_audit_block();

CREATE OR REPLACE FUNCTION trg_header_audit() RETURNS trigger AS $$
BEGIN
    INSERT INTO audit_log(table_name, record_id, action, old_data, new_data)
    VALUES ('journal_headers', COALESCE(NEW.header_id, OLD.header_id), TG_OP,
            CASE WHEN TG_OP <> 'INSERT' THEN to_jsonb(OLD) END,
            CASE WHEN TG_OP <> 'DELETE' THEN to_jsonb(NEW) END);
    RETURN NULL;
END; $$ LANGUAGE plpgsql;

CREATE TRIGGER trg_header_audit AFTER INSERT OR UPDATE OR DELETE ON journal_headers
FOR EACH ROW EXECUTE FUNCTION trg_header_audit();

CREATE OR REPLACE FUNCTION create_voucher(p_ref TEXT, p_date DATE, p_desc TEXT, p_lines JSONB)
RETURNS BIGINT AS $$
DECLARE v_id BIGINT; l JSONB;
BEGIN
    INSERT INTO journal_headers(trx_date, ref_no, description, created_by)
    VALUES (p_date, p_ref, p_desc,
            COALESCE(NULLIF(current_setting('request.jwt.claim.sub', true), ''), current_user))
    RETURNING header_id INTO v_id;

    FOR l IN SELECT * FROM jsonb_array_elements(p_lines) LOOP
        INSERT INTO journal_lines(header_id, account_id, debit, credit)
        VALUES (v_id,
                (SELECT account_id FROM chart_of_accounts WHERE account_code = l->>'account_code'),
                (l->>'debit')::numeric, (l->>'credit')::numeric);
    END LOOP;

    UPDATE journal_headers SET posting_status = 'POSTED' WHERE header_id = v_id;
    RETURN v_id;
END; $$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION reverse_journal(p_header_id BIGINT, p_reason TEXT)
RETURNS BIGINT AS $$
DECLARE v_new BIGINT; v_ref TEXT;
BEGIN
    SELECT ref_no INTO v_ref FROM journal_headers
     WHERE header_id = p_header_id AND posting_status = 'POSTED' FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Hanya jurnal POSTED yang dapat dibalik'; END IF;

    INSERT INTO journal_headers(trx_date, ref_no, description, created_by, reversal_of)
    VALUES (CURRENT_DATE, v_ref || '-REV', 'Storno ' || v_ref || ': ' || p_reason,
            COALESCE(NULLIF(current_setting('request.jwt.claim.sub', true), ''), current_user),
            p_header_id)
    RETURNING header_id INTO v_new;

    INSERT INTO journal_lines(header_id, account_id, debit, credit)
    SELECT v_new, account_id, credit, debit
      FROM journal_lines WHERE header_id = p_header_id;

    UPDATE journal_headers SET posting_status = 'POSTED'   WHERE header_id = v_new;
    UPDATE journal_headers SET posting_status = 'REVERSED' WHERE header_id = p_header_id;
    RETURN v_new;
END; $$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION verify_journal(p_id BIGINT) RETURNS BOOLEAN AS $$
    SELECT hash_checksum = fn_journal_hash(header_id) FROM journal_headers WHERE header_id = p_id;
$$ LANGUAGE sql STABLE;

-- ============================================
-- SKENARIO UJI (jalankan satu per satu di Supabase)
-- ============================================
-- (a) SELECT create_voucher('KK-001','2026-10-19','Bayar listrik',
--   '[{"account_code":"6-1100","debit":500000,"credit":0},
--     {"account_code":"1-1100","debit":0,"credit":500000}]');
-- (b) UPDATE journal_headers SET description='ubah' WHERE ref_no='KK-001';
-- (c) DELETE FROM journal_lines WHERE header_id = 1;
-- (d) SELECT reverse_journal(1, 'Salah akun');
-- (e) SELECT create_voucher('KK-002','2026-10-19','Tidak balance',
--   '[{"account_code":"6-1100","debit":100,"credit":0},
--     {"account_code":"1-1100","debit":0,"credit":90}]');
-- (f) SELECT header_id, verify_journal(header_id) FROM journal_headers WHERE posting_status <> 'DRAFT';