-- ============================================
-- SOAL 2 - Persediaan + Trigger Stok
-- ============================================

CREATE TABLE inventory_items (
    item_id    VARCHAR(10) PRIMARY KEY,
    item_name  VARCHAR(100),
    stock_qty  INT NOT NULL DEFAULT 0,
    unit_cost  NUMERIC(15,2) NOT NULL
);

CREATE TABLE inventory_transactions (
    trx_id   SERIAL PRIMARY KEY,
    item_id  VARCHAR(10) REFERENCES inventory_items(item_id),
    trx_type VARCHAR(10) CHECK (trx_type IN ('PURCHASE','SALE','ADJUSTMENT')),
    qty      INT NOT NULL,
    trx_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE OR REPLACE FUNCTION trg_update_stock_and_journal() RETURNS trigger AS $$
DECLARE
    v_stock INT;
    v_cost  NUMERIC(15,2);
    v_delta INT;
BEGIN
    SELECT stock_qty, unit_cost INTO v_stock, v_cost
      FROM inventory_items WHERE item_id = NEW.item_id FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Barang % tidak ditemukan', NEW.item_id;
    END IF;

    IF NEW.trx_type IN ('PURCHASE','SALE') AND NEW.qty <= 0 THEN
        RAISE EXCEPTION 'qty untuk % harus > 0 (diterima: %)', NEW.trx_type, NEW.qty;
    END IF;

    v_delta := CASE NEW.trx_type
                 WHEN 'PURCHASE'   THEN  NEW.qty
                 WHEN 'SALE'       THEN -NEW.qty
                 WHEN 'ADJUSTMENT' THEN  NEW.qty
               END;

    IF v_stock + v_delta < 0 THEN
        RAISE EXCEPTION 'Stok % tidak cukup: tersedia %, diminta % (%)',
                        NEW.item_id, v_stock, ABS(v_delta), NEW.trx_type;
    END IF;

    UPDATE inventory_items SET stock_qty = stock_qty + v_delta WHERE item_id = NEW.item_id;

    RETURN NEW;
END; $$ LANGUAGE plpgsql;

CREATE TRIGGER trg_inventory_mutation
BEFORE INSERT ON inventory_transactions
FOR EACH ROW EXECUTE FUNCTION trg_update_stock_and_journal();

ALTER TABLE inventory_items ADD CONSTRAINT chk_stock_nonneg CHECK (stock_qty >= 0);

-- ============================================
-- SOAL 2.2 - Contoh kode concurrency (untuk laporan)
-- ============================================

-- Teknik 1: SELECT ... FOR UPDATE
-- BEGIN;
--   SELECT stock_qty FROM inventory_items WHERE item_id = 'BRG-001' FOR UPDATE;
--   INSERT INTO inventory_transactions(item_id, trx_type, qty) VALUES ('BRG-001', 'SALE', 1);
-- COMMIT;

-- Teknik 2: update atomik bersyarat
-- UPDATE inventory_items SET stock_qty = stock_qty - 1
--  WHERE item_id = 'BRG-001' AND stock_qty >= 1;

-- Teknik 3: isolasi SERIALIZABLE (ulangi bila error 40001)
-- BEGIN ISOLATION LEVEL SERIALIZABLE;
--   SELECT stock_qty FROM inventory_items WHERE item_id = 'BRG-001';
--   INSERT INTO inventory_transactions(item_id, trx_type, qty) VALUES ('BRG-001','SALE',1);
-- COMMIT;