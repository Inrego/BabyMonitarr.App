import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../models/audio_state.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

class SoundLevelGraph extends StatelessWidget {
  final List<AudioLevel> history;
  final double currentDisplayLevel;
  final SoundStatus currentStatus;

  const SoundLevelGraph({
    super.key,
    required this.history,
    required this.currentDisplayLevel,
    required this.currentStatus,
  });

  Color get _lineColor {
    switch (currentStatus) {
      case SoundStatus.quiet:
        return AppColors.tealAccent;
      case SoundStatus.moderate:
        return AppColors.primaryWarm;
      case SoundStatus.active:
        return AppColors.secondaryWarm;
      case SoundStatus.alert:
        return AppColors.liveRed;
    }
  }

  static const _thresholds = [40.0, 55.0];
  static const _zoneColors = [
    AppColors.tealAccent,
    AppColors.primaryWarm,
    AppColors.secondaryWarm,
  ];

  static int _zoneIndex(double y) {
    if (y < 40) return 0;
    if (y < 55) return 1;
    return 2;
  }

  /// Splits spots into colored segments at threshold crossings.
  static List<(List<FlSpot>, Color)> _splitByThresholds(List<FlSpot> spots) {
    if (spots.isEmpty) return [];
    if (spots.length == 1) {
      return [(spots, _zoneColors[_zoneIndex(spots.first.y)])];
    }

    final segments = <(List<FlSpot>, Color)>[];
    var currentSegment = <FlSpot>[spots.first];
    var currentZone = _zoneIndex(spots.first.y);

    for (var i = 1; i < spots.length; i++) {
      final prev = spots[i - 1];
      final curr = spots[i];

      // Find threshold crossings between prev and curr.
      final crossings = <FlSpot>[];
      for (final threshold in _thresholds) {
        if ((prev.y < threshold && curr.y >= threshold) ||
            (prev.y >= threshold && curr.y < threshold)) {
          final t = (threshold - prev.y) / (curr.y - prev.y);
          final x = prev.x + t * (curr.x - prev.x);
          crossings.add(FlSpot(x, threshold));
        }
      }

      if (crossings.isEmpty) {
        currentSegment.add(curr);
      } else {
        crossings.sort((a, b) => a.x.compareTo(b.x));
        final goingUp = curr.y > prev.y;
        for (final cp in crossings) {
          currentSegment.add(cp);
          segments.add((currentSegment, _zoneColors[currentZone]));
          currentZone += goingUp ? 1 : -1;
          currentSegment = [cp];
        }
        currentSegment.add(curr);
      }
    }

    if (currentSegment.isNotEmpty) {
      segments.add((currentSegment, _zoneColors[currentZone]));
    }
    return segments;
  }

  String get _statusText {
    switch (currentStatus) {
      case SoundStatus.quiet:
        return 'Quiet';
      case SoundStatus.moderate:
        return 'Moderate';
      case SoundStatus.active:
        return 'Active';
      case SoundStatus.alert:
        return 'Alert!';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          const SizedBox(height: 8),
          SizedBox(
            height: 160,
            child: history.isEmpty ? _buildEmptyState() : _buildChart(),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              currentDisplayLevel.toStringAsFixed(0),
              style: AppTheme.display.copyWith(fontSize: 32, color: _lineColor),
            ),
            const SizedBox(width: 4),
            Text('dB', style: AppTheme.caption),
          ],
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: _lineColor.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            _statusText,
            style: AppTheme.caption.copyWith(
              color: _lineColor,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.graphic_eq,
            size: 32,
            color: AppColors.textSecondary,
          ),
          const SizedBox(height: 8),
          Text(
            'Waiting for audio data...',
            style: AppTheme.caption.copyWith(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildChart() {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final spots = history.map((e) {
      final secondsAgo = (nowMs - e.timestamp) / 1000.0;
      final x = 300.0 - secondsAgo;
      return FlSpot(x.clamp(0, 300), e.displayLevel.clamp(0, 100));
    }).toList();

    return LineChart(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
      LineChartData(
        minX: 0,
        maxX: 300,
        minY: 0,
        maxY: 100,
        clipData: const FlClipData.all(),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: 25,
          getDrawingHorizontalLine: (value) => FlLine(
            color: AppColors.surfaceLight.withValues(alpha: 0.5),
            strokeWidth: 0.5,
          ),
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: 60,
              reservedSize: 22,
              getTitlesWidget: (value, meta) {
                const labels = {
                  0: '5m',
                  60: '4m',
                  120: '3m',
                  180: '2m',
                  240: '1m',
                  300: 'Now',
                };
                final label = labels[value.toInt()];
                if (label == null) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    label,
                    style: AppTheme.caption.copyWith(fontSize: 10),
                  ),
                );
              },
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: 25,
              reservedSize: 28,
              getTitlesWidget: (value, meta) {
                if (value == meta.max || value == meta.min) {
                  return const SizedBox.shrink();
                }
                return Text(
                  value.toInt().toString(),
                  style: AppTheme.caption.copyWith(fontSize: 10),
                );
              },
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
        extraLinesData: ExtraLinesData(
          horizontalLines: [
            HorizontalLine(
              y: 40,
              color: AppColors.primaryWarm.withValues(alpha: 0.3),
              strokeWidth: 1,
              dashArray: [4, 4],
            ),
            HorizontalLine(
              y: 55,
              color: AppColors.secondaryWarm.withValues(alpha: 0.3),
              strokeWidth: 1,
              dashArray: [4, 4],
            ),
          ],
        ),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => AppColors.surfaceLight,
            getTooltipItems: (spots) => spots.map((spot) {
              return LineTooltipItem(
                '${spot.y.toStringAsFixed(0)}%',
                AppTheme.caption.copyWith(
                  color: _lineColor,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              );
            }).toList(),
          ),
        ),
        lineBarsData: _splitByThresholds(spots).map((segment) {
          final (segSpots, color) = segment;
          return LineChartBarData(
            spots: segSpots,
            isCurved: true,
            curveSmoothness: 0.3,
            color: color,
            barWidth: 2,
            isStrokeCapRound: true,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(show: false),
          );
        }).toList(),
      ),
    );
  }
}
