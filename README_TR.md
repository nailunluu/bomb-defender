# Bomb Defender

Bomb Defender, Godot 4 ile geliştirilmiş çevrimdışı oynanabilen 2D bomba ve labirent oyunudur.

**Hava durumu ekranı ve Open-Meteo bağlantısı tamamen kaldırılmıştır.** Oyun hiçbir API anahtarı veya internet bağlantısı istemez.
Oyun açılırken Godot logosu gösterilmez; Windows uygulaması ve görev çubuğunda Bomb Defender simgesi kullanılır.

## Nasıl oynanır?

Her bölümde iki ayrı kırılabilir kutu seçilir: Birinde **bir rastgele geliştirme ödülü**, diğerinde **gizli çıkış kapısı** bulunur. Kutuları bombayla patlat. Yere düşen ödülün üzerine yürü. Bütün düşmanları yen ve açılan kapıya girerek sonraki bölüme geç.

Başlangıç patlama menzili 1 karedir; patlama etkisi 0,26 saniyedir. Uzaktan patlatma, bomba kaydırma ve kutulardan geçme yetenekleri de rastgele bölüm ödülü olarak kazanılır ve sonraki bölümlerde korunur.

| Simge | Özellik |
|---|---|
| `+` | Patlama menzili, +1 kare (en fazla 6) |
| `B` | Birlikte konabilecek bomba sayısı, +1 (en fazla 5) |
| `>` | Hareket hızı, +1 |
| `H` | Ekstra can, +1 |
| `D` | Uzaktan patlatma, `E` tuşuyla |
| `K` | Bombaya yürüyerek bombayı kaydırma |
| `G` | Kırılabilir kutuların içinden geçme |

### Kontroller

`WASD` veya yön tuşları: yürü; `Space`: bomba koy; `E`: D yeteneğiyle uzaktan patlat; `P` / `Esc`: duraklat; `R`: yeni oyun; `Enter`: başlat.

## Godot üzerinde açma

1. Godot 4.4.1'i aç.
2. **Import / İçe Aktar** seçeneğinden bu klasördeki `project.godot` dosyasını seç.
3. **F5** ile oyunu başlat.

## Windows için oynanabilir EXE oluşturma

Bu kaynak pakette önceden derlenmiş bir EXE yoktur. Windows EXE'yi aşağıdaki iki yöntemden biriyle oluşturabilirsin:

**Yöntem A — GitHub (Codex ile yükleme için tavsiye):**

1. Bu klasörün **içindeki bütün dosyaları** GitHub'daki `bomb-defender` deposunun kök dizinine yükle; `.github/workflows/windows.yml` de mutlaka yüklensin.
2. GitHub → **Actions** → **Windows Build** bölümünden son başarılı çalışmayı aç.
3. **Artifacts** altındaki `Bomb-Defender-Windows` dosyasını indir. İçindeki `Bomb Defender.zip` oyunculara gönderebileceğin pakettir.
4. Herkesin GitHub'dan indirebilmesi için Codex üzerinden `v1.0.0` gibi bir **tag** gönder. GitHub Actions çalışıp **Releases** bölümüne `Bomb Defender.zip` paketini koyacak.

**Yöntem B — Kendi Windows bilgisayarında:**

1. Godot 4.4.1 içinde **Editor → Manage Export Templates → Download and Install** ile Windows export şablonlarını yükle.
2. `Build Windows.bat` dosyasını çalıştır. Godot Windows PATH içinde bulunmazsa uygulamanın EXE yolunu sorar; simge için gereken `rcedit` aracını otomatik indirip ayarlar.
3. `dist/` klasöründe `Bomb Defender.exe`, `Bomb Defender.pck` ve paylaşmaya hazır `Bomb Defender.zip` oluşur.

**Oyuncular için:** Hazır Windows paketini [en son GitHub Release sayfasından](https://github.com/nailunluu/bomb-defender/releases/latest) `Bomb Defender.zip` olarak indir. ZIP'i çıkardıktan sonra `Bomb Defender.exe` ve `Bomb Defender.pck` aynı klasörde kalmalıdır; oyunu `.exe` dosyasına çift tıklayarak açabilirsin. İnternet bağlantısı gerekmez. Windows uygulamalarında `.exe` gerçek dosya uzantısıdır; sürüm veya `Godot` eki dosya adına eklenmez.

**Yerel derleme:** Proje Godot 4.4.1 ile içe aktarıldı ve Windows x64 paketi `dist/` klasöründe oluşturuldu. `dist/` GitHub kaynak deposuna eklenmez; kaynakları yüklediğinde `.github/workflows/windows.yml` aynı paketi Actions artifact'i olarak üretir.
