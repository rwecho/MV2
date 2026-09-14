// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'cache_database.dart';

// ignore_for_file: type=lint
class $HttpCacheEntriesTable extends HttpCacheEntries
    with TableInfo<$HttpCacheEntriesTable, HttpCacheEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $HttpCacheEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _urlMeta = const VerificationMeta('url');
  @override
  late final GeneratedColumn<String> url = GeneratedColumn<String>(
    'url',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _bodyMeta = const VerificationMeta('body');
  @override
  late final GeneratedColumn<String> body = GeneratedColumn<String>(
    'body',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _fetchedAtMeta = const VerificationMeta(
    'fetchedAt',
  );
  @override
  late final GeneratedColumn<DateTime> fetchedAt = GeneratedColumn<DateTime>(
    'fetched_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [url, body, fetchedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'http_cache_entries';
  @override
  VerificationContext validateIntegrity(
    Insertable<HttpCacheEntry> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('url')) {
      context.handle(
        _urlMeta,
        url.isAcceptableOrUnknown(data['url']!, _urlMeta),
      );
    } else if (isInserting) {
      context.missing(_urlMeta);
    }
    if (data.containsKey('body')) {
      context.handle(
        _bodyMeta,
        body.isAcceptableOrUnknown(data['body']!, _bodyMeta),
      );
    } else if (isInserting) {
      context.missing(_bodyMeta);
    }
    if (data.containsKey('fetched_at')) {
      context.handle(
        _fetchedAtMeta,
        fetchedAt.isAcceptableOrUnknown(data['fetched_at']!, _fetchedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_fetchedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {url};
  @override
  HttpCacheEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return HttpCacheEntry(
      url: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}url'],
      )!,
      body: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}body'],
      )!,
      fetchedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}fetched_at'],
      )!,
    );
  }

  @override
  $HttpCacheEntriesTable createAlias(String alias) {
    return $HttpCacheEntriesTable(attachedDatabase, alias);
  }
}

class HttpCacheEntry extends DataClass implements Insertable<HttpCacheEntry> {
  final String url;
  final String body;
  final DateTime fetchedAt;
  const HttpCacheEntry({
    required this.url,
    required this.body,
    required this.fetchedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['url'] = Variable<String>(url);
    map['body'] = Variable<String>(body);
    map['fetched_at'] = Variable<DateTime>(fetchedAt);
    return map;
  }

  HttpCacheEntriesCompanion toCompanion(bool nullToAbsent) {
    return HttpCacheEntriesCompanion(
      url: Value(url),
      body: Value(body),
      fetchedAt: Value(fetchedAt),
    );
  }

  factory HttpCacheEntry.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return HttpCacheEntry(
      url: serializer.fromJson<String>(json['url']),
      body: serializer.fromJson<String>(json['body']),
      fetchedAt: serializer.fromJson<DateTime>(json['fetchedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'url': serializer.toJson<String>(url),
      'body': serializer.toJson<String>(body),
      'fetchedAt': serializer.toJson<DateTime>(fetchedAt),
    };
  }

  HttpCacheEntry copyWith({String? url, String? body, DateTime? fetchedAt}) =>
      HttpCacheEntry(
        url: url ?? this.url,
        body: body ?? this.body,
        fetchedAt: fetchedAt ?? this.fetchedAt,
      );
  HttpCacheEntry copyWithCompanion(HttpCacheEntriesCompanion data) {
    return HttpCacheEntry(
      url: data.url.present ? data.url.value : this.url,
      body: data.body.present ? data.body.value : this.body,
      fetchedAt: data.fetchedAt.present ? data.fetchedAt.value : this.fetchedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('HttpCacheEntry(')
          ..write('url: $url, ')
          ..write('body: $body, ')
          ..write('fetchedAt: $fetchedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(url, body, fetchedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is HttpCacheEntry &&
          other.url == this.url &&
          other.body == this.body &&
          other.fetchedAt == this.fetchedAt);
}

class HttpCacheEntriesCompanion extends UpdateCompanion<HttpCacheEntry> {
  final Value<String> url;
  final Value<String> body;
  final Value<DateTime> fetchedAt;
  final Value<int> rowid;
  const HttpCacheEntriesCompanion({
    this.url = const Value.absent(),
    this.body = const Value.absent(),
    this.fetchedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  HttpCacheEntriesCompanion.insert({
    required String url,
    required String body,
    required DateTime fetchedAt,
    this.rowid = const Value.absent(),
  }) : url = Value(url),
       body = Value(body),
       fetchedAt = Value(fetchedAt);
  static Insertable<HttpCacheEntry> custom({
    Expression<String>? url,
    Expression<String>? body,
    Expression<DateTime>? fetchedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (url != null) 'url': url,
      if (body != null) 'body': body,
      if (fetchedAt != null) 'fetched_at': fetchedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  HttpCacheEntriesCompanion copyWith({
    Value<String>? url,
    Value<String>? body,
    Value<DateTime>? fetchedAt,
    Value<int>? rowid,
  }) {
    return HttpCacheEntriesCompanion(
      url: url ?? this.url,
      body: body ?? this.body,
      fetchedAt: fetchedAt ?? this.fetchedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (url.present) {
      map['url'] = Variable<String>(url.value);
    }
    if (body.present) {
      map['body'] = Variable<String>(body.value);
    }
    if (fetchedAt.present) {
      map['fetched_at'] = Variable<DateTime>(fetchedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('HttpCacheEntriesCompanion(')
          ..write('url: $url, ')
          ..write('body: $body, ')
          ..write('fetchedAt: $fetchedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ReadLaterEntriesTable extends ReadLaterEntries
    with TableInfo<$ReadLaterEntriesTable, ReadLaterEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ReadLaterEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _topicIdMeta = const VerificationMeta(
    'topicId',
  );
  @override
  late final GeneratedColumn<int> topicId = GeneratedColumn<int>(
    'topic_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _authorNameMeta = const VerificationMeta(
    'authorName',
  );
  @override
  late final GeneratedColumn<String> authorName = GeneratedColumn<String>(
    'author_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _authorAvatarMeta = const VerificationMeta(
    'authorAvatar',
  );
  @override
  late final GeneratedColumn<String> authorAvatar = GeneratedColumn<String>(
    'author_avatar',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _nodeNameMeta = const VerificationMeta(
    'nodeName',
  );
  @override
  late final GeneratedColumn<String> nodeName = GeneratedColumn<String>(
    'node_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nodeKeyMeta = const VerificationMeta(
    'nodeKey',
  );
  @override
  late final GeneratedColumn<String> nodeKey = GeneratedColumn<String>(
    'node_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _timeLabelMeta = const VerificationMeta(
    'timeLabel',
  );
  @override
  late final GeneratedColumn<String> timeLabel = GeneratedColumn<String>(
    'time_label',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _replyCountMeta = const VerificationMeta(
    'replyCount',
  );
  @override
  late final GeneratedColumn<int> replyCount = GeneratedColumn<int>(
    'reply_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _savedAtMeta = const VerificationMeta(
    'savedAt',
  );
  @override
  late final GeneratedColumn<DateTime> savedAt = GeneratedColumn<DateTime>(
    'saved_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    topicId,
    title,
    authorName,
    authorAvatar,
    nodeName,
    nodeKey,
    timeLabel,
    replyCount,
    savedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'read_later_entries';
  @override
  VerificationContext validateIntegrity(
    Insertable<ReadLaterEntry> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('topic_id')) {
      context.handle(
        _topicIdMeta,
        topicId.isAcceptableOrUnknown(data['topic_id']!, _topicIdMeta),
      );
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('author_name')) {
      context.handle(
        _authorNameMeta,
        authorName.isAcceptableOrUnknown(data['author_name']!, _authorNameMeta),
      );
    } else if (isInserting) {
      context.missing(_authorNameMeta);
    }
    if (data.containsKey('author_avatar')) {
      context.handle(
        _authorAvatarMeta,
        authorAvatar.isAcceptableOrUnknown(
          data['author_avatar']!,
          _authorAvatarMeta,
        ),
      );
    }
    if (data.containsKey('node_name')) {
      context.handle(
        _nodeNameMeta,
        nodeName.isAcceptableOrUnknown(data['node_name']!, _nodeNameMeta),
      );
    } else if (isInserting) {
      context.missing(_nodeNameMeta);
    }
    if (data.containsKey('node_key')) {
      context.handle(
        _nodeKeyMeta,
        nodeKey.isAcceptableOrUnknown(data['node_key']!, _nodeKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_nodeKeyMeta);
    }
    if (data.containsKey('time_label')) {
      context.handle(
        _timeLabelMeta,
        timeLabel.isAcceptableOrUnknown(data['time_label']!, _timeLabelMeta),
      );
    } else if (isInserting) {
      context.missing(_timeLabelMeta);
    }
    if (data.containsKey('reply_count')) {
      context.handle(
        _replyCountMeta,
        replyCount.isAcceptableOrUnknown(data['reply_count']!, _replyCountMeta),
      );
    } else if (isInserting) {
      context.missing(_replyCountMeta);
    }
    if (data.containsKey('saved_at')) {
      context.handle(
        _savedAtMeta,
        savedAt.isAcceptableOrUnknown(data['saved_at']!, _savedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_savedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {topicId};
  @override
  ReadLaterEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ReadLaterEntry(
      topicId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}topic_id'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      authorName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}author_name'],
      )!,
      authorAvatar: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}author_avatar'],
      ),
      nodeName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}node_name'],
      )!,
      nodeKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}node_key'],
      )!,
      timeLabel: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}time_label'],
      )!,
      replyCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}reply_count'],
      )!,
      savedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}saved_at'],
      )!,
    );
  }

  @override
  $ReadLaterEntriesTable createAlias(String alias) {
    return $ReadLaterEntriesTable(attachedDatabase, alias);
  }
}

class ReadLaterEntry extends DataClass implements Insertable<ReadLaterEntry> {
  final int topicId;
  final String title;
  final String authorName;
  final String? authorAvatar;
  final String nodeName;
  final String nodeKey;
  final String timeLabel;
  final int replyCount;
  final DateTime savedAt;
  const ReadLaterEntry({
    required this.topicId,
    required this.title,
    required this.authorName,
    this.authorAvatar,
    required this.nodeName,
    required this.nodeKey,
    required this.timeLabel,
    required this.replyCount,
    required this.savedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['topic_id'] = Variable<int>(topicId);
    map['title'] = Variable<String>(title);
    map['author_name'] = Variable<String>(authorName);
    if (!nullToAbsent || authorAvatar != null) {
      map['author_avatar'] = Variable<String>(authorAvatar);
    }
    map['node_name'] = Variable<String>(nodeName);
    map['node_key'] = Variable<String>(nodeKey);
    map['time_label'] = Variable<String>(timeLabel);
    map['reply_count'] = Variable<int>(replyCount);
    map['saved_at'] = Variable<DateTime>(savedAt);
    return map;
  }

  ReadLaterEntriesCompanion toCompanion(bool nullToAbsent) {
    return ReadLaterEntriesCompanion(
      topicId: Value(topicId),
      title: Value(title),
      authorName: Value(authorName),
      authorAvatar: authorAvatar == null && nullToAbsent
          ? const Value.absent()
          : Value(authorAvatar),
      nodeName: Value(nodeName),
      nodeKey: Value(nodeKey),
      timeLabel: Value(timeLabel),
      replyCount: Value(replyCount),
      savedAt: Value(savedAt),
    );
  }

  factory ReadLaterEntry.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ReadLaterEntry(
      topicId: serializer.fromJson<int>(json['topicId']),
      title: serializer.fromJson<String>(json['title']),
      authorName: serializer.fromJson<String>(json['authorName']),
      authorAvatar: serializer.fromJson<String?>(json['authorAvatar']),
      nodeName: serializer.fromJson<String>(json['nodeName']),
      nodeKey: serializer.fromJson<String>(json['nodeKey']),
      timeLabel: serializer.fromJson<String>(json['timeLabel']),
      replyCount: serializer.fromJson<int>(json['replyCount']),
      savedAt: serializer.fromJson<DateTime>(json['savedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'topicId': serializer.toJson<int>(topicId),
      'title': serializer.toJson<String>(title),
      'authorName': serializer.toJson<String>(authorName),
      'authorAvatar': serializer.toJson<String?>(authorAvatar),
      'nodeName': serializer.toJson<String>(nodeName),
      'nodeKey': serializer.toJson<String>(nodeKey),
      'timeLabel': serializer.toJson<String>(timeLabel),
      'replyCount': serializer.toJson<int>(replyCount),
      'savedAt': serializer.toJson<DateTime>(savedAt),
    };
  }

  ReadLaterEntry copyWith({
    int? topicId,
    String? title,
    String? authorName,
    Value<String?> authorAvatar = const Value.absent(),
    String? nodeName,
    String? nodeKey,
    String? timeLabel,
    int? replyCount,
    DateTime? savedAt,
  }) => ReadLaterEntry(
    topicId: topicId ?? this.topicId,
    title: title ?? this.title,
    authorName: authorName ?? this.authorName,
    authorAvatar: authorAvatar.present ? authorAvatar.value : this.authorAvatar,
    nodeName: nodeName ?? this.nodeName,
    nodeKey: nodeKey ?? this.nodeKey,
    timeLabel: timeLabel ?? this.timeLabel,
    replyCount: replyCount ?? this.replyCount,
    savedAt: savedAt ?? this.savedAt,
  );
  ReadLaterEntry copyWithCompanion(ReadLaterEntriesCompanion data) {
    return ReadLaterEntry(
      topicId: data.topicId.present ? data.topicId.value : this.topicId,
      title: data.title.present ? data.title.value : this.title,
      authorName: data.authorName.present
          ? data.authorName.value
          : this.authorName,
      authorAvatar: data.authorAvatar.present
          ? data.authorAvatar.value
          : this.authorAvatar,
      nodeName: data.nodeName.present ? data.nodeName.value : this.nodeName,
      nodeKey: data.nodeKey.present ? data.nodeKey.value : this.nodeKey,
      timeLabel: data.timeLabel.present ? data.timeLabel.value : this.timeLabel,
      replyCount: data.replyCount.present
          ? data.replyCount.value
          : this.replyCount,
      savedAt: data.savedAt.present ? data.savedAt.value : this.savedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ReadLaterEntry(')
          ..write('topicId: $topicId, ')
          ..write('title: $title, ')
          ..write('authorName: $authorName, ')
          ..write('authorAvatar: $authorAvatar, ')
          ..write('nodeName: $nodeName, ')
          ..write('nodeKey: $nodeKey, ')
          ..write('timeLabel: $timeLabel, ')
          ..write('replyCount: $replyCount, ')
          ..write('savedAt: $savedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    topicId,
    title,
    authorName,
    authorAvatar,
    nodeName,
    nodeKey,
    timeLabel,
    replyCount,
    savedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ReadLaterEntry &&
          other.topicId == this.topicId &&
          other.title == this.title &&
          other.authorName == this.authorName &&
          other.authorAvatar == this.authorAvatar &&
          other.nodeName == this.nodeName &&
          other.nodeKey == this.nodeKey &&
          other.timeLabel == this.timeLabel &&
          other.replyCount == this.replyCount &&
          other.savedAt == this.savedAt);
}

class ReadLaterEntriesCompanion extends UpdateCompanion<ReadLaterEntry> {
  final Value<int> topicId;
  final Value<String> title;
  final Value<String> authorName;
  final Value<String?> authorAvatar;
  final Value<String> nodeName;
  final Value<String> nodeKey;
  final Value<String> timeLabel;
  final Value<int> replyCount;
  final Value<DateTime> savedAt;
  const ReadLaterEntriesCompanion({
    this.topicId = const Value.absent(),
    this.title = const Value.absent(),
    this.authorName = const Value.absent(),
    this.authorAvatar = const Value.absent(),
    this.nodeName = const Value.absent(),
    this.nodeKey = const Value.absent(),
    this.timeLabel = const Value.absent(),
    this.replyCount = const Value.absent(),
    this.savedAt = const Value.absent(),
  });
  ReadLaterEntriesCompanion.insert({
    this.topicId = const Value.absent(),
    required String title,
    required String authorName,
    this.authorAvatar = const Value.absent(),
    required String nodeName,
    required String nodeKey,
    required String timeLabel,
    required int replyCount,
    required DateTime savedAt,
  }) : title = Value(title),
       authorName = Value(authorName),
       nodeName = Value(nodeName),
       nodeKey = Value(nodeKey),
       timeLabel = Value(timeLabel),
       replyCount = Value(replyCount),
       savedAt = Value(savedAt);
  static Insertable<ReadLaterEntry> custom({
    Expression<int>? topicId,
    Expression<String>? title,
    Expression<String>? authorName,
    Expression<String>? authorAvatar,
    Expression<String>? nodeName,
    Expression<String>? nodeKey,
    Expression<String>? timeLabel,
    Expression<int>? replyCount,
    Expression<DateTime>? savedAt,
  }) {
    return RawValuesInsertable({
      if (topicId != null) 'topic_id': topicId,
      if (title != null) 'title': title,
      if (authorName != null) 'author_name': authorName,
      if (authorAvatar != null) 'author_avatar': authorAvatar,
      if (nodeName != null) 'node_name': nodeName,
      if (nodeKey != null) 'node_key': nodeKey,
      if (timeLabel != null) 'time_label': timeLabel,
      if (replyCount != null) 'reply_count': replyCount,
      if (savedAt != null) 'saved_at': savedAt,
    });
  }

  ReadLaterEntriesCompanion copyWith({
    Value<int>? topicId,
    Value<String>? title,
    Value<String>? authorName,
    Value<String?>? authorAvatar,
    Value<String>? nodeName,
    Value<String>? nodeKey,
    Value<String>? timeLabel,
    Value<int>? replyCount,
    Value<DateTime>? savedAt,
  }) {
    return ReadLaterEntriesCompanion(
      topicId: topicId ?? this.topicId,
      title: title ?? this.title,
      authorName: authorName ?? this.authorName,
      authorAvatar: authorAvatar ?? this.authorAvatar,
      nodeName: nodeName ?? this.nodeName,
      nodeKey: nodeKey ?? this.nodeKey,
      timeLabel: timeLabel ?? this.timeLabel,
      replyCount: replyCount ?? this.replyCount,
      savedAt: savedAt ?? this.savedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (topicId.present) {
      map['topic_id'] = Variable<int>(topicId.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (authorName.present) {
      map['author_name'] = Variable<String>(authorName.value);
    }
    if (authorAvatar.present) {
      map['author_avatar'] = Variable<String>(authorAvatar.value);
    }
    if (nodeName.present) {
      map['node_name'] = Variable<String>(nodeName.value);
    }
    if (nodeKey.present) {
      map['node_key'] = Variable<String>(nodeKey.value);
    }
    if (timeLabel.present) {
      map['time_label'] = Variable<String>(timeLabel.value);
    }
    if (replyCount.present) {
      map['reply_count'] = Variable<int>(replyCount.value);
    }
    if (savedAt.present) {
      map['saved_at'] = Variable<DateTime>(savedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ReadLaterEntriesCompanion(')
          ..write('topicId: $topicId, ')
          ..write('title: $title, ')
          ..write('authorName: $authorName, ')
          ..write('authorAvatar: $authorAvatar, ')
          ..write('nodeName: $nodeName, ')
          ..write('nodeKey: $nodeKey, ')
          ..write('timeLabel: $timeLabel, ')
          ..write('replyCount: $replyCount, ')
          ..write('savedAt: $savedAt')
          ..write(')'))
        .toString();
  }
}

class $HistoryEntriesTable extends HistoryEntries
    with TableInfo<$HistoryEntriesTable, HistoryEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $HistoryEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _topicIdMeta = const VerificationMeta(
    'topicId',
  );
  @override
  late final GeneratedColumn<int> topicId = GeneratedColumn<int>(
    'topic_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _authorNameMeta = const VerificationMeta(
    'authorName',
  );
  @override
  late final GeneratedColumn<String> authorName = GeneratedColumn<String>(
    'author_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _authorAvatarMeta = const VerificationMeta(
    'authorAvatar',
  );
  @override
  late final GeneratedColumn<String> authorAvatar = GeneratedColumn<String>(
    'author_avatar',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _nodeNameMeta = const VerificationMeta(
    'nodeName',
  );
  @override
  late final GeneratedColumn<String> nodeName = GeneratedColumn<String>(
    'node_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nodeKeyMeta = const VerificationMeta(
    'nodeKey',
  );
  @override
  late final GeneratedColumn<String> nodeKey = GeneratedColumn<String>(
    'node_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _timeLabelMeta = const VerificationMeta(
    'timeLabel',
  );
  @override
  late final GeneratedColumn<String> timeLabel = GeneratedColumn<String>(
    'time_label',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _viewedAtMeta = const VerificationMeta(
    'viewedAt',
  );
  @override
  late final GeneratedColumn<DateTime> viewedAt = GeneratedColumn<DateTime>(
    'viewed_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    topicId,
    title,
    authorName,
    authorAvatar,
    nodeName,
    nodeKey,
    timeLabel,
    viewedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'history_entries';
  @override
  VerificationContext validateIntegrity(
    Insertable<HistoryEntry> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('topic_id')) {
      context.handle(
        _topicIdMeta,
        topicId.isAcceptableOrUnknown(data['topic_id']!, _topicIdMeta),
      );
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('author_name')) {
      context.handle(
        _authorNameMeta,
        authorName.isAcceptableOrUnknown(data['author_name']!, _authorNameMeta),
      );
    } else if (isInserting) {
      context.missing(_authorNameMeta);
    }
    if (data.containsKey('author_avatar')) {
      context.handle(
        _authorAvatarMeta,
        authorAvatar.isAcceptableOrUnknown(
          data['author_avatar']!,
          _authorAvatarMeta,
        ),
      );
    }
    if (data.containsKey('node_name')) {
      context.handle(
        _nodeNameMeta,
        nodeName.isAcceptableOrUnknown(data['node_name']!, _nodeNameMeta),
      );
    } else if (isInserting) {
      context.missing(_nodeNameMeta);
    }
    if (data.containsKey('node_key')) {
      context.handle(
        _nodeKeyMeta,
        nodeKey.isAcceptableOrUnknown(data['node_key']!, _nodeKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_nodeKeyMeta);
    }
    if (data.containsKey('time_label')) {
      context.handle(
        _timeLabelMeta,
        timeLabel.isAcceptableOrUnknown(data['time_label']!, _timeLabelMeta),
      );
    } else if (isInserting) {
      context.missing(_timeLabelMeta);
    }
    if (data.containsKey('viewed_at')) {
      context.handle(
        _viewedAtMeta,
        viewedAt.isAcceptableOrUnknown(data['viewed_at']!, _viewedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_viewedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {topicId};
  @override
  HistoryEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return HistoryEntry(
      topicId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}topic_id'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      authorName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}author_name'],
      )!,
      authorAvatar: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}author_avatar'],
      ),
      nodeName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}node_name'],
      )!,
      nodeKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}node_key'],
      )!,
      timeLabel: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}time_label'],
      )!,
      viewedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}viewed_at'],
      )!,
    );
  }

  @override
  $HistoryEntriesTable createAlias(String alias) {
    return $HistoryEntriesTable(attachedDatabase, alias);
  }
}

class HistoryEntry extends DataClass implements Insertable<HistoryEntry> {
  final int topicId;
  final String title;
  final String authorName;
  final String? authorAvatar;
  final String nodeName;
  final String nodeKey;
  final String timeLabel;
  final DateTime viewedAt;
  const HistoryEntry({
    required this.topicId,
    required this.title,
    required this.authorName,
    this.authorAvatar,
    required this.nodeName,
    required this.nodeKey,
    required this.timeLabel,
    required this.viewedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['topic_id'] = Variable<int>(topicId);
    map['title'] = Variable<String>(title);
    map['author_name'] = Variable<String>(authorName);
    if (!nullToAbsent || authorAvatar != null) {
      map['author_avatar'] = Variable<String>(authorAvatar);
    }
    map['node_name'] = Variable<String>(nodeName);
    map['node_key'] = Variable<String>(nodeKey);
    map['time_label'] = Variable<String>(timeLabel);
    map['viewed_at'] = Variable<DateTime>(viewedAt);
    return map;
  }

  HistoryEntriesCompanion toCompanion(bool nullToAbsent) {
    return HistoryEntriesCompanion(
      topicId: Value(topicId),
      title: Value(title),
      authorName: Value(authorName),
      authorAvatar: authorAvatar == null && nullToAbsent
          ? const Value.absent()
          : Value(authorAvatar),
      nodeName: Value(nodeName),
      nodeKey: Value(nodeKey),
      timeLabel: Value(timeLabel),
      viewedAt: Value(viewedAt),
    );
  }

  factory HistoryEntry.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return HistoryEntry(
      topicId: serializer.fromJson<int>(json['topicId']),
      title: serializer.fromJson<String>(json['title']),
      authorName: serializer.fromJson<String>(json['authorName']),
      authorAvatar: serializer.fromJson<String?>(json['authorAvatar']),
      nodeName: serializer.fromJson<String>(json['nodeName']),
      nodeKey: serializer.fromJson<String>(json['nodeKey']),
      timeLabel: serializer.fromJson<String>(json['timeLabel']),
      viewedAt: serializer.fromJson<DateTime>(json['viewedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'topicId': serializer.toJson<int>(topicId),
      'title': serializer.toJson<String>(title),
      'authorName': serializer.toJson<String>(authorName),
      'authorAvatar': serializer.toJson<String?>(authorAvatar),
      'nodeName': serializer.toJson<String>(nodeName),
      'nodeKey': serializer.toJson<String>(nodeKey),
      'timeLabel': serializer.toJson<String>(timeLabel),
      'viewedAt': serializer.toJson<DateTime>(viewedAt),
    };
  }

  HistoryEntry copyWith({
    int? topicId,
    String? title,
    String? authorName,
    Value<String?> authorAvatar = const Value.absent(),
    String? nodeName,
    String? nodeKey,
    String? timeLabel,
    DateTime? viewedAt,
  }) => HistoryEntry(
    topicId: topicId ?? this.topicId,
    title: title ?? this.title,
    authorName: authorName ?? this.authorName,
    authorAvatar: authorAvatar.present ? authorAvatar.value : this.authorAvatar,
    nodeName: nodeName ?? this.nodeName,
    nodeKey: nodeKey ?? this.nodeKey,
    timeLabel: timeLabel ?? this.timeLabel,
    viewedAt: viewedAt ?? this.viewedAt,
  );
  HistoryEntry copyWithCompanion(HistoryEntriesCompanion data) {
    return HistoryEntry(
      topicId: data.topicId.present ? data.topicId.value : this.topicId,
      title: data.title.present ? data.title.value : this.title,
      authorName: data.authorName.present
          ? data.authorName.value
          : this.authorName,
      authorAvatar: data.authorAvatar.present
          ? data.authorAvatar.value
          : this.authorAvatar,
      nodeName: data.nodeName.present ? data.nodeName.value : this.nodeName,
      nodeKey: data.nodeKey.present ? data.nodeKey.value : this.nodeKey,
      timeLabel: data.timeLabel.present ? data.timeLabel.value : this.timeLabel,
      viewedAt: data.viewedAt.present ? data.viewedAt.value : this.viewedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('HistoryEntry(')
          ..write('topicId: $topicId, ')
          ..write('title: $title, ')
          ..write('authorName: $authorName, ')
          ..write('authorAvatar: $authorAvatar, ')
          ..write('nodeName: $nodeName, ')
          ..write('nodeKey: $nodeKey, ')
          ..write('timeLabel: $timeLabel, ')
          ..write('viewedAt: $viewedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    topicId,
    title,
    authorName,
    authorAvatar,
    nodeName,
    nodeKey,
    timeLabel,
    viewedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is HistoryEntry &&
          other.topicId == this.topicId &&
          other.title == this.title &&
          other.authorName == this.authorName &&
          other.authorAvatar == this.authorAvatar &&
          other.nodeName == this.nodeName &&
          other.nodeKey == this.nodeKey &&
          other.timeLabel == this.timeLabel &&
          other.viewedAt == this.viewedAt);
}

class HistoryEntriesCompanion extends UpdateCompanion<HistoryEntry> {
  final Value<int> topicId;
  final Value<String> title;
  final Value<String> authorName;
  final Value<String?> authorAvatar;
  final Value<String> nodeName;
  final Value<String> nodeKey;
  final Value<String> timeLabel;
  final Value<DateTime> viewedAt;
  const HistoryEntriesCompanion({
    this.topicId = const Value.absent(),
    this.title = const Value.absent(),
    this.authorName = const Value.absent(),
    this.authorAvatar = const Value.absent(),
    this.nodeName = const Value.absent(),
    this.nodeKey = const Value.absent(),
    this.timeLabel = const Value.absent(),
    this.viewedAt = const Value.absent(),
  });
  HistoryEntriesCompanion.insert({
    this.topicId = const Value.absent(),
    required String title,
    required String authorName,
    this.authorAvatar = const Value.absent(),
    required String nodeName,
    required String nodeKey,
    required String timeLabel,
    required DateTime viewedAt,
  }) : title = Value(title),
       authorName = Value(authorName),
       nodeName = Value(nodeName),
       nodeKey = Value(nodeKey),
       timeLabel = Value(timeLabel),
       viewedAt = Value(viewedAt);
  static Insertable<HistoryEntry> custom({
    Expression<int>? topicId,
    Expression<String>? title,
    Expression<String>? authorName,
    Expression<String>? authorAvatar,
    Expression<String>? nodeName,
    Expression<String>? nodeKey,
    Expression<String>? timeLabel,
    Expression<DateTime>? viewedAt,
  }) {
    return RawValuesInsertable({
      if (topicId != null) 'topic_id': topicId,
      if (title != null) 'title': title,
      if (authorName != null) 'author_name': authorName,
      if (authorAvatar != null) 'author_avatar': authorAvatar,
      if (nodeName != null) 'node_name': nodeName,
      if (nodeKey != null) 'node_key': nodeKey,
      if (timeLabel != null) 'time_label': timeLabel,
      if (viewedAt != null) 'viewed_at': viewedAt,
    });
  }

  HistoryEntriesCompanion copyWith({
    Value<int>? topicId,
    Value<String>? title,
    Value<String>? authorName,
    Value<String?>? authorAvatar,
    Value<String>? nodeName,
    Value<String>? nodeKey,
    Value<String>? timeLabel,
    Value<DateTime>? viewedAt,
  }) {
    return HistoryEntriesCompanion(
      topicId: topicId ?? this.topicId,
      title: title ?? this.title,
      authorName: authorName ?? this.authorName,
      authorAvatar: authorAvatar ?? this.authorAvatar,
      nodeName: nodeName ?? this.nodeName,
      nodeKey: nodeKey ?? this.nodeKey,
      timeLabel: timeLabel ?? this.timeLabel,
      viewedAt: viewedAt ?? this.viewedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (topicId.present) {
      map['topic_id'] = Variable<int>(topicId.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (authorName.present) {
      map['author_name'] = Variable<String>(authorName.value);
    }
    if (authorAvatar.present) {
      map['author_avatar'] = Variable<String>(authorAvatar.value);
    }
    if (nodeName.present) {
      map['node_name'] = Variable<String>(nodeName.value);
    }
    if (nodeKey.present) {
      map['node_key'] = Variable<String>(nodeKey.value);
    }
    if (timeLabel.present) {
      map['time_label'] = Variable<String>(timeLabel.value);
    }
    if (viewedAt.present) {
      map['viewed_at'] = Variable<DateTime>(viewedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('HistoryEntriesCompanion(')
          ..write('topicId: $topicId, ')
          ..write('title: $title, ')
          ..write('authorName: $authorName, ')
          ..write('authorAvatar: $authorAvatar, ')
          ..write('nodeName: $nodeName, ')
          ..write('nodeKey: $nodeKey, ')
          ..write('timeLabel: $timeLabel, ')
          ..write('viewedAt: $viewedAt')
          ..write(')'))
        .toString();
  }
}

abstract class _$CacheDatabase extends GeneratedDatabase {
  _$CacheDatabase(QueryExecutor e) : super(e);
  $CacheDatabaseManager get managers => $CacheDatabaseManager(this);
  late final $HttpCacheEntriesTable httpCacheEntries = $HttpCacheEntriesTable(
    this,
  );
  late final $ReadLaterEntriesTable readLaterEntries = $ReadLaterEntriesTable(
    this,
  );
  late final $HistoryEntriesTable historyEntries = $HistoryEntriesTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    httpCacheEntries,
    readLaterEntries,
    historyEntries,
  ];
}

typedef $$HttpCacheEntriesTableCreateCompanionBuilder =
    HttpCacheEntriesCompanion Function({
      required String url,
      required String body,
      required DateTime fetchedAt,
      Value<int> rowid,
    });
typedef $$HttpCacheEntriesTableUpdateCompanionBuilder =
    HttpCacheEntriesCompanion Function({
      Value<String> url,
      Value<String> body,
      Value<DateTime> fetchedAt,
      Value<int> rowid,
    });

class $$HttpCacheEntriesTableFilterComposer
    extends Composer<_$CacheDatabase, $HttpCacheEntriesTable> {
  $$HttpCacheEntriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get url => $composableBuilder(
    column: $table.url,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get body => $composableBuilder(
    column: $table.body,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get fetchedAt => $composableBuilder(
    column: $table.fetchedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$HttpCacheEntriesTableOrderingComposer
    extends Composer<_$CacheDatabase, $HttpCacheEntriesTable> {
  $$HttpCacheEntriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get url => $composableBuilder(
    column: $table.url,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get body => $composableBuilder(
    column: $table.body,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get fetchedAt => $composableBuilder(
    column: $table.fetchedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$HttpCacheEntriesTableAnnotationComposer
    extends Composer<_$CacheDatabase, $HttpCacheEntriesTable> {
  $$HttpCacheEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get url =>
      $composableBuilder(column: $table.url, builder: (column) => column);

  GeneratedColumn<String> get body =>
      $composableBuilder(column: $table.body, builder: (column) => column);

  GeneratedColumn<DateTime> get fetchedAt =>
      $composableBuilder(column: $table.fetchedAt, builder: (column) => column);
}

class $$HttpCacheEntriesTableTableManager
    extends
        RootTableManager<
          _$CacheDatabase,
          $HttpCacheEntriesTable,
          HttpCacheEntry,
          $$HttpCacheEntriesTableFilterComposer,
          $$HttpCacheEntriesTableOrderingComposer,
          $$HttpCacheEntriesTableAnnotationComposer,
          $$HttpCacheEntriesTableCreateCompanionBuilder,
          $$HttpCacheEntriesTableUpdateCompanionBuilder,
          (
            HttpCacheEntry,
            BaseReferences<
              _$CacheDatabase,
              $HttpCacheEntriesTable,
              HttpCacheEntry
            >,
          ),
          HttpCacheEntry,
          PrefetchHooks Function()
        > {
  $$HttpCacheEntriesTableTableManager(
    _$CacheDatabase db,
    $HttpCacheEntriesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$HttpCacheEntriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$HttpCacheEntriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$HttpCacheEntriesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> url = const Value.absent(),
                Value<String> body = const Value.absent(),
                Value<DateTime> fetchedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => HttpCacheEntriesCompanion(
                url: url,
                body: body,
                fetchedAt: fetchedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String url,
                required String body,
                required DateTime fetchedAt,
                Value<int> rowid = const Value.absent(),
              }) => HttpCacheEntriesCompanion.insert(
                url: url,
                body: body,
                fetchedAt: fetchedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$HttpCacheEntriesTable, HttpCacheEntry>(table),
                  BaseReferences<
                    _$CacheDatabase,
                    $HttpCacheEntriesTable,
                    HttpCacheEntry
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$HttpCacheEntriesTableProcessedTableManager =
    ProcessedTableManager<
      _$CacheDatabase,
      $HttpCacheEntriesTable,
      HttpCacheEntry,
      $$HttpCacheEntriesTableFilterComposer,
      $$HttpCacheEntriesTableOrderingComposer,
      $$HttpCacheEntriesTableAnnotationComposer,
      $$HttpCacheEntriesTableCreateCompanionBuilder,
      $$HttpCacheEntriesTableUpdateCompanionBuilder,
      (
        HttpCacheEntry,
        BaseReferences<_$CacheDatabase, $HttpCacheEntriesTable, HttpCacheEntry>,
      ),
      HttpCacheEntry,
      PrefetchHooks Function()
    >;
typedef $$ReadLaterEntriesTableCreateCompanionBuilder =
    ReadLaterEntriesCompanion Function({
      Value<int> topicId,
      required String title,
      required String authorName,
      Value<String?> authorAvatar,
      required String nodeName,
      required String nodeKey,
      required String timeLabel,
      required int replyCount,
      required DateTime savedAt,
    });
typedef $$ReadLaterEntriesTableUpdateCompanionBuilder =
    ReadLaterEntriesCompanion Function({
      Value<int> topicId,
      Value<String> title,
      Value<String> authorName,
      Value<String?> authorAvatar,
      Value<String> nodeName,
      Value<String> nodeKey,
      Value<String> timeLabel,
      Value<int> replyCount,
      Value<DateTime> savedAt,
    });

class $$ReadLaterEntriesTableFilterComposer
    extends Composer<_$CacheDatabase, $ReadLaterEntriesTable> {
  $$ReadLaterEntriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get topicId => $composableBuilder(
    column: $table.topicId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get authorName => $composableBuilder(
    column: $table.authorName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get authorAvatar => $composableBuilder(
    column: $table.authorAvatar,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get nodeName => $composableBuilder(
    column: $table.nodeName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get nodeKey => $composableBuilder(
    column: $table.nodeKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get timeLabel => $composableBuilder(
    column: $table.timeLabel,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get replyCount => $composableBuilder(
    column: $table.replyCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get savedAt => $composableBuilder(
    column: $table.savedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ReadLaterEntriesTableOrderingComposer
    extends Composer<_$CacheDatabase, $ReadLaterEntriesTable> {
  $$ReadLaterEntriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get topicId => $composableBuilder(
    column: $table.topicId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get authorName => $composableBuilder(
    column: $table.authorName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get authorAvatar => $composableBuilder(
    column: $table.authorAvatar,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get nodeName => $composableBuilder(
    column: $table.nodeName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get nodeKey => $composableBuilder(
    column: $table.nodeKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get timeLabel => $composableBuilder(
    column: $table.timeLabel,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get replyCount => $composableBuilder(
    column: $table.replyCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get savedAt => $composableBuilder(
    column: $table.savedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ReadLaterEntriesTableAnnotationComposer
    extends Composer<_$CacheDatabase, $ReadLaterEntriesTable> {
  $$ReadLaterEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get topicId =>
      $composableBuilder(column: $table.topicId, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get authorName => $composableBuilder(
    column: $table.authorName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get authorAvatar => $composableBuilder(
    column: $table.authorAvatar,
    builder: (column) => column,
  );

  GeneratedColumn<String> get nodeName =>
      $composableBuilder(column: $table.nodeName, builder: (column) => column);

  GeneratedColumn<String> get nodeKey =>
      $composableBuilder(column: $table.nodeKey, builder: (column) => column);

  GeneratedColumn<String> get timeLabel =>
      $composableBuilder(column: $table.timeLabel, builder: (column) => column);

  GeneratedColumn<int> get replyCount => $composableBuilder(
    column: $table.replyCount,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get savedAt =>
      $composableBuilder(column: $table.savedAt, builder: (column) => column);
}

class $$ReadLaterEntriesTableTableManager
    extends
        RootTableManager<
          _$CacheDatabase,
          $ReadLaterEntriesTable,
          ReadLaterEntry,
          $$ReadLaterEntriesTableFilterComposer,
          $$ReadLaterEntriesTableOrderingComposer,
          $$ReadLaterEntriesTableAnnotationComposer,
          $$ReadLaterEntriesTableCreateCompanionBuilder,
          $$ReadLaterEntriesTableUpdateCompanionBuilder,
          (
            ReadLaterEntry,
            BaseReferences<
              _$CacheDatabase,
              $ReadLaterEntriesTable,
              ReadLaterEntry
            >,
          ),
          ReadLaterEntry,
          PrefetchHooks Function()
        > {
  $$ReadLaterEntriesTableTableManager(
    _$CacheDatabase db,
    $ReadLaterEntriesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ReadLaterEntriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ReadLaterEntriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ReadLaterEntriesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> topicId = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String> authorName = const Value.absent(),
                Value<String?> authorAvatar = const Value.absent(),
                Value<String> nodeName = const Value.absent(),
                Value<String> nodeKey = const Value.absent(),
                Value<String> timeLabel = const Value.absent(),
                Value<int> replyCount = const Value.absent(),
                Value<DateTime> savedAt = const Value.absent(),
              }) => ReadLaterEntriesCompanion(
                topicId: topicId,
                title: title,
                authorName: authorName,
                authorAvatar: authorAvatar,
                nodeName: nodeName,
                nodeKey: nodeKey,
                timeLabel: timeLabel,
                replyCount: replyCount,
                savedAt: savedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> topicId = const Value.absent(),
                required String title,
                required String authorName,
                Value<String?> authorAvatar = const Value.absent(),
                required String nodeName,
                required String nodeKey,
                required String timeLabel,
                required int replyCount,
                required DateTime savedAt,
              }) => ReadLaterEntriesCompanion.insert(
                topicId: topicId,
                title: title,
                authorName: authorName,
                authorAvatar: authorAvatar,
                nodeName: nodeName,
                nodeKey: nodeKey,
                timeLabel: timeLabel,
                replyCount: replyCount,
                savedAt: savedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ReadLaterEntriesTable, ReadLaterEntry>(table),
                  BaseReferences<
                    _$CacheDatabase,
                    $ReadLaterEntriesTable,
                    ReadLaterEntry
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ReadLaterEntriesTableProcessedTableManager =
    ProcessedTableManager<
      _$CacheDatabase,
      $ReadLaterEntriesTable,
      ReadLaterEntry,
      $$ReadLaterEntriesTableFilterComposer,
      $$ReadLaterEntriesTableOrderingComposer,
      $$ReadLaterEntriesTableAnnotationComposer,
      $$ReadLaterEntriesTableCreateCompanionBuilder,
      $$ReadLaterEntriesTableUpdateCompanionBuilder,
      (
        ReadLaterEntry,
        BaseReferences<_$CacheDatabase, $ReadLaterEntriesTable, ReadLaterEntry>,
      ),
      ReadLaterEntry,
      PrefetchHooks Function()
    >;
typedef $$HistoryEntriesTableCreateCompanionBuilder =
    HistoryEntriesCompanion Function({
      Value<int> topicId,
      required String title,
      required String authorName,
      Value<String?> authorAvatar,
      required String nodeName,
      required String nodeKey,
      required String timeLabel,
      required DateTime viewedAt,
    });
typedef $$HistoryEntriesTableUpdateCompanionBuilder =
    HistoryEntriesCompanion Function({
      Value<int> topicId,
      Value<String> title,
      Value<String> authorName,
      Value<String?> authorAvatar,
      Value<String> nodeName,
      Value<String> nodeKey,
      Value<String> timeLabel,
      Value<DateTime> viewedAt,
    });

class $$HistoryEntriesTableFilterComposer
    extends Composer<_$CacheDatabase, $HistoryEntriesTable> {
  $$HistoryEntriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get topicId => $composableBuilder(
    column: $table.topicId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get authorName => $composableBuilder(
    column: $table.authorName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get authorAvatar => $composableBuilder(
    column: $table.authorAvatar,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get nodeName => $composableBuilder(
    column: $table.nodeName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get nodeKey => $composableBuilder(
    column: $table.nodeKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get timeLabel => $composableBuilder(
    column: $table.timeLabel,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get viewedAt => $composableBuilder(
    column: $table.viewedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$HistoryEntriesTableOrderingComposer
    extends Composer<_$CacheDatabase, $HistoryEntriesTable> {
  $$HistoryEntriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get topicId => $composableBuilder(
    column: $table.topicId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get authorName => $composableBuilder(
    column: $table.authorName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get authorAvatar => $composableBuilder(
    column: $table.authorAvatar,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get nodeName => $composableBuilder(
    column: $table.nodeName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get nodeKey => $composableBuilder(
    column: $table.nodeKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get timeLabel => $composableBuilder(
    column: $table.timeLabel,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get viewedAt => $composableBuilder(
    column: $table.viewedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$HistoryEntriesTableAnnotationComposer
    extends Composer<_$CacheDatabase, $HistoryEntriesTable> {
  $$HistoryEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get topicId =>
      $composableBuilder(column: $table.topicId, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get authorName => $composableBuilder(
    column: $table.authorName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get authorAvatar => $composableBuilder(
    column: $table.authorAvatar,
    builder: (column) => column,
  );

  GeneratedColumn<String> get nodeName =>
      $composableBuilder(column: $table.nodeName, builder: (column) => column);

  GeneratedColumn<String> get nodeKey =>
      $composableBuilder(column: $table.nodeKey, builder: (column) => column);

  GeneratedColumn<String> get timeLabel =>
      $composableBuilder(column: $table.timeLabel, builder: (column) => column);

  GeneratedColumn<DateTime> get viewedAt =>
      $composableBuilder(column: $table.viewedAt, builder: (column) => column);
}

class $$HistoryEntriesTableTableManager
    extends
        RootTableManager<
          _$CacheDatabase,
          $HistoryEntriesTable,
          HistoryEntry,
          $$HistoryEntriesTableFilterComposer,
          $$HistoryEntriesTableOrderingComposer,
          $$HistoryEntriesTableAnnotationComposer,
          $$HistoryEntriesTableCreateCompanionBuilder,
          $$HistoryEntriesTableUpdateCompanionBuilder,
          (
            HistoryEntry,
            BaseReferences<_$CacheDatabase, $HistoryEntriesTable, HistoryEntry>,
          ),
          HistoryEntry,
          PrefetchHooks Function()
        > {
  $$HistoryEntriesTableTableManager(
    _$CacheDatabase db,
    $HistoryEntriesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$HistoryEntriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$HistoryEntriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$HistoryEntriesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> topicId = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String> authorName = const Value.absent(),
                Value<String?> authorAvatar = const Value.absent(),
                Value<String> nodeName = const Value.absent(),
                Value<String> nodeKey = const Value.absent(),
                Value<String> timeLabel = const Value.absent(),
                Value<DateTime> viewedAt = const Value.absent(),
              }) => HistoryEntriesCompanion(
                topicId: topicId,
                title: title,
                authorName: authorName,
                authorAvatar: authorAvatar,
                nodeName: nodeName,
                nodeKey: nodeKey,
                timeLabel: timeLabel,
                viewedAt: viewedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> topicId = const Value.absent(),
                required String title,
                required String authorName,
                Value<String?> authorAvatar = const Value.absent(),
                required String nodeName,
                required String nodeKey,
                required String timeLabel,
                required DateTime viewedAt,
              }) => HistoryEntriesCompanion.insert(
                topicId: topicId,
                title: title,
                authorName: authorName,
                authorAvatar: authorAvatar,
                nodeName: nodeName,
                nodeKey: nodeKey,
                timeLabel: timeLabel,
                viewedAt: viewedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$HistoryEntriesTable, HistoryEntry>(table),
                  BaseReferences<
                    _$CacheDatabase,
                    $HistoryEntriesTable,
                    HistoryEntry
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$HistoryEntriesTableProcessedTableManager =
    ProcessedTableManager<
      _$CacheDatabase,
      $HistoryEntriesTable,
      HistoryEntry,
      $$HistoryEntriesTableFilterComposer,
      $$HistoryEntriesTableOrderingComposer,
      $$HistoryEntriesTableAnnotationComposer,
      $$HistoryEntriesTableCreateCompanionBuilder,
      $$HistoryEntriesTableUpdateCompanionBuilder,
      (
        HistoryEntry,
        BaseReferences<_$CacheDatabase, $HistoryEntriesTable, HistoryEntry>,
      ),
      HistoryEntry,
      PrefetchHooks Function()
    >;

class $CacheDatabaseManager {
  final _$CacheDatabase _db;
  $CacheDatabaseManager(this._db);
  $$HttpCacheEntriesTableTableManager get httpCacheEntries =>
      $$HttpCacheEntriesTableTableManager(_db, _db.httpCacheEntries);
  $$ReadLaterEntriesTableTableManager get readLaterEntries =>
      $$ReadLaterEntriesTableTableManager(_db, _db.readLaterEntries);
  $$HistoryEntriesTableTableManager get historyEntries =>
      $$HistoryEntriesTableTableManager(_db, _db.historyEntries);
}
