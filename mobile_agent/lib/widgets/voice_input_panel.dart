// lib/widgets/voice_input_panel.dart
//
// Slide-up voice input panel with waveform animation, live transcript,
// and smart code intent preview. The main UI for the Voice->Code flow.
//
// Usage:
// ```dart
// showModalBottomSheet(
//   context: context,
//   isScrollControlled: true,
//   backgroundColor: Colors.transparent,
//   builder: (_) => const VoiceInputPanel(),
// );
// ```

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/theme.dart';
import '../services/voice_service.dart';
import 'waveform_visualizer.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Voice Input Panel
// ─────────────────────────────────────────────────────────────────────────────

/// Slide-up voice input panel for speech-to-code conversion.
///
/// Features:
/// - Animated waveform visualization while listening
/// - Live partial transcript display
/// - Smart code intent detection preview
/// - Cancel / Confirm action buttons
/// - Pulsing listening indicator
/// - Language indicator (zh_CN)
/// - Confidence meter for intent detection
/// - Glassmorphism dark theme matching the app
///
/// Can be used as a modal bottom sheet or inline widget.
class VoiceInputPanel extends StatefulWidget {
  /// Called when the user confirms the transcript and wants to generate code.
  final void Function(String transcript, CodeIntent? intent)? onConfirm;

  /// Called when the user cancels voice input.
  final VoidCallback? onCancel;

  /// Called when the panel is dismissed (either confirm or cancel).
  final VoidCallback? onDismiss;

  /// Height of the panel.
  final double height;

  /// Whether to show the panel as a modal with drag handle.
  final bool showDragHandle;

  /// Whether to auto-start listening when the panel is built.
  final bool autoStart;

  const VoiceInputPanel({
    super.key,
    this.onConfirm,
    this.onCancel,
    this.onDismiss,
    this.height = 420,
    this.showDragHandle = true,
    this.autoStart = true,
  });

  @override
  State<VoiceInputPanel> createState() => _VoiceInputPanelState();
}

class _VoiceInputPanelState extends State<VoiceInputPanel>
    with TickerProviderStateMixin {
  // ── Voice Service (direct for now, can be switched to provider) ────
  late VoiceService _voiceService;

  // ── State ────────────────────────────────────────────────────────────
  VoiceState _voiceState = VoiceState.idle;
  String _transcript = '';
  String _errorMessage = '';
  CodeIntent? _codeIntent;
  String? _codePrompt;

  // ── Animation Controllers ────────────────────────────────────────────
  late AnimationController _pulseController;
  late AnimationController _slideController;
  late AnimationController _fadeController;
  late AnimationController _breathController;

  // ── Stream Subscriptions ─────────────────────────────────────────────
  StreamSubscription<VoiceState>? _stateSub;
  StreamSubscription<String>? _transcriptSub;
  StreamSubscription<AudioLevel>? _audioSub;

  // ── UI State ─────────────────────────────────────────────────────────
  double _currentAmplitude = 0.15;

  @override
  void initState() {
    super.initState();
    _initAnimations();
    _initVoiceService();
  }

  void _initAnimations() {
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
      value: 1.0,
    );

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
      value: 1.0,
    );

    _breathController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat();
  }

  void _initVoiceService() {
    _voiceService = VoiceService();

    // Subscribe to state changes.
    _stateSub = _voiceService.onStateChange.listen((state) {
      if (!mounted) return;
      setState(() {
        _voiceState = state;
        if (state == VoiceState.error) {
          _errorMessage = _voiceService.lastError;
        }
      });

      // Manage pulse animation based on state.
      if (state == VoiceState.listening) {
        _pulseController.repeat();
      } else {
        _pulseController.stop();
      }
    });

    // Subscribe to transcript updates.
    _transcriptSub = _voiceService.onTranscriptUpdate.listen((text) {
      if (!mounted) return;
      setState(() => _transcript = text);
    });

    // Subscribe to audio levels.
    _audioSub = _voiceService.onAudioLevel.listen((level) {
      if (!mounted) return;
      setState(() => _currentAmplitude = level.amplitude);
    });

    // Initialize and optionally start listening.
    _voiceService.initialize().then((available) {
      if (available && widget.autoStart && mounted) {
        _startListening();
      }
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _slideController.dispose();
    _fadeController.dispose();
    _breathController.dispose();
    _stateSub?.cancel();
    _transcriptSub?.cancel();
    _audioSub?.cancel();
    _voiceService.dispose();
    super.dispose();
  }

  // ── Actions ──────────────────────────────────────────────────────────

  Future<void> _startListening() async {
    HapticFeedback.mediumImpact();
    setState(() {
      _transcript = '';
      _errorMessage = '';
      _codeIntent = null;
      _codePrompt = null;
      _voiceState = VoiceState.idle;
    });
    await _voiceService.startListening();
  }

  Future<void> _stopListening() async {
    HapticFeedback.lightImpact();
    await _voiceService.stopListening();

    // Analyze intent after stopping.
    if (_voiceService.transcript.isNotEmpty) {
      final intent = _voiceService.analyzeIntent(_voiceService.transcript);
      final prompt = _voiceService.buildCodePrompt(intent);
      setState(() {
        _codeIntent = intent;
        _codePrompt = prompt;
      });
    }
  }

  void _cancel() {
    HapticFeedback.mediumImpact();
    _voiceService.cancel();
    widget.onCancel?.call();
    widget.onDismiss?.call();
    _dismissPanel();
  }

  void _confirm() {
    HapticFeedback.heavyImpact();
    widget.onConfirm?.call(_transcript, _codeIntent);
    widget.onDismiss?.call();
    _dismissPanel();
  }

  void _retry() {
    setState(() {
      _errorMessage = '';
      _voiceState = VoiceState.idle;
    });
    _startListening();
  }

  void _dismissPanel() {
    _slideController.reverse().then((_) {
      if (mounted) Navigator.of(context).pop();
    });
  }

  // ── Build ────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _slideController,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(0, (1 - _slideController.value) * 100),
          child: Opacity(
            opacity: _fadeController.value,
            child: child,
          ),
        );
      },
      child: Container(
        height: widget.height,
        decoration: BoxDecoration(
          // Glassmorphism background.
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              AppTheme.surface.withOpacity(0.95),
              AppTheme.background.withOpacity(0.98),
            ],
          ),
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(24),
          ),
          border: Border(
            top: BorderSide(
              color: AppTheme.primary.withOpacity(0.3),
              width: 1,
            ),
          ),
          boxShadow: [
            BoxShadow(
              color: AppTheme.primary.withOpacity(0.1),
              blurRadius: 30,
              spreadRadius: 5,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(24),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Drag Handle ──────────────────────────────────────
              if (widget.showDragHandle) _buildDragHandle(),

              // ── Header ───────────────────────────────────────────
              _buildHeader(),

              const SizedBox(height: 8),

              // ── Waveform Visualization ───────────────────────────
              _buildWaveformArea(),

              const SizedBox(height: 12),

              // ── Listening Indicator / Status ─────────────────────
              _buildStatusIndicator(),

              const SizedBox(height: 12),

              // ── Transcript Display ───────────────────────────────
              Expanded(child: _buildTranscriptArea()),

              // ── Intent Preview (if detected) ─────────────────────
              if (_codeIntent != null && _codeIntent!.isCodeRelated)
                _buildIntentPreview(),

              // ── Action Buttons ───────────────────────────────────
              _buildActionBar(),

              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  // ── Sub-Builders ─────────────────────────────────────────────────────

  Widget _buildDragHandle() {
    return Center(
      child: Container(
        margin: const EdgeInsets.only(top: 12, bottom: 4),
        width: 40,
        height: 4,
        decoration: BoxDecoration(
          color: AppTheme.textTertiary.withOpacity(0.5),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Row(
        children: [
          // Voice icon.
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              gradient: AppTheme.primaryGradient,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.mic,
              size: 16,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 10),

          // Title.
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '语音输入',
                style: TextStyle(
                  fontFamily: AppTheme.fontBody,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary,
                ),
              ),
              Text(
                _voiceState == VoiceState.listening
                    ? '正在聆听...'
                    : _voiceState == VoiceState.processing
                        ? '处理中...'
                        : _voiceState == VoiceState.done
                            ? '识别完成'
                            : _voiceState == VoiceState.error
                                ? '出错了'
                                : '点击麦克风开始',
                style: const TextStyle(
                  fontFamily: AppTheme.fontBody,
                  fontSize: 12,
                  color: AppTheme.textTertiary,
                ),
              ),
            ],
          ),

          const Spacer(),

          // Language indicator.
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: AppTheme.surfaceHover,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: AppTheme.border),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.language,
                  size: 12,
                  color: AppTheme.textTertiary,
                ),
                SizedBox(width: 4),
                Text(
                  'zh-CN',
                  style: TextStyle(
                    fontFamily: AppTheme.fontBody,
                    fontSize: 11,
                    color: AppTheme.textTertiary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWaveformArea() {
    return SizedBox(
      height: 100,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Background glow.
          if (_voiceState == VoiceState.listening)
            AnimatedBuilder(
              animation: _breathController,
              builder: (context, child) {
                return Container(
                  width: 180 + 40 * math.sin(_breathController.value * math.pi * 2),
                  height: 80 + 20 * math.sin(_breathController.value * math.pi * 2),
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      colors: [
                        AppTheme.primary.withOpacity(0.15),
                        AppTheme.primary.withOpacity(0.0),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(60),
                  ),
                );
              },
            ),

          // Waveform or idle icon.
          if (_voiceState == VoiceState.listening)
            WaveformVisualizer(
              audioStream: _voiceService.onAudioLevel
                  .map((level) => level.amplitude),
              height: 90,
              barCount: 28,
              barWidth: 4,
              barSpacing: 3,
              gradientStart: AppTheme.primary,
              gradientEnd: AppTheme.accent,
              symmetric: true,
              glowEffect: true,
            )
          else if (_voiceState == VoiceState.processing)
            _buildProcessingIndicator()
          else if (_voiceState == VoiceState.done)
            _buildDoneIndicator()
          else if (_voiceState == VoiceState.error)
            _buildErrorIndicator()
          else
            _buildIdleIndicator(),
        ],
      ),
    );
  }

  Widget _buildProcessingIndicator() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
            strokeWidth: 2.5,
            valueColor: AlwaysStoppedAnimation<Color>(
              AppTheme.primary.withOpacity(0.8),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Text(
          '分析意图中...',
          style: TextStyle(
            fontFamily: AppTheme.fontBody,
            fontSize: 14,
            color: AppTheme.textSecondary.withOpacity(0.8),
          ),
        ),
      ],
    );
  }

  Widget _buildDoneIndicator() {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 400),
      curve: Curves.elasticOut,
      builder: (context, value, child) {
        return Transform.scale(
          scale: value,
          child: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              gradient: AppTheme.accentGradient,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: AppTheme.accent.withOpacity(0.3),
                  blurRadius: 16,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: const Icon(
              Icons.check,
              size: 28,
              color: Colors.white,
            ),
          ),
        );
      },
    );
  }

  Widget _buildErrorIndicator() {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: AppTheme.error.withOpacity(0.15),
        shape: BoxShape.circle,
        border: Border.all(
          color: AppTheme.error.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Icon(
        Icons.error_outline,
        size: 28,
        color: AppTheme.error.withOpacity(0.8),
      ),
    );
  }

  Widget _buildIdleIndicator() {
    return GestureDetector(
      onTap: _startListening,
      child: AnimatedBuilder(
        animation: _breathController,
        builder: (context, child) {
          final scale = 1.0 + 0.05 * math.sin(_breathController.value * math.pi * 2);
          return Transform.scale(
            scale: scale,
            child: Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                gradient: AppTheme.primaryGradient,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.primary.withOpacity(0.25),
                    blurRadius: 20,
                    spreadRadius: 4,
                  ),
                ],
              ),
              child: const Icon(
                Icons.mic,
                size: 32,
                color: Colors.white,
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildStatusIndicator() {
    if (_voiceState != VoiceState.listening) return const SizedBox.shrink();

    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        final opacity = 0.4 + 0.6 * (0.5 + 0.5 * math.sin(_pulseController.value * math.pi * 2));
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: AppTheme.error.withOpacity(opacity * 0.15),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: AppTheme.error.withOpacity(opacity * 0.4),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: AppTheme.error.withOpacity(opacity),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '正在录音',
                style: TextStyle(
                  fontFamily: AppTheme.fontBody,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: AppTheme.error.withOpacity(opacity),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTranscriptArea() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.backgroundElevated.withOpacity(0.6),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _voiceState == VoiceState.listening
              ? AppTheme.primary.withOpacity(0.3)
              : AppTheme.border,
        ),
      ),
      child: _voiceState == VoiceState.error
          ? _buildErrorContent()
          : _buildTranscriptContent(),
    );
  }

  Widget _buildTranscriptContent() {
    if (_transcript.isEmpty && _voiceState != VoiceState.listening) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.keyboard_voice,
              size: 28,
              color: AppTheme.textTertiary.withOpacity(0.4),
            ),
            const SizedBox(height: 8),
            Text(
              '点击麦克风按钮开始语音输入',
              style: TextStyle(
                fontFamily: AppTheme.fontBody,
                fontSize: 13,
                color: AppTheme.textTertiary.withOpacity(0.5),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              '试试说: "创建一个登录页面"',
              style: TextStyle(
                fontFamily: AppTheme.fontBody,
                fontSize: 12,
                color: AppTheme.textTertiary.withOpacity(0.3),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Transcript text.
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: SelectableText(
              key: ValueKey(_transcript),
              _transcript.isEmpty ? '聆听中...' : _transcript,
              style: TextStyle(
                fontFamily: AppTheme.fontBody,
                fontSize: 15,
                height: 1.5,
                color: _transcript.isEmpty
                    ? AppTheme.textTertiary.withOpacity(0.6)
                    : AppTheme.textPrimary,
              ),
            ),
          ),

          // Partial result indicator (dots).
          if (_voiceState == VoiceState.listening && _transcript.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: _buildTypingDots(),
            ),
        ],
      ),
    );
  }

  Widget _buildTypingDots() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (index) {
        return AnimatedBuilder(
          animation: _pulseController,
          builder: (context, child) {
            final offset = math.sin(
              (_pulseController.value * math.pi * 2) + (index * 0.7),
            );
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 2),
              width: 5,
              height: 5,
              decoration: BoxDecoration(
                color: AppTheme.primary.withOpacity(0.4 + 0.4 * ((offset + 1) / 2)),
                shape: BoxShape.circle,
              ),
            );
          },
        );
      }),
    );
  }

  Widget _buildErrorContent() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.mic_off,
          size: 28,
          color: AppTheme.error.withOpacity(0.6),
        ),
        const SizedBox(height: 8),
        Text(
          _errorMessage.isNotEmpty ? _errorMessage : '语音识别出错',
          style: TextStyle(
            fontFamily: AppTheme.fontBody,
            fontSize: 13,
            color: AppTheme.error.withOpacity(0.8),
          ),
          textAlign: TextAlign.center,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 10),
        TextButton.icon(
          onPressed: _retry,
          icon: const Icon(Icons.refresh, size: 16, color: AppTheme.primary),
          label: const Text(
            '重试',
            style: TextStyle(
              fontFamily: AppTheme.fontBody,
              fontSize: 13,
              color: AppTheme.primary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildIntentPreview() {
    if (_codeIntent == null) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppTheme.primary.withOpacity(0.1),
            AppTheme.accent.withOpacity(0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppTheme.primary.withOpacity(0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(
                _getIntentIcon(_codeIntent!.type),
                size: 16,
                color: AppTheme.primary,
              ),
              const SizedBox(width: 6),
              Text(
                _getIntentLabel(_codeIntent!.type),
                style: const TextStyle(
                  fontFamily: AppTheme.fontBody,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary,
                ),
              ),
              const Spacer(),
              _buildConfidenceBadge(_codeIntent!.confidence),
            ],
          ),
          if (_codeIntent!.target.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(
                  Icons.insert_drive_file,
                  size: 12,
                  color: AppTheme.textTertiary,
                ),
                const SizedBox(width: 4),
                Text(
                  _codeIntent!.target,
                  style: const TextStyle(
                    fontFamily: AppTheme.fontCode,
                    fontSize: 12,
                    color: AppTheme.textSecondary,
                  ),
                ),
                if (_codeIntent!.language != null) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.accent.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      _codeIntent!.language!,
                      style: const TextStyle(
                        fontFamily: AppTheme.fontCode,
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                        color: AppTheme.accent,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildConfidenceBadge(double confidence) {
    final color = confidence > 0.7
        ? AppTheme.success
        : confidence > 0.4
            ? AppTheme.warning
            : AppTheme.error;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '${(confidence * 100).toInt()}%',
        style: TextStyle(
          fontFamily: AppTheme.fontCode,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  Widget _buildActionBar() {
    // Listening state: show only Cancel and Stop buttons.
    if (_voiceState == VoiceState.listening) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(
          children: [
            // Cancel button.
            Expanded(
              child: _ActionButton(
                label: '取消',
                icon: Icons.close,
                onPressed: _cancel,
                isPrimary: false,
              ),
            ),
            const SizedBox(width: 12),
            // Stop button.
            Expanded(
              child: _ActionButton(
                label: '完成',
                icon: Icons.stop,
                onPressed: _stopListening,
                isPrimary: true,
                gradient: const LinearGradient(
                  colors: [AppTheme.error, Color(0xFFDC2626)],
                ),
              ),
            ),
          ],
        ),
      );
    }

    // Done state: show Cancel and Confirm buttons.
    if (_voiceState == VoiceState.done && _transcript.isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(
          children: [
            // Cancel button.
            Expanded(
              child: _ActionButton(
                label: '取消',
                icon: Icons.close,
                onPressed: _cancel,
                isPrimary: false,
              ),
            ),
            const SizedBox(width: 12),
            // Confirm button.
            Expanded(
              child: _ActionButton(
                label: '生成代码',
                icon: Icons.auto_awesome,
                onPressed: _confirm,
                isPrimary: true,
                gradient: AppTheme.accentGradient,
              ),
            ),
          ],
        ),
      );
    }

    // Error state: show Cancel and Retry buttons.
    if (_voiceState == VoiceState.error) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(
          children: [
            Expanded(
              child: _ActionButton(
                label: '关闭',
                icon: Icons.close,
                onPressed: _cancel,
                isPrimary: false,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _ActionButton(
                label: '重试',
                icon: Icons.refresh,
                onPressed: _retry,
                isPrimary: true,
              ),
            ),
          ],
        ),
      );
    }

    // Idle / Processing: no action buttons.
    return const SizedBox(height: 52);
  }

  // ── Helpers ──────────────────────────────────────────────────────────

  IconData _getIntentIcon(IntentType type) {
    return switch (type) {
      IntentType.createFile => Icons.create_new_folder_outlined,
      IntentType.modifyFile => Icons.edit_note,
      IntentType.deleteFile => Icons.delete_outline,
      IntentType.searchCode => Icons.search,
      IntentType.explainCode => Icons.menu_book_outlined,
      IntentType.generateSnippet => Icons.code,
      IntentType.runCommand => Icons.terminal,
      IntentType.unknown => Icons.help_outline,
    };
  }

  String _getIntentLabel(IntentType type) {
    return switch (type) {
      IntentType.createFile => '创建文件',
      IntentType.modifyFile => '修改文件',
      IntentType.deleteFile => '删除文件',
      IntentType.searchCode => '搜索代码',
      IntentType.explainCode => '解释代码',
      IntentType.generateSnippet => '生成代码片段',
      IntentType.runCommand => '执行命令',
      IntentType.unknown => '一般对话',
    };
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Action Button
// ─────────────────────────────────────────────────────────────────────────────

/// Styled action button for the voice input panel.
class _ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  final bool isPrimary;
  final Gradient? gradient;

  const _ActionButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    required this.isPrimary,
    this.gradient,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          gradient: isPrimary
              ? (gradient ?? AppTheme.primaryGradient)
              : null,
          color: isPrimary ? null : AppTheme.surfaceHover,
          borderRadius: BorderRadius.circular(14),
          border: isPrimary
              ? null
              : Border.all(color: AppTheme.border),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 18,
              color: isPrimary ? Colors.white : AppTheme.textSecondary,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontFamily: AppTheme.fontBody,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: isPrimary ? Colors.white : AppTheme.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
