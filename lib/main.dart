import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'package:vibration/vibration.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: const FirebaseOptions(
      apiKey: "AIzaSyAFXfHI50_KX059_DmcdW_W6iVHTgpzt",
      authDomain: "time-capsule-app-9062d.firebaseapp.com",
      projectId: "time-capsule-app-9062d",
      storageBucket: "time-capsule-app-9062d.firebasestorage.app",
      messagingSenderId: "519758677282",
      appId: "1:519758677282:web:70f6c9500T859a70d117b",
    ),
  );

  const AndroidInitializationSettings initializationSettingsAndroid =
      AndroidInitializationSettings('@mipmap/ic_launcher');
  const InitializationSettings initializationSettings =
      InitializationSettings(android: initializationSettingsAndroid);

  await flutterLocalNotificationsPlugin.initialize(initializationSettings);

  runApp(const OurieApp());
}

class OurieApp extends StatelessWidget {
  const OurieApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Ourie',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0F172A),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF7C3AED),
          surface: Color(0xFF1E293B),
        ),
      ),
      home: const MainNavigationScreen(),
    );
  }
}

// ---------------- ナビゲーション & 着信監視 ----------------
class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  Timer? _checkTimer;
  bool _isCallingCurrently = false;
  int _selectedIndex = 0;

  final List<Widget> _screens = [
    const RecordScreen(),
    const CapsuleListScreen(),
  ];

  @override
  void initState() {
    super.initState();
    _requestPermissions();
    _checkTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _checkForIncomingCalls();
    });
  }

  Future<void> _requestPermissions() async {
    await Permission.notification.request();
    await Permission.scheduleExactAlarm.request();
  }

  @override
  void dispose() {
    _checkTimer?.cancel();
    super.dispose();
  }

  Future<void> _checkForIncomingCalls() async {
    if (_isCallingCurrently) return;

    final now = DateTime.now();
    try {
      final snapshot =
          await FirebaseFirestore.instance.collection('capsules').get();
      for (var doc in snapshot.docs) {
        final data = doc.data();
        final Timestamp? timestamp = data['targetDate'];
        final DateTime targetDate = timestamp?.toDate() ?? DateTime.now();
        final bool iscalled = data['iscalled'] ?? false;
        final String audioUrl = data['audioUrl'] ?? '';
        final String senderName = data['senderName'] ?? '過去の自分';

        if (now.isAfter(targetDate) && !iscalled && !_isCallingCurrently) {
          _triggerIncomingCall(doc.id, audioUrl, senderName);
          break;
        }
      }
    } catch (e) {
      debugPrint('監視エラー: $e');
    }
  }

  Future<void> _triggerIncomingCall(
      String docId, String audioUrl, String senderName) async {
    _isCallingCurrently = true;

    await FirebaseFirestore.instance.collection('capsules').doc(docId).update({
      'iscalled': true,
    });

    if (!mounted) return;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return IncomingCallOverlay(
          docId: docId,
          audioUrl: audioUrl,
          senderName: senderName,
        );
      },
    );

    _isCallingCurrently = false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(child: _screens[_selectedIndex]),
      bottomNavigationBar: NavigationBar(
        backgroundColor: const Color(0xFF0F172A),
        indicatorColor: const Color(0xFF7C3AED).withOpacity(0.3),
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) =>
            setState(() => _selectedIndex = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.mic_none, color: Color(0xFF94A3B8)),
            selectedIcon: Icon(Icons.mic, color: Color(0xFFA78BFA)),
            label: 'カプセル作成',
          ),
          NavigationDestination(
            icon: Icon(Icons.history_toggle_off, color: Color(0xFF94A3B8)),
            selectedIcon: Icon(Icons.history, color: Color(0xFFA78BFA)),
            label: '蓄積履歴',
          ),
        ],
      ),
    );
  }
}

// ---------------- 画面1: カプセル作成 ----------------
class RecordScreen extends StatefulWidget {
  const RecordScreen({super.key});

  @override
  State<RecordScreen> createState() => _RecordScreenState();
}

class _RecordScreenState extends State<RecordScreen> {
  final TextEditingController _senderController =
      TextEditingController(text: '半年前の自分');
  DateTime? _selectedDateTime = DateTime.now().add(const Duration(minutes: 5));
  bool _isSaving = false;

  final FlutterSoundRecorder _soundRecorder = FlutterSoundRecorder();
  bool _isRecorderInited = false;
  bool _isRecording = false;
  String? _recordedPath;

  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isPlayingSample = false;

  @override
  void initState() {
    super.initState();
    _initRecorder();
  }

  Future<void> _initRecorder() async {
    await _soundRecorder.openRecorder();
    setState(() => _isRecorderInited = true);
  }

  @override
  void dispose() {
    _senderController.dispose();
    _soundRecorder.closeRecorder();
    _audioPlayer.dispose();
    super.dispose();
  }

  Future<void> _toggleRecording() async {
    if (!_isRecorderInited) return;

    try {
      if (_isRecording) {
        final path = await _soundRecorder.stopRecorder();
        setState(() {
          _isRecording = false;
          _recordedPath = path;
        });
      } else {
        final status = await Permission.microphone.request();
        if (status != PermissionStatus.granted) return;

        final dir = await getApplicationDocumentsDirectory();
        final filePath =
            '${dir.path}/capsule_${DateTime.now().millisecondsSinceEpoch}.aac';

        await _soundRecorder.startRecorder(
          toFile: filePath,
          codec: Codec.aacADTS,
        );

        setState(() {
          _isRecording = true;
          _recordedPath = null;
        });
      }
    } catch (e) {
      debugPrint('録音エラー: $e');
    }
  }

  Future<void> _playRecordedAudio() async {
    if (_recordedPath == null) return;

    if (_isPlayingSample) {
      await _audioPlayer.stop();
      setState(() => _isPlayingSample = false);
    } else {
      setState(() => _isPlayingSample = true);
      await _audioPlayer.play(DeviceFileSource(_recordedPath!));
      _audioPlayer.onPlayerComplete.listen((_) {
        if (mounted) setState(() => _isPlayingSample = false);
      });
    }
  }

  void _setOffsetTime(int seconds) {
    setState(() {
      _selectedDateTime = DateTime.now().add(Duration(seconds: seconds));
    });
  }

  Future<void> _saveCapsule() async {
    if (_selectedDateTime == null || _recordedPath == null) return;

    final senderName = _senderController.text.trim().isEmpty
        ? '過去の自分'
        : _senderController.text.trim();

    setState(() => _isSaving = true);

    try {
      await FirebaseFirestore.instance.collection('capsules').add({
        'senderName': senderName,
        'targetDate': Timestamp.fromDate(_selectedDateTime!),
        'creationDate': FieldValue.serverTimestamp(),
        'status': 'sealed',
        'iscalled': false,
        'audioUrl': _recordedPath!,
        'replyAudioUrl': '',
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('未来へタイムカプセルを飛ばしました！🌟'),
          backgroundColor: Color(0xFF7C3AED),
        ),
      );

      setState(() {
        _recordedPath = null;
      });
    } catch (e) {
      debugPrint('保存エラー: $e');
    } finally {
      setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF7C3AED),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.call_received,
                    color: Colors.white, size: 20),
              ),
              const SizedBox(width: 10),
              const Text(
                'Ourie',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color(0xFF4C1D95).withOpacity(0.5),
                  const Color(0xFF1E293B),
                ],
              ),
              borderRadius: BorderRadius.circular(20),
              border:
                  Border.all(color: const Color(0xFF7C3AED).withOpacity(0.3)),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.auto_awesome,
                        color: Color(0xFFA78BFA), size: 18),
                    SizedBox(width: 6),
                    Text(
                      '未来の自分へ肉声を遺す',
                      style:
                          TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                SizedBox(height: 6),
                Text(
                  '指定した日時にスマホに着信音が鳴り響き、過去のあなたから本物の「電話」がかかってきます。',
                  style: TextStyle(fontSize: 12, color: Color(0xFFCBD5E1)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const Text('着信時の発信者名',
              style: TextStyle(fontSize: 12, color: Color(0xFFCBD5E1))),
          const SizedBox(height: 6),
          TextField(
            controller: _senderController,
            style: const TextStyle(fontSize: 14),
            decoration: InputDecoration(
              filled: true,
              fillColor: const Color(0xFF1E293B),
              hintText: '例: 1年前の自分、ハタチの俺',
              hintStyle: const TextStyle(color: Color(0xFF64748B)),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0xFF334155)),
            ),
            child: Column(
              children: [
                GestureDetector(
                  onTap: _toggleRecording,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _isRecording
                          ? Colors.redAccent
                          : const Color(0xFF7C3AED),
                      boxShadow: [
                        BoxShadow(
                          color: (_isRecording
                                  ? Colors.red
                                  : const Color(0xFF7C3AED))
                              .withOpacity(0.4),
                          blurRadius: 20,
                          spreadRadius: 2,
                        )
                      ],
                    ),
                    child: Icon(
                      _isRecording ? Icons.stop : Icons.mic,
                      color: Colors.white,
                      size: 36,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  _isRecording ? '録音中... もう一度押して完了' : 'マイクボタンを押して録音開始',
                  style:
                      const TextStyle(fontSize: 12, color: Color(0xFFCBD5E1)),
                ),
                if (_recordedPath != null && !_isRecording) ...[
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: _playRecordedAudio,
                    icon:
                        Icon(_isPlayingSample ? Icons.pause : Icons.play_arrow),
                    label: Text(_isPlayingSample ? '停止' : '録音プレビュー再生'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF4C1D95),
                      foregroundColor: Colors.white,
                    ),
                  )
                ]
              ],
            ),
          ),
          const SizedBox(height: 20),
          const Text('お届け日時を指定（未来の着信日時）',
              style: TextStyle(fontSize: 12, color: Color(0xFFCBD5E1))),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _setOffsetTime(10),
                  child: const Text('10秒後', style: TextStyle(fontSize: 11)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _setOffsetTime(60),
                  child: const Text('1分後', style: TextStyle(fontSize: 11)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _setOffsetTime(86400),
                  child: const Text('明日', style: TextStyle(fontSize: 11)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton.icon(
              onPressed:
                  (_recordedPath != null && !_isSaving) ? _saveCapsule : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF7C3AED),
                disabledBackgroundColor: const Color(0xFF1E293B),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              icon: const Icon(Icons.send, size: 18),
              label: Text(
                _isSaving ? '送信中...' : '未来へタイムカプセルを飛ばす',
                style:
                    const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              ),
            ),
          )
        ],
      ),
    );
  }
}

// ---------------- 画面2: 蓄積履歴 ----------------
class CapsuleListScreen extends StatelessWidget {
  const CapsuleListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '蓄積履歴 & 封印カプセル',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('capsules')
                  .orderBy('targetDate', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final docs = snapshot.data!.docs;
                if (docs.isEmpty) {
                  return const Center(
                    child: Text('現在セットされているカプセルはありません。',
                        style: TextStyle(color: Color(0xFF64748B))),
                  );
                }

                return ListView.builder(
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final data = docs[index].data() as Map<String, dynamic>;
                    final Timestamp? ts = data['targetDate'];
                    final DateTime targetDate = ts?.toDate() ?? DateTime.now();
                    final String senderName = data['senderName'] ?? '過去の自分';

                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E293B),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFF334155)),
                      ),
                      child: Row(
                        children: [
                          const CircleAvatar(
                            backgroundColor: Color(0xFF4C1D95),
                            child: Icon(Icons.call_received,
                                color: Colors.white, size: 20),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(senderName,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold)),
                                const SizedBox(height: 4),
                                Text(
                                  '着信予定: ${targetDate.month}/${targetDate.day} ${targetDate.hour}:${targetDate.minute.toString().padLeft(2, '0')}',
                                  style: const TextStyle(
                                      fontSize: 12, color: Color(0xFF94A3B8)),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline,
                                color: Color(0xFF64748B)),
                            onPressed: () {
                              FirebaseFirestore.instance
                                  .collection('capsules')
                                  .doc(docs[index].id)
                                  .delete();
                            },
                          )
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          )
        ],
      ),
    );
  }
}

// ---------------- フル画面 着信オーバーレイ ----------------
class IncomingCallOverlay extends StatefulWidget {
  final String docId;
  final String audioUrl;
  final String senderName;

  const IncomingCallOverlay({
    super.key,
    required this.docId,
    required this.audioUrl,
    required this.senderName,
  });

  @override
  State<IncomingCallOverlay> createState() => _IncomingCallOverlayState();
}

class _IncomingCallOverlayState extends State<IncomingCallOverlay> {
  bool _isConnected = false;
  int _callTimer = 0;
  Timer? _timer;

  final AudioPlayer _ringtonePlayer = AudioPlayer();
  final AudioPlayer _voicePlayer = AudioPlayer();

  @override
  void initState() {
    super.initState();
    _startRingtone();
  }

  Future<void> _startRingtone() async {
    try {
      await _ringtonePlayer.setReleaseMode(ReleaseMode.loop);
      await _ringtonePlayer.play(UrlSource(
          "https://assets.mixkit.co/active_storage/sfx/2869/2869-preview.mp3"));
      if (await Vibration.hasVibrator() == true) {
        Vibration.vibrate(pattern: [0, 1000, 1000], repeat: 0);
      }
    } catch (e) {
      debugPrint('着信音エラー: $e');
    }
  }

  Future<void> _answerCall() async {
    Vibration.cancel();
    await _ringtonePlayer.stop();

    setState(() => _isConnected = true);

    if (widget.audioUrl.isNotEmpty) {
      await _voicePlayer.play(DeviceFileSource(widget.audioUrl));
    }

    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() => _callTimer++);
    });
  }

  void _closeCall() {
    Vibration.cancel();
    _timer?.cancel();
    _ringtonePlayer.stop();
    _voicePlayer.stop();
    Navigator.pop(context);
  }

  @override
  void dispose() {
    Vibration.cancel();
    _timer?.cancel();
    _ringtonePlayer.dispose();
    _voicePlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                children: [
                  const SizedBox(height: 40),
                  Container(
                    width: 100,
                    height: 100,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [Color(0xFF7C3AED), Color(0xFF6366F1)],
                      ),
                    ),
                    child:
                        const Icon(Icons.person, size: 50, color: Colors.white),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    widget.senderName,
                    style: const TextStyle(
                        fontSize: 28, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _isConnected
                        ? '通話中: ${(_callTimer ~/ 60).toString().padLeft(2, '0')}:${(_callTimer % 60).toString().padLeft(2, '0')}'
                        : '未来からの着信...',
                    style: TextStyle(
                      fontSize: 14,
                      color: _isConnected
                          ? Colors.emeraldAccent
                          : const Color(0xFFA78BFA),
                    ),
                  ),
                ],
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  FloatingActionButton.large(
                    heroTag: 'decline',
                    onPressed: _closeCall,
                    backgroundColor: Colors.redAccent,
                    shape: const CircleBorder(),
                    child: const Icon(Icons.call_end, size: 36),
                  ),
                  if (!_isConnected)
                    FloatingActionButton.large(
                      heroTag: 'accept',
                      onPressed: _answerCall,
                      backgroundColor: Colors.emerald,
                      shape: const CircleBorder(),
                      child: const Icon(Icons.phone_in_talk, size: 36),
                    ),
                ],
              )
            ],
          ),
        ),
      ),
    );
  }
}
