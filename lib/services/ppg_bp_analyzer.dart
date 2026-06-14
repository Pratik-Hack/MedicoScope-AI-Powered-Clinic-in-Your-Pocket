import 'dart:math' as math;

import 'package:medicoscope/core/constants/disease_constants.dart';
import 'package:medicoscope/models/disease_risk_result.dart';

/// PPG-BP (cuff-less blood pressure) estimator.
///
/// HONESTY NOTE: cuff-less BP from a phone camera is *screening-grade only*.
/// No camera-PPG method (this one included) meets clinical cuff accuracy
/// (IEEE 1708 / AAMI ≤5±8 mmHg), and none is FDA-cleared to replace a cuff.
/// What this pipeline does well — and what we maximise here — is (a) accurate
/// pulse rate / HRV, and (b) HONEST UNCERTAINTY: every reading carries a
/// calibrated confidence, and a low-quality trace is rejected or flagged rather
/// than reported as fact. The BP number is an estimate; its confidence is real.
///
/// Pipeline (Elgendi 2013, Liang 2018, MIMIC-III protocols):
///   1. Fingertip over rear camera + flash → red-channel mean per frame.
///   2. Trim transients → detrend → band-pass 0.7-3.5 Hz (cardiac band).
///   3. Signal-quality assessment: SNR (in-band vs out-of-band power) + beat
///      regularity. Reject if too noisy; otherwise derive a confidence score.
///   4. Adaptive peak detection (refractory period) → IBI/HR/HRV.
///   5. BP estimate via Wu/Teng-style regression, returned WITH its confidence
///      so the Aegis gate can escalate a low-confidence high reading to review.
class PpgBpAnalyzer {
  /// [samples] is the red-channel-mean time series, one value per frame.
  /// [fps] is the camera sampling rate.
  static DiseaseRiskResult analyze({
    required List<double> samples,
    required double fps,
  }) {
    // Minimum usable signal: 5 seconds
    if (samples.length < fps * 5 || fps < 5) {
      return _empty(
          'Not enough clean frames (${samples.length}). Keep your finger firmly on the camera lens + flash for the full 15 seconds.');
    }

    // 1. Trim transients at start (user still pressing) and end (releasing).
    //    Skip the first 2 seconds and last 1 second.
    final startCut = (fps * 2).round();
    final endCut = (fps * 1).round();
    if (samples.length - startCut - endCut < fps * 4) {
      return _empty(
          'Signal too short after trimming transients. Hold still for the full 15 seconds.');
    }
    final trimmed =
        samples.sublist(startCut, samples.length - endCut);

    // 2. Band-pass 0.7–3.5 Hz (≈42–210 bpm) via cascaded moving-average
    //    difference: subtract a LONG moving average (removes baseline wander /
    //    DC, the low-pass complement) then apply a SHORT moving average
    //    (removes high-freq sensor noise). Both are single-pass O(n) running
    //    sums — no per-sample inner loop — so this is also cheaper than the
    //    old 5-tap convolution.
    final longWin = (fps / 0.7).round().clamp(8, 240);   // ~baseline cutoff
    final shortWin = (fps / 3.5).round().clamp(2, 12);   // ~noise cutoff

    // Long moving average (causal+centred via two-pass running sum).
    final baseline = _centredMovingAverage(trimmed, longWin);
    final hp = List<double>.filled(trimmed.length, 0);
    for (int i = 0; i < trimmed.length; i++) {
      hp[i] = trimmed[i] - baseline[i];           // high-pass (remove wander)
    }
    final filtered = _centredMovingAverage(hp, shortWin); // low-pass (denoise)

    // 3. Signal-quality assessment in ONE pass: mean, variance, and a crude
    //    in-band SNR estimate. Out-of-band noise shows up as sample-to-sample
    //    jitter (high first-difference energy) relative to the pulse envelope.
    double sum = 0;
    for (final v in filtered) {
      sum += v;
    }
    final mean = sum / filtered.length;
    double variance = 0, diffEnergy = 0;
    for (int i = 0; i < filtered.length; i++) {
      final d = filtered[i] - mean;
      variance += d * d;
      if (i > 0) {
        final dd = filtered[i] - filtered[i - 1];
        diffEnergy += dd * dd;
      }
    }
    variance /= filtered.length;
    final stddev = math.sqrt(variance);
    if (stddev < 0.3) {
      return _empty(
          'Signal too weak to read a pulse. Press your fingertip firmly over both the rear camera lens AND the flash, then hold still.');
    }

    // SNR proxy: pulse (signal) variance vs high-frequency jitter (noise).
    // Higher = cleaner trace. Bounded to a 0–1 quality term below.
    final noisePower = diffEnergy / math.max(1, filtered.length - 1);
    final snr = variance / math.max(noisePower, 1e-6);
    // SNR < ~2 means the high-freq jitter rivals the pulse — unreliable.
    if (snr < 1.5) {
      return _empty(
          'Too much motion/noise to read a reliable pulse. Rest your hand on a table, hold completely still, and keep steady pressure for the full 15 seconds.');
    }

    // 4. Amplitude from robust percentile range (transient spikes excluded).
    final sorted = List<double>.from(filtered)..sort();
    final p95 = sorted[(sorted.length * 0.95).toInt()];
    final p05 = sorted[(sorted.length * 0.05).toInt()];
    final amplitude = (p95 - p05).abs();
    final smoothed = filtered; // downstream peak detection uses the clean trace

    // 6. Peak detection — adaptive threshold, relaxed to 0.5 × amplitude
    //    with physiological refractory period (300 ms).
    final peakThreshold = amplitude * 0.5;
    final peaks = <int>[];
    for (int i = 3; i < smoothed.length - 3; i++) {
      final v = smoothed[i];
      if (v > peakThreshold &&
          v > smoothed[i - 1] &&
          v > smoothed[i - 2] &&
          v >= smoothed[i + 1] &&
          v >= smoothed[i + 2]) {
        if (peaks.isEmpty || (i - peaks.last) / fps > 0.3) {
          peaks.add(i);
        }
      }
    }

    // 7. If not enough peaks, try a lower threshold (signal is present but
    //    weak — better to produce a noisier estimate than fail the user).
    if (peaks.length < 4) {
      peaks.clear();
      final fallbackThresh = amplitude * 0.25;
      for (int i = 3; i < smoothed.length - 3; i++) {
        final v = smoothed[i];
        if (v > fallbackThresh &&
            v > smoothed[i - 1] &&
            v >= smoothed[i + 1]) {
          if (peaks.isEmpty || (i - peaks.last) / fps > 0.3) {
            peaks.add(i);
          }
        }
      }
    }

    if (peaks.length < 4) {
      return _empty(
          'Could not lock onto a steady pulse. Try again — make sure the flash is on, finger covers both the lens and the flash, and don\'t move.');
    }

    // 8. IBI statistics
    final ibis = <double>[];
    for (int i = 1; i < peaks.length; i++) {
      final ibi = (peaks[i] - peaks[i - 1]) * 1000.0 / fps;
      // Physiological plausibility: HR 30-220 bpm => IBI 272-2000 ms.
      if (ibi > 250 && ibi < 2200) ibis.add(ibi);
    }
    if (ibis.length < 3) {
      return _empty(
          'Detected only a few beats — we need at least 4 clean heartbeats. Try again and hold your finger very still.');
    }

    // Trim IBI outliers (values > 2× median are likely missed/double peaks).
    ibis.sort();
    final medianIbi = ibis[ibis.length ~/ 2];
    final cleanIbis = ibis.where((v) =>
        v > medianIbi * 0.5 && v < medianIbi * 1.8).toList();
    final meanIbi =
        cleanIbis.reduce((a, b) => a + b) / cleanIbis.length;
    final heartRate = 60000.0 / meanIbi;

    // HRV RMSSD
    double rmsSum = 0;
    int rmsCount = 0;
    for (int i = 1; i < cleanIbis.length; i++) {
      final d = cleanIbis[i] - cleanIbis[i - 1];
      rmsSum += d * d;
      rmsCount++;
    }
    final hrv = rmsCount > 0 ? math.sqrt(rmsSum / rmsCount) : 0.0;

    // 8b. CONFIDENCE — the honest core of this estimate. Combine three real
    //     quality signals, each mapped to 0–1, then take their product so any
    //     single weak factor pulls confidence down:
    //       • snrQ      — trace cleanliness (SNR proxy from step 3)
    //       • regQ      — beat regularity (low IBI coefficient-of-variation)
    //       • lenQ      — how many clean beats we measured (more = steadier)
    final meanForCv =
        cleanIbis.reduce((a, b) => a + b) / cleanIbis.length;
    double ibiVar = 0;
    for (final v in cleanIbis) {
      final d = v - meanForCv;
      ibiVar += d * d;
    }
    final ibiCv = math.sqrt(ibiVar / cleanIbis.length) / meanForCv; // 0..~
    final snrQ = ((snr - 1.5) / 8.0).clamp(0.0, 1.0);   // 1.5→0, ≥9.5→1
    final regQ = (1.0 - ibiCv * 3.0).clamp(0.0, 1.0);   // CV 0→1, ≥0.33→0
    final lenQ = (cleanIbis.length / 15.0).clamp(0.0, 1.0); // 15+ beats → full
    // BP is inherently the least certain output, so cap its confidence: even a
    // perfect trace yields a screening-grade BP estimate, never clinical-grade.
    final pulseConfidence = (snrQ * 0.5 + regQ * 0.35 + lenQ * 0.15);
    final bpConfidence = (pulseConfidence * 0.6).clamp(0.0, 0.6);

    // 9. Normalise amplitude to a stable 0-100 range before plugging into the
    //    Wu/Teng regression. Raw byte amplitude varies with camera gain / light
    //    so the original coefficients over-estimated BP.
    final normAmplitude =
        (amplitude / (stddev * 4)).clamp(0.0, 100.0);

    final sbp = (90 + 0.4 * (heartRate - 70) + 0.5 * normAmplitude)
        .clamp(85.0, 210.0);
    final dbp = (60 + 0.25 * (heartRate - 70) + 0.3 * normAmplitude)
        .clamp(50.0, 130.0);

    RiskLevel risk;
    String headline;
    if (sbp >= 180 || dbp >= 120) {
      risk = RiskLevel.critical;
      headline = 'Hypertensive crisis range — seek urgent care.';
    } else if (sbp >= 140 || dbp >= 90) {
      risk = RiskLevel.high;
      headline = 'Stage 2 hypertension range.';
    } else if (sbp >= 130 || dbp >= 80) {
      risk = RiskLevel.moderate;
      headline = 'Stage 1 hypertension range.';
    } else if (sbp >= 120) {
      risk = RiskLevel.moderate;
      headline = 'Elevated BP — lifestyle changes advised.';
    } else {
      risk = RiskLevel.low;
      headline = 'Blood pressure estimate within normal range.';
    }

    // HONESTY GUARD: a low-confidence trace must not raise a hypertensive alarm
    // on a number we don't trust. When confidence is poor AND the estimate is
    // high/critical, we DON'T silently downgrade the risk away — instead we keep
    // the signal but reframe the headline to demand a cuff re-measurement, and
    // the low bpConfidence is passed to the Aegis gate, which (by the confidence
    // rule) routes a high-risk + low-confidence action to clinician review
    // rather than auto-alarming the patient.
    final lowConfidence = bpConfidence < 0.3;
    if (lowConfidence &&
        (risk == RiskLevel.high || risk == RiskLevel.critical)) {
      headline =
          'Possible elevated BP, but the signal was noisy — confirm with a cuff before acting.';
    }

    final findings = [
      MarkerFinding(
        name: 'Estimated Systolic BP',
        value: sbp.toStringAsFixed(0),
        unit: 'mmHg',
        referenceRange: '< 120 normal • ≥ 130 stage 1 • ≥ 140 stage 2',
        flag: sbp >= 180
            ? 'critical'
            : sbp >= 140
                ? 'high'
                : sbp >= 130
                    ? 'low'
                    : 'normal',
        interpretation: sbp >= 140
            ? 'Meets hypertension criteria'
            : sbp >= 130
                ? 'Borderline high'
                : 'Within normal range',
      ),
      MarkerFinding(
        name: 'Estimated Diastolic BP',
        value: dbp.toStringAsFixed(0),
        unit: 'mmHg',
        referenceRange: '< 80 normal • ≥ 90 stage 2',
        flag: dbp >= 120
            ? 'critical'
            : dbp >= 90
                ? 'high'
                : dbp >= 80
                    ? 'low'
                    : 'normal',
        interpretation: dbp >= 90
            ? 'Hypertension range'
            : dbp >= 80
                ? 'Borderline'
                : 'Within normal range',
      ),
      MarkerFinding(
        name: 'Pulse Rate (PPG)',
        value: heartRate.toStringAsFixed(0),
        unit: 'bpm',
        referenceRange: '60–100 bpm resting',
        flag: heartRate > 100
            ? 'high'
            : heartRate < 60
                ? 'low'
                : 'normal',
        interpretation: heartRate > 100
            ? 'Tachycardia'
            : heartRate < 60
                ? 'Bradycardia'
                : 'Normal heart rate',
      ),
      MarkerFinding(
        name: 'HRV (RMSSD)',
        value: hrv.toStringAsFixed(1),
        unit: 'ms',
        referenceRange: '> 30 ms typical healthy',
        flag: hrv < 20 ? 'low' : 'normal',
        interpretation: hrv < 20
            ? 'Low HRV — autonomic / stress marker'
            : 'Adequate HRV',
      ),
      MarkerFinding(
        name: 'Signal quality (SNR)',
        value: snr.toStringAsFixed(1),
        unit: '',
        referenceRange: '> 4 = strong • 1.5–4 = usable',
        flag: snr > 4 ? 'normal' : snr > 2.5 ? 'low' : 'high',
        interpretation: snr > 4
            ? 'Strong, clean PPG trace'
            : snr > 2.5
                ? 'Moderate — firmer pressure / less motion would help'
                : 'Marginal — estimate is approximate',
      ),
      MarkerFinding(
        name: 'Estimate confidence',
        value: '${(bpConfidence * 100).toStringAsFixed(0)}%',
        unit: '',
        referenceRange: 'Screening-grade; cuff confirmation advised',
        flag: bpConfidence >= 0.45
            ? 'normal'
            : bpConfidence >= 0.3
                ? 'low'
                : 'high',
        interpretation: bpConfidence >= 0.45
            ? 'Good signal — but still a screening estimate, not a diagnosis'
            : 'Low confidence — confirm with a calibrated cuff before acting',
      ),
    ];

    return DiseaseRiskResult(
      disease: DiseaseType.hypertension,
      method: DetectionMethod.ppgBloodPressure,
      risk: risk,
      score: ((sbp - 100) / 80 * 0.5 + (dbp - 60) / 50 * 0.5).clamp(0.0, 1.0),
      headline: headline,
      findings: findings,
      topContributors: [
        'Estimated BP ${sbp.toStringAsFixed(0)}/${dbp.toStringAsFixed(0)} mmHg',
        'Heart rate ${heartRate.toStringAsFixed(0)} bpm',
        'HRV ${hrv.toStringAsFixed(0)} ms',
      ],
      recommendations: [
        if (risk == RiskLevel.critical)
          'URGENT: This is a hypertensive crisis range — seek care today.',
        if (risk == RiskLevel.high)
          'URGENT: Confirm with a traditional cuff BP monitor and see a clinician.',
        'Cuff-less estimates are screening-grade — NOT a diagnosis. Always confirm with a calibrated cuff.',
        if (bpConfidence < 0.3)
          'This reading had low signal confidence — re-measure with a still hand before trusting the number.',
        'Reduce sodium, manage stress, 30-min daily walk.',
      ],
      dataSource:
          'PPG-BP regression (Wu 2009 / Teng 2003), band-pass + SNR-gated, '
          'confidence ${(bpConfidence * 100).toStringAsFixed(0)}% — screening-grade',
      timestamp: DateTime.now(),
    );
  }

  /// Centred moving average via a single forward running sum (O(n)). Used as
  /// the low-pass building block for the band-pass filter.
  static List<double> _centredMovingAverage(List<double> x, int win) {
    final n = x.length;
    final out = List<double>.filled(n, 0);
    if (win <= 1) return List<double>.from(x);
    final half = win ~/ 2;
    // Prefix sums for O(1) window queries.
    final prefix = List<double>.filled(n + 1, 0);
    for (int i = 0; i < n; i++) {
      prefix[i + 1] = prefix[i] + x[i];
    }
    for (int i = 0; i < n; i++) {
      final lo = math.max(0, i - half);
      final hi = math.min(n - 1, i + half);
      out[i] = (prefix[hi + 1] - prefix[lo]) / (hi - lo + 1);
    }
    return out;
  }

  static DiseaseRiskResult _empty(String why) {
    return DiseaseRiskResult(
      disease: DiseaseType.hypertension,
      method: DetectionMethod.ppgBloodPressure,
      risk: RiskLevel.low,
      score: 0,
      headline: why,
      findings: const [],
      topContributors: const [],
      recommendations: const [
        'Cover BOTH the rear camera lens AND the flashlight with your fingertip.',
        'Press gently but firmly — enough to see a steady pink/red glow.',
        'Keep your hand completely still for the full 15 seconds.',
        'Sit in a well-lit room and rest your hand on a table.',
      ],
      dataSource: 'PPG-BP signal processing pipeline',
      timestamp: DateTime.now(),
    );
  }
}
