import 'dart:convert';
import 'dart:io';

import 'package:appsflyer_sdk/appsflyer_sdk.dart' show AppsFlyerOptions, AppsflyerSdk;
import 'package:device_info_plus/device_info_plus.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MethodCall, MethodChannel, SystemUiOverlayStyle;
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:timezone/data/latest.dart' as timezone_data;
import 'package:timezone/timezone.dart' as timezone;
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import 'main.dart' show MainHandler, WebPage, PortalView, ScreenPortal, GateVortex, ZxHubView, hvViewModel, crHarbor, MafiaHarbor, ControlTower;

/// FCM Background Handler — казино-этаж слушает канал связи
@pragma('vm:entry-point')
Future<void> casinoBgComms(RemoteMessage pitMsg) async {
  print("Bottle ID: ${pitMsg.messageId}");
  print("Bottle Data: ${pitMsg.data}");
}

/// Экран с веб-вью — основной стол/кабина крупье
class CasinoTable extends StatefulWidget with WidgetsBindingObserver {
  String casinoRoute;
  CasinoTable(this.casinoRoute, {super.key});

  @override
  State<CasinoTable> createState() => _CasinoTableState(casinoRoute);
}

class _CasinoTableState extends State<CasinoTable> with WidgetsBindingObserver {
  _CasinoTableState(this._currentRoute);

  late InAppWebViewController _dealerConsole;  // _cockpit
  String? _casinoFcmChip;                      // _fcmBeacon
  String? _casinoDeviceId;                     // _airframeId
  String? _casinoOsBuild;                      // _airframeBuild
  String? _casinoPlatform;                     // _airframePlatform
  String? _casinoLocale;                       // _localeCode
  String? _casinoTimezone;                     // _tzName
  bool _casinoPushEnabled = true;              // _pushArmed
  bool _casinoLoading = false;                 // _crewLoading
  var _casinoGateOpen = true;                  // _gateOpen
  String _currentRoute;
  DateTime? _casinoPausedAt;                   // _lastBackgroundAt

  // Внешние «хабы» (tg/wa/bnl)
  final Set<String> _casinoHubHosts = {
    't.me', 'telegram.me', 'telegram.dog',
    'wa.me', 'api.whatsapp.com', 'chat.whatsapp.com',
    'bnl.com', 'www.bnl.com',
  };
  final Set<String> _casinoHubSchemes = {'tg', 'telegram', 'whatsapp', 'bnl'};

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState casinoPhase) {
    if (casinoPhase == AppLifecycleState.paused) {
      _casinoPausedAt = DateTime.now();
    }
    if (casinoPhase == AppLifecycleState.resumed) {
      if (Platform.isIOS && _casinoPausedAt != null) {
        final now = DateTime.now();
        final drift = now.difference(_casinoPausedAt!);
        if (drift > const Duration(minutes: 25)) {
          casinoHardReload();
        }
      }
      _casinoPausedAt = null;
    }
  }

  void casinoHardReload() {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (context) => CasinoTable(""),
        ),
            (route) => false,
      );
    });
  }

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this);

    FirebaseMessaging.onBackgroundMessage(casinoBgComms);

    _initCasinoFcm();
    _scanCasinoDevice();
    _wireCasinoFcmForeground();
    _bindCasinoNotificationBell();

    Future.delayed(const Duration(seconds: 2), () {
      // отложенная инициализация курса/маршрута
    });
    Future.delayed(const Duration(seconds: 6), () {
      // резерв
    });
  }

  void _wireCasinoFcmForeground() {
    FirebaseMessaging.onMessage.listen((RemoteMessage msg) {
      if (msg.data['uri'] != null) {
        _casinoNavigate(msg.data['uri'].toString());
      } else {
        _casinoReturnToRoute();
      }
    });

    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage msg) {
      if (msg.data['uri'] != null) {
        _casinoNavigate(msg.data['uri'].toString());
      } else {
        _casinoReturnToRoute();
      }
    });
  }

  void _casinoNavigate(String newLeg) async {
    if (_dealerConsole != null) {
      await _dealerConsole.loadUrl(urlRequest: URLRequest(url: WebUri(newLeg)));
    }
    _currentRoute = newLeg;
  }

  void _casinoReturnToRoute() async {
    Future.delayed(const Duration(seconds: 3), () {
      if (_dealerConsole != null) {
        _dealerConsole.loadUrl(urlRequest: URLRequest(url: WebUri(_currentRoute)));
      }
    });
  }

  Future<void> _initCasinoFcm() async {
    FirebaseMessaging casinoTower = FirebaseMessaging.instance;
    NotificationSettings perm = await casinoTower.requestPermission(alert: true, badge: true, sound: true);
    _casinoFcmChip = await casinoTower.getToken();
  }

  AppsflyerSdk? _casinoAfSdk; // _afSdk
  String _casinoAfPayload = ""; // _afPayload
  String _casinoAfUid = "";     // _afUid

  Future<void> _scanCasinoDevice() async {
    try {
      final dev = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final a = await dev.androidInfo;
        _casinoDeviceId = a.id;
        _casinoPlatform = "android";
        _casinoOsBuild = a.version.release;
      } else if (Platform.isIOS) {
        final i = await dev.iosInfo;
        _casinoDeviceId = i.identifierForVendor;
        _casinoPlatform = "ios";
        _casinoOsBuild = i.systemVersion;
      }
      final pkg = await PackageInfo.fromPlatform();
      _casinoLocale = Platform.localeName.split('_')[0];
      _casinoTimezone = timezone.local.name;
    } catch (e) {
      debugPrint("Avionics Scan Error: $e");
    }
  }

  /// Колокол уведомлений из нативного слоя
  void _bindCasinoNotificationBell() {
    MethodChannel('com.example.fcm/notification').setMethodCallHandler((MethodCall call) async {
      if (call.method == "onNotificationTap") {
        final Map<String, dynamic> payload = Map<String, dynamic>.from(call.arguments);
        print("URI from mast: ${payload['uri']}");
        if (payload["uri"] != null && !payload["uri"].toString().contains("Нет URI")) {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (context) => CasinoTable(payload["uri"])),
                (route) => false,
          );
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    _bindCasinoNotificationBell(); // повторная привязка, как в исходнике

    final isNight = MediaQuery.of(context).platformBrightness == Brightness.dark;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        body: Stack(
          children: [
            InAppWebView(
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
              ),
              initialUrlRequest: URLRequest(url: WebUri.uri(Uri.parse(_currentRoute))),
              onWebViewCreated: (controller) {
                _dealerConsole = controller;

                _dealerConsole.addJavaScriptHandler(
                  handlerName: 'onServerResponse',
                  callback: (args) {
                    print("JS Args: $args");
                    try {
                      return args.reduce((v, e) => v + e);
                    } catch (_) {
                      return args.toString();
                    }
                  },
                );
              },
              onLoadStart: (controller, uri) async {
                if (uri != null) {
                  if (_casinoLooksLikeBareMail(uri)) {
                    try {
                      await controller.stopLoading();
                    } catch (_) {}
                    final mailto = _casinoToMailto(uri);
                    await _casinoOpenMailViaWeb(mailto);
                    return;
                  }
                  final s = uri.scheme.toLowerCase();
                  if (s != 'http' && s != 'https') {
                    try {
                      await controller.stopLoading();
                    } catch (_) {}
                  }
                }
              },
              onLoadStop: (controller, uri) async {
                await controller.evaluateJavascript(source: "console.log('Ahoy from JS!');");
              },
              shouldOverrideUrlLoading: (controller, nav) async {
                final uri = nav.request.url;
                if (uri == null) return NavigationActionPolicy.ALLOW;

                if (_casinoLooksLikeBareMail(uri)) {
                  final mailto = _casinoToMailto(uri);
                  await _casinoOpenMailViaWeb(mailto);
                  return NavigationActionPolicy.CANCEL;
                }

                final sch = uri.scheme.toLowerCase();
                if (sch == 'mailto') {
                  await _casinoOpenMailViaWeb(uri);
                  return NavigationActionPolicy.CANCEL;
                }

                if (_casinoIsExternalHub(uri)) {
                  await _casinoOpenExternal(_casinoMapExternalToHttp(uri));
                  return NavigationActionPolicy.CANCEL;
                }

                if (sch != 'http' && sch != 'https') {
                  return NavigationActionPolicy.CANCEL;
                }

                return NavigationActionPolicy.ALLOW;
              },
              onCreateWindow: (controller, req) async {
                final u = req.request.url;
                if (u == null) return false;

                if (_casinoLooksLikeBareMail(u)) {
                  final m = _casinoToMailto(u);
                  await _casinoOpenMailViaWeb(m);
                  return false;
                }

                final sch = u.scheme.toLowerCase();
                if (sch == 'mailto') {
                  await _casinoOpenMailViaWeb(u);
                  return false;
                }

                if (_casinoIsExternalHub(u)) {
                  await _casinoOpenExternal(_casinoMapExternalToHttp(u));
                  return false;
                }

                if (sch == 'http' || sch == 'https') {
                  controller.loadUrl(urlRequest: URLRequest(url: u));
                }
                return false;
              },
            ),

            if (_casinoLoading)
              Positioned.fill(
                child: Container(
                  color: Colors.black87,
                  child: Center(
                    child: CircularProgressIndicator(
                      backgroundColor: Colors.grey.shade800,
                      valueColor: const AlwaysStoppedAnimation<Color>(Colors.amber),
                      strokeWidth: 6,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // =========================
  // Казино-утилиты навигации/почты
  // =========================

  bool _casinoLooksLikeBareMail(Uri u) {
    final s = u.scheme;
    if (s.isNotEmpty) return false;
    final raw = u.toString();
    return raw.contains('@') && !raw.contains(' ');
  }

  Uri _casinoToMailto(Uri u) {
    final full = u.toString();
    final bits = full.split('?');
    final who = bits.first;
    final qp = bits.length > 1 ? Uri.splitQueryString(bits[1]) : <String, String>{};
    return Uri(
      scheme: 'mailto',
      path: who,
      queryParameters: qp.isEmpty ? null : qp,
    );
  }

  bool _casinoIsExternalHub(Uri u) {
    final sch = u.scheme.toLowerCase();
    if (_casinoHubSchemes.contains(sch)) return true;

    if (sch == 'http' || sch == 'https') {
      final h = u.host.toLowerCase();
      if (_casinoHubHosts.contains(h)) return true;
    }
    return false;
  }

  Uri _casinoMapExternalToHttp(Uri u) {
    final sch = u.scheme.toLowerCase();

    if (sch == 'tg' || sch == 'telegram') {
      final qp = u.queryParameters;
      final domain = qp['domain'];
      if (domain != null && domain.isNotEmpty) {
        return Uri.https('t.me', '/$domain', {
          if (qp['start'] != null) 'start': qp['start']!,
        });
      }
      final path = u.path.isNotEmpty ? u.path : '';
      return Uri.https('t.me', '/$path', u.queryParameters.isEmpty ? null : u.queryParameters);
    }

    if (sch == 'whatsapp') {
      final qp = u.queryParameters;
      final phone = qp['phone'];
      final text = qp['text'];
      if (phone != null && phone.isNotEmpty) {
        return Uri.https('wa.me', '/${_casinoDigitsOnly(phone)}', {
          if (text != null && text.isNotEmpty) 'text': text,
        });
      }
      return Uri.https('wa.me', '/', {if (text != null && text.isNotEmpty) 'text': text});
    }

    if (sch == 'bnl') {
      final newPath = u.path.isNotEmpty ? u.path : '';
      return Uri.https('bnl.com', '/$newPath', u.queryParameters.isEmpty ? null : u.queryParameters);
    }

    return u;
  }

  Future<bool> _casinoOpenMailViaWeb(Uri m) async {
    final g = _casinoGmailComposer(m);
    return await _casinoOpenExternal(g);
  }

  Uri _casinoGmailComposer(Uri m) {
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

  Future<bool> _casinoOpenExternal(Uri u) async {
    try {
      if (await launchUrl(u, mode: LaunchMode.inAppBrowserView)) return true;
      return await launchUrl(u, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('openExternal error: $e; url=$u');
      try {
        return await launchUrl(u, mode: LaunchMode.externalApplication);
      } catch (_) {
        return false;
      }
    }
  }

  String _casinoDigitsOnly(String s) => s.replaceAll(RegExp(r'[^0-9+]'), '');
}