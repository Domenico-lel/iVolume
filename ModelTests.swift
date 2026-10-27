import Foundation
@main
struct ModelTests {
    static func main() {
        let suite = "it.domenicolella.ivolume.regression.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let model = VolumeModel(defaults: defaults)
        for i in 0..<200 { model.volume = Double(i % 101)/100 }
        model.volume = 0.35
        model.handleMediaKey(1)
        assert(abs(model.volume - 0.2875) < 0.00001)
        model.handleMediaKey(0)
        assert(abs(model.volume - 0.35) < 0.00001)
        model.handleMediaKey(7); assert(model.muted)
        model.handleMediaKey(7); assert(!model.muted)
        for _ in 0..<40 { model.handleMediaKey(0) }; assert(model.volume == 1)
        for _ in 0..<40 { model.handleMediaKey(1) }; assert(model.volume == 0)
        model.shutdown()
        defaults.removePersistentDomain(forName: suite)
        print("PASS: volume observer regression, media-key changes, mute, lower/upper bounds")
    }
}
