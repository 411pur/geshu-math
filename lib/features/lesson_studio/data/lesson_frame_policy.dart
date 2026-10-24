/// 内嵌讲解播放器必须显式放行的浏览器能力。
///
/// 讲解 HTML 是通过 data: URL 直接塞进 iframe 的，这种子帧的 origin 是 opaque（"null"），
/// 而 fullscreen 的默认 allowlist 只放行同源帧——不放行时子帧里的 `requestFullscreen()`
/// 会被权限策略直接拒掉（实测 Edge 下子帧 `document.fullscreenEnabled` 为 false），
/// 黑板上的「全屏黑板」就变成点了没反应。
///
/// 真正的行为验证在 `lesson_engine/tests/browser.test.ts`（真实 Edge + data: URL 帧）；
/// 这里单独放一个不依赖任何 web-only 库的文件，便于离线单测守住这个约定。
const String kLessonFrameAllow = 'fullscreen';
