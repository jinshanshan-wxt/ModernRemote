import Foundation

@main struct PlaybackPresentationTests {
    static func main() {
        let client = RemoteClient()
        func wait(_ seconds: Double) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }
        var song = Playback(); song.trackID = "0000000000000001"; song.playing = true
        client.applyPlayback(song)
        client.applyPlayback(Playback())
        wait(0.4)
        precondition(client.playback.trackID == song.trackID, "Transient empty state must not blank player")
        // The next regular status poll resolves the transition.
        wait(1.6)
        song.trackID = "0000000000000002"; client.applyPlayback(song)
        wait(0.6)
        precondition(client.playback.trackID == song.trackID, "Cancelled empty update must not blank new song")
        client.applyPlayback(Playback()); wait(2)
        client.applyPlayback(Playback()); wait(0.6)
        precondition(client.playback.trackID == nil, "Repeated stopped reports must eventually clear player")
        client.applyPlayback(song); client.applyPlayback(Playback()); client.disconnect()
        client.applyPlayback(Playback()); wait(2.6)
        precondition(client.playback.trackID == nil, "Disconnect must release the cancelled transition")
        print("PASS: player survives transient empty status, updates next song, clears genuine stop and disconnect")
    }
}
