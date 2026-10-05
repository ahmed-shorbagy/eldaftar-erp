import 'package:flutter/material.dart';

import '../../daily_ledger/application/idempotency_key.dart';
import '../../daily_ledger/presentation/opening_copy.dart';
import '../application/daily_note_submission.dart';
import '../application/note_draft_store.dart';
import '../application/notes_gateway.dart';
import '../domain/daily_note_draft.dart';
import 'daily_note_copy.dart';

class DailyNotesScreen extends StatefulWidget {
  const DailyNotesScreen({
    super.key,
    required this.gateway,
    required this.userId,
    required this.shopId,
    required this.drafts,
    required this.files,
    required this.images,
    this.businessDayId,
    this.canWrite = true,
    this.newKey,
  });

  final NotesGateway gateway;
  final String userId;
  final String shopId;
  final String? businessDayId;
  final bool canWrite;
  final NoteDraftStore drafts;
  final NoteImageFileStore files;
  final NoteImageSource images;
  final String Function()? newKey;

  @override
  State<DailyNotesScreen> createState() => _DailyNotesScreenState();
}

class _DailyNotesScreenState extends State<DailyNotesScreen> {
  final _text = TextEditingController();
  final _search = TextEditingController();
  final _textFocus = FocusNode();
  final _saveFocus = FocusNode();
  NoteAttachmentRef? _attachment;
  List<int>? _bytes;
  String? _idempotencyKey;
  DailyNoteDraft? _recorded;
  DailyNoteDraft? _pending;
  bool _pendingUncertain = false;
  String? _pendingUserId;
  String? _pendingShopId;
  String? _status;
  String? _error;
  bool _busy = false;
  bool _restoring = true;
  bool _restoreFailed = false;
  bool _loading = true;
  bool _failed = false;
  DailyNotePage? _page;
  String? _previewUrl;
  String? _previewFor;
  int _readGeneration = 0;
  int _screenGeneration = 0;

  @override
  void initState() {
    super.initState();
    _restore();
    _load();
  }

  @override
  void didUpdateWidget(DailyNotesScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final ownerChanged =
        oldWidget.userId != widget.userId || oldWidget.shopId != widget.shopId;
    final dayChanged = oldWidget.businessDayId != widget.businessDayId;
    if (!ownerChanged && !dayChanged) return;
    _screenGeneration += 1;
    final keepPending = !ownerChanged && _pendingUncertain && _pending != null;
    setState(() {
      _page = null;
      _previewUrl = null;
      _previewFor = null;
      _loading = true;
      _failed = false;
      _busy = false;
      _restoring = true;
      _restoreFailed = false;
      if (!keepPending) {
        _pending = null;
        _pendingUncertain = false;
        _pendingUserId = null;
        _pendingShopId = null;
        _recorded = null;
        _text.clear();
        _attachment = null;
        _bytes = null;
        _idempotencyKey = null;
        _status = null;
        _error = null;
      }
    });
    _restore();
    _load();
  }

  @override
  void dispose() {
    _text.dispose();
    _search.dispose();
    _textFocus.dispose();
    _saveFocus.dispose();
    super.dispose();
  }

  bool _sameScreen(int generation, String userId, String shopId) =>
      mounted &&
      generation == _screenGeneration &&
      widget.userId == userId &&
      widget.shopId == shopId;

  Future<void> _restore() async {
    final generation = _screenGeneration;
    final user = widget.userId;
    final shop = widget.shopId;
    setState(() {
      _restoring = true;
      _restoreFailed = false;
      _status = DailyNoteCopy.restoring;
      _error = null;
    });
    try {
      // A pending in-memory request retains its original business day.
      final stored = _pendingUncertain && _pending != null
          ? null
          : await widget.drafts.read(userId: user, shopId: shop);
      if (!_sameScreen(generation, user, shop)) return;
      if (stored != null) {
        if (stored.userId != user || stored.shopId != shop) {
          throw StateError('Draft ownership mismatch');
        }
        _freezeDraft(stored.toDraft(), user);
      }
      final draft = _pending;
      if (draft != null) {
        await _restoreStatus(draft, generation, user, shop);
      } else {
        setState(() => _status = null);
      }
    } catch (_) {
      if (!_sameScreen(generation, user, shop)) return;
      setState(() {
        _restoreFailed = true;
        _status = null;
        _error = DailyNoteCopy.restoreFailed;
      });
    } finally {
      if (_sameScreen(generation, user, shop)) {
        setState(() => _restoring = false);
      }
    }
  }

  void _freezeDraft(DailyNoteDraft draft, String user) {
    setState(() {
      _pending = draft;
      _pendingUncertain = true;
      _pendingUserId = user;
      _pendingShopId = draft.shopId;
      _recorded = draft;
      _idempotencyKey = draft.idempotencyKey;
      _text.text = draft.text;
      _attachment = draft.attachment;
      _status = DailyNoteCopy.confirming;
      _error = DailyNoteCopy.frozen;
    });
  }

  Future<void> _restoreStatus(
    DailyNoteDraft draft,
    int generation,
    String user,
    String shop,
  ) async {
    final status = await _reconcile(draft.idempotencyKey);
    if (!_sameScreen(generation, user, shop) || status == null) return;
    if (status is NoteStatusCompleted) {
      await _markConfirmed(draft);
    } else if (status is NoteStatusAbsent) {
      setState(() {
        _pending = null;
        _pendingUncertain = false;
        _pendingUserId = null;
        _pendingShopId = null;
        _status = DailyNoteCopy.localDraft;
        _error = draft.businessDayId != widget.businessDayId
            ? noteFailureCopy('stale_day')
            : null;
      });
    } else {
      _freezeDraft(draft, user);
      if (status is NoteStatusRejected) {
        setState(() => _error = noteFailureCopy(status.code));
      }
    }
  }

  Future<void> _retryRestore() async {
    if (_busy || _restoring) return;
    await _restore();
  }

  Future<void> _load({String? before}) async {
    final generation = ++_readGeneration;
    final user = widget.userId;
    final shop = widget.shopId;
    final day = widget.businessDayId;
    final query = _query();
    if (mounted) {
      setState(() {
        _loading = true;
        _failed = false;
      });
    }
    try {
      final page = await widget.gateway.listNotes(
        callerUserId: user,
        shopId: shop,
        dayId: day,
        beforeSequence: before,
        query: query,
        limit: 30,
      );
      if (!mounted || generation != _readGeneration) return;
      if (widget.userId != user ||
          widget.shopId != shop ||
          widget.businessDayId != day) {
        return;
      }
      if (page.shopId != shop) return;
      if (day != null && page.dayId != null && page.dayId != day) return;
      setState(() {
        if (before == null || _page == null) {
          _page = page;
        } else {
          final seen = _page!.items.map((item) => item.noteId).toSet();
          _page = DailyNotePage(
            shopId: page.shopId,
            dayId: page.dayId,
            limit: page.limit,
            hasMore: page.hasMore,
            serverSequence: page.serverSequence,
            snapshotSequence: page.snapshotSequence,
            nextBeforeSequence: page.nextBeforeSequence,
            items: [
              ..._page!.items,
              for (final item in page.items)
                if (seen.add(item.noteId)) item,
            ],
          );
        }
        _loading = false;
      });
    } on NoteReadException catch (error) {
      if (!mounted || generation != _readGeneration) return;
      setState(() {
        _loading = false;
        _failed = true;
        _error = noteFailureCopy(error.code);
      });
    } catch (_) {
      if (!mounted || generation != _readGeneration) return;
      setState(() {
        _loading = false;
        _failed = true;
        _error = noteFailureCopy(null);
      });
    }
  }

  String? _query() {
    final text = _search.text.trim();
    if (text.isEmpty) return null;
    if (text.runes.length > noteSearchMaxChars) return null;
    return text;
  }

  Future<void> _persist(DailyNoteDraft draft, String user) async {
    final drafts = widget.drafts;
    final files = widget.files;
    final bytes = _bytes;
    final attachment = draft.attachment;
    if (attachment != null && bytes != null) {
      await files.write(
        userId: user,
        shopId: draft.shopId,
        clientObjectId: attachment.clientObjectId,
        bytes: bytes,
      );
    }
    await drafts.save(userId: user, draft: draft);
  }

  Future<void> _freezeRecorded(int generation, String user, String shop) async {
    if (!_sameScreen(generation, user, shop)) return;
    final frozen = _recorded;
    if (frozen == null) return;
    _freezeDraft(frozen, user);
  }

  Future<void> _markConfirmed(DailyNoteDraft draft) async {
    final generation = _screenGeneration;
    final user = widget.userId;
    await cleanupConfirmedNote(
      drafts: widget.drafts,
      files: widget.files,
      userId: user,
      draft: draft,
    );
    if (!_sameScreen(generation, user, draft.shopId)) return;
    setState(() {
      _pending = null;
      _pendingUncertain = false;
      _pendingUserId = null;
      _pendingShopId = null;
      _recorded = null;
      _text.clear();
      _attachment = null;
      _bytes = null;
      _idempotencyKey = null;
      _previewUrl = null;
      _status = DailyNoteCopy.confirmed;
      _error = null;
    });
    await _load();
  }

  Future<NoteStatusResult?> _reconcile(String key) async {
    final generation = _screenGeneration;
    final user = widget.userId;
    final shop = widget.shopId;
    NoteStatusResult status;
    try {
      status = await widget.gateway.noteStatus(
        callerUserId: user,
        idempotencyKey: key,
      );
    } catch (_) {
      status = const NoteStatusUnknown();
    }
    if (!_sameScreen(generation, user, shop)) return null;
    return status;
  }

  Future<void> _pick() async {
    if (_busy ||
        _restoring ||
        _restoreFailed ||
        !widget.canWrite ||
        _pendingUncertain) {
      return;
    }
    await _runAction(_pickUnlocked);
  }

  Future<void> _runAction(Future<void> Function() action) async {
    final generation = _screenGeneration;
    final user = widget.userId;
    final shop = widget.shopId;
    setState(() => _busy = true);
    try {
      await action();
    } catch (_) {
      if (!_sameScreen(generation, user, shop)) return;
      if (_recorded != null) _freezeDraft(_recorded!, user);
      setState(() => _error = DailyNoteCopy.frozen);
    } finally {
      if (_sameScreen(generation, user, shop)) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _pickUnlocked() async {
    final generation = _screenGeneration;
    final user = widget.userId;
    final shop = widget.shopId;
    var knownAbsent = _idempotencyKey == null;
    if (_idempotencyKey != null) {
      final status = await _reconcile(_idempotencyKey!);
      if (!_sameScreen(generation, user, shop) || status == null) return;
      if (status is! NoteStatusAbsent && status is! NoteStatusCompleted) {
        await _freezeRecorded(generation, user, shop);
        return;
      }
      if (status is NoteStatusCompleted) {
        final draft =
            _recorded ??
            (await widget.drafts.read(userId: user, shopId: shop))?.toDraft();
        if (draft == null || !_sameScreen(generation, user, shop)) return;
        await _markConfirmed(draft);
        return;
      }
      knownAbsent = status is NoteStatusAbsent;
    }
    final selected = await widget.images.pickImage();
    if (!_sameScreen(generation, user, shop) ||
        selected == null ||
        _pendingUncertain) {
      return;
    }
    final day = widget.businessDayId;
    if (day == null) {
      setState(() => _error = noteFailureCopy('day_closed'));
      return;
    }
    final previous = _bytes;
    final changed = previous != null && !_sameBytes(previous, selected.bytes);
    final objectId = changed
        ? newIdempotencyKey()
        : (_attachment?.clientObjectId ??
              (widget.newKey ?? newIdempotencyKey)());
    var idempotencyKey =
        _idempotencyKey ?? (widget.newKey ?? newIdempotencyKey)();
    var decision = _compose(
      idempotencyKey: idempotencyKey,
      day: day,
      objectId: objectId,
      mimeType: selected.mimeType,
      fileName: selected.name,
      bytes: selected.bytes,
    );
    if (decision.draft != null &&
        _recorded != null &&
        knownAbsent &&
        !_sameBody(decision.draft!, _recorded!)) {
      idempotencyKey = newIdempotencyKey();
      decision = _compose(
        idempotencyKey: idempotencyKey,
        day: day,
        objectId: objectId,
        mimeType: selected.mimeType,
        fileName: selected.name,
        bytes: selected.bytes,
      );
    }
    if (!decision.isAccepted || decision.draft?.attachment == null) {
      setState(
        () => _error = noteFailureCopy(decision.code ?? 'attachment_rejected'),
      );
      return;
    }
    final draft = decision.draft!;
    setState(() {
      _idempotencyKey = draft.idempotencyKey;
      _recorded = draft;
      _attachment = draft.attachment;
      _bytes = selected.bytes;
      _status = DailyNoteCopy.localDraft;
      _error = null;
    });
    try {
      await _persist(draft, user);
    } catch (_) {
      if (!_sameScreen(generation, user, shop)) return;
      setState(() => _error = noteFailureCopy('local_persistence'));
    }
  }

  NoteDraftDecision _compose({
    required String idempotencyKey,
    required String day,
    String? objectId,
    String? mimeType,
    String? fileName,
    List<int>? bytes,
  }) {
    return composeDailyNote(
      idempotencyKey: idempotencyKey,
      shopId: widget.shopId,
      businessDayId: day,
      text: _text.text,
      clientObjectId: objectId,
      mimeType: mimeType,
      fileName: fileName,
      bytes: bytes,
    );
  }

  Future<void> _save() async {
    if (_busy || _restoring || _restoreFailed || !widget.canWrite) return;
    await _runAction(_saveUnlocked);
  }

  Future<void> _saveUnlocked() async {
    if (_pendingUncertain && _pending != null) {
      if (_pendingUserId != widget.userId || _pendingShopId != widget.shopId) {
        return;
      }
      await _submit(_pending!, bytes: _bytes);
      return;
    }
    final generation = _screenGeneration;
    final user = widget.userId;
    final shop = widget.shopId;
    var knownAbsent = _idempotencyKey == null;
    if (_idempotencyKey != null) {
      final status = await _reconcile(_idempotencyKey!);
      if (!_sameScreen(generation, user, shop) || status == null) return;
      if (status is! NoteStatusAbsent && status is! NoteStatusCompleted) {
        await _freezeRecorded(generation, user, shop);
        return;
      }
      if (status is NoteStatusCompleted) {
        final draft =
            _recorded ??
            (await widget.drafts.read(userId: user, shopId: shop))?.toDraft();
        if (draft == null || !_sameScreen(generation, user, shop)) return;
        await _markConfirmed(draft);
        return;
      }
      knownAbsent = status is NoteStatusAbsent;
    }
    if (!_sameScreen(generation, user, shop)) return;
    final day = widget.businessDayId;
    if (day == null) {
      setState(() => _error = noteFailureCopy('day_closed'));
      return;
    }
    var bytes = _bytes;
    final existing = _attachment;
    if (existing != null && bytes == null) {
      try {
        bytes = await widget.files.read(
          userId: user,
          shopId: shop,
          clientObjectId: existing.clientObjectId,
        );
      } catch (_) {
        if (!_sameScreen(generation, user, shop)) return;
        setState(() => _error = noteFailureCopy('local_persistence'));
        return;
      }
      if (bytes == null) {
        if (!_sameScreen(generation, user, shop)) return;
        setState(() => _error = noteFailureCopy('attachment_missing'));
        return;
      }
    }
    if (!_sameScreen(generation, user, shop)) return;
    var idempotencyKey =
        _idempotencyKey ?? (widget.newKey ?? newIdempotencyKey)();
    var decision = _compose(
      idempotencyKey: idempotencyKey,
      day: day,
      objectId: existing?.clientObjectId,
      mimeType: existing?.mimeType,
      fileName: existing == null ? null : 'note.${existing.extension}',
      bytes: bytes,
    );
    if (decision.draft != null &&
        _recorded != null &&
        knownAbsent &&
        !_sameBody(decision.draft!, _recorded!)) {
      idempotencyKey = newIdempotencyKey();
      decision = _compose(
        idempotencyKey: idempotencyKey,
        day: day,
        objectId: existing?.clientObjectId,
        mimeType: existing?.mimeType,
        fileName: existing == null ? null : 'note.${existing.extension}',
        bytes: bytes,
      );
    }
    if (!decision.isAccepted || decision.draft == null) {
      setState(() => _error = noteFailureCopy(decision.code));
      return;
    }
    await _submit(decision.draft!, bytes: bytes);
  }

  Future<void> _submit(DailyNoteDraft draft, {List<int>? bytes}) async {
    final generation = _screenGeneration;
    final user = _pendingUncertain
        ? (_pendingUserId ?? widget.userId)
        : widget.userId;
    setState(() {
      _busy = true;
      _idempotencyKey = draft.idempotencyKey;
      _recorded = draft;
      _status = draft.attachment == null
          ? DailyNoteCopy.confirming
          : DailyNoteCopy.uploading;
      _error = null;
    });
    final outcome =
        await DailyNoteSubmission(
          gateway: widget.gateway,
          drafts: widget.drafts,
          files: widget.files,
        ).submit(
          userId: user,
          sessionShopId: draft.shopId,
          draft: draft,
          imageBytes: bytes ?? _bytes,
        );
    if (!_sameScreen(generation, user, draft.shopId)) return;
    setState(() {
      if (outcome.phase == NoteSubmitPhase.confirming) {
        _pending = draft;
        _pendingUncertain = true;
        _pendingUserId = user;
        _pendingShopId = draft.shopId;
        _recorded = draft;
        _text.text = draft.text;
        _attachment = draft.attachment;
        _idempotencyKey = draft.idempotencyKey;
      } else if (outcome.isConfirmed) {
        _pending = null;
        _pendingUncertain = false;
        _pendingUserId = null;
        _pendingShopId = null;
        _recorded = null;
        _text.clear();
        _attachment = null;
        _bytes = null;
        _idempotencyKey = null;
        _previewUrl = null;
      }
      _status = switch (outcome.phase) {
        NoteSubmitPhase.confirmed => DailyNoteCopy.confirmed,
        NoteSubmitPhase.uploading => DailyNoteCopy.uploading,
        NoteSubmitPhase.uploadFailed => outcome.messageAr,
        NoteSubmitPhase.confirming => DailyNoteCopy.confirming,
        NoteSubmitPhase.localDraft => DailyNoteCopy.localDraft,
        NoteSubmitPhase.rejected => outcome.messageAr,
      };
      _error = outcome.isConfirmed ? null : outcome.messageAr;
    });
    if (outcome.isConfirmed && generation == _screenGeneration) await _load();
  }

  Future<void> _preview(DailyNoteView note) async {
    final attachment = note.attachment;
    if (attachment == null) return;
    final generation = _readGeneration;
    final user = widget.userId;
    final shop = widget.shopId;
    final day = widget.businessDayId;
    try {
      final detail = await widget.gateway.noteDetail(
        callerUserId: user,
        shopId: shop,
        noteId: note.noteId,
      );
      if (!mounted ||
          generation != _readGeneration ||
          widget.userId != user ||
          widget.shopId != shop ||
          widget.businessDayId != day) {
        return;
      }
      final objectName = detail.attachment?.objectName;
      if (objectName == null) return;
      final url = await widget.gateway.noteReadUrl(
        callerUserId: user,
        objectName: objectName,
      );
      if (!mounted ||
          generation != _readGeneration ||
          widget.userId != user ||
          widget.shopId != shop ||
          widget.businessDayId != day) {
        return;
      }
      setState(() {
        _previewUrl = url;
        _previewFor = note.noteId;
      });
    } on NoteReadException catch (error) {
      if (!mounted || generation != _readGeneration) return;
      setState(() => _error = noteFailureCopy(error.code));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final items = _page?.items ?? const <DailyNoteView>[];
    final editingLocked =
        _busy || _restoring || _restoreFailed || _pendingUncertain;
    final canSave =
        widget.canWrite &&
        !_busy &&
        !_restoring &&
        !_restoreFailed &&
        ((_pendingUncertain && _pending != null) ||
            _text.text.trim().isNotEmpty ||
            _attachment != null);
    return Scaffold(
      appBar: AppBar(title: const Text(DailyNoteCopy.helpTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_restoring) ...[
            const LinearProgressIndicator(key: Key('daily-note-restoring')),
            const SizedBox(height: 12),
          ],
          if (!widget.canWrite)
            Text(
              widget.businessDayId == null
                  ? noteFailureCopy('day_closed')
                  : noteFailureCopy('shop_not_active'),
            ),
          TextField(
            key: const Key('daily-note-text'),
            controller: _text,
            focusNode: _textFocus,
            enabled: widget.canWrite && !editingLocked,
            style: _pendingUncertain
                ? theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.onSurface,
                  )
                : null,
            minLines: 3,
            maxLines: 6,
            decoration: const InputDecoration(
              labelText: DailyNoteCopy.textLabel,
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            key: const Key('daily-note-attach'),
            onPressed: widget.canWrite && !editingLocked ? _pick : null,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
            icon: const Icon(Icons.image_outlined),
            label: Text(
              _attachment == null ? DailyNoteCopy.attach : 'تم اختيار صورة',
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(
            key: const Key('daily-note-save'),
            focusNode: _saveFocus,
            onPressed: canSave ? _save : null,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
            child: Text(
              _pendingUncertain
                  ? DailyNoteCopy.retrySameRequest
                  : DailyNoteCopy.save,
            ),
          ),
          if (_status != null) ...[
            const SizedBox(height: 12),
            Text(_status!, key: const Key('daily-note-status')),
          ],
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              key: const Key('daily-note-error'),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ],
          if (_restoreFailed || _pendingUncertain) ...[
            const SizedBox(height: 12),
            OutlinedButton(
              key: const Key('daily-note-reconcile'),
              onPressed: _busy || _restoring ? null : _retryRestore,
              child: Text(
                _restoreFailed
                    ? DailyNoteCopy.retryRestore
                    : DailyNoteCopy.reconcile,
              ),
            ),
          ],
          const SizedBox(height: 20),
          TextField(
            key: const Key('daily-note-search'),
            controller: _search,
            decoration: const InputDecoration(
              labelText: DailyNoteCopy.searchLabel,
            ),
            onSubmitted: (value) {
              if (value.trim().runes.length > noteSearchMaxChars) {
                setState(() => _error = noteFailureCopy('invalid_input'));
                return;
              }
              _load();
            },
          ),
          const SizedBox(height: 12),
          if (_loading)
            const LinearProgressIndicator(key: Key('daily-notes-loading'))
          else if (_failed)
            const Text('تعذر تحميل الملاحظات')
          else if (items.isEmpty)
            const Text(DailyNoteCopy.empty, key: Key('daily-notes-empty'))
          else
            for (final note in items)
              ListTile(
                key: Key('daily-note-${note.noteId}'),
                title: Text(note.text.isEmpty ? 'صورة' : note.text),
                subtitle: Text(
                  '${note.actorDisplayName} · ${formatServerCairoTimestamp(note.occurredAtShop)} · ${note.shopSequence}',
                ),
                onTap: note.attachment == null ? null : () => _preview(note),
              ),
          if (_previewUrl != null && _previewFor != null) ...[
            const SizedBox(height: 8),
            Image.network(
              _previewUrl!,
              key: Key('daily-note-preview-$_previewFor'),
              height: 160,
              errorBuilder: (_, _, _) => const Text('تعذرت معاينة الصورة'),
            ),
            TextButton(
              key: const Key('daily-note-refresh-preview'),
              onPressed: () {
                final match = items.where((item) => item.noteId == _previewFor);
                if (match.isEmpty) return;
                _preview(match.first);
              },
              style: TextButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
              child: const Text(DailyNoteCopy.refreshPreview),
            ),
          ],
          if (_page?.hasMore == true)
            OutlinedButton(
              key: const Key('daily-notes-older'),
              onPressed: _loading
                  ? null
                  : () => _load(before: _page?.nextBeforeSequence),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
              child: const Text(DailyNoteCopy.older),
            ),
        ],
      ),
    );
  }
}

bool _sameBytes(List<int> left, List<int> right) {
  if (identical(left, right)) return true;
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

bool _sameBody(DailyNoteDraft left, DailyNoteDraft right) {
  final leftImage = left.attachment;
  final rightImage = right.attachment;
  return left.businessDayId == right.businessDayId &&
      left.text == right.text &&
      leftImage?.clientObjectId == rightImage?.clientObjectId &&
      leftImage?.mimeType == rightImage?.mimeType &&
      leftImage?.extension == rightImage?.extension &&
      leftImage?.byteSize == rightImage?.byteSize;
}
