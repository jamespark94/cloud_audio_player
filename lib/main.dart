import 'dart:async';
import 'dart:io';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import 'services/account_manager.dart';
import 'services/audio_player_service.dart';
import 'services/cloud_audio_handler.dart';
import 'services/folder_shortcut_manager.dart';
import 'services/google_auth_manager.dart';
import 'services/local_stream_proxy.dart';
import 'services/playback_history_service.dart';
import 'ui/screens/home_screen.dart';
import 'utils/platform_utils.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    await windowManager.ensureInitialized();
  }

  // 1. 고음질 오디오 재생 엔진 (libmpv 기반 media_kit) 초기화
  MediaKit.ensureInitialized();

  // 2. 플랫폼 환경 감지 초기화
  await PlatformUtils.initialize();

  // 3. Google Sign-In 이전 로그인 세션 비차단 무음 복구
  unawaited(GoogleAuthManager().initialize());

  // 4. 클라우드 오디오 구간 탐색(Range), 무음 토큰 갱신, 다음 곡 Prefetch를 위한 로컬 스트림 프록시 기동
  await LocalStreamProxy.instance.start();

  // 5. Android/iOS 화면 꺼짐(백그라운드) MediaSession 서비스 초기화
  CloudAudioHandler? audioHandler;
  if (Platform.isAndroid || Platform.isIOS) {
    try {
      audioHandler = await AudioService.init(
        builder: () => CloudAudioHandler(),
        config: const AudioServiceConfig(
          androidNotificationChannelId:
              'com.example.cloud_audio_player.channel.audio',
          androidNotificationChannelName: '클라우드 오디오 스트리밍',
          androidNotificationOngoing: true,
          androidStopForegroundOnPause: true,
        ),
      );
    } catch (e) {
      debugPrint('[Main] AudioService 초기화 예외: $e');
    }
  }

  final accountManager = AccountManager();
  await accountManager.loadAccounts();

  await AudioPlayerService.instance.initialize(
    accountManager: accountManager,
    audioHandler: audioHandler,
  );

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(
          value: accountManager,
        ),
        ChangeNotifierProvider(
          create: (_) => FolderShortcutManager()..loadShortcuts(),
        ),
        ChangeNotifierProvider.value(
          value: PlaybackHistoryService.instance,
        ),
        ChangeNotifierProvider.value(
          value: AudioPlayerService.instance,
        ),
      ],
      child: const CloudAudioPlayerApp(),
    ),
  );
}

class CloudAudioPlayerApp extends StatelessWidget {
  const CloudAudioPlayerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Cloud Audio Player',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.tealAccent,
          brightness: Brightness.dark,
          surface: const Color(0xFF14171F),
        ),
        scaffoldBackgroundColor: const Color(0xFF0D0F14),
        cardColor: const Color(0xFF1B202B),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF14171F),
          elevation: 0,
          centerTitle: false,
        ),
        snackBarTheme: SnackBarThemeData(
          backgroundColor: Colors.black.withAlpha(160),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(color: Colors.white.withAlpha(50), width: 0.8),
          ),
          contentTextStyle: const TextStyle(color: Colors.white, fontSize: 13),
        ),
      ),
      home: const HomeScreen(),
    );
  }
}
