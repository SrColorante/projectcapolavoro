import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:vibration/vibration.dart';
import 'package:shared_preferences/shared_preferences.dart';

class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const initSettings = InitializationSettings(android: androidSettings, iOS: iosSettings);

    await _notificationsPlugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (response) {
        // Action to trigger when user taps the local notification
      },
    );
    _initialized = true;
  }

  Future<void> triggerVibration() async {
    final prefs = await SharedPreferences.getInstance();
    final vibrationEnabled = prefs.getBool('notifications_vibration_enabled') ?? true;
    if (vibrationEnabled) {
      if (await Vibration.hasVibrator() ?? false) {
        // double pulse vibration: wait 0ms, vibrate 150ms, wait 100ms, vibrate 250ms
        Vibration.vibrate(pattern: [0, 150, 100, 250]);
      }
    }
  }

  Future<void> showMessageNotification({
    required int id,
    required String senderName,
    required String messageText,
    bool isGroup = false,
  }) async {
    await initialize();
    await triggerVibration();

    final channelId = isGroup ? 'group_messages' : 'direct_messages';
    final channelName = isGroup ? 'Messaggi di Gruppo' : 'Messaggi Diretti';
    final channelDesc = isGroup 
        ? 'Notifiche relative alle chat di gruppo' 
        : 'Notifiche relative ai messaggi diretti uno-a-uno';

    final androidDetails = AndroidNotificationDetails(
      channelId,
      channelName,
      channelDescription: channelDesc,
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    final details = NotificationDetails(android: androidDetails, iOS: iosDetails);
    
    await _notificationsPlugin.show(
      id,
      isGroup ? '$senderName nel gruppo' : senderName,
      messageText,
      details,
    );
  }

  Future<void> showCallNotification({
    required int id,
    required String callerName,
  }) async {
    await initialize();
    await triggerVibration();

    const androidDetails = AndroidNotificationDetails(
      'voice_calls',
      'Chiamate Vocali',
      channelDescription: 'Notifiche relative a chiamate vocali in arrivo',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    final details = NotificationDetails(android: androidDetails, iOS: iosDetails);

    await _notificationsPlugin.show(
      id,
      'Chiamata in arrivo',
      '$callerName ti sta chiamando...',
      details,
    );
  }
}
