import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data_store.dart';

/// 已初始化的 DataStore 单例。
///
/// 这里刻意用**同步** Provider，实例由 main() 在 runApp 之前创建并 override 进来。
///
/// 为什么不用 FutureProvider：错题指导 / 知识图谱 / 考试分析的数据源都是同步
/// Provider，只有拿到 store 才能构造。早期实现是
/// `ref.watch(dataStoreProvider).asData?.value` + 为 null 就 throw ——
/// 首次读取若发生在异步初始化完成之前，这个 Provider 会进入 error 状态，
/// 之后任何一次读取都会抛 "Tried to use a provider that is in error state"。
/// 典型症状：错题讲解生成完了，却在保存那一步整页报错。
final dataStoreProvider = Provider<DataStore>((ref) {
  throw StateError(
    'dataStoreProvider 尚未注入：请在 main() 中先 await store.initialize()，'
    '再通过 ProviderScope(overrides: ...) 覆盖本 provider。',
  );
});
