import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform, HttpHeaders, HttpClient;
import 'dart:math' as math;

import 'package:appsflyer_sdk/appsflyer_sdk.dart' as af_core;
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MethodChannel, SystemChrome, SystemUiOverlayStyle;
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' as r;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:logger/logger.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz_zone;

import 'luckpufi.dart';

// ============================================================================
// Константы
// ============================================================================
const String kChestKeyLoadedOnce = "loaded_event_sent_once";
const String kShipStatEndpoint = "https://get.getluckyapp.club/stat";
const String kChestKeyCachedParrot = "cached_fcm_token";

// ============================================================================
// Синглтоны/Логгер/Сеть
// ============================================================================
class CasinoSingletons {
  static final CasinoSingletons _inst = CasinoSingletons._();
  CasinoSingletons._();

  factory CasinoSingletons() => _inst;

  final FlutterSecureStorage vault = const FlutterSecureStorage();
  final CasinoLogger pitBoss = CasinoLogger();
  final Connectivity networkEye = Connectivity();
}

class CasinoLogger {
  final Logger _lg = Logger();
  void i(Object msg) => _lg.i(msg);
  void w(Object msg) => _lg.w(msg);
  void e(Object msg) => _lg.e(msg);
}

class CasinoNet {
  final CasinoSingletons _sx = CasinoSingletons();

  Future<bool> isOnline() async {
    final c = await _sx.networkEye.checkConnectivity();
    return c != ConnectivityResult.none;
  }

  Future<void> postJson(String url, Map<String, dynamic> payload) async {
    try {
      await http.post(
        Uri.parse(url),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(payload),
      );
    } catch (e) {
      _sx.pitBoss.e("postJson error: $e");
    }
  }
}

// ============================================================================
// Досье устройства — PlayerCard
// ============================================================================
class PlayerCard {
  String? deviceId;
  String? sessionId = "mafia-one-off";
  String? platform;
  String? osVersion;
  String? appVersion;
  String? language;
  String? timezone;
  bool pushEnabled = true;

  Future<void> collect() async {
    final info = DeviceInfoPlugin();
    if (Platform.isAndroid) {
      final a = await info.androidInfo;
      deviceId = a.id;
      platform = "android";
      osVersion = a.version.release;
    } else if (Platform.isIOS) {
      final i = await info.iosInfo;
      deviceId = i.identifierForVendor;
      platform = "ios";
      osVersion = i.systemVersion;
    }
    final pkg = await PackageInfo.fromPlatform();
    appVersion = pkg.version;
    language = Platform.localeName.split('_')[0];
    timezone = tz_zone.local.name;
    sessionId = "voyage-${DateTime.now().millisecondsSinceEpoch}";
  }

  Map<String, dynamic> toMap({String? fcmToken}) => {
    "fcm_token": fcmToken ?? 'missing_token',
    "device_id": deviceId ?? 'missing_id',
    "app_name": "luckywaveincasino",
    "instance_id": sessionId ?? 'missing_session',
    "platform": platform ?? 'missing_system',
    "os_version": osVersion ?? 'missing_build',
    "app_version": appVersion ?? 'missing_app',
    "language": language ?? 'en',
    "timezone": timezone ?? 'UTC',
    "push_enabled": pushEnabled,
  };
}

// ============================================================================
// AppsFlyer — CasinoAffiliate
// ============================================================================
class CasinoAffiliate with ChangeNotifier {
  af_core.AppsFlyerOptions? _opts;
  af_core.AppsflyerSdk? _sdk;

  String affiliateUID = "";
  String affiliateData = "";

  void init(VoidCallback onNudge) {
    final cfg = af_core.AppsFlyerOptions(
      afDevKey: "qsBLmy7dAXDQhowM8V3ca4",
      appId: "6754248088",
      showDebug: true,
      timeToWaitForATTUserAuthorization: 0,
    );
    _opts = cfg;
    _sdk = af_core.AppsflyerSdk(cfg);

    _sdk?.initSdk(
      registerConversionDataCallback: true,
      registerOnAppOpenAttributionCallback: true,
      registerOnDeepLinkingCallback: true,
    );
    _sdk?.startSDK(
      onSuccess: () => CasinoSingletons().pitBoss.i("Consigliere hoisted"),
      onError: (int c, String m) => CasinoSingletons().pitBoss.e("Consigliere storm $c: $m"),
    );
    _sdk?.onInstallConversionData((loot) {
      affiliateData = loot.toString();
      onNudge();
      notifyListeners();
    });
    _sdk?.getAppsFlyerUID().then((v) {
      affiliateUID = v.toString();
      onNudge();
      notifyListeners();
    });
  }
}

// ============================================================================
// Riverpod/Provider
// ============================================================================
final quartermasterProvider = r.FutureProvider<PlayerCard>((ref) async {
  final pc = PlayerCard();
  await pc.collect();
  return pc;
});

final consigliereProvider = p.ChangeNotifierProvider<CasinoAffiliate>(
  create: (_) => CasinoAffiliate(),
);

// ============================================================================
// Новый неоновый лоадер LuckyWaveNeonLoader
// ============================================================================
class LuckyWaveNeonLoader extends StatefulWidget {
  const LuckyWaveNeonLoader({Key? key}) : super(key: key);

  @override
  State<LuckyWaveNeonLoader> createState() => _LuckyWaveNeonLoaderState();
}

class _LuckyWaveNeonLoaderState extends State<LuckyWaveNeonLoader>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _pulse;
  final List<_FallingDie> _dice = [];
  late Timer _diceTimer;
  final math.Random _rnd = math.Random();

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);
    _pulse = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);

    for (int i = 0; i < 14; i++) {
      _dice.add(_randomDie(startAbove: true));
    }
    _diceTimer = Timer.periodic(const Duration(milliseconds: 16), (_) {
      setState(() {
        for (final d in _dice) {
          d.update();
        }
      });
    });
  }

  _FallingDie _randomDie({bool startAbove = false}) {
    final w = WidgetsBinding.instance.platformDispatcher.views.isNotEmpty
        ? WidgetsBinding.instance.platformDispatcher.views.first.physicalSize /
        WidgetsBinding.instance.platformDispatcher.views.first.devicePixelRatio
        : const Size(360, 640);
    final width = w.width;
    final height = w.height;

    final x = _rnd.nextDouble() * width;
    final y = startAbove ? -(_rnd.nextDouble() * height * 0.6 + 20) : _rnd.nextDouble() * height;
    final size = 14.0 + _rnd.nextDouble() * 18.0;
    final vy = 1.4 + _rnd.nextDouble() * 2.6;
    final rot = _rnd.nextDouble() * math.pi;
    final vr = (_rnd.nextDouble() - 0.5) * 0.06;
    final swayAmp = 10 + _rnd.nextDouble() * 30;
    final swayFreq = 0.004 + _rnd.nextDouble() * 0.006;

    return _FallingDie(
      x: x,
      y: y,
      size: size,
      vy: vy,
      rot: rot,
      vr: vr,
      swayAmp: swayAmp,
      swayFreq: swayFreq,
      reset: () {
        final nx = _rnd.nextDouble() * width;
        final nsize = 14.0 + _rnd.nextDouble() * 18.0;
        final nvy = 1.4 + _rnd.nextDouble() * 2.6;
        final nvrot = (_rnd.nextDouble() - 0.5) * 0.06;
        final nrot = _rnd.nextDouble() * math.pi;
        final namp = 10 + _rnd.nextDouble() * 30;
        final nfreq = 0.004 + _rnd.nextDouble() * 0.006;
        return _DieReset(
          x: nx,
          y: -nsize - _rnd.nextDouble() * height * 0.3,
          size: nsize,
          vy: nvy,
          rot: nrot,
          vr: nvrot,
          swayAmp: namp,
          swayFreq: nfreq,
        );
      },
    )..screenHeight = height;
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _diceTimer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final neonGreen = const Color(0xFF00FF88);
    final neonWhite = Colors.white;

    return Container(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          RepaintBoundary(
            child: CustomPaint(
              painter: _DiceRainPainter(dice: _dice),
              isComplex: true,
              willChange: true,
            ),
          ),
          Center(
            child: AnimatedBuilder(
              animation: _pulse,
              builder: (context, _) {
                final t = _pulse.value;
                final color = Color.lerp(neonWhite, neonGreen, t)!;
                final blur = 18.0 + t * 28.0;

                return Stack(
                  alignment: Alignment.center,
                  children: [
                    Text(
                      "Lucky Wave",
                      style: TextStyle(
                        fontSize: 42,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                        color: color.withOpacity(0.0),
                        shadows: [
                          Shadow(color: color.withOpacity(0.18), blurRadius: blur, offset: const Offset(0, 0)),
                          Shadow(color: color.withOpacity(0.22), blurRadius: blur * 0.7, offset: const Offset(0, 0)),
                          Shadow(color: color.withOpacity(0.25), blurRadius: blur * 0.45, offset: const Offset(0, 0)),
                        ],
                      ),
                    ),
                    Text(
                      "Lucky Wave",
                      style: TextStyle(
                        fontSize: 42,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                        color: color,
                        shadows: [
                          Shadow(color: color.withOpacity(0.35), blurRadius: blur * 0.35, offset: const Offset(0, 0)),
                          Shadow(color: color.withOpacity(0.25), blurRadius: blur * 0.18, offset: const Offset(0, 0)),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _DiceRainPainter extends CustomPainter {
  final List<_FallingDie> dice;
  _DiceRainPainter({required this.dice});

  @override
  void paint(Canvas canvas, Size size) {
    final bgGlowPaint = Paint()
      ..style = PaintingStyle.fill
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);

    for (final d in dice) {
      final x = d.x + d.swayAmp * math.sin(d.time * d.swayFreq);
      final y = d.y;
      final s = d.size;
      final r = d.rot;

      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(r);

      bgGlowPaint.color = Colors.white.withOpacity(0.05);
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromCenter(center: Offset.zero, width: s, height: s), const Radius.circular(4)),
        bgGlowPaint,
      );

      final rect = Rect.fromCenter(center: Offset.zero, width: s, height: s);
      final bodyPaint = Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFAFAFA), Color(0xFFE8E8E8)],
        ).createShader(rect);
      final stroke = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = Colors.white.withOpacity(0.9);

      canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(5)), bodyPaint);
      canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(5)), stroke);

      final highlight = Paint()
        ..shader = RadialGradient(
          colors: [Colors.white.withOpacity(0.28), Colors.transparent],
        ).createShader(Rect.fromCircle(center: Offset(-s * 0.2, -s * 0.2), radius: s * 0.8));
      canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(5)), highlight);

      final pipsPaint = Paint()..color = Colors.black.withOpacity(0.85);
      final face = d.faceIndex;
      final pip = (Offset o) => canvas.drawCircle(o, s * 0.095, pipsPaint);

      final off = s * 0.28;
      final p = <Offset>[
        Offset(-off, -off), Offset(0, -off), Offset(off, -off),
        Offset(-off, 0), Offset(0, 0), Offset(off, 0),
        Offset(-off, off), Offset(0, off), Offset(off, off),
      ];

      void drawFace(int n) {
        switch (n) {
          case 1: pip(p[4]); break;
          case 2: pip(p[0]); pip(p[8]); break;
          case 3: pip(p[0]); pip(p[4]); pip(p[8]); break;
          case 4: pip(p[0]); pip(p[2]); pip(p[6]); pip(p[8]); break;
          case 5: pip(p[0]); pip(p[2]); pip(p[4]); pip(p[6]); pip(p[8]); break;
          case 6: pip(p[0]); pip(p[2]); pip(p[3]); pip(p[5]); pip(p[6]); pip(p[8]); break;
          default: pip(p[4]);
        }
      }

      drawFace(face);
      canvas.restore();

      d.screenHeight = size.height;
      d.screenWidth = size.width;
    }
  }

  @override
  bool shouldRepaint(covariant _DiceRainPainter oldDelegate) => true;
}

class _FallingDie {
  double x;
  double y;
  double size;
  double vy;
  double rot;
  double vr;
  double swayAmp;
  double swayFreq;
  int faceIndex;
  double time = 0.0;
  double screenHeight = 800;
  double screenWidth = 360;
  final _DieReset Function() reset;

  _FallingDie({
    required this.x,
    required this.y,
    required this.size,
    required this.vy,
    required this.rot,
    required this.vr,
    required this.swayAmp,
    required this.swayFreq,
    required this.reset,
  }) : faceIndex = (math.Random().nextInt(6) + 1);

  void update() {
    time += 16;
    y += vy;
    rot += vr;

    if (y - size > screenHeight + 20) {
      final r = reset();
      x = r.x;
      y = r.y;
      size = r.size;
      vy = r.vy;
      rot = r.rot;
      vr = r.vr;
      swayAmp = r.swayAmp;
      swayFreq = r.swayFreq;
      faceIndex = (math.Random().nextInt(6) + 1);
      time = 0.0;
    }
  }
}

class _DieReset {
  final double x, y, size, vy, rot, vr, swayAmp, swayFreq;
  _DieReset({
    required this.x,
    required this.y,
    required this.size,
    required this.vy,
    required this.rot,
    required this.vr,
    required this.swayAmp,
    required this.swayFreq,
  });
}

// ============================================================================
// Push фон — casinoBgPush
// ============================================================================
@pragma('vm:entry-point')
Future<void> casinoBgPush(RemoteMessage msg) async {
  CasinoSingletons().pitBoss.i("bg-parrot: ${msg.messageId}");
  CasinoSingletons().pitBoss.i("bg-cargo: ${msg.data}");
}

// ============================================================================
// CasinoPushBridge — токен ТОЛЬКО из MethodChannel
// ============================================================================
class CasinoPushBridge extends ChangeNotifier {
  final CasinoSingletons _sx = CasinoSingletons();
  String? _token;
  final List<void Function(String)> _waiters = [];

  String? get token => _token;

  CasinoPushBridge() {
    const MethodChannel('com.example.fcm/token').setMethodCallHandler((call) async {
      if (call.method == 'setToken') {
        final String s = call.arguments as String;
        if (s.isNotEmpty) {
          _applyToken(s);
        }
      }
    });
    _restoreToken();
  }

  Future<void> _restoreToken() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final cached = sp.getString(kChestKeyCachedParrot);
      if (cached != null && cached.isNotEmpty) {
        _applyToken(cached, notifyNative: false);
      } else {
        final ss = await _sx.vault.read(key: kChestKeyCachedParrot);
        if (ss != null && ss.isNotEmpty) {
          _applyToken(ss, notifyNative: false);
        }
      }
    } catch (_) {}
  }

  void _applyToken(String t, {bool notifyNative = true}) async {
    _token = t;
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(kChestKeyCachedParrot, t);
      await _sx.vault.write(key: kChestKeyCachedParrot, value: t);
    } catch (_) {}
    for (final cb in List.of(_waiters)) {
      try {
        cb(t);
      } catch (e) {
        _sx.pitBoss.w("parrot-waiter error: $e");
      }
    }
    _waiters.clear();
    notifyListeners();
  }

  Future<void> awaitToken(Function(String t) onToken) async {
    try {
      await FirebaseMessaging.instance.requestPermission(alert: true, badge: true, sound: true);
      if (_token != null && _token!.isNotEmpty) {
        onToken(_token!);
        return;
      }
      _waiters.add(onToken);
    } catch (e) {
      _sx.pitBoss.e("CasinoPushBridge awaitToken: $e");
    }
  }
}

// ============================================================================
// Splash — ждём токен из Bridge и идём дальше
// ============================================================================
class CasinoSplash extends StatefulWidget {
  const CasinoSplash({Key? key}) : super(key: key);

  @override
  State<CasinoSplash> createState() => _CasinoSplashState();
}

class _CasinoSplashState extends State<CasinoSplash> {
  final CasinoPushBridge _pushBridge = CasinoPushBridge();
  bool _fired = false;
  Timer? _timeout;

  @override
  void initState() {
    super.initState();

    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.black,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
    ));

    _pushBridge.awaitToken((sig) => _go(sig));
    _timeout = Timer(const Duration(seconds: 8), () => _go(''));
  }

  void _go(String sig) {
    if (_fired) return;
    _fired = true;
    _timeout?.cancel();
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => CasinoLobby(signal: sig)),
    );
  }

  @override
  void dispose() {
    _timeout?.cancel();
    _pushBridge.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Colors.black,
      body: Center(child: LuckyWaveNeonLoader()),
    );
  }
}

// ============================================================================
// MVVM (CasinoViewModel + CasinoCourier)
// ============================================================================
class CasinoViewModel with ChangeNotifier {
  final PlayerCard player;
  final CasinoAffiliate affiliate;

  CasinoViewModel({required this.player, required this.affiliate});

  Map<String, dynamic> devicePayload(String? token) => player.toMap(fcmToken: token);

  Map<String, dynamic> afPayload(String? token) => {
    "content": {
      "af_data": affiliate.affiliateData,
      "af_id": affiliate.affiliateUID,
      "fb_app_name": "luckywaveincasino",
      "app_name": "luckywaveincasino",
      "deep": null,
      "bundle_identifier": "com.giflaog.luckwave.luckwaveincasino",
      "app_version": "1.0.0",
      "apple_id": "6754248088",
      "fcm_token": token ?? "no_token",
      "device_id": player.deviceId ?? "no_device",
      "instance_id": player.sessionId ?? "no_instance",
      "platform": player.platform ?? "no_type",
      "os_version": player.osVersion ?? "no_os",
      "app_version": player.appVersion ?? "no_app",
      "language": player.language ?? "en",
      "timezone": player.timezone ?? "UTC",
      "push_enabled": player.pushEnabled,
      "useruid": affiliate.affiliateUID,
    },
  };
}

class CasinoCourier {
  final CasinoViewModel model;
  final InAppWebViewController Function() getWeb;

  CasinoCourier({required this.model, required this.getWeb});

  Future<void> putDeviceToLocalStorage(String? token) async {
    final m = model.devicePayload(token);
    await getWeb().evaluateJavascript(source: '''
localStorage.setItem('app_data', JSON.stringify(${jsonEncode(m)}));
''');
  }

  Future<void> sendRawToWeb(String? token) async {
    final payload = model.afPayload(token);
    final jsonString = jsonEncode(payload);
    CasinoSingletons().pitBoss.i("SendRawData: $jsonString");
    await getWeb().evaluateJavascript(source: "sendRawData(${jsonEncode(jsonString)});");
  }
}

// ============================================================================
// Переходы/статистика
// ============================================================================
Future<String> resolveFinalUrl(String startUrl, {int maxHops = 10}) async {
  final client = HttpClient();
  client.userAgent = 'Mozilla/5.0 (Flutter; dart:io HttpClient)';
  try {
    var current = Uri.parse(startUrl);
    for (int i = 0; i < maxHops; i++) {
      final req = await client.getUrl(current);
      req.followRedirects = false;
      final res = await req.close();
      if (res.isRedirect) {
        final loc = res.headers.value(HttpHeaders.locationHeader);
        if (loc == null || loc.isEmpty) break;
        final next = Uri.parse(loc);
        current = next.hasScheme ? next : current.resolveUri(next);
        continue;
      }
      return current.toString();
    }
    return current.toString();
  } catch (e) {
    debugPrint("chartFinalUrl error: $e");
    return startUrl;
  } finally {
    client.close(force: true);
  }
}

Future<void> postCasinoStat({
  required String event,
  required int timeStart,
  required String url,
  required int timeFinish,
  required String appSid,
  int? firstPageLoadTs,
}) async {
  try {
    final finalUrl = await resolveFinalUrl(url);
    final payload = {
      "event": event,
      "timestart": timeStart,
      "timefinsh": timeFinish,
      "url": finalUrl,
      "appleID": "6754248088",
      "open_count": "$appSid/$timeStart",
    };

    debugPrint("loadingstatinsic $payload");
    final res = await http.post(
      Uri.parse("$kShipStatEndpoint/$appSid"),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode(payload),
    );
    debugPrint(" ur _loaded$kShipStatEndpoint/$appSid");
    debugPrint("_postStat status=${res.statusCode} body=${res.body}");
  } catch (e) {
    debugPrint("_postStat error: $e");
  }
}

// ============================================================================
// Главный WebView — CasinoLobby
// ============================================================================
class CasinoLobby extends StatefulWidget {
  final String? signal; // сюда приходит FCM токен из Bridge (или пустая строка)
  const CasinoLobby({super.key, required this.signal});

  @override
  State<CasinoLobby> createState() => _CasinoLobbyState();
}

class _CasinoLobbyState extends State<CasinoLobby> with WidgetsBindingObserver {
  late InAppWebViewController _web;
  bool _busy = false;
  final String _homeUrl = "https://get.getluckyapp.club/";
  final PlayerCard _player = PlayerCard();
  final CasinoAffiliate _affiliate = CasinoAffiliate();

  int _reloadKey = 0;
  DateTime? _pausedAt;
  bool _veil = false;
  double _progressRel = 0.0;
  late Timer _progressTimer;
  final int _warmupSecs = 6;
  bool _cover = true;

  bool _loadedEventSentOnce = false;
  int? _firstPageStamp;

  CasinoCourier? _courier;
  CasinoViewModel? _vm;

  String _currentUrl = "";
  var _startLoadTs = 0;

  // Флаги против повторных отправок
  bool _devicePushedOnce = false;
  bool _afPushedOnce = false;

  bool _notificationChannelBound = false;

  final Set<String> _customSchemes = {
    'tg', 'telegram',
    'whatsapp',
    'viber',
    'skype',
    'fb-messenger',
    'sgnl',
    'tel',
    'mailto',
    'bnl',
  };

  final Set<String> _externalHosts = {
    't.me', 'telegram.me', 'telegram.dog',
    'wa.me', 'api.whatsapp.com', 'chat.whatsapp.com',
    'm.me',
    'signal.me',
    'bnl.com', 'www.bnl.com',
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _firstPageStamp = DateTime.now().millisecondsSinceEpoch;

    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _cover = false);
    });

    Future.delayed(const Duration(seconds: 7), () {
      if (!mounted) return;
      setState(() => _veil = true);
    });

    _boot();
  }

  Future<void> _loadOnceFlag() async {
    final sp = await SharedPreferences.getInstance();
    _loadedEventSentOnce = sp.getBool(kChestKeyLoadedOnce) ?? false;
  }

  Future<void> _saveOnceFlag() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setBool(kChestKeyLoadedOnce, true);
    _loadedEventSentOnce = true;
  }

  Future<void> sendLoadedOnce({required String url, required int timestart}) async {
    if (_loadedEventSentOnce) {
      debugPrint("Loaded already sent, skipping");
      return;
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    await postCasinoStat(
      event: "Loaded",
      timeStart: timestart,
      timeFinish: now,
      url: url,
      appSid: _affiliate.affiliateUID,
      firstPageLoadTs: _firstPageStamp,
    );
    await _saveOnceFlag();
  }

  void _boot() {
    _startWarmProgress();
    _wirePush();
    _affiliate.init(() => setState(() {}));
    _bindNotificationChannel();
    _preparePlayer();

    // ВАЖНО: не отправляем тут никаких данных, только после первой успешной загрузки (onLoadStop) с флагами
  }

  void _wirePush() {
    FirebaseMessaging.onMessage.listen((msg) {
      final link = msg.data['uri'];
      if (link != null) {
        _navigate(link.toString());
      } else {
        _resetToHome();
      }
    });
    FirebaseMessaging.onMessageOpenedApp.listen((msg) {
      final link = msg.data['uri'];
      if (link != null) {
        _navigate(link.toString());
      } else {
        _resetToHome();
      }
    });
  }

  void _bindNotificationChannel() {
    if (_notificationChannelBound) return;
    _notificationChannelBound = true;

    MethodChannel('com.example.fcm/notification').setMethodCallHandler((call) async {
      if (call.method == "onNotificationTap") {
        final Map<String, dynamic> payload = Map<String, dynamic>.from(call.arguments);
        if (payload["uri"] != null && !payload["uri"].toString().contains("Нет URI")) {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (context) => CasinoTable(payload["uri"].toString())),
                (route) => false,
          );
        }
      }
    });
  }

  Future<void> _preparePlayer() async {
    try {
      await _player.collect();
      await _askPushPerms(); // только права, токен не берём
      _vm ??= CasinoViewModel(player: _player, affiliate: _affiliate);
      _courier ??= CasinoCourier(model: _vm!, getWeb: () => _web);
      await _loadOnceFlag();
    } catch (e) {
      CasinoSingletons().pitBoss.e("prepare-player fail: $e");
    }
  }

  Future<void> _askPushPerms() async {
    await FirebaseMessaging.instance.requestPermission(alert: true, badge: true, sound: true);
  }

  void _navigate(String link) async {
    await _web.loadUrl(urlRequest: URLRequest(url: WebUri(link)));
  }

  void _resetToHome() async {
    Future.delayed(const Duration(seconds: 3), () {
      _web.loadUrl(urlRequest: URLRequest(url: WebUri(_homeUrl)));
    });
  }

  Future<void> _pushDeviceDataOnce() async {
    if (_devicePushedOnce) return;
    _devicePushedOnce = true;
    CasinoSingletons().pitBoss.i("TOKEN ship ${widget.signal}");
    try {
      await _courier?.putDeviceToLocalStorage(widget.signal);
    } catch (e) {
      CasinoSingletons().pitBoss.w("putDeviceToLocalStorage failed: $e");
    }
  }

  Future<void> _pushAffiliateDataOnce() async {
    if (_afPushedOnce) return;
    _afPushedOnce = true;
    try {
      await _courier?.sendRawToWeb(widget.signal);
    } catch (e) {
      CasinoSingletons().pitBoss.w("sendRawToWeb failed: $e");
    }
  }

  void _startWarmProgress() {
    int n = 0;
    _progressRel = 0.0;
    _progressTimer = Timer.periodic(const Duration(milliseconds: 100), (t) {
      if (!mounted) return;
      setState(() {
        n++;
        _progressRel = n / (_warmupSecs * 10);
        if (_progressRel >= 1.0) {
          _progressRel = 1.0;
          _progressTimer.cancel();
        }
      });
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _pausedAt = DateTime.now();
    }
    if (state == AppLifecycleState.resumed) {
      if (Platform.isIOS && _pausedAt != null) {
        final now = DateTime.now();
        final drift = now.difference(_pausedAt!);
        if (drift > const Duration(minutes: 25)) {
          _hardReload();
        }
      }
      _pausedAt = null;
    }
  }

  void _hardReload() {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => CasinoLobby(signal: widget.signal)),
            (route) => false,
      );
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _progressTimer.cancel();
    super.dispose();
  }

  // ================== URL helpers ==================
  bool _isBareEmail(Uri u) {
    final s = u.scheme;
    if (s.isNotEmpty) return false;
    final raw = u.toString();
    return raw.contains('@') && !raw.contains(' ');
  }

  Uri _toMailto(Uri u) {
    final full = u.toString();
    final parts = full.split('?');
    final email = parts.first;
    final qp = parts.length > 1 ? Uri.splitQueryString(parts[1]) : <String, String>{};
    return Uri(scheme: 'mailto', path: email, queryParameters: qp.isEmpty ? null : qp);
  }

  bool _isPlatformish(Uri u) {
    final s = u.scheme.toLowerCase();
    if (_customSchemes.contains(s)) return true;

    if (s == 'http' || s == 'https') {
      final h = u.host.toLowerCase();
      if (_externalHosts.contains(h)) return true;
      if (h.endsWith('t.me')) return true;
      if (h.endsWith('wa.me')) return true;
      if (h.endsWith('m.me')) return true;
      if (h.endsWith('signal.me')) return true;
    }
    return false;
  }

  Uri _normalizeToHttp(Uri u) {
    final s = u.scheme.toLowerCase();

    if (s == 'tg' || s == 'telegram') {
      final qp = u.queryParameters;
      final domain = qp['domain'];
      if (domain != null && domain.isNotEmpty) {
        return Uri.https('t.me', '/$domain', {if (qp['start'] != null) 'start': qp['start']!});
      }
      final path = u.path.isNotEmpty ? u.path : '';
      return Uri.https('t.me', '/$path', u.queryParameters.isEmpty ? null : u.queryParameters);
    }

    if ((s == 'http' || s == 'https') && u.host.toLowerCase().endsWith('t.me')) {
      return u;
    }

    if (s == 'viber') return u;

    if (s == 'whatsapp') {
      final qp = u.queryParameters;
      final phone = qp['phone'];
      final text = qp['text'];
      if (phone != null && phone.isNotEmpty) {
        return Uri.https('wa.me', '/${_digitsOnly(phone)}', {if (text != null && text.isNotEmpty) 'text': text});
      }
      return Uri.https('wa.me', '/', {if (text != null && text.isNotEmpty) 'text': text});
    }

    if ((s == 'http' || s == 'https') &&
        (u.host.toLowerCase().endsWith('wa.me') || u.host.toLowerCase().endsWith('whatsapp.com'))) {
      return u;
    }

    if (s == 'skype') return u;

    if (s == 'fb-messenger') {
      final path = u.pathSegments.isNotEmpty ? u.pathSegments.join('/') : '';
      final qp = u.queryParameters;
      final id = qp['id'] ?? qp['user'] ?? path;
      if (id.isNotEmpty) {
        return Uri.https('m.me', '/$id', u.queryParameters.isEmpty ? null : u.queryParameters);
      }
      return Uri.https('m.me', '/', u.queryParameters.isEmpty ? null : u.queryParameters);
    }

    if (s == 'sgnl') {
      final qp = u.queryParameters;
      final ph = qp['phone'];
      final un = u.queryParameters['username'];
      if (ph != null && ph.isNotEmpty) return Uri.https('signal.me', '/#p/${_digitsOnly(ph)}');
      if (un != null && un.isNotEmpty) return Uri.https('signal.me', '/#u/$un');
      final path = u.pathSegments.join('/');
      if (path.isNotEmpty) return Uri.https('signal.me', '/$path', u.queryParameters.isEmpty ? null : u.queryParameters);
      return u;
    }

    if (s == 'tel') {
      return Uri.parse('tel:${_digitsOnly(u.path)}');
    }

    if (s == 'mailto') return u;

    if (s == 'bnl') {
      final newPath = u.path.isNotEmpty ? u.path : '';
      return Uri.https('bnl.com', '/$newPath', u.queryParameters.isEmpty ? null : u.queryParameters);
    }

    return u;
  }

  Future<bool> _openMailInWeb(Uri mailto) async {
    final u = _gmailLike(mailto);
    return await _openInBrowser(u);
  }

  Uri _gmailLike(Uri m) {
    final qp = m.queryParameters;
    final params = <String, String>{
      'view': 'cm',
      'fs': '1',
      if (m.path.isNotEmpty) 'to': m.path,
      if ((qp['subject'] ?? '').isNotEmpty) 'su': qp['subject']!,
      if ((qp['body'] ?? '').isNotEmpty) 'body': qp['body']!,
      if ((qp['cc'] ?? '').isNotEmpty) 'cc': qp['cc']!,
      if ((qp['bcc'] ?? '').isNotEmpty) 'bcc': qp['bcc']!,
    };
    return Uri.https('mail.google.com', '/mail/', params);
  }

  Future<bool> _openInBrowser(Uri u) async {
    try {
      if (await launchUrl(u, mode: LaunchMode.inAppBrowserView)) return true;
      return await launchUrl(u, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('openInAppBrowser error: $e; url=$u');
      try {
        return await launchUrl(u, mode: LaunchMode.externalApplication);
      } catch (_) {
        return false;
      }
    }
  }

  String _digitsOnly(String s) => s.replaceAll(RegExp(r'[^0-9+]'), '');

  @override
  Widget build(BuildContext context) {
    _bindNotificationChannel(); // защита от повторной привязки уже есть

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            if (_cover)
              const LuckyWaveNeonLoader()
            else
              Container(
                color: Colors.black,
                child: Stack(
                  children: [
                    InAppWebView(
                      key: ValueKey(_reloadKey),
                      initialSettings: InAppWebViewSettings(
                        javaScriptEnabled: true,
                        disableDefaultErrorPage: true,
                        mediaPlaybackRequiresUserGesture: false,
                        allowsInlineMediaPlayback: true,
                        allowsPictureInPictureMediaPlayback: true,
                        useOnDownloadStart: true,
                        javaScriptCanOpenWindowsAutomatically: true,
                        useShouldOverrideUrlLoading: true,
                        supportMultipleWindows: true,
                        transparentBackground: true,
                      ),
                      initialUrlRequest: URLRequest(url: WebUri(_homeUrl)),
                      onWebViewCreated: (c) {
                        _web = c;

                        _vm ??= CasinoViewModel(player: _player, affiliate: _affiliate);
                        _courier ??= CasinoCourier(model: _vm!, getWeb: () => _web);

                        _web.addJavaScriptHandler(
                          handlerName: 'onServerResponse',
                          callback: (args) {
                            try {
                              final saved = args.isNotEmpty &&
                                  args[0] is Map &&
                                  args[0]['savedata'].toString() == "false";
                              if (saved) {
                                Navigator.pushAndRemoveUntil(
                                  context,
                                  MaterialPageRoute(builder: (context) => const CasinoHelpLite()),
                                      (route) => false,
                                );
                              }
                            } catch (_) {}
                            if (args.isEmpty) return null;
                            try {
                              return args.reduce((curr, next) => curr + next);
                            } catch (_) {
                              return args.first;
                            }
                          },
                        );
                      },
                      onLoadStart: (c, u) async {
                        setState(() {
                          _startLoadTs = DateTime.now().millisecondsSinceEpoch;
                          _busy = true;
                        });
                        final v = u;
                        if (v != null) {
                          if (_isBareEmail(v)) {
                            try { await c.stopLoading(); } catch (_) {}
                            final mailto = _toMailto(v);
                            await _openMailInWeb(mailto);
                            return;
                          }
                          final sch = v.scheme.toLowerCase();
                          if (sch != 'http' && sch != 'https') {
                            try { await c.stopLoading(); } catch (_) {}
                          }
                        }
                      },
                      onLoadError: (controller, url, code, message) async {
                        final now = DateTime.now().millisecondsSinceEpoch;
                        final ev = "InAppWebViewError(code=$code, message=$message)";
                        await postCasinoStat(
                          event: ev,
                          timeStart: now,
                          timeFinish: now,
                          url: url?.toString() ?? '',
                          appSid: _affiliate.affiliateUID,
                          firstPageLoadTs: _firstPageStamp,
                        );
                        if (mounted) setState(() => _busy = false);
                      },
                      onReceivedHttpError: (controller, request, errorResponse) async {
                        final now = DateTime.now().millisecondsSinceEpoch;
                        final ev = "HTTPError(status=${errorResponse.statusCode}, reason=${errorResponse.reasonPhrase})";
                        await postCasinoStat(
                          event: ev,
                          timeStart: now,
                          timeFinish: now,
                          url: request.url?.toString() ?? '',
                          appSid: _affiliate.affiliateUID,
                          firstPageLoadTs: _firstPageStamp,
                        );
                      },
                      onReceivedError: (controller, request, error) async {
                        final now = DateTime.now().millisecondsSinceEpoch;
                        final desc = (error.description ?? '').toString();
                        final ev = "WebResourceError(code=${error}, message=$desc)";
                        await postCasinoStat(
                          event: ev,
                          timeStart: now,
                          timeFinish: now,
                          url: request.url?.toString() ?? '',
                          appSid: _affiliate.affiliateUID,
                          firstPageLoadTs: _firstPageStamp,
                        );
                      },
                      onLoadStop: (c, u) async {
                        await c.evaluateJavascript(source: "console.log('Harbor up!');");

                        // Отправляем данные только ОДИН РАЗ
                        await _pushDeviceDataOnce();
                        await _pushAffiliateDataOnce();

                        setState(() => _currentUrl = u.toString());

                        Future.delayed(const Duration(seconds: 20), () {
                          sendLoadedOnce(url: _currentUrl.toString(), timestart: _startLoadTs);
                        });

                        if (mounted) setState(() => _busy = false);
                      },
                      shouldOverrideUrlLoading: (c, action) async {
                        final uri = action.request.url;
                        if (uri == null) return NavigationActionPolicy.ALLOW;

                        if (_isBareEmail(uri)) {
                          final mailto = _toMailto(uri);
                          await _openMailInWeb(mailto);
                          return NavigationActionPolicy.CANCEL;
                        }

                        final sch = uri.scheme.toLowerCase();

                        if (sch == 'mailto') {
                          await _openMailInWeb(uri);
                          return NavigationActionPolicy.CANCEL;
                        }

                        if (sch == 'tel') {
                          await launchUrl(uri, mode: LaunchMode.externalApplication);
                          return NavigationActionPolicy.CANCEL;
                        }

                        if (_isPlatformish(uri)) {
                          final web = _normalizeToHttp(uri);
                          if (web.scheme == 'http' || web.scheme == 'https') {
                            await _openInBrowser(web);
                          } else {
                            try {
                              if (await canLaunchUrl(uri)) {
                                await launchUrl(uri, mode: LaunchMode.externalApplication);
                              } else if (web != uri && (web.scheme == 'http' || web.scheme == 'https')) {
                                await _openInBrowser(web);
                              }
                            } catch (_) {}
                          }
                          return NavigationActionPolicy.CANCEL;
                        }

                        if (sch != 'http' && sch != 'https') {
                          return NavigationActionPolicy.CANCEL;
                        }

                        return NavigationActionPolicy.ALLOW;
                      },
                      onCreateWindow: (c, req) async {
                        final uri = req.request.url;
                        if (uri == null) return false;

                        if (_isBareEmail(uri)) {
                          final mailto = _toMailto(uri);
                          await _openMailInWeb(mailto);
                          return false;
                        }

                        final sch = uri.scheme.toLowerCase();

                        if (sch == 'mailto') {
                          await _openMailInWeb(uri);
                          return false;
                        }

                        if (sch == 'tel') {
                          await launchUrl(uri, mode: LaunchMode.externalApplication);
                          return false;
                        }

                        if (_isPlatformish(uri)) {
                          final web = _normalizeToHttp(uri);
                          if (web.scheme == 'http' || web.scheme == 'https') {
                            await _openInBrowser(web);
                          } else {
                            try {
                              if (await canLaunchUrl(uri)) {
                                await launchUrl(uri, mode: LaunchMode.externalApplication);
                              } else if (web != uri && (web.scheme == 'http' || web.scheme == 'https')) {
                                await _openInBrowser(web);
                              }
                            } catch (_) {}
                          }
                          return false;
                        }

                        if (sch == 'http' || sch == 'https') {
                          c.loadUrl(urlRequest: URLRequest(url: uri));
                        }
                        return false;
                      },
                      onDownloadStartRequest: (c, req) async {
                        await _openInBrowser(req.url);
                      },
                    ),
                    Visibility(
                      visible: !_veil,
                      child: const LuckyWaveNeonLoader(),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// CasinoExternalWeb — отдельный WebView для внешних ссылок (из нотификаций)
// ============================================================================
class CasinoExternalWeb extends StatefulWidget with WidgetsBindingObserver {
  final String uri;
  const CasinoExternalWeb(this.uri, {super.key});

  @override
  State<CasinoExternalWeb> createState() => _CasinoExternalWebState();
}

class _CasinoExternalWebState extends State<CasinoExternalWeb> with WidgetsBindingObserver {
  late InAppWebViewController _ctrl;

  @override
  Widget build(BuildContext context) {
    final night = MediaQuery.of(context).platformBrightness == Brightness.dark;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: night ? SystemUiOverlayStyle.dark : SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: InAppWebView(
          initialSettings:  InAppWebViewSettings(
            javaScriptEnabled: true,
            disableDefaultErrorPage: true,
            mediaPlaybackRequiresUserGesture: false,
            allowsInlineMediaPlayback: true,
            allowsPictureInPictureMediaPlayback: true,
            useOnDownloadStart: true,
            javaScriptCanOpenWindowsAutomatically: true,
            useShouldOverrideUrlLoading: true,
            supportMultipleWindows: true,
          ),
          initialUrlRequest: URLRequest(url: WebUri(widget.uri)),
          onWebViewCreated: (c) => _ctrl = c,
        ),
      ),
    );
  }
}

// ============================================================================
// Help экраны
// ============================================================================
class CasinoHelpLite extends StatefulWidget {
  const CasinoHelpLite({super.key});

  @override
  State<CasinoHelpLite> createState() => _CasinoHelpLiteState();
}

class _CasinoHelpLiteState extends State<CasinoHelpLite> {
  InAppWebViewController? _wvc;
  bool _ld = true;

  Future<bool> _goBackInWebViewIfPossible() async {
    if (_wvc == null) return false;
    try {
      final canBack = await _wvc!.canGoBack();
      if (canBack) {
        await _wvc!.goBack();
        return true;
      }
    } catch (_) {}
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        final handled = await _goBackInWebViewIfPossible();
        return handled ? false : false;
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          elevation: 0,
          leading: IconButton(
            tooltip: 'Назад',
            icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white),
            onPressed: () async {
              final handled = await _goBackInWebViewIfPossible();
              if (!handled) {}
            },
          ),
        ),
        body: SafeArea(
          child: Stack(
            children: [
              InAppWebView(
                initialFile: 'assets/luckwave.html',
                initialSettings:  InAppWebViewSettings(
                  javaScriptEnabled: true,
                  supportZoom: false,
                  disableHorizontalScroll: false,
                  disableVerticalScroll: false,
                  transparentBackground: true,
                  mediaPlaybackRequiresUserGesture: false,
                  disableDefaultErrorPage: true,
                  allowsInlineMediaPlayback: true,
                  allowsPictureInPictureMediaPlayback: true,
                  useOnDownloadStart: true,
                  javaScriptCanOpenWindowsAutomatically: true,
                ),
                onWebViewCreated: (controller) => _wvc = controller,
                onLoadStart: (controller, url) => setState(() => _ld = true),
                onLoadStop: (controller, url) async => setState(() => _ld = false),
                onLoadError: (controller, url, code, message) =>
                    setState(() => _ld = false),
              ),
              if (_ld)
                const Positioned.fill(
                  child: IgnorePointer(
                    ignoring: true,
                    child: LuckyWaveNeonLoader(),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// main()
// ============================================================================
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp();
  FirebaseMessaging.onBackgroundMessage(casinoBgPush);

  if (Platform.isAndroid) {
    await InAppWebViewController.setWebContentsDebuggingEnabled(true);
  }
  tz_data.initializeTimeZones();

  runApp(
    p.MultiProvider(
      providers: [
        consigliereProvider,
      ],
      child: r.ProviderScope(
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          home: const CasinoSplash(),
        ),
      ),
    ),
  );
}

// ============================================================================
// Заглушка экрана, открываемого из уведомлений по URI
// ============================================================================
class CasinoTable extends StatelessWidget {
  final String url;
  const CasinoTable(this.url, {super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: InAppWebView(
        initialUrlRequest: URLRequest(url: WebUri(url)),
        initialSettings:  InAppWebViewSettings(
          javaScriptEnabled: true,
          disableDefaultErrorPage: true,
          mediaPlaybackRequiresUserGesture: false,
          allowsInlineMediaPlayback: true,
          allowsPictureInPictureMediaPlayback: true,
          useOnDownloadStart: true,
          javaScriptCanOpenWindowsAutomatically: true,
          useShouldOverrideUrlLoading: true,
          supportMultipleWindows: true,
        ),
      ),
    );
  }
}