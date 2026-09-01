import AVFoundation
import KSPlayer

/// Oynatıcı seçenekleri.
///
/// Tek işi tamponun dolu sayılma ölçütünü ses çıkışına uydurmak — ve yalnızca
/// çıkış `AudioRendererPlayer` olduğunda; `AudioEnginePlayer` yolunda
/// kütüphanenin kendi ölçütü olduğu gibi geçerli. Ses
/// `AudioRendererPlayer` ile çalındığından çözülmüş kareler
/// `AVSampleBufferAudioRenderer`ın kuyruğunda birikiyor; `MEPlayerItemTrack`
/// ise `frameCount`u kendi `outputRenderQueue`undan okuyor ve renderer o
/// kuyruğu sürekli boşalttığı için sesin `loadedTime`ı
/// `preferredForwardBufferDuration`ı hiç bulamıyor.
///
/// Sonuç: ses de görüntü de akarken oynatıcı `buffering` ile `bufferFinished`
/// arasında durmadan gidip geliyor, ekranda spinner kalıyor, oynatma dilim
/// dilim ilerliyor. Ağla ilgisi yok — sesin nerede tamponlandığı değişince
/// ölçüm anlamını yitiriyor.
///
/// Burada ses, oynatma başladıktan sonra hakemlikten tamamen çıkarılıyor:
/// tamponun yeterli olup olmadığına yalnızca video izi karar veriyor. Sese
/// bir alt sınır koymak çözüm değil, çünkü renderer kuyruğu sıfıra çektiği
/// için ses hangi eşik konursa onun etrafında salınıyor ve aynı sorun daha
/// aşağıda yeniden üretiliyor.
///
/// İlk açılış ve sarma bunun dışında: orada `AVSampleBufferRenderSynchronizer`
/// zaman tabanını gerçek bir medya damgasına bağlıyor ve elinde ses karesi
/// yoksa `.zero`ya düşüyor — saat medyanın önünde başlar ve bir daha
/// yakalayamaz. O anda kütüphanenin `frameCount >= 2` koruması gerekli, o
/// yüzden dokunulmuyor.
final class PlayerOptions: KSOptions {
    override func playable(capacitys: [CapacityProtocol], isFirst: Bool, isSeek: Bool) -> LoadingState {
        // Yalnızca sesi renderer çalarken geçerli. `AudioEnginePlayer` çekme
        // tabanlı: her render çağrısında bir kare alıyor, kuyruk dolu kalıyor
        // ve kütüphanenin ölçütü doğru çalışıyor. Orada sesin veto hakkını
        // kaldırmak yanlış olur — tampon gerçekten zayıfken oynatmayı sürdürür.
        guard KSOptions.audioPlayerType == AudioRendererPlayer.self else {
            return super.playable(capacitys: capacitys, isFirst: isFirst, isSeek: isSeek)
        }
        // Saatin doğru damgaya bağlanması gereken anlar: kütüphane karar versin.
        guard !isFirst, !isSeek else {
            return super.playable(capacitys: capacitys, isFirst: isFirst, isSeek: isSeek)
        }
        // Hakemlik edecek bir video izi yoksa ölçüyü elimizden bırakamayız.
        guard capacitys.contains(where: { $0.mediaType == .video }) else {
            return super.playable(capacitys: capacitys, isFirst: isFirst, isSeek: isSeek)
        }

        let adjusted = capacitys.map { capacity -> CapacityProtocol in
            guard capacity.mediaType == .audio, !capacity.isEndOfFile else { return capacity }
            // `frameCount` en az 2 olmalı: kütüphane bunun altındaki her izi
            // peşinen oynatılamaz sayıyor ve renderer kuyruğu sıfırda tutuyor.
            return SaturatedCapacity(
                fps: capacity.fps,
                packetCount: Int((TimeInterval(max(capacity.fps, 1)) * preferredForwardBufferDuration).rounded(.up)) + 1,
                frameCount: max(capacity.frameCount, 2),
                frameMaxCount: capacity.frameMaxCount,
                isEndOfFile: capacity.isEndOfFile,
                mediaType: capacity.mediaType
            )
        }

        return super.playable(capacitys: adjusted, isFirst: isFirst, isSeek: isSeek)
    }
}

/// Tamponu dolu görünen bir iz. Yalnızca `playable` hesabına girmek için var.
private struct SaturatedCapacity: CapacityProtocol {
    let fps: Float
    let packetCount: Int
    let frameCount: Int
    let frameMaxCount: Int
    let isEndOfFile: Bool
    let mediaType: AVMediaType
}
