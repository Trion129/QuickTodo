import 'dart:async';

import 'package:flutter/material.dart';
import 'package:sound_mode/utils/ringer_mode_statuses.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';
import 'package:sound_mode/sound_mode.dart';
import 'package:vibration/vibration.dart';
import 'dart:convert';

import 'package:wakelock_plus/wakelock_plus.dart';

void main() {
  runApp(TodoAutomationApp());
}

class TodoAutomationApp extends StatelessWidget {
  const TodoAutomationApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData.dark().copyWith(scaffoldBackgroundColor: Colors.black),
      home: TaskCreationScreen(),
    );
  }
}

// Models
class Subtask {
  String description;
  int time; // in minutes
  Subtask(this.description, this.time);
}

class Task {
  String prompt;
  List<Subtask> subtasks;
  Task(this.prompt, this.subtasks);
}

// Screens
class TaskCreationScreen extends StatefulWidget {
  const TaskCreationScreen({super.key});

  @override
  _TaskCreationScreenState createState() => _TaskCreationScreenState();
}

class _TaskCreationScreenState extends State<TaskCreationScreen> {
  final TextEditingController _promptController = TextEditingController();
  List<Task> history = [];

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final historyJson = prefs.getString('task_history');
    if (historyJson != null) {
      final List<dynamic> historyList = json.decode(historyJson);
      setState(() {
        history = historyList
            .map((item) => Task(
                item['prompt'],
                (item['subtasks'] as List)
                    .map((sub) => Subtask(sub['description'], sub['time']))
                    .toList()))
            .toList();
      });
    }
  }

  Future<void> _saveHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final historyJson = json.encode(history
        .map((task) => {
              'prompt': task.prompt,
              'subtasks': task.subtasks
                  .map((sub) =>
                      {'description': sub.description, 'time': sub.time})
                  .toList()
            })
        .toList());
    await prefs.setString('task_history', historyJson);
  }

  Future<void> _generateSubtasks(String prompt) async {
    final prefs = await SharedPreferences.getInstance();
    final apiKey = prefs.getString('gemini_api_key');
    final userContext = prefs.getString('user_context') ?? '';
    if (apiKey == null || apiKey.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Please set your Gemini API Key in settings.')),
      );
      return;
    }
    final model =
        GenerativeModel(model: 'gemini-2.0-flash-lite', apiKey: apiKey);
    final fullPrompt =
        'User context: $userContext\n\nBreak down the task "$prompt" into subtasks with time estimates in minutes(integer). This will be parsed. Do not add anything at end of line. Add a relevant android supported emoji. Format as: "Subtask: [emoji][description] - Time: [minutes (integer)] min"';
    try {
      final response = await model.generateContent([Content.text(fullPrompt)]);
      final lines = response.text?.split('\n');
      final subtasks =
          lines?.where((line) => line.contains('Subtask:')).map((line) {
        final parts = line.split(' - Time: ');
        final description = parts[0].replaceFirst('Subtask: ', '').trim();
        final time = int.parse(parts[1].replaceAll(' min', '').trim());
        return Subtask(description, time);
      }).toList();

      if (subtasks == null || subtasks.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No subtasks generated.')),
        );
        return;
      }
      setState(() {
        history.add(Task(prompt, subtasks));
        _saveHistory();
      });
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) =>
              SubtaskManagementScreen(task: Task(prompt, subtasks)),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error generating subtasks: $e')),
      );
    }
  }

  void _deleteHistoryItem(int index) {
    setState(() {
      history.removeAt(index);
      _saveHistory();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Quick Todo'),
        actions: [
          IconButton(
            icon: Icon(Icons.settings),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => SettingsScreen()),
            ),
          ),
        ],
      ),
      body: Padding(
        padding: EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              controller: _promptController,
              decoration: InputDecoration(labelText: 'Enter the Task'),
            ),
            SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => _generateSubtasks(_promptController.text),
              child: Text('Plan it!'),
            ),
            SizedBox(height: 16),
            Text('History', style: TextStyle(fontSize: 18)),
            Expanded(
              child: ListView.builder(
                itemCount: history.length,
                itemBuilder: (context, index) {
                  return ListTile(
                    trailing: IconButton(
                      icon: Icon(Icons.delete),
                      onPressed: () {
                        setState(() {
                          _deleteHistoryItem(index);
                        });
                      },
                    ),
                    title: Text(history[index].prompt),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) =>
                            SubtaskManagementScreen(task: history[index]),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SubtaskManagementScreen extends StatefulWidget {
  final Task task;
  const SubtaskManagementScreen({super.key, required this.task});

  @override
  _SubtaskManagementScreenState createState() =>
      _SubtaskManagementScreenState();
}

class _SubtaskManagementScreenState extends State<SubtaskManagementScreen> {
  late List<Subtask> subtasks;

  @override
  void initState() {
    super.initState();
    subtasks = widget.task.subtasks;
  }

  void _addSubtask() {
    setState(() {
      subtasks.add(Subtask('New Subtask', 10));
    });
  }

  void _editSubtask(int index, String description, int time) {
    setState(() {
      subtasks[index].description = description;
      subtasks[index].time = time;
    });
  }

  void _removeSubtask(int index) {
    setState(() {
      subtasks.removeAt(index);
    });
  }

  void _rearrangeSubtasks(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex -= 1;
      final Subtask item = subtasks.removeAt(oldIndex);
      subtasks.insert(newIndex, item);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Manage Subtasks'),
      ),
      body: CustomScrollView(
        slivers: [
          SliverReorderableList(
            onReorder: _rearrangeSubtasks,
            itemCount: subtasks.length,
            itemBuilder: (context, index) {
              final subtask = subtasks[index];
              return ListTile(
                key: ValueKey(subtask),
                title: Text(subtask.description),
                subtitle: Text('${subtask.time} min'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: Icon(Icons.edit),
                      onPressed: () => _showEditDialog(index),
                    ),
                    IconButton(
                      icon: Icon(Icons.delete),
                      onPressed: () => _removeSubtask(index),
                    ),
                  ],
                ),
              );
            },
          ),
          SliverPadding(
            padding: EdgeInsets.only(bottom: 100.0), // Extra scrollable space
          ),
        ],
      ),
      floatingActionButton: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FloatingActionButton(
            heroTag: 'add_subtask',
            onPressed: _addSubtask,
            child: Icon(Icons.add),
          ),
          SizedBox(width: 16),
          FloatingActionButton(
            heroTag: 'start_playlist',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => TimerPlaylistScreen(subtasks: subtasks),
              ),
            ),
            child: Icon(Icons.play_arrow),
          ),
        ],
      ),
    );
  }

  void _showEditDialog(int index) {
    final controller = TextEditingController(text: subtasks[index].description);
    final timeController =
        TextEditingController(text: subtasks[index].time.toString());
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Edit Subtask'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controller,
              decoration: InputDecoration(labelText: 'Description'),
            ),
            TextField(
              controller: timeController,
              decoration: InputDecoration(labelText: 'Time (min)'),
              keyboardType: TextInputType.number,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              _editSubtask(
                  index, controller.text, int.parse(timeController.text));
              Navigator.pop(context);
            },
            child: Text('Save'),
          ),
        ],
      ),
    );
  }
}

class TimerPlaylistScreen extends StatefulWidget {
  final List<Subtask> subtasks;
  const TimerPlaylistScreen({super.key, required this.subtasks});

  @override
  _TimerPlaylistScreenState createState() => _TimerPlaylistScreenState();
}

class _TimerPlaylistScreenState extends State<TimerPlaylistScreen> {
  int currentIndex = 0;
  late int _totalDurationSeconds;
  int _elapsedSecondsBeforePause = 0;
  DateTime? _startTime;
  bool isPaused = false;
  Timer? _timer;
  bool _keepScreenOn = false;
  bool hasTriggered = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    if (widget.subtasks.isNotEmpty) {
      _initializeTimerForCurrentSubtask();
      _startTimer();
    }
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _keepScreenOn = prefs.getBool('keep_screen_on') ?? false;
    if (_keepScreenOn) {
      WakelockPlus.enable();
    } else {
      WakelockPlus.disable();
    }
  }

  void _applyScreenWakeLock() async {
    if (_keepScreenOn) {
      WakelockPlus.enable();
    } else {
      WakelockPlus.disable();
    }
  }

  void _initializeTimerForCurrentSubtask() {
    _totalDurationSeconds = widget.subtasks[currentIndex].time * 60;
    _elapsedSecondsBeforePause = 0;
    _startTime = DateTime.now();
    hasTriggered = false;
  }

  @override
  void dispose() {
    _timer?.cancel();
    WakelockPlus.disable();
    super.dispose();
  }

  void _startTimer() {
    _timer?.cancel();
    _applyScreenWakeLock();
    if (!isPaused) {
      _startTime ??= DateTime.now();
      _timer = Timer.periodic(Duration(milliseconds: 200), (timer) async {
        if (mounted) {
          if (!isPaused) {
            final currentRemainingTime = _calculateRemainingTime();
            if (currentRemainingTime <= 0 && !hasTriggered) {
              _playNotificationSound();
              _triggerVibration();
              hasTriggered = true;
            }
            setState(() {});
          } else {
            timer.cancel();
          }
        } else {
          timer.cancel();
        }
      });
    }
  }

  int _calculateRemainingTime() {
    if (_startTime != null) {
      // Timer is running
      final elapsedSinceStart =
          DateTime.now().difference(_startTime!).inSeconds;
      final totalElapsedSeconds =
          _elapsedSecondsBeforePause + elapsedSinceStart;
      return _totalDurationSeconds - totalElapsedSeconds;
    } else {
      // Timer is paused
      return _totalDurationSeconds - _elapsedSecondsBeforePause;
    }
  }

  void _playNotificationSound() async {
    if (await SoundMode.ringerModeStatus == RingerModeStatus.normal) {
      FlutterRingtonePlayer().play(
        android: AndroidSounds.notification,
        ios: IosSounds.glass,
        volume: 0.5,
        asAlarm: true,
      );
    }
  }

  void _triggerVibration() async {
    if (await SoundMode.ringerModeStatus != RingerModeStatus.silent &&
        await Vibration.hasVibrator()) {
      Vibration.vibrate(duration: 500);
    }
  }

  void _nextSubtask() {
    if (currentIndex < widget.subtasks.length - 1) {
      setState(() {
        currentIndex++;
        _initializeTimerForCurrentSubtask();
      });
      _startTimer();
    } else {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => CongratsScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.subtasks.isEmpty) {
      return Scaffold(
        body: Center(child: Text('No subtasks to display')),
      );
    }
    final currentSubtask = widget.subtasks[currentIndex];
    final currentRemainingTime = _calculateRemainingTime();
    final isNegative = currentRemainingTime < 0;
    final absTime = currentRemainingTime.abs();
    final minutes = absTime ~/ 60;
    final seconds = absTime % 60;
    final timeString =
        '${isNegative ? '-' : ''}${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';

    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              currentSubtask.description,
              style: TextStyle(color: Colors.white, fontSize: 20),
            ),
            SizedBox(height: 20),
            Text(
              timeString,
              style: TextStyle(
                color: isNegative ? Colors.red : Colors.white,
                fontSize: 48,
              ),
            ),
            SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: Icon(isPaused ? Icons.play_arrow : Icons.pause,
                      color: Colors.white),
                  onPressed: () {
                    setState(() {
                      isPaused = !isPaused;
                      if (!isPaused) {
                        _startTime = DateTime.now();
                        _startTimer();
                      } else {
                        if (_startTime != null) {
                          final elapsedSinceStart =
                              DateTime.now().difference(_startTime!).inSeconds;
                          _elapsedSecondsBeforePause += elapsedSinceStart;
                        }
                        _startTime = null;
                        _timer?.cancel();
                        _applyScreenWakeLock();
                      }
                    });
                  },
                ),
                IconButton(
                  icon: Icon(Icons.check, color: Colors.white),
                  onPressed: _nextSubtask,
                ),
                IconButton(
                  icon: Icon(Icons.stop, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class CongratsScreen extends StatelessWidget {
  const CongratsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle, color: Colors.green, size: 100),
            SizedBox(height: 20),
            Text('All done!',
                style: TextStyle(color: Colors.white, fontSize: 24)),
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: () => Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (context) => TaskCreationScreen()),
                (route) => false,
              ),
              child: Text('Awesome!'),
            ),
          ],
        ),
      ),
    );
  }
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  _SettingsScreenState createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final TextEditingController _apiKeyController = TextEditingController();
  final TextEditingController _contextController = TextEditingController();
  bool _keepScreenOn = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _apiKeyController.text = prefs.getString('gemini_api_key') ?? '';
    _contextController.text = prefs.getString('user_context') ?? '';
    setState(() {
      _keepScreenOn = prefs.getBool('keep_screen_on') ?? false;
    });
  }

  Future<void> _launchGeminiAIStudioUrl() async {
    final Uri url = Uri.parse('https://aistudio.google.com/app/apikey');
    if (!await launchUrl(url)) {
      throw Exception('Could not launch $url');
    }
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('gemini_api_key', _apiKeyController.text);
    await prefs.setString('user_context', _contextController.text);
    await prefs.setBool('keep_screen_on', _keepScreenOn);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Settings')),
      body: Padding(
        padding: EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              controller: _apiKeyController,
              decoration: InputDecoration(labelText: 'Gemini API Key'),
            ),
            SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text('Need an API Key?'),
                TextButton(
                  onPressed: () {
                    _launchGeminiAIStudioUrl();
                  },
                  child: Text(
                    'Go to Gemini AI Studio',
                  ),
                ),
              ],
            ),
            SizedBox(height: 16),
            TextField(
              controller: _contextController,
              decoration: InputDecoration(
                  labelText: 'User Context (e.g., preferences, constraints)'),
              maxLines: 3,
            ),
            SizedBox(height: 16), // Add this SizedBox
            SwitchListTile(
              // Add this SwitchListTile
              title: Text('Keep Screen On During Timer'),
              value: _keepScreenOn,
              onChanged: (value) {
                setState(() {
                  _keepScreenOn = value;
                });
              },
            ),
            SizedBox(height: 16),
            ElevatedButton(
              onPressed: _saveSettings,
              child: Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}
