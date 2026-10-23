/// 纯 Dart 工具（无 dart:html,可在 VM 中单测）。
library;

/// 剥离 `data:image/png;base64,` 前缀,返回纯 base64（供 Image.memory 解码）。
String dataImageBase64(String dataUri) =>
    dataUri.contains(',') ? dataUri.split(',').last : dataUri;
