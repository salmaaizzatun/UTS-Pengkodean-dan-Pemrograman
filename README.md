# UTS Pengkodean dan Pemrograman

Laporan Ujian Tengah Semester Gasal 2026/2027  
Mata Kuliah: Pengkodean dan Pemrograman / Coding

## Identitas

- **Nama:** Salma Izzatun Nisa Rahmawati
- **NIM:** 12030124120044
- **Kelas:** D
- **Program Studi:** S1 Akuntansi
- **Fakultas:** Ekonomika dan Bisnis
- **Universitas:** Diponegoro

## Isi Repository

| Folder | Isi |
|---|---|
| `SOAL 1/` | DDL schema, constraint, trigger balance + screenshot |
| `SOAL 2/` | Trigger persediaan + screenshot eksekusi |
| `SOAL 3/` | Audit trail, immutability, RPC + screenshot |
| `voucher_entri_transaksi_kas_keluar.html` | Purwarupa formulir voucher |
| `prompt_log.md` | Dokumentasi prompt Gemini Canvas |
| `erd.png` | Entity Relationship Diagram |

## Alat yang Digunakan

- Supabase (PostgreSQL)
- dbdiagram.io
- Gemini Canvas
- NotebookLM
- HTML + Tailwind CSS
- JavaScript

## Cara Menjalankan

1. Buka file `voucher_entri_transaksi_kas_keluar.html` di browser
2. Isi form dengan data jurnal yang seimbang (Debit = Kredit)
3. Klik tombol "Submit Voucher"
4. Data akan tersimpan di Supabase melalui RPC `create_voucher`
