# Prompt Log Gemini Canvas

## Prompt 1
Buat satu file HTML dengan Tailwind CSS dan JavaScript murni untuk Voucher Entri Transaksi Kas Keluar. 

Field header: tanggal, nomor bukti, deskripsi.

Tabel baris jurnal dinamis (bisa tambah/hapus baris) dengan kolom: akun (dropdown), debit, kredit.

Fitur:
- Hitung total debit, total kredit, dan selisih secara real time
- Tampilkan indikator hijau "BALANCED" bila selisih = 0 dan total > 0
- Tampilkan indikator merah "TIDAK SEIMBANG" bila tidak
- Tombol Submit nonaktif selama tidak seimbang

### Respons Gemini
Gemini membuat form voucher HTML dengan Tailwind CSS, dropdown akun, kalkulasi real-time, indikator BALANCED/TIDAK SEIMBANG, tombol Submit nonaktif saat tidak seimbang.

## Prompt 2
Tambahkan aturan validasi:
- Satu baris hanya boleh debit atau kredit (tidak boleh keduanya)
- Nilai tidak boleh negatif
- Minimal 2 baris
- Bandingkan dalam satuan sen (integer) untuk hindari galat floating point

### Respons Gemini
Gemini menambahkan validasi: satu baris hanya boleh debit atau kredit, tidak boleh negatif, minimal 2 baris, perbandingan dalam satuan sen (integer).

## Prompt 3
Hubungkan tombol Submit ke Supabase RPC create_voucher dan tampilkan pesan error dari database apa adanya.

### Respons Gemini
Gemini menambahkan konfigurasi Supabase (URL + anon key) dan tombol submit memanggil RPC create_voucher.