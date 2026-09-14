import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_hbb/utils/multi_window_manager.dart';

class TelesolverSession {
  static final TelesolverSession instance = TelesolverSession._internal();
  factory TelesolverSession() => instance;
  TelesolverSession._internal();

  String? token;
  String clientName = '';
  String providerName = '';
  String serviceTitle = '';
  int durationMinutes = 60;
  int remainingSeconds = 0;
  bool isExpired = false;
  bool isInitialized = false;
  bool hasActiveSession = false;

  bool _idRegistered = false;
  String? registeredRemoteId;

  Timer? _timer;
  final List<VoidCallback> _listeners = [];

  void addListener(VoidCallback listener) {
    _listeners.add(listener);
  }

  void removeListener(VoidCallback listener) {
    _listeners.remove(listener);
  }

  void _notify() {
    for (final listener in _listeners) {
      try {
        listener();
      } catch (e) {
        debugPrint('[TelesolverSession] Listener error: $e');
      }
    }
  }

  /// Inizializza la sessione leggendo token da argomenti o nome eseguibile
  Future<void> init({List<String>? args}) async {
    if (isInitialized) return;
    isInitialized = true;

    token = _extractToken(args);
    debugPrint('[TelesolverSession] Detected token: $token');

    if (token != null && token!.isNotEmpty) {
      hasActiveSession = true;
      await fetchSessionDetails();
      _startCountdown();
      _startRegisterIdWatcher();
    }
  }

  String? _extractToken(List<String>? args) {
    // 1. Argomenti da linea di comando: --session <token> o --session=<token>
    if (args != null && args.isNotEmpty) {
      for (int i = 0; i < args.length; i++) {
        if (args[i] == '--session' && i + 1 < args.length) {
          return args[i + 1];
        }
        if (args[i].startsWith('--session=')) {
          return args[i].substring('--session='.length);
        }
        if (args[i].startsWith('session=')) {
          return args[i].substring('session='.length);
        }
      }
    }

    // 2. Variabile d'ambiente RUSTDESK_APPNAME passata dall'unpacker portatile
    final envAppname = Platform.environment['RUSTDESK_APPNAME'];
    if (envAppname != null && envAppname.isNotEmpty) {
      final t = _parseTokenFromString(envAppname);
      if (t != null) return t;
    }

    // 3. Platform.resolvedExecutable / Platform.executable
    try {
      final resolved = Platform.resolvedExecutable;
      final t = _parseTokenFromString(resolved);
      if (t != null) return t;
    } catch (_) {}

    try {
      final exe = Platform.executable;
      final t = _parseTokenFromString(exe);
      if (t != null) return t;
    } catch (_) {}

    return null;
  }

  String? _parseTokenFromString(String input) {
    final regExp = RegExp(r'(?:session|token)=([a-zA-Z0-9_-]+)', caseSensitive: false);
    final match = regExp.firstMatch(input);
    if (match != null && match.groupCount >= 1) {
      return match.group(1);
    }
    return null;
  }

  /// Recupera i dettagli della sessione dalle API Telesolver
  Future<void> fetchSessionDetails() async {
    if (token == null || token!.isEmpty) return;

    try {
      final url = Uri.parse('https://telesolver.com/api/remote-desktop/session/$token');
      final response = await http.get(url).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true && data['session'] != null) {
          final s = data['session'];
          clientName = s['clientName']?.toString() ?? '';
          providerName = s['providerName']?.toString() ?? '';
          serviceTitle = s['serviceTitle']?.toString() ?? '';
          durationMinutes = (s['durationMinutes'] is num) ? (s['durationMinutes'] as num).toInt() : 60;
          remainingSeconds = (s['remainingSeconds'] is num) ? (s['remainingSeconds'] as num).toInt() : 0;
          isExpired = (s['isExpired'] == true) || remainingSeconds <= 0;

          if (isExpired) {
            _onSessionExpired();
          }
          _notify();
        }
      } else {
        debugPrint('[TelesolverSession] API status ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('[TelesolverSession] Error fetching session: $e');
    }
  }

  /// Monitora la generazione dell'ID del client locale e lo trasmette in automatico alla sessione Telesolver
  void _startRegisterIdWatcher() {
    if (_idRegistered || token == null || token!.isEmpty) return;

    int attempts = 0;
    Timer.periodic(const Duration(milliseconds: 500), (timer) async {
      attempts++;
      if (_idRegistered || attempts > 120) {
        timer.cancel();
        return;
      }

      try {
        final id = await bind.mainGetMyId();
        if (id.isNotEmpty && id != 'Generating ...' && id != '-') {
          final password = await bind.mainGetTemporaryPassword();
          await registerCredentials(id, (password.isNotEmpty && password != '-') ? password : null);
          registeredRemoteId = id;
          _idRegistered = true;
          timer.cancel();
          _notify();
        }
      } catch (e) {
        debugPrint('[TelesolverSession] Polling local ID error: $e');
      }
    });
  }

  Future<void> registerCredentials(String remoteId, String? password) async {
    if (token == null || token!.isEmpty) return;
    try {
      final url = Uri.parse('https://telesolver.com/api/remote-desktop/session/$token/register-id');
      final res = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'remoteId': remoteId,
          if (password != null) 'password': password,
        }),
      ).timeout(const Duration(seconds: 10));

      debugPrint('[TelesolverSession] Auto-register credentials response: ${res.statusCode}');
    } catch (e) {
      debugPrint('[TelesolverSession] Error auto-registering credentials: $e');
    }
  }

  void _startCountdown() {
    _timer?.cancel();
    if (remainingSeconds <= 0) {
      isExpired = true;
      _onSessionExpired();
      _notify();
      return;
    }

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (remainingSeconds > 0) {
        remainingSeconds--;
        _notify();
      }

      if (remainingSeconds <= 0) {
        timer.cancel();
        isExpired = true;
        _onSessionExpired();
        _notify();
      }
    });
  }

  void _onSessionExpired() {
    try {
      // Chiude immediatamente tutte le sottofinestre di controllo remoto attive
      rustDeskWinManager.closeAllSubWindows();
    } catch (e) {
      debugPrint('[TelesolverSession] Error closing subwindows on expire: $e');
    }
  }

  String get formattedTime {
    if (remainingSeconds <= 0) return '00:00';
    final hours = remainingSeconds ~/ 3600;
    final mins = (remainingSeconds % 3600) ~/ 60;
    final secs = remainingSeconds % 60;

    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
    }
    return '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  void dispose() {
    _timer?.cancel();
    _listeners.clear();
  }
}

/// Widget HUD elegante integrato nell'interfaccia client
class TelesolverSessionWidget extends StatefulWidget {
  const TelesolverSessionWidget({Key? key}) : super(key: key);

  @override
  State<TelesolverSessionWidget> createState() => _TelesolverSessionWidgetState();
}

class _TelesolverSessionWidgetState extends State<TelesolverSessionWidget> {
  final session = TelesolverSession.instance;

  @override
  void initState() {
    super.initState();
    session.addListener(_onSessionUpdate);
  }

  @override
  void dispose() {
    session.removeListener(_onSessionUpdate);
    super.dispose();
  }

  void _onSessionUpdate() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (!session.hasActiveSession) {
      return const SizedBox.shrink();
    }

    final isExpired = session.isExpired;
    final isWarning = !isExpired && session.remainingSeconds > 0 && session.remainingSeconds <= 300;

    final primaryColor = isExpired
        ? Colors.redAccent
        : (isWarning ? Colors.amber : const Color(0xFF4F46E5));

    final bgColor = isExpired
        ? Colors.red.withOpacity(0.12)
        : (isWarning ? Colors.amber.withOpacity(0.12) : const Color(0xFF1E1B4B).withOpacity(0.5));

    final isIdRegistered = session.registeredRemoteId != null;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: primaryColor.withOpacity(0.4),
          width: 1.2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header Badge & Session Token
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: primaryColor.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(5),
                  border: Border.all(color: primaryColor.withOpacity(0.5), width: 0.8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isExpired ? Icons.cancel_outlined : (isWarning ? Icons.warning_amber_rounded : Icons.verified_user),
                      size: 13,
                      color: primaryColor,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      isExpired ? 'Sessione Scaduta' : 'Supporto Telesolver',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: primaryColor,
                      ),
                    ),
                  ],
                ),
              ),
              if (session.token != null)
                Text(
                  '#${session.token}',
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade400,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),

          // Interlocutori (Cliente & Esperto)
          if (session.clientName.isNotEmpty || session.providerName.isNotEmpty) ...[
            Row(
              children: [
                const Icon(Icons.people_alt_outlined, size: 13, color: Colors.grey),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    '${session.clientName.isNotEmpty ? session.clientName : "Cliente"} ↔ ${session.providerName.isNotEmpty ? session.providerName : "Esperto"}',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
          ],

          // Titolo Servizio
          if (session.serviceTitle.isNotEmpty) ...[
            Row(
              children: [
                const Icon(Icons.work_outline, size: 13, color: Colors.grey),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    session.serviceTitle,
                    style: TextStyle(
                      fontSize: 10.5,
                      color: Colors.grey.shade300,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],

          // Stato trasmissione automatica credenziali
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: isIdRegistered
                  ? Colors.green.withOpacity(0.15)
                  : Colors.indigo.withOpacity(0.15),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: isIdRegistered
                    ? Colors.green.withOpacity(0.35)
                    : Colors.indigo.withOpacity(0.35),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  isIdRegistered ? Icons.check_circle_outline : Icons.sync,
                  size: 14,
                  color: isIdRegistered ? Colors.greenAccent : Colors.indigoAccent,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    isIdRegistered
                        ? 'Credenziali trasmesse! Clicca "Accetta" all\'arrivo della richiesta.'
                        : 'Connessione e sincronizzazione ID in corso...',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                      color: isIdRegistered ? Colors.greenAccent : Colors.indigoAccent,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // Countdown Timer Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.3),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.timer_outlined,
                      size: 13,
                      color: isExpired ? Colors.redAccent : (isWarning ? Colors.amber : Colors.indigoAccent),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      isExpired ? 'Tempo scaduto' : 'Tempo residuo:',
                      style: TextStyle(
                        fontSize: 10.5,
                        color: isExpired ? Colors.redAccent : Colors.grey.shade300,
                        fontWeight: isExpired ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
                Text(
                  session.formattedTime,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: isExpired
                        ? Colors.redAccent
                        : (isWarning ? Colors.amber : Colors.greenAccent),
                  ),
                ),
              ],
            ),
          ),

          // Messaggio di avviso in caso di scadenza
          if (isExpired) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.2),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.red.withOpacity(0.4)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.lock_clock, size: 13, color: Colors.redAccent),
                  SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      'Sessione conclusa. Controllo remoto interrotto.',
                      style: TextStyle(fontSize: 9.5, color: Colors.redAccent),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
