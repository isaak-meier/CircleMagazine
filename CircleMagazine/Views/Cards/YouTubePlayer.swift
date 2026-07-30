//
//  YouTubePlayer.swift
//  CircleMagazine
//
//  A YouTube embed with our own controls instead of YouTube's chrome. The
//  IFrame Player API runs in a WKWebView (controls:0); JS posts state back over
//  a script message handler, and SwiftUI draws the controls over the video:
//  play/pause, a seek scrubber, mute, and fullscreen. Taps toggle the controls
//  (and are consumed, so YouTube's own tap overlay never shows).
//

import SwiftUI
import WebKit

/// Flip to false to bring back our custom control bar (scrubber/play/mute/
/// fullscreen). true uses YouTube's native controls and hides ours — safe only
/// while the player keeps its full width on screen, since YouTube's bar spans
/// the frame and a cropped player would cut its end buttons off.
private let ytUseNativeControls = true

/// Mute is a per-viewer preference, shared across every card, so unmuting one
/// video keeps the next one you scroll to unmuted too.
@Observable @MainActor
final class MutePreference {
    static let shared = MutePreference()
    var isMuted = true
    private init() {}
}

@Observable @MainActor
final class YTPlayerModel {
    var isPlaying = false
    var currentTime: Double = 0
    var duration: Double = 0
    private(set) var isReady = false
    private var active = false
    /// Set when the viewer taps the facade's play button before the webview has
    /// mounted/readied — we play as soon as it's ready.
    private var playWhenReady = false

    weak var webView: WKWebView?

    private func js(_ code: String) { webView?.evaluateJavaScript(code) }

    /// The facade play button was tapped — mount is happening; play on ready.
    func requestPlay() {
        playWhenReady = true
        if isReady { js("cmPlay()") }
    }

    func togglePlay() { isPlaying ? js("cmPause()") : js("cmPlay()") }
    func seek(to t: Double) { currentTime = t; js("cmSeek(\(t))") }
    func fullscreen() { js("cmFullscreen()") }
    func applyMute() { js(MutePreference.shared.isMuted ? "cmMute()" : "cmUnmute()") }

    /// Autoplay is off — becoming the snapped-to card does NOT start playback;
    /// the viewer taps play. We still pause when scrolled away.
    func setActive(_ a: Bool) {
        active = a
        guard isReady else { return }
        applyMute()
        if !a { js("cmPause()") }
    }

    // MARK: JS → Swift
    func onReady() {
        isReady = true
        applyMute()
        // autoplay off — only play if the viewer tapped the facade's play button.
        if playWhenReady { js("cmPlay()") }
    }
    func onState(_ state: Int, duration d: Double) {
        isPlaying = (state == 1)
        if d > 0 { duration = d }
    }
    func onTime(_ t: Double, duration d: Double) {
        currentTime = t
        if d > 0 { duration = d }
    }
}

struct YouTubePlayer: View {
    let id: String
    var isActive: Bool

    @State private var model = YTPlayerModel()
    @State private var activated = false
    @State private var controlsVisible = true
    @State private var scrubbing = false
    @State private var scrubTime = 0.0

    var body: some View {
        // The card sizes itself to 16:9, so the player just fills what it's
        // given — no letterboxing to hide and nothing to crop.
        ZStack(alignment: .bottom) {
            if activated {
                YTWebView(id: id, model: model)

                if !ytUseNativeControls {
                    // Consume taps so YouTube's own overlay never appears; toggle ours.
                    Color.clear.contentShape(Rectangle())
                        .onTapGesture { withAnimation(.easeInOut(duration: 0.2)) { controlsVisible.toggle() } }

                    if controlsVisible { controlBar.transition(.opacity) }
                }
            } else {
                facade
            }
        }
        .onChange(of: isActive, initial: true) { _, active in model.setActive(active) }
    }

    /// Lightweight stand-in shown until the viewer taps play, so the costly
    /// WKWebView only mounts on demand — no hitch when the card first appears.
    private var facade: some View {
        Button {
            activated = true
            model.requestPlay()
        } label: {
            // Color.black takes the proposed size and the still hangs off it as
            // an overlay — an aspectRatio(.fill) reports its oversized frame up
            // the layout, which would push the caption plate off the card.
            Color.black
                .overlay { still.aspectRatio(16.0 / 9.0, contentMode: .fill) }
                .clipped()
                .overlay {
                    Image(systemName: "play.fill")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 58, height: 58)
                        .background(.black.opacity(0.55), in: SwiftUI.Circle())
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// The thumbnail. hqdefault, because it's the one size every upload has:
    /// maxresdefault 404s for plenty of videos and img.youtube.com answers a
    /// 404 with a grey placeholder *image*, which AsyncImage reports as a
    /// success — so a "prefer maxres, fall back" ladder silently shows grey.
    /// It's 4:3 with baked black bars; scaledToFill crops those away.
    private var still: some View {
        AsyncImage(url: URL(string: "https://img.youtube.com/vi/\(id)/hqdefault.jpg")) {
            $0.resizable().scaledToFill()
        } placeholder: {
            Color.black
        }
    }

    private var controlBar: some View {
        VStack(spacing: 8) {
            PlayerScrubber(progress: displayProgress) { fraction, editing in
                scrubbing = editing
                scrubTime = fraction * max(model.duration, 1)
                if !editing { model.seek(to: scrubTime) }
            }

            HStack(spacing: 16) {
                Button { model.togglePlay() } label: {
                    Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                }
                Text("\(clock(scrubbing ? scrubTime : model.currentTime)) / \(clock(model.duration))")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                Spacer(minLength: 0)
                Button {
                    MutePreference.shared.isMuted.toggle()
                    model.applyMute()
                } label: {
                    Image(systemName: MutePreference.shared.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                }
                Button { model.fullscreen() } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                }
            }
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white)
        }
        .padding(.horizontal, 14).padding(.bottom, 8).padding(.top, 24)
        .background(LinearGradient(colors: [.clear, .black.opacity(0.55)],
                                   startPoint: .top, endPoint: .bottom))
    }

    private var displayProgress: Double {
        let t = scrubbing ? scrubTime : model.currentTime
        return t / max(model.duration, 1)
    }

    private func clock(_ t: Double) -> String {
        guard t.isFinite, t >= 0 else { return "0:00" }
        let s = Int(t)
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

// MARK: - Scrubber

/// Thin track with a small dot; tap or drag to seek. `onScrub(fraction, editing)`
/// fires continuously while dragging (editing=true) and once on release (false).
private struct PlayerScrubber: View {
    let progress: Double
    let onScrub: (Double, Bool) -> Void

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let p = max(0, min(1, progress))
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.3)).frame(height: 3)
                Capsule().fill(.white).frame(width: p * w, height: 3)
                SwiftUI.Circle().fill(.white).frame(width: 10, height: 10).offset(x: p * w - 5)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { onScrub(max(0, min(1, $0.location.x / w)), true) }
                    .onEnded   { onScrub(max(0, min(1, $0.location.x / w)), false) }
            )
        }
        .frame(height: 16)
    }
}

// MARK: - Web view

private struct YTWebView: UIViewRepresentable {
    let id: String
    let model: YTPlayerModel

    func makeCoordinator() -> Coordinator { Coordinator(model) }

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        let model: YTPlayerModel
        init(_ model: YTPlayerModel) { self.model = model }

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any],
                  let event = body["event"] as? String else { return }
            let state = body["state"] as? Int ?? -1
            let time = body["time"] as? Double ?? 0
            let duration = body["duration"] as? Double ?? 0
            Task { @MainActor in
                switch event {
                case "ready": model.onReady()
                case "state": model.onState(state, duration: duration)
                case "time":  model.onTime(time, duration: duration)
                default: break
                }
            }
        }
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.preferences.isElementFullscreenEnabled = true
        // ponytail: WKUserContentController strongly retains the handler; fine
        // for the handful of cards on screen — revisit if players leak.
        let ucc = WKUserContentController()
        ucc.add(context.coordinator, name: "yt")
        config.userContentController = ucc

        let web = WKWebView(frame: .zero, configuration: config)
        web.scrollView.isScrollEnabled = false
        web.isOpaque = false
        web.navigationDelegate = context.coordinator
        model.webView = web
        web.loadHTMLString(html, baseURL: URL(string: "https://circlemagazine.app"))
        return web
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    private var html: String {
        """
        <!DOCTYPE html><html><head>
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>html,body{margin:0;background:#000;height:100%;overflow:hidden}#p{width:100%;height:100%}</style>
        </head><body>
        <div id="p"></div>
        <script>
          var player, ready=false, wantPlay=false, wantMute=true, timer=null;
          function post(o){ try{ window.webkit.messageHandlers.yt.postMessage(o); }catch(e){} }
          function tick(){ if(player&&player.getCurrentTime){
            post({event:'time', time:player.getCurrentTime(), duration:player.getDuration()}); } }
          function onYouTubeIframeAPIReady(){
            player = new YT.Player('p', {
              videoId: '\(id)',
              playerVars: {playsinline:1, controls:\(ytUseNativeControls ? 1 : 0), rel:0,
                           modestbranding:1, fs:1, iv_load_policy:3,
                           disablekb:\(ytUseNativeControls ? 0 : 1), mute:1,
                           origin:'https://circlemagazine.app'},
              events: {
                onReady: function(){
                  ready=true;
                  if(wantMute){player.mute();}else{player.unMute();}
                  if(wantPlay){player.playVideo();}
                  post({event:'ready'});
                },
                onStateChange: function(e){
                  post({event:'state', state:e.data, duration:player.getDuration()});
                  if(e.data==1){ if(!timer){ timer=setInterval(tick,250); } }
                  else { if(timer){ clearInterval(timer); timer=null; } }
                }
              }
            });
          }
          function cmPlay(){ wantPlay=true; if(ready){player.playVideo();} }
          function cmPause(){ wantPlay=false; if(ready){player.pauseVideo();} }
          function cmMute(){ wantMute=true; if(ready){player.mute();} }
          function cmUnmute(){ wantMute=false; if(ready){player.unMute();player.setVolume(100);} }
          function cmSeek(t){ if(ready){player.seekTo(t,true);} }
          function cmFullscreen(){ if(!player)return; var f=player.getIframe();
            if(f.requestFullscreen){f.requestFullscreen();}
            else if(f.webkitRequestFullscreen){f.webkitRequestFullscreen();} }
          var s=document.createElement('script');
          s.src='https://www.youtube.com/iframe_api';
          document.head.appendChild(s);
        </script>
        </body></html>
        """
    }
}
