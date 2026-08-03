import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/leaderboard_entry.dart';
import '../models/waste_transaction.dart';
import 'connectivity_service.dart';
import 'preferences_service.dart';

/// Single gateway to persisted transactions. Provides an offline-first write
/// path (queue locally, sync when online) and live merged read streams that
/// include not-yet-synced local records.
class TransactionRepository {
  TransactionRepository({
    required FirebaseFirestore firestore,
    required PreferencesService prefs,
    required ConnectivityService connectivity,
  })  : _firestore = firestore,
        _prefs = prefs,
        _connectivity = connectivity {
    // Flush the queue whenever connectivity is (re)established.
    _connSub = _connectivity.onStatusChange.listen((online) {
      if (online) flushQueue();
    });
  }

  final FirebaseFirestore _firestore;
  final PreferencesService _prefs;
  final ConnectivityService _connectivity;

  StreamSubscription? _connSub;
  // Broadcasts whenever the local offline queue changes, so merged read
  // streams re-emit even without a Firestore event.
  final _queuePing = StreamController<void>.broadcast();

  CollectionReference<Map<String, dynamic>> get _col =>
      _firestore.collection('plastic_transactions');

  int get pendingCount => _prefs.queuedTransactions.length;

  // --- Writes ---------------------------------------------------------------

  /// Records a transaction. Attempts a live Firestore write; on any failure
  /// (offline, permission, timeout) it lands in the durable local queue and is
  /// retried automatically later. Returns `true` if it synced immediately.
  Future<bool> mint(WasteTransaction tx) async {
    final online = await _connectivity.isOnline;
    if (!online) {
      await _enqueue(tx);
      return false;
    }
    try {
      await _col.add(tx.toFirestore());
      return true;
    } catch (_) {
      await _enqueue(tx);
      return false;
    }
  }

  Future<void> _enqueue(WasteTransaction tx) async {
    await _prefs.enqueue(
      tx.copyWith(status: TransactionStatus.pendingSync).toJson(),
    );
    _queuePing.add(null);
  }

  /// Pushes every queued transaction to Firestore. Survivors of failed writes
  /// stay in the queue for the next attempt. Returns the count synced.
  Future<int> flushQueue() async {
    final queued = _prefs.queuedTransactions;
    if (queued.isEmpty) return 0;

    final remaining = <Map<String, dynamic>>[];
    var synced = 0;
    for (final json in queued) {
      try {
        final tx = WasteTransaction.fromJson(json)
            .copyWith(status: TransactionStatus.verified);
        await _col.add(tx.toFirestore());
        synced++;
      } catch (_) {
        remaining.add(json); // keep for retry
      }
    }
    await _prefs.saveQueue(remaining);
    _queuePing.add(null);
    return synced;
  }

  // --- Reads ----------------------------------------------------------------

  List<WasteTransaction> _pendingFor(String? userId) {
    return _prefs.queuedTransactions
        .map(WasteTransaction.fromJson)
        .where((t) => userId == null || t.userId == userId)
        .toList();
  }

  /// Live stream of a single user's transactions, newest first, merged with any
  /// pending offline records so the UI reflects them instantly.
  Stream<List<WasteTransaction>> watchUserTransactions(String userId) {
    final controller = StreamController<List<WasteTransaction>>.broadcast();
    var remote = <WasteTransaction>[];

    void emit() {
      final pending = _pendingFor(userId);
      final remoteIds = remote.map((e) => e.id).toSet();
      final merged = [
        ...pending.where((p) => !remoteIds.contains(p.id)),
        ...remote,
      ]..sort((a, b) => b.timestamp.compareTo(a.timestamp));
      if (!controller.isClosed) controller.add(merged);
    }

    // Avoid a composite-index requirement by sorting client-side.
    final sub = _col
        .where('user_id', isEqualTo: userId)
        .snapshots()
        .listen(
      (snap) {
        remote = snap.docs.map(WasteTransaction.fromFirestore).toList();
        emit();
      },
      onError: (_) => emit(),
    );
    final pingSub = _queuePing.stream.listen((_) => emit());

    controller.onCancel = () {
      sub.cancel();
      pingSub.cancel();
    };
    emit(); // seed with pending records immediately
    return controller.stream;
  }

  /// Live global feed (capped) used for the exchange totals & leaderboard.
  Stream<List<WasteTransaction>> watchGlobalTransactions({int limit = 500}) {
    return _col
        .orderBy('timestamp', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs.map(WasteTransaction.fromFirestore).toList());
  }

  /// Aggregates the global feed into a ranked leaderboard by contributor.
  Stream<List<LeaderboardEntry>> watchLeaderboard({int limit = 500}) {
    return watchGlobalTransactions(limit: limit).map(
      (txns) => LeaderboardEntry.rankAll(txns),
    );
  }

  void dispose() {
    _connSub?.cancel();
    _queuePing.close();
  }
}
