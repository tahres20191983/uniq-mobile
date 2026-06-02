import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

final FlutterLocalNotificationsPlugin _localNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp();
  } catch (_) {
    // Ignore initialization errors in background isolate.
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  } catch (_) {
    // If Firebase is not configured yet (e.g. missing google-services.json),
    // app should still run without push features.
  }
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.black,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );
  runApp(const UniqApp());
}

class RichNotificationContent {
  const RichNotificationContent({
    required this.enabled,
    required this.format,
    required this.bodyHtml,
    required this.bodyText,
    required this.version,
  });

  final bool enabled;
  final String format;
  final String bodyHtml;
  final String bodyText;
  final int version;

  bool get hasHtml => bodyHtml.trim().isNotEmpty;
  bool get hasText => bodyText.trim().isNotEmpty;
}

class NotificationInboxItem {
  const NotificationInboxItem({
    required this.deliveryId,
    required this.notificationId,
    required this.title,
    required this.body,
    required this.type,
    required this.dataJson,
    required this.status,
    required this.isOpened,
    required this.sentAt,
    required this.openedAt,
    required this.createdAt,
  });

  final int deliveryId;
  final int notificationId;
  final String title;
  final String body;
  final String type;
  final String dataJson;
  final String status;
  final bool isOpened;
  final DateTime? sentAt;
  final DateTime? openedAt;
  final DateTime? createdAt;

  String get cacheKey => '${notificationId}_$deliveryId';

  NotificationInboxItem copyWith({
    bool? isOpened,
    DateTime? openedAt,
  }) {
    return NotificationInboxItem(
      deliveryId: deliveryId,
      notificationId: notificationId,
      title: title,
      body: body,
      type: type,
      dataJson: dataJson,
      status: status,
      isOpened: isOpened ?? this.isOpened,
      sentAt: sentAt,
      openedAt: openedAt ?? this.openedAt,
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'deliveryId': deliveryId,
      'notificationId': notificationId,
      'title': title,
      'body': body,
      'type': type,
      'dataJson': dataJson,
      'status': status,
      'isOpened': isOpened,
      'sentAt': sentAt?.toIso8601String(),
      'openedAt': openedAt?.toIso8601String(),
      'createdAt': createdAt?.toIso8601String(),
    };
  }

  static NotificationInboxItem? fromJson(Map<String, dynamic> json) {
    final notificationId = _toInt(json['notificationId']);
    final deliveryId = _toInt(json['deliveryId']);
    if (notificationId == null || deliveryId == null) return null;
    return NotificationInboxItem(
      deliveryId: deliveryId,
      notificationId: notificationId,
      title: (json['title'] ?? '').toString(),
      body: (json['body'] ?? '').toString(),
      type: (json['type'] ?? '').toString(),
      dataJson: (json['dataJson'] ?? '').toString(),
      status: (json['status'] ?? '').toString(),
      isOpened: _toBool(json['isOpened']),
      sentAt: _toDate(json['sentAt']),
      openedAt: _toDate(json['openedAt']),
      createdAt: _toDate(json['createdAt']),
    );
  }

  static int? _toInt(dynamic v) {
    if (v == null) return null;
    return int.tryParse(v.toString());
  }

  static bool _toBool(dynamic v) {
    if (v == true) return true;
    final s = (v ?? '').toString().toLowerCase();
    return s == 'true' || s == '1';
  }

  static DateTime? _toDate(dynamic v) {
    if (v == null) return null;
    return DateTime.tryParse(v.toString());
  }
}

class UniqApp extends StatelessWidget {
  const UniqApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'UNIQ',
      theme: ThemeData.dark(),
      home: const UniqWebViewPage(),
    );
  }
}

class UniqWebViewPage extends StatefulWidget {
  const UniqWebViewPage({super.key});

  @override
  State<UniqWebViewPage> createState() => _UniqWebViewPageState();
}

class _UniqWebViewPageState extends State<UniqWebViewPage> {
  static const String _brandLogoUrl =
      'https://www.uniqperformance.com.tr/Content/images/uniq-logo.svg';
  static const String _googleLoginEndpoint =
      'https://www.uniqperformance.com.tr/Account/GoogleLogin';
  static const String _deviceTokenEndpoint =
      'https://www.uniqperformance.com.tr/api/mobile/device-token';
  static const String _notificationsEndpoint =
      'https://www.uniqperformance.com.tr/api/mobile/notifications';
  static const String _notificationsCacheKey = 'uniq.notifications.cache.v1';
  static const String _notificationsOpenRetryKey =
      'uniq.notifications.open_retry.v1';
  static const String _googleServerClientId =
      '721753132038-7ouaeaqrsp91qj8bbnkcvqkmrvf7c89i.apps.googleusercontent.com';
  static const String _googleIosClientId =
      '721753132038-lh42ifc4qpdbqd92klob70b0tnopu4cg.apps.googleusercontent.com';
  WebViewController? _controller;
  final GoogleSignIn _googleSignIn = GoogleSignIn.instance;
  bool _googleInitialized = false;
  bool _googleLoginInProgress = false;
  String? _lastGoogleInitError;
  bool _loading = true;
  bool _showBootSplash = true;
  bool _hasError = false;
  String _errorDetail = '';
  String _currentUrl = 'https://www.uniqperformance.com.tr/Home/Index';
  String _previousUrl = '';
  String? _lastTokenSyncError;
  bool _pushInitWarningShown = false;
  bool _pushMessagingReady = false;
  bool _pushListenersAttached = false;
  bool _tokenSyncArmedByLogin = false;
  final Uri _home = Uri.parse('https://www.uniqperformance.com.tr/Home/Index');
  final Set<String> _trustedLinkHosts = {
    'uniqperformance.com.tr',
    'www.uniqperformance.com.tr',
  };
  late final bool _supportsInAppWebView;
  String? _deviceToken;
  String? _lastSyncedDeviceToken;
  StreamSubscription<String>? _tokenRefreshSub;
  StreamSubscription<RemoteMessage>? _foregroundMsgSub;
  StreamSubscription<RemoteMessage>? _openMsgSub;
  List<NotificationInboxItem> _inboxItems = const [];

  Future<void> _loadHome() async {
    _hasError = false;
    _errorDetail = '';
    _loading = true;
    setState(() {});
    await _controller?.loadRequest(_home);
  }

  @override
  void initState() {
    super.initState();
    _initGoogleSignIn();
    _initPushNotifications();
    _loadNotificationsFromCache();
    _supportsInAppWebView = !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS);

    if (_supportsInAppWebView) {
      _controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..addJavaScriptChannel(
          'UniqNativeAuth',
          onMessageReceived: (message) async {
            if (message.message == 'google_native_login') {
              await _handleNativeGoogleLogin();
            }
          },
        )
        ..setNavigationDelegate(
          NavigationDelegate(
            onPageStarted: (url) {
              setState(() {
                _loading = true;
                _hasError = false;
                _errorDetail = '';
                _previousUrl = _currentUrl;
                _currentUrl = url;
              });
              unawaited(_injectMobileScrollbarStyle());
            },
            onPageFinished: (_) async {
              setState(() {
                _loading = false;
                _showBootSplash = false;
              });
              final isLogin = _isLikelyLoginUrl(_currentUrl);
              final cameFromLogin = _isLikelyLoginUrl(_previousUrl) && !isLogin;
              if (isLogin) {
                _tokenSyncArmedByLogin = true;
                debugPrint('[PUSH] login sayfasinda, token sync arm edildi.');
              } else if (_tokenSyncArmedByLogin && cameFromLogin) {
                debugPrint('[PUSH] login sonrasi ilk sayfa, token sync basliyor.');
                await _bindFirebaseMessaging();
                await Future<void>.delayed(const Duration(milliseconds: 800));
                await _syncDeviceTokenWithBackend();
                if (_deviceToken != null && _lastSyncedDeviceToken == _deviceToken) {
                  debugPrint(
                    '[PUSH] device-token backend ile eslesti (${_pushPlatformLabel()}).',
                  );
                }
                await _refreshNotificationsFromApi(top: 100);
                await _flushPendingOpenQueue();
                _tokenSyncArmedByLogin = false;
              }
              if (!_isLikelyLoginUrl(_currentUrl)) {
                _schedulePushBinding();
              }
              await _injectGooglePopupBridge();
              await _injectGoogleNativeButtonBridge();
              await _hideWebAppleSignInIfNeeded();
              await _injectInlineGoogleButtonIfNeeded();
              await _injectMobileScrollbarStyle();
            },
            onWebResourceError: (error) {
              if (error.isForMainFrame ?? false) {
                setState(() {
                  _loading = false;
                  _showBootSplash = false;
                  _hasError = true;
                  _errorDetail = error.description;
                });
              }
            },
            onNavigationRequest: (request) async {
              final uri = Uri.tryParse(request.url);
              if (uri == null) return NavigationDecision.prevent;

              if (_isExternalScheme(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
                return NavigationDecision.prevent;
              }

              // Site + odeme/3D/BKM/banka: WebView icinde kalmali (iOS Safari'ye acinca oturum kaybolur).
              if (_shouldStayInWebView(uri)) {
                return NavigationDecision.navigate;
              }

              final host = uri.host.toLowerCase();
              final trusted = _trustedLinkHosts.contains(host) ||
                  _trustedLinkHosts.any((h) => host.endsWith('.$h'));
              if (!trusted) {
                final opened = await launchUrl(
                  uri,
                  mode: LaunchMode.externalApplication,
                );
                return opened
                    ? NavigationDecision.prevent
                    : NavigationDecision.navigate;
              }

              return NavigationDecision.navigate;
            },
          ),
        );
      unawaited(_configureNativeWebViewChrome(_controller!));
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        unawaited(
          _controller!.setUserAgent(
            'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) '
            'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 '
            'Mobile/15E148 Safari/604.1',
          ),
        );
      }
      _loadHome();
    } else {
      _loading = false;
    }
  }

  @override
  void dispose() {
    _tokenRefreshSub?.cancel();
    _foregroundMsgSub?.cancel();
    _openMsgSub?.cancel();
    super.dispose();
  }

  bool _isExternalScheme(Uri uri) {
    final scheme = uri.scheme.toLowerCase();
    return scheme == 'intent' ||
        scheme == 'market' ||
        scheme == 'tg' ||
        scheme == 'whatsapp';
  }

  Future<void> _initGoogleSignIn() async {
    if (_googleInitialized) return;
    // Android: serverClientId + SHA. iOS: clientId + serverClientId (GoogleService-Info / Info.plist).
    final attempts = <Future<void> Function()>[];
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      attempts.add(
        () => _googleSignIn.initialize(
          clientId: _googleIosClientId,
          serverClientId: _googleServerClientId,
        ),
      );
    }
    attempts.add(
      () => _googleSignIn.initialize(serverClientId: _googleServerClientId),
    );
    attempts.add(() => _googleSignIn.initialize());

    for (final attempt in attempts) {
      try {
        await attempt();
        _googleInitialized = true;
        _lastGoogleInitError = null;
        return;
      } catch (e) {
        _lastGoogleInitError = e.toString();
        debugPrint('[AUTH] Google initialize failed: $_lastGoogleInitError');
      }
    }
    _googleInitialized = false;
  }

  /// Yerel bildirim kanali; FCM baglantisi [_bindFirebaseMessaging] ile geciktirilir.
  String _pushPlatformLabel() {
    if (defaultTargetPlatform == TargetPlatform.iOS) return 'ios';
    return 'android';
  }

  Future<void> _initPushNotifications() async {
    try {
      const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
      const darwinInit = DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      );
      const settings = InitializationSettings(
        android: androidInit,
        iOS: darwinInit,
        macOS: darwinInit,
      );
      await _localNotificationsPlugin.initialize(settings);
      await _requestNotificationPermissions();
    } catch (e, st) {
      debugPrint('[PUSH] local notifications init: $e\n$st');
    }
  }

  Future<void> _bindFirebaseMessaging() async {
    if (_pushMessagingReady) return;
    if (Firebase.apps.isEmpty) {
      debugPrint('[PUSH] Firebase henuz hazir degil, baglanti ertelendi.');
      return;
    }

    try {
      if (!_pushListenersAttached) {
        _tokenRefreshSub ??= FirebaseMessaging.instance.onTokenRefresh.listen((
          token,
        ) async {
          _deviceToken = token;
          _lastSyncedDeviceToken = null;
          if (_shouldSyncTokenAfterLogin()) {
            await _syncDeviceTokenWithBackend();
          }
        });

        _foregroundMsgSub ??= FirebaseMessaging.onMessage.listen((message) async {
          await _handleForegroundMessage(message);
        });

        _openMsgSub ??= FirebaseMessaging.onMessageOpenedApp.listen((message) async {
          await _handleOpenedMessage(message);
        });
        _pushListenersAttached = true;
      }

      for (var attempt = 0; attempt < 4; attempt++) {
        try {
          final token = await FirebaseMessaging.instance.getToken();
          if (token != null && token.isNotEmpty) {
            _deviceToken = token;
            _pushMessagingReady = true;
            debugPrint('[PUSH] FCM token alindi (deneme ${attempt + 1}).');
            break;
          }
        } catch (e) {
          debugPrint('[PUSH] getToken deneme ${attempt + 1}: $e');
        }
        if (!_pushMessagingReady && attempt < 3) {
          await Future<void>.delayed(Duration(milliseconds: 600 * (attempt + 1)));
        }
      }

      if (!_pushMessagingReady) {
        debugPrint('[PUSH] FCM token su an alinamadi; giris sonrasi tekrar denenecek.');
        return;
      }

      try {
        final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
        if (initialMessage != null) {
          await _handleOpenedMessage(initialMessage);
        }
      } catch (e) {
        debugPrint('[PUSH] getInitialMessage: $e');
      }
    } catch (e, st) {
      debugPrint('[PUSH] FCM baglanti hatasi: $e\n$st');
    }
  }

  void _schedulePushBinding() {
    if (_pushMessagingReady) return;
    unawaited(_bindFirebaseMessaging());
  }

  void _showPushInitWarning(String message) {
    if (_pushInitWarningShown || !mounted) return;
    if (_isLikelyLoginUrl(_currentUrl)) return;
    _pushInitWarningShown = true;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _requestNotificationPermissions() async {
    try {
      await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );
      await _localNotificationsPlugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestNotificationsPermission();
    } catch (_) {
      // Ignore permission errors.
    }
  }

  Future<void> _showForegroundNotification(RemoteMessage message) async {
    final notification = message.notification;
    if (notification == null) return;
    const androidDetails = AndroidNotificationDetails(
      'uniq_push_channel',
      'UNIQ Bildirimler',
      channelDescription: 'UNIQ mobil bildirim kanali',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
    );
    const darwinDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );
    const details = NotificationDetails(
      android: androidDetails,
      iOS: darwinDetails,
      macOS: darwinDetails,
    );
    await _localNotificationsPlugin.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      notification.title ?? 'UNIQ',
      notification.body ?? '',
      details,
    );
  }

  Future<void> _handleForegroundMessage(RemoteMessage message) async {
    final rich = _extractRichNotification(message.data);
    if (rich != null && rich.enabled && (rich.hasHtml || rich.hasText)) {
      await _showRichNotificationView(
        rich: rich,
        title: message.notification?.title ?? 'UNIQ',
        deeplink: _extractDeeplink(message.data),
      );
      return;
    }
    await _showForegroundNotification(message);
  }

  Future<void> _handleOpenedMessage(RemoteMessage message) async {
    final deepLink = _extractDeeplink(message.data);
    final notificationId = _extractNotificationId(message.data);
    if (notificationId != null) {
      await _markNotificationOpened(notificationId);
    }
    if (deepLink != null && deepLink.isNotEmpty) {
      await _openDeepLinkInWebView(deepLink);
    }
    final rich = _extractRichNotification(message.data);
    if (rich != null && rich.enabled && (rich.hasHtml || rich.hasText)) {
      await _showRichNotificationView(
        rich: rich,
        title: message.notification?.title ?? 'UNIQ',
        deeplink: deepLink,
      );
    }
  }

  String? _extractDeeplink(Map<String, dynamic> data) {
    final dynamic deeplink = data['deeplink'] ?? data['deepLink'] ?? data['url'];
    if (deeplink is String && deeplink.trim().isNotEmpty) return deeplink.trim();
    return null;
  }

  RichNotificationContent? _extractRichNotification(Map<String, dynamic> data) {
    dynamic raw = data['notificationRich'];
    Map<String, dynamic>? richMap;
    if (raw is String && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) richMap = decoded;
      } catch (_) {
        richMap = null;
      }
    } else if (raw is Map<String, dynamic>) {
      richMap = raw;
    }

    if (richMap == null) {
      final hasFlattened = data.keys.any((k) => k.startsWith('notificationRich.'));
      if (!hasFlattened) return null;
      richMap = <String, dynamic>{
        'enabled': data['notificationRich.enabled'],
        'format': data['notificationRich.format'],
        'bodyHtml': data['notificationRich.bodyHtml'],
        'bodyText': data['notificationRich.bodyText'],
        'version': data['notificationRich.version'],
      };
    }

    final enabledRaw = richMap['enabled'];
    final enabled = enabledRaw == true ||
        enabledRaw?.toString().toLowerCase() == 'true' ||
        enabledRaw?.toString() == '1';
    final format = richMap['format']?.toString() ?? 'html';
    final bodyHtml = _sanitizeNotificationHtml(
      richMap['bodyHtml']?.toString() ?? '',
    );
    final bodyText = richMap['bodyText']?.toString() ?? '';
    final version = int.tryParse(richMap['version']?.toString() ?? '1') ?? 1;

    return RichNotificationContent(
      enabled: enabled,
      format: format,
      bodyHtml: bodyHtml,
      bodyText: bodyText,
      version: version,
    );
  }

  String _sanitizeNotificationHtml(String html) {
    var sanitized = html;
    sanitized = sanitized.replaceAll(
      RegExp(r'<\s*script[^>]*>.*?<\s*/\s*script\s*>', caseSensitive: false, dotAll: true),
      '',
    );
    sanitized = sanitized.replaceAll(
      RegExp(r'<\s*style[^>]*>.*?<\s*/\s*style\s*>', caseSensitive: false, dotAll: true),
      '',
    );
    sanitized = sanitized.replaceAll(
      RegExp("on\\w+\\s*=\\s*['\\\"][^'\\\"]*['\\\"]", caseSensitive: false),
      '',
    );
    sanitized = sanitized.replaceAll(
      RegExp(r'javascript:', caseSensitive: false),
      '',
    );
    return sanitized;
  }

  Future<void> _openDeepLinkInWebView(String deepLink) async {
    if (_controller == null) return;
    final uri = Uri.tryParse(deepLink);
    if (uri == null) return;

    if (uri.scheme == 'uniq') {
      final target = Uri.parse('https://www.uniqperformance.com.tr${uri.path}');
      await _controller!.loadRequest(target);
      return;
    }
    await _controller!.loadRequest(uri);
  }

  Future<void> _showRichNotificationView({
    required RichNotificationContent rich,
    required String title,
    String? deeplink,
  }) async {
    if (!mounted) return;
    final bodyText = rich.hasText ? rich.bodyText : 'Yeni bildirim var.';
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF111318),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 46,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 10),
                if (rich.hasHtml)
                  Html(
                    data: rich.bodyHtml,
                    onlyRenderTheseTags: {
                      'b',
                      'strong',
                      'i',
                      'em',
                      'u',
                      'br',
                      'ul',
                      'ol',
                      'li',
                      'p',
                      'span',
                      'a',
                    },
                    style: {
                      '*': Style(color: Colors.white),
                      'a': Style(color: const Color(0xFFC8FF00)),
                    },
                    onLinkTap: (url, _, _) async {
                      if (url == null || url.isEmpty) return;
                      await _openExternalLinkWithConfirmation(url);
                    },
                  )
                else
                  Text(
                    bodyText,
                    style: const TextStyle(color: Colors.white70, fontSize: 15),
                  ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    if (deeplink != null && deeplink.isNotEmpty)
                      Expanded(
                        child: FilledButton(
                          onPressed: () async {
                            Navigator.of(context).pop();
                            await _openDeepLinkInWebView(deeplink);
                          },
                          child: const Text('Detaya git'),
                        ),
                      ),
                    if (deeplink != null && deeplink.isNotEmpty)
                      const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Kapat'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _openExternalLinkWithConfirmation(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    final host = uri.host.toLowerCase();
    final trusted = _trustedLinkHosts.contains(host) ||
        _trustedLinkHosts.any((h) => host.endsWith('.$h'));
    if (trusted) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      return;
    }
    if (!mounted) return;
    final allowed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Harici baglanti'),
          content: Text('Bu baglantiyi acmak istiyor musunuz?\n$url'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Vazgec'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Ac'),
            ),
          ],
        );
      },
    );
    if (allowed == true) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  int? _extractNotificationId(Map<String, dynamic> data) {
    final dynamic id =
        data['notificationId'] ?? data['notification_id'] ?? data['id'];
    if (id == null) return null;
    return int.tryParse(id.toString());
  }

  Future<void> _loadNotificationsFromCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_notificationsCacheKey);
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      final list = decoded
          .whereType<Map>()
          .map((e) => NotificationInboxItem.fromJson(Map<String, dynamic>.from(e)))
          .whereType<NotificationInboxItem>()
          .toList();
      setState(() {
        _inboxItems = _sortInbox(list);
      });
    } catch (_) {
      // ignore cache read errors
    }
  }

  Future<void> _saveNotificationsToCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = jsonEncode(_inboxItems.map((e) => e.toJson()).toList());
      await prefs.setString(_notificationsCacheKey, raw);
    } catch (_) {
      // ignore cache write errors
    }
  }

  Future<void> _refreshNotificationsFromApi({int top = 100}) async {
    if (_controller == null) return;
    final safeTop = top.clamp(1, 500);
    try {
      final result = await _controller!.runJavaScriptReturningResult('''
(async function() {
  try {
    var response = await fetch('$_notificationsEndpoint?top=$safeTop', {
      method: 'GET',
      headers: { 'Accept': 'application/json' },
      credentials: 'include'
    });
    var text = await response.text();
    text = text.replaceAll('|', '/');
    return String(response.status || 0) + '|' + text;
  } catch (e) {
    return '0|network_error';
  }
})();
''');
      final parsed = _parseStatusAndBody(result);
      if (parsed.$1 != 200) return;
      final bodyJson = jsonDecode(parsed.$2);
      if (bodyJson is! Map<String, dynamic>) return;
      if (bodyJson['success'] != true || bodyJson['items'] is! List) return;
      final incoming = (bodyJson['items'] as List)
          .whereType<Map>()
          .map((e) => NotificationInboxItem.fromJson(Map<String, dynamic>.from(e)))
          .whereType<NotificationInboxItem>()
          .toList();
      _mergeInboxItems(incoming);
      await _saveNotificationsToCache();
    } catch (_) {
      // ignore network/parse failures
    }
  }

  void _mergeInboxItems(List<NotificationInboxItem> incoming) {
    final map = <String, NotificationInboxItem>{
      for (final item in _inboxItems) item.cacheKey: item,
    };
    for (final item in incoming) {
      map[item.cacheKey] = item;
    }
    final merged = _sortInbox(map.values.toList());
    setState(() {
      _inboxItems = merged;
    });
  }

  List<NotificationInboxItem> _sortInbox(List<NotificationInboxItem> items) {
    final sorted = [...items];
    sorted.sort((a, b) {
      final aDate = a.sentAt ?? a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bDate = b.sentAt ?? b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bDate.compareTo(aDate);
    });
    return sorted;
  }

  Future<void> _markNotificationOpened(int notificationId) async {
    final index = _inboxItems.indexWhere((e) => e.notificationId == notificationId);
    if (index >= 0 && _inboxItems[index].isOpened) return;

    final now = DateTime.now();
    if (index >= 0) {
      final updated = [..._inboxItems];
      updated[index] = updated[index].copyWith(isOpened: true, openedAt: now);
      setState(() {
        _inboxItems = _sortInbox(updated);
      });
      await _saveNotificationsToCache();
    }

    if (_controller == null) {
      await _queueOpenRetry(notificationId);
      return;
    }
    try {
      final result = await _controller!.runJavaScriptReturningResult('''
(async function() {
  try {
    var response = await fetch('$_notificationsEndpoint/$notificationId/open', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json'
      },
      credentials: 'include'
    });
    var text = await response.text();
    text = text.replaceAll('|', '/');
    return String(response.status || 0) + '|' + text;
  } catch (e) {
    return '0|network_error';
  }
})();
''');
      final parsed = _parseStatusAndBody(result);
      final status = parsed.$1;
      if (status >= 200 && status < 300) {
        await _removePendingOpen(notificationId);
      } else {
        await _queueOpenRetry(notificationId);
      }
    } catch (_) {
      await _queueOpenRetry(notificationId);
    }
  }

  Future<void> _queueOpenRetry(int notificationId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(_notificationsOpenRetryKey) ?? <String>[];
      final id = notificationId.toString();
      if (!list.contains(id)) {
        list.add(id);
        await prefs.setStringList(_notificationsOpenRetryKey, list);
      }
    } catch (_) {
      // ignore queue errors
    }
  }

  Future<void> _removePendingOpen(int notificationId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(_notificationsOpenRetryKey) ?? <String>[];
      list.remove(notificationId.toString());
      await prefs.setStringList(_notificationsOpenRetryKey, list);
    } catch (_) {
      // ignore queue errors
    }
  }

  Future<void> _flushPendingOpenQueue() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(_notificationsOpenRetryKey) ?? <String>[];
      if (list.isEmpty) return;
      for (final s in [...list]) {
        final id = int.tryParse(s);
        if (id != null) {
          await _markNotificationOpened(id);
        }
      }
    } catch (_) {
      // ignore queue errors
    }
  }

  (int, String) _parseStatusAndBody(Object? result) {
    try {
      final raw = result?.toString() ?? '';
      if (raw.isEmpty) return (0, '');
      final normalized = (raw.startsWith('"') && raw.endsWith('"'))
          ? jsonDecode(raw) as String
          : raw;
      final idx = normalized.indexOf('|');
      if (idx <= 0) return (0, normalized);
      final status = int.tryParse(normalized.substring(0, idx)) ?? 0;
      final body = normalized.substring(idx + 1);
      return (status, body);
    } catch (_) {
      return (0, '');
    }
  }

  Future<void> _syncDeviceTokenWithBackend() async {
    if (!_shouldSyncTokenAfterLogin()) return;
    if (_controller == null) {
      return;
    }
    if (_deviceToken == null || _deviceToken!.isEmpty) {
      await _bindFirebaseMessaging();
    }
    if (_deviceToken == null || _deviceToken!.isEmpty) {
      debugPrint('[PUSH] sync skipped: token null/empty');
      return;
    }
    if (_deviceToken == _lastSyncedDeviceToken) return;
    try {
      final escapedToken = _deviceToken!
          .replaceAll(r'\', r'\\')
          .replaceAll("'", r"\'");
      final platform = _pushPlatformLabel();
      final result = await _controller!.runJavaScriptReturningResult('''
(async function() {
  try {
    var response = await fetch('$_deviceTokenEndpoint', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json'
      },
      credentials: 'include',
      body: JSON.stringify({
        deviceToken: '$escapedToken',
        platform: '$platform'
      })
    });
    var data = null;
    try { data = await response.json(); } catch (e) {}
    var ok = response.ok === true && (!data || data.success !== false);
    var message = data && data.message ? String(data.message) : '';
    message = message.replaceAll('|', '/');
    return (ok ? '1' : '0') + '|' + String(response.status || 0) + '|' + message;
  } catch (e) {
    return '0|0|network_error';
  }
})();
''');

      final parsed = _parseJsResult(result);
      final ok = parsed['ok'] == true;
      if (ok) {
        _lastSyncedDeviceToken = _deviceToken;
        _lastTokenSyncError = null;
        debugPrint('[PUSH] device-token synced successfully.');
      } else {
        final status = parsed['status']?.toString() ?? 'unknown';
        final message = parsed['message']?.toString() ?? 'unknown_error';
        final err = 'status=$status message=$message';
        if (_lastTokenSyncError != err) {
          _lastTokenSyncError = err;
          debugPrint('[PUSH] device-token sync failed: $err');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Push token gonderilemedi: $status'),
                duration: const Duration(seconds: 2),
              ),
            );
          }
        }
      }
    } catch (_) {
      // Retry on next page finish/token refresh.
    }
  }

  Map<String, dynamic> _parseJsResult(Object? result) {
    try {
      final raw = result?.toString() ?? '';
      if (raw.isEmpty) return <String, dynamic>{'ok': false};
      final normalized = (raw.startsWith('"') && raw.endsWith('"'))
          ? jsonDecode(raw) as String
          : raw;
      if (normalized.contains('|')) {
        final parts = normalized.split('|');
        return <String, dynamic>{
          'ok': parts.isNotEmpty && parts[0] == '1',
          'status': parts.length > 1 ? parts[1] : '0',
          'message': parts.length > 2 ? parts.sublist(2).join('|') : '',
        };
      }
    } catch (_) {
      // ignore parse errors
    }
    return <String, dynamic>{'ok': false};
  }

  bool _isPaymentUrl(Uri uri) {
    final u = uri.toString().toLowerCase();
    return u.contains('odeme') ||
        u.contains('payment') ||
        u.contains('3d') ||
        u.contains('iyzico') ||
        u.contains('paytr') ||
        u.contains('bank') ||
        u.contains('secure');
  }

  bool _isPaymentRelatedHost(Uri uri) {
    final host = uri.host.toLowerCase();
    if (host.contains('bkm') || host.endsWith('.bkm.com.tr')) return true;
    if (_isPaymentUrl(uri)) return true;

    const bankHints = <String>[
      'garanti',
      'akbank',
      'isbank',
      'iscep',
      'yapikredi',
      'ziraat',
      'halkbank',
      'qnbfinansbank',
      'qnb',
      'denizbank',
      'finansbank',
      'teb',
      'vakifbank',
      'ingbank',
      'kuveytturk',
      'papara',
      'paycell',
      'emv',
      'pos',
    ];
    for (final hint in bankHints) {
      if (host.contains(hint)) return true;
    }
    return false;
  }

  bool _shouldStayInWebView(Uri uri) {
    if (_shouldOpenInsideWebView(uri)) return true;
    return _isPaymentRelatedHost(uri);
  }

  bool _shouldOpenInsideWebView(Uri uri) {
    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') return false;

    final host = uri.host.toLowerCase();
    return host.endsWith('uniqperformance.com.tr') ||
        host == 'accounts.google.com' ||
        host.endsWith('.google.com') ||
        host.endsWith('.gstatic.com') ||
        host.endsWith('.googleusercontent.com');
  }

  Future<void> _configureNativeWebViewChrome(WebViewController controller) async {
    if (kIsWeb) return;
    try {
      if (await controller.supportsSetScrollBarsEnabled()) {
        await controller.setVerticalScrollBarEnabled(false);
        await controller.setHorizontalScrollBarEnabled(false);
      }
    } catch (_) {
      // Best effort only.
    }
  }

  Future<void> _injectMobileScrollbarStyle() async {
    if (_controller == null) return;
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.android &&
            defaultTargetPlatform != TargetPlatform.iOS)) {
      return;
    }
    try {
      await _controller!.runJavaScript('''
(function() {
  document.documentElement.classList.add('uniq-in-app');
  var style = document.getElementById('uniq-hide-scrollbar-style');
  if (!style) {
    style = document.createElement('style');
    style.id = 'uniq-hide-scrollbar-style';
    document.head.appendChild(style);
  }
  style.textContent = [
    'html.uniq-in-app,html.uniq-in-app body,html.uniq-in-app *{',
    'scrollbar-width:none!important;-ms-overflow-style:none!important;',
    'scrollbar-color:#0a0a0a #0a0a0a!important;',
    '}',
    'html.uniq-in-app::-webkit-scrollbar,',
    'html.uniq-in-app body::-webkit-scrollbar,',
    'html.uniq-in-app *::-webkit-scrollbar{',
    'width:0!important;height:0!important;display:none!important;',
    'background:#0a0a0a!important;',
    '}',
    'html.uniq-in-app::-webkit-scrollbar-thumb,',
    'html.uniq-in-app *::-webkit-scrollbar-thumb{',
    'background:#0a0a0a!important;',
    '}',
    'html.uniq-in-app::-webkit-scrollbar-track,',
    'html.uniq-in-app *::-webkit-scrollbar-track{',
    'background:#0a0a0a!important;',
    '}'
  ].join('');
})();
''');
    } catch (_) {
      // Best effort only.
    }
  }

  Future<void> _injectGooglePopupBridge() async {
    if (_controller == null) return;
    try {
      await _controller!.runJavaScript('''
(function() {
  if (window.__uniqPopupBridgeInstalled) return;
  window.__uniqPopupBridgeInstalled = true;

  var originalOpen = window.open;
  window.open = function(url, name, specs) {
    if (url) {
      var lower = String(url).toLowerCase();
      var isGoogle = lower.indexOf('google') >= 0 || lower.indexOf('accounts.google') >= 0;
      if (isGoogle) {
        window.location.href = url;
        return null;
      }
    }
    if (originalOpen) return originalOpen.apply(window, arguments);
    if (url) {
      window.location.href = url;
      return null;
    }
    return null;
  };
})();
''');
    } catch (_) {
      // Ignore JS bridge errors; navigation delegate still handles normal links.
    }
  }

  Future<void> _injectGoogleNativeButtonBridge() async {
    if (_controller == null) return;
    try {
      await _controller!.runJavaScript('''
(function() {
  if (window.__uniqNativeGoogleBridgeInstalled) return;
  window.__uniqNativeGoogleBridgeInstalled = true;

  function looksLikeGoogleTarget(el) {
    if (!el) return false;
    if (el.closest && el.closest('#googleSignInBtn')) return false;
    if (el.closest && el.closest('#uniq-native-google-btn')) return true;
    var text = ((el.innerText || el.value || '') + '').toLowerCase();
    var cls = ((el.className || '') + '').toLowerCase();
    var href = '';
    if (el.getAttribute) href = (el.getAttribute('href') || '').toLowerCase();
    var action = '';
    var form = el.closest ? el.closest('form[action]') : null;
    if (form && form.action) action = form.action.toLowerCase();

    return text.indexOf('google') >= 0 ||
      cls.indexOf('google') >= 0 ||
      href.indexOf('/account/googlelogin') >= 0 ||
      action.indexOf('/account/googlelogin') >= 0;
  }

  document.addEventListener('click', function(event) {
    var el = event.target && event.target.closest
      ? event.target.closest('a,button,input[type="submit"],div,span')
      : null;
    if (!looksLikeGoogleTarget(el)) return;

    event.preventDefault();
    event.stopPropagation();
    event.stopImmediatePropagation();

    if (window.UniqNativeAuth && window.UniqNativeAuth.postMessage) {
      window.UniqNativeAuth.postMessage('google_native_login');
    }
  }, true);
})();
''');
    } catch (_) {
      // Best effort only.
    }
  }

  bool _isLikelyLoginUrl(String url) {
    final u = url.toLowerCase();
    return u.contains('/account/login') || u.endsWith('/login');
  }

  bool _shouldSyncTokenAfterLogin() {
    final canSync = _currentUrl.isNotEmpty && !_isLikelyLoginUrl(_currentUrl);
    debugPrint('[PUSH] sync-check url=$_currentUrl canSync=$canSync');
    return canSync;
  }

  /// iOS: Web giris sayfasindaki Apple ile giris ogelerini gizler (uygulama sunmuyor).
  Future<void> _hideWebAppleSignInIfNeeded() async {
    if (_controller == null ||
        defaultTargetPlatform != TargetPlatform.iOS ||
        !_isLikelyLoginUrl(_currentUrl)) {
      return;
    }
    try {
      await _controller!.runJavaScript('''
(function() {
  if (window.__uniqAppleHidden) return;
  window.__uniqAppleHidden = true;

  function hideEl(el) {
    if (!el) return;
    var wrap = el.closest('div, section, li, form') || el;
    wrap.style.setProperty('display', 'none', 'important');
    wrap.style.setProperty('visibility', 'hidden', 'important');
    wrap.style.setProperty('height', '0', 'important');
    wrap.style.setProperty('overflow', 'hidden', 'important');
    wrap.setAttribute('aria-hidden', 'true');
  }

  var ids = ['appleSignInBtn', 'AppleSignIn', 'apple-sign-in', 'appleid-signin'];
  for (var i = 0; i < ids.length; i++) hideEl(document.getElementById(ids[i]));

  var nodes = document.querySelectorAll(
    'a, button, div, span, iframe, [class*="apple" i], [id*="apple" i]'
  );
  for (var j = 0; j < nodes.length; j++) {
    var n = nodes[j];
    if (n.id === 'uniq-native-google-btn') continue;
    var t = ((n.innerText || n.title || n.getAttribute('aria-label') || '') + '').toLowerCase();
    var src = (n.src || n.getAttribute('href') || '').toLowerCase();
    if (src.indexOf('appleid') >= 0 ||
        t.indexOf('apple ile') >= 0 ||
        t.indexOf('sign in with apple') >= 0 ||
        (t.indexOf('apple') >= 0 && (t.indexOf('gir') >= 0 || t.indexOf('sign') >= 0))) {
      hideEl(n);
    }
  }
})();
''');
    } catch (_) {
      // Best effort only.
    }
  }

  Future<void> _injectInlineGoogleButtonIfNeeded() async {
    if (_controller == null || !_isLikelyLoginUrl(_currentUrl)) return;
    try {
      await _controller!.runJavaScript('''
(function() {
  if (document.getElementById('uniq-native-google-btn')) return;

  var btn = document.createElement('button');
  btn.id = 'uniq-native-google-btn';
  btn.type = 'button';
  btn.style.width = '100%';
  btn.style.maxWidth = '280px';
  btn.style.height = '44px';
  btn.style.margin = '10px auto 0 auto';
  btn.style.display = 'flex';
  btn.style.alignItems = 'center';
  btn.style.justifyContent = 'center';
  btn.style.gap = '8px';
  btn.style.border = 'none';
  btn.style.borderRadius = '8px';
  btn.style.background = '#CCFF00';
  btn.style.color = '#000';
  btn.style.fontSize = '15px';
  btn.style.fontWeight = '700';
  btn.style.cursor = 'pointer';

  var icon = document.createElement('img');
  icon.src = 'https://www.gstatic.com/firebasejs/ui/2.0.0/images/auth/google.svg';
  icon.alt = 'Google';
  icon.style.width = '18px';
  icon.style.height = '18px';

  var label = document.createElement('span');
  label.id = 'uniq-native-google-btn-label';
  label.textContent = 'Google ile giris yap';

  var spinner = document.createElement('span');
  spinner.id = 'uniq-native-google-spinner';
  spinner.style.display = 'none';
  spinner.style.width = '14px';
  spinner.style.height = '14px';
  spinner.style.border = '2px solid rgba(0,0,0,0.25)';
  spinner.style.borderTopColor = '#000';
  spinner.style.borderRadius = '50%';
  spinner.style.animation = 'uniq-google-spin 0.8s linear infinite';

  if (!document.getElementById('uniq-google-spin-style')) {
    var style = document.createElement('style');
    style.id = 'uniq-google-spin-style';
    style.textContent = '@keyframes uniq-google-spin { from { transform: rotate(0deg);} to { transform: rotate(360deg);} }';
    document.head.appendChild(style);
  }

  btn.appendChild(icon);
  btn.appendChild(label);
  btn.appendChild(spinner);

  btn.addEventListener('click', function(e) {
    e.preventDefault();
    if (window.__uniqGoogleLoginPending) return;
    window.__uniqGoogleLoginPending = true;
    btn.disabled = true;
    btn.style.opacity = '0.85';
    if (spinner) spinner.style.display = 'inline-block';
    if (label) label.textContent = 'Bekleyiniz...';
    if (window.UniqNativeAuth && window.UniqNativeAuth.postMessage) {
      window.UniqNativeAuth.postMessage('google_native_login');
    }
  });

  function isVisible(el) {
    if (!el || !el.getBoundingClientRect) return false;
    var r = el.getBoundingClientRect();
    return r.width > 0 && r.height > 0;
  }

  function hideSiteGoogleWidget() {
    var gsi = document.getElementById('googleSignInBtn');
    if (gsi) {
      var wrap = gsi.closest('div') || gsi;
      wrap.style.display = 'none';
    }
  }

  var all = Array.prototype.slice.call(document.querySelectorAll('*'));
  var veyaCandidates = all.filter(function(el) {
    return (el.innerText || '').trim().toLowerCase() === 'veya' && isVisible(el);
  });
  var registerCandidates = all.filter(function(el) {
    var t = (el.innerText || '').trim().toLowerCase();
    return isVisible(el) && (t.indexOf('hesabiniz yok') >= 0 || t.indexOf('kayit ol') >= 0);
  });
  registerCandidates.sort(function(a, b) {
    return a.getBoundingClientRect().top - b.getBoundingClientRect().top;
  });
  var registerEl = registerCandidates.length ? registerCandidates[0] : null;

  var veyaEl = null;
  if (veyaCandidates.length) {
    veyaCandidates.sort(function(a, b) {
      return a.getBoundingClientRect().top - b.getBoundingClientRect().top;
    });
    if (registerEl) {
      var regTop = registerEl.getBoundingClientRect().top;
      var best = veyaCandidates.filter(function(el) {
        return el.getBoundingClientRect().top < regTop;
      });
      veyaEl = best.length ? best[best.length - 1] : veyaCandidates[0];
    } else {
      veyaEl = veyaCandidates[0];
    }
  }

  var row = document.createElement('div');
  row.style.width = '100%';
  row.style.display = 'flex';
  row.style.justifyContent = 'center';
  row.style.padding = '0 10px';
  row.appendChild(btn);

  if (veyaEl) {
    veyaEl.insertAdjacentElement('afterend', row);
    hideSiteGoogleWidget();
    return;
  }
  if (registerEl) {
    registerEl.insertAdjacentElement('beforebegin', row);
    hideSiteGoogleWidget();
    return;
  }
  var form = document.querySelector('form');
  if (form && form.parentElement) {
    form.parentElement.appendChild(row);
    hideSiteGoogleWidget();
    return;
  }
  document.body.appendChild(row);
  hideSiteGoogleWidget();
})();
''');
    } catch (_) {
      // Best effort only.
    }
  }

  bool _isGoogleSignInConfigError(Object e) {
    if (e is GoogleSignInException) {
      return e.code == GoogleSignInExceptionCode.clientConfigurationError ||
          e.code == GoogleSignInExceptionCode.providerConfigurationError;
    }
    final s = e.toString().toLowerCase();
    return s.contains('developer_error') ||
        s.contains('apiexception: 10') ||
        s.contains('code: 10') ||
        s.contains('sign_in_failed');
  }

  String _googleLoginErrorMessage(Object e) {
    if (e is GoogleSignInException) {
      if (e.code == GoogleSignInExceptionCode.canceled) {
        return 'Hesap secildi ama giris iptal edildi. '
            'Cogu zaman Google Cloud Android istemcisinde Play SHA-1 eksiktir '
            '(01:AE:2D:2C:...). Firebase yeterli olmayabilir.';
      }
      return 'Google hata (${e.code.name}): ${e.description ?? e}';
    }
    final detail = e.toString();
    if (defaultTargetPlatform == TargetPlatform.iOS &&
        _isGoogleSignInConfigError(e)) {
      return 'iOS Google istemci hatasi. Google Cloud > Credentials > iOS '
          'client bundle ID: com.uniqperformance.mobile olmali.';
    }
    if (_isGoogleSignInConfigError(e)) {
      return 'Imza/istemci hatasi. Google Cloud > Credentials > Android '
          'istemcisine Play SHA-1 ekleyin: 01:AE:2D:2C:60:44:B0:...';
    }
    return detail.isEmpty ? 'Google girisi baslatilamadi.' : detail;
  }

  void _showGoogleLoginErrorSnackBar(Object e) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_googleLoginErrorMessage(e)),
        duration: const Duration(seconds: 8),
      ),
    );
  }

  /// Native imza hatasinda site uzerindeki web Google dugmesini dener (Android).
  /// iOS WebView icinde Google web girisi guvenilir degil; native kullanilir.
  Future<bool> _triggerWebGoogleSignIn() async {
    if (defaultTargetPlatform == TargetPlatform.iOS) return false;
    if (_controller == null) return false;
    try {
      await _controller!.runJavaScript('''
(function() {
  window.__uniqNativeGoogleBridgeInstalled = false;
  window.__uniqGoogleLoginPending = false;
  var gsi = document.getElementById('googleSignInBtn');
  if (!gsi) return;
  var btn = gsi.querySelector('div[role="button"]');
  if (btn) { btn.click(); return; }
  var iframe = gsi.querySelector('iframe');
  if (iframe) { iframe.click(); return; }
  gsi.click();
})();
''');
      if (!mounted) return true;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Web Google girisi deneniyor...'),
          duration: Duration(seconds: 2),
        ),
      );
      return true;
    } catch (err) {
      debugPrint('[AUTH] web Google fallback failed: $err');
      return false;
    }
  }

  Future<void> _handleNativeGoogleLogin() async {
    if (_controller == null) return;
    if (_googleLoginInProgress) return;
    _googleLoginInProgress = true;
    await _setInlineGoogleButtonLoading(true);
    try {
      if (!_googleInitialized) {
        await _initGoogleSignIn();
      }
      if (!_googleInitialized) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _lastGoogleInitError == null
                  ? 'Google Sign-In baslatilamadi.'
                  : 'Google Sign-In baslatilamadi: $_lastGoogleInitError',
            ),
          ),
        );
        return;
      }

      final account = await _googleSignIn.authenticate(
        scopeHint: const ['email', 'profile', 'openid'],
      );

      final idToken = account.authentication.idToken;
      if (idToken == null || idToken.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Google token alinamadi.')),
        );
        return;
      }

      final tokenLiteral = idToken.replaceAll(r'\', r'\\').replaceAll("'", r"\'");
      await _controller!.runJavaScript('''
(async function() {
  try {
    var idToken = '$tokenLiteral';
    var response = await fetch('$_googleLoginEndpoint', {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      credentials: 'include',
      body: 'idToken=' + encodeURIComponent(idToken)
    });

    var data = await response.json();
    if (data && data.success) {
      var redirect = data.redirectUrl || '/Home/Index';
      if (redirect.indexOf('http') !== 0) {
        redirect = 'https://www.uniqperformance.com.tr' + redirect;
      }
      window.location.href = redirect;
      return;
    }

    var message = (data && data.message) ? data.message : 'Google giris basarisiz.';
    alert(message);
  } catch (e) {
    alert('Google giris sirasinda hata olustu.');
  }
})();
''');
    } on GoogleSignInException catch (e) {
      debugPrint('[AUTH] GoogleSignInException: ${e.code} $e');
      if (_controller != null) {
        final webOk = await _triggerWebGoogleSignIn();
        if (webOk) return;
      }
      if (!mounted) return;
      _showGoogleLoginErrorSnackBar(e);
    } catch (e) {
      debugPrint('[AUTH] Google login failed: $e');
      if (_controller != null) {
        final webOk = await _triggerWebGoogleSignIn();
        if (webOk) return;
      }
      if (!mounted) return;
      _showGoogleLoginErrorSnackBar(e);
    } finally {
      _googleLoginInProgress = false;
      await _setInlineGoogleButtonLoading(false);
    }
  }

  Future<void> _setInlineGoogleButtonLoading(bool loading) async {
    if (_controller == null) return;
    try {
      final loadingLiteral = loading ? 'true' : 'false';
      await _controller!.runJavaScript('''
(function() {
  var loading = $loadingLiteral;
  var btn = document.getElementById('uniq-native-google-btn');
  var label = document.getElementById('uniq-native-google-btn-label');
  var spinner = document.getElementById('uniq-native-google-spinner');
  window.__uniqGoogleLoginPending = loading;
  if (!btn) return;
  btn.disabled = loading;
  btn.style.opacity = loading ? '0.85' : '1';
  btn.style.cursor = loading ? 'not-allowed' : 'pointer';
  if (spinner) spinner.style.display = loading ? 'inline-block' : 'none';
  if (label) label.textContent = loading ? 'Bekleyiniz...' : 'Google ile giris yap';
})();
''');
    } catch (_) {
      // Best effort only.
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (_controller != null) {
          if (await _controller!.canGoBack()) {
            _controller!.goBack();
          } else {
            _loadHome();
          }
        }
      },
      child: Scaffold(
        body: _supportsInAppWebView
            ? (_hasError
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.wifi_off, size: 48),
                          const SizedBox(height: 12),
                          const Text(
                            'Sayfa su an acilamadi.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _errorDetail.isEmpty
                                ? 'Lutfen tekrar deneyin.'
                                : _errorDetail,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 13,
                              color: Colors.white70,
                            ),
                          ),
                          const SizedBox(height: 16),
                          FilledButton.icon(
                            onPressed: _loadHome,
                            icon: const Icon(Icons.refresh),
                            label: const Text('Tekrar dene'),
                          ),
                          const SizedBox(height: 8),
                          TextButton.icon(
                            onPressed: () => launchUrl(
                              _home,
                              mode: LaunchMode.externalApplication,
                            ),
                            icon: const Icon(Icons.open_in_new),
                            label: const Text('Tarayicida ac'),
                          ),
                        ],
                      ),
                    ),
                  )
                : Stack(
                    children: [
                      WebViewWidget(controller: _controller!),
                      if (_loading)
                        const Center(child: CircularProgressIndicator()),
                      if (_showBootSplash)
                        Container(
                          color: const Color(0xFF07090F),
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 24,
                                  ),
                                  child: SizedBox(
                                    width: 260,
                                    height: 92,
                                    child: SvgPicture.network(
                                      _brandLogoUrl,
                                      fit: BoxFit.contain,
                                      placeholderBuilder: (context) =>
                                          const Center(
                                        child: Text(
                                          'UNIQ',
                                          style: TextStyle(
                                            fontSize: 44,
                                            fontWeight: FontWeight.w800,
                                            letterSpacing: 2,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 10),
                                const Text(
                                  'Performance • Strength • Flow',
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 13,
                                  ),
                                ),
                                const SizedBox(height: 18),
                                Container(
                                  width: 180,
                                  height: 4,
                                  decoration: BoxDecoration(
                                    color: Colors.white12,
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(999),
                                    child: const LinearProgressIndicator(
                                      minHeight: 4,
                                      backgroundColor: Colors.transparent,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        Color(0xFFC8FF00),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ))
            : Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.open_in_browser, size: 48),
                      const SizedBox(height: 12),
                      const Text(
                        'Bu platformda uygulama ici WebView desteklenmiyor.',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: () => launchUrl(
                          _home,
                          mode: LaunchMode.externalApplication,
                        ),
                        icon: const Icon(Icons.language),
                        label: const Text('UNIQ sitesini ac'),
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}

class NotificationInboxPage extends StatefulWidget {
  const NotificationInboxPage({
    super.key,
    required this.items,
    required this.onRefresh,
    required this.onOpen,
  });

  final List<NotificationInboxItem> items;
  final Future<List<NotificationInboxItem>> Function() onRefresh;
  final Future<void> Function(NotificationInboxItem item) onOpen;

  @override
  State<NotificationInboxPage> createState() => _NotificationInboxPageState();
}

class _NotificationInboxPageState extends State<NotificationInboxPage> {
  late List<NotificationInboxItem> _items;

  @override
  void initState() {
    super.initState();
    _items = [...widget.items];
  }

  Future<void> _handleRefresh() async {
    final fresh = await widget.onRefresh();
    if (!mounted) return;
    setState(() {
      _items = [...fresh];
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Bildirimler')),
      body: RefreshIndicator(
        onRefresh: _handleRefresh,
        child: _items.isEmpty
            ? ListView(
                children: const [
                  SizedBox(height: 120),
                  Center(
                    child: Text(
                      'Bildirim bulunamadi',
                      style: TextStyle(color: Colors.white70),
                    ),
                  ),
                ],
              )
            : ListView.separated(
                itemCount: _items.length,
                separatorBuilder: (_, _) =>
                    const Divider(height: 1, color: Colors.white12),
                itemBuilder: (context, index) {
                  final item = _items[index];
                  return ListTile(
                    title: Text(
                      item.title.isEmpty ? 'Bildirim' : item.title,
                      style: TextStyle(
                        fontWeight: item.isOpened
                            ? FontWeight.w500
                            : FontWeight.w700,
                      ),
                    ),
                    subtitle: Text(
                      item.body.isEmpty ? '-' : item.body,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: item.isOpened
                        ? null
                        : const Icon(
                            Icons.circle,
                            size: 10,
                            color: Color(0xFFC8FF00),
                          ),
                    onTap: () async {
                      await widget.onOpen(item);
                      if (!mounted) return;
                      setState(() {
                        _items[index] = item.copyWith(
                          isOpened: true,
                          openedAt: DateTime.now(),
                        );
                      });
                    },
                  );
                },
              ),
      ),
    );
  }
}
