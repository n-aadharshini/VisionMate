import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

class TransportQueryService {
  Database? _db;

  Future<void> ensureDatabase() async {
    if (_db != null) return;
    final dir = await getApplicationDocumentsDirectory();
    final dbPath = p.join(dir.path, 'transit.db');

    final exists = await databaseExists(dbPath);
    if (!exists) {
      final blob = await rootBundle.load('assets/data/transit.db');
      final bytes = blob.buffer.asUint8List();
      await File(dbPath).writeAsBytes(bytes);
    }
    _db = await openDatabase(dbPath);
  }

  Database get _database {
    final db = _db;
    if (db == null) {
      throw StateError('TransportQueryService not initialized. Call ensureDatabase() first.');
    }
    return db;
  }

  Future<List<Map<String, dynamic>>> busesToDestination(
    String destinationName, {
    int limit = 5,
  }) async {
    final db = _database;
    final rows = await db.rawQuery('''
      SELECT DISTINCT r.route_short_name, r.route_long_name, r.route_id
      FROM stops s
      JOIN stop_times st ON st.stop_id = s.stop_id
      JOIN trips t ON t.trip_id = st.trip_id
      JOIN routes r ON r.route_id = t.route_id
      WHERE s.stop_name LIKE ?
      LIMIT ?
    ''', ['%$destinationName%', limit]);
    return rows;
  }

  Future<List<Map<String, dynamic>>> busesBetween(
    String originName,
    String destinationName, {
    int limit = 5,
  }) async {
    final db = _database;
    final rows = await db.rawQuery('''
      SELECT DISTINCT r.route_short_name, r.route_long_name, r.route_id
      FROM stop_times st_o
      JOIN stops s_o ON s_o.stop_id = st_o.stop_id
      JOIN stop_times st_d ON st_d.trip_id = st_o.trip_id
          AND st_d.stop_sequence > st_o.stop_sequence
      JOIN stops s_d ON s_d.stop_id = st_d.stop_id
      JOIN trips t ON t.trip_id = st_o.trip_id
      JOIN routes r ON r.route_id = t.route_id
      WHERE s_o.stop_name LIKE ? AND s_d.stop_name LIKE ?
      LIMIT ?
    ''', ['%$originName%', '%$destinationName%', limit]);
    return rows;
  }

  Future<List<Map<String, dynamic>>> routeScheduleAtStop(
    String routeShortName,
    String stopName, {
    int limit = 10,
  }) async {
    final db = _database;
    final rows = await db.rawQuery('''
      SELECT st.arrival_time, s.stop_name, r.route_short_name
      FROM stop_times st
      JOIN trips t ON t.trip_id = st.trip_id
      JOIN routes r ON r.route_id = t.route_id
      JOIN stops s ON s.stop_id = st.stop_id
      WHERE r.route_short_name = ? AND s.stop_name LIKE ?
      ORDER BY st.arrival_time
      LIMIT ?
    ''', [routeShortName, '%$stopName%', limit]);
    return rows;
  }

  Future<int?> approximateHeadwayMinutes(
    String routeShortName,
    String stopName,
  ) async {
    final rows = await routeScheduleAtStop(routeShortName, stopName, limit: 200);
    final times = rows
        .map((r) => r['arrival_time'] as String?)
        .where((t) => t != null && t.isNotEmpty)
        .map((t) => t!)
        .toList()
      ..sort();
    if (times.length < 2) return null;

    int toMinutes(String t) {
      final parts = t.split(':');
      return int.parse(parts[0]) * 60 + int.parse(parts[1]);
    }

    final mins = times.map(toMinutes).toList();
    final gaps = <int>[];
    for (var i = 1; i < mins.length; i++) {
      if (mins[i] > mins[i - 1]) gaps.add(mins[i] - mins[i - 1]);
    }
    if (gaps.isEmpty) return null;
    return (gaps.reduce((a, b) => a + b) / gaps.length).round();
  }

  Future<List<Map<String, dynamic>>> findStops(
    String query, {
    int limit = 5,
  }) async {
    final db = _database;
    final rows = await db.rawQuery('''
      SELECT stop_id, stop_name, stop_lat, stop_lon
      FROM stops
      WHERE stop_name LIKE ?
      LIMIT ?
    ''', ['%$query%', limit]);
    return rows;
  }

  void dispose() {
    _db?.close();
    _db = null;
  }
}
