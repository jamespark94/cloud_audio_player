import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/audio_player_service.dart';

/// 화면을 끄고 음악/오디오북을 들을 때 유용한 취침 예약 타이머 설정 다이얼로그
class SleepTimerDialog extends StatelessWidget {
  const SleepTimerDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog(
      context: context,
      builder: (_) => const SleepTimerDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final player = context.watch<AudioPlayerService>();
    final remaining = player.remainingSleepTime;

    final presets = <MapEntry<String, Duration>>[
      const MapEntry('15분 후 정지', Duration(minutes: 15)),
      const MapEntry('30분 후 정지', Duration(minutes: 30)),
      const MapEntry('45분 후 정지', Duration(minutes: 45)),
      const MapEntry('60분 (1시간) 후 정지', Duration(minutes: 60)),
      const MapEntry('90분 후 정지', Duration(minutes: 90)),
      const MapEntry('120분 (2시간) 후 정지', Duration(minutes: 120)),
    ];

    return AlertDialog(
      backgroundColor: const Color(0xFF1B202C),
      title: const Row(
        children: [
          Icon(Icons.bedtime_rounded, color: Colors.amberAccent),
          SizedBox(width: 10),
          Text(
            '취침 예약 타이머',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (remaining != null)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.amberAccent.withAlpha(25),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.timer_outlined,
                      color: Colors.amberAccent,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '남은 시간: ${remaining.inMinutes}분 ${remaining.inSeconds.remainder(60)}초',
                        style: const TextStyle(
                          color: Colors.amberAccent,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ListTile(
              leading: Icon(
                Icons.music_off_rounded,
                color: player.stopAfterCurrentTrack
                    ? Colors.tealAccent
                    : Colors.white70,
              ),
              title: const Text('현재 곡까지만 재생 후 정지'),
              trailing: player.stopAfterCurrentTrack
                  ? const Icon(Icons.check_circle, color: Colors.tealAccent)
                  : null,
              onTap: () {
                player.setSleepTimer(stopAfterCurrent: true);
                Navigator.pop(context);
              },
            ),
            const Divider(color: Colors.white12),
            ...presets.map(
              (entry) => ListTile(
                leading: const Icon(
                  Icons.access_time_rounded,
                  color: Colors.white70,
                ),
                title: Text(entry.key),
                onTap: () {
                  player.setSleepTimer(duration: entry.value);
                  Navigator.pop(context);
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        if (remaining != null || player.stopAfterCurrentTrack)
          TextButton(
            onPressed: () {
              player.cancelSleepTimer();
              Navigator.pop(context);
            },
            child: const Text(
              '타이머 해제',
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('닫기'),
        ),
      ],
    );
  }
}
