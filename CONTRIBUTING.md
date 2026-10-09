# Berkontribusi ke Neovarch Agent

Terima kasih sudah mau membantu. Panduan singkat ini berlaku untuk desktop (`desktop/`), inti (`core/`), dan remote HP (`lib/`).

## Sebelum mulai

- Cari dulu di [Issues](https://github.com/Maftuuh1922/neovrach_Agent/issues) agar tidak dobel.
- Untuk perubahan besar, buka issue lebih dulu dan jelaskan rencananya.
- Bug dan ide fitur: pakai templat di **New issue**.

## Alur kerja

1. Fork repo, lalu buat branch dari `main` (pengembangan v1.4 desktop di `neovarch-office`, HP di `neovarch-android`).
   Nama branch: `fix/…`, `feat/…`, atau `docs/…`.
2. Buat perubahan kecil dan fokus. Satu PR untuk satu hal.
3. Jalankan tes yang relevan (lihat di bawah) sebelum membuka PR.
4. Buka Pull Request ke `main` (atau ke branch pengembangan yang sesuai) dengan deskripsi singkat: apa yang berubah dan kenapa.

## Tes

```bash
# Desktop
cd desktop && npm ci && npm run typecheck && npm test

# Inti
cd core && pip install -e '.[test]' && python -m pytest -q

# HP
flutter pub get && flutter analyze && flutter test
```

## Gaya

- Teks UI dalam bahasa Indonesia.
- Tampilan: gelap, merah datar, sudut membulat, tanpa gradien.
- Pesan commit singkat dan jelas, dalam bentuk kalimat (bahasa Indonesia atau Inggris).
- Jangan pernah meng-commit API key, token, atau berkas `.env`.
- Inti hanya boleh membaca dan menulis di `~/.neovarch`.

## Lisensi

Dengan berkontribusi, kamu setuju kontribusimu dirilis di bawah lisensi MIT (lihat `LICENSE`).
Kode di `desktop/` juga tunduk pada pemberitahuan di `desktop/LICENSE` dan `desktop/NOTICE`.
