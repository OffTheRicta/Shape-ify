import 'dart:math' as math;

/// Approximate catalog guidance. These predictions are never solver inputs.
class GuideStar {
  final String name;
  final double raHours, decDeg, magnitude;
  const GuideStar(this.name, this.raHours, this.decDeg, this.magnitude);
}

class SkyTarget {
  final GuideStar star;
  final double azimuthDeg, altitudeDeg;
  const SkyTarget(this.star, this.azimuthDeg, this.altitudeDeg);
}

class SkyLocation {
  final double latitude, longitude;
  const SkyLocation(this.latitude, this.longitude);
}

class CommonSkyWindow {
  final DateTime utc;
  final List<GuideStar> stars;
  const CommonSkyWindow(this.utc, this.stars);
}

class PartialSkyWindow {
  final CommonSkyWindow window;
  final List<int> includedIndexes;
  const PartialSkyWindow(this.window, this.includedIndexes);
}

class GroupSkyRequest {
  final List<SkyLocation> sites;
  final DateTime startUtc;
  final bool demo;
  const GroupSkyRequest(this.sites, this.startUtc, {this.demo = false});
}

class GroupSkySearch {
  final CommonSkyWindow? allSites;
  final PartialSkyWindow? subset;
  const GroupSkySearch(this.allSites, this.subset);
}

class SiteObservationWindow {
  final DateTime startUtc, endUtc;
  const SiteObservationWindow(this.startUtc, this.endUtc);
  Map<String, String> toJson() => {
    'startUtc': startUtc.toIso8601String(),
    'endUtc': endUtc.toIso8601String(),
  };
}

class DistributedSkyPlan {
  final List<GuideStar> stars;
  final List<List<SiteObservationWindow>> windows;
  final bool openingReady;
  final DateTime? nextOpeningUtc;
  const DistributedSkyPlan(this.stars, this.windows,
      {this.openingReady = true, this.nextOpeningUtc});
  List<int> reservedAt(DateTime utc) => [
    for (var i = 0; i < windows.length; i++)
      if (!windows[i].any((w) =>
          !utc.isBefore(w.startUtc) && !utc.isAfter(w.endUtc))) i,
  ];
}

/// The earliest opening slot at a participation tier. Priority zero means
/// every station; ten means at least 90%, and so on.
class OpeningChoice {
  final int priority, timeIndex, included;
  const OpeningChoice(this.priority, this.timeIndex, this.included);
}

class SkyGuide {
  static const openingDayMinutes = 12 * 60;
  static DistributedSkyPlan? planGroup(GroupSkyRequest request) =>
      planAcrossSites(request.sites, request.startUtc, demo: request.demo);
  /// Diagnosis only: empty site windows identify people who cannot observe
  /// this trio before the deadline. Never publish such a plan to the relay.
  static DistributedSkyPlan? planWithBlocked(GroupSkyRequest request) =>
      planAcrossSites(request.sites, request.startUtc,
        demo: request.demo, allowBlocked: true);
  /// Legacy shared-window query. Group creation uses [planGroup] instead.
  static GroupSkySearch searchGroup(GroupSkyRequest request) {
    final all = chooseCommon(request.sites, request.startUtc);
    return GroupSkySearch(all,
        chooseDarkSubset(request.sites, request.startUtc));
  }
  // Apparent V magnitudes at or brighter than +2.5. Positions are approximate
  // J2000 catalogue coordinates for pointing guidance, not solver inputs.
  // Catalogue provenance: Bright Star Catalogue, 5th Edition (BSC5P),
  // https://heasarc.gsfc.nasa.gov/W3Browse/catalog/bsc5p.html
  static const maxCatalogMagnitude = 2.5;
  static const brightStars = <GuideStar>[
    GuideStar('Sirius', 6.7525, -16.716, -1.46),
    GuideStar('Canopus', 6.3992, -52.696, -0.74),
    GuideStar('Arcturus', 14.261, 19.182, -0.05),
    GuideStar('Vega', 18.6156, 38.784, 0.03),
    GuideStar('Capella', 5.2782, 45.998, 0.08),
    GuideStar('Rigel', 5.2423, -8.202, 0.13),
    GuideStar('Procyon', 7.655, 5.225, 0.34),
    GuideStar('Betelgeuse', 5.9195, 7.407, 0.42),
    GuideStar('Achernar', 1.6286, -57.237, 0.46),
    GuideStar('Hadar', 14.0637, -60.374, 0.61),
    GuideStar('Acrux', 12.4433, -63.1, 0.77),
    GuideStar('Altair', 19.8464, 8.868, 0.77),
    GuideStar('Aldebaran', 4.5987, 16.509, 0.85),
    GuideStar('Spica', 13.4199, -11.161, 0.98),
    GuideStar('Antares', 16.4901, -26.432, 1.06),
    GuideStar('Fomalhaut', 22.9608, -29.622, 1.16),
    GuideStar('Deneb', 20.6905, 45.28, 1.25),
    GuideStar('Mimosa', 12.7953, -59.688, 1.25),
    GuideStar('Regulus', 10.1395, 11.968, 1.35),
    GuideStar('Pollux', 7.7553, 28.026, 1.14),
    GuideStar('Polaris', 2.5303, 89.2641, 1.98),
    GuideStar('Adhara', 6.9833, -29.0, 1.50),
    GuideStar('Castor', 7.5833, 31.9, 1.58),
    GuideStar('Gacrux', 12.5167, -57.1, 1.59),
    GuideStar('Shaula', 17.5667, -37.1, 1.62),
    GuideStar('Bellatrix', 5.4167, 6.3, 1.64),
    GuideStar('Elnath', 5.4333, 28.6, 1.65),
    GuideStar('Miaplacidus', 9.2167, -69.7, 1.67),
    GuideStar('Alnilam', 5.6000, -1.2, 1.69),
    GuideStar('Alnair', 22.1333, -47.0, 1.73),
    GuideStar('Alioth', 12.9000, 56.0, 1.76),
    GuideStar('Mirfak', 3.4000, 49.9, 1.79),
    GuideStar('Dubhe', 11.0667, 61.8, 1.81),
    GuideStar('Alkaid', 13.8000, 49.3, 1.85),
    GuideStar('Menkalinan', 6.0000, 44.9, 1.90),
    GuideStar('Atria', 16.8167, -69.0, 1.91),
    GuideStar('Peacock', 20.4333, -56.7, 1.94),
    GuideStar('Hamal', 2.1167, 23.5, 2.01),
    GuideStar('Nunki', 18.9167, -26.3, 2.05),
    GuideStar('Alpheratz', 0.1333, 29.1, 2.07),
    GuideStar('Mirach', 1.1667, 35.6, 2.07),
    GuideStar('Denebola', 11.8167, 14.6, 2.14),
    GuideStar('Sadr', 20.3667, 40.3, 2.23),
    GuideStar('Enif', 21.7333, 9.9, 2.38),
    GuideStar('Ankaa', 0.4333, -42.3, 2.40),
  ];

  /// First search all stations in the next 30 minutes. If that is impossible,
  /// lower required participation in 10% steps, never below 60% or three.
  static OpeningChoice? chooseOpening(List<int> includedCounts,
      List<int> minuteOffsets, int siteCount) {
    if (siteCount < 3 || includedCounts.length != minuteOffsets.length) {
      throw ArgumentError('Invalid opening-window counts');
    }
    final tried = <int>{};
    for (var percent = 100; percent >= 60; percent -= 10) {
      final required = math.max(3, (siteCount * percent + 99) ~/ 100);
      if (!tried.add(required)) continue;
      for (var i = 0; i < includedCounts.length; i++) {
        if (minuteOffsets[i] > 30) break;
        if (includedCounts[i] >= required) {
          return OpeningChoice(100 - percent, i, includedCounts[i]);
        }
      }
    }
    return null;
  }

  static int? chooseLaterToday(List<int> includedCounts,
      List<int> minuteOffsets, int minimumCount) {
    if (includedCounts.length != minuteOffsets.length) {
      throw ArgumentError('Invalid opening-window counts');
    }
    for (var i = 0; i < minuteOffsets.length; i++) {
      if (minuteOffsets[i] > openingDayMinutes) break;
      if (minuteOffsets[i] > 30 && includedCounts[i] >= minimumCount) {
        return i;
      }
    }
    return null;
  }

  // Reject nearly coincident or dependent star directions: three sightings
  // must constrain a ground normal, not merely fill three camera prompts.
  static bool independentTrio(GuideStar a, GuideStar b, GuideStar c) {
    List<double> direction(GuideStar star) {
      final dec = _rad(star.decDeg);
      final ra = _rad(star.raHours * 15);
      return [math.cos(dec) * math.cos(ra),
        math.cos(dec) * math.sin(ra), math.sin(dec)];
    }
    final x = direction(a), y = direction(b), z = direction(c);
    double dot(List<double> p, List<double> q) =>
        p[0] * q[0] + p[1] * q[1] + p[2] * q[2];
    if (dot(x, y) > math.cos(_rad(25)) ||
        dot(x, z) > math.cos(_rad(25)) ||
        dot(y, z) > math.cos(_rad(25))) return false;
    final det = x[0] * (y[1] * z[2] - y[2] * z[1]) +
        x[1] * (y[2] * z[0] - y[0] * z[2]) +
        x[2] * (y[0] * z[1] - y[1] * z[0]);
    return det.abs() >= 0.1;
  }

  /// Diagnostic for a member excluded from a proposed shared trio. This
  /// distinguishes unavailable sky from stars visible under another plan.
  static bool hasIndependentThreeSoon(SkyLocation site, DateTime startUtc,
      {bool demo = false}) {
    for (var minute = 0; minute <= 30; minute += 5) {
      final time = startUtc.toUtc().add(Duration(minutes: minute));
      if (!demo && sunAltitude(site.latitude, site.longitude, time) >= -8) {
        continue;
      }
      final visible = <GuideStar>[];
      for (final star in brightStars) {
        final altitude = horizontal(star, site.latitude,
          site.longitude, time).altitudeDeg;
        if (altitude >= 12 && altitude <= 85) visible.add(star);
      }
      for (var a = 0; a < visible.length - 2; a++) {
        for (var b = a + 1; b < visible.length - 1; b++) {
          for (var c = b + 1; c < visible.length; c++) {
            if (independentTrio(visible[a], visible[b], visible[c])) {
              return true;
            }
          }
        }
      }
    }
    return false;
  }

  /// A conservative proof of permanent incompatibility. If even the
  /// individual altitude ranges of three common stars cannot be reached at
  /// these latitudes, there cannot be an observing window for that trio.
  /// Keeping someone when the three individual ranges fail to overlap in
  /// time is safer than wrongly removing them based on a coarse time grid.
  static List<bool> geometricallyCompatible(GroupSkyRequest request) {
    final sites = request.sites;
    if (sites.length < 3) return List<bool>.filled(sites.length, false);
    final possible = <int>[];
    for (final site in sites) {
      var bits = 0;
      final phi = _rad(site.latitude);
      for (var i = 0; i < brightStars.length; i++) {
        final dec = _rad(brightStars[i].decDeg);
        final middle = math.sin(phi) * math.sin(dec);
        final swing = math.cos(phi) * math.cos(dec);
        final high = _deg(math.asin((middle + swing).clamp(-1.0, 1.0)));
        final low = _deg(math.asin((middle - swing).clamp(-1.0, 1.0)));
        if (high >= 12 && low <= 85) bits |= 1 << i;
      }
      possible.add(bits);
    }
    final threshold = math.max(3, (sites.length * 60 + 99) ~/ 100);
    final compatible = List<bool>.filled(sites.length, false);
    for (var a = 0; a < brightStars.length - 2; a++) {
      for (var b = a + 1; b < brightStars.length - 1; b++) {
        for (var c = b + 1; c < brightStars.length; c++) {
          if (!independentTrio(brightStars[a], brightStars[b],
              brightStars[c])) continue;
          final trio = (1 << a) | (1 << b) | (1 << c);
          final eligible = <int>[];
          for (var site = 0; site < sites.length; site++) {
            if ((possible[site] & trio) == trio) {
              eligible.add(site);
            }
          }
          if (eligible.length >= threshold) {
            for (final i in eligible) compatible[i] = true;
            if (compatible.every((value) => value)) return compatible;
          }
        }
      }
    }
    return compatible;
  }

  /// Every member gets their own feasible times for the *same* three stars.
  /// This planner predicts visibility; it does not contribute to the fit.
  static DistributedSkyPlan? planAcrossSites(List<SkyLocation> sites,
      DateTime startUtc, {bool demo = false, bool allowBlocked = false}) {
    if (sites.length < 3) return null;
    final start = startUtc.toUtc();
    final candidates = brightStars
      .where((star) => star.magnitude <= maxCatalogMagnitude).toList()
      ..sort((a, b) => a.magnitude.compareTo(b.magnitude));
    final preferred = sites.every((s) => s.latitude > 0) ? 'Polaris' :
        sites.every((s) => s.latitude < 0) ? 'Acrux' : null;
    // Search today's opening every five minutes for twelve hours. The
    // following day is available for members who could not observe during
    // today's opening; it is not another opening opportunity for the group.
    final minutes = <int>[
      for (var i = 0; i <= 144; i++) i * 5,
      for (var i = 49; i <= 190; i++) i * 15,
    ];
    final times = [for (final minute in minutes)
      start.add(Duration(minutes: minute))];
    // Bit masks make the expanded naked-eye catalogue inexpensive to scan.
    final masks = <List<int>>[];
    for (final site in sites) {
      final available = <int>[];
      for (final time in times) {
        var bits = 0;
        if (demo || sunAltitude(site.latitude, site.longitude, time) < -8) {
          for (var star = 0; star < candidates.length; star++) {
            final altitude = horizontal(candidates[star], site.latitude,
                site.longitude, time).altitudeDeg;
            if (altitude >= 12 && altitude <= 85) bits |= 1 << star;
          }
        }
        available.add(bits);
      }
      masks.add(available);
    }
    DistributedSkyPlan? best;
    List<int>? bestScore;
    bool isBetter(List<int> score, List<int>? previous) {
      if (previous == null) return true;
      for (var i = 0; i < score.length; i++) {
        if (score[i] != previous[i]) return score[i] < previous[i];
      }
      return false;
    }
    for (var a = 0; a < candidates.length - 2; a++) {
      for (var b = a + 1; b < candidates.length - 1; b++) {
        for (var c = b + 1; c < candidates.length; c++) {
          if (!independentTrio(candidates[a], candidates[b], candidates[c])) {
            continue;
          }
          final trio = (1 << a) | (1 << b) | (1 << c);
          final perSite = <List<SiteObservationWindow>>[];
          final firstMinutes = <int>[];
          for (var site = 0; site < sites.length; site++) {
            int? first;
            var previousIndex = -2;
            final windows = <SiteObservationWindow>[];
            for (var i = 0; i < times.length; i++) {
              if ((masks[site][i] & trio) != trio) continue;
              first ??= i;
              final until = times[i].add(Duration(minutes:
                minutes[i] < openingDayMinutes ? 5 : 15));
              if (windows.isNotEmpty && i == previousIndex + 1) {
                windows[windows.length - 1] = SiteObservationWindow(
                  windows.last.startUtc, until);
                previousIndex = i;
              } else if (windows.length < 3) {
                windows.add(SiteObservationWindow(times[i], until));
                previousIndex = i;
              }
            }
            // One shared star plan must still have a valid later window for
            // every member before the relay's 48-hour deadline.
            if (first == null && !allowBlocked) break;
            if (first != null) firstMinutes.add(minutes[first]);
            perSite.add(windows);
          }
          if (perSite.length != sites.length || firstMinutes.length < 3 ||
              (allowBlocked && perSite.first.isEmpty)) {
            continue;
          }

          final counts = <int>[];
          for (var i = 0; i < times.length; i++) {
            var included = 0;
            for (var site = 0; site < sites.length; site++) {
              if ((masks[site][i] & trio) == trio) included++;
            }
            counts.add(included);
          }
          final opening = chooseOpening(counts, minutes, sites.length);
          if (!allowBlocked && opening == null) continue;
          // A diagnosis can propose a trio for the currently available
          // stations, but it can never be sent as a group plan until the
          // original membership meets the 60% threshold and all have windows.
          final minimum = math.max(3, (sites.length * 60 + 99) ~/ 100);
          final nextIndex = opening == null ?
            chooseLaterToday(counts, minutes, minimum) : null;
          final diagnostic = opening ?? (allowBlocked ?
            chooseOpening(counts, minutes, firstMinutes.length) : null);
          final index = diagnostic?.timeIndex ?? nextIndex;
          if (index == null) continue;
          final sortedFirst = firstMinutes.toList()..sort();
          final firstTime = minutes[index];
          final tier = opening?.priority ?? 100;
          final score = <int>[
            if (allowBlocked) sites.length - firstMinutes.length,
            tier, firstTime,
            -(diagnostic?.included ?? counts[index]),
            sortedFirst.last,
            firstMinutes.reduce((sum, minute) => sum + minute),
            preferred != null &&
                ![candidates[a].name, candidates[b].name,
                  candidates[c].name].contains(preferred) ? 1 : 0,
            ((candidates[a].magnitude + candidates[b].magnitude +
                candidates[c].magnitude) * 100).round(),
          ];
          if (isBetter(score, bestScore)) {
            bestScore = score;
            best = DistributedSkyPlan([candidates[a], candidates[b],
              candidates[c]], perSite, openingReady: opening != null,
              nextOpeningUtc: nextIndex == null ? null : times[nextIndex]);
          }
        }
      }
    }
    return best;
  }

  static double _rad(double deg) => deg * math.pi / 180;
  static double _deg(double rad) => rad * 180 / math.pi;
  static double wrap(double value) => (value % 360 + 360) % 360;
  static double angularDelta(double a, double b) => (a - b + 540) % 360 - 180;

  static double julianDay(DateTime utc) =>
      utc.toUtc().millisecondsSinceEpoch / 86400000 + 2440587.5;

  /// USNO approximate GMST formula; UTC is adequate for coarse guidance.
  static double siderealDeg(DateTime utc) {
    final jd = julianDay(utc);
    final jd0 = (jd + 0.5).floorToDouble() - 0.5;
    final d = jd0 - 2451545.0;
    final h = (jd - jd0) * 24;
    final t = (jd - 2451545.0) / 36525;
    final gmstHours = 6.697375 + 0.065709824279 * d +
        1.0027379 * h + 0.0000258 * t * t;
    return wrap(gmstHours * 15);
  }

  static SkyTarget horizontal(GuideStar star, double latitude,
      double longitude, DateTime utc) {
    final phi = _rad(latitude), dec = _rad(star.decDeg);
    final hour = _rad(wrap(siderealDeg(utc) + longitude - 15 * star.raHours));
    final sinAltitude = math.sin(phi) * math.sin(dec) +
        math.cos(phi) * math.cos(dec) * math.cos(hour);
    final altitude = _deg(math.asin(sinAltitude.clamp(-1.0, 1.0)));
    final east = -math.cos(dec) * math.sin(hour);
    final north = math.sin(dec) * math.cos(phi) -
        math.cos(dec) * math.cos(hour) * math.sin(phi);
    return SkyTarget(star, wrap(_deg(math.atan2(east, north))), altitude);
  }

  /// Simple solar position for deciding whether to invite an observation now.
  static double sunAltitude(double latitude, double longitude, DateTime utc) {
    final d = julianDay(utc) - 2451545.0;
    final meanLongitude = _rad(wrap(280.46 + 0.9856474 * d));
    final anomaly = _rad(wrap(357.528 + 0.9856003 * d));
    final ecliptic = meanLongitude + _rad(1.915 * math.sin(anomaly) +
        0.020 * math.sin(2 * anomaly));
    final obliquity = _rad(23.439 - 0.0000004 * d);
    final ra = wrap(_deg(math.atan2(math.cos(obliquity) *
        math.sin(ecliptic), math.cos(ecliptic)))) / 15;
    final dec = _deg(math.asin(math.sin(obliquity) * math.sin(ecliptic)));
    return horizontal(GuideStar('Sun', ra, dec, -26.7),
        latitude, longitude, utc).altitudeDeg;
  }

  static DateTime nextDarkTime(double latitude, double longitude, DateTime now) {
    if (sunAltitude(latitude, longitude, now) < -6) return now.toUtc();
    for (var i = 1; i <= 72; i++) {
      final candidate = now.toUtc().add(Duration(minutes: i * 30));
      if (sunAltitude(latitude, longitude, candidate) < -6) return candidate;
    }
    return now.toUtc(); // Polar daylight: caller also checks darkness.
  }

  static List<SkyTarget> chooseThree(double latitude, double longitude,
      DateTime utc) {
    final visible = brightStars
        .map((s) => horizontal(s, latitude, longitude, utc))
        .where((s) => s.altitudeDeg >= 18 && s.altitudeDeg <= 78)
        .toList();
    visible.sort((a, b) => a.star.magnitude.compareTo(b.star.magnitude));
    final chosen = <SkyTarget>[];
    for (final candidate in visible) {
      if (chosen.every((previous) => _separation(previous, candidate) >= 30)) {
        chosen.add(candidate);
      }
      if (chosen.length == 3) break;
    }
    // Some latitudes/times have fewer than three widely separated bright stars.
    for (final candidate in visible) {
      if (chosen.length == 3) break;
      if (!chosen.contains(candidate)) chosen.add(candidate);
    }
    return chosen;
  }

  /// Search up to one year so a real next window can be reported as a countdown.
  /// A null result is an honest bounded search, not a fabricated future date.
  static CommonSkyWindow? chooseCommon(
      List<SkyLocation> sites, DateTime startUtc,
      {int lookaheadDays = 365}) {
    if (sites.length < 2) return null;
    final start = startUtc.toUtc();
    // Check the current dark sky first, with five minutes to send the plan.
    // The observing window is ±45 minutes, so an eligible group can aim now.
    for (var minutes = 5; minutes <= lookaheadDays * 1440; minutes += 15) {
      final when = start.add(Duration(minutes: minutes));
      if (!sites.every((site) =>
          sunAltitude(site.latitude, site.longitude, when) < -8)) {
        continue;
      }
      final stars = _commonStars(sites, when);
      if (stars != null) return CommonSkyWindow(when, stars);
    }
    return null;
  }

  /// Find a viable smaller group. Excluded sites are precisely the sites in
  /// daylight at the proposed time; all dark sites must see the same stars.
  /// Prefer including more people, then the earliest such window.
  static PartialSkyWindow? chooseDarkSubset(
      List<SkyLocation> sites, DateTime startUtc,
      {int lookaheadDays = 30}) {
    if (sites.length < 3) return null;
    final start = startUtc.toUtc();
    PartialSkyWindow? best;
    for (var minutes = 5; minutes <= lookaheadDays * 1440; minutes += 15) {
      final when = start.add(Duration(minutes: minutes));
      final indexes = [for (var i = 0; i < sites.length; i++)
        if (sunAltitude(sites[i].latitude, sites[i].longitude, when) < -8) i];
      if (indexes.length < 2 || indexes.length == sites.length ||
          (best != null && indexes.length <= best.includedIndexes.length)) {
        continue;
      }
      final included = [for (final i in indexes) sites[i]];
      final stars = _commonStars(included, when);
      if (stars != null) {
        best = PartialSkyWindow(CommonSkyWindow(when, stars), indexes);
        if (indexes.length == sites.length - 1) break;
      }
    }
    return best;
  }

  static List<GuideStar>? _commonStars(
      List<SkyLocation> sites, DateTime when) {
    final visible = [for (final star in brightStars)
      if (sites.every((site) {
        final alt = horizontal(star, site.latitude, site.longitude, when)
            .altitudeDeg;
        return alt >= 18 && alt <= 78;
      })) star];
    if (visible.length < 3) return null;
    final chosen = <GuideStar>[];
    for (final star in visible) {
      final target = horizontal(star, sites.first.latitude,
          sites.first.longitude, when);
      if (chosen.every((other) => _separation(target,
          horizontal(other, sites.first.latitude,
              sites.first.longitude, when)) >= 25)) {
        chosen.add(star);
      }
      if (chosen.length == 3) break;
    }
    if (chosen.length < 3) {
      for (final star in visible) {
        if (!chosen.contains(star)) chosen.add(star);
        if (chosen.length == 3) break;
      }
    }
    return chosen;
  }

  static double _separation(SkyTarget a, SkyTarget b) {
    final altA = _rad(a.altitudeDeg), altB = _rad(b.altitudeDeg);
    final daz = _rad(angularDelta(a.azimuthDeg, b.azimuthDeg));
    final dot = math.sin(altA) * math.sin(altB) +
        math.cos(altA) * math.cos(altB) * math.cos(daz);
    return _deg(math.acos(dot.clamp(-1.0, 1.0)));
  }
}
