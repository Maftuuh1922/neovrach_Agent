/**
 * Indonesian copy for Neovarch's "Profil & Teman" page (GitHub friends/profile).
 *
 * Neovarch-only surfaces keep their strings in a small Neovarch catalog instead of
 * the upstream `en` key tree, so the eight bundled upstream locales (which must
 * mirror the English key set exactly) are not forced to carry copy they never
 * show. Interpolation uses `{name}` placeholders filled by `fmt()`.
 */
export const NV_SOCIAL_ID = {
  rail: 'Profil & Teman',
  kicker: 'Profil & Teman',
  title: 'Profil & Teman',
  sub: 'Profil kamu diambil dari GitHub, aktivitasnya dihitung di PC ini, lalu dipublikasikan ke Gist publik. Teman = saling follow di GitHub.',
  signIn: 'Masuk dengan GitHub',
  signOut: 'Keluar',
  signingIn: 'Menunggu persetujuan di GitHub…',
  deviceStep1: 'Buka {url} lalu masukkan kode ini:',
  copyCode: 'Salin kode',
  openGithub: 'Buka GitHub',
  cancel: 'Batal',
  noClientId: 'Client ID OAuth App GitHub belum diatur.',
  noClientIdHelp:
    'Buat OAuth App di GitHub (Settings → Developer settings → OAuth Apps → New, centang "Enable Device Flow"), lalu tempel Client ID-nya di sini. Tidak perlu client secret.',
  clientIdLabel: 'Client ID GitHub',
  clientIdSave: 'Simpan',
  signedOutTitle: 'Belum masuk',
  signedOutBody:
    'Masuk dengan GitHub untuk menampilkan profil, grafik aktivitas, stack yang sering dipakai, dan teman yang lagi ngoding.',
  codingNow: 'Lagi ngoding',
  codingIn: 'Lagi ngoding · {project}',
  idle: 'Tidak aktif',
  lastActive: 'Aktif {when}',
  heatmapTitle: 'Aktivitas 365 hari',
  heatmapLegendLess: 'Sedikit',
  heatmapLegendMore: 'Banyak',
  heatmapSummary: '{total} aktivitas · {days} hari aktif · streak {streak} hari',
  heatmapCell: '{date}: {count} aktivitas',
  stackTitle: 'Stack yang sering dipakai',
  toolsTitle: 'Alat agen',
  stackEmpty: 'Belum ada data stack.',
  friendsTitle: 'Teman',
  friendsCount: '{n} teman · {coding} lagi ngoding',
  friendsEmpty: 'Belum ada teman. Teman adalah akun GitHub yang saling follow dengan kamu.',
  pendingTitle: 'Menunggu follow balik',
  noNeovarch: 'Belum pakai Neovarch',
  addFriend: 'Tambah teman',
  searchPlaceholder: 'Cari username GitHub…',
  follow: 'Follow',
  following: 'Di-follow',
  followsYou: 'Follow kamu',
  unfriend: 'Hapus teman',
  unfriendConfirm: 'Hapus {login} dari teman? Ini akan unfollow {login} di GitHub.',
  unfriendYes: 'Ya, unfollow',
  back: 'Kembali',
  openProfile: 'Profil GitHub',
  privacyTitle: 'Privasi & publikasi',
  publishHeatmap: 'Publikasikan grafik aktivitas',
  publishStack: 'Publikasikan stack',
  publishStatus: 'Publikasikan status "lagi ngoding"',
  shareProject: 'Tampilkan nama proyek saat ngoding',
  includeContrib: 'Gabungkan kontribusi GitHub di grafik',
  paused: 'Jeda publikasi',
  publishNow: 'Publikasikan sekarang',
  publishedAt: 'Terakhir dipublikasikan {when}',
  neverPublished: 'Belum pernah dipublikasikan',
  gistLink: 'Lihat Gist',
  loading: 'Memuat…',
  retry: 'Coba lagi',
  error: 'Gagal memuat: {message}',
  justNow: 'baru saja',
  minutesAgo: '{n} mnt lalu',
  hoursAgo: '{n} jam lalu',
  daysAgo: '{n} hari lalu',
  share: 'Bagikan profil',
  shareTitle: 'Bagikan profil',
  shareFormat: 'Format kartu',
  shareStory: 'Story 9:16',
  shareSquare: 'Kotak 1:1',
  sharePreview: 'Pratinjau kartu profil',
  shareSize: 'PNG {w}×{h} piksel',
  shareSave: 'Simpan PNG',
  shareSaved: 'PNG disimpan ke folder unduhan.',
  shareCopy: 'Salin gambar',
  shareCopied: 'Gambar disalin ke papan klip.',
  shareLink: 'Salin tautan Gist',
  shareLinkCopied: 'Tautan profil disalin.'
} as const

export type NvSocialKey = keyof typeof NV_SOCIAL_ID

/** Fill `{name}` placeholders. Unknown placeholders are left as-is. */
export function fmt(template: string, args: Record<string, number | string> = {}): string {
  return template.replace(/\{(\w+)\}/g, (all, key: string) => (key in args ? String(args[key]) : all))
}

export function socialT(key: NvSocialKey, args?: Record<string, number | string>): string {
  return fmt(NV_SOCIAL_ID[key], args)
}
