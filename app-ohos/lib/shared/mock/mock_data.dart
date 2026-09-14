import 'package:flutter/material.dart';

import '../models/models.dart';

/// Design-fidelity fixtures.
///
/// Every string here is copied verbatim from `designs/*.png` so the rendered
/// screens can be diffed against the mockups one-to-one. This file is the only
/// place allowed to contain sample content; when the Dio + parser layer lands,
/// `shared/mock/` is deleted and the same models are produced by repositories.
abstract final class MockData {
  // ------------------------------------------------------------------ users

  /// Demo avatars. `i.pravatar.cc` is blocked on some networks, so fixtures use
  /// a host that resolves reliably; production will use `cdn.v2ex.com` URLs
  /// straight from the API.
  static V2User user(String name, String portrait) => V2User(
    username: name,
    avatarUrl: 'https://randomuser.me/api/portraits/$portrait.jpg',
  );

  static final kernel = user('kernel', 'men/32');
  static final seanChen = user('SeanChen', 'men/45');
  static final winterzz = user('winterzz', 'men/12');
  static final eight = user('Eight', 'men/78');
  static final charlieYe = user('CharlieYe', 'men/22');
  static final imshuai = user('imshuai', 'women/65');
  static final lemon = user('Lemon', 'women/33');
  static final me = V2User(
    username: 'rwecho',
    avatarUrl: 'https://randomuser.me/api/portraits/men/8.jpg',
    id: 94728,
    tagline: '更好的开发者社区',
  );

  // ------------------------------------------------------------------ nodes

  static const programmer = V2Node(
    key: 'programmer',
    name: '程序员',
    icon: Icons.code,
    topicCount: 12400,
    tags: ['编程', '技术栈', '职业发展'],
  );

  static const create = V2Node(
    key: 'create',
    name: '分享创造',
    icon: Icons.lightbulb_outline,
    topicCount: 8700,
    tags: ['独立项目', '产品', '创意'],
  );

  static const ai = V2Node(
    key: 'ai',
    name: 'AI',
    icon: Icons.auto_awesome,
    topicCount: 15200,
    tags: ['大语言模型', 'AI 应用', '提示工程'],
    iconStyle: NodeIconStyle.soft,
  );

  static const apple = V2Node(
    key: 'apple',
    name: 'Apple',
    icon: Icons.apple,
    topicCount: 6800,
    tags: ['iOS', 'macOS', 'Apple 生态'],
  );

  static const qna = V2Node(
    key: 'qna',
    name: '问与答',
    icon: Icons.help_outline,
    topicCount: 9100,
    tags: ['技术问答', '产品使用', '生活经验'],
  );

  static const idev = V2Node(
    key: 'idev',
    name: '独立开发',
    icon: Icons.rocket_launch_outlined,
    topicCount: 5300,
    tags: ['独立开发', '产品', '增长'],
  );

  static const dotnet = V2Node(
    key: 'dotnet',
    name: '.NET',
    icon: Icons.terminal,
    topicCount: 4200,
    tags: ['C#', 'MAUI', 'ASP.NET'],
  );

  static const remote = V2Node(
    key: 'remote',
    name: '远程工作',
    icon: Icons.laptop_mac,
    topicCount: 3100,
    tags: ['远程', '效率'],
  );

  static const devtools = V2Node(
    key: 'devtools',
    name: '开发工具',
    icon: Icons.build_outlined,
    topicCount: 7600,
    tags: ['IDE', '效率工具'],
  );

  static const security = V2Node(
    key: 'security',
    name: '安全',
    icon: Icons.shield_outlined,
    topicCount: 2400,
    tags: ['安全'],
  );

  /// `designs/04-nodes-explore.png` → 热门节点.
  static const hotNodes = <V2Node>[programmer, create, ai, apple, qna, idev];

  /// `designs/04-nodes-explore.png` → 最近访问.
  static const recentNodeNames = <String>['程序员', '分享创造', '问与答', 'AI', 'Apple'];

  // ------------------------------------------------------------------- feed

  static List<V2Topic> feed() => <V2Topic>[
    V2Topic(
      id: 1,
      node: ai,
      title: 'Claude Code 真正改变了我的开发方式',
      excerpt:
          '从一开始的怀疑到现在每天都在用，Claude Code 不只是一个 AI 工具，更像是一个真正理解上下文的搭档。分享一些这段...',
      author: kernel,
      createdAtLabel: '3 小时前',
      replyCount: 42,
    ),
    V2Topic(
      id: 2,
      node: programmer,
      title: 'Codex 上手一周后的真实体验',
      excerpt: 'OpenAI 的 Codex 在实际项目中的表现比我预期的要好，尤其是在理解复杂代码结构和生成测试用例方面。也聊聊它...',
      author: seanChen,
      createdAtLabel: '5 小时前',
      replyCount: 28,
    ),
    V2Topic(
      id: 3,
      node: dotnet,
      title: '用 MAUI 开发跨平台应用的一些经验分享',
      excerpt: '趁着最近的项目实践，整理了一些 MAUI 开发过程中的坑和技巧，分享给有需要的朋友。整体体验比预期要好，已经能满...',
      author: winterzz,
      createdAtLabel: '8 小时前',
      replyCount: 16,
    ),
    V2Topic(
      id: 4,
      node: idev,
      title: '从 0 到 1：一个 Indie Hacker 的一年回顾',
      excerpt: '独立开发一年，产品从无人问津到有了一些稳定的用户。这篇文章记录了我的心理历程、踩过的坑，以及一些经验总结...',
      author: eight,
      createdAtLabel: '12 小时前',
      replyCount: 53,
    ),
    V2Topic(
      id: 5,
      node: remote,
      title: '远程开发已经三年了，聊聊我的工具链和心态变化',
      excerpt: '从最初的不适应，到现在觉得这是最适合我的工作方式。分享一下我常用的工具、协作方式，以及如何保持专注和效率。',
      author: charlieYe,
      createdAtLabel: '1 天前',
      replyCount: 37,
    ),
    V2Topic(
      id: 6,
      node: create,
      title: '推荐几个我最近在用的 AI 工具',
      excerpt: '工作和生活效率都提升了不少，简单介绍一下这几款工具的使用场景和优缺点，希望对大家有帮助。',
      author: imshuai,
      createdAtLabel: '1 天前',
      replyCount: 24,
    ),
  ];

  // ---------------------------------------------------------- topic detail

  static V2Topic topicDetail() => V2Topic(
    id: 1001,
    node: programmer,
    title: 'Claude Code 现在到底值不值得长期使用？',
    author: kernel,
    createdAtLabel: '3 小时前',
    viewCountLabel: '2.3k',
    replyCount: 54,
    excerpt: null,
    body: const <String>[
      '这段时间我几乎每天都在用 Claude Code 进行日常开发，从项目搭建、功能实现到代码重构，整体体验比我预期的要好很多。',
      '它在理解项目上下文方面确实很强，尤其是处理复杂的代码结构时，能够保持比较连贯的思路，不会轻易“跑偏”。相比之下，之前用过的一些工具在多文件场景中经常需要重复解释背景，效率会低不少。',
      '目前我主要把 Claude Code 当作日常开发的协作伙伴，用来快速实现功能、编写测试、梳理思路和优化代码。它并不能完全替代开发者，但在很多场景下已经能显著提升效率。',
      '想听听大家的看法：你们觉得 Claude Code 现在值得长期使用吗？有哪些实际使用中的优点或不足？',
    ],
    linkPreview: const V2LinkPreview(
      title: 'Claude Code 官方介绍',
      description: '了解 Claude Code 的功能、使用方法和最新更新内容。',
      url: 'https://claude.ai/code',
    ),
  );

  static List<V2Reply> replies() => <V2Reply>[
    V2Reply(
      floor: 1,
      author: seanChen,
      createdAtLabel: '2 小时前',
      likes: 56,
      content: '我觉得非常值得。Claude Code 在理解复杂项目方面的表现确实出色，尤其是多文件修改时，基本不需要我反复解释上下文。已经成了我日常开发中不可或缺的工具。',
    ),
    V2Reply(
      floor: 2,
      author: winterzz,
      createdAtLabel: '1 小时前',
      likes: 28,
      content: '我觉得要看看具体场景。简单的 CRUD 可能感觉不明显，但在复杂业务逻辑、重构和代码审查方面，Claude Code 的价值非常大。唯一的不足是有时候会过于保守，需要我们明确一些约束条件。',
    ),
    V2Reply(
      floor: 3,
      author: eight,
      createdAtLabel: '1 小时前',
      likes: 17,
      content: '我已经用了三个月，整体是正向体验。它让我的开发流程更顺畅，尤其是在写测试和文档方面节省了很多时间。建议配合项目规范一起使用，效果会更好。',
    ),
    V2Reply(
      floor: 4,
      author: imshuai,
      createdAtLabel: '58 分钟前',
      likes: 9,
      content: '我觉得目前还不能完全替代人工，特别是在一些领域知识很强的问题上，还是需要人来把关。',
    ),
  ];

  // ---------------------------------------------------------- composer (03)

  static V2Topic composerTopic() => V2Topic(
    id: 1001,
    node: ai,
    title: 'Claude Code 现在到底值不值得长期使用？',
    author: kernel,
    createdAtLabel: '3 小时前',
    replyCount: 42,
    excerpt: '最近一直在用 Claude Code 处理日常开发任务，体验感觉很不错，但也看到不少朋友在讨论它的局限性。想听听大家...',
  );

  static const String composerDraft = '''
我个人觉得 Claude Code 是非常值得长期使用的，尤其是对于需要大量阅读、理解和生成代码的开发者来说，确实能显著提升效率。

在我的日常工作流里，Claude Code 主要承担了这几个角色：代码阅读与理解、快速原型实现、问题排查以及文档撰写。它在处理复杂代码结构时的上下文理解能力非常出色，很多时候不需要我反复解释背景，就能给出比较准确且有深度的建议。

当然，它也不是完美的。比如在一些非常细节的工程配置、特定框架的冷门问题上，偶尔还是会出现不够准确的情况。但整体来看，它已经成为我日常开发中不可或缺的工具之一。

未来如果能在多文件编辑、项目级记忆和更强的可定制化方面继续提升，我相信它会变得更强大。''';

  // --------------------------------------------------------- notifications

  static List<V2NotificationGroup> notificationGroups() =>
      <V2NotificationGroup>[
        V2NotificationGroup(
          title: '今天',
          items: <V2Notification>[
            V2Notification(
              id: 'n1',
              kind: NotificationKind.reply,
              actor: kernel,
              timeLabel: '3 小时前',
              quote: '我也遇到过类似的问题，后来通过调整提示词格式解决了，分享一下我的配置...',
              sourceTitle: 'Claude Code 真正改变了我的开发方式',
              isUnread: true,
            ),
            V2Notification(
              id: 'n2',
              kind: NotificationKind.mention,
              actor: seanChen,
              timeLabel: '5 小时前',
              quote: '@imshuai 这个方案很有参考价值，感谢分享！',
              sourceTitle: 'Codex 上手一周后的真实体验',
              isUnread: true,
            ),
            V2Notification(
              id: 'n3',
              kind: NotificationKind.like,
              actor: eight,
              timeLabel: '8 小时前',
              quote: '写得很详细，受益匪浅 👍',
              sourceTitle: '用 MAUI 开发跨平台应用的一些经验分享',
              isUnread: true,
            ),
          ],
        ),
        V2NotificationGroup(
          title: '昨天',
          items: <V2Notification>[
            V2Notification(
              id: 'n4',
              kind: NotificationKind.favorite,
              actor: charlieYe,
              timeLabel: '昨天 21:20',
              quote: '很棒的总结，已收藏，方便后续再看...',
              sourceTitle: '从 0 到 1：一个 Indie Hacker 的一年回顾',
              isUnread: true,
            ),
            V2Notification(
              id: 'n5',
              kind: NotificationKind.reply,
              actor: imshuai,
              timeLabel: '昨天 16:34',
              quote: '确实是这样，我最近也在尝试这种方法...',
              sourceTitle: '远程开发已经三年了，聊聊我的工具链和心态变化',
              isUnread: true,
            ),
            V2Notification(
              id: 'n6',
              kind: NotificationKind.mention,
              actor: winterzz,
              timeLabel: '昨天 11:03',
              quote: '@imshuai 你提到的这款工具我也在用，体验很棒！',
              sourceTitle: '推荐几个我最近在用的 AI 工具',
              isUnread: true,
            ),
            V2Notification(
              id: 'n7',
              kind: NotificationKind.like,
              actor: lemon,
              timeLabel: '昨天 09:17',
              quote: '内容很实用，感谢分享！',
              sourceTitle: '远程开发已经三年了，聊聊我的工具链和心态变化',
              isUnread: true,
            ),
          ],
        ),
      ];

  // --------------------------------------------------------------- search

  static const List<String> recentSearches = <String>[
    'Claude Code',
    'MAUI',
    'Indie Hacker',
    '远程开发',
  ];

  static List<V2Topic> searchResults() => <V2Topic>[
    V2Topic(
      id: 2001,
      node: ai,
      title: 'OpenAI Codex：从研究预览到真实开发助手',
      excerpt:
          'OpenAI 的 Codex 正在把自然语言转化为可运行的代码，从简单的脚本生成到复杂的工程任务。本文整理了它的能力边界、使用...',
      author: kernel,
      createdAtLabel: '3 小时前',
      replyCount: 42,
    ),
    V2Topic(
      id: 2002,
      node: devtools,
      title: '在真实项目中使用 Codex 的一些体验',
      excerpt:
          '这篇文章记录了我在实际项目中使用 OpenAI Codex 的过程，包括环境配置、提示词技巧、代码审查的配合方式，以及与...',
      author: seanChen,
      createdAtLabel: '5 小时前',
      replyCount: 28,
    ),
    V2Topic(
      id: 2003,
      node: dotnet,
      title: '用 Codex 加速 MAUI 应用开发的实践',
      excerpt:
          '结合最近的项目实践，我整理了一些利用 Codex 辅助 MAUI 开发的技巧，包括界面生成、跨平台问题处理和调试思路。整体体验...',
      author: winterzz,
      createdAtLabel: '8 小时前',
      replyCount: 16,
    ),
    V2Topic(
      id: 2004,
      node: idev,
      title: 'Codex 如何改变独立开发者的工作流',
      excerpt: '从 0 到 1：一个 Indie Hacker 使用 Codex 一年的经验总结。这篇文章记录了我在产品开发、内容创作、代码维护等方面的实...',
      author: eight,
      createdAtLabel: '12 小时前',
      replyCount: 53,
    ),
    V2Topic(
      id: 2005,
      node: ai,
      title: 'Claude Code vs Codex：两种 AI 编程工具的对比',
      excerpt:
          '从产品定位、模型能力、使用体验到生态，全面对比了 Claude Code 和 Codex 的异同，帮助你选择更适合自己的工具。',
      author: imshuai,
      createdAtLabel: '1 天前',
      replyCount: 24,
    ),
  ];

  // -------------------------------------------------------------- profile

  static const V2Profile profile = V2Profile(
    user: V2User(
      username: 'rwecho',
      avatarUrl: 'https://randomuser.me/api/portraits/men/8.jpg',
      id: 94728,
    ),
    topicCount: 50,
    replyCount: 336,
    favoriteCount: 28,
  );

  // ------------------------------------------------------------- settings

  static const String cacheSizeLabel = '48 MB';
  static const String appVersion = '2.0.0';
}
