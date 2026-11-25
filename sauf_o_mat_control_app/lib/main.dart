import 'dart:math';
import 'package:flutter/material.dart';
import 'package:sauf_o_mat_control_app/colors.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:sauf_o_mat_control_app/server_manager.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");

  final String? ipAddress = dotenv.env['SERVER_IP'];
  final String? port = dotenv.env['SERVER_PORT'];
  // Does not block if the server is unreachable; keeps retrying in background.
  ServerManager().connect("ws://$ipAddress:$port");

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(title: 'Sauf-O-Mat Controls', theme: appTheme, home: const MyHomePage());
  }
}

class NavigationPage {
  final String name;
  final int index;
  final bool isLivestream;

  NavigationPage({required this.name, required this.index, this.isLivestream = false});
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

List<NavigationPage> pages = [
  NavigationPage(name: "Balkendiagramm", index: 0),
  NavigationPage(name: "Top 3", index: 1),
  NavigationPage(name: "Gewinn", index: 2),
  NavigationPage(name: "Ablaufplan", index: 3),
  NavigationPage(name: "Kommentare", index: 4),
  NavigationPage(name: "Werbung", index: 5),
  NavigationPage(name: "Ex-Cam", index: 6, isLivestream: true),
  NavigationPage(name: "Kiss-Cam", index: 7, isLivestream: true),
];

class MySize {
  double h = 0.0;
  double w = 0.0;
  BuildContext context;

  MySize(this.context) {
    w = MediaQuery.of(context).size.width;
    h = MediaQuery.of(context).size.height;
  }
}

/// Random ID of this phone for this app run, used to tell phones apart.
final String deviceId = "${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(1 << 32)}";

class _MyHomePageState extends State<MyHomePage> {
  NavigationPage currentNavigationPage = pages.first;
  bool indexFrozen = false;

  bool _showCamera = false;
  bool _isRecordingRunning = false;

  RTCVideoRenderer localVideo = RTCVideoRenderer();
  MediaStream? localStream;
  RTCPeerConnection? peerConnection;

  late final MessageHandler _socketListener = _handleSocketMessage;

  /// After this phone sends a command, "state" broadcasts that the display sent
  /// before handling the command (e.g. from its auto rotation) are outdated.
  /// Until then, only direct replies are applied.
  DateTime _ignoreUnsolicitedStateUntil = DateTime.fromMillisecondsSinceEpoch(0);

  void send(Map<String, dynamic> data) {
    ServerManager().send(data);
  }

  /// Sends a command to the display (pageIndex / freeze).
  void sendCommand(Map<String, dynamic> data) {
    _ignoreUnsolicitedStateUntil = DateTime.now().add(const Duration(seconds: 2));
    // Tell the display who sent a page change, so it knows which phone owns
    // the livestream. All other phones then turn their camera off.
    if (data["event"] == "pageIndex") data = {...data, "owner": deviceId};
    send(data);
  }

  void _onConnectionChanged() {
    if (!mounted) return;
    setState(() {});
    // Ask the display which page it shows right now.
    if (ServerManager().connected.value) send({"event": "requestState"});
  }

  Future<void> _handleSocketMessage(Map<String, dynamic> decoded) async {
    try {
      // Note: phones never answer "offer" messages. A phone always starts the
      // call itself, and answering another phone's offer would connect the two
      // phones with each other instead of with the display.
      if (decoded["event"] == "ice") {
        await peerConnection?.addCandidate(
          RTCIceCandidate(decoded["data"]["candidate"], decoded["data"]["sdpMid"], decoded["data"]["sdpMLineIndex"]),
        );
      } else if (decoded["event"] == "answer") {
        // Only accept an answer while waiting for one to our own offer.
        final state = await peerConnection?.getSignalingState();
        if (state == RTCSignalingState.RTCSignalingStateHaveLocalOffer) {
          await peerConnection?.setRemoteDescription(
            RTCSessionDescription(decoded["data"]["sdp"], decoded["data"]["type"]),
          );
        }
      } else if (decoded["event"] == "state") {
        _applyDisplayState(decoded);
      } else {
        debugPrint(decoded.toString());
      }
    } catch (e) {
      debugPrint("ERROR $e");
    }
  }

  /// Syncs the dropdown and freeze switch with what the display really shows,
  /// so all phones show the same state.
  void _applyDisplayState(Map<String, dynamic> data) {
    if (!mounted) return;
    final index = data["pageIndex"];
    final frozen = data["frozen"];
    if (index is! int || frozen is! bool) return;
    if (data["reply"] != true && DateTime.now().isBefore(_ignoreUnsolicitedStateUntil)) return;

    final newPage = pages.firstWhere((p) => p.index == index, orElse: () => currentNavigationPage);
    final pageChanged = newPage.index != currentNavigationPage.index;
    final ownedByOtherPhone = newPage.isLivestream && data["livestreamOwner"] != deviceId;

    // Stop the local camera if the display left the livestream this phone was
    // on (other phone or prize page), or another phone took over the stream.
    final loseCamera = currentNavigationPage.isLivestream && (pageChanged || ownedByOtherPhone);
    if (loseCamera) stopLocalCamera();

    setState(() {
      indexFrozen = frozen;
      if (pageChanged) currentNavigationPage = newPage;
      if (loseCamera) {
        _showCamera = false;
        _isRecordingRunning = false;
      }
    });
  }

  /// Turns the camera off without telling the display, because the display
  /// is either on another page or already showing another phone's stream.
  Future<void> stopLocalCamera() async {
    _cameraGeneration++; // cancels a camera start that is still running
    _cameraStarting = false;
    await cleanupLivestream();
  }

  // STUN server configuration
  Map<String, dynamic> configuration = {
    'iceServers': [
      {
        'urls': ['stun:stun1.l.google.com:19302', 'stun:stun2.l.google.com:19302'],
      },
    ],
  };

  /// Increased on every camera start/stop. A start that was overtaken by a
  /// newer start/stop throws its result away instead of using it.
  int _cameraGeneration = 0;
  bool _cameraStarting = false;
  String? _cameraError;

  /// (Re)starts the local camera. Always releases the previous camera first,
  /// otherwise Android keeps it busy and the new start fails.
  Future<void> startCamera() async {
    final generation = ++_cameraGeneration;
    setState(() {
      _showCamera = false;
      _isRecordingRunning = false;
      _cameraStarting = true;
      _cameraError = null;
    });
    await cleanupLivestream();

    MediaStream? stream;
    RTCVideoRenderer? renderer;
    RTCPeerConnection? pc;
    try {
      stream = await navigator.mediaDevices.getUserMedia({
        'video': {'facingMode': 'environment'},
        'audio': false,
      });
      renderer = RTCVideoRenderer();
      await renderer.initialize();
      pc = await createPeerConnection(configuration);

      if (generation != _cameraGeneration || !mounted) {
        // Overtaken (e.g. another phone took over meanwhile): release again.
        await _release(pc, stream, renderer);
        return;
      }

      localStream = stream;
      localVideo = renderer;
      peerConnection = pc;
      renderer.srcObject = stream;
      for (final track in stream.getTracks()) {
        await pc.addTrack(track, stream);
      }
      registerPeerConnectionListeners();
      setState(() {
        _showCamera = true;
        _cameraStarting = false;
      });
      debugPrint("📷 Camera started");
    } catch (e) {
      debugPrint("❌ Error starting camera: $e");
      await _release(pc, stream, renderer);
      if (generation == _cameraGeneration && mounted) {
        setState(() {
          _cameraStarting = false;
          _cameraError = "Kamera konnte nicht gestartet werden ($e). \"Kamera neu starten\" drücken.";
        });
      }
    }
  }

  void makeCall() async {
    // Creating a offer for remote peer
    RTCSessionDescription offer = await peerConnection!.createOffer();

    // Setting own SDP as local description
    await peerConnection?.setLocalDescription(offer);

    // Sending the offer
    send({"event": "offer", "data": offer.toMap()});
  }

  // Help to debug our code
  void registerPeerConnectionListeners() {
    debugPrint("registerPeerConnectionListeners");
    peerConnection?.onIceGatheringState = (RTCIceGatheringState state) {
      debugPrint('ICE gathering state changed: $state');
    };

    peerConnection?.onIceCandidate = (RTCIceCandidate candidate) {
      send({"event": "ice", "data": candidate.toMap()});
    };

    peerConnection?.onConnectionState = (RTCPeerConnectionState state) {
      debugPrint('Connection state change: $state');
    };

    peerConnection?.onSignalingState = (RTCSignalingState state) {
      debugPrint('Signaling state change: $state');
    };
    peerConnection?.onTrack = (RTCTrackEvent event) {
      debugPrint("⚠️ Track received, but no stream available");
    };
  }

  Future<void> pauseCamera() async {
    try {
      if (localStream != null) {
        for (var track in localStream!.getVideoTracks()) {
          track.enabled = false; // Stop sending frames
          send({"event": "paused"});
        }
        debugPrint("📷 Camera paused");
      }
    } catch (e) {
      debugPrint("❌ Error pausing camera: $e");
    }
  }

  Future<void> resumeCamera() async {
    try {
      if (localStream != null) {
        for (var track in localStream!.getVideoTracks()) {
          track.enabled = true; // Resume sending frames
          send({"event": "resumed"});
        }
        debugPrint("📷 Camera resumed");
      }
    } catch (e) {
      debugPrint("❌ Error resuming camera: $e");
    }
  }

  /// Closes the peer connection and releases the camera and renderer.
  Future<void> cleanupLivestream() async {
    final pc = peerConnection;
    final stream = localStream;
    final renderer = localVideo;
    // Detach first, so nothing uses them while they are being released.
    peerConnection = null;
    localStream = null;
    localVideo = RTCVideoRenderer();
    await _release(pc, stream, renderer);
    debugPrint("✅ Livestream cleaned up");
  }

  Future<void> _release(RTCPeerConnection? pc, MediaStream? stream, RTCVideoRenderer? renderer) async {
    try {
      await pc?.close();
    } catch (e) {
      debugPrint("❌ Error closing peer connection: $e");
    }
    try {
      for (final track in stream?.getTracks() ?? <MediaStreamTrack>[]) {
        await track.stop(); // frees the camera
      }
      await stream?.dispose();
    } catch (e) {
      debugPrint("❌ Error stopping camera: $e");
    }
    try {
      await renderer?.dispose();
    } catch (e) {
      debugPrint("❌ Error disposing renderer: $e");
    }
  }

  Future<void> reloadApp() async {
    // Only restart the camera if this phone was the one streaming; otherwise
    // two phones would have their camera on.
    final hadCamera = _showCamera;
    await pauseCamera();
    await stopLocalCamera();

    await ServerManager().reconnect();
    if (!mounted) return;
    setState(() {
      _showCamera = false;
      _isRecordingRunning = false;
    });
    if (hadCamera && currentNavigationPage.isLivestream) startCamera();
  }

  @override
  void initState() {
    super.initState();
    ServerManager().addListener(_socketListener);
    ServerManager().connected.addListener(_onConnectionChanged);
    // The connection may already be open before this widget existed.
    if (ServerManager().connected.value) send({"event": "requestState"});
  }

  @override
  void dispose() {
    ServerManager().removeListener(_socketListener);
    ServerManager().connected.removeListener(_onConnectionChanged);
    peerConnection?.close();
    localVideo.dispose();
    super.dispose();
  }

  Widget myDropDownButtonFormField(double widthFactor, double paddingFactor) {
    return Container(
      width: MySize(context).w * widthFactor,
      padding: EdgeInsets.symmetric(horizontal: MySize(context).h * paddingFactor),
      decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary, borderRadius: BorderRadius.circular(8)),
      child: DropdownButtonFormField<String>(
        // initialValue is only read once; the key rebuilds the field when the
        // page is changed by the display or another phone.
        key: ValueKey(currentNavigationPage.index),
        initialValue: currentNavigationPage.name,
        icon: Icon(Icons.expand_more, color: Theme.of(context).colorScheme.onPrimary),
        dropdownColor: Theme.of(context).colorScheme.surface,
        decoration: const InputDecoration(
          enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.transparent)),
          focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.transparent)),
        ),
        style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
        selectedItemBuilder: (BuildContext context) {
          return pages.map((page) {
            return Align(
              alignment: Alignment.centerLeft,
              child: Text(
                page.name,
                style: TextStyle(color: Theme.of(context).colorScheme.onPrimary, fontWeight: FontWeight.bold),
              ),
            );
          }).toList();
        },
        items: pages.map((NavigationPage page) {
          return DropdownMenuItem<String>(
            value: page.name,
            child: Text(page.name, style: TextStyle(color: Theme.of(context).colorScheme.onSurface)),
          );
        }).toList(),
        onChanged: (String? newValue) async {
          NavigationPage newPage = pages.firstWhere((page) => page.name == newValue);
          // Same livestream page reselected while this phone's camera already
          // runs: keep it running instead of restarting it.
          final keepCamera = newPage.index == currentNavigationPage.index && _showCamera;

          debugPrint("send event pageIndex with index ${newPage.index}");
          sendCommand({"event": "pageIndex", "index": newPage.index});

          final leavesLivestream = currentNavigationPage.isLivestream && !newPage.isLivestream;
          setState(() {
            if (indexFrozen || newPage.isLivestream) {
              sendCommand({"event": "freeze", "freeze": true});
              indexFrozen = true;
            }
            if (leavesLivestream) {
              sendCommand({"event": "freeze", "freeze": false});
              indexFrozen = false;
            }
            currentNavigationPage = newPage;
            _cameraError = null;
            if (!keepCamera) {
              _isRecordingRunning = false;
              _showCamera = false;
            }
          });

          if (newPage.isLivestream && !keepCamera) {
            startCamera();
          } else if (leavesLivestream) {
            stopLocalCamera(); // frees the camera, it was only hidden before
          }
        },
      ),
    );
  }

  String get cameraPlaceholderText {
    if (!currentNavigationPage.isLivestream) return "Kamera wird aktiviert wenn Livestream ausgewählt ist";
    if (_cameraError != null) return _cameraError!;
    if (_cameraStarting) return "Kamera wird gestartet …";
    return "Livestream wurde von einem anderen Handy gestartet. \"Kamera neu starten\" um ihn zu übernehmen.";
  }

  Widget reloadAppButton() {
    final isConnected = ServerManager().connected.value;
    return ElevatedButton.icon(
      onPressed: reloadApp,
      icon: Icon(isConnected ? Icons.wifi : Icons.wifi_off, color: isConnected ? Colors.green : Colors.red),
      label: const Text("Neu verbinden"),
    );
  }

  Widget freezeSwitch() {
    return Row(
      children: [
        Text("Page freeze: "),
        Switch(
          value: indexFrozen,
          activeThumbColor: Colors.green,

          onChanged: (bool newFrozenValue) {
            setState(() {
              indexFrozen = newFrozenValue;
              debugPrint("freeze page: $newFrozenValue");
              sendCommand({"event": "freeze", "freeze": newFrozenValue});
            });
          },
        ),
      ],
    );
  }

  Widget reloadDataButton() {
    return currentNavigationPage.isLivestream
        ? ElevatedButton(
            onPressed: () async {
              sendCommand({"event": "pageIndex", "index": currentNavigationPage.index, "reset": true});
              await pauseCamera();
              await startCamera();
            },
            child: const Text("Kamera neu starten"),
          )
        : ElevatedButton(
            onPressed: () {
              debugPrint("send event reset");
              sendCommand({"event": "pageIndex", "index": currentNavigationPage.index, "reset": true});
            },
            child: const Text("Seiten-Daten neu laden"),
          );
  }

  Widget cameraWidget({
    required double controlBarHeight,
    required double height,
    required double width,
    Widget exCamLimiter = const SizedBox(),
    required double roseWreathWidthFactor,
    required double roseWreathTopPositionFactor,
    Widget kissCamLimiter = const SizedBox(),
  }) {
    return Stack(
      alignment: Alignment.center,
      children: [
        Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(width: width, height: height, child: RTCVideoView(localVideo, mirror: false)),
                currentNavigationPage.index != 7 ? exCamLimiter : kissCamLimiter,
              ],
            ),
            Container(
              width: width,
              height: controlBarHeight,
              color: Colors.black,
              child: IconButton(
                onPressed: () async {
                  if (_isRecordingRunning) {
                    await pauseCamera();
                  } else {
                    await resumeCamera();
                    makeCall();
                  }

                  setState(() {
                    _isRecordingRunning = !_isRecordingRunning;
                  });
                },
                icon: Icon(
                  _isRecordingRunning ? Icons.stop_circle : Icons.play_circle,
                  color: _isRecordingRunning ? Colors.red : Colors.white,
                ),
                iconSize: controlBarHeight * 0.7,
              ),
            ),
          ],
        ),
        if (currentNavigationPage.index == 7)
          Positioned(
            top: height * roseWreathTopPositionFactor,
            child: Image.asset(
              'assets/rose_wreath.png',
              width: width * roseWreathWidthFactor,
              height: width * roseWreathWidthFactor * 0.8,
              fit: BoxFit.fill,
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: MediaQuery.of(context).orientation == Orientation.portrait
          ? Padding(
              padding: EdgeInsets.symmetric(vertical: MySize(context).h * 0.06, horizontal: MySize(context).w * 0.03),
              child: Column(
                children: <Widget>[
                  Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [reloadAppButton(), myDropDownButtonFormField(0.5, 0.02)],
                      ),
                      SizedBox(height: MySize(context).h * 0.02),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [freezeSwitch(), reloadDataButton()],
                      ),
                    ],
                  ),
                  SizedBox(height: MySize(context).h * 0.02),
                  Expanded(
                    child: _showCamera
                        ? LayoutBuilder(
                            builder: (context, constraints) {
                              var controlBarHeight = constraints.maxHeight * 0.13;
                              var height = constraints.maxHeight - controlBarHeight;
                              var width = height * 9 / 16;
                              return cameraWidget(
                                controlBarHeight: controlBarHeight,
                                height: height,
                                width: width,
                                exCamLimiter: SizedBox(
                                  height: height,
                                  child: Column(
                                    mainAxisSize: MainAxisSize.max,
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Container(width: width, height: height * 0.2, color: Colors.black),
                                      Container(width: width, height: height * 0.16, color: Colors.black),
                                    ],
                                  ),
                                ),
                                roseWreathWidthFactor: 1.3,
                                roseWreathTopPositionFactor: 0.22,
                                kissCamLimiter: SizedBox(
                                  height: height,
                                  child: Column(
                                    mainAxisSize: MainAxisSize.max,
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Container(width: width, height: height * 0.25, color: Colors.black),
                                      Container(width: width, height: height * 0.22, color: Colors.black),
                                    ],
                                  ),
                                ),
                              );
                            },
                          )
                        : Center(
                            child: Padding(
                              padding: EdgeInsets.all(MySize(context).h * 0.02),
                              child: Text(
                                cameraPlaceholderText,
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                  ),
                  SizedBox(height: MySize(context).h * 0.02),
                ],
              ),
            )
          : Padding(
              padding: EdgeInsets.symmetric(vertical: MySize(context).h * 0.06, horizontal: MySize(context).w * 0.05),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: _showCamera
                        ? LayoutBuilder(
                            builder: (context, constraints) {
                              var controlBarHeight = constraints.maxHeight * 0.2;
                              var height = (constraints.maxWidth * 9 / 16) - controlBarHeight;
                              var width = height * 16 / 9;
                              return cameraWidget(
                                controlBarHeight: controlBarHeight,
                                height: height,
                                width: width,
                                exCamLimiter: SizedBox(
                                  width: width,
                                  child: Row(
                                    mainAxisSize: MainAxisSize.max,
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Container(width: width * 0.30, height: height, color: Colors.black),
                                      Container(width: width * 0.30, height: height, color: Colors.black),
                                    ],
                                  ),
                                ),
                                roseWreathWidthFactor: 0.75,
                                roseWreathTopPositionFactor: 0.01,
                                kissCamLimiter: SizedBox(
                                  width: width,
                                  child: Row(
                                    mainAxisSize: MainAxisSize.max,
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Container(width: width * 0.14, height: height, color: Colors.black),
                                      Container(width: width * 0.14, height: height, color: Colors.black),
                                    ],
                                  ),
                                ),
                              );
                            },
                          )
                        : Center(
                            child: Padding(
                              padding: EdgeInsets.all(MySize(context).h * 0.02),
                              child: Text(
                                cameraPlaceholderText,
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                  ),
                  SizedBox(height: MySize(context).w * 0.02),
                  Column(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      reloadAppButton(),
                      myDropDownButtonFormField(0.23, 0.03),
                      freezeSwitch(),
                      reloadDataButton(),
                    ],
                  ),
                ],
              ),
            ),
    );
  }
}
