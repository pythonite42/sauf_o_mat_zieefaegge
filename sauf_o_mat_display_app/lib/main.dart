import 'dart:async';
import 'package:flutter/material.dart';
import 'package:sauf_o_mat_display_app/theme.dart';
import 'package:sauf_o_mat_display_app/globals.dart';
import 'package:sauf_o_mat_display_app/page_diagram.dart';
import 'package:sauf_o_mat_display_app/page_livestream.dart';
import 'package:sauf_o_mat_display_app/page_prize.dart';
import 'package:sauf_o_mat_display_app/page_quote.dart';
import 'package:sauf_o_mat_display_app/page_schedule.dart';
import 'package:sauf_o_mat_display_app/page_top3.dart';
import 'package:sauf_o_mat_display_app/page_advertising.dart';
import 'package:window_manager/window_manager.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:sauf_o_mat_display_app/server_manager.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();

  WindowOptions windowOptions = WindowOptions(
    size: Size(1400, 900),
    backgroundColor: Colors.transparent,
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.normal,
  );
  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });
  await dotenv.load(fileName: ".env");

  if (dotenv.env['MODE'] == "testing") {
    customDurations = CustomDurationsTest();
  } else {
    customDurations = CustomDurationsProduction();
  }

  // Connect to WebSocket before running app
  final String? ipAddress = dotenv.env['SERVER_IP'];
  final String? port = dotenv.env['SERVER_PORT'];

  await ServerManager().connect("ws://$ipAddress:$port");

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sauf-O-Mat',
      theme: appTheme,
      debugShowCheckedModeBanner: false,
      home: MyScaffold(),
    );
  }
}

class MyScaffold extends StatefulWidget {
  const MyScaffold({super.key});

  @override
  State<MyScaffold> createState() => _MyScaffoldState();
}

class _MyScaffoldState extends State<MyScaffold> {
  bool titleBarVisible = true;
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

  int pageIndex = 0;
  bool animateNavigation = true;
  bool overridePageIndex = false;

  late final MessageHandler socketPageIndexListener;

  Timer? _pageIndexReloadTimer;
  Timer? _prePrizeTimer;
  Timer? _unfreezeTimer;
  final List<Timer> _disabledPagesTimers = [];
  bool _socketFrozen = false;

  /// ID of the phone whose camera is shown on the livestream page.
  String? _livestreamOwner;
  int _nextPrizeIndex = 0;

  @override
  void initState() {
    super.initState();

    socketPageIndexListener = (data) {
      debugPrint("socket event received: $data");
      if (data['event'] == 'freeze' && data["freeze"] == true) {
        //wenn 5 Minuten vor Preis, dann wird auf prize page gewechselt. wenn dann per app überschrieben wird ist der freeze automatisch drin bis eine minute nach preisZeit. Das wird in der App nicht angezeigt. Ist das okay so?
        _socketFrozen = true;
        _cancelAutoTimer();
        _broadcastState(reply: true);
      } else if (data['event'] == 'freeze' && data["freeze"] == false) {
        _socketFrozen = false;
        _maybeStartAutoTimer();
        _broadcastState(reply: true);
      }
      if (data['event'] == 'pageIndex' && data['index'] is int) {
        int newIndex = data['index'];
        bool navigated = false;
        if (newIndex != pageIndex || data['reset'] == true) {
          animateNavigation = !(data['reset'] == true);
          overridePageIndex = true;
          _navigateToPage(newIndex);
          navigated = true;
        }
        // The phone that (re)selected a livestream page owns the stream; all
        // other phones turn their camera off when they see this in the state.
        if (_isLivestreamPage(pageIndex) && pageIndex == newIndex) {
          final String? newOwner = data['owner'] is String ? data['owner'] : null;
          if (!navigated && newOwner != _livestreamOwner) {
            // Another phone takes over: rebuild the page so it gets a fresh
            // WebRTC connection that can accept the new phone's offer.
            animateNavigation = false;
            overridePageIndex = true;
            _navigateToPage(newIndex);
          }
          _livestreamOwner = newOwner;
        }
        // Always answer, so a phone whose request was rejected gets corrected.
        _broadcastState(reply: true);
      }
      if (data['event'] == 'requestState') {
        _broadcastState();
      }
    };

    ServerManager().addListener(socketPageIndexListener);
    ServerManager().connected.addListener(_onConnectionChanged);

    _startPageIndexTimer();
    _schedulePrizeGuard();
    _scheduleDisabledPagesBroadcast();
  }

  void _onConnectionChanged() {
    if (ServerManager().connected.value) _broadcastState();
  }

  /// Tells all phones which page is shown and whether the rotation is frozen.
  /// [reply] marks a direct answer to a phone's command (see control app).
  void _broadcastState({bool reply = false}) {
    ServerManager().send({
      "event": "state",
      "pageIndex": pageIndex,
      "frozen": _socketFrozen,
      "livestreamOwner": _livestreamOwner,
      "disabledPages": _disabledPages(),
      "reply": reply,
    });
  }

  /// Pages that can no longer be shown: prize page after the last prize time,
  /// schedule page after the last performance.
  List<int> _disabledPages() {
    final now = DateTime.now();
    return [
      if (now.isAfter(GlobalSettings.prizeTimes.last)) 2,
      if (now.isAfter(GlobalSettings.lastPerformance)) 3,
    ];
  }

  /// Broadcasts the state when a page becomes unavailable, so the phones
  /// disable it in their dropdown even while the rotation is frozen.
  void _scheduleDisabledPagesBroadcast() {
    final now = DateTime.now();
    for (final deadline in [
      GlobalSettings.prizeTimes.last,
      GlobalSettings.lastPerformance,
    ]) {
      if (deadline.isAfter(now)) {
        _disabledPagesTimers.add(
          Timer(
            deadline.difference(now) + const Duration(seconds: 1),
            _broadcastState,
          ),
        );
      }
    }
  }

  bool _isLivestreamPage(int index) => index == 6 || index == 7;

  void _navigateToPage(int index) {
    if (_disabledPages().contains(index)) return;

    setState(() {
      pageIndex = index;
    });
    if (!_isLivestreamPage(index)) _livestreamOwner = null;

    if (_navigatorKey.currentContext != null) {
      _navigatorKey.currentState!.pushReplacementNamed('/page$index');
    }
  }

  void _startPageIndexTimer() {
    _pageIndexReloadTimer?.cancel();
    _pageIndexReloadTimer = Timer.periodic(
      Duration(seconds: customDurations.indexNavigationChange),
      (_) {
        if (!overridePageIndex) {
          int nextIndex = (pageIndex + 1) % 6;
          if (nextIndex == 2 &&
              DateTime.now().isAfter(GlobalSettings.prizeTimes.last)) {
            nextIndex++;
          }
          if (nextIndex == 3 &&
              DateTime.now().isAfter(GlobalSettings.lastPerformance)) {
            nextIndex++;
          }
          animateNavigation = true;
          _navigateToPage(nextIndex);
          _broadcastState();
        } else {
          overridePageIndex = false;
        }
      },
    );
  }

  void _schedulePrizeGuard() {
    _prePrizeTimer?.cancel();
    _unfreezeTimer?.cancel();

    if (_nextPrizeIndex >= GlobalSettings.prizeTimes.length) {
      return;
    }

    final prizeTime = GlobalSettings.prizeTimes[_nextPrizeIndex];
    final preStart = prizeTime.subtract(
      Duration(seconds: customDurations.changeToPrizePageBeforePrizeTime),
    );
    final preEnd = prizeTime.add(
      Duration(seconds: customDurations.stayOnPrizePageAfterPrizeTime),
    );
    final now = DateTime.now();

    if (now.isBefore(preStart)) {
      final wait = preStart.difference(now);
      _prePrizeTimer = Timer(wait, _enterPrizeFreeze);
    } else if (!now.isAfter(preEnd)) {
      _enterPrizeFreeze();
      final remaining = preEnd.difference(now);
      _unfreezeTimer = Timer(remaining, _exitPrizeFreeze);
    } else {
      _nextPrizeIndex++;
      _schedulePrizeGuard();
    }
  }

  void _enterPrizeFreeze() {
    animateNavigation = true;
    _navigateToPage(2);
    _cancelAutoTimer();
    _broadcastState();

    _unfreezeTimer?.cancel();
    _unfreezeTimer = Timer(
      Duration(
        seconds:
            customDurations.changeToPrizePageBeforePrizeTime +
            customDurations.stayOnPrizePageAfterPrizeTime,
      ),
      _exitPrizeFreeze,
    );
  }

  void _exitPrizeFreeze() {
    // After the prize page the rotation always restarts: freeze commands sent
    // by phones before or during the prize time are discarded.
    _socketFrozen = false;
    _maybeStartAutoTimer();
    _broadcastState();
    _nextPrizeIndex++;
    _schedulePrizeGuard();
  }

  void _cancelAutoTimer() {
    _pageIndexReloadTimer?.cancel();
    _pageIndexReloadTimer = null;
  }

  void _maybeStartAutoTimer() {
    if (_socketFrozen) return;
    if (_pageIndexReloadTimer != null) return;
    _startPageIndexTimer();
  }

  @override
  void dispose() {
    ServerManager().removeListener(socketPageIndexListener);
    ServerManager().connected.removeListener(_onConnectionChanged);
    _pageIndexReloadTimer?.cancel();
    _prePrizeTimer?.cancel();
    _unfreezeTimer?.cancel();
    for (final timer in _disabledPagesTimers) {
      timer.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: Container(
              color: billboardBackgroundColor,
              child: Navigator(
                key: _navigatorKey,
                initialRoute: '/page0',
                onGenerateRoute: (settings) {
                  switch (settings.name) {
                    case '/page0':
                      return _createRoute(PageDiagram());
                    case '/page1':
                      return _createRoute(PageTop3());
                    case '/page2':
                      return _createRoute(PagePrize());
                    case '/page3':
                      return _createRoute(PageSchedule());
                    case '/page4':
                      return _createRoute(PageQuote());
                    case '/page5':
                      return _createRoute(PageAdvertising());
                    case '/page6':
                      return _createRoute(PageLivestream(isKiss: false));
                    case '/page7':
                      return _createRoute(PageLivestream(isKiss: true));
                    default:
                      return MaterialPageRoute(
                        builder: (_) =>
                            const Center(child: Text('Unknown Page')),
                      );
                  }
                },
              ),
            ),
          ),
          Positioned(
            top: 5,
            right: 5,
            child: IconButton(
              onPressed: () async {
                if (titleBarVisible) {
                  windowManager.setTitleBarStyle(TitleBarStyle.hidden);
                  setState(() => titleBarVisible = false);
                  await windowManager.setFullScreen(true);
                } else {
                  windowManager.setTitleBarStyle(TitleBarStyle.normal);
                  setState(() => titleBarVisible = true);
                  await windowManager.setFullScreen(false);
                }
              },
              icon: Icon(
                titleBarVisible ? Icons.open_in_full : Icons.close_fullscreen,
                color: titleBarVisible
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.secondary,
                size: GlobalSettings.fullscreenIconSize,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Route _createRoute(Widget page) {
    if (animateNavigation) {
      return PageRouteBuilder(
        transitionDuration: Duration(
          milliseconds: customDurations.navigationTransition,
        ),
        pageBuilder: (_, animation, secondaryAnimation) =>
            backgroundContainer(child: page),
        transitionsBuilder: (_, animation, secondaryAnimation, child) {
          const curve = Curves.ease;

          // New page slides in from right → center
          final inTween = Tween<Offset>(
            begin: const Offset(1.0, 0.0),
            end: Offset.zero,
          ).chain(CurveTween(curve: curve));

          // Old page slides from center → left
          final outTween = Tween<Offset>(
            begin: Offset.zero,
            end: const Offset(-1.0, 0.0),
          ).chain(CurveTween(curve: curve));

          return SlideTransition(
            position: animation.drive(inTween),
            child: SlideTransition(
              position: secondaryAnimation.drive(outTween),
              child: child,
            ),
          );
        },
      );
    }

    return PageRouteBuilder(
      pageBuilder: (_, _, _) => backgroundContainer(child: page),
    );
  }

  Widget backgroundContainer({Widget? child}) {
    return Container(
      decoration: const BoxDecoration(
        image: DecorationImage(
          image: AssetImage("assets/billboard.png"),
          fit: BoxFit.cover,
        ),
      ),
      child: child,
    );
  }
}
